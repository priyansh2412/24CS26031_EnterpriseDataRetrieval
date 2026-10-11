import json
import os
import sys
from pathlib import Path

# Add backend directory to sys.path
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from app.core.config import settings
from app.core.database import SessionLocal, init_db
from app.models import Document, Role, User
from app.services.acl_service import sync_document_acl_entries, verify_document_access
from app.services.ingestion_service import ingest_document_file

SAMPLE_EXECUTIVE_COMPENSATION_CONTENT = """================================================================================
            ATLAS ENTERPRISE - EXECUTIVE COMPENSATION PLAN 2026
================================================================================
Document Reference: EXEC-COMP-2026-CONFIDENTIAL
Classification: STRICTLY CONFIDENTIAL - EXECUTIVE & FINANCE BOARD ONLY
Effective Date: January 1, 2026

1. EXECUTIVE LEADERSHIP COMPENSATION OVERVIEW
This document outlines the executive compensation package, base salaries, performance bonuses, and long-term equity incentives approved by the Atlas Enterprise Compensation Committee for FY2026.

2. C-SUITE BASE SALARY AND ANNUAL INCENTIVE SCHEDULE

Role                     Name               Base Salary      Target Bonus (%)   Annual Bonus ($)   Equity Grant ($)
---------------------------------------------------------------------------------------------------------------------
Chief Executive Officer  Alexander Vance    $850,000         100%               $850,000           $1,500,000
Chief Financial Officer  Eleanor Sterling   $520,000          75%               $390,000             $800,000
Chief Technology Officer Marcus Reed        $540,000          75%               $405,000             $850,000
Chief Operating Officer  Sarah Jenkins      $480,000          60%               $288,000             $600,000

3. CEO COMPENSATION SUMMARY
- The CEO's base salary is $850,000 per annum.
- The CEO's target annual bonus is 100% of base salary ($850,000), contingent upon meeting enterprise ARR and EBITDA targets.
- Total direct cash compensation for the CEO is $1,700,000 with a total target compensation of $3,200,000 including equity grants.

4. ACCESS AND CONFIDENTIALITY RESTRICTIONS
Access to this document is strictly restricted to Corporate Board Administrators and the Finance Department. Unauthorized access or dissemination will result in immediate termination and legal action.
"""


def seed_whatsapp_demo():
    print("=== Seeding WhatsApp Demo Documents & ACLs ===")
    init_db()
    db = SessionLocal()

    try:
        data_dir = backend_dir / "data"
        data_dir.mkdir(parents=True, exist_ok=True)
        file_path = data_dir / "Executive_Compensation_2026.txt"

        # 1. Write document file if not present or ensure content
        if not file_path.exists():
            file_path.write_text(SAMPLE_EXECUTIVE_COMPENSATION_CONTENT, encoding="utf-8")
            print(f"Created demo document file: {file_path}")
        else:
            print(f"Demo document file already exists: {file_path}")

        # 2. Ingest document using existing ingestion service
        eff_tenant = settings.default_tenant_id
        eff_project = settings.default_project_id
        res = ingest_document_file(
            file_path=file_path,
            db=db,
            tenant_id=eff_tenant,
            project_id=eff_project,
            source_type="local"
        )
        print(f"Ingestion result for Executive_Compensation_2026.txt: {res.get('status')} - {res.get('message')}")

        # 3. Find document record and set ACL: ONLY admin and finance can read it
        doc = db.query(Document).filter(
            Document.name == "Executive_Compensation_2026.txt",
            Document.tenant_id == eff_tenant
        ).first()

        if not doc:
            raise RuntimeError("Document Executive_Compensation_2026.txt not found in database after ingestion!")

        role_strings = ["admin", "finance"]
        doc.access_roles = json.dumps(role_strings)
        doc.denied_users = json.dumps([])
        db.commit()

        allowed_pkeys = [f"r:{r}" for r in role_strings]

        sync_document_acl_entries(
            db=db,
            document_id=doc.id,
            principal_keys=allowed_pkeys,
            origin="manual",
            denied_principal_keys=[]
        )
        print(f"Updated ACL for '{doc.name}' (ID: {doc.id}) -> Allowed roles: {role_strings}")

        # 4. Verify ACL permissions for demo users
        finance_user = db.query(User).filter(User.email == "finance@example.com").first()
        employee_user = db.query(User).filter(User.email == "employee@example.com").first()
        admin_user = db.query(User).filter(User.email == "admin@example.com").first()

        if finance_user:
            fin_can_read = verify_document_access(db, finance_user, doc.id)
            print(f"  [Verification] finance@example.com access to {doc.name}: {'ALLOWED' if fin_can_read else 'DENIED'}")
        if employee_user:
            emp_can_read = verify_document_access(db, employee_user, doc.id)
            print(f"  [Verification] employee@example.com access to {doc.name}: {'ALLOWED' if emp_can_read else 'DENIED'}")
        if admin_user:
            adm_can_read = verify_document_access(db, admin_user, doc.id)
            print(f"  [Verification] admin@example.com access to {doc.name}: {'ALLOWED' if adm_can_read else 'DENIED'}")

        # 5. Confirm HR_Employee_Handbook_2026.txt is readable by employees
        handbook_doc = db.query(Document).filter(
            Document.name == "HR_Employee_Handbook_2026.txt"
        ).first()

        if handbook_doc and employee_user:
            handbook_can_read = verify_document_access(db, employee_user, handbook_doc.id)
            print(f"  [Verification] employee@example.com access to HR_Employee_Handbook_2026.txt: {'ALLOWED' if handbook_can_read else 'DENIED'}")
            assert handbook_can_read, "HR_Employee_Handbook_2026.txt must be readable by employee@example.com!"
        elif not handbook_doc:
            print("  [Warning] HR_Employee_Handbook_2026.txt not yet in DB; auto-ingesting...")
            handbook_path = data_dir / "HR_Employee_Handbook_2026.txt"
            if handbook_path.exists():
                ingest_document_file(handbook_path, db, tenant_id=eff_tenant)
                if employee_user:
                    hb = db.query(Document).filter(Document.name == "HR_Employee_Handbook_2026.txt").first()
                    print(f"  [Verification] employee@example.com access to HR_Employee_Handbook_2026.txt: {'ALLOWED' if verify_document_access(db, employee_user, hb.id) else 'DENIED'}")

        print("=== Seed WhatsApp Demo completed successfully ===")
    finally:
        db.close()


if __name__ == "__main__":
    seed_whatsapp_demo()
