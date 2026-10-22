import json
import logging
import re
from datetime import date, datetime, timedelta
from typing import Literal
from zoneinfo import ZoneInfo
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.config import jira_configured, settings
from app.core.database import SessionLocal
from app.models import JiraIssueLink, Team, TeamChatMessage, TeamMember, User
from app.services.embedding_service import get_genai_client

logger = logging.getLogger(__name__)


class WorkItemExtraction(BaseModel):
    intent: Literal["task", "meeting", "deadline", "none"] = "none"
    title: str | None = None
    assignee_hint: str | None = None
    due_date: str | None = None  # YYYY-MM-DD
    due_time: str | None = None  # HH:MM 24h
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)


def extract_work_item(
    message_text: str,
    sender_name_or_email: str,
    member_names: list[str],
    now_ist: datetime
) -> WorkItemExtraction | None:
    """
    Extracts actionable work items (task, deadline, or meeting) from team messages
    using Gemini with structured JSON output.
    """
    if not message_text or len(message_text.strip()) < 3:
        return None

    if not settings.gemini_api_key:
        logger.warning("Gemini API key is not configured for work item extraction.")
        return None

    date_str = now_ist.strftime("%Y-%m-%d")
    time_str = now_ist.strftime("%H:%M")
    day_str = now_ist.strftime("%A")
    members_str = ", ".join(member_names) if member_names else "None listed"

    prompt = f"""You are an enterprise AI assistant analyzing internal team messages for work items to track in Jira.

CURRENT CONTEXT (Asia/Kolkata / IST):
- Reference Date: {date_str} ({day_str})
- Reference Time: {time_str} IST
- Message Sender: {sender_name_or_email}
- Team Members: {members_str}

MESSAGE TO ANALYZE:
\"\"\"{message_text}\"\"\"

EXTRACTION RULES:
1. Intent Classification:
   - "task": A concrete action item someone must do (e.g. "Rahul, finish the login API", "Need to write tests", "Please review PR 42").
   - "meeting": A scheduled meeting, call, demo, or sync (e.g. "meeting tomorrow at 2PM", "let's sync at 4:30pm").
   - "deadline": An explicit due date or milestone (e.g. "Release is due next Friday", "Feature freeze tomorrow").
   - "none": Greetings ("good morning"), general questions, opinions, jokes, status chatter, or work already finished ("I deployed the fix").
2. Relative Dates & Deadlines:
   - Resolve all relative dates against Reference Date ({date_str}, {day_str}):
     * "today" / "EOD" -> {date_str}
     * "tomorrow" -> {(now_ist.date() + timedelta(days=1)).isoformat()}
     * "in 2 days" -> {(now_ist.date() + timedelta(days=2)).isoformat()}
     * "by Friday" -> next upcoming Friday
     * "next Monday" -> next upcoming Monday
   - Format: "YYYY-MM-DD" or null.
3. Times:
   - If a meeting or deadline includes a time of day, output 24-hour "HH:MM" (e.g. "2PM" -> "14:00", "4:30pm" -> "16:30"). Otherwise null.
4. Title:
   - Short, concise, imperative title (max 80 chars), e.g. "Finish the login API", "Team sync meeting".
5. Assignee:
   - The person assigned or requested to do the task. If sender says "I will..." or "I'm on it", output "me". If nobody named, output null.
6. Confidence:
   - Float 0.0 to 1.0 representing certainty that this is an actionable work item.
"""

    candidate_models = []
    for m in [settings.gemini_model, "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-2.5-flash", "gemini-flash-latest"]:
        if m and m not in candidate_models:
            candidate_models.append(m)

    for model_name in candidate_models:
        try:
            from google.genai import types
            client = get_genai_client()
            cfg = types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=WorkItemExtraction,
                temperature=0.0,
            )
            response = client.models.generate_content(
                model=model_name,
                contents=prompt,
                config=cfg,
            )
            if response and response.text:
                data = json.loads(response.text)
                return WorkItemExtraction.model_validate(data)
        except Exception as exc:
            logger.warning(f"extract_work_item failed for model {model_name}: {exc}")

    return None


