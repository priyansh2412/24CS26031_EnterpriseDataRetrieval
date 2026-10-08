from qdrant_client import QdrantClient, models
from app.core.config import settings

_client = None


def get_qdrant_client() -> QdrantClient:
    global _client
    if _client is None:
        _client = QdrantClient(
            url=settings.qdrant_url,
            api_key=settings.qdrant_api_key or None
        )
    return _client


def ensure_collection():
    client = get_qdrant_client()
    collections = client.get_collections().collections
    existing = {collection.name for collection in collections}

    if settings.qdrant_collection not in existing:
        client.create_collection(
            collection_name=settings.qdrant_collection,
            vectors_config=models.VectorParams(
                size=settings.embedding_dimension,
                distance=models.Distance.COSINE
            )
        )
        # Create payload indexes for efficient filtering
        try:
            client.create_payload_index(
                collection_name=settings.qdrant_collection,
                field_name="tenant_id",
                field_schema=models.PayloadSchemaType.KEYWORD
            )
            client.create_payload_index(
                collection_name=settings.qdrant_collection,
                field_name="document_id",
                field_schema=models.PayloadSchemaType.KEYWORD
            )
            client.create_payload_index(
                collection_name=settings.qdrant_collection,
                field_name="principal_keys",
                field_schema=models.PayloadSchemaType.KEYWORD
            )
        except Exception:
            pass


def upsert_chunk(
    point_id: str,
    vector: list[float],
    payload: dict
):
    client = get_qdrant_client()
    client.upsert(
        collection_name=settings.qdrant_collection,
        points=[
            models.PointStruct(
                id=point_id,
                vector=vector,
                payload=payload
            )
        ],
        wait=True
    )


def update_document_acl_payload(
    document_id: str,
    principal_keys: list[str],
    acl_version: int
):
    """
    Updates the ACL payload (principal_keys & acl_version) for all chunks of a document in Qdrant
    without re-embedding.
    """
    client = get_qdrant_client()
    client.set_payload(
        collection_name=settings.qdrant_collection,
        payload={
            "principal_keys": principal_keys,
            "acl_version": acl_version
        },
        points=models.Filter(
            must=[
                models.FieldCondition(
                    key="document_id",
                    match=models.MatchValue(value=str(document_id))
                )
            ]
        ),
        wait=True
    )


def delete_document_chunks(document_id: str):
    client = get_qdrant_client()
    try:
        client.delete(
            collection_name=settings.qdrant_collection,
            points_selector=models.FilterSelector(
                filter=models.Filter(
                    must=[
                        models.FieldCondition(
                            key="document_id",
                            match=models.MatchValue(value=str(document_id))
                        )
                    ]
                )
            ),
            wait=True
        )
    except Exception:
        pass


def search(
    vector: list[float],
    limit: int = 8,
    tenant_id: str = "tenant-001",
    principal_keys: list[str] | None = None,
    document_id: str | None = None
):
    client = get_qdrant_client()
    must_conditions = []

    if tenant_id:
        must_conditions.append(
            models.FieldCondition(
                key="tenant_id",
                match=models.MatchValue(value=tenant_id)
            )
        )

    if document_id:
        must_conditions.append(
            models.FieldCondition(
                key="document_id",
                match=models.MatchValue(value=str(document_id))
            )
        )

    if principal_keys is not None and len(principal_keys) > 0:
        # User must match at least one of the document's allowed principal_keys
        # In Qdrant keyword arrays, MatchAny checks if the point's principal_keys contains any key in principal_keys
        must_conditions.append(
            models.FieldCondition(
                key="principal_keys",
                match=models.MatchAny(any=principal_keys)
            )
        )

    query_filter = models.Filter(must=must_conditions) if must_conditions else None

    result = client.query_points(
        collection_name=settings.qdrant_collection,
        query=vector,
        query_filter=query_filter,
        limit=limit,
        with_payload=True,
        with_vectors=False
    )

    return result.points