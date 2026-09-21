from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.core.database import Base, SessionLocal, apply_compatible_migrations, engine
from app.core.security import hash_password
from app.models import Role, User
from app.routers import analytics, audit, auth, chat, documents, feedback, users

@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)  # Replace with Alembic migrations in a deployed environment.
    apply_compatible_migrations()
    db = SessionLocal()

    seed_users = [
        ("admin@example.com", "AdminPass123!", Role.ADMIN),
        ("hr@example.com", "HrPass123!", Role.HR),
        ("manager@example.com", "ManagerPass123!", Role.MANAGER),
        ("finance@example.com", "FinancePass123!", Role.FINANCE),
        ("employee@example.com", "EmployeePass123!", Role.EMPLOYEE),
    ]
    for email, pwd, role in seed_users:
        existing = db.query(User).filter(User.email == email).first()
        if not existing:
            db.add(User(email=email, password_hash=hash_password(pwd), role=role, is_active=True))
        else:
            existing.password_hash = hash_password(pwd)
            existing.is_active = True
            existing.role = role
    db.commit()
    db.close()
    yield

app = FastAPI(title="Enterprise Data Retrieval API", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=[x.strip() for x in settings.cors_origins.split(",")], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
for router in (auth.router, documents.router, chat.router, feedback.router, analytics.router, users.router, audit.router):
    app.include_router(router)

@app.get("/health")
def health(): return {"status": "ok"}

