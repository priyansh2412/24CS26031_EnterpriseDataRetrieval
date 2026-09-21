from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import require_permission
from app.models import AuditLog, User
from app.schemas import AuditLogOut

router = APIRouter(prefix="/api/audit-logs", tags=["audit"])

@router.get("", response_model=list[AuditLogOut])
def list_audit_logs(db: Session = Depends(get_db), _: User = Depends(require_permission("audit:view"))):
    logs = db.query(AuditLog, User.email).outerjoin(User, AuditLog.user_id == User.id).order_by(AuditLog.created_at.desc()).limit(100).all()
    out = []
    for log, email in logs:
        item = AuditLogOut(
            id=log.id,
            user_id=log.user_id,
            user_email=email or "System/Guest",
            action=log.action,
            resource_type=log.resource_type,
            resource_id=log.resource_id,
            detail=log.detail,
            created_at=log.created_at
        )
        out.append(item)
    return out
