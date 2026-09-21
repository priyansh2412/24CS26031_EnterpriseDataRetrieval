🌐 Frontend Stack
React 18 & TypeScript: Core UI library providing reactive state management and type-safety.
Vite: Ultra-fast build tool and dev server powering the client web app on http://localhost:5174/.
Lucide React: Modern icon service library for enterprise UI elements.
Vanilla CSS & Design Tokens: Custom styling system supporting Dark Black / Light themes, glassmorphism, responsive flex layouts, and smooth animations.


⚡ Backend & API Services
FastAPI (app.main:app): High-performance Python asynchronous web framework powering REST APIs on http://127.0.0.1:8000.
Uvicorn: ASGI web server running FastAPI with auto-reload capabilities.
Pydantic: Schema validation and settings management (pydantic-settings).


🧠 RAG, AI & Search Services
Groq SDK (groq): Low-latency AI Inference service API for LLM answer generation (llama-3.3-70b-versatile / llama3-8b-8192).
OpenAI API (openai): Supported fallback/provider LLM service integration.
Sentence Transformers (sentence-transformers): Local embedding service (all-MiniLM-L6-v2) used to compute dense vector embeddings for document text chunks.
ChromaDB (chromadb): In-memory / persistent Vector Database storing embeddings and performing fast Cosine Similarity vector searches.


📄 Multi-Format Document Ingestion Services
pdfplumber: PDF text extraction and document structure parsing.
python-docx: Microsoft Word (.docx) file parsing.
python-pptx: Microsoft PowerPoint (.pptx) presentation parsing.
openpyxl: Microsoft Excel (.xlsx) spreadsheet parsing.


🔐 Security & Database Services
SQLAlchemy 2.0 & SQLite (rag.db): Object-Relational Mapping (ORM) and relational DB engine storing persistent chat history, query logs, role-based users, feedback, and audit logs.
JWT Authentication (python-jose): Secure JSON Web Token authentication with bearer token tokens.
Passlib & Bcrypt (passlib[bcrypt]): Enterprise password hashing and verification service.
Role-Based Access Control (RBAC): Fine-grained access control module enforcing role access across Admin, HR, Manager, Finance, and Employee roles.