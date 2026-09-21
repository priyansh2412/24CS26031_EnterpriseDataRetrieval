from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import current_user
from app.models import Feedback, QueryLog, User
from app.schemas import FeedbackIn

router = APIRouter(prefix="/api/feedback", tags=["feedback"])

@router.post("", status_code=201)
def add_feedback(payload: FeedbackIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if not db.get(QueryLog, payload.query_log_id): return {"accepted": False, "reason": "Query not found"}
    db.add(Feedback(query_log_id=payload.query_log_id, user_id=user.id, is_positive=payload.is_positive, comment=payload.comment)); db.commit()
    return {"accepted": True}
