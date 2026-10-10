from app.core.database import engine
from sqlalchemy import text

tables_to_drop = [
    'message_citations',
    'message_feedback',
    'messages',
    'conversations',
    'retrieval_events',
    'pii_findings',
    'ingestion_jobs',
    'user_idp_links',
    'external_identities',
    'identity_providers',
    'user_group_closure',
    'group_members',
    'user_groups',
    'groups',
    'role_assignments',
    'role_permissions',
    'permissions',
    'roles',
    'sync_runs',
    'source_connections',
    'classification_levels',
    'abac_policies',
    'projects',
    'audit_logs_default',
    'system_settings',
]

with engine.connect() as conn:
    for t in tables_to_drop:
        try:
            conn.execute(text(f'DROP TABLE IF EXISTS "{t}" CASCADE;'))
            print(f'Dropped table: {t}')
        except Exception as e:
            print(f'Error dropping {t}: {e}')
    conn.commit()

print('All requested legacy tables dropped successfully!')

