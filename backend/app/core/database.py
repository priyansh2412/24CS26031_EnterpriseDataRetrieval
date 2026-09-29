from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from app.core.config import settings

engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def apply_compatible_migrations() -> None:
    """Small compatibility migration for the local SQLite demo database."""
    inspector = inspect(engine)
    table_names = inspector.get_table_names()

    with engine.begin() as connection:
        if "documents" in table_names:
            columns = {column["name"] for column in inspector.get_columns("documents")}
            if "access_roles" not in columns:
                default_roles = '["admin", "hr", "finance", "manager", "employee"]'
                connection.execute(text("ALTER TABLE documents ADD COLUMN access_roles TEXT NOT NULL DEFAULT '[]'"))
                connection.execute(text("UPDATE documents SET access_roles = :roles WHERE access_roles = '[]'"), {"roles": default_roles})

        if "query_logs" in table_names:
            log_columns = {column["name"] for column in inspector.get_columns("query_logs")}
            if "citations_json" not in log_columns:
                connection.execute(text("ALTER TABLE query_logs ADD COLUMN citations_json TEXT DEFAULT '[]'"))
            if "team_id" not in log_columns:
                connection.execute(text("ALTER TABLE query_logs ADD COLUMN team_id INTEGER NULL"))

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


