import hashlib
import hmac
import secrets
import threading
from collections import OrderedDict
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import current_user
from app.models import User, UserPhoneLink, WhatsAppLinkCode
from app.services.access import log_access
from app.services.whatsapp_service import handle_inbound

router = APIRouter(prefix="/api/whatsapp", tags=["whatsapp"])

internal_router = APIRouter(
    prefix="/api/internal/whatsapp",
    tags=["whatsapp-internal"],
    include_in_schema=False
)



class WhatsAppLinkStartResponse(BaseModel):
    code: str
    expires_at: str
    bot_number: str
    instruction: str


class WhatsAppLinkStatusResponse(BaseModel):
    linked: bool
    wa_display_name: str | None = None
    verified_at: str | None = None
    pending_code_expires_at: str | None = None


class WhatsAppUnlinkResponse(BaseModel):
    ok: bool


def _format_utc_iso(dt: datetime | None) -> str | None:
    if not dt:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


@router.post("/link/start", response_model=WhatsAppLinkStartResponse)
def start_whatsapp_link(
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """
    Generate a 6-digit linking code for the current user to send to the WhatsApp bot.
    Expires any previous unused codes for this user.
    """
    now = datetime.utcnow()

    # Expire/delete previous unused codes for this user
    db.query(WhatsAppLinkCode).filter(
        WhatsAppLinkCode.user_id == user.id,
        WhatsAppLinkCode.used_at.is_(None)
    ).delete()
    db.commit()

    # Generate random 6-digit code, retrying until hash does not collide with any active code
    while True:
        code_int = secrets.randbelow(900000) + 100000
        code = str(code_int)
        code_hash = hashlib.sha256(code.encode("utf-8")).hexdigest()

        active_collision = db.query(WhatsAppLinkCode).filter(
            WhatsAppLinkCode.code_hash == code_hash,
            WhatsAppLinkCode.used_at.is_(None),
            WhatsAppLinkCode.expires_at > now
        ).first()

        if not active_collision:
            break

    expires_at = now + timedelta(minutes=10)

    link_code = WhatsAppLinkCode(
        user_id=user.id,
        tenant_id=user.tenant_id,
        code_hash=code_hash,
        expires_at=expires_at,
        attempts=0,
        created_at=now
    )
    db.add(link_code)
    db.commit()

    log_access(db, user, "whatsapp_link_start", "whatsapp", detail=None, channel="web")
    db.commit()

    bot_number_clean = settings.whatsapp_bot_number.strip().lstrip("+")
    bot_display = f"+{bot_number_clean}" if bot_number_clean else ""
    instruction = f"Send LINK {code} to {bot_display} on WhatsApp"

    return WhatsAppLinkStartResponse(
        code=code,
        expires_at=_format_utc_iso(expires_at),
        bot_number=settings.whatsapp_bot_number,
        instruction=instruction
    )


@router.get("/link/status", response_model=WhatsAppLinkStatusResponse)
def get_whatsapp_link_status(
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """
    Check if current user is linked to a WhatsApp number, and return pending code expiry if any.
    """
    now = datetime.utcnow()

    active_link = db.query(UserPhoneLink).filter(
        UserPhoneLink.user_id == user.id,
        UserPhoneLink.status == "active"
    ).order_by(UserPhoneLink.created_at.desc()).first()

    pending_code = db.query(WhatsAppLinkCode).filter(
        WhatsAppLinkCode.user_id == user.id,
        WhatsAppLinkCode.used_at.is_(None),
        WhatsAppLinkCode.expires_at > now
    ).order_by(WhatsAppLinkCode.expires_at.desc()).first()

    return WhatsAppLinkStatusResponse(
        linked=active_link is not None,
        wa_display_name=active_link.wa_display_name if active_link else None,
        verified_at=_format_utc_iso(active_link.verified_at) if (active_link and active_link.verified_at) else None,
        pending_code_expires_at=_format_utc_iso(pending_code.expires_at) if pending_code else None
    )


@router.delete("/link", response_model=WhatsAppUnlinkResponse)
def unlink_whatsapp(
    db: Session = Depends(get_db),
    user: User = Depends(current_user)
):
    """
    Revoke all active WhatsApp links for current user.
    """
    links = db.query(UserPhoneLink).filter(
        UserPhoneLink.user_id == user.id,
        UserPhoneLink.status == "active"
    ).all()

    for link in links:
        link.status = "revoked"

    log_access(db, user, "whatsapp_unlink", "whatsapp", detail=None, channel="web")
    db.commit()

    return WhatsAppUnlinkResponse(ok=True)


# ---------------------------------------------------------------------------
# Internal Gateway Inbound Endpoint
# ---------------------------------------------------------------------------
_dedupe_lock = threading.Lock()
_seen_messages: OrderedDict[str, None] = OrderedDict()
MAX_SEEN_MESSAGES = 2000


def _is_duplicate_message(msg_id: str) -> bool:
    with _dedupe_lock:
        if msg_id in _seen_messages:
            return True
        _seen_messages[msg_id] = None
        if len(_seen_messages) > MAX_SEEN_MESSAGES:
            _seen_messages.popitem(last=False)
        return False


def _clear_seen_messages() -> None:
    with _dedupe_lock:
        _seen_messages.clear()


class WhatsAppInboundRequest(BaseModel):
    wa_message_id: str
    jid: str
    push_name: str | None = None
    text: str


class WhatsAppInboundResponse(BaseModel):
    reply: str | None = None


@internal_router.post("/inbound", response_model=WhatsAppInboundResponse)
def inbound_whatsapp_message(
    payload: WhatsAppInboundRequest,
    db: Session = Depends(get_db),
    x_gateway_secret: str | None = Header(None, alias="x-gateway-secret")
):
    """
    Internal endpoint called by the WhatsApp gateway.
    Requires valid x-gateway-secret header matching settings.whatsapp_gateway_secret.
    Dedupes wa_message_id in memory (returns {"reply": null} for duplicates).
    Dispatches to whatsapp_service.handle_inbound.
    """
    configured_secret = (settings.whatsapp_gateway_secret or "").strip()
    if not configured_secret or not x_gateway_secret:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")

    if not hmac.compare_digest(x_gateway_secret.strip().encode("utf-8"), configured_secret.encode("utf-8")):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")

    # In-memory deduplication (ordered set capped at 2000)
    if _is_duplicate_message(payload.wa_message_id):
        return WhatsAppInboundResponse(reply=None)

    reply = handle_inbound(
        db=db,
        wa_message_id=payload.wa_message_id,
        jid=payload.jid,
        push_name=payload.push_name,
        text=payload.text
    )

    return WhatsAppInboundResponse(reply=reply)

