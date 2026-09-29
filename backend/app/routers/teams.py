import json
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import AuditLog, LogSeverity, Team, TeamChatMessage, TeamMember, User
from app.schemas import Citation, TeamChatMessageOut, TeamCreate, TeamMemberAdd, TeamMemberOut, TeamOut
from app.services.llm import generate_answer
from app.services.retrieval import retrieve

router = APIRouter(prefix="/api/teams", tags=["teams"])


def _user_in_team(db: Session, team_id: int, user_id: int) -> bool:
    return db.query(TeamMember).filter(TeamMember.team_id == team_id, TeamMember.user_id == user_id).first() is not None


@router.get("", response_model=list[TeamOut])
def list_teams(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    # Admins or top-rank users see all teams; regular users see teams they belong to
    if current_user.rank_level <= 2 or current_user.role.value == "admin":
        teams = db.query(Team).order_by(Team.created_at.desc()).all()
    else:
        member_team_ids = db.query(TeamMember.team_id).filter(TeamMember.user_id == current_user.id).all()
        ids = [t[0] for t in member_team_ids]
        teams = db.query(Team).filter(Team.id.in_(ids)).order_by(Team.created_at.desc()).all()

    out = []
    for team in teams:
        members_query = db.query(TeamMember, User).join(User, TeamMember.user_id == User.id).filter(TeamMember.team_id == team.id).all()
        members_out = [
            TeamMemberOut(
                id=m.id,
                user_id=u.id,
                user_email=u.email,
                user_role_key=u.role_key or u.role.value,
                user_rank_level=u.rank_level,
                role_in_team=m.role_in_team
            ) for m, u in members_query
        ]
        out.append(TeamOut(
            id=team.id,
            name=team.name,
            project_name=team.project_name,
            description=team.description,
            created_by_id=team.created_by_id,
            created_at=team.created_at,
            members=members_out
        ))
    return out


@router.post("", response_model=TeamOut)
def create_team(payload: TeamCreate, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = Team(
        name=payload.name,
        project_name=payload.project_name,
        description=payload.description,
        created_by_id=current_user.id
    )
    db.add(team)
    db.flush()

    # Automatically add creator as team lead
    lead_member = TeamMember(team_id=team.id, user_id=current_user.id, role_in_team="lead")
    db.add(lead_member)

    db.add(AuditLog(
        user_id=current_user.id,
        action="create_team",
        resource_type="team",
        resource_id=str(team.id),
        severity=LogSeverity.INFO,
        detail=f"Created team '{team.name}' for project '{team.project_name}'"
    ))
    db.commit()
    db.refresh(team)

    return TeamOut(
        id=team.id,
        name=team.name,
        project_name=team.project_name,
        description=team.description,
        created_by_id=team.created_by_id,
        created_at=team.created_at,
        members=[TeamMemberOut(
            id=lead_member.id,
            user_id=current_user.id,
            user_email=current_user.email,
            user_role_key=current_user.role_key or current_user.role.value,
            user_rank_level=current_user.rank_level,
            role_in_team="lead"
        )]
    )


@router.post("/{team_id}/members", response_model=TeamOut)
def add_team_member(team_id: int, payload: TeamMemberAdd, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    target_user = db.get(User, payload.user_id)
    if not target_user:
        raise HTTPException(status_code=404, detail="User to add not found")

    existing = db.query(TeamMember).filter(TeamMember.team_id == team_id, TeamMember.user_id == payload.user_id).first()
    if existing:
        raise HTTPException(status_code=400, detail="User is already a member of this team")

    new_member = TeamMember(team_id=team_id, user_id=payload.user_id, role_in_team=payload.role_in_team)
    db.add(new_member)
    db.add(AuditLog(
        user_id=current_user.id,
        action="add_team_member",
        resource_type="team",
        resource_id=str(team_id),
        severity=LogSeverity.INFO,
        detail=f"Added {target_user.email} to team '{team.name}' as {payload.role_in_team}"
    ))
    db.commit()

    return list_teams(db, current_user)[0]


@router.delete("/{team_id}/members/{user_id}")
def remove_team_member(team_id: int, user_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    member = db.query(TeamMember).filter(TeamMember.team_id == team_id, TeamMember.user_id == user_id).first()
    if not member:
        raise HTTPException(status_code=404, detail="Team member not found")

    db.delete(member)
    db.add(AuditLog(
        user_id=current_user.id,
        action="remove_team_member",
        resource_type="team",
        resource_id=str(team_id),
        severity=LogSeverity.INFO,
        detail=f"Removed user ID {user_id} from team '{team.name}'"
    ))
    db.commit()
    return {"detail": "Member removed successfully"}


@router.get("/{team_id}/chat", response_model=list[TeamChatMessageOut])
def get_team_chat_history(team_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    # Check permission
    if not _user_in_team(db, team_id, current_user.id) and current_user.rank_level > 2 and current_user.role.value != "admin":
        raise HTTPException(status_code=403, detail="Access denied to team chat history")

    messages = db.query(TeamChatMessage).filter(TeamChatMessage.team_id == team_id).order_by(TeamChatMessage.created_at.asc()).limit(100).all()
    out = []
    for msg in messages:
        try:
            citations_raw = json.loads(msg.citations_json or "[]")
            citations = [Citation(**c) for c in citations_raw]
        except Exception:
            citations = []
        out.append(TeamChatMessageOut(
            id=msg.id,
            team_id=msg.team_id,
            user_id=msg.user_id,
            user_email=msg.user_email,
            message=msg.message,
            response=msg.response,
            citations=citations,
            created_at=msg.created_at
        ))
    return out


@router.post("/{team_id}/chat", response_model=TeamChatMessageOut)
def send_team_chat_message(team_id: int, payload: dict, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    message_text = payload.get("message")
    if not message_text or len(message_text.strip()) < 2:
        raise HTTPException(status_code=400, detail="Message is required")

    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    if not _user_in_team(db, team_id, current_user.id) and current_user.rank_level > 2 and current_user.role.value != "admin":
        raise HTTPException(status_code=403, detail="Not a member of this team")

    # 1. Retrieve knowledge chunks grounded for enterprise project
    citations = retrieve(question=message_text, db=db, top_k=5)
    
    # Add team project context to prompt
    prompt_with_project_context = f"[Project Scope: {team.project_name} | Team: {team.name}]\n{message_text}"
    answer = generate_answer(question=prompt_with_project_context, citations=citations)

    citations_json = json.dumps([c.model_dump() for c in citations])

    team_msg = TeamChatMessage(
        team_id=team_id,
        user_id=current_user.id,
        user_email=current_user.email,
        message=message_text,
        response=answer,
        citations_json=citations_json
    )
    db.add(team_msg)
    db.flush()

    db.add(AuditLog(
        user_id=current_user.id,
        action="team_chat_query",
        resource_type="team_chat",
        resource_id=str(team_id),
        severity=LogSeverity.INFO,
        detail=f"Shared chat query in team '{team.name}' (Project: {team.project_name})"
    ))
    db.commit()

    return TeamChatMessageOut(
        id=team_msg.id,
        team_id=team_id,
        user_id=current_user.id,
        user_email=current_user.email,
        message=message_text,
        response=answer,
        citations=citations,
        created_at=team_msg.created_at
    )
