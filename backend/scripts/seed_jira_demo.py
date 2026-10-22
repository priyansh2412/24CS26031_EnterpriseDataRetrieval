"""
Idempotent script to seed Jira integration demo data.
Prepares:
- Users: manager@example.com, employee@example.com (display_name="Rahul"), finance@example.com
- Team: "Backend Core Team" / Project: "Jira Integration Sprint" with manager (lead), employee & finance (members)
- Sets team's jira_project_key to settings.jira_default_project_key
"""
import os
import sys
from pathlib import Path

# Add backend directory to sys.path so app modules are importable
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))
os.chdir(backend_dir)

from app.core.config import settings
from app.core.database import SessionLocal, init_db, apply_compatible_migrations
from app.models import Team, TeamMember, User


def seed_jira_demo():
    print("=" * 60)
    print("Seeding Jira Integration Demo Workspace...")
    print("=" * 60)

    # Ensure tables and compatible migrations are up to date
    init_db()
    apply_compatible_migrations()

    with SessionLocal() as db:
        manager = db.query(User).filter(User.email == "manager@example.com").first()
        employee = db.query(User).filter(User.email == "employee@example.com").first()
        finance = db.query(User).filter(User.email == "finance@example.com").first()

        if not manager or not employee or not finance:
            print("Error: Required demo users (manager@example.com, employee@example.com, finance@example.com) not found.")
            print("Please ensure database is initialized by starting backend once.")
            return

        # Ensure employee has display_name="Rahul" for assignee matching demo
        if not employee.display_name or employee.display_name != "Rahul":
            employee.display_name = "Rahul"
            db.commit()
            print("Set employee@example.com display_name to 'Rahul'.")
        else:
            print("employee@example.com display_name is already 'Rahul'.")

        # Check or create Team
        team_name = "Backend Core Team"
        project_name = "Jira Integration Sprint"

        team = db.query(Team).filter(Team.name == team_name).first()
        if not team:
            eff_tenant = str(manager.tenant_id or settings.default_tenant_id)
            team = Team(
                tenant_id=eff_tenant,
                name=team_name,
                project_name=project_name,
                description="Engineering workspace for Atlas Team Chat & Jira Cloud issue integration.",
                created_by_id=manager.id,
                jira_project_key=settings.jira_default_project_key or "ATLAS"
            )
            db.add(team)
            db.flush()
            print(f"Created Team: '{team.name}' (ID: {team.id}, Project: '{team.project_name}')")
        else:
            if not team.jira_project_key and settings.jira_default_project_key:
                team.jira_project_key = settings.jira_default_project_key
                db.commit()
            print(f"Team '{team.name}' already exists (ID: {team.id}, Jira Project: '{team.jira_project_key}').")

        # Ensure members exist
        existing_members = {
            m.user_id for m in db.query(TeamMember).filter(TeamMember.team_id == team.id).all()
        }

        # Manager as lead
        if manager.id not in existing_members:
            db.add(TeamMember(team_id=team.id, user_id=manager.id, role_in_team="lead"))
            print(f"Added manager ({manager.email}) as team lead.")
        # Employee as member
        if employee.id not in existing_members:
            db.add(TeamMember(team_id=team.id, user_id=employee.id, role_in_team="member"))
            print(f"Added employee ({employee.email}, Rahul) as member.")
        # Finance as member
        if finance.id not in existing_members:
            db.add(TeamMember(team_id=team.id, user_id=finance.id, role_in_team="member"))
            print(f"Added finance ({finance.email}) as member.")

        db.commit()
        db.refresh(team)

        print("-" * 60)
        print("DEMO SETUP COMPLETE!")
        print(f"Team ID: {team.id}")
        print(f"Team Name: {team.name}")
        print(f"Jira Project Key: {team.jira_project_key or '(None set, configure via PATCH /api/jira/teams/' + str(team.id) + '/settings)'}")
        print("\nDemo Accounts:")
        print("  - Manager (Lead): manager@example.com / ManagerPass123!")
        print("  - Rahul (Member): employee@example.com / EmployeePass123! (Display Name: Rahul)")
        print("  - Finance (Member): finance@example.com / FinancePass123!")
        print("\nWhat to test in Team Chat (mode: 'team'):")
        print('  1. "Rahul, finish the login API in 2 days"')
        print('     -> Detects task, assignee Rahul, due date 2 days from now.')
        print('  2. "meeting tomorrow at 2PM"')
        print('     -> Detects meeting, tomorrow\'s date, due_time 14:00.')
        print('  3. "good morning team"')
        print('     -> Ignored (intent "none", no Jira card).')
        print("=" * 60)


if __name__ == "__main__":
    seed_jira_demo()
