import logging
import re
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import jira_configured, settings
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import JiraIssueLink, Team, TeamChatMessage, TeamMember, User
from app.routers.teams import _is_system_admin, _to_uuid, _user_in_team
from app.schemas import JiraIssueOut, JiraSettingsUpdate, JiraStatusOut
from app.services.access import log_access
from app.services.jira_service import JiraError, create_issue, find_account_id

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/jira", tags=["jira"])

PROJECT_KEY_REGEX = re.compile(r"^[A-Z][A-Z0-9_]{1,49}$")


def _is_team_lead_or_admin(db: Session, team: Team, user: User) -> bool:
    if _is_system_admin(user):
        return True
    user_role = user.role.value if hasattr(user.role, "value") else str(user.role or "employee").lower()
    if user_role == "admin" or getattr(user, "rank_level", 5) <= 2:
        return True
    if team.created_by_id == user.id:
        return True
    member = db.query(TeamMember).filter(TeamMember.team_id == team.id, TeamMember.user_id == user.id).first()
    return member is not None and getattr(member, "role_in_team", "member") == "lead"


def _format_time_am_pm(t_str: str) -> str:
    try:
        parts = t_str.split(":")
        h = int(parts[0])
        m = int(parts[1])
        dt = datetime(2000, 1, 1, h, m)
        return dt.strftime("%I:%M %p").lstrip("0")
    except Exception:
        return t_str


def _link_to_jira_out(link: JiraIssueLink, assignee_name: str | None = None) -> JiraIssueOut:
    return JiraIssueOut(
        id=link.id,
        status=link.status,
        intent=link.intent,
        title=link.title,
        assignee_hint=link.assignee_hint,
        assignee_email=link.assignee_email,
        assignee_name=assignee_name,
        due_date=link.due_date,
        due_time=link.due_time,
        jira_key=link.jira_key,
        jira_url=link.jira_url,
        assigned_in_jira=link.assigned_in_jira,
        error_message=link.error_message
    )


@router.get("/status", response_model=JiraStatusOut)
def get_jira_status(current_user: User = Depends(get_current_user)):
    """
    Returns public Jira integration status and default settings.
    Never exposes API token or credentials.
    """
    return JiraStatusOut(
        configured=jira_configured(),
        base_url=settings.jira_base_url or "",
        default_project_key=settings.jira_default_project_key or "",
        default_issue_type=settings.jira_default_issue_type or "Task"
    )


