import hashlib
import json
import logging
import re
import threading
import time
import uuid
from abc import ABC, abstractmethod
from datetime import datetime, timedelta
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import EnterpriseAdmin, QueryLog, User, UserPhoneLink, WhatsAppLinkCode
from app.schemas import Citation
from app.services.access import log_access
from app.services.citation_service import format_context_prompt
from app.services.llm import generate_answer
from app.services.retrieval_service import retrieve_authorized_chunks

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Channel Adapter Interface
# ---------------------------------------------------------------------------
class ChannelAdapter(ABC):
    """
    Abstract adapter for outbound messaging channels.
    Provides a standardized swap point for the future official WhatsApp Business API
    or alternative provider adapters (Baileys Node gateway currently handles sending).
    """

    @abstractmethod
    def send_message(self, jid: str, text: str) -> None:
        """Send an outbound message to the given WhatsApp JID."""
        pass


# ---------------------------------------------------------------------------
# In-Memory Rate Limiting (Sliding Window, Thread-Safe)
# ---------------------------------------------------------------------------
_rate_limit_lock = threading.Lock()
_user_message_times: dict[str, list[float]] = {}
RATE_LIMIT_MAX_MESSAGES = 10
RATE_LIMIT_WINDOW_SECONDS = 60.0


def is_rate_limited(user_id: str) -> bool:
    """
    Thread-safe sliding window rate limiter: allows up to 10 messages per 60 seconds per user.
    Returns True if rate limit is exceeded.
    """
    user_key = str(user_id)
    now = time.time()
    cutoff = now - RATE_LIMIT_WINDOW_SECONDS

    with _rate_limit_lock:
        timestamps = _user_message_times.get(user_key, [])
        # Prune timestamps outside the current window
        timestamps = [t for t in timestamps if t > cutoff]
        if len(timestamps) >= RATE_LIMIT_MAX_MESSAGES:
            _user_message_times[user_key] = timestamps
            return True
        timestamps.append(now)
        _user_message_times[user_key] = timestamps
        return False


def _clear_rate_limits() -> None:
    """Helper for testing to reset rate limit state."""
    with _rate_limit_lock:
        _user_message_times.clear()


# ---------------------------------------------------------------------------
# In-Memory Session Management (Thread-Safe)
# ---------------------------------------------------------------------------
_session_lock = threading.Lock()
_user_sessions: dict[str, tuple[str, datetime]] = {}
SESSION_IDLE_TIMEOUT = timedelta(minutes=30)


def get_session_id(user_id: str) -> str:
    """
    Returns active session id for user. Reuses if idle < 30 minutes,
    otherwise creates a fresh session ID.
    """
    user_key = str(user_id)
    now = datetime.utcnow()
    with _session_lock:
        if user_key in _user_sessions:
            sess_id, last_activity = _user_sessions[user_key]
            if (now - last_activity) < SESSION_IDLE_TIMEOUT:
                _user_sessions[user_key] = (sess_id, now)
                return sess_id
        new_sess = f"sess-wa-{uuid.uuid4().hex[:10]}"
        _user_sessions[user_key] = (new_sess, now)
        return new_sess


def reset_session(user_id: str) -> str:
    """Resets session for user and returns the new session ID."""
    user_key = str(user_id)
    now = datetime.utcnow()
    new_sess = f"sess-wa-{uuid.uuid4().hex[:10]}"
    with _session_lock:
        _user_sessions[user_key] = (new_sess, now)
    return new_sess


def _clear_sessions() -> None:
    """Helper for testing to reset session state."""
    with _session_lock:
        _user_sessions.clear()


