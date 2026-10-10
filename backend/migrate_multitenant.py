from app.core.database import engine
from sqlalchemy import text

def run_migration():
    with engine.begin() as conn:
        print("Migrating users.tenant_id to VARCHAR(64)...")
        conn.execute(text("""
            ALTER TABLE users ALTER COLUMN tenant_id TYPE VARCHAR(64) USING tenant_id::text;
        """))

        print("Adding tenant_id to teams...")
        conn.execute(text("""
            ALTER TABLE teams ADD COLUMN IF NOT EXISTS tenant_id VARCHAR(64) DEFAULT 'tenant-001';
            CREATE INDEX IF NOT EXISTS idx_teams_tenant_id ON teams(tenant_id);
        """))

        print("Adding tenant_id to query_logs...")
        conn.execute(text("""
            ALTER TABLE query_logs ADD COLUMN IF NOT EXISTS tenant_id VARCHAR(64) DEFAULT 'tenant-001';
            CREATE INDEX IF NOT EXISTS idx_query_logs_tenant_id ON query_logs(tenant_id);
        """))

        print("Adding tenant_id to sources...")
        conn.execute(text("""
            ALTER TABLE sources ADD COLUMN IF NOT EXISTS tenant_id VARCHAR(64) DEFAULT 'tenant-001';
            CREATE INDEX IF NOT EXISTS idx_sources_tenant_id ON sources(tenant_id);
        """))

        print("Migrating audit_logs.tenant_id to VARCHAR(64)...")
        conn.execute(text("""
            ALTER TABLE audit_logs ALTER COLUMN tenant_id TYPE VARCHAR(64) USING tenant_id::text;
            CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_id ON audit_logs(tenant_id);
        """))

        print("Ensuring enterprise_admins table and columns...")
        conn.execute(text("""
            ALTER TABLE enterprise_admins ADD COLUMN IF NOT EXISTS tenant_id VARCHAR(64) DEFAULT 'tenant-001';
            CREATE INDEX IF NOT EXISTS idx_enterprise_admins_tenant_id ON enterprise_admins(tenant_id);
        """))

        # Synchronize existing enterprise admins with users table
        print("Syncing existing enterprise admin tenant IDs...")
        res = conn.execute(text("SELECT id, enterprise_name, admin_email, tenant_id FROM enterprise_admins;")).fetchall()
        for row in res:
            ent_id, ent_name, email, t_id = row
            if not t_id or t_id == "tenant-001":
                # Give each existing enterprise a distinct tenant_id if it doesn't have one
                clean_name = "".join(c.lower() for c in ent_name if c.isalnum())[:10]
                t_id = f"tenant_{clean_name}_{ent_id}"
                conn.execute(text("UPDATE enterprise_admins SET tenant_id=:tid WHERE id=:eid"), {"tid": t_id, "eid": ent_id})
            
            # Sync user
            conn.execute(text("UPDATE users SET tenant_id=:tid WHERE email=:email"), {"tid": t_id, "email": email})

        # Also ensure default test users have tenant-001 if null
        conn.execute(text("UPDATE users SET tenant_id='tenant-001' WHERE tenant_id IS NULL AND email != 'system@gmailexample.com'"))

    print("Multi-tenant database migration completed successfully.")

if __name__ == "__main__":
    run_migration()

