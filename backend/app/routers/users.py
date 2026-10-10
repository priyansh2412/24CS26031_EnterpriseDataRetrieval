import uuid
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user, hash_password
from app.models import AuditLog, CompanyRole, LogSeverity, User
from app.schemas import UserCreate, UserOut, UserUpdate

router = APIRouter(prefix="/api/users", tags=["users"])


def _to_uuid(val: Any) -> uuid.UUID | None:
    if not val:
        return None
    if isinstance(val, uuid.UUID):
        return val
    try:
        return uuid.UUID(str(val))
    except Exception:
        return None


def _is_system_admin(user: User) -> bool:
    role_val = user.role.value if hasattr(user.role, "value") else str(user.role or "employee")
    return user.email == "system@gmailexample.com" or (role_val == "admin" and getattr(user, "rank_level", 5) == 0)


@router.get("", response_model=list[UserOut])
def list_users(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """List users within the same enterprise tenant, or all users for system super admin."""
    if _is_system_admin(current_user):
        return db.query(User).order_by(User.rank_level.asc(), User.id.asc()).all()

    eff_tenant = current_user.tenant_id
    if eff_tenant:
        return db.query(User).filter(User.tenant_id == eff_tenant).order_by(User.rank_level.asc(), User.id.asc()).all()
    else:
        return db.query(User).filter(User.tenant_id.is_(None)).order_by(User.rank_level.asc(), User.id.asc()).all()


@router.post("", response_model=UserOut)
def create_user(payload: UserCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    # Hierarchy Check: Cannot assign a rank level higher than or equal to own rank (unless rank 1 / admin)
    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
    assigned_rank = payload.rank_level or 5
    if payload.role_key:
        matched_role = db.query(CompanyRole).filter(CompanyRole.key == payload.role_key).first()
        if matched_role:
            assigned_rank = matched_role.rank_level

    if curr_role != "admin" and current_user.rank_level != 1 and not _is_system_admin(current_user):
        if assigned_rank <= current_user.rank_level:
            raise HTTPException(
                status_code=403,
                detail=f"Cannot create user with rank level {assigned_rank} (must be subordinate to your rank level {current_user.rank_level})"
            )

    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="User with this email already exists in database")

    new_user = User(
        email=payload.email,
        display_name=payload.display_name,
        password_hash=hash_password(payload.password),
        role=payload.role.value if hasattr(payload.role, "value") else str(payload.role),
        role_key=payload.role_key or (payload.role.value if hasattr(payload.role, "value") else str(payload.role)),
        rank_level=assigned_rank,
        tenant_id=current_user.tenant_id,
        created_by_id=current_user.id,
        is_active=True
    )
    db.add(new_user)
    db.flush()

    db.add(AuditLog(
        user_id=current_user.id,
        tenant_id=_to_uuid(current_user.tenant_id),
        action="create_user",
        resource_type="user",
        resource_id=str(new_user.id),
        severity=LogSeverity.INFO,
        detail=f"Created user {new_user.email} ({new_user.display_name or ''}) with role '{new_user.role_key}' (Rank Level {new_user.rank_level})"
    ))
    db.commit()
    db.refresh(new_user)
    return new_user


@router.patch("/{user_id}", response_model=UserOut)
def update_user(user_id: str, payload: UserUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        uid = uuid.UUID(user_id)
        target = db.query(User).filter(User.id == uid).first()
    except Exception:
        target = db.query(User).filter(User.id == user_id).first()

    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    # Enforce tenant boundary
    if not _is_system_admin(current_user) and target.tenant_id != current_user.tenant_id:
        raise HTTPException(status_code=403, detail="Access denied: user belongs to different enterprise.")

    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")

    # Hierarchy Check: Cannot edit a user with higher or equal rank (unless rank 1 / admin or self)
    if curr_role != "admin" and current_user.rank_level != 1 and not _is_system_admin(current_user) and target.id != current_user.id:
        if target.rank_level <= current_user.rank_level:
            raise HTTPException(
                status_code=403,
                detail=f"Cannot modify user with rank level {target.rank_level} (equal or higher than your rank level {current_user.rank_level})"
            )

    if payload.display_name is not None:
        target.display_name = payload.display_name

    if payload.role_key is not None:
        target.role_key = payload.role_key
        matched_role = db.query(CompanyRole).filter(CompanyRole.key == payload.role_key).first()
        if matched_role:
            target.rank_level = matched_role.rank_level

    if payload.rank_level is not None:
        if curr_role != "admin" and current_user.rank_level != 1 and not _is_system_admin(current_user):
            if payload.rank_level <= current_user.rank_level:
                raise HTTPException(status_code=403, detail="Cannot set rank level equal to or higher than your own.")
        target.rank_level = payload.rank_level

    if payload.role is not None:
        target.role = payload.role.value if hasattr(payload.role, "value") else str(payload.role)

    if payload.is_active is not None:
        target.is_active = payload.is_active

    db.add(AuditLog(
        user_id=current_user.id,
        tenant_id=_to_uuid(current_user.tenant_id),
        action="update_user",
        resource_type="user",
        resource_id=str(user_id),
        severity=LogSeverity.INFO,
        detail=f"Updated user {target.email} (Role Key: {target.role_key}, Rank Level: {target.rank_level})"
    ))
    db.commit()
    db.refresh(target)
    return target


@router.delete("/{user_id}")
def delete_user(user_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    try:
        uid = uuid.UUID(user_id)
        target = db.query(User).filter(User.id == uid).first()
    except Exception:
        target = db.query(User).filter(User.id == user_id).first()

    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    if not _is_system_admin(current_user) and target.tenant_id != current_user.tenant_id:
        raise HTTPException(status_code=403, detail="Access denied: user belongs to different enterprise.")

    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
    if curr_role != "admin" and current_user.rank_level != 1 and not _is_system_admin(current_user):
        if target.rank_level <= current_user.rank_level:
            raise HTTPException(status_code=403, detail="Cannot delete user with equal or higher rank level.")

    target_email = target.email
    target_dname = target.display_name or "N/A"
    db.delete(target)
    db.add(AuditLog(
        user_id=current_user.id,
        tenant_id=_to_uuid(current_user.tenant_id),
        action="delete_user",
        resource_type="user",
        resource_id=str(user_id),
        severity=LogSeverity.WARNING,
        detail=f"Deleted user {target_email} ({target_dname})"
    ))
    db.commit()
    return {"status": "success", "message": f"User {target_email} deleted"}
