import json
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import hash_password
from app.models import AuditLog, CompanyRole, LogSeverity, Role, SystemSetting, User
from app.schemas import CompanyRoleSchema, SetupStatusOut, SystemSetupInit

router = APIRouter(prefix="/api/setup", tags=["setup"])


@router.get("/status", response_model=SetupStatusOut)
def get_setup_status(db: Session = Depends(get_db)):
    setting = db.query(SystemSetting).filter(SystemSetting.key == "setup_completed").first()
    is_init = setting is not None and setting.value == "true"
    comp_name_setting = db.query(SystemSetting).filter(SystemSetting.key == "company_name").first()
    company_name = comp_name_setting.value if comp_name_setting else None
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


@router.post("/initialize", response_model=SetupStatusOut)
def initialize_system(payload: SystemSetupInit, db: Session = Depends(get_db)):
    setting = db.query(SystemSetting).filter(SystemSetting.key == "setup_completed").first()
    if setting and setting.value == "true":
        raise HTTPException(status_code=400, detail="System setup has already been completed.")

    # 1. Store Company Name & Setup Completed Flag
    db.merge(SystemSetting(key="setup_completed", value="true"))
    db.merge(SystemSetting(key="company_name", value=payload.company_name))

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
