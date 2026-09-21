# Implementation guide

## 1. Data model and access control

PostgreSQL is the system of record for users, document metadata, query audit logs and feedback. ChromaDB contains only chunk vectors plus the document/chunk identifiers. This separation allows the vector index to be rebuilt without losing governance data.

JWTs carry a user id and role. `require_role` protects administrative ingestion, deletion and analytics endpoints. Guests can be added later as a read-only role by including `Role.GUEST` on the desired retrieval dependency.

## 2. Ingestion pipeline

1. The admin places files in `backend/data` and calls `POST /api/documents/ingest/local`.
2. `parsers.py` chooses a parser from the file extension and labels pages, slides and sheets in extracted text.
3. `chunk_text` makes ~500 word-token chunks with a 75-token overlap, helping answers retain context at boundaries.
4. `all-MiniLM-L6-v2` embeds every chunk. The chunks and embeddings are upserted into Chroma using stable IDs such as `12:3`.
5. PostgreSQL saves operational status and chunk count. A SHA-256 checksum prevents repeated indexing of unchanged local files.

For a production deployment, perform ingestion via Celery/RQ/background workers so that large documents do not hold the HTTP request open. `sources.py` provides isolated Google Drive and S3 adapters; keep service-account JSON and cloud credentials in a secrets manager.

## 3. Retrieval-augmented answer flow

```text
Question
  -> MiniLM query vector
  -> Chroma cosine top-k results
  -> SQL metadata lookup
  -> context prompt with numbered sources
  -> Groq Llama 3.3 (or OpenAI fallback)
  -> answer, exact chunk citations, query audit row
```

The UI renders the exact chunk sent to the model under every answer. This makes citations inspectable rather than merely linking to a filename.

## 4. API reference

| Endpoint | Role | Purpose |
|---|---|---|
| `POST /api/auth/login` | Public | OAuth2 form login; returns a JWT |
| `GET /api/auth/me` | Any signed-in user | Current identity and role |
| `POST /api/documents/ingest/local` | Admin | Scan and ingest the local data folder |
| `GET /api/documents` | Admin, User | List/filter indexed documents |
| `POST /api/documents/{id}/reingest` | Admin | Rebuild one document’s chunks |
| `DELETE /api/documents/{id}` | Admin | Remove SQL metadata and vectors |
| `POST /api/documents/{id}/summary` | Admin, User | Generate an executive summary |
| `POST /api/chat/ask` | Any signed-in user | Grounded answer plus citations |
| `POST /api/feedback` | Any signed-in user | Helpful/not-helpful answer signal |
| `GET /api/analytics/overview` | Admin | Document/query usage metrics |

Example answer request:

```json
{ "question": "What are the project risks?", "top_k": 5 }
```

## 5. Sprint roadmap

| Sprint | Additions |
|---|---|
| 1 (included) | Local ingestion, parsing, vector search, cited chat, JWT/RBAC, document and analytics UI |
| 2 | Alembic migrations, async worker, upload endpoint, Drive OAuth and source-sync scheduler |
| 3 | PostgreSQL full-text/hybrid reranking, document-level permissions, dashboards for feedback and document usage |
| 4 | Structured LLM entity extraction; store `subject-predicate-object` edges and add graph-assisted retrieval |

## 6. Production checklist

- Replace the development JWT secret and seeded administrator password.
- Run Alembic migrations rather than `Base.metadata.create_all`.
- Restrict CORS to the deployed frontend origin.
- Put Chroma/PostgreSQL on private networking, enable database backups, and add encrypted object storage for source files.
- Rate-limit login and chat endpoints, set token expiry appropriate to the organization, and redact secrets/PII from audit logs where required.
