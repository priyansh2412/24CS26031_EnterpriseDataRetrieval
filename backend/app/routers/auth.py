from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import create_token, current_user, verify_password
from app.models import AuditLog, User
from app.schemas import ForgotPasswordRequest, Token, UserOut

router = APIRouter(prefix="/api/auth", tags=["authentication"])

@router.post("/login", response_model=Token)
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == form.username).first()
    if not user or not verify_password(form.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Incorrect email or password")
    if not user.is_active:
        raise HTTPException(status_code=401, detail="Account is deactivated")
    return Token(access_token=create_token(user))

@router.get("/me", response_model=UserOut)
def me(user: User = Depends(current_user)): return user

@router.post("/forgot-password")
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user:
        raise HTTPException(status_code=404, detail="No account found with this email address in our records.")
    db.add(AuditLog(user_id=user.id, action="password_reset_request", resource_type="auth", detail=f"Reset request for {user.email}"))
    db.commit()
    return {"message": "Password reset instructions have been recorded. Please contact your system administrator or check your email."}

