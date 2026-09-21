import enum
from datetime import datetime
from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base


class Role(str, enum.Enum):
    ADMIN = "admin"
    HR = "hr"
    FINANCE = "finance"
    MANAGER = "manager"
    EMPLOYEE = "employee"
    USER = "user"  # Legacy role; treated with employee-level permissions.
    GUEST = "guest"


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[Role] = mapped_column(Enum(Role), default=Role.EMPLOYEE)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class Document(Base):
    __tablename__ = "documents"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(512), index=True)
    source: Mapped[str] = mapped_column(String(50), default="local")
    source_uri: Mapped[str] = mapped_column(String(1024), unique=True)
    checksum: Mapped[str] = mapped_column(String(64), index=True)
    mime_type: Mapped[str | None] = mapped_column(String(128), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="pending")
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    chunk_count: Mapped[int] = mapped_column(Integer, default=0)
    access_roles: Mapped[str] = mapped_column(Text, default='["admin", "hr", "finance", "manager", "employee"]')
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class QueryLog(Base):
    __tablename__ = "query_logs"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    query: Mapped[str] = mapped_column(Text)
    response: Mapped[str] = mapped_column(Text)
    retrieved_document_ids: Mapped[str] = mapped_column(Text, default="[]")
    citations_json: Mapped[str | None] = mapped_column(Text, nullable=True, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())



class Feedback(Base):
    __tablename__ = "feedback"
    id: Mapped[int] = mapped_column(primary_key=True)
    query_log_id: Mapped[int] = mapped_column(ForeignKey("query_logs.id"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    is_positive: Mapped[bool] = mapped_column(Boolean)
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(100), index=True)
    resource_type: Mapped[str] = mapped_column(String(60))
    resource_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)
