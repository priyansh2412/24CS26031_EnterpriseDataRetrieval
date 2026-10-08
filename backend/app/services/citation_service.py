from app.schemas import Citation, Source


def format_context_prompt(chunks: list[dict]) -> tuple[str, list[Citation]]:
    """
    Formats retrieved chunks into a standardized context block for Gemini
    and extracts structured Citation models for the API response.
    """
    if not chunks:
        return "", []

    context_parts = []
    citations = []

    for index, chunk in enumerate(chunks, start=1):
        doc_id = chunk.get("document_id", "unknown")
        doc_name = chunk.get("document_name") or chunk.get("name") or f"Document {doc_id}"
        chunk_id = chunk.get("chunk_id", f"chk-{index}")
        chunk_index = chunk.get("chunk_index", index - 1)
        page_start = chunk.get("page_start")
        page_end = chunk.get("page_end")
        section_path = chunk.get("section_path") or "General"
        text = chunk.get("text", "").strip()
        score = chunk.get("score") if chunk.get("score") is not None else 0.9

        page_str = (
            f"Page {page_start}"
            if page_start == page_end and page_start is not None
            else f"Pages {page_start}-{page_end}"
            if page_start is not None
            else "General"
        )

        block = (
            f"--- [Source {index}] ---\n"
            f"Document: {doc_name} (ID: {doc_id})\n"
            f"Location: {page_str} | Section: {section_path}\n"
            f"Content:\n{text}\n"
        )
        context_parts.append(block)

        citations.append(
            Citation(
                document_id=doc_id,
                document_name=doc_name,
                chunk_index=chunk_index,
                text=text,
                score=round(float(score), 4),
                page_start=page_start,
                page_end=page_end,
                section_path=section_path if section_path != "General" else None,
                chunk_id=chunk_id
            )
        )

    formatted_context = "\n".join(context_parts)
    return formatted_context, citations
