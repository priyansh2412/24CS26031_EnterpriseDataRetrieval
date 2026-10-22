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

if db_url.startswith("sqlite"):
    engine = create_engine(
        db_url,
        connect_args={"check_same_thread": False}
    )
else:
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
    import app.models  # noqa: F401
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
                if "folder_path" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN folder_path VARCHAR(512) DEFAULT '/'"))
                if "drive_link_id" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN drive_link_id INTEGER NULL"))
                if "denied_users" not in columns:
                    connection.execute(text("ALTER TABLE documents ADD COLUMN denied_users TEXT DEFAULT '[]'"))

            if "teams" in table_names:
                team_columns = {column["name"] for column in inspector.get_columns("teams")}
                if "tenant_id" not in team_columns:
                    connection.execute(text("ALTER TABLE teams ADD COLUMN tenant_id VARCHAR(64) DEFAULT 'tenant-001'"))
                if "project_name" not in team_columns:
                    connection.execute(text("ALTER TABLE teams ADD COLUMN project_name VARCHAR(150) DEFAULT 'General'"))
                if "jira_project_key" not in team_columns:
                    connection.execute(text("ALTER TABLE teams ADD COLUMN jira_project_key VARCHAR(50) NULL"))

            if "team_chat_messages" in table_names:
                msg_columns = {column["name"] for column in inspector.get_columns("team_chat_messages")}
                if "message_type" not in msg_columns:
                    connection.execute(text("ALTER TABLE team_chat_messages ADD COLUMN message_type VARCHAR(20) DEFAULT 'ai'"))
                    connection.execute(text("UPDATE team_chat_messages SET message_type = 'ai' WHERE message_type IS NULL"))

            if "query_logs" in table_names:
                log_columns = {column["name"] for column in inspector.get_columns("query_logs")}
                if "tenant_id" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN tenant_id VARCHAR(64) DEFAULT 'tenant-001'"))
                if "user_id" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN user_id VARCHAR(36) NULL"))
                if "citations_json" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN citations_json TEXT DEFAULT '[]'"))
                if "team_id" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN team_id INTEGER NULL"))
                if "session_id" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN session_id VARCHAR(100) NULL"))
                if "channel" not in log_columns:
                    connection.execute(text("ALTER TABLE query_logs ADD COLUMN channel VARCHAR(20) NOT NULL DEFAULT 'web'"))


            if "users" in table_names:
                user_columns = {column["name"] for column in inspector.get_columns("users")}
                if "role_key" not in user_columns:
                    connection.execute(text("ALTER TABLE users ADD COLUMN role_key VARCHAR(50) DEFAULT 'employee'"))
                if "rank_level" not in user_columns:
                    connection.execute(text("ALTER TABLE users ADD COLUMN rank_level INTEGER DEFAULT 5"))
                if "created_by_id" not in user_columns:
                    connection.execute(text("ALTER TABLE users ADD COLUMN created_by_id INTEGER NULL"))
                if "display_name" not in user_columns:
                    connection.execute(text("ALTER TABLE users ADD COLUMN display_name VARCHAR(255) NULL"))

            if "audit_logs" in table_names:
                audit_columns = {column["name"] for column in inspector.get_columns("audit_logs")}
                if "severity" not in audit_columns:
                    connection.execute(text("ALTER TABLE audit_logs ADD COLUMN severity VARCHAR(20) DEFAULT 'INFO'"))
                if "channel" not in audit_columns:
                    connection.execute(text("ALTER TABLE audit_logs ADD COLUMN channel VARCHAR(20) NOT NULL DEFAULT 'web'"))
                if "tenant_id" not in audit_columns:
                    connection.execute(text("ALTER TABLE audit_logs ADD COLUMN tenant_id VARCHAR(36) NULL"))


    except Exception as e:
        print(f"Migration notice: {e}")
