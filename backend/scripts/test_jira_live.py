import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import time
import httpx

BASE = "http://127.0.0.1:8000"

def run_test():
    # 1. Login
    r = httpx.post(
        f"{BASE}/api/auth/login",
        data={"username": "manager@example.com", "password": "ManagerPass123!"}
    )
    assert r.status_code == 200, f"Login failed: {r.text}"
    token = r.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    print("[OK] Logged in as manager@example.com")

    # 2. Send message
    msg_payload = {"message": "Rahul, finish the login API in 2 days", "mode": "team"}
    r_msg = httpx.post(f"{BASE}/api/teams/1/chat", json=msg_payload, headers=headers)
    assert r_msg.status_code == 200, f"Send message failed: {r_msg.text}"
    sent_msg = r_msg.json()
    msg_id = sent_msg["id"]
    print(f"[OK] Sent message (ID: {msg_id}): '{sent_msg['message']}'")

    # 3. Wait for background task
    suggestion = None
    for attempt in range(15):
        time.sleep(1.5)
        r_hist = httpx.get(f"{BASE}/api/teams/1/chat", headers=headers)
        assert r_hist.status_code == 200
        msgs = r_hist.json()
        for m in msgs:
            if m["id"] == msg_id and m.get("jira"):
                suggestion = m["jira"]
                break
        if suggestion:
            break
        print(f"Waiting for AI extraction... (attempt {attempt+1})")

    if not suggestion:
        print("[FAIL] No Jira suggestion created after waiting.")
        return False

    print("\n================ JIRA SUGGESTION EXTRACTED ================")
    print(f"  Link ID:        {suggestion['id']}")
    print(f"  Status:         {suggestion['status']}")
    print(f"  Intent:         {suggestion['intent']}")
    print(f"  Title:          {suggestion['title']}")
    print(f"  Assignee Name:  {suggestion['assignee_name']}")
    print(f"  Assignee Email: {suggestion['assignee_email']}")
    print(f"  Due Date:       {suggestion['due_date']}")
    print("===========================================================\n")

    # 4. Confirm suggestion
    link_id = suggestion["id"]
    print(f"Calling POST /api/jira/suggestions/{link_id}/confirm ...")
    r_confirm = httpx.post(f"{BASE}/api/jira/suggestions/{link_id}/confirm", headers=headers, timeout=30.0)
    print("Confirm HTTP Status:", r_confirm.status_code)
    confirm_data = r_confirm.json()
    print("Confirm Response JSON:", confirm_data)

    if r_confirm.status_code != 200:
        print("[FAIL] Confirm failed!")
        return False

    jira_key = confirm_data.get("jira_key")
    jira_url = confirm_data.get("jira_url")
    print(f"\n[SUCCESS] Real Jira Issue Created!")
    print(f"  Issue Key: {jira_key}")
    print(f"  Issue URL: {jira_url}")

    # 5. Verify the issue directly via Jira REST API
    from app.services.jira_service import _get_base_url, _get_auth
    base_url = _get_base_url()
    with httpx.Client(timeout=15.0) as client:
        r_jira = client.get(
            f"{base_url}/rest/api/3/issue/{jira_key}",
            auth=_get_auth(),
            headers={"Accept": "application/json"}
        )
        print("\nVerifying issue in Jira Cloud:")
        print(f"  GET {base_url}/rest/api/3/issue/{jira_key}")
        print("  Status code:", r_jira.status_code)
        if r_jira.status_code == 200:
            fields = r_jira.json().get("fields", {})
            print("  Issue Summary:", fields.get("summary"))
            print("  Issue Status:", fields.get("status", {}).get("name"))
            print("  Issue Project:", fields.get("project", {}).get("key"))
            print("  Issue Due Date:", fields.get("duedate"))
            print("  Issue Labels:", fields.get("labels"))
            print("  VERIFIED: The issue exists and is confirmed in Jira Cloud!")
            return True
        else:
            print("  [WARNING] Could not verify issue in Jira:", r_jira.text)
            return False

if __name__ == "__main__":
    run_test()
