from google.genai import types
from app.core.config import settings
from app.schemas import Citation
from app.services.embedding_service import get_genai_client
import re


def _prompt(question: str, citations: list[Citation]) -> str:
    context = "\n\n".join(
        f"[Source {i + 1}: {c.document_name}, chunk {c.chunk_index}]\n{c.text}"
        for i, c in enumerate(citations)
    )
    return (
        f"Answer only from the supplied context. If it is insufficient, say so. Cite factual claims with [Source N].\n\n"
        f"Question: {question}\n\n"
        f"Context:\n{context}"
    )


def generate_answer(question: str, citations: list[Citation]) -> str:
    if not citations:
        return (
            "I couldn't find any indexed documents matching your query. "
            "Please make sure relevant documents are uploaded in the Knowledge Library."
        )

    prompt = _prompt(question, citations)

    # 1. Primary: Google Gemini
    if settings.gemini_api_key:
        try:
            client = get_genai_client()
            response = client.models.generate_content(
                model=settings.gemini_model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    system_instruction="You are a precise, intelligent enterprise knowledge assistant. Cite sources with [Source N].",
                    temperature=0.2,
                ),
            )
            if response and response.text:
                return response.text
        except Exception as e:
            print(f"Gemini generate_answer failed: {e}")

    # 2. Fallback: Groq
    if settings.groq_api_key:
        try:
            from groq import Groq
            response = Groq(api_key=settings.groq_api_key).chat.completions.create(
                model="llama-3.3-70b-versatile",
                messages=[
                    {"role": "system", "content": "You are a precise enterprise knowledge assistant."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.1
            )
            return response.choices[0].message.content or "No answer generated."
        except Exception:
            pass

    # 3. Fallback: OpenAI
    if settings.openai_api_key:
        try:
            from openai import OpenAI
            response = OpenAI(api_key=settings.openai_api_key).chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {"role": "system", "content": "You are a precise enterprise knowledge assistant."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.1
            )
            return response.choices[0].message.content or "No answer generated."
        except Exception:
            pass

    # 4. Fallback: Extractive Grounded Answer
    return _extractive_answer(question, citations)


def _extractive_answer(question: str, citations: list[Citation]) -> str:
    if not citations:
        return "I could not find any relevant information to answer this question."

    top_c = citations[0]
    return f"Based on indexed record **{top_c.document_name}** [Source 1]:\n\n\"{top_c.text[:400].strip()}...\""


def summarize_document(text: str) -> str:
    if settings.gemini_api_key:
        try:
            client = get_genai_client()
            response = client.models.generate_content(
                model=settings.gemini_model,
                contents=f"Provide a concise executive summary with key takeaways of the following document:\n\n{text[:15000]}",
                config=types.GenerateContentConfig(
                    system_instruction="You are an enterprise executive document summarizer.",
                    temperature=0.2,
                ),
            )
            if response and response.text:
                return response.text
        except Exception as e:
            print(f"Gemini summarize failed: {e}")

    return f"Executive Summary:\nDocument content excerpt: {text[:300]}..."
