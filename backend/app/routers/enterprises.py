import re
import secrets
import string
import uuid
from datetime import datetime
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user, hash_password
from app.models import AuditLog, EnterpriseAdmin, LogSeverity, Tenant, User
from app.schemas import EnterpriseCreate, EnterpriseOut, EnterpriseStatusUpdate
from app.services.qdrant_service import ensure_collection

router = APIRouter(prefix="/api/enterprises", tags=["enterprises"])


def _to_uuid(val: Any) -> uuid.UUID | None:
    if not val:
        return None
    if isinstance(val, uuid.UUID):
        return val
    try:
        return uuid.UUID(str(val))
    except Exception:
        return None


def _generate_temp_password(length: int = 12) -> str:
    """Generates a secure, human-friendly temporary password."""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    chars = [
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.ascii_lowercase),
        secrets.choice(string.digits),
        secrets.choice("!@#$%^&*")
    ]
    chars += [secrets.choice(alphabet) for _ in range(length - 4)]
    secrets.SystemRandom().shuffle(chars)
    return "".join(chars)


@router.get("", response_model=list[EnterpriseOut])
def list_enterprises(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    List all connected enterprises with admin credentials and status.
    Accessible to system administrators.
    """
    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
    if curr_role != "admin" and current_user.rank_level > 2:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to System Administrators and Executives."
        )

    enterprises = db.query(EnterpriseAdmin).order_by(EnterpriseAdmin.created_at.desc()).all()
    return enterprises


@router.post("", response_model=EnterpriseOut)
def create_enterprise(
    payload: EnterpriseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Add a new Connected Enterprise:
    1. Generates a temporary password if none provided.
    2. Provisions a distinct tenant record in PostgreSQL.
    3. Provisions a dedicated Qdrant collection / vector space for the enterprise.
    4. Creates or updates an Admin user with role='admin' & rank_level=1 tied to the enterprise's tenant_id.
    5. Saves credentials in the enterprise_admins table.
    """
    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
    if curr_role != "admin" and current_user.rank_level > 2:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to System Administrators."
        )

    clean_email = payload.admin_email.strip().lower()
    temp_pwd = payload.temp_password.strip() if payload.temp_password and payload.temp_password.strip() else _generate_temp_password()

    # 1. Provision Tenant in PostgreSQL
    ent_name = payload.enterprise_name.strip()
    slug_base = re.sub(r"[^a-zA-Z0-9]+", "-", ent_name.lower()).strip("-")
    if not slug_base:
        slug_base = "enterprise"

    existing_tenant = db.query(Tenant).filter(Tenant.name == ent_name).first()
    if not existing_tenant:
        tenant_uuid = uuid.uuid4()
        unique_slug = f"{slug_base}-{tenant_uuid.hex[:6]}"
        tenant_record = Tenant(
            id=tenant_uuid,
            slug=unique_slug,
            name=ent_name,
            status="active"
        )
        db.add(tenant_record)
        db.flush()
        eff_tenant_id = str(tenant_record.id)
    else:
        eff_tenant_id = str(existing_tenant.id)

    # 2. Provision dedicated Qdrant collection space for this enterprise
    ensure_collection(eff_tenant_id)

    # 3. Ensure admin user exists in users table with role admin, rank level 1, and scoped tenant_id
    user = db.query(User).filter(User.email == clean_email).first()
    if not user:
        user = User(
            email=clean_email,
            password_hash=hash_password(temp_pwd),
            role="admin",
            role_key="admin",
            rank_level=1,
            tenant_id=eff_tenant_id,
            is_active=True,
            created_by_id=current_user.id,
            created_at=datetime.utcnow()
        )
        db.add(user)
        db.flush()
    else:
        user.password_hash = hash_password(temp_pwd)
        user.role = "admin"
        user.role_key = "admin"
        user.rank_level = 1
        user.tenant_id = eff_tenant_id
        user.is_active = True

    # 4. Add or update enterprise_admins table
    ent = db.query(EnterpriseAdmin).filter(EnterpriseAdmin.admin_email == clean_email).first()
    if ent:
        ent.enterprise_name = ent_name
        ent.temp_password = temp_pwd
        ent.user_id = user.id
        ent.tenant_id = eff_tenant_id
        ent.is_active = True
        ent.updated_at = datetime.utcnow()
    else:
        ent = EnterpriseAdmin(
            enterprise_name=ent_name,
            admin_email=clean_email,
            temp_password=temp_pwd,
            user_id=user.id,
            tenant_id=eff_tenant_id,
            is_active=True,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow()
        )
        db.add(ent)

    # 5. Log Audit Trail
    db.add(AuditLog(
        user_id=current_user.id,
        tenant_id=_to_uuid(eff_tenant_id),
        action="add_enterprise",
        resource_type="enterprise",
        resource_id=str(clean_email),
        severity=LogSeverity.INFO,
        detail=f"Connected enterprise '{ent_name}' (Tenant: {eff_tenant_id}) with Admin '{clean_email}'"
    ))

    db.commit()
    db.refresh(ent)
    return ent


