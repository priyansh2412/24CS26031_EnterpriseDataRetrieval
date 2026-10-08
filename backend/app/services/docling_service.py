from pathlib import Path
from typing import Any
import logging

logger = logging.getLogger(__name__)

_converter = None
_chunker = None


def get_docling_converter():
    global _converter
    if _converter is None:
        try:
            from docling.document_converter import DocumentConverter, PdfFormatOption
            from docling.datamodel.base_models import InputFormat
            from docling.datamodel.pipeline_options import PdfPipelineOptions, HeadingHierarchyOptions

            pipeline_options = PdfPipelineOptions()
            pipeline_options.do_ocr = False
            pipeline_options.do_table_structure = True
            pipeline_options.generate_parsed_pages = True
            pipeline_options.heading_hierarchy_options = HeadingHierarchyOptions(enabled=True)

            _converter = DocumentConverter(
                format_options={
                    InputFormat.PDF: PdfFormatOption(
                        pipeline_options=pipeline_options
                    )
                }
            )
        except Exception as e:
            logger.warning(f"Docling DocumentConverter lazy init notice: {e}")
            _converter = None
    return _converter


def get_docling_chunker():
    global _chunker
    if _chunker is None:
        try:
            from docling_core.transforms.chunker import HierarchicalChunker
            _chunker = HierarchicalChunker()
        except Exception as e:
            logger.warning(f"Docling HierarchicalChunker lazy init notice: {e}")
            _chunker = None
    return _chunker


def get_page_number(item: Any) -> int | None:
    try:
        if hasattr(item, "prov") and item.prov:
            return item.prov[0].page_no
    except Exception:
        pass
    return None


def build_section_path(metadata: Any) -> str | None:
    try:
        headings = getattr(metadata, "headings", None)
        if headings:
            return " > ".join(str(h).strip() for h in headings if str(h).strip())
    except Exception:
        pass
    return None


def parse_and_chunk_document(file_path: str | Path) -> list[dict[str, Any]]:
    """
    Sends document to Docling -> preserves headings, paragraphs, tables, pages, and section_path.
    Falls back gracefully for non-PDF or plain text files.
    """
    p = Path(file_path)
    suffix = p.suffix.lower()

    converter = get_docling_converter()
    chunker = get_docling_chunker()

    if converter and chunker and suffix in [".pdf", ".docx", ".pptx", ".html"]:
        try:
            result = converter.convert(str(p))
            doc = result.document
            raw_chunks = list(chunker.chunk(doc))

            parsed_chunks = []
            for index, chunk in enumerate(raw_chunks):
                chunk_text = chunk.text.strip()
                if not chunk_text:
                    continue

                page_start = None
                page_end = None
                try:
                    if hasattr(chunk, "meta") and hasattr(chunk.meta, "doc_items") and chunk.meta.doc_items:
                        pages = []
                        for item in chunk.meta.doc_items:
                            pg = get_page_number(item)
                            if pg is not None:
                                pages.append(pg)
                        if pages:
                            page_start = min(pages)
                            page_end = max(pages)
                except Exception:
                    pass

                section_path = build_section_path(getattr(chunk, "meta", None))

                parsed_chunks.append({
                    "chunk_index": index,
                    "text": chunk_text,
                    "page_start": page_start,
                    "page_end": page_end,
                    "section_path": section_path
                })

            if parsed_chunks:
                return parsed_chunks
        except Exception as e:
            logger.warning(f"Docling parsing warning on {p.name}: {e}. Using fallback parser...")

    # Fallback parser: handles text, markdown, or fallback PDF extraction
    return _fallback_parse_and_chunk(p)


def _fallback_parse_and_chunk(file_path: Path) -> list[dict[str, Any]]:
    text = ""
    suffix = file_path.suffix.lower()

    if suffix in [".txt", ".md", ".csv", ".json", ".log"]:
        text = file_path.read_text(encoding="utf-8", errors="ignore")
    elif suffix == ".pdf":
        try:
            import pdfplumber
            pages_text = []
            with pdfplumber.open(file_path) as pdf:
                for idx, page in enumerate(pdf.pages, start=1):
                    t = page.extract_text() or ""
                    if t.strip():
                        pages_text.append((idx, t))
            if pages_text:
                chunks = []
                c_idx = 0
                for pg_no, pg_txt in pages_text:
                    paras = [p.strip() for p in pg_txt.split("\n\n") if p.strip()]
                    current_section = f"Page {pg_no}"
                    for para in paras:
                        if len(para) < 80 and ("\n" not in para) and (para.isupper() or para.startswith(("#", "1.", "2.", "3.", "4.", "5.", "6.", "7.", "8.", "9."))):
                            current_section = para.strip("# ")
                        chunks.append({
                            "chunk_index": c_idx,
                            "text": para,
                            "page_start": pg_no,
                            "page_end": pg_no,
                            "section_path": current_section
                        })
                        c_idx += 1
                return chunks
        except Exception:
            pass

    if not text:
        text = file_path.read_text(encoding="utf-8", errors="ignore") if file_path.exists() else ""

    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    if not paragraphs and text:
        paragraphs = [text.strip()]

    chunks = []
    current_section = "General Overview"
    for idx, para in enumerate(paragraphs):
        lines = para.split("\n")
        first_line = lines[0].strip()
        if len(first_line) < 80 and (first_line.isupper() or first_line.startswith(("#", "1.", "2.", "3.", "Section"))):
            current_section = first_line.strip("# ")

        chunks.append({
            "chunk_index": idx,
            "text": para,
            "page_start": 1,
            "page_end": 1,
            "section_path": current_section
        })
    return chunks

