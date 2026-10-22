import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import settings
from app.core.database import Base, get_db
from app.core.security import create_token
from app.main import app
from app.models import JiraIssueLink, Team, TeamChatMessage, TeamMember, User
from app.services.jira_service import JiraError, text_to_adf
from app.services.team_intel_service import (
    WorkItemExtraction,
    process_message_for_jira,
    resolve_assignee,
)


@pytest.fixture(scope="module")
def test_db_setup():
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine, expire_on_commit=False)

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
    yield session
    session.close()


@pytest.fixture(scope="module")
def client(test_db_setup):
    return TestClient(app)


@pytest.fixture(scope="module")
def seed_data(test_db_setup):
    """Seed test users and a test team once for the module."""
    TestingSessionLocal, _ = test_db_setup
    db = TestingSessionLocal()

    # User 1: Manager (Lead)
    u_manager = User(
        id=uuid.uuid4(),
        email="manager_jira_test@example.com",
        display_name="Test Manager",
        role="manager",
        rank_level=3,
        tenant_id=uuid.uuid4(),
        is_active=True
    )
    # User 2: Rahul (Member)
    u_rahul = User(
        id=uuid.uuid4(),
        email="rahul_jira_test@example.com",
        display_name="Rahul",
        role="employee",
        rank_level=4,
        tenant_id=u_manager.tenant_id,
        is_active=True
    )
    # User 3: Outsider (Different team/enterprise)
    u_outsider = User(
        id=uuid.uuid4(),
        email="outsider_jira_test@example.com",
        display_name="Outsider",
        role="employee",
        rank_level=4,
        tenant_id=uuid.uuid4(),
        is_active=True
    )
    db.add_all([u_manager, u_rahul, u_outsider])
    db.commit()

    team = Team(
        tenant_id=str(u_manager.tenant_id),
        name="Backend Core Test Team",
        project_name="Jira Test Sprint",
        created_by_id=u_manager.id,
        jira_project_key="ATLAS"
    )
    db.add(team)
    db.commit()

    tm_lead = TeamMember(team_id=team.id, user_id=u_manager.id, role_in_team="lead")
    tm_rahul = TeamMember(team_id=team.id, user_id=u_rahul.id, role_in_team="member")
    db.add_all([tm_lead, tm_rahul])
    db.commit()

    db.refresh(u_manager)
    db.refresh(u_rahul)
    db.refresh(u_outsider)
    db.refresh(team)

    return {
        "manager": u_manager,
        "rahul": u_rahul,
        "outsider": u_outsider,
        "team": team,
        "team_id": team.id
    }


def auth_header(user: User) -> dict:
    return {"Authorization": f"Bearer {create_token(user)}"}


# ===========================================================================
# 1. Test text_to_adf shape
# ===========================================================================
def test_text_to_adf():
    # Empty string
    adf_empty = text_to_adf("")
    assert adf_empty["version"] == 1
    assert adf_empty["type"] == "doc"
    assert len(adf_empty["content"]) == 1

    # Multiline text
    text = "Line one\nLine two\n\nLine three"
    adf = text_to_adf(text)
    assert adf["version"] == 1
    assert len(adf["content"]) == 3
    assert adf["content"][0]["content"][0]["text"] == "Line one"
    assert adf["content"][1]["content"][0]["text"] == "Line two"
    assert adf["content"][2]["content"][0]["text"] == "Line three"


# ===========================================================================
# 2. Test resolve_assignee
# ===========================================================================
def test_resolve_assignee(db, seed_data):
    manager = seed_data["manager"]
    rahul = seed_data["rahul"]
    team = seed_data["team"]

    # "me" / "I" resolves to sender
    assert resolve_assignee(db, team.id, "me", manager).id == manager.id
    assert resolve_assignee(db, team.id, "I", rahul).id == rahul.id

    # Display name match "Rahul"
    assert resolve_assignee(db, team.id, "Rahul", manager).id == rahul.id
    assert resolve_assignee(db, team.id, "rahul", manager).id == rahul.id

    # Email local-part match "rahul_jira_test"
    assert resolve_assignee(db, team.id, "rahul_jira_test", manager).id == rahul.id

    # No match
    assert resolve_assignee(db, team.id, "UnknownPerson", manager) is None

    # Empty hint
    assert resolve_assignee(db, team.id, None, manager) is None


