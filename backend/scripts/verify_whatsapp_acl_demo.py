import json
import sys
import uuid
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from app.core.database import SessionLocal, init_db
from app.models import User, UserPhoneLink
from app.services.whatsapp_service import handle_inbound, _clear_rate_limits
from app.services.retrieval_service import retrieve_authorized_chunks
from app.core.config import settings

def run_verification():
    print("=" * 70)
    print("WHATSAPP ACL ACCESS CONTROL & RAG END-TO-END VERIFICATION")
    print("=" * 70)
    init_db()
    db = SessionLocal()

    try:
        _clear_rate_limits()

        # 1. Fetch demo users
        finance_user = db.query(User).filter(User.email == "finance@example.com").first()
        employee_user = db.query(User).filter(User.email == "employee@example.com").first()

        assert finance_user is not None, "finance@example.com user not found in database!"
        assert employee_user is not None, "employee@example.com user not found in database!"

        print(f"Finance User:  {finance_user.email} (Role: {finance_user.role}, Rank: {finance_user.rank_level})")
        print(f"Employee User: {employee_user.email} (Role: {employee_user.role}, Rank: {employee_user.rank_level})")

        # 2. Link test JIDs
        jid_finance = "15550001111@s.whatsapp.net"
        jid_employee = "15550002222@s.whatsapp.net"

        for user_obj, jid, name in [
            (finance_user, jid_finance, "Finance Lead"),
            (employee_user, jid_employee, "Standard Employee"),
        ]:
            link = db.query(UserPhoneLink).filter(UserPhoneLink.wa_jid == jid).first()
            if not link:
                link = UserPhoneLink(
                    user_id=user_obj.id,
                    tenant_id=user_obj.tenant_id,
                    wa_jid=jid,
                    wa_display_name=name,
                    status="active"
                )
                db.add(link)
            else:
                link.user_id = user_obj.id
                link.tenant_id = user_obj.tenant_id
                link.wa_display_name = name
                link.status = "active"
        db.commit()

        # ---------------------------------------------------------------------
        # TEST 1: Restricted Document Query ("What is the CEO's salary?")
        # ---------------------------------------------------------------------
        query_salary = "What is the CEO's salary?"
        print(f"\n[QUERY 1] '{query_salary}'")

        # Test 1A: Finance user asking about CEO salary
        reply_fin_salary = handle_inbound(
            db=db,
            wa_message_id=f"msg-v-{uuid.uuid4().hex[:6]}",
            jid=jid_finance,
            push_name="Finance Tester",
            text=query_salary
        )
        print(f"\n--- [Finance JID Reply] ---:\n{reply_fin_salary}\n")

        # Test 1B: Employee user asking about CEO salary
        reply_emp_salary = handle_inbound(
            db=db,
            wa_message_id=f"msg-v-{uuid.uuid4().hex[:6]}",
            jid=jid_employee,
            push_name="Employee Tester",
            text=query_salary
        )
        print(f"--- [Employee JID Reply] ---:\n{reply_emp_salary}\n")

        # Assertions for Query 1
        assert "850,000" in reply_fin_salary or "850" in reply_fin_salary or "Sources:" in reply_fin_salary, (
            "Finance user should receive CEO salary details with citations!"
        )
        assert reply_emp_salary == "I couldn't find that in the documents you have access to.", (
            f"Employee must be denied access to Executive Compensation! Got: {reply_emp_salary}"
        )
        print(">>> RESULT 1: Finance received answer with citations; Employee was denied as expected. PASS.")

        # ---------------------------------------------------------------------
        # TEST 2: Common Document Query ("What is the leave policy for employees?")
        # ---------------------------------------------------------------------
        query_leave = "What is the leave policy for employees?"
        print(f"\n[QUERY 2] '{query_leave}'")

        reply_fin_leave = handle_inbound(
            db=db,
            wa_message_id=f"msg-v-{uuid.uuid4().hex[:6]}",
            jid=jid_finance,
            push_name="Finance Tester",
            text=query_leave
        )
        print(f"\n--- [Finance JID Reply] ---:\n{reply_fin_leave}\n")

        reply_emp_leave = handle_inbound(
            db=db,
            wa_message_id=f"msg-v-{uuid.uuid4().hex[:6]}",
            jid=jid_employee,
            push_name="Employee Tester",
            text=query_leave
        )
        print(f"--- [Employee JID Reply] ---:\n{reply_emp_leave}\n")

        # Assertions for Query 2
        assert "Sources:" in reply_emp_leave or "leave" in reply_emp_leave.lower() or "pto" in reply_emp_leave.lower(), (
            "Employee user should receive leave policy answer!"
        )
        assert "Sources:" in reply_fin_leave or "leave" in reply_fin_leave.lower() or "pto" in reply_fin_leave.lower(), (
            "Finance user should receive leave policy answer!"
        )
        print(">>> RESULT 2: Both Finance and Employee received leave policy information. PASS.")

        # ---------------------------------------------------------------------
        # TEST 3: Parity Verification against Web Chat /api/chat/ask retrieval
        # ---------------------------------------------------------------------
        print("\n[VERIFICATION] Checking parity between WhatsApp and Web RAG Retrieval...")
        eff_tenant = str(employee_user.tenant_id or settings.default_tenant_id)
        web_chunks_emp = retrieve_authorized_chunks(
            question=query_salary,
            db=db,
            user=employee_user,
            top_k=5,
            tenant_id=eff_tenant
        )
        emp_has_exec = any(c['document_name'] == 'Executive_Compensation_2026.txt' for c in web_chunks_emp)
        assert not emp_has_exec, "Web path for employee must NOT return any chunks from Executive_Compensation_2026.txt!"

        web_chunks_fin = retrieve_authorized_chunks(
            question=query_salary,
            db=db,
            user=finance_user,
            top_k=5,
            tenant_id=eff_tenant
        )
        fin_has_exec = any(c['document_name'] == 'Executive_Compensation_2026.txt' for c in web_chunks_fin)
        assert fin_has_exec, "Web path for finance must return chunks from Executive_Compensation_2026.txt!"
        print(f">>> Parity confirmed: Finance has access to Executive_Compensation_2026.txt, while Employee is completely restricted from it.")

        print("\n" + "=" * 70)
        print("ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!")
        print("=" * 70)

    finally:
        db.close()


if __name__ == "__main__":
    run_verification()
