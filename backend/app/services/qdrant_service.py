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


def get_tenant_collection_name(tenant_id: str | None = None) -> str:
    """
    Returns the dedicated Qdrant collection name for a given tenant.
    For default or unassigned tenants, uses settings.qdrant_collection.
    For specific enterprises, uses a distinct collection name (e.g., chunks_tenant_apex_123).
    """
    if not tenant_id or str(tenant_id).strip() in ["tenant-001", "default", ""]:
        return settings.qdrant_collection

    clean_id = str(tenant_id).strip().replace("-", "_").replace(" ", "_").lower()
    return f"chunks_{clean_id}"


def ensure_collection(tenant_id: str | None = None):
    """
    Ensures that the dedicated collection exists for the tenant in Qdrant,
    and sets up payload indexes for tenant_id, document_id, and principal_keys.
    """
    client = get_qdrant_client()
    coll_name = get_tenant_collection_name(tenant_id)

    try:
        collections = client.get_collections().collections
        existing = {c.name for c in collections}
    except Exception:
        existing = set()

    if coll_name not in existing:
        try:
            client.create_collection(
                collection_name=coll_name,
                vectors_config=models.VectorParams(
                    size=settings.embedding_dimension,
                    distance=models.Distance.COSINE
                )
            )
        except Exception:
            pass

        # Create payload indexes for fast filtering
        try:
            client.create_payload_index(
                collection_name=coll_name,
                field_name="tenant_id",
                field_schema=models.PayloadSchemaType.KEYWORD
            )
            client.create_payload_index(
                collection_name=coll_name,
                field_name="document_id",
                field_schema=models.PayloadSchemaType.KEYWORD
            )
            client.create_payload_index(
                collection_name=coll_name,
                field_name="principal_keys",
                field_schema=models.PayloadSchemaType.KEYWORD
            )
            client.create_payload_index(
                collection_name=coll_name,
                field_name="denied_principals",
                field_schema=models.PayloadSchemaType.KEYWORD
            )
        except Exception:
            pass

    # Also ensure default collection exists
    if settings.qdrant_collection not in existing and coll_name != settings.qdrant_collection:
        try:
            client.create_collection(
                collection_name=settings.qdrant_collection,
                vectors_config=models.VectorParams(
                    size=settings.embedding_dimension,
                    distance=models.Distance.COSINE
                )
            )
        except Exception:
            pass


def upsert_chunk(
    point_id: str,
    vector: list[float],
    payload: dict,
    tenant_id: str | None = None
):
    """
    Upserts a chunk vector and payload into the tenant's dedicated collection.
    """
    eff_tenant = payload.get("tenant_id") or tenant_id
    coll_name = get_tenant_collection_name(eff_tenant)
    ensure_collection(eff_tenant)

    client = get_qdrant_client()
    client.upsert(
        collection_name=coll_name,
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
    acl_version: int,
    tenant_id: str | None = None,
    denied_principals: list[str] | None = None
):
    """
    Updates the ACL payload (principal_keys, denied_principals & acl_version) for all chunks of a document
    in the tenant's dedicated Qdrant collection without re-embedding.
    """
    client = get_qdrant_client()
    coll_name = get_tenant_collection_name(tenant_id)
    ensure_collection(tenant_id)

    filter_cond = models.Filter(
        must=[
            models.FieldCondition(
                key="document_id",
                match=models.MatchValue(value=str(document_id))
            )
        ]
    )

    payload_data = {
        "principal_keys": principal_keys,
        "denied_principals": denied_principals or [],
        "acl_version": acl_version
    }

    try:
        client.set_payload(
            collection_name=coll_name,
            payload=payload_data,
            points=filter_cond,
            wait=True
        )
    except Exception as e:
        # Fallback to default collection if not found
        if coll_name != settings.qdrant_collection:
            try:
                client.set_payload(
                    collection_name=settings.qdrant_collection,
                    payload=payload_data,
                    points=filter_cond,
                    wait=True
                )
            except Exception:
                pass


def delete_document_chunks(document_id: str, tenant_id: str | None = None):
    """
    Deletes all chunk points of a document from the tenant's Qdrant collection.
    """
    client = get_qdrant_client()
    coll_name = get_tenant_collection_name(tenant_id)
    filter_cond = models.Filter(
        must=[
            models.FieldCondition(
                key="document_id",
                match=models.MatchValue(value=str(document_id))
            )
        ]
    )

    try:
        client.delete(
            collection_name=coll_name,
            points_selector=models.FilterSelector(filter=filter_cond),
            wait=True
        )
    except Exception:
        pass

    if coll_name != settings.qdrant_collection:
        try:
            client.delete(
                collection_name=settings.qdrant_collection,
                points_selector=models.FilterSelector(filter=filter_cond),
                wait=True
            )
        except Exception:
            pass


def search(
    vector: list[float],
    limit: int = 8,
    tenant_id: str | None = None,
    principal_keys: list[str] | None = None,
    document_id: str | None = None
):
    """
    Searches the tenant's dedicated collection in Qdrant.
    Enforces strict tenant isolation and principal matching + denied principal filtering.
    """
    client = get_qdrant_client()
    coll_name = get_tenant_collection_name(tenant_id)
    ensure_collection(tenant_id)

    must_conditions = []
    must_not_conditions = []

    if tenant_id:
        must_conditions.append(
            models.FieldCondition(
                key="tenant_id",
                match=models.MatchValue(value=str(tenant_id))
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
        must_conditions.append(
            models.FieldCondition(
                key="principal_keys",
                match=models.MatchAny(any=principal_keys)
            )
        )
        # Exclude points where user matches denied_principals
        must_not_conditions.append(
            models.FieldCondition(
                key="denied_principals",
                match=models.MatchAny(any=principal_keys)
            )
        )

    query_filter = models.Filter(
        must=must_conditions if must_conditions else None,
        must_not=must_not_conditions if must_not_conditions else None
    )

    try:
        result = client.query_points(
            collection_name=coll_name,
            query=vector,
            query_filter=query_filter,
            limit=limit,
            with_payload=True,
            with_vectors=False
        )
        points = result.points
    except Exception:
        points = []

    # If tenant collection yielded nothing and fallback might have points in default collection
    if not points and coll_name != settings.qdrant_collection:
        try:
            result = client.query_points(
                collection_name=settings.qdrant_collection,
                query=vector,
                query_filter=query_filter,
                limit=limit,
                with_payload=True,
                with_vectors=False
            )
            points = result.points
        except Exception:
            points = []

    return points