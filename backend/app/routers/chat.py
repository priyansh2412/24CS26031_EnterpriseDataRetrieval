import json
import uuid
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import current_user
from app.models import Document, Feedback, QueryLog, User
from app.schemas import AskRequest, AskResponse, ChatSessionOut
from app.services.llm import generate_answer
from app.services.retrieval import retrieve
from app.services.access import document_is_available_to, log_access

router = APIRouter(prefix="/api/chat", tags=["chat"])

@router.post("/ask", response_model=AskResponse)
def ask(payload: AskRequest, db: Session = Depends(get_db), user: User = Depends(current_user)):
    citations = [citation for citation in retrieve(payload.question, db, payload.top_k * 3) if (document := db.get(Document, citation.document_id)) and document_is_available_to(user, document)][:payload.top_k]
    answer = generate_answer(payload.question, citations)
    citations_data = [c.model_dump() for c in citations]

    sess_id = payload.session_id.strip() if payload.session_id and payload.session_id.strip() else f"sess-{uuid.uuid4().hex[:12]}"

    log = QueryLog(
        user_id=user.id,
        team_id=payload.team_id,
        session_id=sess_id,
        query=payload.question,
        response=answer,
        retrieved_document_ids=json.dumps(list({c.document_id for c in citations})),
        citations_json=json.dumps(citations_data),
    )
    db.add(log); db.commit(); db.refresh(log)
    log_access(db, user, "ask", "knowledge_base", str(log.id), payload.question[:250]); db.commit()
    return AskResponse(query_log_id=log.id, answer=answer, citations=citations, session_id=sess_id)

@router.get("/sessions", response_model=list[ChatSessionOut])
def get_chat_sessions(db: Session = Depends(get_db), user: User = Depends(current_user)):
    logs = db.query(QueryLog).filter(QueryLog.user_id == user.id).order_by(QueryLog.created_at.desc()).all()
    sessions_dict = {}
    for log in logs:
        sess_id = log.session_id or f"sess-legacy-{user.id}"
        if sess_id not in sessions_dict:
            ts = log.created_at.strftime("%b %d, %I:%M %p") if log.created_at else ""
            sessions_dict[sess_id] = {
                "session_id": sess_id,
                "title": log.query[:60] + ("..." if len(log.query) > 60 else ""),
                "created_at": ts,
                "message_count": 0,
            }
        sessions_dict[sess_id]["message_count"] += 2

    return list(sessions_dict.values())

@router.get("/history")
def get_chat_history(session_id: str | None = None, db: Session = Depends(get_db), user: User = Depends(current_user)):
    query = db.query(QueryLog).filter(QueryLog.user_id == user.id)
    if session_id:
        query = query.filter(QueryLog.session_id == session_id)
    logs = query.order_by(QueryLog.id.asc()).all()
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
            "session_id": log.session_id or f"sess-legacy-{user.id}",
        })
        history.append({
            "id": f"ast-{log.id}",
            "sender": "assistant",
            "text": log.response,
            "citations": cits,
            "query_log_id": log.id,
            "timestamp": ts,
            "feedbackGiven": fb_status,
            "session_id": log.session_id or f"sess-legacy-{user.id}",
        })
    return history

@router.delete("/sessions/{session_id}")
def delete_chat_session(session_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    db.query(QueryLog).filter(QueryLog.user_id == user.id, QueryLog.session_id == session_id).delete()
    db.commit()
    return {"status": "session_deleted"}

@router.delete("/history")
def clear_chat_history(db: Session = Depends(get_db), user: User = Depends(current_user)):
    db.query(QueryLog).filter(QueryLog.user_id == user.id).delete()
    db.commit()
    return {"status": "cleared"}

