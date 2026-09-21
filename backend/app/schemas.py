from datetime import datetime
from pydantic import BaseModel, Field
from app.models import Role


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    email: str
    role: Role
    class Config: from_attributes = True


class UserCreate(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=8, max_length=128)
    role: Role = Role.EMPLOYEE


class UserUpdate(BaseModel):
    role: Role | None = None
    is_active: bool | None = None


class ForgotPasswordRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)


class AuditLogOut(BaseModel):
    id: int
    user_id: int | None
    user_email: str | None = None
    action: str
    resource_type: str
    resource_id: str | None
    detail: str | None
    created_at: datetime
    class Config: from_attributes = True


class AskRequest(BaseModel):
    question: str = Field(min_length=2, max_length=4000)
    top_k: int = Field(default=5, ge=1, le=10)


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
