from datetime import datetime
from typing import Any
from uuid import UUID
from pydantic import BaseModel, Field
from app.models import Role


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class CompanyRoleSchema(BaseModel):
    id: int | None = None
    name: str
    key: str
    rank_level: int
    description: str | None = None
    permissions: list[str] = ["chat", "documents:view"]
    class Config: from_attributes = True


class SetupStatusOut(BaseModel):
    is_initialized: bool
    company_name: str | None = None


class SystemSetupInit(BaseModel):
    company_name: str = Field(min_length=2, max_length=150)
    roles: list[CompanyRoleSchema] = Field(min_length=1)
    admin_email: str = Field(min_length=3, max_length=255)
    admin_password: str = Field(min_length=8, max_length=128)


class UserOut(BaseModel):
    id: Any
    email: str
    display_name: str | None = None
    role: Role | str
    role_key: str | None = "employee"
    rank_level: int = 5
    is_active: bool = True
    tenant_id: Any = None
    created_at: datetime | None = None
    class Config: from_attributes = True


class UserProfileOut(BaseModel):
    id: Any
    email: str
    display_name: str | None = None
    role: Role | str
    role_key: str | None = "employee"
    rank_level: int = 5
    is_active: bool = True
    tenant_id: Any = None
    enterprise_name: str | None = None
    created_at: datetime | None = None
    class Config: from_attributes = True


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=6, max_length=128)


class UserCreate(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    display_name: str | None = None
    password: str = Field(min_length=8, max_length=128)
    role: Role = Role.EMPLOYEE
    role_key: str | None = "employee"
    rank_level: int | None = 5


class UserUpdate(BaseModel):
    display_name: str | None = None
    role: Role | None = None
    role_key: str | None = None
    rank_level: int | None = None
    is_active: bool | None = None


class ForgotPasswordRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)


class AuditLogOut(BaseModel):
    id: Any
    user_id: Any = None
    user_email: str | None = None
    user_role_key: str | None = None
    user_rank_level: int | None = None
    action: str
    resource_type: str
    resource_id: str | None = None
    severity: str = "INFO"
    detail: str | None = None
    created_at: datetime
    class Config: from_attributes = True


class AskRequest(BaseModel):
    question: str = Field(min_length=2, max_length=4000)
    top_k: int = Field(default=5, ge=1, le=10)
    team_id: int | None = None
    session_id: str | None = None
    document_id: str | None = None


class Citation(BaseModel):
    document_id: str | int
    document_name: str
    chunk_index: int
    text: str
    score: float
    page_start: int | None = None
    page_end: int | None = None
    section_path: str | None = None
    chunk_id: str | None = None


class AskResponse(BaseModel):
    query_log_id: int
    answer: str
    citations: list[Citation]
    session_id: str | None = None


class ChatSessionOut(BaseModel):
    session_id: str
    title: str
    created_at: str
    message_count: int


# Standalone RAG Schema
class ChatRequest(BaseModel):
    question: str = Field(min_length=1, description="The user query to answer using document context")
    document_id: str | None = Field(default=None, description="Optional document ID filter")
    top_k: int = Field(default=5, ge=1, le=10)


class Source(BaseModel):
    document_id: str
    chunk_id: str
    page_start: int | None = None
    page_end: int | None = None
    section_path: str | None = None
    score: float | None = None


class ChatResponse(BaseModel):
    answer: str
    sources: list[Source]


class IngestionResponse(BaseModel):
    status: str
    message: str | None = None
    document_id: str | None = None
    chunks: int = 0
    vectors: int = 0


class DocumentOut(BaseModel):
    id: str
    name: str
    source: str
    status: str
    chunk_count: int
    access_roles: str
    denied_users: str | None = "[]"
    folder_path: str | None = "/"
    drive_link_id: int | None = None
    summary: str | None = None
    drive_file_id: str | None = None
    web_view_link: str | None = None
    acl_version: int = 1
    created_at: datetime
    class Config: from_attributes = True


class FeedbackIn(BaseModel):
    query_log_id: int
    is_positive: bool
    comment: str | None = Field(default=None, max_length=1000)


class DocumentAccessUpdate(BaseModel):
    roles: list[str] = Field(min_length=1)
    denied_users: list[str] = Field(default=[])
    apply_to_folder: bool = False


class EnterpriseDriveLinkCreate(BaseModel):
    name: str | None = None
    drive_url: str = Field(min_length=5)
    password: str | None = None
    folder_path: str | None = "/"


class EnterpriseDriveLinkUpdatePassword(BaseModel):
    current_password: str | None = None
    new_password: str = Field(min_length=4)


class EnterpriseDriveLinkOut(BaseModel):
    id: int
    tenant_id: str
    name: str
    drive_url: str
    drive_id: str | None = None
    is_folder: bool = True
    is_password_protected: bool = False
    status: str = "active"
    doc_count: int = 0
    created_at: datetime
    updated_at: datetime
    class Config: from_attributes = True


class SourceCreate(BaseModel):
    name: str
    uri: str
    source_type: str = "google_drive"
    tenant_id: str | None = None
    project_id: str | None = None


class SourceOut(BaseModel):
    id: int
    name: str
    source_type: str
    uri: str
    drive_file_id: str | None
    folder_id: str | None
    status: str
    created_at: datetime
    class Config: from_attributes = True


class TeamCreate(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    project_name: str = Field(min_length=2, max_length=150)
    description: str | None = Field(default=None, max_length=1000)


class TeamMemberOut(BaseModel):
    id: int
    user_id: Any
    user_email: str
    user_role_key: str | None = None
    user_rank_level: int | None = None
    role_in_team: str = "member"
    class Config: from_attributes = True


class TeamOut(BaseModel):
    id: int
    name: str
    project_name: str
    description: str | None = None
    created_by_id: Any = None
    created_at: datetime
    members: list[TeamMemberOut] = []
    class Config: from_attributes = True


class TeamMemberAdd(BaseModel):
    user_id: Any
    role_in_team: str = "member"


class TeamChatRequest(BaseModel):
    message: str = Field(min_length=2, max_length=4000)
    top_k: int = Field(default=5, ge=1, le=10)


class TeamChatMessageOut(BaseModel):
    id: int
    team_id: int
    user_id: Any
    user_email: str
    message: str
    response: str
    citations: list[Citation] = []
    created_at: datetime
    class Config: from_attributes = True


class EnterpriseCreate(BaseModel):
    enterprise_name: str = Field(min_length=2, max_length=150)
    admin_email: str = Field(min_length=3, max_length=255)
    temp_password: str | None = Field(default=None, max_length=128)
    tenant_id: str | None = "tenant-001"


class EnterpriseOut(BaseModel):
    id: int
    enterprise_name: str
    admin_email: str
    temp_password: str
    user_id: Any = None
    tenant_id: str
    is_active: bool
    created_at: datetime
    updated_at: datetime
    class Config: from_attributes = True


class EnterpriseStatusUpdate(BaseModel):
    is_active: bool
