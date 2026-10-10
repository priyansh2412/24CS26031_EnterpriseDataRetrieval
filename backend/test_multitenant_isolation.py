import uuid
from app.core.database import SessionLocal, init_db
from app.models import Document, EnterpriseAdmin, Tenant, User
from app.routers.enterprises import create_enterprise
from app.schemas import EnterpriseCreate
from app.services.ingestion_service import ingest_document_file
from app.services.qdrant_service import get_qdrant_client, get_tenant_collection_name
from app.services.retrieval_service import retrieve_authorized_chunks

def test_multi_tenant_isolation():
    init_db()
    db = SessionLocal()
    client = get_qdrant_client()

    print("\n--- 1. Checking Super Admin ---")
    super_admin = db.query(User).filter(User.email == "system@gmailexample.com").first()
    assert super_admin is not None, "Super admin user missing!"
    print(f"Super admin: {super_admin.email} (ID: {super_admin.id})")

    print("\n--- 2. Creating Two Test Enterprises ---")
    ent_a_payload = EnterpriseCreate(
        enterprise_name="Acme Corporation",
        admin_email="admin@acmecorp.com",
        temp_password="Password123!"
    )
    ent_b_payload = EnterpriseCreate(
        enterprise_name="Apex Technologies",
        admin_email="admin@apex.com",
        temp_password="Password123!"
    )

    ent_a = create_enterprise(ent_a_payload, db=db, current_user=super_admin)
    ent_b = create_enterprise(ent_b_payload, db=db, current_user=super_admin)

    print(f"Enterprise A created: {ent_a.enterprise_name} | Tenant ID: {ent_a.tenant_id}")
    print(f"Enterprise B created: {ent_b.enterprise_name} | Tenant ID: {ent_b.tenant_id}")

    assert ent_a.tenant_id != ent_b.tenant_id, "Tenant IDs must be distinct!"

    print("\n--- 3. Verifying Qdrant Vector Spaces ---")
    coll_a = get_tenant_collection_name(ent_a.tenant_id)
    coll_b = get_tenant_collection_name(ent_b.tenant_id)
    print(f"Enterprise A Qdrant Collection: {coll_a}")
    print(f"Enterprise B Qdrant Collection: {coll_b}")

    existing_colls = {c.name for c in client.get_collections().collections}
    print(f"All Qdrant Collections: {existing_colls}")
    assert coll_a in existing_colls, f"Collection {coll_a} not found in Qdrant!"
    assert coll_b in existing_colls, f"Collection {coll_b} not found in Qdrant!"

    print("\n--- 4. Checking Enterprise Admin Users in PostgreSQL ---")
    user_a = db.query(User).filter(User.email == "admin@acmecorp.com").first()
    user_b = db.query(User).filter(User.email == "admin@apex.com").first()

    assert user_a is not None and str(user_a.tenant_id) == str(ent_a.tenant_id), "User A tenant_id mismatch!"
    assert user_b is not None and str(user_b.tenant_id) == str(ent_b.tenant_id), "User B tenant_id mismatch!"
    print(f"User A ({user_a.email}): tenant_id = {user_a.tenant_id}")
    print(f"User B ({user_b.email}): tenant_id = {user_b.tenant_id}")

    print("\n--- 5. Ingesting Documents into Isolated Tenant Spaces ---")
    from pathlib import Path
    
    # Create sample doc for Acme
    doc_a_path = Path("sample_acme_policy.txt")
    doc_a_path.write_text("Acme Corporation Secret Policy: All Acme employees receive quarterly innovation bonuses of $5000.", encoding="utf-8")
    
    # Create sample doc for Apex
    doc_b_path = Path("sample_apex_handbook.txt")
    doc_b_path.write_text("Apex Technologies Confidential Handbook: Apex project code is Project-Titanium and remote work stipend is $1200.", encoding="utf-8")

    res_a = ingest_document_file(doc_a_path, db=db, tenant_id=ent_a.tenant_id)
    res_b = ingest_document_file(doc_b_path, db=db, tenant_id=ent_b.tenant_id)

    print(f"Ingested for Acme: {res_a}")
    print(f"Ingested for Apex: {res_b}")

    print("\n--- 6. Testing Isolated Retrieval ---")
    # Acme Admin asks about bonuses
    chunks_acme = retrieve_authorized_chunks("What is the innovation bonus?", db=db, user=user_a, top_k=3)
    print(f"Acme retrieval result count: {len(chunks_acme)}")
    for c in chunks_acme:
        print(f"  - [{c.get('document_name')}] {c.get('text')}")
    assert any("Acme Corporation" in c.get("text", "") for c in chunks_acme), "Acme doc not found for Acme admin!"
    assert not any("Apex Technologies" in c.get("text", "") for c in chunks_acme), "Apex data leaked to Acme admin!"

    # Apex Admin asks about bonuses / titanium
    chunks_apex = retrieve_authorized_chunks("What is the project code and remote work stipend?", db=db, user=user_b, top_k=3)
    print(f"\nApex retrieval result count: {len(chunks_apex)}")
    for c in chunks_apex:
        print(f"  - [{c.get('document_name')}] {c.get('text')}")
    assert any("Apex Technologies" in c.get("text", "") for c in chunks_apex), "Apex doc not found for Apex admin!"
    assert not any("Acme Corporation" in c.get("text", "") for c in chunks_apex), "Acme data leaked to Apex admin!"

    # Cross-tenant query test: Apex admin searches for Acme bonus -> should find NOTHING
    chunks_leak_test = retrieve_authorized_chunks("innovation bonus", db=db, user=user_b, top_k=3)
    assert not any("Acme Corporation" in c.get("text", "") for c in chunks_leak_test), "SECURITY LEAK: Acme data returned to Apex user!"
    print("\nSUCCESS: Strict multi-tenant isolation verified! Zero cross-enterprise data leakage.")

    # Cleanup temp files
    if doc_a_path.exists(): doc_a_path.unlink()
    if doc_b_path.exists(): doc_b_path.unlink()
    db.close()

if __name__ == "__main__":
    test_multi_tenant_isolation()