@router.get("/teams/{team_id}/settings")
def get_team_jira_settings(
    team_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")
    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        if not _user_in_team(db, team.id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: only team members can view Jira settings")
    return {
        "status": "ok",
        "team_id": team.id,
        "jira_project_key": team.jira_project_key
    }


@router.patch("/teams/{team_id}/settings")
def update_team_jira_settings(
    team_id: int,
    payload: JiraSettingsUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Updates Jira project key for a specific team.
    Allowed for team lead, creator, or admin/executive users of the same tenant.
    """
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        if not _is_team_lead_or_admin(db, team, current_user):
            raise HTTPException(status_code=403, detail="Access denied: only team leads or admins can configure Jira settings")

    key_val = payload.jira_project_key
    if key_val is not None and key_val.strip():
        clean_key = key_val.strip().upper()
        if not PROJECT_KEY_REGEX.match(clean_key):
            raise HTTPException(
                status_code=400,
                detail="Invalid Jira project key format. Must start with an uppercase letter and contain 2-50 uppercase letters, numbers, or underscores (e.g. ATLAS, PROJ_1)."
            )
        team.jira_project_key = clean_key
    else:
        team.jira_project_key = None

    log_access(
        db=db,
        user=current_user,
        action="jira_settings_updated",
        resource_type="team",
        resource_id=str(team_id),
        detail=f"Jira project key set to '{team.jira_project_key}' for team '{team.name}'",
        channel="web"
    )
    db.commit()
    db.refresh(team)

    return {
        "status": "ok",
        "team_id": team.id,
        "jira_project_key": team.jira_project_key
    }


@router.get("/teams/{team_id}/issues", response_model=list[JiraIssueOut])
def get_team_jira_issues(
    team_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Returns JiraIssueLink rows with status 'created' for this team, newest first.
    Team members and enterprise admins only.
    """
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        if not _user_in_team(db, team_id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: you are not a member of this team")

    links = (
        db.query(JiraIssueLink)
        .filter(JiraIssueLink.team_id == team_id, JiraIssueLink.status == "created")
        .order_by(JiraIssueLink.created_at.desc())
        .all()
    )

    assignee_ids = [l.assignee_user_id for l in links if l.assignee_user_id]
    user_map = {}
    if assignee_ids:
        users = db.query(User).filter(User.id.in_(assignee_ids)).all()
        user_map = {u.id: (u.display_name or u.email.split("@")[0]) for u in users}

    return [_link_to_jira_out(l, user_map.get(l.assignee_user_id)) for l in links]


@router.post("/suggestions/{link_id}/confirm", response_model=JiraIssueOut)
def confirm_jira_suggestion(
    link_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Confirms a Jira suggestion card and creates the real Jira Cloud issue.
    Atomically transitions status to 'creating' to avoid race conditions.
    Idempotent: if already 'created', returns the existing record.
    """
    link = db.get(JiraIssueLink, link_id)
    if not link:
        raise HTTPException(status_code=404, detail="Jira suggestion not found")

    team = db.get(Team, link.team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team for this suggestion not found")

    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        if not _user_in_team(db, team.id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: only team members can confirm suggestions")

    # Idempotency check: if already created, return immediately
    if link.status == "created":
        assignee_name = None
        if link.assignee_user_id:
            u = db.get(User, link.assignee_user_id)
            if u:
                assignee_name = u.display_name or u.email.split("@")[0]
        return _link_to_jira_out(link, assignee_name)

    # Atomic transition from pending/failed -> creating
    result = db.execute(
        text("UPDATE jira_issue_links SET status = 'creating' WHERE id = :id AND status IN ('pending', 'failed')"),
        {"id": link_id}
    )
    db.commit()

    if result.rowcount == 0:
        db.refresh(link)
        if link.status == "created":
            return _link_to_jira_out(link)
        if link.status == "creating":
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Jira issue creation is already in progress.")
        raise HTTPException(status_code=400, detail=f"Suggestion cannot be confirmed in current status '{link.status}'.")

    # Refreshed link now in 'creating' status
    db.refresh(link)

    # Determine project key
    project_key = (team.jira_project_key or settings.jira_default_project_key or "").strip().upper()
    if not project_key:
        link.status = "failed"
        link.error_message = "No Jira project key configured. Please configure a project key in team settings."
        db.commit()
        raise HTTPException(
            status_code=400,
            detail="No Jira project key configured. Please set a project key for this team or configure JIRA_DEFAULT_PROJECT_KEY."
        )

    # Resolve Jira account id if assignee exists
    account_id = None
    if link.assignee_email or link.assignee_hint:
        try:
            account_id = find_account_id(email=link.assignee_email, name_hint=link.assignee_hint)
        except Exception as exc:
            logger.warning(f"Error finding Jira account id: {exc}")

    # Build Summary
    if link.intent == "meeting" and link.due_time:
        formatted_time = _format_time_am_pm(link.due_time)
        summary = f"[Meeting] {link.title} - {formatted_time} IST"
    elif link.intent == "meeting":
        summary = f"[Meeting] {link.title}"
    else:
        summary = link.title

    # Build Labels
    labels = ["atlas-chat"]
    if link.intent == "meeting":
        labels.append("meeting")
    elif link.intent == "deadline":
        labels.append("deadline")

    # Build Description text
    msg = db.get(TeamChatMessage, link.message_id)
    orig_msg_text = msg.message if msg else link.title
    sender_email = msg.user_email if msg else current_user.email

    desc_lines = [
        f"Original Message: {orig_msg_text}",
        f"Requested by: {sender_email} in team '{team.name}' (Project: {team.project_name}) via Atlas Team Chat",
    ]
    if link.due_date:
        desc_lines.append(f"Due Date: {link.due_date}")
    if link.due_time:
        desc_lines.append(f"Scheduled Time: {link.due_time} IST")
    if link.assignee_hint and not account_id:
        desc_lines.append(f"Assignee Mentioned: {link.assignee_hint} (could not automatically map to a Jira account)")

    desc_text = "\n".join(desc_lines)

    try:
        jira_res = create_issue(
            project_key=project_key,
            summary=summary,
            description_text=desc_text,
            due_date=link.due_date,
            labels=labels,
            assignee_account_id=account_id
        )

        link.status = "created"
        link.jira_key = jira_res["key"]
        link.jira_url = jira_res["url"]
        link.assigned_in_jira = bool(account_id)
        link.created_by_id = current_user.id
        link.error_message = None

        log_access(
            db=db,
            user=current_user,
            action="jira_issue_created",
            resource_type="jira_issue",
            resource_id=jira_res["key"],
            detail=f"Created Jira issue {jira_res['key']} for team '{team.name}'",
            channel="web"
        )
        db.commit()
        db.refresh(link)

        assignee_name = None
        if link.assignee_user_id:
            u = db.get(User, link.assignee_user_id)
            if u:
                assignee_name = u.display_name or u.email.split("@")[0]

        return _link_to_jira_out(link, assignee_name)

    except JiraError as j_err:
        logger.warning(f"Jira issue creation failed for suggestion {link_id}: {j_err}")
        link.status = "failed"
        link.error_message = str(j_err)
        db.commit()
        raise HTTPException(status_code=502, detail=str(j_err))
    except Exception as exc:
        logger.error(f"Unexpected error creating Jira issue: {exc}", exc_info=True)
        link.status = "failed"
        link.error_message = "Unexpected error while communicating with Jira."
        db.commit()
        raise HTTPException(status_code=502, detail="Failed to create Jira issue due to an internal error.")


@router.post("/suggestions/{link_id}/dismiss")
def dismiss_jira_suggestion(
    link_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Dismisses a Jira suggestion card. Members only.
    """
    link = db.get(JiraIssueLink, link_id)
    if not link:
        raise HTTPException(status_code=404, detail="Jira suggestion not found")

    team = db.get(Team, link.team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        if not _user_in_team(db, team.id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: only team members can dismiss suggestions")

    link.status = "dismissed"
    log_access(
        db=db,
        user=current_user,
        action="jira_suggestion_dismissed",
        resource_type="jira_issue",
        resource_id=str(link.id),
        detail=f"Dismissed suggestion '{link.title}' for team '{team.name}'",
        channel="web"
    )
    db.commit()

    return {
        "status": "dismissed",
        "id": link.id
    }
