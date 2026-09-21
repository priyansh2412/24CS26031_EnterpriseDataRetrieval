from sqlalchemy import func
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import require_permission
from app.models import Document, QueryLog, Role, User

router = APIRouter(prefix="/api/analytics", tags=["analytics"])

@router.get("/overview")
def overview(db: Session = Depends(get_db), _: User = Depends(require_permission("analytics:view"))):
    popular_queries = db.query(QueryLog.query, func.count(QueryLog.id).label("count")).group_by(QueryLog.query).order_by(func.count(QueryLog.id).desc()).limit(10).all()
    return {"document_count": db.query(func.count(Document.id)).scalar(), "ready_documents": db.query(func.count(Document.id)).filter(Document.status == "ready").scalar(), "query_count": db.query(func.count(QueryLog.id)).scalar(), "popular_queries": [{"query": query, "count": count} for query, count in popular_queries]}

