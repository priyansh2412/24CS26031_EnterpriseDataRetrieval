import shutil
import uuid
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db, init_db
from app.models import Chunk, Document, DocumentVersion, Source
from app.schemas import IngestionResponse
from app.services.ingestion_service import (
    ingest_document_file,
    ingest_from_drive_link,
)
from app.services.qdrant_service import ensure_collection, get_qdrant_client

router = APIRouter(
    prefix="/api/ingestion",
    tags=["Ingestion"]
)


class IngestExistingRequest(BaseModel):
    filename: str


class IngestDriveRequest(BaseModel):
    drive_link: str
    tenant_id: str | None = None
    project_id: str | None = None


@router.post(
    "/upload",
    response_model=IngestionResponse
)
async def upload_document(
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    if not file.filename:
        return IngestionResponse(
            status="error",
            message="Filename is required."
        )

    incoming_dir = settings.incoming_path
    incoming_dir.mkdir(parents=True, exist_ok=True)

    safe_name = f"{uuid.uuid4().hex[:8]}_{file.filename}"
    file_path = incoming_dir / safe_name

    with open(file_path, "wb") as output:
        shutil.copyfileobj(file.file, output)

    try:
        result = ingest_document_file(file_path, db, source_type="upload")
        return IngestionResponse(**result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/ingest-file",
    response_model=IngestionResponse
)
def ingest_existing_file(
    request: IngestExistingRequest,
    db: Session = Depends(get_db)
):
    incoming_dir = settings.incoming_path
    file_path = incoming_dir / request.filename
    if not file_path.exists():
        file_path = settings.data_path / request.filename

    if not file_path.exists() or not file_path.is_file():
        raise HTTPException(status_code=404, detail=f"File '{request.filename}' not found.")

    try:
        result = ingest_document_file(file_path, db, source_type="local")
        return IngestionResponse(**result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/drive",
    response_model=IngestionResponse
)
def ingest_google_drive(
    request: IngestDriveRequest,
    db: Session = Depends(get_db)
):
    """
    Ingests a file or folder from a Google Drive URL:
    - Extracts drive_file_id.
    - Registers source in PostgreSQL.
    - Fetches metadata via Google Drive API.
    - Downloads/reads document with SHA-256 deduplication.
    - Chunks with Docling.
    - Embeds with Gemini and inserts vector + payload into Qdrant.
    """
    if not request.drive_link or not request.drive_link.strip():
        raise HTTPException(status_code=400, detail="Google Drive link is required.")

    try:
        result = ingest_from_drive_link(
            drive_link_or_id=request.drive_link.strip(),
            db=db,
            tenant_id=request.tenant_id,
            project_id=request.project_id
        )
        return IngestionResponse(**result)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Google Drive ingestion failed: {str(e)}")


@router.post("/reset")
def reset_all_data(db: Session = Depends(get_db)):
    """Wipes all documents and chunks from PostgreSQL and resets Qdrant collection."""
    try:
        db.query(Chunk).delete()
        db.query(DocumentVersion).delete()
        db.query(Document).delete()
        db.query(Source).delete()
        db.commit()

        client = get_qdrant_client()
        try:
            client.delete_collection(settings.qdrant_collection)
        except Exception:
            pass

        ensure_collection()
        return {
            "status": "success",
            "message": "All document chunks, relational records, and vector points have been completely reset."
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/files")
def list_incoming_files():
    """List all available document files in data/incoming."""
    incoming_dir = settings.incoming_path
    if not incoming_dir.exists():
        return {"files": []}

    files = []
    for f in incoming_dir.glob("*"):
        if f.is_file():
            files.append({
                "name": f.name,
                "size_kb": round(f.stat().st_size / 1024, 2)
            })
    return {"files": files}


@router.get("/documents")
def list_ingested_documents(db: Session = Depends(get_db)):
    """List all documents and chunk counts stored in PostgreSQL."""
    try:
        docs = db.query(Document).order_by(Document.created_at.desc()).all()
        return {
            "documents": [
                {
                    "id": str(d.id),
                    "name": d.name,
                    "created_at": str(d.created_at),
                    "chunks": d.chunk_count,
                    "status": d.status,
                    "source": d.source,
                    "web_view_link": d.web_view_link,
                    "acl_version": d.acl_version
                }
                for d in docs
            ]
        }
    except Exception as e:
        return {"documents": [], "error": str(e)}