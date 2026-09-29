from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import AuditLog, CompanyRole, LogSeverity, User
from app.schemas import UserCreate, UserOut, UserUpdate

router = APIRouter(prefix="/api/users", tags=["users"])


@router.get("", response_model=list[UserOut])
def list_users(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    # Users can view other users, ordered by rank level
    return db.query(User).order_by(User.rank_level.asc(), User.id.asc()).all()


@router.post("", response_model=UserOut)
def create_user(payload: UserCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    # Hierarchy Check: Cannot assign a rank level higher than or equal to own rank (unless rank 1 / admin)
    assigned_rank = payload.rank_level or 5
    if payload.role_key:
        matched_role = db.query(CompanyRole).filter(CompanyRole.key == payload.role_key).first()
        if matched_role:
            assigned_rank = matched_role.rank_level

    if current_user.role.value != "admin" and current_user.rank_level != 1:
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
        password_hash=hash_password(payload.password),
        role=payload.role,
        role_key=payload.role_key or payload.role.value,
        rank_level=assigned_rank,
        created_by_id=current_user.id,
        is_active=True
    )
    db.add(new_user)
    db.flush()

    db.add(AuditLog(
        user_id=current_user.id,
        action="create_user",
        resource_type="user",
        resource_id=str(new_user.id),
        severity=LogSeverity.INFO,
        detail=f"Created user {new_user.email} with role '{new_user.role_key}' (Rank Level {new_user.rank_level})"
    ))
    db.commit()
    db.refresh(new_user)
    return new_user


@router.patch("/{user_id}", response_model=UserOut)
def update_user(user_id: int, payload: UserUpdate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    # Hierarchy Check: Cannot edit a user with higher or equal rank (unless rank 1 / admin or self)
    if current_user.role.value != "admin" and current_user.rank_level != 1 and target.id != current_user.id:
        if target.rank_level <= current_user.rank_level:
            raise HTTPException(
                status_code=403,
                detail=f"Cannot modify user with rank level {target.rank_level} (equal or higher than your rank level {current_user.rank_level})"
            )

    if payload.role_key is not None:
        target.role_key = payload.role_key
        matched_role = db.query(CompanyRole).filter(CompanyRole.key == payload.role_key).first()
        if matched_role:
            target.rank_level = matched_role.rank_level

    if payload.rank_level is not None:
        if current_user.role.value != "admin" and current_user.rank_level != 1:
            if payload.rank_level <= current_user.rank_level:
                raise HTTPException(status_code=403, detail="Cannot set rank level equal to or higher than your own.")
        target.rank_level = payload.rank_level

    if payload.role is not None:
        target.role = payload.role

    if payload.is_active is not None:
        target.is_active = payload.is_active

    db.add(AuditLog(
        user_id=current_user.id,
        action="update_user",
        resource_type="user",
        resource_id=str(user_id),
        severity=LogSeverity.INFO,
        detail=f"Updated user {target.email} (Role Key: {target.role_key}, Rank Level: {target.rank_level})"
    ))
    db.commit()
    db.refresh(target)
    return target