def resolve_assignee(db: Session, team_id: int, hint: str | None, sender_user: User) -> User | None:
    """
    Case-insensitive match of assignee hint against team members' display_name and email local-part.
    'me'/'I'/'myself' resolves to the sender.
    Ambiguous (>1 match) or 0 matches returns None.
    """
    if not hint:
        return None
    cleaned = hint.strip().lower()
    if cleaned in ("me", "i", "myself"):
        return sender_user

    members = (
        db.query(TeamMember, User)
        .join(User, TeamMember.user_id == User.id)
        .filter(TeamMember.team_id == team_id)
        .all()
    )

    matches: list[User] = []
    for tm, user in members:
        email_local = (user.email or "").split("@")[0].lower()
        disp_name = (user.display_name or "").lower().strip()
        first_name = disp_name.split()[0] if disp_name else ""

        if cleaned == email_local or (disp_name and cleaned == disp_name) or (first_name and cleaned == first_name):
            matches.append(user)

    if len(matches) == 1:
        return matches[0]
    return None


def process_message_for_jira(message_id: int) -> None:
    """
    Background worker: analyzes a team message, extracts work items,
    and saves a pending JiraIssueLink.
    Uses its own isolated SessionLocal().
    """
    with SessionLocal() as db:
        try:
            msg = db.get(TeamChatMessage, message_id)
            if not msg:
                return

            if getattr(msg, "message_type", "ai") != "team":
                return

            if not jira_configured():
                return

            existing = db.query(JiraIssueLink).filter(JiraIssueLink.message_id == message_id).first()
            if existing:
                return

            team = db.get(Team, msg.team_id)
            if not team:
                return

            # Collect team member names for extractor
            members = (
                db.query(User)
                .join(TeamMember, TeamMember.user_id == User.id)
                .filter(TeamMember.team_id == msg.team_id)
                .all()
            )
            member_names = [
                u.display_name or u.email.split("@")[0]
                for u in members
                if (u.display_name or u.email)
            ]

            now_ist = datetime.now(ZoneInfo("Asia/Kolkata"))
            extraction = extract_work_item(
                message_text=msg.message,
                sender_name_or_email=msg.user_email,
                member_names=member_names,
                now_ist=now_ist
            )

            if not extraction:
                return

            if extraction.intent == "none":
                return

            if extraction.confidence < settings.jira_suggestion_min_confidence:
                return

            clean_title = (extraction.title or "").strip()
            if not clean_title:
                return

            # Validate due_date
            valid_due_date = None
            if extraction.due_date:
                try:
                    parsed_d = date.fromisoformat(extraction.due_date.strip())
                    cutoff = now_ist.date() - timedelta(days=1)
                    if parsed_d >= cutoff:
                        valid_due_date = parsed_d.isoformat()
                except Exception:
                    valid_due_date = None

            # Validate due_time (HH:MM)
            valid_due_time = None
            if extraction.due_time:
                t_str = extraction.due_time.strip()
                if re.match(r"^\d{2}:\d{2}$", t_str):
                    valid_due_time = t_str

            # Resolve assignee
            sender_user = db.query(User).filter(User.id == msg.user_id).first() or db.query(User).filter(User.email == msg.user_email).first()
            resolved_user = resolve_assignee(db, msg.team_id, extraction.assignee_hint, sender_user) if sender_user else None

            eff_tenant = str(team.tenant_id or (sender_user.tenant_id if sender_user else None) or settings.default_tenant_id)

            jira_link = JiraIssueLink(
                tenant_id=eff_tenant,
                team_id=msg.team_id,
                message_id=msg.id,
                intent=extraction.intent,
                title=clean_title,
                assignee_hint=extraction.assignee_hint,
                assignee_user_id=resolved_user.id if resolved_user else None,
                assignee_email=resolved_user.email if resolved_user else None,
                due_date=valid_due_date,
                due_time=valid_due_time,
                confidence=round(extraction.confidence, 2),
                status="pending",
                assigned_in_jira=False
            )
            db.add(jira_link)
            db.commit()
            logger.info(f"Created pending Jira suggestion {jira_link.id} for team message {msg.id} ('{clean_title}')")

        except Exception as exc:
            logger.warning(f"process_message_for_jira exception for message {message_id}: {exc}")
