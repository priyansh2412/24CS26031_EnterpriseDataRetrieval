import re
from sqlalchemy.orm import Session
from app.models import Document
from app.schemas import Citation
from app.services.vector_store import collection, embed


def retrieve(question: str, db: Session, top_k: int) -> list[Citation]:
    result = collection().query(
        query_embeddings=embed([question]),
        n_results=min(top_k * 4, 20),
        include=["documents", "metadatas", "distances"]
    )
    if not result or not result.get("documents") or not result["documents"][0]:
        return []

    stop_words = {"a", "an", "and", "are", "the", "is", "of", "for", "to", "in", "on", "what", "which", "how", "does", "do", "about"}
    q_words = [w for w in re.findall(r"[a-z0-9]+", question.lower()) if len(w) > 2 and w not in stop_words]

    citations: list[Citation] = []
    for text, metadata, distance in zip(result["documents"][0], result["metadatas"][0], result["distances"][0]):
        document = db.get(Document, int(metadata["document_id"]))
        if document and document.status == "ready":
            # Distance in cosine space ranges 0.0 (exact match) to 2.0
            base_similarity = max(0.05, 1.0 - float(distance))
            # Boost score based on query word overlap
            text_lower = text.lower()
            keyword_matches = sum(1 for w in q_words if w in text_lower)
            boost = (keyword_matches / max(len(q_words), 1)) * 0.3
            final_score = round(min(0.99, base_similarity + boost), 4)

            citations.append(
                Citation(
                    document_id=document.id,
                    document_name=document.name,
                    chunk_index=int(metadata["chunk_index"]),
                    text=text,
                    score=final_score,
                )
            )

    # Sort by final score descending
    citations.sort(key=lambda c: c.score, reverse=True)
    return citations[:top_k]

