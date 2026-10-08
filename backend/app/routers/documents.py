from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import current_user, require_permission
from app.models import Document, User
from app.schemas import DocumentAccessUpdate, DocumentOut
from app.services.access import log_access
from app.services.acl_service import sync_document_acl_entries, verify_document_access
from app.services.docling_service import parse_and_chunk_document
from app.services.ingestion_service import (
    ingest_directory_files,
    ingest_document_file,
)
from app.services.llm import summarize_document
from app.services.qdrant_service import delete_document_chunks

router = APIRouter(prefix="/api/documents", tags=["documents"])


@router.get("", response_model=list[DocumentOut])
def list_documents(
    search: str | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:view")),
):
    query = db.query(Document)
    if search:
        query = query.filter(Document.name.ilike(f"%{search}%"))

    docs = query.order_by(Document.created_at.desc()).all()
    accessible_docs = [doc for doc in docs if verify_document_access(db, user, doc.id)]

    log_access(db, user, "view", "document_library", detail=f"{len(accessible_docs)} documents visible")
    db.commit()

    return accessible_docs


@router.post("/ingest/local", response_model=list[DocumentOut])
def ingest_local(
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage")),
):
    results = ingest_directory_files(settings.data_path, db)
    log_access(db, user, "ingest", "document_library", detail=f"{len(results)} local files processed")
    db.commit()

    # Return refreshed list of documents
    return db.query(Document).order_by(Document.created_at.desc()).all()


@router.post("/{document_id}/reingest", response_model=DocumentOut)
def reingest(
    document_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage")),
):
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document:
        raise HTTPException(404, "Document not found")

    file_path = document.source_uri
    if not file_path or not Path(file_path).exists():
        # Look in data or incoming folder
        matched = list(settings.data_path.glob(f"*{document.name}*")) or list(settings.incoming_path.glob(f"*{document.name}*"))
        if matched:
            file_path = str(matched[0])
        else:
            raise HTTPException(404, f"Local source file for '{document.name}' not found.")

    res = ingest_document_file(file_path, db, source_type=document.source)
    log_access(db, user, "reingest", "document", str(document_id))
    db.commit()

    db.refresh(document)
    return document


@router.post("/{document_id}/summary", response_model=DocumentOut)
def summarize(
    document_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:view")),
):
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document or not verify_document_access(db, user, document.id):
        raise HTTPException(404, "Document not found")

    chunks = parse_and_chunk_document(document.source_uri) if document.source_uri and Path(document.source_uri).exists() else []
    full_text = "\n\n".join(c["text"] for c in chunks) if chunks else document.name

    document.summary = summarize_document(full_text)
    log_access(db, user, "summarize", "document", str(document_id))
    db.commit()
    db.refresh(document)
    return document


@router.delete("/{document_id}", status_code=204)
def remove(
    document_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage")),
):
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document:
        raise HTTPException(404, "Document not found")

    delete_document_chunks(document.id)
    db.delete(document)
    log_access(db, user, "delete", "document", str(document_id))
    db.commit()


@router.put("/{document_id}/access", response_model=DocumentOut)
def update_access(
    document_id: str,
    payload: DocumentAccessUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:access")),
):
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document:
        raise HTTPException(404, "Document not found")

    # Update access roles JSON
    role_strings = [r.value for r in payload.roles]
    document.access_roles = "[" + ", ".join(f'"{r}"' for r in role_strings) + "]"

    # Sync principal keys and update Qdrant payload via ACL Outbox
    pkeys = [f"r:{r}" for r in role_strings] + [
        f"t:{document.tenant_id or settings.default_tenant_id}",
        "r:admin",
    ]
    sync_document_acl_entries(db, document.id, pkeys, origin="manual")

    log_access(db, user, "update_access", "document", str(document_id), document.access_roles)
    db.commit()
    db.refresh(document)
    return document
