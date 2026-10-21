from pathlib import Path
import json
import shutil
import uuid
from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, Form
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import current_user
from app.models import Document, Feedback, QueryLog, User, TeamMember
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
from app.services.acl_service import verify_document_access
from app.services.citation_service import format_context_prompt
from app.services.embedding_service import embed_text
from app.services.ingestion_service import ingest_temporary_document, delete_temporary_document
from app.services.llm import generate_answer
from app.services.qdrant_service import search
from app.services.rag_service import answer_question
from app.services.retrieval_service import retrieve_authorized_chunks

router = APIRouter(prefix="/api/chat", tags=["chat"])


def check_document_payload_access(payload: dict, user: User, db: Session) -> bool:
    """
    Checks if a user has permission to access a document chunk based on Qdrant payload
    (denied_principals, principal_keys) and database ACL rules.
    Returns True if accessible, False if restricted/denied.
    """
    # 0. Strict privacy enforcement for temporary user documents:
    # Accessible ONLY to the user who uploaded it!
    if payload.get("is_temporary") or payload.get("source") == "temp_user":
        uploaded_by_email = str(payload.get("uploaded_by_email") or "").strip().lower()
        user_email = user.email.strip().lower()
        if uploaded_by_email and uploaded_by_email != user_email:
            return False

    if payload.get("source") == "temp_team":
        team_id = payload.get("team_id")
        if team_id:
            try:
                is_mem = db.query(TeamMember).filter(TeamMember.team_id == int(team_id), TeamMember.user_id == user.id).first()
                if not is_mem and str(payload.get("uploaded_by_email") or "").strip().lower() != user.email.strip().lower():
                    return False
            except Exception:
                pass

    user_role = (user.role.value if hasattr(user.role, "value") else str(user.role or "employee")).lower()
    if user_role == "admin" or user.rank_level == 1:
        return True

    # 1. Check explicit denied principals in Qdrant payload
    denied = [str(x).strip().lower() for x in (payload.get("denied_principals") or [])]
    user_email = user.email.strip().lower()
    user_id_str = str(user.id).strip().lower()

    if (
        f"u:{user_email}" in denied
        or user_email in denied
        or f"u:{user_id_str}" in denied
        or f"u:user-{user_id_str}" in denied
    ):
        return False

    # 2. Check allowed principal keys in Qdrant payload
    allowed = [str(x).strip().lower() for x in (payload.get("principal_keys") or [])]
    user_role_k = (user.role_key or user_role).lower()

    # Filter for role / user permissions (ignore tenant key t: which is tenant isolation only)
    role_or_user_perms = [
        k for k in allowed
        if k == "*" or k.startswith("r:") or k.startswith("u:") or k.startswith("g:")
    ]

    if role_or_user_perms:
        has_role_match = (
            "*" in role_or_user_perms
            or f"r:{user_role_k}" in role_or_user_perms
            or f"r:{user_role}" in role_or_user_perms
            or f"u:{user_email}" in role_or_user_perms
            or f"u:{user_id_str}" in role_or_user_perms
            or f"g:{user_role_k}" in role_or_user_perms
        )
        if not has_role_match:
            return False

    # 3. Check PostgreSQL ACL verification
    doc_id = payload.get("document_id")
    if doc_id:
        if not verify_document_access(db, user, doc_id):
            return False

    return True


