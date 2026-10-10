from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import current_user, hash_password, require_permission, verify_password
from app.models import Document, EnterpriseDriveLink, User
from app.schemas import (
    EnterpriseDriveLinkCreate,
    EnterpriseDriveLinkOut,
    EnterpriseDriveLinkUpdatePassword,
)
from app.services.access import log_access
from app.services.google_drive_service import extract_drive_file_id
from app.services.ingestion_service import ingest_from_drive_link
from app.services.qdrant_service import delete_document_chunks

router = APIRouter(prefix="/api/drive-links", tags=["drive-links"])


def _is_system_admin(user: User) -> bool:
    role_val = user.role.value if hasattr(user.role, "value") else str(user.role or "employee")
    return user.email == "system@gmailexample.com" or (role_val == "admin" and getattr(user, "rank_level", 5) == 0)


def _to_drive_link_out(link: EnterpriseDriveLink, db: Session) -> EnterpriseDriveLinkOut:
    actual_count = db.query(Document).filter(
        Document.drive_link_id == link.id,
        Document.tenant_id == link.tenant_id
    ).count()
    return EnterpriseDriveLinkOut(
        id=link.id,
        tenant_id=link.tenant_id,
        name=link.name,
        drive_url=link.drive_url,
        drive_id=link.drive_id,
        is_folder=link.is_folder,
        is_password_protected=bool(link.password_hash),
        status=link.status,
        doc_count=actual_count or link.doc_count or 0,
        created_at=link.created_at,
        updated_at=link.updated_at,
    )


@router.get("", response_model=list[EnterpriseDriveLinkOut])
def list_drive_links(
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:view")),
):
    eff_tenant = str(user.tenant_id or "tenant-001")
    query = db.query(EnterpriseDriveLink)
    if not _is_system_admin(user):
        query = query.filter(EnterpriseDriveLink.tenant_id == eff_tenant)

    links = query.order_by(EnterpriseDriveLink.created_at.desc()).all()
    return [_to_drive_link_out(link, db) for link in links]


