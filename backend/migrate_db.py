import os
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()
db_url = os.getenv("DATABASE_URL")
if db_url.startswith("postgresql://"):
    db_url = db_url.replace("postgresql://", "postgresql+psycopg://", 1)

eng = create_engine(db_url)

with eng.begin() as conn:
    conn.execute(text("""
        ALTER TABLE document_acl_entries DROP COLUMN IF EXISTS principal_key CASCADE;
        ALTER TABLE document_acl_entries ADD COLUMN principal_key VARCHAR(128);
        ALTER TABLE document_acl_entries ALTER COLUMN principal_type DROP NOT NULL;
        ALTER TABLE document_acl_entries ALTER COLUMN principal_id DROP NOT NULL;
    """))

print("document_acl_entries principal_key made standard column successfully.")

