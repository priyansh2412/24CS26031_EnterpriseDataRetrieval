from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from app.core.config import settings


def get_normalized_db_url(url: str) -> str:
    """Ensure PostgreSQL URLs use the installed psycopg v3 driver if not specified."""
    if url.startswith("postgresql://"):
        return url.replace("postgresql://", "postgresql+psycopg://", 1)
    if url.startswith("postgres://"):
        return url.replace("postgres://", "postgresql+psycopg://", 1)
    return url


db_url = get_normalized_db_url(settings.database_url)

engine = create_engine(
    db_url,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False
)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def execute(sql: str, params: dict | None = None):
    with engine.begin() as connection:
        return connection.execute(
            text(sql),
            params or {}
        )


def fetch_one(sql: str, params: dict | None = None):
    with engine.begin() as connection:
        return connection.execute(
            text(sql),
            params or {}
        ).mappings().first()


def fetch_all(sql: str, params: dict | None = None):
    with engine.begin() as connection:
        return connection.execute(
            text(sql),
            params or {}
        ).mappings().all()


def init_db():
    """Create all database tables if they do not exist."""
    Base.metadata.create_all(bind=engine)


def apply_compatible_migrations() -> None:
    """Safe automatic migrations for existing schemas."""
    try:
        inspector = inspect(engine)
        table_names = inspector.get_table_names()

        with engine.begin() as connection:
            if "documents" in table_names:
                columns = {column["name"] for column in inspector.get_columns("documents")}
                if "access_roles" not in columns:
                    default_roles = '["admin", "hr", "finance", "manager", "employee"]'
                    connection.execute(text("ALTER TABLE documents ADD COLUMN access_roles TEXT NOT NULL DEFAULT '[]'"))
                    connection.execute(text("UPDATE documents SET access_roles = :roles WHERE access_roles = '[]'"), {"roles": default_roles})
                if "acl_version" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN acl_version INTEGER NOT NULL DEFAULT 1"))
                if "tenant_id" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN tenant_id VARCHAR(64) DEFAULT 'tenant-001'"))
                if "project_id" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN project_id VARCHAR(64) DEFAULT 'project-001'"))
                if "drive_file_id" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN drive_file_id VARCHAR(128)"))
                if "web_view_link" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN web_view_link VARCHAR(1024)"))
                if "revision_id" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN revision_id VARCHAR(128)"))
                if "owner_email" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN owner_email VARCHAR(255)"))

            if "query_logs" in table_names:
                log_columns = {column["name"] for column in inspector.get_columns("query_logs")}
                if "citations_json" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN citations_json TEXT DEFAULT '[]'"))
                if "team_id" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN team_id INTEGER NULL"))
                if "session_id" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN session_id VARCHAR(100) NULL"))

            if "users" in table_names:
                user_columns = {column["name"] for column in inspector.get_columns("users")}
                if "role_key" not in user_columns:
                    connection.execute(text("ALTER TABLE users ADD COLUMN role_key VARCHAR(50) DEFAULT 'employee'"))
                if "rank_level" not in user_columns:
                    connection.execute(text("ALTER TABLE users ADD COLUMN rank_level INTEGER DEFAULT 5"))
                if "created_by_id" not in user_columns:
                    connection.execute(text("ALTER TABLE users ADD COLUMN created_by_id INTEGER NULL"))

            if "audit_logs" in table_names:
                audit_columns = {column["name"] for column in inspector.get_columns("audit_logs")}
                if "severity" not in audit_columns:
                    connection.execute(text("ALTER TABLE audit_logs ADD COLUMN severity VARCHAR(20) DEFAULT 'INFO'"))
    except Exception as e:
        print(f"Migration notice: {e}")
