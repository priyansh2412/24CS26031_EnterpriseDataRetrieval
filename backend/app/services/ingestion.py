from pathlib import Path
from sqlalchemy.orm import Session
from app.models import Document
from app.services.ingestion_service import (
    ingest_directory_files,
    ingest_document_file,
    ingest_from_drive_link,
)


def ingest_file(path: Path | str, db: Session, source: str = "local") -> Document:
    res = ingest_document_file(path, db, source_type=source)
    doc_id = res.get("document_id")
    return db.query(Document).filter(Document.id == doc_id).first()


def ingest_directory(directory: Path | str, db: Session) -> list[Document]:
    ingest_directory_files(directory, db)
    return db.query(Document).order_by(Document.created_at.desc()).all()