@router.post("/ask", response_model=AskResponse)
def ask(
    payload: AskRequest,
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """
    Session-aware chat endpoint:
    1. Checks Qdrant payload & ACL for accessibility of top-matching document.
    2. If inaccessible/denied, replies 'sorry you can not access this information . '.
    3. Otherwise retrieves authorized chunks, generates grounded answer, and saves session history.
    """
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    sess_id = (
        payload.session_id.strip()
        if payload.session_id and payload.session_id.strip()
        else f"sess-{uuid.uuid4().hex[:12]}"
    )

    # 1. Inspect Qdrant payload for accessibility before answering:
    # Query Qdrant for top matching chunks across the collection without principal filtering
    query_vector = embed_text(payload.question)
    raw_points = search(
        vector=query_vector,
        limit=5,
        tenant_id=eff_tenant,
        principal_keys=None,
        document_id=payload.document_id,
    )

    if raw_points:
        top_pt = raw_points[0]
        # If the top semantically relevant match has score >= 0.50
        if (top_pt.score or 0) >= 0.50:
            top_payload = top_pt.payload or {}
            if not check_document_payload_access(top_payload, user, db):
                denied_answer = "sorry you can not access this information . "
                log = QueryLog(
                    tenant_id=eff_tenant,
                    user_id=user.id,
                    team_id=payload.team_id,
                    session_id=sess_id,
                    query=payload.question,
                    response=denied_answer,
                    retrieved_document_ids="[]",
                    citations_json="[]",
                )
                db.add(log)
                db.commit()
                db.refresh(log)

                log_access(db, user, "ask:denied", "knowledge_base", str(log.id), f"Access denied to doc {top_payload.get('document_id')}")
                db.commit()

                return AskResponse(
                    query_log_id=log.id,
                    answer=denied_answer,
                    citations=[],
                    session_id=sess_id,
                )

    # 2. Retrieve authorized chunks strictly from user's enterprise tenant
    raw_chunks = retrieve_authorized_chunks(
        question=payload.question,
        db=db,
        user=user,
        top_k=payload.top_k,
        document_id=payload.document_id,
        tenant_id=eff_tenant
    )

    # If raw_points had relevant content (score >= 0.50) but raw_chunks is empty due to ACL
    if not raw_chunks and raw_points and (raw_points[0].score or 0) >= 0.50:
        denied_answer = "sorry you can not access this information . "
        log = QueryLog(
            tenant_id=eff_tenant,
            user_id=user.id,
            team_id=payload.team_id,
            session_id=sess_id,
            query=payload.question,
            response=denied_answer,
            retrieved_document_ids="[]",
            citations_json="[]",
        )
        db.add(log)
        db.commit()
        db.refresh(log)

        return AskResponse(
            query_log_id=log.id,
            answer=denied_answer,
            citations=[],
            session_id=sess_id,
        )

    # 3. Format context & citations
    context_text, citations = format_context_prompt(raw_chunks)

    # 4. Generate answer
    answer = generate_answer(payload.question, citations)

    # 5. Save QueryLog scoped to tenant
    citations_data = [c.model_dump() for c in citations]
    log = QueryLog(
        tenant_id=eff_tenant,
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
    """Fetch past chat sessions for current user within their enterprise tenant."""
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    logs = (
        db.query(QueryLog)
        .filter(
            QueryLog.user_id == user.id,
            (QueryLog.tenant_id == eff_tenant) | (QueryLog.tenant_id.is_(None))
        )
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
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    query = db.query(QueryLog).filter(
        QueryLog.user_id == user.id,
        (QueryLog.tenant_id == eff_tenant) | (QueryLog.tenant_id.is_(None))
    )
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
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    db.query(QueryLog).filter(
        QueryLog.user_id == user.id,
        QueryLog.session_id == session_id,
        (QueryLog.tenant_id == eff_tenant) | (QueryLog.tenant_id.is_(None))
    ).delete()
    db.commit()
    return {"status": "session_deleted"}


@router.delete("/history")
def clear_chat_history(
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    db.query(QueryLog).filter(
        QueryLog.user_id == user.id,
        (QueryLog.tenant_id == eff_tenant) | (QueryLog.tenant_id.is_(None))
    ).delete()
    db.commit()
    return {"status": "cleared"}


@router.post("/upload-temp")
async def upload_temp_document(
    file: UploadFile = File(...),
    session_id: str | None = Form(None),
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """
    Upload a temporary document for current user's chat session.
    Ingests into Qdrant for one-time/session usage.
    Available ONLY to this user's chat.
    """
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file selected")

    ext = Path(file.filename).suffix.lower()
    if ext not in [".pdf", ".docx", ".txt", ".md", ".csv", ".json", ".pptx", ".log"]:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file format '{ext}'. Supported: PDF, DOCX, TXT, MD, CSV, JSON."
        )

    temp_dir = settings.data_path / "temp_uploads"
    temp_dir.mkdir(parents=True, exist_ok=True)
    temp_file_path = temp_dir / f"{uuid.uuid4().hex}_{file.filename}"

    with open(temp_file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    try:
        result = ingest_temporary_document(
            file_path=temp_file_path,
            filename=file.filename,
            user=user,
            db=db,
            session_id=session_id
        )
        return result
    except Exception as e:
        if temp_file_path.exists():
            temp_file_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=f"Failed to process document: {str(e)}")


@router.get("/temp-docs")
def list_temp_documents(
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """List active temporary documents for current user."""
    eff_tenant = str(user.tenant_id or settings.default_tenant_id)
    docs = (
        db.query(Document)
        .filter(
            Document.source == "temp_user",
            Document.tenant_id == eff_tenant,
            Document.owner_email == user.email
        )
        .order_by(Document.created_at.desc())
        .all()
    )
    return [
        {
            "document_id": d.id,
            "name": d.name,
            "chunk_count": d.chunk_count,
            "size_bytes": d.size_bytes,
            "created_at": d.created_at.isoformat() if d.created_at else None,
        }
        for d in docs
    ]


@router.delete("/temp-docs/{document_id}")
def remove_temp_document(
    document_id: str,
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """Remove a temporary document and its vector chunks."""
    success = delete_temporary_document(document_id, user, db)
    if not success:
        raise HTTPException(status_code=404, detail="Temporary document not found or unauthorized")
    return {"status": "success", "message": "Temporary document deleted."}

