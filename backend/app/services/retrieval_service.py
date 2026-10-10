from sqlalchemy.orm import Session
from app.core.config import settings
from app.models import Chunk, Document, Role, User
from app.services.acl_service import resolve_user_principals, verify_document_access
from app.services.embedding_service import embed_text
from app.services.qdrant_service import search


def retrieve_authorized_chunks(
    question: str,
    db: Session,
    user: User | None = None,
    top_k: int | None = None,
    document_id: str | None = None,
    tenant_id: str | None = None,
    project_id: str | None = None,
) -> list[dict]:
    """
    1. Resolves user's principals (u:, g:, p:, r:, t: keys).
    2. Embeds question using Gemini.
    3. Searches Qdrant filtered by tenant_id + matching principal_keys.
    4. Fetches chunk text and metadata from PostgreSQL chunks table.
    5. Performs final PostgreSQL authorization check on each document.
    6. Returns ranked, authorized chunks.
    """
    limit = top_k or settings.top_k
    eff_tenant = str(tenant_id or (user.tenant_id if user and getattr(user, "tenant_id", None) else settings.default_tenant_id))

    # 1. Resolve user principal keys
    principal_keys = None
    if user:
        if user.role != Role.ADMIN and user.rank_level > 1:
            principal_keys = resolve_user_principals(db, user, eff_tenant, project_id)

    # 2. Embed query vector
    query_vector = embed_text(question)

    # 3. Search Qdrant vector collection
    points = search(
        vector=query_vector,
        limit=limit * 3,  # Fetch slightly more to account for PostgreSQL authorization check
        tenant_id=eff_tenant,
        principal_keys=principal_keys,
        document_id=document_id,
    )

    if not points:
        return []

    chunk_ids = [str(pt.id) for pt in points]

    # 4. Fetch complete chunk records from PostgreSQL strictly scoped to eff_tenant
    db_chunks = db.query(Chunk).filter(Chunk.id.in_(chunk_ids), Chunk.tenant_id == eff_tenant).all()
    chunk_map = {str(c.id): c for c in db_chunks}

    # Fetch referenced documents for metadata & ACL verification strictly scoped to eff_tenant
    doc_ids = {c.document_id for c in db_chunks}
    docs = db.query(Document).filter(Document.id.in_(doc_ids), Document.tenant_id == eff_tenant).all()
    doc_map = {str(d.id): d for d in docs}

    results = []
    for pt in points:
        cid = str(pt.id)
        db_chunk = chunk_map.get(cid)
        if not db_chunk:
            continue

        doc = doc_map.get(str(db_chunk.document_id))
        if not doc:
            continue

        # 5. Final PostgreSQL authorization check
        if user and not verify_document_access(db, user, doc.id):
            continue

        results.append({
            "chunk_id": db_chunk.id,
            "document_id": doc.id,
            "document_name": doc.name,
            "chunk_index": db_chunk.chunk_index,
            "page_start": db_chunk.page_start,
            "page_end": db_chunk.page_end,
            "section_path": db_chunk.section_path,
            "text": db_chunk.text,
            "score": float(pt.score) if pt.score is not None else 0.95,
        })

        if len(results) >= limit:
            break

    return results


# Backward compatibility alias
def retrieve(
    question: str,
    db: Session,
    top_k: int = 5,
    user: User | None = None,
    document_id: str | None = None
) -> list[dict]:
    return retrieve_authorized_chunks(
        question=question,
        db=db,
        user=user,
        top_k=top_k,
        document_id=document_id
    )