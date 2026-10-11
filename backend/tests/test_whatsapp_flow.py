import hashlib
import hmac
import uuid
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import settings
from app.core.database import Base, get_db
from app.main import app
from app.models import User, UserPhoneLink, WhatsAppLinkCode
from app.routers.whatsapp import _clear_seen_messages
from app.services.whatsapp_service import (
    _clear_rate_limits,
    _clear_sessions,
    handle_inbound,
)


@pytest.fixture(scope="module")
def test_db_setup():
    # In-memory SQLite with StaticPool so all connections share the DB
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    yield TestingSessionLocal, engine

    app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=engine)


@pytest.fixture
def db(test_db_setup):
    TestingSessionLocal, _ = test_db_setup
    session = TestingSessionLocal()
    _clear_rate_limits()
    _clear_sessions()
    _clear_seen_messages()
    yield session
    session.close()


@pytest.fixture
def test_user(db):
    user = User(
        id=uuid.uuid4(),
        email=f"test_{uuid.uuid4().hex[:6]}@example.com",
        display_name="Alice WhatsApp",
        role="employee",
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@pytest.fixture
def client(test_db_setup):
    return TestClient(app)


def test_link_code_success_direct(db, test_user):
    """Test linking succeeds with valid 6-digit code via handle_inbound directly."""
    code = "123456"
    code_hash = hashlib.sha256(code.encode("utf-8")).hexdigest()
    expires_at = datetime.utcnow() + timedelta(minutes=10)

    link_code = WhatsAppLinkCode(
        user_id=test_user.id,
        tenant_id=test_user.tenant_id,
        code_hash=code_hash,
        expires_at=expires_at,
        attempts=0,
    )
    db.add(link_code)
    db.commit()

    jid = "1234567890@s.whatsapp.net"
    reply = handle_inbound(
        db=db,
        wa_message_id="msg-001",
        jid=jid,
        push_name="Alice",
        text=f"LINK {code}",
    )

    assert reply is not None
    assert "Linked to Alice WhatsApp ✅" in reply
    assert "Ask me anything" in reply

    # Check link is active in DB
    phone_link = db.query(UserPhoneLink).filter(UserPhoneLink.wa_jid == jid).first()
    assert phone_link is not None
    assert phone_link.status == "active"
    assert phone_link.user_id == test_user.id
    assert phone_link.wa_display_name == "Alice"

    # Check code marked as used
    db.refresh(link_code)
    assert link_code.used_at is not None


def test_wrong_code_fails(db, test_user):
    """Test invalid link code replies with error message and does not link."""
    jid = "9998887770@s.whatsapp.net"
    reply = handle_inbound(
        db=db,
        wa_message_id="msg-wrong",
        jid=jid,
        push_name="Hacker",
        text="LINK 999999",
    )

    assert reply == "That code is invalid or expired. Generate a new one from the website."
    phone_link = db.query(UserPhoneLink).filter(UserPhoneLink.wa_jid == jid).first()
    assert phone_link is None


def test_expired_code_fails(db, test_user):
    """Test expired link code fails."""
    code = "654321"
    code_hash = hashlib.sha256(code.encode("utf-8")).hexdigest()
    # Expired 5 minutes ago
    expires_at = datetime.utcnow() - timedelta(minutes=5)

    link_code = WhatsAppLinkCode(
        user_id=test_user.id,
        tenant_id=test_user.tenant_id,
        code_hash=code_hash,
        expires_at=expires_at,
        attempts=0,
    )
    db.add(link_code)
    db.commit()

    jid = "5555555555@s.whatsapp.net"
    reply = handle_inbound(
        db=db,
        wa_message_id="msg-expired",
        jid=jid,
        push_name="Late Alice",
        text=f"LINK {code}",
    )

    assert reply == "That code is invalid or expired. Generate a new one from the website."
    phone_link = db.query(UserPhoneLink).filter(UserPhoneLink.wa_jid == jid).first()
    assert phone_link is None


def test_unknown_jid_gets_not_linked_reply(db):
    """Test unlinked JID asking questions gets 'not linked' message and no data leak."""
    jid = "unknown_user@s.whatsapp.net"
    reply = handle_inbound(
        db=db,
        wa_message_id="msg-unknown",
        jid=jid,
        push_name="Stranger",
        text="What are our confidential revenues?",
    )

    assert reply == "Your WhatsApp is not linked yet. Log in to the website, open Linked Devices and send the LINK code here."


def test_rate_limit_triggers_on_11th_message(db, test_user):
    """Test that after 10 messages within 60s, the 11th message triggers the rate limit message."""
    jid = "ratelimit_user@s.whatsapp.net"
    link = UserPhoneLink(
        user_id=test_user.id,
        tenant_id=test_user.tenant_id,
        wa_jid=jid,
        wa_display_name="Fast Sender",
        status="active",
        verified_at=datetime.utcnow(),
    )
    db.add(link)
    db.commit()

    _clear_rate_limits()

    # Send 10 commands (e.g. /help)
    for i in range(10):
        reply = handle_inbound(
            db=db,
            wa_message_id=f"rl-msg-{i}",
            jid=jid,
            push_name="Fast Sender",
            text="/help",
        )
        assert reply is not None
        assert "Available commands" in reply

    # 11th message must trigger rate limit
    reply_11 = handle_inbound(
        db=db,
        wa_message_id="rl-msg-11",
        jid=jid,
        push_name="Fast Sender",
        text="/help",
    )
    assert reply_11 == "You're sending messages too fast. Please wait a minute."


def test_internal_endpoint_requires_secret(client):
    """Test POST /api/internal/whatsapp/inbound returns 401 without valid secret header."""
    payload = {
        "wa_message_id": "test-sec-1",
        "jid": "1234@s.whatsapp.net",
        "push_name": "Test",
        "text": "Hello",
    }

    # 1. No secret header
    resp = client.post("/api/internal/whatsapp/inbound", json=payload)
    assert resp.status_code == 401

    # 2. Wrong secret header
    resp = client.post(
        "/api/internal/whatsapp/inbound",
        json=payload,
        headers={"x-gateway-secret": "incorrect-secret-value"},
    )
    assert resp.status_code == 401

    # 3. Correct secret header
    resp = client.post(
        "/api/internal/whatsapp/inbound",
        json=payload,
        headers={"x-gateway-secret": settings.whatsapp_gateway_secret},
    )
    assert resp.status_code == 200
    assert "reply" in resp.json()


def test_internal_endpoint_deduplication(client):
    """Test duplicate wa_message_id returns {"reply": null}."""
    msg_id = f"dedupe-{uuid.uuid4().hex[:8]}"
    payload = {
        "wa_message_id": msg_id,
        "jid": "unlinked@s.whatsapp.net",
        "push_name": "Tester",
        "text": "Hello there",
    }

    # First call: processed
    resp1 = client.post(
        "/api/internal/whatsapp/inbound",
        json=payload,
        headers={"x-gateway-secret": settings.whatsapp_gateway_secret},
    )
    assert resp1.status_code == 200
    assert resp1.json()["reply"] is not None

    # Second call with same message ID: deduped
    resp2 = client.post(
        "/api/internal/whatsapp/inbound",
        json=payload,
        headers={"x-gateway-secret": settings.whatsapp_gateway_secret},
    )
    assert resp2.status_code == 200
    assert resp2.json()["reply"] is None


def test_commands_help_new_unlink(db, test_user):
    """Test /help, /new, and /unlink commands."""
    jid = "cmd_user@s.whatsapp.net"
    link = UserPhoneLink(
        user_id=test_user.id,
        tenant_id=test_user.tenant_id,
        wa_jid=jid,
        wa_display_name="Command Tester",
        status="active",
        verified_at=datetime.utcnow(),
    )
    db.add(link)
    db.commit()

    # /help
    reply_help = handle_inbound(db, "cmd-1", jid, "Tester", "/help")
    assert reply_help is not None
    assert "/help" in reply_help and "/new" in reply_help and "/unlink" in reply_help

    # /new
    reply_new = handle_inbound(db, "cmd-2", jid, "Tester", "/new")
    assert reply_new is not None
    assert "Started a new chat session." in reply_new

    # /unlink
    reply_unlink = handle_inbound(db, "cmd-3", jid, "Tester", "/unlink")
    assert reply_unlink is not None
    assert "unlinked" in reply_unlink

    # Verify link revoked
    db.refresh(link)
    assert link.status == "revoked"


def test_deactivated_user_revoked(db, test_user):
    """Test deactivated user message revokes link and responds with access disabled notice."""
    jid = "deact_user@s.whatsapp.net"
    link = UserPhoneLink(
        user_id=test_user.id,
        tenant_id=test_user.tenant_id,
        wa_jid=jid,
        wa_display_name="Deactivated",
        status="active",
        verified_at=datetime.utcnow(),
    )
    db.add(link)
    db.commit()

    # Deactivate user
    test_user.is_active = False
    db.commit()

    reply = handle_inbound(db, "deact-msg", jid, "Deactivated", "Hello?")
    assert reply == "Your access has been disabled. Please contact your administrator."

    db.refresh(link)
    assert link.status == "revoked"


def test_whatsapp_reply_formatting():
    """Test WhatsApp formatting helper: markdown bold, sources format, and 3500-char truncation."""
    from app.schemas import Citation
    from app.services.whatsapp_service import format_whatsapp_reply

    # 1. No citations
    assert format_whatsapp_reply("Some answer", []) == "I couldn't find that in the documents you have access to."

    # 2. Citations with bold markdown
    c1 = Citation(
        document_id="doc-1",
        document_name="Handbook.pdf",
        chunk_index=0,
        text="Sample text",
        score=0.9,
        page_start=1,
        page_end=3,
    )
    c2 = Citation(
        document_id="doc-2",
        document_name="FAQ.docx",
        chunk_index=1,
        text="Sample text 2",
        score=0.85,
        page_start=5,
        page_end=5,
    )
    c3 = Citation(
        document_id="doc-3",
        document_name="Policy.txt",
        chunk_index=2,
        text="Sample text 3",
        score=0.8,
        page_start=None,
        page_end=None,
    )

    ans = "This is **bold text** and another **important** point."
    formatted = format_whatsapp_reply(ans, [c1, c2, c3])

    assert "*bold text*" in formatted
    assert "**" not in formatted
    assert "Sources:" in formatted
    assert "[1] Handbook.pdf, p.1-3" in formatted
    assert "[2] FAQ.docx, p.5" in formatted
    assert "[3] Policy.txt" in formatted

    # 3. Truncation when exceeding 3500 chars (preserves sentence boundary and Sources block)
    long_ans = "Sentence one is complete. " * 200
    formatted_long = format_whatsapp_reply(long_ans, [c1])
    assert len(formatted_long) <= 3500
    assert "…" in formatted_long
    assert "[1] Handbook.pdf, p.1-3" in formatted_long


def test_whatsapp_cleanup_helpers():
    """Test WhatsApp text cleanup: headers, bold, bullets, and 3+ blank lines collapse."""
    from app.services.whatsapp_service import clean_whatsapp_text

    raw = (
        "# Main Title\n"
        "## Sub Heading\n"
        "### Section Header\n"
        "#### Detail Header\n\n"
        "Here is **very important** text.\n"
        "* Bullet point one\n"
        "- Bullet point two\n"
        "  * Indented bullet\n"
        "  - Indented dash\n\n\n\n"
        "Next paragraph after 3 blank lines."
    )

    cleaned = clean_whatsapp_text(raw)

    # Headers converted to *Header*
    assert "*Main Title*" in cleaned
    assert "*Sub Heading*" in cleaned
    assert "*Section Header*" in cleaned
    assert "*Detail Header*" in cleaned
    assert "#" not in cleaned

    # Bold converted from ** to *
    assert "*very important*" in cleaned
    assert "**" not in cleaned

    # Bullets converted from * and - to •
    assert "• Bullet point one" in cleaned
    assert "• Bullet point two" in cleaned
    assert "  • Indented bullet" in cleaned
    assert "  • Indented dash" in cleaned

    # 3+ blank lines collapsed to 1 blank line (\n\n)
    assert "\n\n\n" not in cleaned
    assert "Indented dash\n\nNext paragraph" in cleaned


def test_whatsapp_sources_inline_numbering_matching():
    """Test sources list matches inline [Source N] numbering and filters invalid references."""
    from app.schemas import Citation
    from app.services.whatsapp_service import format_whatsapp_reply

    c1 = Citation(document_id="d1", document_name="Doc1.pdf", chunk_index=0, text="t1", score=0.9, page_start=1, page_end=1)
    c2 = Citation(document_id="d2", document_name="Doc2.pdf", chunk_index=1, text="t2", score=0.8, page_start=5, page_end=8)
    c3 = Citation(document_id="d3", document_name="Doc3.pdf", chunk_index=2, text="t3", score=0.7, page_start=None, page_end=None)
    c4 = Citation(document_id="d4", document_name="Doc4.pdf", chunk_index=3, text="t4", score=0.6, page_start=2, page_end=2)

    # 1. Answer cites only [Source 2] and [Source 4]
    ans_specific = "According to [Source 2], the leave applies. Also check [Source 4]."
    reply_specific = format_whatsapp_reply(ans_specific, [c1, c2, c3, c4])

    assert "[2] Doc2.pdf, p.5-8" in reply_specific
    assert "[4] Doc4.pdf, p.2" in reply_specific
    assert "[1] Doc1.pdf" not in reply_specific
    assert "[3] Doc3.pdf" not in reply_specific

    # 2. Answer cites non-existent [Source 99] and [Source 1]
    ans_invalid = "Facts from [Source 1] and [Source 99]."
    reply_invalid = format_whatsapp_reply(ans_invalid, [c1, c2])

    assert "[1] Doc1.pdf, p.1" in reply_invalid
    assert "[99]" not in reply_invalid

    # 3. Answer cites no sources: falls back to first 3 citations
    ans_none = "General answer without any inline source brackets."
    reply_none = format_whatsapp_reply(ans_none, [c1, c2, c3, c4])

    assert "[1] Doc1.pdf, p.1" in reply_none
    assert "[2] Doc2.pdf, p.5-8" in reply_none
    assert "[3] Doc3.pdf" in reply_none
    assert "[4] Doc4.pdf" not in reply_none


def test_whatsapp_truncation_boundaries():
    """Test truncation cuts at sentence or paragraph boundary, not mid-word, preserving Sources."""
    from app.schemas import Citation
    from app.services.whatsapp_service import format_whatsapp_reply

    c = Citation(document_id="d1", document_name="DocLong.pdf", chunk_index=0, text="txt", score=0.9, page_start=1, page_end=2)

    # Build an answer of ~4000 characters composed of clear sentences
    sentence = "Atlas Enterprise provides comprehensive leave benefits to all eligible staff members. "
    long_answer = sentence * 45  # ~3960 chars

    reply = format_whatsapp_reply(long_answer, [c])

    assert len(reply) <= 3500
    assert reply.endswith("Sources:\n[1] DocLong.pdf, p.1-2")

    # The answer portion right before \n\nSources: must end with … following a sentence boundary
    answer_part = reply.split("\n\nSources:")[0]
    assert answer_part.endswith("staff members.…")