# ---------------------------------------------------------------------------
# Formatting Helpers for WhatsApp
# ---------------------------------------------------------------------------
def clean_whatsapp_text(text: str) -> str:
    """
    WhatsApp cleanup of the answer text:
    - Convert markdown headers (lines starting with #, ##, ###, ####) into '*Header text*'.
    - Convert '**text**' to '*text*'.
    - Convert lines starting with '* ' or '- ' into '• '.
    - Collapse 3 or more blank lines into 1.
    """
    if not text:
        return text

    # Normalize CRLF
    text = text.replace("\r\n", "\n")

    # 1. Convert markdown headers (lines starting with #, ##, ###, ####) into "*Header text*"
    lines = text.split("\n")
    cleaned_header_lines = []
    for line in lines:
        stripped = line.strip()
        header_match = re.match(r"^#{1,6}\s+(.+)$", stripped)
        if header_match:
            header_text = header_match.group(1).strip()
            # Strip existing outer asterisks if any to avoid double asterisks
            if header_text.startswith("*") and header_text.endswith("*") and len(header_text) > 1:
                header_text = header_text[1:-1].strip()
            cleaned_header_lines.append(f"*{header_text}*")
        else:
            cleaned_header_lines.append(line)
    text = "\n".join(cleaned_header_lines)

    # 2. Convert "**text**" to "*text*"
    text = text.replace("**", "*")

    # 3. Convert lines starting with "* " or "- " into "• "
    lines = text.split("\n")
    bullet_cleaned_lines = []
    for line in lines:
        bullet_cleaned_lines.append(re.sub(r"^(\s*)[*-]\s+", r"\1• ", line))
    text = "\n".join(bullet_cleaned_lines)

    # 4. Collapse 3 or more blank lines into 1 (i.e. at least 4 newlines into 2)
    text = re.sub(r"\n(?:[ \t]*\n){3,}", "\n\n", text)

    return text


def _truncate_at_boundary(text: str, max_chars: int) -> str:
    """
    Truncate text so len(text) <= max_chars, ending with '…'.
    Truncates at a paragraph boundary (\n\n) or sentence boundary ([.!?]),
    falling back to word boundary, and never cutting in the middle of a word.
    """
    ellipsis = "…"
    if len(text) <= max_chars:
        return text

    budget = max_chars - len(ellipsis)
    if budget <= 0:
        return text[:max_chars]

    candidate = text[:budget]

    best_cut = -1

    # Check for sentence boundary ([.!?] followed by whitespace or end)
    sentence_matches = list(re.finditer(r"[.!?](?=\s|$)", candidate))
    if sentence_matches:
        best_cut = sentence_matches[-1].end()

    # Check for paragraph boundary (\n\n)
    last_para = candidate.rfind("\n\n")
    if last_para != -1 and last_para > best_cut:
        best_cut = last_para

    if best_cut > 0:
        return candidate[:best_cut].rstrip() + ellipsis

    # Fallback: word boundary (space)
    last_space = candidate.rfind(" ")
    if last_space > 0:
        return candidate[:last_space].rstrip() + ellipsis

    # Extreme edge case: single token exceeding budget
    return candidate.rstrip() + ellipsis


