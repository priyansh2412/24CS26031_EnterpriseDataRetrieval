from sqlalchemy.orm import Session
from app.models import User
from app.schemas import Citation
from app.services.citation_service import format_context_prompt
from app.services.retrieval_service import retrieve_authorized_chunks


def retrieve(
    question: str,
    db: Session,
    top_k: int = 5,
    user: User | None = None,
    document_id: str | None = None
) -> list[Citation]:
    chunks = retrieve_authorized_chunks(
        question=question,
        db=db,
        user=user,
        top_k=top_k,
        document_id=document_id
    )
    _, citations = format_context_prompt(chunks)
    return citations
