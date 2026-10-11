# WhatsApp Channel Integration & Live Demo Guide

This guide details the complete end-to-end setup, live presentation script, troubleshooting matrix, and production roadmap for the WhatsApp enterprise knowledge assistant.

---

## 1. Prerequisites & Environment Setup

### Step 1: Root Environment Variables (`.env`)
Ensure your root `.env` includes the WhatsApp gateway secret and bot configuration:
```ini
# WhatsApp Integration
WHATSAPP_GATEWAY_SECRET=atlas-super-secret-gateway-key-2026
WHATSAPP_BOT_NUMBER=+15550009999
```

### Step 2: Gateway Environment Variables (`whatsapp-gateway/.env`)
Create `whatsapp-gateway/.env` matching the backend secret:
```ini
API_URL=http://127.0.0.1:8000
GATEWAY_SECRET=atlas-super-secret-gateway-key-2026
ALLOW_GROUPS=false
LOG_LEVEL=info
```

### Step 3: Seed Demo Documents & ACLs
Run the idempotent seed script to ingest the confidential `Executive_Compensation_2026.txt` and assign permissions:
```powershell
cd backend
.\venv\Scripts\python.exe scripts\seed_whatsapp_demo.py
```
*Expected Output*:
- `Executive_Compensation_2026.txt` ingested with restricted roles: `['admin', 'finance']`.
- `finance@example.com` access: `ALLOWED`.
- `employee@example.com` access: `DENIED`.
- `employee@example.com` access to `HR_Employee_Handbook_2026.txt`: `ALLOWED`.

---

## 2. Launching Services (3 Terminals)

### Terminal 1: FastAPI Backend
```powershell
cd backend
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```
Backend starts on `http://127.0.0.1:8000`.

### Terminal 2: React Frontend
```powershell
cd frontend
npm run dev
```
Web app opens on `http://localhost:5173`.

### Terminal 3: WhatsApp Gateway
```powershell
cd whatsapp-gateway
npm run dev
```
A QR code will render in the terminal.

---

## 3. Pairing the WhatsApp Bot Phone

1. Open WhatsApp on your bot dedicated phone.
2. Tap **Settings** (iOS) or **⋮** (Android) > **Linked devices** > **Link a device**.
3. Scan the terminal QR code.
4. When paired, Terminal 3 logs:
   ```text
   Connected as <bot_number>
   ```

---

## 4. Live Demo Presentation Script

### Step 1: Link an Employee's WhatsApp
1. On the web portal (`http://localhost:5173`), log in as `employee@example.com` (password: `employee123` or your setup password).
2. Click **"Linked Devices"** in the sidebar (route `/linked-devices`).
3. Click **"Link WhatsApp"**. A large 6-digit code appears with a live 10-minute countdown.
4. From your personal phone, send `LINK <code>` to the bot number (or click **"Open WhatsApp"** on the web page).
5. The bot responds:
   ```text
   Linked to employee@example.com ✅. Ask me anything about your company documents. Send /help for commands.
   ```
6. The web page automatically transitions to the **"Connected"** state card.

### Step 2: Query General Company Knowledge (Allowed)
- **Prompt (from Employee phone)**:
  ```text
  What is the leave policy for employees?
  ```
- **Bot Reply**:
  Returns the leave policy breakdown (22 PTO days, 10 sick leave days, carryover rules) with numbered sources citing `HR_Employee_Handbook_2026.txt` and `Employee_Leave_Policy.pdf`.

### Step 3: Demonstrate Hierarchical ACL Enforcement (Restricted)
- **Prompt (from Employee phone)**:
  ```text
  What is the CEO's salary?
  ```
- **Bot Reply**:
  ```text
  I couldn't find that in the documents you have access to.
  ```
  *(Employee role cannot view `Executive_Compensation_2026.txt`)*

- **Now switch to Finance**:
  1. On the website, log in as `finance@example.com`.
  2. Navigate to **"Linked Devices"** and click **"Link WhatsApp"**.
  3. Send `LINK <code>` from your phone to re-link to Finance.
  4. Ask the same query again:
     ```text
     What is the CEO's salary?
     ```