def format_whatsapp_reply(answer: str, citations: list[Citation]) -> str:
    """
    Formats RAG answer for WhatsApp:
    1. If no citations: replies standard no-document message.
    2. Cleans answer text (headers, bold, bullets, collapses blank lines).
    3. Builds 'Sources:' block matching inline [Source N] numbering (N is 1-based index in citations).
       If none cited, lists first 3 citations. Never lists N with no matching citation.
    4. Enforces 3500-character cap by truncating answer at paragraph/sentence boundary,
       never in the middle of a word, and never cutting the Sources block.
    """
    if not citations:
        return "I couldn't find that in the documents you have access to."

    # 1. Clean answer text for WhatsApp before adding Sources
    cleaned_answer = clean_whatsapp_text(answer).strip()

    # If the answer indicates insufficient context and has no citations, return standard unavailable message
    insufficient_patterns = [
        r"does not contain",
        r"is insufficient",
        r"not mentioned in the (supplied )?context",
        r"cannot find",
        r"couldn't find",
        r"no information (is )?available",
        r"not provided in the (supplied )?context",
    ]
    if any(re.search(pat, cleaned_answer, re.IGNORECASE) for pat in insufficient_patterns):
        if not re.search(r"\[Source \d+", answer):
            return "I couldn't find that in the documents you have access to."

    # 2. Extract inline [Source N] numbers from the answer text
    cited_numbers: list[int] = []
    seen_numbers: set[int] = set()
    for m in re.finditer(r"\[Source (\d+)", answer):
        n = int(m.group(1))
        if 1 <= n <= len(citations) and n not in seen_numbers:
            seen_numbers.add(n)
            cited_numbers.append(n)

    # If the answer cites none, list the first 3 citations
    if not cited_numbers:
        cited_numbers = list(range(1, min(len(citations), 3) + 1))

    # 3. Format sources lines: "[N] <document_name>, p.<page_start>-<page_end>"
    sources_lines: list[str] = []
    for n in cited_numbers:
        c = citations[n - 1]
        page_part = ""
        if c.page_start is not None and c.page_end is not None:
            if c.page_start == c.page_end:
                page_part = f", p.{c.page_start}"
            else:
                page_part = f", p.{c.page_start}-{c.page_end}"
        elif c.page_start is not None:
            page_part = f", p.{c.page_start}"
        elif c.page_end is not None:
            page_part = f", p.{c.page_end}"

        sources_lines.append(f"[{n}] {c.document_name}{page_part}")

    sources_block = "\n\nSources:\n" + "\n".join(sources_lines)

    # 4. Cap total at 3500 characters, truncating answer (not Sources block)
    max_len = 3500
    full_message = f"{cleaned_answer}{sources_block}"
    if len(full_message) > max_len:
        allowed_answer_len = max_len - len(sources_block)
        if allowed_answer_len > 0:
            truncated_answer = _truncate_at_boundary(cleaned_answer, allowed_answer_len)
            full_message = f"{truncated_answer}{sources_block}"
        else:
            full_message = full_message[: max_len - 1] + "…"

    return full_message



