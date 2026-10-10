import uuid
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import create_token, current_user, hash_password, verify_password
from app.models import AuditLog, EnterpriseAdmin, LogSeverity, Tenant, User
from app.schemas import ChangePasswordRequest, ForgotPasswordRequest, Token, UserProfileOut

router = APIRouter(prefix="/api/auth", tags=["authentication"])


def _to_uuid(val):
    if not val:
        return None
    if isinstance(val, uuid.UUID):
        return val
    try:
        return uuid.UUID(str(val))
    except Exception:
        return None


@router.post("/login", response_model=Token)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    clean_email = form.username.strip().lower()
    user = db.query(User).filter(User.email == clean_email).first()
    if not user or not verify_password(form.password, user.password_hash):
        db.add(AuditLog(
            user_id=None,
            tenant_id=_to_uuid(user.tenant_id) if user else None,
            action="login_failed",
            resource_type="auth",
            severity=LogSeverity.WARNING,
            detail=f"Failed login attempt for email {clean_email}"
        ))
        db.commit()
        raise HTTPException(status_code=401, detail="Incorrect email or password")

    if not user.is_active:
        db.add(AuditLog(
            user_id=user.id,
            tenant_id=_to_uuid(user.tenant_id),
            action="login_blocked",
            resource_type="auth",
            severity=LogSeverity.WARNING,
            detail=f"Deactivated user {user.email} attempted login"
        ))
        db.commit()
        raise HTTPException(status_code=401, detail="Account is deactivated")

    db.add(AuditLog(
        user_id=user.id,
        tenant_id=_to_uuid(user.tenant_id),
        action="login_success",
        resource_type="auth",
        severity=LogSeverity.INFO,
        detail=f"User {user.email} logged in successfully"
    ))
    db.commit()
    return Token(access_token=create_token(user))


@router.get("/me", response_model=UserProfileOut)
def me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    # Resolve enterprise name
    ent_name = None
    if user.tenant_id:
        try:
            t_uuid = _to_uuid(user.tenant_id)
            if t_uuid:
                t = db.get(Tenant, t_uuid)
                if t:
                    ent_name = t.name
        except Exception:
            pass

    if not ent_name:
        ea = db.query(EnterpriseAdmin).filter((EnterpriseAdmin.user_id == user.id) | (EnterpriseAdmin.admin_email == user.email)).first()
        if ea:
            ent_name = ea.enterprise_name

    return UserProfileOut(
        id=user.id,
        email=user.email,
        role=user.role,
        role_key=user.role_key or (user.role.value if hasattr(user.role, "value") else str(user.role)),
        rank_level=user.rank_level,
        is_active=user.is_active,
        tenant_id=str(user.tenant_id) if user.tenant_id else None,
        enterprise_name=ent_name,
        created_at=user.created_at
    )


@router.post("/change-password")
def change_password(
    payload: ChangePasswordRequest,
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    if not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect.")

    if len(payload.new_password.strip()) < 6:
        raise HTTPException(status_code=400, detail="New password must be at least 6 characters long.")

    # Update User password hash
    user.password_hash = hash_password(payload.new_password.strip())

    # Sync with EnterpriseAdmin table if user is an enterprise admin
    ea = db.query(EnterpriseAdmin).filter(EnterpriseAdmin.admin_email == user.email).first()
    if ea:
        ea.temp_password = payload.new_password.strip()

    db.add(AuditLog(
        user_id=user.id,
        tenant_id=_to_uuid(user.tenant_id),
        action="change_password",
        resource_type="auth",
        severity=LogSeverity.INFO,
        detail=f"User {user.email} successfully updated their account password."
    ))
    db.commit()
    return {"status": "success", "message": "Password updated successfully."}


@router.post("/forgot-password")
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    clean_email = payload.email.strip().lower()
    user = db.query(User).filter(User.email == clean_email).first()
    if not user:
        raise HTTPException(status_code=404, detail="No account found with this email address in our records.")

    db.add(AuditLog(
        user_id=user.id,
        tenant_id=_to_uuid(user.tenant_id),
        action="password_reset_request",
        resource_type="auth",
        detail=f"Reset request for {user.email}"
    ))
    db.commit()
    return {"message": "Password reset instructions have been recorded. Please contact your system administrator or check your email."}
