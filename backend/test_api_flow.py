import sys
import json
from fastapi.testclient import TestClient
from app.main import app
from app.core.security import create_token
from app.core.database import SessionLocal
from app.models import User

def main():
    client = TestClient(app)
    db = SessionLocal()
    user = db.query(User).filter(User.email == "admin@example.com").first()
    token = create_token(user)
    db.close()

    headers = {"Authorization": f"Bearer {token}"}

    print("1. Testing GET /api/chat/sessions ...")
    res = client.get("/api/chat/sessions", headers=headers)
    print("Status:", res.status_code)

    print("\n2. Testing POST /api/chat/ask ...")
    ask_payload = {
        "question": "How many days of PTO do full-time employees accrue annually?",
        "top_k": 5
    }
    ask_res = client.post("/api/chat/ask", json=ask_payload, headers=headers)
    print("Status:", ask_res.status_code)
    if ask_res.status_code == 200:
        data = ask_res.json()
        print("\n--- Model Answer ---")
        print(data.get("answer"))
        print("\nSession ID:", data.get("session_id"))
        print("Citations Count:", len(data.get("citations", [])))

        print("\n3. Testing GET /api/chat/history ...")
        sid = data.get("session_id")
        hist_res = client.get(f"/api/chat/history?session_id={sid}", headers=headers)
        print("Status:", hist_res.status_code)
        print(f"Retrieved {len(hist_res.json())} history entries for session {sid}:")
        for entry in hist_res.json():
            print(f"[{entry['sender']}]: {entry['text'][:90]}...")
    else:
        print("Error:", ask_res.text)

if __name__ == "__main__":
    main()

