from app.core.config import settings
from app.schemas import Citation
import re


def _prompt(question: str, citations: list[Citation]) -> str:
    context = "\n\n".join(f"[Source {i + 1}: {c.document_name}, chunk {c.chunk_index}]\n{c.text}" for i, c in enumerate(citations))
    return f"Answer only from the supplied context. If it is insufficient, say so. Cite factual claims with [Source N].\n\nQuestion: {question}\n\nContext:\n{context}"


def generate_answer(question: str, citations: list[Citation]) -> str:
    prompt = _prompt(question, citations)
    if settings.groq_api_key:
        from groq import Groq
        response = Groq(api_key=settings.groq_api_key).chat.completions.create(model="llama-3.3-70b-versatile", messages=[{"role": "system", "content": "You are a precise enterprise knowledge assistant."}, {"role": "user", "content": prompt}], temperature=0.1)
        return response.choices[0].message.content or "No answer generated."
    if settings.openai_api_key:
        from openai import OpenAI
        response = OpenAI(api_key=settings.openai_api_key).chat.completions.create(model="gpt-4o-mini", messages=[{"role": "system", "content": "You are a precise enterprise knowledge assistant."}, {"role": "user", "content": prompt}], temperature=0.1)
        return response.choices[0].message.content or "No answer generated."
    return _extractive_answer(question, citations)


def _extractive_answer(question: str, citations: list[Citation]) -> str:
    """Provide a useful, grounded answer in local mode without an LLM API key."""
    if not citations:
        return (
            "I couldn't find any indexed documents matching your query. "
            "Please make sure relevant documents are uploaded in the Knowledge Library."
        )

    stop_words = {"a", "an", "and", "are", "the", "is", "of", "for", "to", "in", "on", "what", "which", "how", "does", "do", "about", "tell", "me", "our", "us"}
    terms = [word for word in re.findall(r"[a-z0-9]+", question.lower()) if len(word) > 2 and word not in stop_words]

    candidates: list[tuple[float, int, str]] = []
    for source_index, citation in enumerate(citations, 1):
        sentences = re.split(r"(?<=[.!?\n])\s+", citation.text)
        for sentence_index, sentence in enumerate(sentences):
            clean_s = sentence.strip()
            if len(clean_s) < 25:
                continue
            s_lower = clean_s.lower()
            overlap = sum(1 for term in terms if term in s_lower)
            score = (overlap * 2.0) + (citation.score * 1.5)
            candidates.append((score, -sentence_index, f"{clean_s} [Source {source_index}]"))

    # Sort candidates by score descending
    candidates.sort(key=lambda x: x[0], reverse=True)

    # Deduplicate candidate sentences
    seen_texts = set()
    selected_sentences = []
    for score, _, sentence in candidates:
        plain_text = sentence.split(" [Source")[0].lower()
        if plain_text not in seen_texts:
            seen_texts.add(plain_text)
            selected_sentences.append(sentence)
        if len(selected_sentences) >= 4:
            break

    if not selected_sentences:
        # Fallback to top citation snippet directly
        top_citation = citations[0]
        snippet = top_citation.text[:300].strip()
        return f"Based on indexed document **{top_citation.document_name}** [Source 1]:\n\n\"{snippet}...\""

    top_doc_name = citations[0].document_name
    lines = [f"Based on your organization's indexed records (e.g., **{top_doc_name}**):\n"]
    for s in selected_sentences:
        lines.append(f"• {s}")

    return "\n".join(lines)


def summarize_document(text: str) -> str:
    return generate_answer("Provide a concise executive summary of this document.", [Citation(document_id=0, document_name="document", chunk_index=0, text=text[:12000], score=1)])

