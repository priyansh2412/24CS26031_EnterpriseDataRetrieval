import json
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import get_current_user, hash_password
from app.models import AuditLog, CompanyRole, LogSeverity, Role, Tenant, User
from app.schemas import CompanyRoleSchema, SetupStatusOut, SystemSetupInit

router = APIRouter(prefix="/api/setup", tags=["setup"])


@router.get("/status", response_model=SetupStatusOut)
def get_setup_status(db: Session = Depends(get_db)):
    tenant = db.query(Tenant).first()
    has_admin = db.query(User).filter(User.rank_level == 1).first() is not None
    is_init = tenant is not None and has_admin
    company_name = tenant.name if tenant else "Apex Enterprise"
    return SetupStatusOut(is_initialized=is_init, company_name=company_name)


@router.get("/roles", response_model=list[CompanyRoleSchema])
def list_company_roles(db: Session = Depends(get_db)):
    roles = db.query(CompanyRole).order_by(CompanyRole.rank_level.asc()).all()
    out = []
    for r in roles:
        try:
            perms = json.loads(r.permissions_json or "[]")
        except Exception:
            perms = ["chat", "documents:view"]
        out.append(CompanyRoleSchema(
            id=r.id,
            name=r.name,
            key=r.key,
            rank_level=r.rank_level,
            description=r.description,
            permissions=perms
        ))
    return out


@router.post("/roles", response_model=CompanyRoleSchema)
def save_company_role(
    payload: CompanyRoleSchema,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Add or update a role in the company hierarchy."""
    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
    if curr_role != "admin" and current_user.rank_level > 2:
        raise HTTPException(status_code=403, detail="Access restricted to workspace administrators.")

    perms_json = json.dumps(payload.permissions)
    clean_key = payload.key.strip().lower().replace(" ", "_")

    if payload.id:
        role = db.get(CompanyRole, payload.id)
        if not role:
            raise HTTPException(status_code=404, detail="Role not found")
        role.name = payload.name.strip()
        role.key = clean_key
        role.rank_level = payload.rank_level
        role.description = payload.description
        role.permissions_json = perms_json
    else:
        existing = db.query(CompanyRole).filter((CompanyRole.key == clean_key) | (CompanyRole.name == payload.name.strip())).first()
        if existing:
            existing.name = payload.name.strip()
            existing.rank_level = payload.rank_level
            existing.description = payload.description
            existing.permissions_json = perms_json
            role = existing
        else:
            role = CompanyRole(
                name=payload.name.strip(),
                key=clean_key,
                rank_level=payload.rank_level,
                description=payload.description,
                permissions_json=perms_json
            )
            db.add(role)

    db.add(AuditLog(
        user_id=current_user.id,
        action="update_hierarchy_role",
        resource_type="company_role",
        resource_id=clean_key,
        severity=LogSeverity.INFO,
        detail=f"Updated role '{role.name}' (Rank Level {role.rank_level})"
    ))
    db.commit()
    db.refresh(role)

    return CompanyRoleSchema(
        id=role.id,
        name=role.name,
        key=role.key,
        rank_level=role.rank_level,
        description=role.description,
        permissions=json.loads(role.permissions_json or "[]")
    )


@router.delete("/roles/{role_id}")
def delete_company_role(
    role_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Remove a custom company role from the hierarchy."""
    curr_role = current_user.role.value if hasattr(current_user.role, "value") else str(current_user.role or "employee")
    if curr_role != "admin" and current_user.rank_level > 2:
        raise HTTPException(status_code=403, detail="Access restricted to workspace administrators.")

    role = db.get(CompanyRole, role_id)
    if not role:
        raise HTTPException(status_code=404, detail="Role not found")

    if role.key in ["admin", "employee"]:
        raise HTTPException(status_code=400, detail="Cannot delete core system role.")

    db.delete(role)
    db.add(AuditLog(
        user_id=current_user.id,
        action="delete_hierarchy_role",
        resource_type="company_role",
        resource_id=str(role.id),
        severity=LogSeverity.WARNING,
        detail=f"Removed role '{role.name}' from hierarchy."
    ))
    db.commit()
    return {"status": "success", "message": f"Role '{role.name}' deleted."}


@router.post("/initialize", response_model=SetupStatusOut)
def initialize_system(payload: SystemSetupInit, db: Session = Depends(get_db)):
    admin_exists = db.query(User).filter(User.rank_level == 1).first() is not None
    if admin_exists:
        raise HTTPException(status_code=400, detail="System setup has already been completed.")

    # 1. Store Company Name in Tenant
    tenant = db.query(Tenant).first()
    if not tenant:
        tenant = Tenant(name=payload.company_name, slug="default")
        db.add(tenant)
    else:
        tenant.name = payload.company_name

    # 2. Add Company Roles
    for role_def in payload.roles:
        existing_role = db.query(CompanyRole).filter(CompanyRole.key == role_def.key).first()
        if not existing_role:
            perms_json = json.dumps(role_def.permissions)
            new_role = CompanyRole(
                name=role_def.name,
                key=role_def.key,
                rank_level=role_def.rank_level,
                description=role_def.description,
                permissions_json=perms_json
            )
            db.add(new_role)

    # 3. Create Root Administrator Account (Rank 1)
    admin_user = db.query(User).filter(User.email == payload.admin_email).first()
    if not admin_user:
        admin_user = User(
            email=payload.admin_email,
            password_hash=hash_password(payload.admin_password),
            role=Role.ADMIN,
            role_key=payload.roles[0].key if payload.roles else "admin",
            rank_level=1,
            is_active=True
        )
        db.add(admin_user)
        db.flush()

        db.add(AuditLog(
            user_id=admin_user.id,
            action="system_initialized",
            resource_type="system",
            severity=LogSeverity.INFO,
            detail=f"System initialized for {payload.company_name} with root administrator {payload.admin_email}"
        ))

    db.commit()
    return SetupStatusOut(is_initialized=True, company_name=payload.company_name)
