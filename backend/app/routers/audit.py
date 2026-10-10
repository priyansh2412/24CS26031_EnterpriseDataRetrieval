import uuid
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import AuditLog, LogSeverity, User
from app.schemas import AuditLogOut

router = APIRouter(prefix="/api/audit-logs", tags=["audit"])


@router.get("", response_model=list[AuditLogOut])
def list_audit_logs(
    target_user_id: str | None = Query(None),
    severity: str | None = Query(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
    query = db.query(AuditLog, User.email, User.role_key, User.role, User.rank_level).outerjoin(User, AuditLog.user_id == User.id)

    # Hierarchical Role-Based Filtering:
    # A user can only view logs of users with rank_level > current_user.rank_level (succeeding/lower level roles)
    # Root Admin (rank 1) or user with rank 1 can see all logs
    if curr_role != "admin" and current_user.rank_level > 1:
        query = query.filter(
            (User.rank_level > current_user.rank_level) | (AuditLog.user_id == current_user.id)
        )

    # Filter by specific target user if requested
    if target_user_id is not None:
        try:
            uid = uuid.UUID(target_user_id)
            query = query.filter(AuditLog.user_id == uid)
        except Exception:
            query = query.filter(AuditLog.user_id == target_user_id)

    # Filter by severity level if requested
    if severity and severity.upper() in [s.value for s in LogSeverity]:
        query = query.filter(AuditLog.severity == severity.upper())

    logs = query.order_by(AuditLog.created_at.desc()).limit(150).all()

    out = []
    for log, email, role_key, role_enum, rank_lvl in logs:
        severity_val = log.severity.value if hasattr(log.severity, "value") else str(log.severity or "INFO")
        role_val = role_enum.value if hasattr(role_enum, "value") else str(role_enum or "system")
        item = AuditLogOut(
            id=log.id,
            user_id=log.user_id,
            user_email=email or "System/Guest",
            user_role_key=role_key or role_val,
            user_rank_level=rank_lvl if rank_lvl is not None else 0,
            action=log.action,
            resource_type=log.resource_type,
            resource_id=log.resource_id,
            severity=severity_val,
            detail=log.detail,
            created_at=log.created_at
        )
        out.append(item)
    return out


@router.get("/subordinates", response_model=list[dict])
def list_subordinate_users(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Returns list of users in succeeding (lower) role levels for the audit log dropdown filter."""
    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
    if curr_role == "admin" or current_user.rank_level == 1:
        users = db.query(User).filter(User.id != current_user.id).order_by(User.rank_level.asc(), User.email.asc()).all()
    else:
        users = db.query(User).filter(User.rank_level > current_user.rank_level).order_by(User.rank_level.asc(), User.email.asc()).all()

    return [
        {
            "id": u.id,
            "email": u.email,
            "role_key": u.role_key or (u.role.value if hasattr(u.role, "value") else str(u.role)),
            "rank_level": u.rank_level
        } for u in users
    ]

