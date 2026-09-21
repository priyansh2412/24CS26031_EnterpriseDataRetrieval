import json
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import current_user
from app.models import Document, Feedback, QueryLog, User
from app.schemas import AskRequest, AskResponse
from app.services.llm import generate_answer
from app.services.retrieval import retrieve
from app.services.access import document_is_available_to, log_access

router = APIRouter(prefix="/api/chat", tags=["chat"])

@router.post("/ask", response_model=AskResponse)
def ask(payload: AskRequest, db: Session = Depends(get_db), user: User = Depends(current_user)):
    citations = [citation for citation in retrieve(payload.question, db, payload.top_k * 3) if (document := db.get(Document, citation.document_id)) and document_is_available_to(user, document)][:payload.top_k]
    answer = generate_answer(payload.question, citations)
    citations_data = [c.model_dump() for c in citations]
    log = QueryLog(
        user_id=user.id,
        query=payload.question,
        response=answer,
        retrieved_document_ids=json.dumps(list({c.document_id for c in citations})),
        citations_json=json.dumps(citations_data),
    )
    db.add(log); db.commit(); db.refresh(log)
    log_access(db, user, "ask", "knowledge_base", str(log.id), payload.question[:250]); db.commit()
    return AskResponse(query_log_id=log.id, answer=answer, citations=citations)

@router.get("/history")
def get_chat_history(db: Session = Depends(get_db), user: User = Depends(current_user)):
    logs = db.query(QueryLog).filter(QueryLog.user_id == user.id).order_by(QueryLog.id.asc()).all()
    history = []
    for log in logs:
        cits = []
        if getattr(log, "citations_json", None):
            try:
                cits = json.loads(log.citations_json)
            except Exception:
                cits = []
        
        fb = db.query(Feedback).filter(Feedback.query_log_id == log.id, Feedback.user_id == user.id).first()
        fb_status = fb.is_positive if fb else None
        ts = log.created_at.strftime("%I:%M %p") if log.created_at else ""

        history.append({
            "id": f"usr-{log.id}",
            "sender": "user",
            "text": log.query,
            "timestamp": ts,
        })
        history.append({
            "id": f"ast-{log.id}",
            "sender": "assistant",
            "text": log.response,
            "citations": cits,
            "query_log_id": log.id,
            "timestamp": ts,
            "feedbackGiven": fb_status,
        })
    return history

@router.delete("/history")
def clear_chat_history(db: Session = Depends(get_db), user: User = Depends(current_user)):
    db.query(QueryLog).filter(QueryLog.user_id == user.id).delete()
    db.commit()
    return {"status": "cleared"}

