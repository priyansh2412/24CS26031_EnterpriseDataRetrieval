from pathlib import Path
import json
import shutil
import uuid
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.orm import Session
from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_user
from app.models import AuditLog, Document, LogSeverity, Team, TeamChatMessage, TeamMember, User
from app.schemas import Citation, TeamChatMessageOut, TeamCreate, TeamMemberAdd, TeamMemberOut, TeamOut
from app.services.citation_service import format_context_prompt
from app.services.ingestion_service import ingest_temporary_document, delete_temporary_document
from app.services.llm import generate_answer
from app.services.retrieval_service import retrieve_authorized_chunks

router = APIRouter(prefix="/api/teams", tags=["teams"])


def _to_uuid(val: Any) -> uuid.UUID | None:
    if not val:
        return None
    if isinstance(val, uuid.UUID):
        return val
    try:
        return uuid.UUID(str(val))
    except Exception:
        return None


def _is_system_admin(user: User) -> bool:
    role_val = user.role.value if hasattr(user.role, "value") else str(user.role or "employee")
    return user.email == "system@gmailexample.com" or (role_val == "admin" and getattr(user, "rank_level", 5) == 0)


def _user_in_team(db: Session, team_id: int, user_id: Any) -> bool:
    try:
        uid = uuid.UUID(str(user_id))
        return db.query(TeamMember).filter(TeamMember.team_id == team_id, TeamMember.user_id == uid).first() is not None
    except Exception:
        return db.query(TeamMember).filter(TeamMember.team_id == team_id, TeamMember.user_id == user_id).first() is not None


@router.get("", response_model=list[TeamOut])
def list_teams(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None

    query = db.query(Team)
    if not _is_system_admin(current_user):
        # 1. Enforce same enterprise
        if user_tenant:
            query = query.filter(Team.tenant_id == user_tenant)
        else:
            query = query.filter((Team.tenant_id.is_(None)) | (Team.tenant_id == settings.default_tenant_id))

        # 2. Enforce same team membership: Only active members of the team can view it
        member_team_ids = db.query(TeamMember.team_id).filter(TeamMember.user_id == current_user.id).all()
        ids = {t[0] for t in member_team_ids}
        query = query.filter(Team.id.in_(list(ids)))

    teams = query.order_by(Team.created_at.desc()).all()

    out = []
    for team in teams:
        members_query = db.query(TeamMember, User).join(User, TeamMember.user_id == User.id).filter(TeamMember.team_id == team.id).all()
        members_out = [
            TeamMemberOut(
                id=m.id,
                user_id=u.id,
                user_email=u.email,
                user_role_key=u.role_key or (u.role.value if hasattr(u.role, "value") else str(u.role)),
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
    eff_tenant = str(current_user.tenant_id or settings.default_tenant_id)
    team = Team(
        tenant_id=eff_tenant,
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
        tenant_id=_to_uuid(eff_tenant),
        action="create_team",
        resource_type="team",
        resource_id=str(team.id),
        severity=LogSeverity.INFO,
        detail=f"Created team '{team.name}' for project '{team.project_name}'"
    ))
    db.commit()
    db.refresh(team)

    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
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
            user_role_key=current_user.role_key or curr_role,
            user_rank_level=current_user.rank_level,
            role_in_team="lead"
        )]
    )


