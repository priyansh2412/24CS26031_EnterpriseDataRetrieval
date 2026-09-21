from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.config import settings
from app.core.database import get_db
from app.core.security import current_user, require_permission
from app.models import Document, User
from app.schemas import DocumentAccessUpdate, DocumentOut
from app.services.access import document_is_available_to, log_access
from app.services.ingestion import ingest_directory, ingest_file
from app.services.llm import summarize_document
from app.services.parsers import extract_text
from app.services.vector_store import delete_document

router = APIRouter(prefix="/api/documents", tags=["documents"])

@router.get("", response_model=list[DocumentOut])
def list_documents(search: str | None = None, db: Session = Depends(get_db), user: User = Depends(require_permission("documents:view"))):
    query = db.query(Document)
    if search: query = query.filter(Document.name.ilike(f"%{search}%"))
    documents = [document for document in query.order_by(Document.created_at.desc()).all() if document_is_available_to(user, document)]
    log_access(db, user, "view", "document_library", detail=f"{len(documents)} documents visible")
    db.commit()
    return documents

@router.post("/ingest/local", response_model=list[DocumentOut])
def ingest_local(db: Session = Depends(get_db), user: User = Depends(require_permission("documents:manage"))):
    documents = ingest_directory(settings.data_path, db)
    log_access(db, user, "ingest", "document_library", detail=f"{len(documents)} local documents")
    db.commit()
    return documents

@router.post("/{document_id}/reingest", response_model=DocumentOut)
def reingest(document_id: int, db: Session = Depends(get_db), user: User = Depends(require_permission("documents:manage"))):
    document = db.get(Document, document_id)
    if not document: raise HTTPException(404, "Document not found")
    result = ingest_file(Path(document.source_uri), db, document.source)
    log_access(db, user, "reingest", "document", str(document_id)); db.commit()
    return result

@router.post("/{document_id}/summary", response_model=DocumentOut)
def summarize(document_id: int, db: Session = Depends(get_db), user: User = Depends(require_permission("documents:view"))):
    document = db.get(Document, document_id)
    if not document or not document_is_available_to(user, document): raise HTTPException(404, "Document not found")
    document.summary = summarize_document(extract_text(Path(document.source_uri)))
    log_access(db, user, "summarize", "document", str(document_id)); db.commit(); db.refresh(document)
    return document

@router.delete("/{document_id}", status_code=204)
def remove(document_id: int, db: Session = Depends(get_db), user: User = Depends(require_permission("documents:manage"))):
    document = db.get(Document, document_id)
    if not document: raise HTTPException(404, "Document not found")
    delete_document(document.id); db.delete(document); log_access(db, user, "delete", "document", str(document_id)); db.commit()


@router.put("/{document_id}/access", response_model=DocumentOut)
def update_access(document_id: int, payload: DocumentAccessUpdate, db: Session = Depends(get_db), user: User = Depends(require_permission("documents:access"))):
    document = db.get(Document, document_id)
    if not document: raise HTTPException(404, "Document not found")
    document.access_roles = "[" + ", ".join(f'\"{role.value}\"' for role in payload.roles) + "]"
    log_access(db, user, "update_access", "document", str(document_id), document.access_roles)
    db.commit(); db.refresh(document)
    return document
