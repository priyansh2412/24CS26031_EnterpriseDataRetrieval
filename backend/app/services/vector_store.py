from functools import lru_cache
import chromadb
from chromadb.config import Settings as ChromaSettings
from sentence_transformers import SentenceTransformer
from app.core.config import settings

COLLECTION = "document_chunks"


@lru_cache
def embedder() -> SentenceTransformer:
    return SentenceTransformer("all-MiniLM-L6-v2")


@lru_cache
def collection():
    # Persistent remote service is production-friendly; fallback makes initial local use easier.
    client = chromadb.HttpClient(host=settings.chroma_host, port=settings.chroma_port, settings=ChromaSettings(anonymized_telemetry=False))
    return client.get_or_create_collection(COLLECTION, metadata={"hnsw:space": "cosine"})


def embed(texts: list[str]) -> list[list[float]]:
    return embedder().encode(texts, normalize_embeddings=True).tolist()


def upsert_chunks(document_id: int, chunks: list[str]) -> None:
    ids = [f"{document_id}:{index}" for index in range(len(chunks))]
    collection().upsert(ids=ids, documents=chunks, embeddings=embed(chunks), metadatas=[{"document_id": document_id, "chunk_index": index} for index in range(len(chunks))])


def delete_document(document_id: int) -> None:
    collection().delete(where={"document_id": document_id})
