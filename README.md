# Enterprise Data Retrieval (RAG)

A modular academic RAG system built with FastAPI, PostgreSQL, ChromaDB, sentence-transformers, and React.

## Architecture

```text
Documents -> parsers -> chunks -> embeddings -> ChromaDB
     |                                      |
PostgreSQL <--- metadata, audit, feedback <- retrieval -> LLM -> cited answer
```

## Quick start

1. Copy `.env.example` to `.env` and add a Groq or OpenAI key.
2. Start infrastructure: `docker compose up -d db chroma`.
3. Backend: `cd backend`, create a virtual environment, install `pip install -r requirements.txt`, then `uvicorn app.main:app --reload`.
4. Frontend: `cd frontend`, `npm install`, then `npm run dev`.
5. Put supported files in `backend/data`, log in with `admin@example.com` / `ChangeMe123!`, and use **Ingest local folder**.

## Modules

| Module | Responsibility |
|---|---|
| `app/services/parsers.py` | PDF, DOCX, PPTX and XLSX text extraction |
| `app/services/ingestion.py` | deduplication, chunking, embedding and vector indexing |
| `app/services/retrieval.py` | semantic search and citation assembly |
| `app/services/llm.py` | Groq-first answer/summarization generation, OpenAI fallback |
| `app/routers` | auth, documents, chat, analytics and feedback APIs |
| `frontend/src/pages` | chat, document management and analytics UI |

## API flow

```text
POST /api/documents/ingest/local (Admin)
POST /api/chat/ask (authenticated) -> retrieve top-k -> LLM answer + exact citations
POST /api/feedback                 -> score an answer
GET  /api/analytics/overview       -> role-restricted usage reporting
```

The API documentation is available at `http://localhost:8000/docs`.