- **Bot Reply**:
  ```text
  The CEO's base salary is $850,000 per annum [Source 1]. Including bonuses and equity grants, total target compensation is $3,200,000 [Source 1].

  Sources:
  [1] Executive_Compensation_2026.txt, p.1
  ```
  *Live proof: The exact same question produces different answers based on the user's authenticated organizational rank and role ACLs!*

### Step 4: Bot Commands
- Send `/help` -> Lists available bot commands (`/help`, `/new`, `/unlink`).
- Send `/new` -> Resets current chat session memory (`Started a new chat session.`).
- Send `/unlink` -> Revokes WhatsApp link immediately (`Your WhatsApp account has been unlinked.`).

### Step 5: Unlinked / Unknown Phone Handling
- Send any message from a phone number that is not linked:
  ```text
  Hello assistant
  ```
- **Bot Reply**:
  ```text
  Your WhatsApp is not linked yet. Log in to the website, open Linked Devices and send the LINK code here.
  ```

---

## 5. Troubleshooting Matrix

| Issue | Root Cause | Solution |
|---|---|---|
| **QR Code Expired** | Baileys QR rotates every ~60 seconds if un-scanned | Enlarge terminal window and scan the newest QR code that prints automatically. |
| **"WhatsApp session logged out"** | Device was unlinked from WhatsApp mobile app | Stop gateway (`Ctrl + C`), delete `./auth_state/`, and restart `npm run dev` to scan a fresh QR code. |
| **`@lid` JID Format** | WhatsApp modern privacy format for phone numbers | Supported natively. The gateway forwards `remoteJid` unchanged and uses it directly for message replies. |
| **Gemini API Quota Exhausted** | Google AI free tier rate limit exceeded | The system falls back to Groq (`llama-3.3-70b-versatile`) if `GROQ_API_KEY` is present, or extractive context matching. |
| **Gateway Cannot Reach API (ECONNREFUSED)** | FastAPI backend is stopped or running on another port | Verify FastAPI is running in Terminal 1 on `http://127.0.0.1:8000`. |
| **401 Unauthorized Error in Gateway** | Shared secret mismatch between `.env` files | Verify `WHATSAPP_GATEWAY_SECRET` in root `.env` exactly matches `GATEWAY_SECRET` in `whatsapp-gateway/.env`. |

---

## 6. Production Architecture Roadmap

While Baileys provides a fast developer bridge, enterprise production deployment requires the following architecture:

1. **Official WhatsApp Cloud API**:
   - Replace Baileys with Meta's official WhatsApp Business Cloud API (`graph.facebook.com`).
   - Implement `ChannelAdapter.send_message` to dispatch via Meta REST endpoints.

2. **Webhook HMAC Signature Verification**:
   - Authenticate incoming Meta webhooks via `X-Hub-Signature-256` using `HMAC-SHA256` with Meta App Secret.

3. **Secure Auth & Credential Storage**:
   - Migrate session credentials from local `./auth_state` to encrypted enterprise secrets storage (AWS Secrets Manager, HashiCorp Vault).

4. **Multi-Tenant Routing**:
   - Map enterprise `tenant_id` to distinct WhatsApp Business Phone Number IDs or WABA accounts for complete company isolation.

5. **Asynchronous Query Queuing**:
   - Decouple inbound webhook handling from RAG generation using Redis + Celery / BullMQ worker queues to ensure 200 OK responses to WhatsApp within 5 seconds while processing complex multi-chunk retrievals.

---

## 7. Manual Testing Checklist for Real Phones

- [ ] **QR Connection**: Gateway starts and terminal QR code links phone without disconnection warnings.
- [ ] **Web UI**: `/linked-devices` displays "Not Linked", generates a 6-digit code, and live countdown starts.
- [ ] **Linking**: Sending `LINK <code>` from real phone links within 3 seconds and web UI updates to "Connected".
- [ ] **General Query**: Employee asks about leave policy -> Receives accurate summary with citations to `HR_Employee_Handbook_2026.txt`.
- [ ] **ACL Isolation**: Employee asks about executive compensation -> Denied with "I couldn't find that in the documents you have access to."
- [ ] **Privileged Access**: Finance user asks about executive compensation -> Receives CEO salary ($850,000) with citation to `Executive_Compensation_2026.txt`.
- [ ] **Session Reset**: `/new` clears context without crashing.
- [ ] **Unlink**: `/unlink` revokes link; subsequent questions prompt user to re-link via web app.
