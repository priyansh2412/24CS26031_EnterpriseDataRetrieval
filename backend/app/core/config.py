from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

BASE_BACKEND_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = Path(__file__).resolve().parents[3]
ENV_PATHS = (
    str(ROOT_DIR / ".env"),
    str(BASE_BACKEND_DIR / ".env"),
    ".env"
)


class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql+psycopg://postgres:Hetvi%403207@localhost:5433/enterprise_rag"

    # Qdrant
    qdrant_url: str = "http://localhost:6333"
    qdrant_api_key: str = ""
    qdrant_collection: str = "document_chunks"

    # Gemini AI
    gemini_api_key: str = ""
    embedding_model: str = "gemini-embedding-2"
    embedding_dimension: int = 768
    gemini_model: str = "gemini-3-flash-preview"

    # Retrieval parameters
    top_k: int = 8
    final_context_k: int = 5

    # Auth & Security
    jwt_secret: str = "replace-this-with-a-long-random-secret"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 480
    cors_origins: str = "http://localhost:5173,http://localhost:3000,http://localhost:8000"

    # Local data directories
    data_directory: str = "./data"
    incoming_directory: str = "./data/incoming"

    # Google Drive & Ingestion automation
    documents_drive_link: str | None = None
    google_drive_folder_url: str | None = None
    google_drive_folder_id: str | None = None
    google_application_credentials: str | None = None
    google_drive_api_key: str | None = None

    # Tenancy defaults
    default_tenant_id: str = "tenant-001"
    default_project_id: str = "project-001"

    # Optional third-party providers
    groq_api_key: str | None = None
    openai_api_key: str | None = None

    @property
    def data_path(self) -> Path:
        p = Path(self.data_directory)
        if not p.is_absolute():
            p = BASE_BACKEND_DIR / self.data_directory
        return p

    @property
    def incoming_path(self) -> Path:
        p = Path(self.incoming_directory)
        if not p.is_absolute():
            p = BASE_BACKEND_DIR / self.incoming_directory
        return p

    model_config = SettingsConfigDict(
        env_file=ENV_PATHS,
        env_file_encoding="utf-8",
        extra="ignore"
    )


settings = Settings()