@router.post("/{team_id}/members", response_model=TeamOut)
def add_team_member(team_id: int, payload: TeamMemberAdd, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        # 1. Enforce same enterprise
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        # 2. Must be a member of this team to add colleagues
        if not _user_in_team(db, team_id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: only members of this team can add colleagues")

    try:
        uid = uuid.UUID(str(payload.user_id))
        target_user = db.query(User).filter(User.id == uid).first()
    except Exception:
        target_user = db.query(User).filter(User.id == payload.user_id).first()

    if not target_user:
        raise HTTPException(status_code=404, detail="User to add not found")

    # 3. Target user MUST belong to the SAME enterprise!
    target_tenant = str(target_user.tenant_id) if target_user.tenant_id else None
    if user_tenant and target_tenant and target_tenant != user_tenant:
        raise HTTPException(status_code=400, detail="Cannot add a user from a different enterprise to this team")

    existing = db.query(TeamMember).filter(TeamMember.team_id == team_id, TeamMember.user_id == target_user.id).first()
    if existing:
        raise HTTPException(status_code=400, detail="User is already a member of this team")

    new_member = TeamMember(team_id=team_id, user_id=target_user.id, role_in_team=payload.role_in_team)
    db.add(new_member)
    db.add(AuditLog(
        user_id=current_user.id,
        tenant_id=_to_uuid(team.tenant_id),
        action="add_team_member",
        resource_type="team",
        resource_id=str(team_id),
        severity=LogSeverity.INFO,
        detail=f"Added {target_user.email} to team '{team.name}' as {payload.role_in_team}"
    ))
    db.commit()

    # Return refreshed team
    members_query = db.query(TeamMember, User).join(User, TeamMember.user_id == User.id).filter(TeamMember.team_id == team.id).all()
    members_out = [
        TeamMemberOut(
            id=m.id,
            user_id=u.id,
            user_email=u.email,
            user_role_key=u.role_key or (u.role.value if hasattr(u.role, "value") else str(u.role)),
            user_rank_level=u.rank_level,
            role_in_team=m.role_in_team
        ) for m, u in members_query
    ]
    return TeamOut(
        id=team.id,
        name=team.name,
        project_name=team.project_name,
        description=team.description,
        created_by_id=team.created_by_id,
        created_at=team.created_at,
        members=members_out
    )


@router.delete("/{team_id}/members/{user_id}")
def remove_team_member(team_id: int, user_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(status_code=404, detail="Team not found")

    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        if not _user_in_team(db, team_id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: only members of this team can manage membership")

    try:
        uid = uuid.UUID(user_id)
        member = db.query(TeamMember).filter(TeamMember.team_id == team_id, TeamMember.user_id == uid).first()
    except Exception:
        member = db.query(TeamMember).filter(TeamMember.team_id == team_id, TeamMember.user_id == user_id).first()

    if not member:
        raise HTTPException(status_code=404, detail="Team member not found")

    db.delete(member)
    db.add(AuditLog(
        user_id=current_user.id,
        tenant_id=_to_uuid(team.tenant_id),
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

    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        # 1. Enforce same enterprise
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        # 2. Enforce same team membership
        if not _user_in_team(db, team_id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: you are not a member of this team")

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

    user_tenant = str(current_user.tenant_id) if current_user.tenant_id else None
    if not _is_system_admin(current_user):
        # 1. Enforce same enterprise
        if user_tenant and team.tenant_id and team.tenant_id != user_tenant:
            raise HTTPException(status_code=403, detail="Access denied: team belongs to another enterprise")
        # 2. Enforce same team membership
        if not _user_in_team(db, team_id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: you are not a member of this team")

    eff_tenant = str(team.tenant_id or current_user.tenant_id or settings.default_tenant_id)

    # 1. Retrieve knowledge chunks grounded for enterprise project
    raw_chunks = retrieve_authorized_chunks(
        question=message_text,
        db=db,
        user=current_user,
        top_k=5,
        project_id=str(team.id),
        tenant_id=eff_tenant
    )
    _, citations = format_context_prompt(raw_chunks)

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
        tenant_id=_to_uuid(eff_tenant),
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


@router.post("/{team_id}/upload-temp")
async def upload_team_temp_document(
    team_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Upload a temporary document for this team's workspace chat.
    Ingests into Qdrant for this team.
    Available only to members of this team.
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
    temp_file_path = temp_dir / f"team_{team_id}_{uuid.uuid4().hex}_{file.filename}"

    with open(temp_file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    try:
        result = ingest_temporary_document(
            file_path=temp_file_path,
            filename=file.filename,
            user=current_user,
            db=db,
            team_id=team_id
        )
        return result
    except Exception as e:
        if temp_file_path.exists():
            temp_file_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=f"Failed to process document: {str(e)}")


@router.get("/{team_id}/temp-docs")
def list_team_temp_documents(
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
        if not _user_in_team(db, team_id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: you are not a member of this team")

    docs = (
        db.query(Document)
        .filter(
            Document.source == "temp_team",
            Document.project_id == str(team_id)
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


@router.delete("/{team_id}/temp-docs/{document_id}")
def remove_team_temp_document(
    team_id: int,
    document_id: str,
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
        if not _user_in_team(db, team_id, current_user.id) and team.created_by_id != current_user.id:
            raise HTTPException(status_code=403, detail="Access denied: you are not a member of this team")

    success = delete_temporary_document(document_id, current_user, db, team_id=team_id)
    if not success:
        raise HTTPException(status_code=404, detail="Temporary document not found")
    return {"status": "success", "message": "Team temporary document deleted."}

