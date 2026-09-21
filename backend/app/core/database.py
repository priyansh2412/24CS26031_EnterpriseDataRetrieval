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
    if "documents" in inspector.get_table_names():
        columns = {column["name"] for column in inspector.get_columns("documents")}
        if "access_roles" not in columns:
            default_roles = '["admin", "hr", "finance", "manager", "employee"]'
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE documents ADD COLUMN access_roles TEXT NOT NULL DEFAULT '[]'"))
                connection.execute(text("UPDATE documents SET access_roles = :roles WHERE access_roles = '[]'"), {"roles": default_roles})

    if "query_logs" in inspector.get_table_names():
        log_columns = {column["name"] for column in inspector.get_columns("query_logs")}
        if "citations_json" not in log_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE query_logs ADD COLUMN citations_json TEXT DEFAULT '[]'"))

