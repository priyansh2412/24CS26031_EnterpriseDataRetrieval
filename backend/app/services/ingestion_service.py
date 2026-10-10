import hashlib
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal, init_db
from app.models import (
    Chunk,
    Document,
    DocumentVersion,
    Source,
)
from app.services.acl_service import sync_document_acl_entries
from app.services.docling_service import parse_and_chunk_document
from app.services.embedding_service import embed_text
from app.services.google_drive_service import (
    download_drive_file,
    extract_drive_file_id,
    extract_drive_principal_keys,
    fetch_drive_metadata,
)
from app.services.qdrant_service import (
    delete_document_chunks,
    ensure_collection,
    upsert_chunk,
)


def calculate_file_hash(file_path: Path | str) -> str:
    sha256 = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(1024 * 1024):
            sha256.update(chunk)
    return sha256.hexdigest()


def ingest_document_file(
    file_path: Path | str,
    db: Session,
    tenant_id: str | None = None,
    project_id: str | None = None,
    source_type: str = "local",
    drive_metadata: dict[str, Any] | None = None,
    custom_principal_keys: list[str] | None = None,
    folder_path: str | None = None,
    drive_link_id: int | None = None,
) -> dict[str, Any]:
    """
    Ingests a document file into PostgreSQL and Qdrant.
    - Preserves headings, paragraphs, tables, pages, and section_path via Docling.
    - Stores chunk text in PostgreSQL.
    - Embeds with Gemini and upserts into Qdrant with the specified payload.
    - Handles SHA-256 deduplication and versioning.
    """
    init_db()
    ensure_collection()

    p = Path(file_path)
    if not p.exists() or not p.is_file():
        raise FileNotFoundError(f"File not found: {file_path}")

    eff_tenant = tenant_id or settings.default_tenant_id
    eff_project = project_id or settings.default_project_id
    ensure_collection(eff_tenant)
    checksum = calculate_file_hash(p)

    meta = drive_metadata or {}
    drive_id = meta.get("drive_file_id")
    source_uri = meta.get("web_view_link") or str(p.resolve())
    doc_name = meta.get("name") or p.name

    # Check if document already exists for this tenant
    existing_doc = (
        db.query(Document)
        .filter(
            (Document.tenant_id == eff_tenant) &
            (
                (Document.checksum == checksum) |
                (Document.source_uri == source_uri) |
                ((Document.drive_file_id == drive_id) if drive_id else False)
            )
        )
        .first()
    )

    if existing_doc and existing_doc.checksum == checksum and existing_doc.status == "ready":
        # Content unchanged: verify and update ACL if permissions changed
        pkeys = custom_principal_keys or (
            extract_drive_principal_keys(meta, eff_tenant, eff_project)
            if drive_id
            else [
                f"t:{eff_tenant}",
                f"p:{eff_project}",
                "r:employee",
                "r:admin",
                "g:group-hr",
                "r:hr",
                "r:finance",
                "r:manager",
            ]
        )
        sync_document_acl_entries(db, existing_doc.id, pkeys, origin="source_sync")
        return {
            "status": "already_ingested",
            "message": f"Document '{existing_doc.name}' content is unchanged. ACL verified.",
            "document_id": existing_doc.id,
            "chunks": existing_doc.chunk_count,
            "vectors": existing_doc.chunk_count,
        }

    # New or modified document
    doc_id = existing_doc.id if existing_doc else f"doc-{uuid.uuid4().hex[:12]}"
    ver_num = (
        db.query(DocumentVersion).filter(DocumentVersion.document_id == doc_id).count() + 1
        if existing_doc
        else 1
    )
    ver_id = f"ver-{uuid.uuid4().hex[:8]}"

    if not existing_doc:
        doc = Document(
            id=doc_id,
            tenant_id=eff_tenant,
            project_id=eff_project,
            name=doc_name,
            source=source_type,
            source_uri=source_uri,
            drive_file_id=drive_id,
            folder_path=folder_path or "/",
            drive_link_id=drive_link_id,
            mime_type=meta.get("mime_type") or "application/pdf",
            size_bytes=meta.get("size_bytes") or p.stat().st_size,
            owner_email=meta.get("owner_email"),
            web_view_link=meta.get("web_view_link"),
            revision_id=meta.get("revision_id"),
            modified_time=meta.get("modified_time") or datetime.utcnow(),
            checksum=checksum,
            source_hash=checksum,
            status="processing",
            acl_version=1,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(doc)
    else:
        doc = existing_doc
        doc.checksum = checksum
        doc.source_hash = checksum
        doc.status = "processing"
        doc.updated_at = datetime.utcnow()
        if folder_path:
            doc.folder_path = folder_path
        if drive_link_id:
            doc.drive_link_id = drive_link_id
        if drive_id:
            doc.drive_file_id = drive_id
            doc.web_view_link = meta.get("web_view_link")
            doc.revision_id = meta.get("revision_id")

        # Clean old chunks before re-indexing new version
        db.query(Chunk).filter(Chunk.document_id == doc_id).delete()
        delete_document_chunks(doc_id, tenant_id=eff_tenant)

    db.commit()

    # Create document version
    db.add(
        DocumentVersion(
            id=ver_id,
            document_id=doc_id,
            version_number=ver_num,
            version_no=ver_num,
            checksum=checksum,
            content_hash=checksum,
            revision_id=meta.get("revision_id"),
            file_size=p.stat().st_size,
            created_at=datetime.utcnow(),
        )
    )
    db.commit()

    # Parse and chunk with Docling
    chunks_data = parse_and_chunk_document(p)
    if not chunks_data:
        doc.status = "failed"
        db.commit()
        return {
            "status": "error",
            "message": "No extractable text found in document.",
            "document_id": doc_id,
            "chunks": 0,
            "vectors": 0,
        }

    # Resolve principal keys for document ACL
    principal_keys = custom_principal_keys or (
        extract_drive_principal_keys(meta, eff_tenant, eff_project)
        if drive_id
        else [
            f"t:{eff_tenant}",
            f"p:{eff_project}",
            "r:employee",
            "r:admin",
            "g:group-hr",
            "r:hr",
            "r:finance",
            "r:manager",
        ]
    )

    vector_count = 0
    for chunk in chunks_data:
        chunk_text = chunk["text"]
        chunk_id = str(uuid.uuid4())
        text_hash = hashlib.sha256(chunk_text.encode("utf-8")).hexdigest()

        # 1. Insert chunk into PostgreSQL chunks table
        db_chunk = Chunk(
            id=chunk_id,
            tenant_id=eff_tenant,
            document_id=doc_id,
            version_id=ver_id,
            project_id=eff_project,
            chunk_index=chunk["chunk_index"],
            page_start=chunk.get("page_start"),
            page_end=chunk.get("page_end"),
            section_path=chunk.get("section_path"),
            text=chunk_text,
            text_hash=text_hash,
            embedding_model=settings.embedding_model,
            index_state="indexed",
            created_at=datetime.utcnow(),
        )
        db.add(db_chunk)

        # 2. Generate Gemini embedding
        embedding = embed_text(chunk_text)

        # 3. Upsert into Qdrant with exact payload schema
        payload = {
            "chunk_id": chunk_id,
            "tenant_id": eff_tenant,
            "document_id": doc_id,
            "version_id": ver_id,
            "project_id": eff_project,
            "page_start": chunk.get("page_start"),
            "page_end": chunk.get("page_end"),
            "section_path": chunk.get("section_path"),
            "acl_version": doc.acl_version or 1,
            "principal_keys": principal_keys,
        }

        upsert_chunk(
            point_id=chunk_id,
            vector=embedding,
            payload=payload,
            tenant_id=eff_tenant
        )
        vector_count += 1

    doc.chunk_count = len(chunks_data)
    doc.status = "ready"
    db.commit()

    # Sync ACL entries and outbox
    sync_document_acl_entries(db, doc_id, principal_keys, origin="source_sync")

    return {
        "status": "success",
        "message": f"Successfully ingested {doc_name} ({len(chunks_data)} chunks, {vector_count} vectors).",
        "document_id": doc_id,
        "chunks": len(chunks_data),
        "vectors": vector_count,
    }


def ingest_from_drive_link(
    drive_link_or_id: str,
    db: Session,
    tenant_id: str | None = None,
    project_id: str | None = None,
    custom_principal_keys: list[str] | None = None,
    folder_path: str | None = None,
    drive_link_id: int | None = None,
) -> dict[str, Any]:
    """
    Admin adds a Google Drive file/folder link:
    - Extracts drive_file_id.
    - If folder: retrieves all contained files and ingests each one individually.
    - If single file: downloads and ingests the file.
    """
    from app.services.google_drive_service import fetch_drive_folder_details
    file_id, kind = extract_drive_file_id(drive_link_or_id)
    eff_tenant = tenant_id or settings.default_tenant_id
    eff_project = project_id or settings.default_project_id
    incoming_dir = settings.incoming_path

    if kind == "folder":
        folder_details = fetch_drive_folder_details(drive_link_or_id)
        folder_title = folder_details.get("name") or "Google Drive Folder"
        items = folder_details.get("items") or []
        effective_folder_path = folder_path or f"/{folder_title}"
        if not effective_folder_path.startswith("/"):
            effective_folder_path = f"/{effective_folder_path}"

        total_ingested = 0
        total_chunks = 0
        total_vectors = 0
        results = []

        for item in items:
            item_id = item.get("id")
            if not item_id:
                continue
            try:
                target_path, meta = download_drive_file(item_id, incoming_dir, metadata={
                    "drive_file_id": item_id,
                    "name": item.get("name"),
                    "mime_type": item.get("mime_type", "application/pdf"),
                    "web_view_link": f"https://drive.google.com/file/d/{item_id}/view"
                })
                res = ingest_document_file(
                    file_path=target_path,
                    db=db,
                    tenant_id=eff_tenant,
                    project_id=eff_project,
                    source_type="google_drive",
                    drive_metadata=meta,
                    custom_principal_keys=custom_principal_keys,
                    folder_path=effective_folder_path,
                    drive_link_id=drive_link_id,
                )
                total_ingested += 1
                total_chunks += res.get("chunks", 0)
                total_vectors += res.get("vectors", 0)
                results.append(res)
            except Exception as e:
                db.rollback()
                print(f"Error ingesting item {item.get('name')}: {e}")

        return {
            "status": "success",
            "message": f"Successfully ingested folder '{folder_title}' with {total_ingested} files ({total_chunks} chunks, {total_vectors} vectors).",
            "folder_name": folder_title,
            "count": total_ingested,
            "chunks": total_chunks,
            "vectors": total_vectors,
            "results": results,
        }

    # Single File
    target_path, meta = download_drive_file(file_id, incoming_dir)
    return ingest_document_file(
        file_path=target_path,
        db=db,
        tenant_id=eff_tenant,
        project_id=eff_project,
        source_type="google_drive",
        drive_metadata=meta,
        custom_principal_keys=custom_principal_keys,
        folder_path=folder_path,
        drive_link_id=drive_link_id,
    )


def ingest_directory_files(directory: Path | str, db: Session, tenant_id: str | None = None) -> list[dict[str, Any]]:
    """Ingests all valid documents in local directory for the specified tenant."""
    dir_path = Path(directory)
    dir_path.mkdir(parents=True, exist_ok=True)
    results = []
    supported_exts = {".pdf", ".docx", ".pptx", ".txt", ".md", ".csv"}

    eff_tenant = tenant_id or settings.default_tenant_id

    for f in dir_path.rglob("*"):
        if f.is_file() and f.suffix.lower() in supported_exts:
            try:
                res = ingest_document_file(f, db, tenant_id=eff_tenant, source_type="local")
                results.append(res)
            except Exception as e:
                print(f"Error ingesting file {f.name}: {e}")
                results.append({"status": "error", "file": f.name, "error": str(e)})

    return results


def auto_ingest_all_sources(db: Session):
    """
    Automated startup ingestion:
    Documents are strictly ingested through Google Drive links.
    """
    drive_link = (
        settings.documents_drive_link
        or settings.google_drive_folder_url
        or settings.google_drive_folder_id
    )
    if drive_link:
        try:
            print(f"Automating ingestion from Google Drive link: {drive_link}")
            res = ingest_from_drive_link(drive_link, db)
            print(f"Drive ingestion result: {res.get('status')}")
        except Exception as e:
            print(f"Auto drive ingestion error: {e}")