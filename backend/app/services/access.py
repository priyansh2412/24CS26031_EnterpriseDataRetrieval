import json
from sqlalchemy.orm import Session
from app.models import AuditLog, Document, Role, User

ROLE_PERMISSIONS: dict[str, set[str]] = {
    "admin": {"chat", "documents:view", "documents:manage", "documents:access", "analytics:view", "users:manage", "audit:view"},
    "hr": {"chat", "documents:view", "documents:access"},
    "finance": {"chat", "documents:view", "documents:access"},
    "manager": {"chat", "documents:view", "documents:access", "analytics:view"},
    "employee": {"chat", "documents:view"},
    "user": {"chat", "documents:view"},
    "guest": {"chat"},
}


def has_permission(user: User, permission: str) -> bool:
    role_k = user.role.value if hasattr(user.role, "value") else str(user.role or "employee").lower()
    return permission in ROLE_PERMISSIONS.get(role_k, set()) or role_k == "admin"


def document_is_available_to(user: User, document: Document) -> bool:
    role_k = user.role.value if hasattr(user.role, "value") else str(user.role or "employee").lower()
    if role_k == "admin" or user.rank_level == 1:
        return True
    try:
        allowed_roles = set(json.loads(document.access_roles or "[]"))
    except json.JSONDecodeError:
        allowed_roles = set()
    return role_k in allowed_roles or "employee" in allowed_roles


def log_access(
    db: Session,
    user: User | None,
    action: str,
    resource_type: str,
    resource_id: str | None = None,
    detail: str | None = None
) -> None:
    try:
        db.add(
            AuditLog(
                user_id=user.id if user else None,
                action=action,
                resource_type=resource_type,
                resource_id=resource_id,
                severity="INFO",
                detail=detail
            )
        )
    except Exception as e:
        print(f"Audit log warning: {e}")
