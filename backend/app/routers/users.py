from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import hash_password, require_permission
from app.models import AuditLog, User
from app.schemas import UserCreate, UserOut, UserUpdate

router = APIRouter(prefix="/api/users", tags=["users"])

@router.get("", response_model=list[UserOut])
def list_users(db: Session = Depends(get_db), _: User = Depends(require_permission("users:manage"))):
    return db.query(User).order_by(User.id.asc()).all()

@router.post("", response_model=UserOut)
def create_user(payload: UserCreate, db: Session = Depends(get_db), admin: User = Depends(require_permission("users:manage"))):
    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="User with this email already exists in database")
    new_user = User(
        email=payload.email,
        password_hash=hash_password(payload.password),
        role=payload.role,
        is_active=True
    )
    db.add(new_user)
    db.flush()
    db.add(AuditLog(user_id=admin.id, action="create_user", resource_type="user", resource_id=str(new_user.id), detail=f"Created {new_user.email} as {new_user.role.value}"))
    db.commit()
    db.refresh(new_user)
    return new_user

@router.patch("/{user_id}", response_model=UserOut)
def update_user(user_id: int, payload: UserUpdate, db: Session = Depends(get_db), admin: User = Depends(require_permission("users:manage"))):
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found")
    if payload.role is not None:
        target.role = payload.role
    if payload.is_active is not None:
        target.is_active = payload.is_active
    db.add(AuditLog(user_id=admin.id, action="update_user", resource_type="user", resource_id=str(user_id), detail=f"Updated user {target.email}"))
    db.commit()
    db.refresh(target)
    return target
