from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    database_url: str = "sqlite:///./rag.db"  # convenient fallback for a demo
    chroma_host: str = "localhost"
    chroma_port: int = 8001
    jwt_secret: str = "development-only-change-me"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 480
    groq_api_key: str | None = None
    openai_api_key: str | None = None
    data_directory: str = "./data"
    cors_origins: str = "http://localhost:5173"

    @property
    def data_path(self) -> Path:
        return Path(self.data_directory)


settings = Settings()
