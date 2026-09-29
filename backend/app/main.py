import json
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.core.database import Base, SessionLocal, apply_compatible_migrations, engine
from app.core.security import hash_password
from app.models import CompanyRole, Role, User
from app.routers import analytics, audit, auth, chat, documents, feedback, setup, teams, users

@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)  # Replace with Alembic migrations in a deployed environment.
    apply_compatible_migrations()
    db = SessionLocal()

    # Seed Default Company Roles if empty
    default_company_roles = [
        ("Executive Admin", "admin", 1, "Root System Administrator & C-Suite Executive"),
        ("Department Head", "hr", 2, "Department & HR Manager Access"),
        ("Finance Lead", "finance", 2, "Financial & Operations Lead Access"),
        ("Team Manager", "manager", 3, "Team Lead & Project Manager Access"),
        ("Staff Employee", "employee", 4, "General Staff & Individual Contributor Access"),
    ]
    for name, key, rank, desc in default_company_roles:
        existing_role = db.query(CompanyRole).filter(CompanyRole.key == key).first()
        if not existing_role:
            db.add(CompanyRole(name=name, key=key, rank_level=rank, description=desc, permissions_json=json.dumps(["chat", "documents:view"])))

    seed_users = [
        ("admin@example.com", "AdminPass123!", Role.ADMIN, "admin", 1),
        ("hr@example.com", "HrPass123!", Role.HR, "hr", 2),
        ("manager@example.com", "ManagerPass123!", Role.MANAGER, "manager", 3),
        ("finance@example.com", "FinancePass123!", Role.FINANCE, "finance", 2),
        ("employee@example.com", "EmployeePass123!", Role.EMPLOYEE, "employee", 4),
    ]
    for email, pwd, role, role_k, rank in seed_users:
        existing = db.query(User).filter(User.email == email).first()
        if not existing:
            db.add(User(email=email, password_hash=hash_password(pwd), role=role, role_key=role_k, rank_level=rank, is_active=True))
        else:
            existing.password_hash = hash_password(pwd)
            existing.is_active = True
            existing.role = role
            existing.role_key = role_k
            existing.rank_level = rank
    db.commit()
    db.close()
    yield

app = FastAPI(title="Enterprise Data Retrieval API", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=[x.strip() for x in settings.cors_origins.split(",")], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
for router in (setup.router, auth.router, documents.router, chat.router, feedback.router, analytics.router, users.router, audit.router, teams.router):
    app.include_router(router)

@app.get("/health")
def health(): return {"status": "ok"}


