import json
import uuid
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import current_user
from app.models import Document, Feedback, QueryLog, User
from app.schemas import (
    AskRequest,
    AskResponse,
    ChatRequest,
    ChatResponse,
    ChatSessionOut,
    Citation,
    Source,
)
from app.services.access import log_access
from app.services.citation_service import format_context_prompt
from app.services.llm import generate_answer
from app.services.rag_service import answer_question
from app.services.retrieval_service import retrieve_authorized_chunks

router = APIRouter(prefix="/api/chat", tags=["chat"])


@router.post("/ask", response_model=AskResponse)
def ask(
    payload: AskRequest,
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """
    Session-aware chat endpoint:
    1. Resolves user's principals (u:, g:, p:, r:, t: keys).
    2. Searches Qdrant filtered by tenant_id + matching principal_keys.
    3. Performs PostgreSQL final ACL check.
    4. Generates grounded answer with Gemini + citations.
    5. Saves session conversation history in query_logs.
    """
    # 1. Retrieve authorized chunks
    raw_chunks = retrieve_authorized_chunks(
        question=payload.question,
        db=db,
        user=user,
        top_k=payload.top_k,
        document_id=payload.document_id,
    )

    # 2. Format context & citations
    context_text, citations = format_context_prompt(raw_chunks)

    # 3. Generate answer
    answer = generate_answer(payload.question, citations)

    # 4. Handle session ID
    sess_id = (
        payload.session_id.strip()
        if payload.session_id and payload.session_id.strip()
        else f"sess-{uuid.uuid4().hex[:12]}"
    )

    # 5. Save QueryLog
    citations_data = [c.model_dump() for c in citations]
    log = QueryLog(
        user_id=user.id,
        team_id=payload.team_id,
        session_id=sess_id,
        query=payload.question,
        response=answer,
        retrieved_document_ids=json.dumps(list({str(c.document_id) for c in citations})),
        citations_json=json.dumps(citations_data),
    )
    db.add(log)
    db.commit()
    db.refresh(log)

    log_access(db, user, "ask", "knowledge_base", str(log.id), payload.question[:250])
    db.commit()

    return AskResponse(
        query_log_id=log.id,
        answer=answer,
        citations=citations,
        session_id=sess_id
    )


@router.post("", response_model=ChatResponse)
def chat_direct(
    request: ChatRequest,
    db: Session = Depends(get_db)
):
    """
    Direct RAG API endpoint (supports standalone queries).
    """
    result = answer_question(
        question=request.question,
        db=db,
        document_id=request.document_id,
        top_k=request.top_k
    )

    sources = [
        Source(
            document_id=str(c.document_id),
            chunk_id=c.chunk_id or f"chk-{idx}",
            page_start=c.page_start,
            page_end=c.page_end,
            section_path=c.section_path,
            score=c.score
        )
        for idx, c in enumerate(result.get("citations", []))
    ]

    return ChatResponse(
        answer=result.get("answer", "No answer found."),
        sources=sources
    )


@router.get("/sessions", response_model=list[ChatSessionOut])
def get_chat_sessions(
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """Fetch past chat sessions for current user."""
    logs = (
        db.query(QueryLog)
        .filter(QueryLog.user_id == user.id)
        .order_by(QueryLog.created_at.desc())
        .all()
    )
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
def get_chat_history(
    session_id: str | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """Fetch full chat history for a session or user."""
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

        fb = (
            db.query(Feedback)
            .filter(Feedback.query_log_id == log.id, Feedback.user_id == user.id)
            .first()
        )
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
def delete_chat_session(
    session_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    db.query(QueryLog).filter(
        QueryLog.user_id == user.id,
        QueryLog.session_id == session_id
    ).delete()
    db.commit()
    return {"status": "session_deleted"}


@router.delete("/history")
def clear_chat_history(
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    db.query(QueryLog).filter(QueryLog.user_id == user.id).delete()
    db.commit()
    return {"status": "cleared"}
