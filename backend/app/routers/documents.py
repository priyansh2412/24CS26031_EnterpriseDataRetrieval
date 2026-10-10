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


def _is_system_admin(user: User) -> bool:
    role_val = user.role.value if hasattr(user.role, "value") else str(user.role or "employee")
    return user.email == "system@gmailexample.com" or (role_val == "admin" and getattr(user, "rank_level", 5) == 0)


@router.get("", response_model=list[DocumentOut])
def list_documents(
    search: str | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:view")),
):
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    query = db.query(Document)

    # Scoped multi-tenant isolation (unless system super admin)
    if not _is_system_admin(user):
        query = query.filter(Document.tenant_id == eff_tenant)

    # Exclude temporary user/team uploads from general knowledge library
    query = query.filter(Document.source.notin_(["temp_user", "temp_team"]))

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
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    results = ingest_directory_files(settings.data_path, db, tenant_id=eff_tenant)
    log_access(db, user, "ingest", "document_library", detail=f"{len(results)} local files processed for tenant {eff_tenant}")
    db.commit()

    # Return refreshed list of documents for this tenant
    return db.query(Document).filter(Document.tenant_id == eff_tenant).order_by(Document.created_at.desc()).all()


@router.post("/{document_id}/reingest", response_model=DocumentOut)
def reingest(
    document_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage")),
):
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    query = db.query(Document).filter(Document.id == document_id)
    if not _is_system_admin(user):
        query = query.filter(Document.tenant_id == eff_tenant)

    document = query.first()
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

    res = ingest_document_file(file_path, db, tenant_id=document.tenant_id, source_type=document.source)
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
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    query = db.query(Document).filter(Document.id == document_id)
    if not _is_system_admin(user):
        query = query.filter(Document.tenant_id == eff_tenant)

    document = query.first()
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
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    query = db.query(Document).filter(Document.id == document_id)
    if not _is_system_admin(user):
        query = query.filter(Document.tenant_id == eff_tenant)

    document = query.first()
    if not document:
        raise HTTPException(404, "Document not found")

    delete_document_chunks(document.id, tenant_id=document.tenant_id)
    db.delete(document)
    log_access(db, user, "delete", "document", str(document_id))
    db.commit()


@router.get("/folders")
def list_folders(
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:view")),
):
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    query = db.query(Document.folder_path).filter(Document.tenant_id == eff_tenant).distinct()
    paths = [p[0] or "/" for p in query.all()]
    if "/" not in paths:
        paths.insert(0, "/")
    return sorted(list(set(paths)))


@router.put("/{document_id}/access", response_model=DocumentOut)
def update_access(
    document_id: str,
    payload: DocumentAccessUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:access")),
):
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    query = db.query(Document).filter(Document.id == document_id)
    if not _is_system_admin(user):
        query = query.filter(Document.tenant_id == eff_tenant)

    document = query.first()
    if not document:
        raise HTTPException(404, "Document not found")

    import json
    role_strings = [str(r).strip().lower() for r in payload.roles]
    denied_strings = [str(d).strip().lower() for d in payload.denied_users]

    document.access_roles = json.dumps(role_strings)
    document.denied_users = json.dumps(denied_strings)

    allowed_pkeys = [f"r:{r}" for r in role_strings] + [
        f"t:{document.tenant_id or eff_tenant}",
        "r:admin",
    ]
    denied_pkeys = [f"u:{du}" for du in denied_strings]

    sync_document_acl_entries(
        db=db,
        document_id=document.id,
        principal_keys=allowed_pkeys,
        origin="manual",
        denied_principal_keys=denied_pkeys
    )

    if payload.apply_to_folder and document.folder_path:
        siblings = db.query(Document).filter(
            Document.tenant_id == document.tenant_id,
            Document.folder_path == document.folder_path,
            Document.id != document.id
        ).all()
        for sib in siblings:
            sib.access_roles = json.dumps(role_strings)
            sib.denied_users = json.dumps(denied_strings)
            sync_document_acl_entries(
                db=db,
                document_id=sib.id,
                principal_keys=allowed_pkeys,
                origin="manual",
                denied_principal_keys=denied_pkeys
            )

    log_access(db, user, "update_access", "document", str(document_id), f"roles: {role_strings}, denied: {denied_strings}")
    db.commit()
    db.refresh(document)
    return document
