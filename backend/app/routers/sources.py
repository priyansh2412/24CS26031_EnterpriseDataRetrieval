from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import current_user, require_permission
from app.models import Source, User
from app.schemas import SourceCreate, SourceOut
from app.services.access import log_access
from app.services.google_drive_service import extract_drive_file_id
from app.services.ingestion_service import ingest_from_drive_link

router = APIRouter(prefix="/api/sources", tags=["sources"])


@router.get("", response_model=list[SourceOut])
def list_sources(
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:view"))
):
    return db.query(Source).order_by(Source.created_at.desc()).all()


@router.post("", response_model=SourceOut)
def register_source(
    payload: SourceCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage"))
):
    """
    Registers a Google Drive file/folder source in PostgreSQL and triggers ingestion.
    """
    file_id, kind = extract_drive_file_id(payload.uri)

    source = db.query(Source).filter(Source.uri == payload.uri).first()
    if not source:
        source = Source(
            name=payload.name,
            source_type=payload.source_type,
            uri=payload.uri,
            drive_file_id=file_id,
            folder_id=file_id if kind == "folder" else None,
            status="active"
        )
        db.add(source)
        db.commit()
        db.refresh(source)

    # Ingest document from drive link
    if payload.source_type == "google_drive" or "drive.google.com" in payload.uri or "docs.google.com" in payload.uri:
        try:
            ingest_from_drive_link(
                drive_link_or_id=payload.uri,
                db=db,
                tenant_id=payload.tenant_id,
                project_id=payload.project_id
            )
        except Exception as e:
            print(f"Ingestion warning for source {source.id}: {e}")

    log_access(db, user, "register_source", "source", str(source.id), payload.uri)
    db.commit()
    return source


@router.post("/{source_id}/sync")
def sync_source(
    source_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage"))
):
    source = db.get(Source, source_id)
    if not source:
        raise HTTPException(404, "Source not found")

    res = ingest_from_drive_link(source.uri, db)
    log_access(db, user, "sync_source", "source", str(source_id))
    db.commit()
    return {"status": "success", "result": res}

