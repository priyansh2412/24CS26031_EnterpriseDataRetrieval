import secrets
import string
import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user, hash_password
from app.models import AuditLog, EnterpriseAdmin, LogSeverity, Role, User
from app.schemas import EnterpriseCreate, EnterpriseOut, EnterpriseStatusUpdate

router = APIRouter(prefix="/api/enterprises", tags=["enterprises"])


def _generate_temp_password(length: int = 12) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(secrets.choice(alphabet) for _ in range(length))


@router.get("", response_model=list[EnterpriseOut])
def list_enterprises(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """List all connected enterprises (Executive Admins only)."""
    if current_user.rank_level > 2 and current_user.role != Role.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only executive administrators can access enterprise management."
        )

    enterprises = db.query(EnterpriseAdmin).order_by(EnterpriseAdmin.created_at.desc()).all()
    return enterprises


@router.post("", response_model=EnterpriseOut, status_code=status.HTTP_201_CREATED)
def create_enterprise(
    payload: EnterpriseCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Provision a new connected enterprise and its admin user."""
    if current_user.rank_level > 2 and current_user.role != Role.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only executive administrators can create enterprises."
        )

    # Check if admin email is already registered
    existing_ent = db.query(EnterpriseAdmin).filter(EnterpriseAdmin.admin_email == payload.admin_email).first()
    if existing_ent:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"An enterprise admin with email '{payload.admin_email}' already exists."
        )

    temp_pwd = payload.temp_password or _generate_temp_password()
    tenant_id = payload.tenant_id or f"tenant-{uuid.uuid4().hex[:8]}"

    # Provision user account for the enterprise admin
    user = db.query(User).filter(User.email == payload.admin_email).first()
    if not user:
        user = User(
            email=payload.admin_email,
            password_hash=hash_password(temp_pwd),
            role=Role.ADMIN.value,
            role_key="admin",
            rank_level=1,
            tenant_id=uuid.uuid4(),
            created_by_id=current_user.id,
            is_active=True
        )
        db.add(user)
        db.flush()
    else:
        user.password_hash = hash_password(temp_pwd)
        user.is_active = True
        user.role = Role.ADMIN.value
        user.role_key = "admin"
        user.rank_level = 1

    ent = EnterpriseAdmin(
        enterprise_name=payload.enterprise_name,
        admin_email=payload.admin_email,
        temp_password=temp_pwd,
        user_id=user.id,
        tenant_id=tenant_id,
        is_active=True
    )
    db.add(ent)

    db.add(AuditLog(
        user_id=current_user.id,
        action="create_enterprise",
        resource_type="enterprise",
        resource_id=payload.enterprise_name,
        severity=LogSeverity.INFO.value,
        detail=f"Provisioned enterprise '{payload.enterprise_name}' with admin '{payload.admin_email}'"
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
    """Enable or disable an enterprise and its corresponding admin account."""
    if current_user.rank_level > 2 and current_user.role != Role.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only executive administrators can modify enterprise status."
        )

    ent = db.get(EnterpriseAdmin, enterprise_id)
    if not ent:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Enterprise not found")

    ent.is_active = payload.is_active

    if ent.user_id:
        admin_user = db.get(User, ent.user_id)
        if admin_user:
            admin_user.is_active = payload.is_active

    db.add(AuditLog(
        user_id=current_user.id,
        action="toggle_enterprise_status",
        resource_type="enterprise",
        resource_id=str(ent.id),
        severity=LogSeverity.WARNING.value if not payload.is_active else LogSeverity.INFO.value,
        detail=f"Set enterprise '{ent.enterprise_name}' is_active to {payload.is_active}"
    ))

    db.commit()
    db.refresh(ent)
    return ent


@router.delete("/{enterprise_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_enterprise(
    enterprise_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Delete an enterprise record and deactivate its admin account."""
    if current_user.rank_level > 2 and current_user.role != Role.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only executive administrators can delete enterprises."
        )

    ent = db.get(EnterpriseAdmin, enterprise_id)
    if not ent:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Enterprise not found")

    if ent.user_id:
        admin_user = db.get(User, ent.user_id)
        if admin_user:
            admin_user.is_active = False

    db.add(AuditLog(
        user_id=current_user.id,
        action="delete_enterprise",
        resource_type="enterprise",
        resource_id=str(ent.id),
        severity=LogSeverity.CRITICAL.value,
        detail=f"Deleted enterprise '{ent.enterprise_name}' (admin: {ent.admin_email})"
    ))

    db.delete(ent)
    db.commit()
    return None
