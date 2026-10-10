import uuid
from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.orm import Session
from app.core.config import settings
from app.core.database import get_db
from app.models import Role, User
from app.services.access import has_permission

try:
    import bcrypt

    def hash_password(value: str) -> str:
        salt = bcrypt.gensalt()
        return bcrypt.hashpw(value.encode("utf-8"), salt).decode("utf-8")

    def verify_password(value: str, hashed: str) -> bool:
        if not value or not hashed:
            return False
        try:
            return bcrypt.checkpw(value.encode("utf-8"), hashed.encode("utf-8"))
        except Exception:
            return False

except ImportError:
    from passlib.context import CryptContext
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    def hash_password(value: str) -> str: return pwd_context.hash(value)
    def verify_password(value: str, hashed: str) -> bool: return pwd_context.verify(value, hashed)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


def create_token(user: User) -> str:
    payload = {
        "sub": str(user.id),
        "role": user.role.value if hasattr(user.role, "value") else str(user.role),
        "exp": datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_minutes)
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    try:
        sub = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])["sub"]
        try:
            user_id = uuid.UUID(sub)
        except (ValueError, AttributeError):
            try:
                user_id = int(sub)
            except ValueError:
                user_id = sub
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid authentication token")

    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Inactive user")
    return user


get_current_user = current_user


def require_role(*roles: Role):
    def checker(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(status_code=403, detail="Insufficient role")
        return user
    return checker


def require_permission(permission: str):
    def checker(user: User = Depends(current_user)) -> User:
        if not has_permission(user, permission):
            raise HTTPException(status_code=403, detail="You do not have permission to perform this action")
        return user
    return checker

