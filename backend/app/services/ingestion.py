import hashlib
from pathlib import Path
from sqlalchemy.orm import Session
from app.models import Document
from app.services.parsers import SUPPORTED_EXTENSIONS, extract_text
from app.services.vector_store import delete_document, upsert_chunks


def chunk_text(text: str, size: int = 500, overlap: int = 75) -> list[str]:
    """Word-token approximation: simple, inspectable and suitable for MiniLM input."""
    words = text.split()
    step = size - overlap
    return [" ".join(words[start:start + size]) for start in range(0, len(words), step) if words[start:start + size]]


def ingest_file(path: Path, db: Session, source: str = "local") -> Document:
    raw = path.read_bytes()
    checksum = hashlib.sha256(raw).hexdigest()
    uri = str(path.resolve())
    document = db.query(Document).filter(Document.source_uri == uri).first()
    if document and document.checksum == checksum:
        return document
    if not document:
        document = Document(name=path.name, source=source, source_uri=uri, checksum=checksum)
        db.add(document); db.flush()
    else:
        delete_document(document.id)
        document.checksum = checksum
    try:
        document.status = "processing"; db.commit()
        chunks = chunk_text(extract_text(path))
        if not chunks: raise ValueError("No extractable text found")
        upsert_chunks(document.id, chunks)
        document.chunk_count, document.status = len(chunks), "ready"
    except Exception:
        document.status = "failed"; db.commit(); raise
    db.commit(); db.refresh(document)
    return document


def ingest_directory(directory: Path, db: Session) -> list[Document]:
    directory.mkdir(parents=True, exist_ok=True)
    return [ingest_file(file, db) for file in directory.rglob("*") if file.is_file() and file.suffix.lower() in SUPPORTED_EXTENSIONS]
