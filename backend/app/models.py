import enum
import uuid
from datetime import datetime
from typing import Any
from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    func
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base


class Role(str, enum.Enum):
    ADMIN = "admin"
    HR = "hr"
    FINANCE = "finance"
    MANAGER = "manager"
    EMPLOYEE = "employee"
    USER = "user"  # Legacy role; treated with employee-level permissions.
    GUEST = "guest"


class LogSeverity(str, enum.Enum):
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class SystemSetting(Base):
    __tablename__ = "system_settings"
    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    value: Mapped[str] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class CompanyRole(Base):
    __tablename__ = "company_roles"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True)
    key: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    rank_level: Mapped[int] = mapped_column(Integer, index=True, default=1)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    permissions_json: Mapped[str] = mapped_column(Text, default='["chat", "documents:view"]')
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class Tenant(Base):
    __tablename__ = "tenants"
    id: Mapped[Any] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(Text, unique=True, index=True)
    name: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="active")
    data_region: Mapped[str | None] = mapped_column(Text, nullable=True, default="us-east-1")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class User(Base):
    __tablename__ = "users"
    id: Mapped[Any] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    role: Mapped[str] = mapped_column(String(50), default="employee")
    role_key: Mapped[str | None] = mapped_column(String(50), nullable=True, default="employee")
    rank_level: Mapped[int] = mapped_column(Integer, default=5, index=True)
    created_by_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    group_memberships = relationship("GroupMember", back_populates="user", cascade="all, delete-orphan")


class Group(Base):
    __tablename__ = "groups"
    id: Mapped[Any] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    key: Mapped[str | None] = mapped_column(String(50), unique=True, index=True, nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    members = relationship("GroupMember", back_populates="group", cascade="all, delete-orphan")


class GroupMember(Base):
    __tablename__ = "group_members"
    id: Mapped[Any] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True)
    group_id: Mapped[Any] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[Any] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    group = relationship("Group", back_populates="members")
    user = relationship("User", back_populates="group_memberships")


class UserGroupClosure(Base):
    __tablename__ = "user_group_closure"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[Any] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    group_id: Mapped[Any] = mapped_column(ForeignKey("groups.id", ondelete="CASCADE"), index=True)
    depth: Mapped[int] = mapped_column(Integer, default=0)


class RoleAssignment(Base):
    __tablename__ = "role_assignments"
    id: Mapped[Any] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True)
    user_id: Mapped[Any] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    role_key: Mapped[str] = mapped_column(String(50), index=True)
    scope_type: Mapped[str] = mapped_column(String(50), default="tenant")
    scope_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class Source(Base):
    __tablename__ = "sources"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tenant_id: Mapped[str | None] = mapped_column(String(64), default="tenant-001", index=True, nullable=True)
    name: Mapped[str] = mapped_column(String(255))
    source_type: Mapped[str] = mapped_column(String(50), default="google_drive")
    uri: Mapped[str] = mapped_column(String(1024), unique=True, index=True)
    drive_file_id: Mapped[str | None] = mapped_column(String(128), index=True, nullable=True)
    folder_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="active")
    metadata_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class EnterpriseDriveLink(Base):
    __tablename__ = "enterprise_drive_links"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tenant_id: Mapped[str] = mapped_column(String(64), index=True)
    name: Mapped[str] = mapped_column(String(255))
    drive_url: Mapped[str] = mapped_column(Text)
    drive_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_folder: Mapped[bool] = mapped_column(Boolean, default=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="active")
    doc_count: Mapped[int] = mapped_column(Integer, default=0)
    created_by_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())