@router.patch("/{enterprise_id}/status", response_model=EnterpriseOut)
def toggle_enterprise_status(
    enterprise_id: int,
    payload: EnterpriseStatusUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Toggle Active / Deactivated status of an enterprise.
    Synchronizes status with User and Tenant records.
    """
    ent = db.get(EnterpriseAdmin, enterprise_id)
    if not ent:
        raise HTTPException(status_code=404, detail="Enterprise record not found")

    ent.is_active = payload.is_active
    ent.updated_at = datetime.utcnow()

    # Sync with users table
    if ent.user_id:
        user = db.get(User, ent.user_id)
        if user:
            user.is_active = payload.is_active
    else:
        user = db.query(User).filter(User.email == ent.admin_email).first()
        if user:
            user.is_active = payload.is_active

    # Sync with tenants table
    try:
        t_uuid = uuid.UUID(str(ent.tenant_id))
        tenant_record = db.get(Tenant, t_uuid)
        if tenant_record:
            tenant_record.status = "active" if payload.is_active else "inactive"
    except Exception:
        pass

    db.add(AuditLog(
        user_id=current_user.id,
        tenant_id=_to_uuid(ent.tenant_id),
        action="toggle_enterprise_status",
        resource_type="enterprise",
        resource_id=str(ent.id),
        severity=LogSeverity.INFO,
        detail=f"Set enterprise '{ent.enterprise_name}' ({ent.admin_email}) status to {'Active' if payload.is_active else 'Deactivated'}"
    ))

    db.commit()
    db.refresh(ent)
    return ent


@router.delete("/{enterprise_id}")
def delete_enterprise(
    enterprise_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Remove an enterprise and deactivate its admin.
    """
    ent = db.get(EnterpriseAdmin, enterprise_id)
    if not ent:
        raise HTTPException(status_code=404, detail="Enterprise record not found")

    # Deactivate corresponding user
    if ent.user_id:
        user = db.get(User, ent.user_id)
        if user:
            user.is_active = False

    # Mark tenant inactive
    try:
        t_uuid = uuid.UUID(str(ent.tenant_id))
        tenant_record = db.get(Tenant, t_uuid)
        if tenant_record:
            tenant_record.status = "deleted"
    except Exception:
        pass

    db.delete(ent)
    db.add(AuditLog(
        user_id=current_user.id,
        tenant_id=_to_uuid(ent.tenant_id),
        action="delete_enterprise",
        resource_type="enterprise",
        resource_id=str(enterprise_id),
        severity=LogSeverity.WARNING,
        detail=f"Deleted enterprise '{ent.enterprise_name}' with admin {ent.admin_email}"
    ))
    db.commit()
    return {"status": "success", "message": f"Enterprise '{ent.enterprise_name}' deleted."}