# ===========================================================================
# 3. Test process_message_for_jira (Pending link creation & filtering)
# ===========================================================================
def test_process_message_for_jira(test_db_setup, db, seed_data, monkeypatch):
    manager = seed_data["manager"]
    rahul = seed_data["rahul"]
    team = seed_data["team"]

    # Enable jira_configured
    monkeypatch.setattr("app.services.team_intel_service.jira_configured", lambda: True)

    # 1. Actionable task message
    msg = TeamChatMessage(
        team_id=team.id,
        user_id=manager.id,
        user_email=manager.email,
        message="Rahul, finish the login API in 2 days",
        response="",
        citations_json="[]",
        message_type="team"
    )
    db.add(msg)
    db.commit()

    mock_extract = MagicMock(return_value=WorkItemExtraction(
        intent="task",
        title="Finish the login API",
        assignee_hint="Rahul",
        due_date="2026-10-25",
        confidence=0.95
    ))
    monkeypatch.setattr("app.services.team_intel_service.extract_work_item", mock_extract)
    TestingSessionLocal, _ = test_db_setup
    monkeypatch.setattr("app.services.team_intel_service.SessionLocal", TestingSessionLocal)

    process_message_for_jira(msg.id)

    link = db.query(JiraIssueLink).filter(JiraIssueLink.message_id == msg.id).first()
    assert link is not None
    assert link.status == "pending"
    assert link.intent == "task"
    assert link.title == "Finish the login API"
    assert link.assignee_user_id == rahul.id
    assert link.assignee_email == rahul.email
    assert link.due_date == "2026-10-25"

    # 2. Ignored intent: "none"
    msg2 = TeamChatMessage(
        team_id=team.id,
        user_id=manager.id,
        user_email=manager.email,
        message="good morning team",
        response="",
        citations_json="[]",
        message_type="team"
    )
    db.add(msg2)
    db.commit()

    mock_extract_none = MagicMock(return_value=WorkItemExtraction(
        intent="none",
        title=None,
        confidence=0.1
    ))
    monkeypatch.setattr("app.services.team_intel_service.extract_work_item", mock_extract_none)
    process_message_for_jira(msg2.id)

    link2 = db.query(JiraIssueLink).filter(JiraIssueLink.message_id == msg2.id).first()
    assert link2 is None

    # 3. Low confidence
    msg3 = TeamChatMessage(
        team_id=team.id,
        user_id=manager.id,
        user_email=manager.email,
        message="maybe we could review something later",
        response="",
        citations_json="[]",
        message_type="team"
    )
    db.add(msg3)
    db.commit()

    mock_extract_low = MagicMock(return_value=WorkItemExtraction(
        intent="task",
        title="Review something",
        confidence=0.4
    ))
    monkeypatch.setattr("app.services.team_intel_service.extract_work_item", mock_extract_low)
    process_message_for_jira(msg3.id)

    link3 = db.query(JiraIssueLink).filter(JiraIssueLink.message_id == msg3.id).first()
    assert link3 is None


