from app.core.database import SessionLocal, init_db
from app.models import CompanyRole, User
from app.routers.auth import change_password, me
from app.routers.setup import list_company_roles, save_company_role
from app.routers.users import create_user, update_user
from app.schemas import ChangePasswordRequest, CompanyRoleSchema, UserCreate, UserUpdate

def test_profile_and_hierarchy():
    init_db()
    db = SessionLocal()

    print("\n--- 1. Testing Admin Profile Info ---")
    admin = db.query(User).filter(User.email == "admin@acmecorp.com").first()
    assert admin is not None, "Admin user not found!"
    profile = me(user=admin, db=db)
    print(f"Profile: Email={profile.email}, Role={profile.role_key}, Rank={profile.rank_level}, Enterprise={profile.enterprise_name}, Tenant={profile.tenant_id}")
    assert profile.email == "admin@acmecorp.com"
    assert profile.rank_level == 1
    assert profile.enterprise_name is not None

    print("\n--- 2. Testing Password Change ---")
    change_res = change_password(
        payload=ChangePasswordRequest(
            current_password="Password123!",
            new_password="NewSecurePassword2026!"
        ),
        db=db,
        user=admin
    )
    print("Password change response:", change_res)
    assert change_res.get("status") == "success"

    # Reset back
    change_res2 = change_password(
        payload=ChangePasswordRequest(
            current_password="NewSecurePassword2026!",
            new_password="Password123!"
        ),
        db=db,
        user=admin
    )
    print("Reset back response:", change_res2)
    assert change_res2.get("status") == "success"

    print("\n--- 3. Testing Workspace Hierarchy & Role Management ---")
    new_role_payload = CompanyRoleSchema(
        name="Lead AI Architect",
        key="lead_ai_architect",
        rank_level=3,
        description="Oversees RAG pipeline and vector search algorithms",
        permissions=["chat", "documents:view", "documents:manage", "analytics:view"]
    )
    saved_role = save_company_role(payload=new_role_payload, db=db, current_user=admin)
    print(f"Saved Hierarchy Role: ID={saved_role.id}, Name={saved_role.name}, Key={saved_role.key}, Rank={saved_role.rank_level}")
    assert saved_role.key == "lead_ai_architect"
    assert saved_role.rank_level == 3

    roles_list = list_company_roles(db=db)
    print(f"Total roles in hierarchy: {len(roles_list)}")
    assert any(r.key == "lead_ai_architect" for r in roles_list)

    print("\n--- 4. Testing Employee Hierarchy Reassignment ---")
    # Find or create employee in same tenant
    emp_email = "employee_test@acmecorp.com"
    emp = db.query(User).filter(User.email == emp_email).first()
    if not emp:
        emp = create_user(
            payload=UserCreate(
                email=emp_email,
                password="Employee123!",
                role_key="employee",
                rank_level=5
            ),
            db=db,
            current_user=admin
        )
    print(f"Acme Employee: {emp.email} -> Initial Role={emp.role_key}, Rank={emp.rank_level}")

    updated_emp = update_user(
        user_id=str(emp.id),
        payload=UserUpdate(role_key="lead_ai_architect", rank_level=3),
        db=db,
        current_user=admin
    )
    print(f"Reassigned Employee: {updated_emp.email} -> Updated Role={updated_emp.role_key}, Rank={updated_emp.rank_level}")
    assert updated_emp.role_key == "lead_ai_architect"
    assert updated_emp.rank_level == 3

    print("\nALL ADMIN PROFILE & HIERARCHY TESTS PASSED SUCCESSFULLY!")
    db.close()

if __name__ == "__main__":
    test_profile_and_hierarchy()