# ---------------------------------------------------------------------------
# Core Inbound Handler
# ---------------------------------------------------------------------------
def handle_inbound(
    db: Session,
    wa_message_id: str,
    jid: str,
    push_name: str | None,
    text: str
) -> str | None:
    """
    Handles an inbound WhatsApp message from the gateway:
    1. Trims text; ignores empty or whitespace-only messages.
    2. Handles LINK <code> command: validates code hash, links user, logs audit, confirms.
    3. Verifies existing active phone link for JID; returns generic prompt if unlinked.
    4. Validates user and tenant active status; revokes link if deactivated.
    5. Checks sliding window rate limit (10 msgs / 60s per user).
    6. Processes commands (/help, /new, /unlink).
    7. Runs RAG query with authorized chunks, format prompt, Gemini answer, and audit logs.
    """
    if not text or not text.strip():
        return None
    text = text.strip()

    # 1. Check for LINK <code> command
    link_match = re.match(r"^LINK\s+(\d{6})$", text, re.IGNORECASE)
    if link_match:
        code_str = link_match.group(1)
        code_hash = hashlib.sha256(code_str.encode("utf-8")).hexdigest()
        now = datetime.utcnow()

        link_code = db.query(WhatsAppLinkCode).filter(
            WhatsAppLinkCode.code_hash == code_hash,
            WhatsAppLinkCode.used_at.is_(None),
            WhatsAppLinkCode.expires_at > now,
            WhatsAppLinkCode.attempts < 5
        ).first()

        if not link_code:
            return "That code is invalid or expired. Generate a new one from the website."

        user = db.query(User).filter(User.id == link_code.user_id).first()
        if not user:
            return "That code is invalid or expired. Generate a new one from the website."

        # Mark code as used
        link_code.used_at = now

        # Revoke any other active UserPhoneLink with the same jid OR the same user_id
        other_links = db.query(UserPhoneLink).filter(
            or_(
                UserPhoneLink.user_id == user.id,
                UserPhoneLink.wa_jid == jid
            ),
            UserPhoneLink.status == "active"
        ).all()
        for link in other_links:
            link.status = "revoked"

        # Update existing record for this JID or create new active record
        existing_jid_link = db.query(UserPhoneLink).filter(UserPhoneLink.wa_jid == jid).first()
        if existing_jid_link:
            existing_jid_link.user_id = user.id
            existing_jid_link.tenant_id = user.tenant_id
            existing_jid_link.wa_display_name = push_name
            existing_jid_link.status = "active"
            existing_jid_link.verified_at = now
        else:
            new_link = UserPhoneLink(
                user_id=user.id,
                tenant_id=user.tenant_id,
                wa_jid=jid,
                wa_display_name=push_name,
                status="active",
                verified_at=now,
                created_at=now
            )
            db.add(new_link)

        log_access(db, user, "whatsapp_link", "whatsapp", detail=None, channel="whatsapp")
        db.commit()

        user_name = user.display_name or user.email
        return f"Linked to {user_name} ✅. Ask me anything about your company documents. Send /help for commands."

    # 2. Check for active phone link for this JID
    active_link = db.query(UserPhoneLink).filter(
        UserPhoneLink.wa_jid == jid,
        UserPhoneLink.status == "active"
    ).first()

    if not active_link:
        return "Your WhatsApp is not linked yet. Log in to the website, open Linked Devices and send the LINK code here."

    # 3. Load User and verify active status (user and tenant)
    user = db.query(User).filter(User.id == active_link.user_id).first()
    is_disabled = False
    if not user or not user.is_active:
        is_disabled = True
    elif user.tenant_id:
        ent = db.query(EnterpriseAdmin).filter(EnterpriseAdmin.tenant_id == str(user.tenant_id)).first()
        if ent and not ent.is_active:
            is_disabled = True

    if is_disabled:
        active_link.status = "revoked"
        db.commit()
        return "Your access has been disabled. Please contact your administrator."

    # 4. Check rate limit per user
    if is_rate_limited(str(user.id)):
        return "You're sending messages too fast. Please wait a minute."

    # 5. Check commands (case-insensitive)
    cmd = text.strip().lower()
    if cmd == "/help":
        return (
            "Available commands:\n"
            "• /help - Show this commands guide\n"
            "• /new - Reset current chat session\n"
            "• /unlink - Unlink WhatsApp from your company account\n\n"
            "Or ask any question about your company documents!"
        )
    elif cmd == "/new":
        reset_session(str(user.id))
        return "Started a new chat session."
    elif cmd == "/unlink":
        active_link.status = "revoked"
        log_access(db, user, "whatsapp_unlink", "whatsapp", detail=None, channel="whatsapp")
        db.commit()
        return "Your WhatsApp account has been unlinked."

    # 6. Question processing (truncate to 4000 chars; ignore if under 2 chars)
    if len(text) < 2:
        return None

    question = text[:4000]

    # 7. RAG query execution inside try/except
    try:
        sess_id = get_session_id(str(user.id))
        eff_tenant = str(user.tenant_id or settings.default_tenant_id)

        raw_chunks = retrieve_authorized_chunks(
            question=question,
            db=db,
            user=user,
            top_k=5,
            document_id=None,
            tenant_id=eff_tenant
        )
        context_text, citations = format_context_prompt(raw_chunks)

        if not citations:
            reply_text = "I couldn't find that in the documents you have access to."
            citations_data = []
            retrieved_doc_ids = []
            answer = reply_text
        else:
            answer = generate_answer(question, citations)
            reply_text = format_whatsapp_reply(answer, citations)
            citations_data = [c.model_dump() for c in citations]
            retrieved_doc_ids = list({str(c.document_id) for c in citations})

        # Save QueryLog scoped to tenant
        log = QueryLog(
            tenant_id=eff_tenant,
            user_id=user.id,
            team_id=None,
            session_id=sess_id,
            query=question,
            response=reply_text,
            retrieved_document_ids=json.dumps(retrieved_doc_ids),
            citations_json=json.dumps(citations_data),
            channel="whatsapp"
        )
        db.add(log)
        db.commit()
        db.refresh(log)

        log_access(db, user, "whatsapp_ask", "knowledge_base", str(log.id), question[:250], channel="whatsapp")
        db.commit()

        return reply_text
    except Exception:
        logger.exception("Error processing WhatsApp query")
        return "Something went wrong, please try again."
