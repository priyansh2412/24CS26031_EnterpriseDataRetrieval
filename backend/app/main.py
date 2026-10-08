import json
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.database import (
    Base,
    SessionLocal,
    apply_compatible_migrations,
    engine,
    fetch_one,
    init_db,
)
from app.core.security import hash_password
from app.models import CompanyRole, Role, User
from app.routers import (
    analytics,
    audit,
    auth,
    chat,
    documents,
    enterprises,
    feedback,
    ingestion,
    setup,
    sources,
    teams,
    users,
)
from app.services.ingestion_service import auto_ingest_all_sources
from app.services.qdrant_service import ensure_collection, get_qdrant_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

STATIC_DIR = Path(__file__).resolve().parent / "static"


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing database tables...")
    try:
        init_db()
        apply_compatible_migrations()
        logger.info("Database tables initialized successfully.")
    except Exception as e:
        logger.warning(f"Database initialization notice: {e}")

    logger.info("Verifying Qdrant vector collection...")
    try:
        ensure_collection()
        logger.info("Qdrant collection verified successfully.")
    except Exception as e:
        logger.warning(f"Qdrant collection initialization notice: {e}")

    # Seed Default Company Roles & Users
    try:
        db = SessionLocal()
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
                db.add(CompanyRole(
                    name=name,
                    key=key,
                    rank_level=rank,
                    description=desc,
                    permissions_json=json.dumps(["chat", "documents:view"])
                ))

        seed_users = [
            ("system@gmailexample.com", "System123@", Role.ADMIN, "system_admin", 0),
            ("admin@example.com", "AdminPass123!", Role.ADMIN, "admin", 1),
            ("hr@example.com", "HrPass123!", Role.HR, "hr", 2),
            ("manager@example.com", "ManagerPass123!", Role.MANAGER, "manager", 3),
            ("finance@example.com", "FinancePass123!", Role.FINANCE, "finance", 2),
            ("employee@example.com", "EmployeePass123!", Role.EMPLOYEE, "employee", 4),
        ]
        for email, pwd, role_enum, role_k, rank in seed_users:
            role_val = role_enum.value
            existing = db.query(User).filter(User.email == email).first()
            if not existing:
                db.add(User(
                    email=email,
                    password_hash=hash_password(pwd),
                    role=role_val,
                    role_key=role_k,
                    rank_level=rank,
                    is_active=True
                ))
            else:
                existing.password_hash = hash_password(pwd)
                existing.is_active = True
                existing.role = role_val
                existing.role_key = role_k
                existing.rank_level = rank
        db.commit()

        db.close()

        # Automated document ingestion (Drive link from .env + local documents) in background thread
        import threading
        def _bg_ingest():
            with SessionLocal() as bg_db:
                try:
                    auto_ingest_all_sources(bg_db)
                except Exception as err:
                    logger.warning(f"Background auto-ingestion error: {err}")

        threading.Thread(target=_bg_ingest, daemon=True).start()
    except Exception as e:
        logger.warning(f"Lifespan seeding notice: {e}")

    yield


app = FastAPI(
    title="Enterprise RAG & Data Retrieval Platform",
    description="Enterprise Knowledge Retrieval with Google Drive, Docling hierarchical parsing, Qdrant ACL vector search, and Gemini generation.",
    version="1.0.0",
    lifespan=lifespan
)

# CORS Middleware
origins = [x.strip() for x in settings.cors_origins.split(",") if x.strip()] or ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins if "*" not in origins else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register All API Routers
app.include_router(setup.router)
app.include_router(auth.router)
app.include_router(documents.router)
app.include_router(ingestion.router)
app.include_router(sources.router)
app.include_router(chat.router)
app.include_router(feedback.router)
app.include_router(analytics.router)
app.include_router(users.router)
app.include_router(audit.router)
app.include_router(teams.router)
app.include_router(enterprises.router)


@app.get("/api/status")
@app.get("/status")
def get_system_status():
    """Check health and live stats for PostgreSQL and Qdrant."""
    db_ok = False
    doc_count = 0
    chunk_count = 0

    try:
        doc_row = fetch_one("SELECT COUNT(*) AS total FROM documents")
        if doc_row:
            doc_count = doc_row["total"]
        chunk_row = fetch_one("SELECT COUNT(*) AS total FROM chunks")
        if chunk_row:
            chunk_count = chunk_row["total"]
        db_ok = True
    except Exception as e:
        logger.debug(f"DB status check failed: {e}")

    qdrant_ok = False
    vector_count = 0
    try:
        client = get_qdrant_client()
        coll_info = client.get_collection(settings.qdrant_collection)
        vector_count = coll_info.points_count or 0
        qdrant_ok = True
    except Exception as e:
        logger.debug(f"Qdrant status check failed: {e}")

    return {
        "status": "ok" if (db_ok and qdrant_ok) else "partial",
        "database": {
            "connected": db_ok,
            "documents": doc_count,
            "chunks": chunk_count
        },
        "qdrant": {
            "connected": qdrant_ok,
            "collection": settings.qdrant_collection,
            "vectors": vector_count
        },
        "models": {
            "gemini_model": settings.gemini_model,
            "embedding_model": settings.embedding_model
        }
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "Enterprise RAG & Data Retrieval Platform"
    }


# Static UI mount
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/")
def index():
    index_file = STATIC_DIR / "index.html"
    if index_file.exists():
        return FileResponse(str(index_file))
    return {
        "message": "Enterprise Data Retrieval API is running.",
        "docs": "/docs"
    }