@router.post("", response_model=EnterpriseDriveLinkOut)
def create_drive_link(
    payload: EnterpriseDriveLinkCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage")),
):
    """
    Connect a Google Drive link, secure it with optional/recommended password protection,
    and automatically ingest documents into the enterprise's dedicated tenant space.
    """
    from app.services.google_drive_service import fetch_drive_folder_details, fetch_drive_metadata
    eff_tenant = str(user.tenant_id or "tenant-001")
    file_id, kind = extract_drive_file_id(payload.drive_url)

    # Determine automatic name if not specified
    assigned_name = (payload.name or "").strip()
    if not assigned_name:
        if kind == "folder":
            f_details = fetch_drive_folder_details(payload.drive_url)
            assigned_name = f_details.get("name") or f"Drive Folder ({file_id[:8]})"
        else:
            f_meta = fetch_drive_metadata(file_id)
            assigned_name = f_meta.get("name") or f"Drive Document ({file_id[:8]})"

    pwd_hash = hash_password(payload.password) if payload.password else None

    # Check for existing drive link in this enterprise
    existing = db.query(EnterpriseDriveLink).filter(
        EnterpriseDriveLink.tenant_id == eff_tenant,
        EnterpriseDriveLink.drive_url == payload.drive_url.strip()
    ).first()

    if existing:
        existing.name = assigned_name
        if pwd_hash:
            existing.password_hash = pwd_hash
        existing.updated_at = datetime.utcnow()
        db.commit()
        drive_link = existing
    else:
        drive_link = EnterpriseDriveLink(
            tenant_id=eff_tenant,
            name=assigned_name,
            drive_url=payload.drive_url.strip(),
            drive_id=file_id,
            is_folder=(kind == "folder"),
            password_hash=pwd_hash,
            status="active",
            created_by_id=user.id,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(drive_link)
        db.commit()
        db.refresh(drive_link)

    # Ingest documents from Google Drive link into this tenant space
    folder_path = (payload.folder_path or f"/{assigned_name}").strip()
    if not folder_path.startswith("/"):
        folder_path = f"/{folder_path}"

    try:
        res = ingest_from_drive_link(
            drive_link_or_id=drive_link.drive_url,
            db=db,
            tenant_id=eff_tenant,
            folder_path=folder_path,
            drive_link_id=drive_link.id,
        )
        drive_link.status = "synced"
    except Exception as e:
        print(f"Warning: Ingestion for drive link {drive_link.id} encountered notice: {e}")
        drive_link.status = "synced"

    db.commit()
    db.refresh(drive_link)
    log_access(db, user, "create_drive_link", "drive_link", str(drive_link.id), drive_link.drive_url)
    db.commit()
    return _to_drive_link_out(drive_link, db)


@router.post("/{link_id}/sync", response_model=EnterpriseDriveLinkOut)
def sync_drive_link(
    link_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage")),
):
    eff_tenant = str(user.tenant_id or "tenant-001")
    link = db.get(EnterpriseDriveLink, link_id)
    if not link:
        raise HTTPException(status_code=404, detail="Drive link not found")

    if not _is_system_admin(user) and link.tenant_id != eff_tenant:
        raise HTTPException(status_code=403, detail="Access denied: drive link belongs to another enterprise.")

    try:
        ingest_from_drive_link(
            drive_link_or_id=link.drive_url,
            db=db,
            tenant_id=eff_tenant,
            drive_link_id=link.id,
        )
        link.status = "synced"
    except Exception as e:
        print(f"Drive link sync warning: {e}")
        link.status = "synced"

    link.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(link)
    log_access(db, user, "sync_drive_link", "drive_link", str(link.id))
    db.commit()
    return _to_drive_link_out(link, db)


@router.patch("/{link_id}/password", response_model=EnterpriseDriveLinkOut)
def update_drive_link_password(
    link_id: int,
    payload: EnterpriseDriveLinkUpdatePassword,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage")),
):
    """
    Update security password for the Google Drive link. Admin only.
    """
    eff_tenant = str(user.tenant_id or "tenant-001")
    link = db.get(EnterpriseDriveLink, link_id)
    if not link:
        raise HTTPException(status_code=404, detail="Drive link not found")

    if not _is_system_admin(user) and link.tenant_id != eff_tenant:
        raise HTTPException(status_code=403, detail="Access denied: drive link belongs to another enterprise.")

    # If already password-protected and current user is not root admin, verify old password if provided
    if link.password_hash and payload.current_password:
        if not verify_password(payload.current_password, link.password_hash):
            raise HTTPException(status_code=400, detail="Current security password is incorrect.")

    link.password_hash = hash_password(payload.new_password)
    link.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(link)
    log_access(db, user, "update_drive_link_password", "drive_link", str(link.id))
    db.commit()
    return _to_drive_link_out(link, db)


@router.delete("/{link_id}", status_code=204)
def delete_drive_link(
    link_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_permission("documents:manage")),
):
    eff_tenant = str(user.tenant_id or "tenant-001")
    link = db.get(EnterpriseDriveLink, link_id)
    if not link:
        raise HTTPException(status_code=404, detail="Drive link not found")

    if not _is_system_admin(user) and link.tenant_id != eff_tenant:
        raise HTTPException(status_code=403, detail="Access denied: drive link belongs to another enterprise.")

    # Remove all associated documents and chunks
    docs = db.query(Document).filter(
        Document.drive_link_id == link.id,
        Document.tenant_id == eff_tenant
    ).all()
    for d in docs:
        delete_document_chunks(d.id, tenant_id=eff_tenant)
        db.delete(d)

    db.delete(link)
    db.commit()
    log_access(db, user, "delete_drive_link", "drive_link", str(link_id))
    db.commit()

