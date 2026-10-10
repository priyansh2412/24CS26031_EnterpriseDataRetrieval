import uuid
from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.models import Role, User
from app.services.access import has_permission

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


def hash_password(value: str) -> str:
    return pwd_context.hash(value)


def verify_password(value: str, hashed: str | None) -> bool:
    if not hashed:
        return False
    return pwd_context.verify(value, hashed)


def create_token(user: User) -> str:
    role_str = user.role.value if hasattr(user.role, "value") else str(user.role)
    payload = {
        "sub": str(user.id),
        "role": role_str,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        user_id_str = payload.get("sub")
        if not user_id_str:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid authentication token")
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid authentication token")

    try:
        user = db.query(User).filter(User.id == uuid.UUID(user_id_str)).first()
    except Exception:
        user = db.query(User).filter(User.email == user_id_str).first()

    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Inactive or non-existent user")
    return user


get_current_user = current_user


def require_role(*roles: Role | str):
    def checker(user: User = Depends(current_user)) -> User:
        user_role_val = user.role.value if hasattr(user.role, "value") else str(user.role)
        role_vals = [r.value if hasattr(r, "value") else str(r) for r in roles]
        if user_role_val not in role_vals:
            raise HTTPException(status_code=403, detail="Insufficient role")
        return user
    return checker


def require_permission(permission: str):
    def checker(user: User = Depends(current_user)) -> User:
        if not has_permission(user, permission):
            raise HTTPException(status_code=403, detail="You do not have permission to perform this action")
        return user
    return checker
