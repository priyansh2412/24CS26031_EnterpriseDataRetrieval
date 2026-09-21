import json
from sqlalchemy.orm import Session
from app.models import AuditLog, Document, Role, User


ROLE_PERMISSIONS: dict[Role, set[str]] = {
    Role.ADMIN: {"chat", "documents:view", "documents:manage", "documents:access", "analytics:view", "users:manage", "audit:view"},
    Role.HR: {"chat", "documents:view", "documents:access"},
    Role.FINANCE: {"chat", "documents:view", "documents:access"},
    Role.MANAGER: {"chat", "documents:view", "documents:access", "analytics:view"},
    Role.EMPLOYEE: {"chat", "documents:view"},
    Role.USER: {"chat", "documents:view"},
    Role.GUEST: {"chat"},
}


def has_permission(user: User, permission: str) -> bool:
    return permission in ROLE_PERMISSIONS.get(user.role, set())


def document_is_available_to(user: User, document: Document) -> bool:
    if user.role == Role.ADMIN:
        return True
    try:
        allowed_roles = set(json.loads(document.access_roles or "[]"))
    except json.JSONDecodeError:
        allowed_roles = set()
    return user.role.value in allowed_roles or (user.role == Role.USER and Role.EMPLOYEE.value in allowed_roles)


def log_access(db: Session, user: User | None, action: str, resource_type: str, resource_id: str | None = None, detail: str | None = None) -> None:
    db.add(AuditLog(user_id=user.id if user else None, action=action, resource_type=resource_type, resource_id=resource_id, detail=detail))
