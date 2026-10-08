from google.genai import types
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import User
from app.services.citation_service import format_context_prompt
from app.services.embedding_service import get_genai_client
from app.services.retrieval_service import retrieve_authorized_chunks

SYSTEM_INSTRUCTION = """You are an intelligent, precise enterprise RAG assistant.
Your task is to answer the user's question accurately using ONLY the provided context sources.

Guidelines:
1. Base your answer strictly on the context provided. Do not fabricate or extrapolate beyond what the sources state.
2. If the provided context does not contain enough information to answer the question, state clearly: "Based on the provided documents, I could not find information to answer this question."
3. Cite the relevant source numbers within your answer using bracket notation like [Source 1], [Source 2] where appropriate.
4. Keep the response clear, structured, and easy to read with bullet points or paragraphs where helpful.
"""


def answer_question(
    question: str,
    db: Session,
    user: User | None = None,
    document_id: str | None = None,
    top_k: int | None = None,
) -> dict:
    """
    RAG pipeline:
    1. Retrieve authorized chunks from Qdrant vector search + PostgreSQL ACL check.
    2. Format prompt context and citation metadata.
    3. Generate grounded answer using Gemini.
    4. Return answer and structured citations.
    """
    chunks = retrieve_authorized_chunks(
        question=question,
        db=db,
        user=user,
        top_k=top_k or settings.top_k,
        document_id=document_id,
    )

    if not chunks:
        return {
            "answer": "I could not find any relevant information in your authorized documents to answer your question.",
            "sources": [],
            "citations": [],
        }

    # Select top final_context_k chunks
    selected_chunks = chunks[: settings.final_context_k]
    context_text, citations = format_context_prompt(selected_chunks)

    prompt = (
        f"Context Sources:\n"
        f"{context_text}\n\n"
        f"User Question: {question}\n\n"
        f"Answer:"
    )

    try:
        client = get_genai_client()
        response = client.models.generate_content(
            model=settings.gemini_model,
            contents=prompt,
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_INSTRUCTION,
                temperature=0.2,
            ),
        )
        answer_text = response.text if response and response.text else "No response generated."
    except Exception as e:
        print(f"Gemini generation error: {e}. Falling back to extractive answer.")
        answer_text = f"Based on retrieved documents:\n\n" + "\n\n".join(
            f"• {c.text[:250]}... [Source {idx+1}]" for idx, c in enumerate(citations[:3])
        )

    return {
        "answer": answer_text,
        "citations": citations,
        "sources": citations,
    }