# ===========================================================================
# 4. Test confirm endpoint (Idempotency and Success)
# ===========================================================================
def test_confirm_jira_suggestion_success_and_idempotent(client, db, seed_data, monkeypatch):
    manager = seed_data["manager"]
    rahul = seed_data["rahul"]
    team = seed_data["team"]

    msg = TeamChatMessage(
        team_id=team.id,
        user_id=manager.id,
        user_email=manager.email,
        message="Rahul, finish the login API",
        response="",
        citations_json="[]",
        message_type="team"
    )
    db.add(msg)
    db.commit()

    link = JiraIssueLink(
        tenant_id=team.tenant_id,
        team_id=team.id,
        message_id=msg.id,
        intent="task",
        title="Finish the login API",
        assignee_hint="Rahul",
        assignee_user_id=rahul.id,
        assignee_email=rahul.email,
        due_date="2026-10-25",
        confidence=0.9,
        status="pending"
    )
    db.add(link)
    db.commit()

    call_count = 0

    def mock_create_issue(**kwargs):
        nonlocal call_count
        call_count += 1
        return {
            "key": "ATLAS-101",
            "url": "https://jira.example.com/browse/ATLAS-101",
            "dropped_fields": []
        }

    monkeypatch.setattr("app.routers.jira.create_issue", mock_create_issue)
    monkeypatch.setattr("app.routers.jira.find_account_id", lambda email, name_hint: "jira-account-123")

    # First call: Confirm
    resp = client.post(
        f"/api/jira/suggestions/{link.id}/confirm",
        headers=auth_header(rahul)
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "created"
    assert data["jira_key"] == "ATLAS-101"
    assert data["jira_url"] == "https://jira.example.com/browse/ATLAS-101"
    assert data["assigned_in_jira"] is True
    assert call_count == 1

    # Second call (Idempotency): Should return existing without creating another issue
    resp2 = client.post(
        f"/api/jira/suggestions/{link.id}/confirm",
        headers=auth_header(rahul)
    )
    assert resp2.status_code == 200
    data2 = resp2.json()
    assert data2["jira_key"] == "ATLAS-101"
    assert call_count == 1  # Not incremented!


# ===========================================================================
# 5. Test confirm failure and retry
# ===========================================================================
def test_confirm_jira_suggestion_failure_and_retry(client, db, seed_data, monkeypatch):
    manager = seed_data["manager"]
    rahul = seed_data["rahul"]
    team = seed_data["team"]

    msg = TeamChatMessage(
        team_id=team.id,
        user_id=manager.id,
        user_email=manager.email,
        message="Rahul, sync data",
        response="",
        citations_json="[]",
        message_type="team"
    )
    db.add(msg)
    db.commit()

    link = JiraIssueLink(
        tenant_id=team.tenant_id,
        team_id=team.id,
        message_id=msg.id,
        intent="task",
        title="Sync data",
        status="pending",
        confidence=0.85
    )
    db.add(link)
    db.commit()

    # 1. Failure scenario
    def mock_fail(**kwargs):
        raise JiraError("Jira API error (400): Project key does not exist")

    monkeypatch.setattr("app.routers.jira.create_issue", mock_fail)

    resp = client.post(
        f"/api/jira/suggestions/{link.id}/confirm",
        headers=auth_header(manager)
    )
    assert resp.status_code == 502
    assert "Project key does not exist" in resp.json()["detail"]

    db.refresh(link)
    assert link.status == "failed"
    assert "Project key does not exist" in link.error_message

    # 2. Retry succeeds
    def mock_success(**kwargs):
        return {
            "key": "ATLAS-102",
            "url": "https://jira.example.com/browse/ATLAS-102",
            "dropped_fields": []
        }

    monkeypatch.setattr("app.routers.jira.create_issue", mock_success)

    resp_retry = client.post(
        f"/api/jira/suggestions/{link.id}/confirm",
        headers=auth_header(manager)
    )
    assert resp_retry.status_code == 200
    assert resp_retry.json()["status"] == "created"
    assert resp_retry.json()["jira_key"] == "ATLAS-102"


# ===========================================================================
# 6. Test dismiss endpoint
# ===========================================================================
def test_dismiss_jira_suggestion(client, db, seed_data):
    manager = seed_data["manager"]
    team = seed_data["team"]

    msg = TeamChatMessage(
        team_id=team.id,
        user_id=manager.id,
        user_email=manager.email,
        message="Test dismiss",
        response="",
        citations_json="[]",
        message_type="team"
    )
    db.add(msg)
    db.commit()

    link = JiraIssueLink(
        tenant_id=team.tenant_id,
        team_id=team.id,
        message_id=msg.id,
        intent="task",
        title="Test dismiss",
        status="pending",
        confidence=0.8
    )
    db.add(link)
    db.commit()

    resp = client.post(
        f"/api/jira/suggestions/{link.id}/dismiss",
        headers=auth_header(manager)
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "dismissed"

    db.refresh(link)
    assert link.status == "dismissed"


# ===========================================================================
# 7. Test non-member forbidden
# ===========================================================================
def test_non_member_forbidden(client, db, seed_data):
    outsider = seed_data["outsider"]
    manager = seed_data["manager"]
    team = seed_data["team"]

    msg = TeamChatMessage(
        team_id=team.id,
        user_id=manager.id,
        user_email=manager.email,
        message="Test non-member",
        response="",
        citations_json="[]",
        message_type="team"
    )
    db.add(msg)
    db.commit()

    link = JiraIssueLink(
        tenant_id=team.tenant_id,
        team_id=team.id,
        message_id=msg.id,
        intent="task",
        title="Secret task",
        status="pending",
        confidence=0.8
    )
    db.add(link)
    db.commit()

    # Confirm attempt by non-member
    resp = client.post(f"/api/jira/suggestions/{link.id}/confirm", headers=auth_header(outsider))
    assert resp.status_code == 403

    # Dismiss attempt by non-member
    resp2 = client.post(f"/api/jira/suggestions/{link.id}/dismiss", headers=auth_header(outsider))
    assert resp2.status_code == 403

    # Issues list attempt by non-member
    resp3 = client.get(f"/api/jira/teams/{team.id}/issues", headers=auth_header(outsider))
    assert resp3.status_code == 403


# ===========================================================================
# 8. Test "team" mode vs "ai" mode in send_team_chat_message
# ===========================================================================
def test_team_mode_vs_ai_mode(client, db, seed_data, monkeypatch):
    manager = seed_data["manager"]
    team = seed_data["team"]

    generate_answer_called = False

    def mock_generate_answer(**kwargs):
        nonlocal generate_answer_called
        generate_answer_called = True
        return "Grounded RAG Answer"

    monkeypatch.setattr("app.routers.teams.generate_answer", mock_generate_answer)
    monkeypatch.setattr("app.routers.teams.retrieve_authorized_chunks", lambda **kw: [])

    # 1. Mode "team" -> Should NOT call generate_answer
    generate_answer_called = False
    resp_team = client.post(
        f"/api/teams/{team.id}/chat",
        json={"message": "Rahul, please review the API in 2 days", "mode": "team"},
        headers=auth_header(manager)
    )
    assert resp_team.status_code == 200
    data_team = resp_team.json()
    assert data_team["message_type"] == "team"
    assert data_team["response"] == ""
    assert data_team["citations"] == []
    assert generate_answer_called is False

    # 2. Mode "ai" -> Should call generate_answer
    generate_answer_called = False
    resp_ai = client.post(
        f"/api/teams/{team.id}/chat",
        json={"message": "What is our company project scope?", "mode": "ai"},
        headers=auth_header(manager)
    )
    assert resp_ai.status_code == 200
    data_ai = resp_ai.json()
    assert data_ai["message_type"] == "ai"
    assert data_ai["response"] == "Grounded RAG Answer"
    assert generate_answer_called is True