class Document(Base):
    __tablename__ = "documents"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    tenant_id: Mapped[str] = mapped_column(String(64), default="tenant-001", index=True)
    project_id: Mapped[str | None] = mapped_column(String(64), default="project-001", nullable=True)
    name: Mapped[str] = mapped_column(String(512), index=True)
    source: Mapped[str] = mapped_column(String(50), default="local")
    source_uri: Mapped[str | None] = mapped_column(String(1024), nullable=True, index=True)
    drive_file_id: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    folder_path: Mapped[str | None] = mapped_column(String(512), default="/", nullable=True)
    drive_link_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    mime_type: Mapped[str | None] = mapped_column(String(128), nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    owner_email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    web_view_link: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    revision_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    modified_time: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    checksum: Mapped[str | None] = mapped_column(String(64), index=True)
    source_hash: Mapped[str | None] = mapped_column(String(64), index=True, nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="pending")
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    chunk_count: Mapped[int] = mapped_column(Integer, default=0)
    acl_version: Mapped[int] = mapped_column(Integer, default=1)
    access_roles: Mapped[str] = mapped_column(Text, default='["admin", "hr", "finance", "manager", "employee"]')
    denied_users: Mapped[str | None] = mapped_column(Text, default="[]", nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    versions = relationship("DocumentVersion", back_populates="document", cascade="all, delete-orphan")
    acl_entries = relationship("DocumentACLEntry", back_populates="document", cascade="all, delete-orphan")
    chunks = relationship("Chunk", back_populates="document", cascade="all, delete-orphan")


class DocumentVersion(Base):
    __tablename__ = "document_versions"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    document_id: Mapped[str] = mapped_column(ForeignKey("documents.id", ondelete="CASCADE"), index=True)
    version_number: Mapped[int] = mapped_column(Integer, default=1)
    version_no: Mapped[int | None] = mapped_column(Integer, default=1, nullable=True)
    checksum: Mapped[str | None] = mapped_column(String(64), index=True)
    content_hash: Mapped[str | None] = mapped_column(String(64), index=True, nullable=True)
    revision_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    file_size: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    document = relationship("Document", back_populates="versions")


class DocumentACLEntry(Base):
    __tablename__ = "document_acl_entries"
    id: Mapped[Any] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    document_id: Mapped[str] = mapped_column(ForeignKey("documents.id", ondelete="CASCADE"), index=True)
    principal_key: Mapped[str] = mapped_column(String(128), index=True)
    permission: Mapped[str] = mapped_column(String(32), default="read")
    effect: Mapped[str] = mapped_column(String(16), default="allow")
    origin: Mapped[str] = mapped_column(String(32), default="source_sync")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    document = relationship("Document", back_populates="acl_entries")

    __table_args__ = (
        Index("idx_doc_acl_principal", "document_id", "principal_key"),
    )


class ACLOutbox(Base):
    __tablename__ = "acl_outbox"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    document_id: Mapped[str] = mapped_column(String(64), index=True)
    acl_version: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(32), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    processed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Chunk(Base):
    __tablename__ = "chunks"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    tenant_id: Mapped[str] = mapped_column(String(64), default="tenant-001", index=True)
    document_id: Mapped[str] = mapped_column(ForeignKey("documents.id", ondelete="CASCADE"), index=True)
    version_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    project_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    chunk_index: Mapped[int] = mapped_column(Integer, nullable=False)
    page_start: Mapped[int | None] = mapped_column(Integer, nullable=True)
    page_end: Mapped[int | None] = mapped_column(Integer, nullable=True)
    section_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    text_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    embedding_model: Mapped[str | None] = mapped_column(String(64), nullable=True)
    index_state: Mapped[str] = mapped_column(String(32), default="indexed", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    document = relationship("Document", back_populates="chunks")

    __table_args__ = (
        Index("idx_chunks_doc_chunk", "document_id", "chunk_index"),
        Index("idx_chunks_tenant_doc", "tenant_id", "document_id"),
    )


class QueryLog(Base):
    __tablename__ = "query_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tenant_id: Mapped[str | None] = mapped_column(String(64), default="tenant-001", index=True, nullable=True)
    user_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True, index=True)
    team_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    session_id: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    query: Mapped[str] = mapped_column(Text)
    response: Mapped[str] = mapped_column(Text)
    retrieved_document_ids: Mapped[str] = mapped_column(Text, default="[]")
    citations_json: Mapped[str | None] = mapped_column(Text, nullable=True, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class Feedback(Base):
    __tablename__ = "feedback"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    query_log_id: Mapped[int] = mapped_column(Integer, index=True)
    user_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True)
    is_positive: Mapped[bool] = mapped_column(Boolean)
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[Any] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True, index=True)
    user_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(100), index=True)
    resource_type: Mapped[str] = mapped_column(String(60))
    resource_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    severity: Mapped[str] = mapped_column(String(20), default="INFO", index=True)
    detail: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)


class Team(Base):
    __tablename__ = "teams"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    tenant_id: Mapped[str | None] = mapped_column(String(64), default="tenant-001", index=True, nullable=True)
    name: Mapped[str] = mapped_column(String(100), index=True)
    project_name: Mapped[str] = mapped_column(String(150), index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class TeamMember(Base):
    __tablename__ = "team_members"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    team_id: Mapped[int] = mapped_column(Integer, ForeignKey("teams.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    role_in_team: Mapped[str] = mapped_column(String(50), default="member")
    joined_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class TeamChatMessage(Base):
    __tablename__ = "team_chat_messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    team_id: Mapped[int] = mapped_column(Integer, ForeignKey("teams.id", ondelete="CASCADE"), index=True)
    user_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), nullable=True, index=True)
    user_email: Mapped[str] = mapped_column(String(255))
    message: Mapped[str] = mapped_column(Text)
    response: Mapped[str] = mapped_column(Text)
    citations_json: Mapped[str | None] = mapped_column(Text, nullable=True, default="[]")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


class EnterpriseAdmin(Base):
    __tablename__ = "enterprise_admins"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    enterprise_name: Mapped[str] = mapped_column(String(150), index=True)
    admin_email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    temp_password: Mapped[str] = mapped_column(String(255))
    user_id: Mapped[Any] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    tenant_id: Mapped[str] = mapped_column(String(64), default="tenant-001", index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    user = relationship("User", foreign_keys=[user_id])
