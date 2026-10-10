import json
from datetime import datetime
from sqlalchemy.orm import Session
from app.core.config import settings
from app.models import (
    ACLOutbox,
    CompanyRole,
    Document,
    DocumentACLEntry,
    Group,
    GroupMember,
    Role,
    RoleAssignment,
    Team,
    TeamMember,
    User,
    UserGroupClosure,
)
from app.services.qdrant_service import update_document_acl_payload


def resolve_user_principals(
    db: Session,
    user: User,
    tenant_id: str | None = None,
    project_id: str | None = None
) -> list[str]:
    """
    Resolve user's principals through users -> group_members -> user_group_closure -> role_assignments.
    Generates structured principal keys:
    - u:<user_id> / u:user-<id> / u:<email>
    - g:<group_key> / g:group-<group_key>
    - p:<project_id> / p:project-<id>
    - r:<role_key> (e.g. r:employee, r:admin, r:hr)
    - t:<tenant_id>
    - *
    """
    eff_tenant = tenant_id or settings.default_tenant_id
    keys: set[str] = set()

    # 1. Tenant Key
    keys.add(f"t:{eff_tenant}")

    # 2. User Keys
    keys.add(f"u:{user.id}")
    keys.add(f"u:user-{user.id}")
    keys.add(f"u:{user.email.lower()}")

    # 3. Role Keys
    role_val = user.role.value if hasattr(user.role, "value") else str(user.role or "employee").lower()
    role_k = (user.role_key or role_val).lower()
    keys.add(f"r:{role_k}")
    if role_val != "admin":
        keys.add(f"r:{role_val}")
    # General employee role inheritance for standard users
    keys.add("r:employee")

    if role_val == "admin" or user.rank_level == 1:
        keys.add("r:admin")
        keys.add("r:hr")
        keys.add("r:finance")
        keys.add("r:manager")
        keys.add("*")

    # Explicit role assignments
    role_assigns = db.query(RoleAssignment).filter(RoleAssignment.user_id == user.id).all()
    for ra in role_assigns:
        keys.add(f"r:{ra.role_key.lower()}")

    # 4. Group Keys (via group_members and user_group_closure)
    direct_groups = (
        db.query(Group)
        .join(GroupMember, GroupMember.group_id == Group.id)
        .filter(GroupMember.user_id == user.id)
        .all()
    )
    for g in direct_groups:
        keys.add(f"g:{g.key.lower()}")
        keys.add(f"g:group-{g.key.lower()}")

    closure_groups = (
        db.query(Group)
        .join(UserGroupClosure, UserGroupClosure.group_id == Group.id)
        .filter(UserGroupClosure.user_id == user.id)
        .all()
    )
    for g in closure_groups:
        keys.add(f"g:{g.key.lower()}")
        keys.add(f"g:group-{g.key.lower()}")

    # Auto-map role_key to standard department groups if present
    if role_k in ["hr", "finance", "engineering", "legal", "admin", "operations"]:
        keys.add(f"g:{role_k}")
        keys.add(f"g:group-{role_k}")

    # 5. Project / Team Keys
    if project_id:
        keys.add(f"p:{project_id}")
        keys.add(f"p:project-{project_id}")

    teams = (
        db.query(Team)
        .join(TeamMember, TeamMember.team_id == Team.id)
        .filter(TeamMember.user_id == user.id)
        .all()
    )
    for t in teams:
        keys.add(f"p:{t.id}")
        keys.add(f"p:project-{t.id}")
        if t.project_name:
            clean_proj = t.project_name.lower().replace(" ", "-")
            keys.add(f"p:{clean_proj}")
            keys.add(f"p:project-{clean_proj}")

    if not teams and settings.default_project_id:
        keys.add(f"p:{settings.default_project_id}")
        keys.add(f"p:project-{settings.default_project_id}")

    return sorted(list(keys))


resolve_user_principal_keys = resolve_user_principals


