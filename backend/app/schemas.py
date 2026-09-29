from datetime import datetime
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
    id: int
    email: str
    role: Role
    role_key: str | None = "employee"
    rank_level: int = 5
    is_active: bool = True
    class Config: from_attributes = True


class UserCreate(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=8, max_length=128)
    role: Role = Role.EMPLOYEE
    role_key: str | None = "employee"
    rank_level: int | None = 5


class UserUpdate(BaseModel):
    role: Role | None = None
    role_key: str | None = None
    rank_level: int | None = None
    is_active: bool | None = None


class ForgotPasswordRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)


class AuditLogOut(BaseModel):
    id: int
    user_id: int | None
    user_email: str | None = None
    user_role_key: str | None = None
    user_rank_level: int | None = None
    action: str
    resource_type: str
    resource_id: str | None
    severity: str = "INFO"
    detail: str | None
    created_at: datetime
    class Config: from_attributes = True


class AskRequest(BaseModel):
    question: str = Field(min_length=2, max_length=4000)
    top_k: int = Field(default=5, ge=1, le=10)
    team_id: int | None = None


class Citation(BaseModel):
    document_id: int
    document_name: str
    chunk_index: int
    text: str
    score: float


class AskResponse(BaseModel):
    query_log_id: int
    answer: str
    citations: list[Citation]


class DocumentOut(BaseModel):
    id: int
    name: str
    source: str
    status: str
    chunk_count: int
    access_roles: str
    summary: str | None
    created_at: datetime
    class Config: from_attributes = True


class FeedbackIn(BaseModel):
    query_log_id: int
    is_positive: bool
    comment: str | None = Field(default=None, max_length=1000)


class DocumentAccessUpdate(BaseModel):
    roles: list[Role] = Field(min_length=1)


class TeamCreate(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    project_name: str = Field(min_length=2, max_length=150)
    description: str | None = Field(default=None, max_length=1000)


class TeamMemberOut(BaseModel):
    id: int
    user_id: int
    user_email: str
    user_role_key: str | None = None
    user_rank_level: int | None = None
    role_in_team: str = "member"
    class Config: from_attributes = True


class TeamOut(BaseModel):
    id: int
    name: str
    project_name: str
    description: str | None
    created_by_id: int
    created_at: datetime
    members: list[TeamMemberOut] = []
    class Config: from_attributes = True


class TeamMemberAdd(BaseModel):
    user_id: int
    role_in_team: str = "member"


class TeamChatRequest(BaseModel):
    message: str = Field(min_length=2, max_length=4000)
    top_k: int = Field(default=5, ge=1, le=10)


class TeamChatMessageOut(BaseModel):
    id: int
    team_id: int
    user_id: int
    user_email: str
    message: str
    response: str
    citations: list[Citation] = []
    created_at: datetime
    class Config: from_attributes = True

