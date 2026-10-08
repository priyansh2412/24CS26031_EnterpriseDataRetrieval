from google import genai
from google.genai import types
from app.core.config import settings

_client = None


def get_genai_client() -> genai.Client:
    global _client
    if _client is None:
        if not settings.gemini_api_key:
            raise ValueError(
                "GEMINI_API_KEY is not set in environment or .env file."
            )
        _client = genai.Client(api_key=settings.gemini_api_key)
    return _client


def embed_text(text: str) -> list[float]:
    client = get_genai_client()
    result = client.models.embed_content(
        model=settings.embedding_model,
        contents=text,
        config=types.EmbedContentConfig(
            output_dimensionality=settings.embedding_dimension
        )
    )
    return list(result.embeddings[0].values)


def embed_texts(texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    embeddings = []
    for text in texts:
        embeddings.append(embed_text(text))
    return embeddings