def sync_document_acl_entries(
    db: Session,
    document_id: str,
    principal_keys: list[str],
    origin: str = "source_sync",
    effect: str = "allow",
    permission: str = "read",
    denied_principal_keys: list[str] | None = None,
) -> int:
    """
    Stores document ACL in document_acl_entries and triggers acl_outbox.
    Returns the new acl_version.
    """
    doc = db.query(Document).filter(Document.id == document_id).first()
    if not doc:
        return 1

    # Increment acl_version
    doc.acl_version = (doc.acl_version or 1) + 1
    new_version = doc.acl_version

    # Clear existing entries for this document
    db.query(DocumentACLEntry).filter(
        DocumentACLEntry.document_id == document_id,
        DocumentACLEntry.origin.in_([origin, "manual", "source_sync"])
    ).delete()

    for pkey in set(principal_keys):
        if pkey and pkey.strip():
            db.add(
                DocumentACLEntry(
                    document_id=document_id,
                    principal_key=pkey.strip(),
                    permission=permission,
                    effect="allow",
                    origin=origin,
                    created_at=datetime.utcnow()
                )
            )

    if denied_principal_keys:
        for dkey in set(denied_principal_keys):
            if dkey and dkey.strip():
                db.add(
                    DocumentACLEntry(
                        document_id=document_id,
                        principal_key=dkey.strip(),
                        permission=permission,
                        effect="deny",
                        origin=origin,
                        created_at=datetime.utcnow()
                    )
                )

    # Add to outbox for Qdrant payload synchronization
    outbox = ACLOutbox(
        document_id=document_id,
        acl_version=new_version,
        status="pending",
        created_at=datetime.utcnow()
    )
    db.add(outbox)
    db.commit()

    # Process outbox immediately
    process_acl_outbox(db)
    return new_version


def process_acl_outbox(db: Session):
    """
    Pulls pending acl_outbox entries and updates Qdrant vector payload ACLs without re-indexing.
    """
    pending = db.query(ACLOutbox).filter(ACLOutbox.status == "pending").all()
    for item in pending:
        try:
            # Fetch all active allowed principal keys for the document
            doc = db.query(Document).filter(Document.id == item.document_id).first()
            t_id = doc.tenant_id if doc else None

            acl_rows = (
                db.query(DocumentACLEntry.principal_key)
                .filter(
                    DocumentACLEntry.document_id == item.document_id,
                    DocumentACLEntry.effect == "allow"
                )
                .all()
            )
            pkeys = [r[0] for r in acl_rows]
            if not pkeys:
                # Default fallback
                pkeys = [
                    f"t:{t_id or settings.default_tenant_id}",
                    "r:employee",
                    "r:admin"
                ]

            deny_rows = (
                db.query(DocumentACLEntry.principal_key)
                .filter(
                    DocumentACLEntry.document_id == item.document_id,
                    DocumentACLEntry.effect == "deny"
                )
                .all()
            )
            denied_pkeys = [r[0] for r in deny_rows]

            update_document_acl_payload(
                document_id=item.document_id,
                principal_keys=pkeys,
                acl_version=item.acl_version,
                tenant_id=t_id,
                denied_principals=denied_pkeys
            )

            item.status = "done"
            item.processed_at = datetime.utcnow()
            db.commit()
        except Exception as e:
            item.status = "failed"
            db.commit()
            print(f"Error processing ACL outbox for doc {item.document_id}: {e}")


def verify_document_access(db: Session, user: User, document_id: str) -> bool:
    """
    Final ACL authorization check in PostgreSQL:
    Resolves user's principals and verifies against document_acl_entries.
    """
    role_val = user.role.value if hasattr(user.role, "value") else str(user.role or "employee").lower()
    if role_val == "admin" or user.rank_level == 1:
        return True

    doc = db.query(Document).filter(Document.id == document_id).first()
    if not doc:
        return False

    # Check doc.denied_users JSON list first
    if doc.denied_users:
        try:
            denied_list = [d.lower() for d in json.loads(doc.denied_users or "[]")]
            if user.email.lower() in denied_list or str(user.id).lower() in denied_list:
                return False
        except Exception:
            pass

    user_principals = set(resolve_user_principals(db, user, doc.tenant_id, doc.project_id))

    # Check explicit deny entries next
    deny_entries = (
        db.query(DocumentACLEntry.principal_key)
        .filter(
            DocumentACLEntry.document_id == document_id,
            DocumentACLEntry.effect == "deny"
        )
        .all()
    )
    for (deny_key,) in deny_entries:
        if deny_key in user_principals:
            return False

    # Check allow entries
    allow_entries = (
        db.query(DocumentACLEntry.principal_key)
        .filter(
            DocumentACLEntry.document_id == document_id,
            DocumentACLEntry.effect == "allow"
        )
        .all()
    )

    if allow_entries:
        for (allow_key,) in allow_entries:
            if allow_key in user_principals or allow_key == "*":
                return True
        return False

    # Fallback to legacy document access_roles
    try:
        allowed_roles = set(json.loads(doc.access_roles or "[]"))
        return (user.role_key or role_val) in allowed_roles or "employee" in allowed_roles
    except Exception:
        return True
