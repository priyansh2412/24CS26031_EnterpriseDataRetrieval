# WhatsApp Gateway for Enterprise RAG Assistant

A lightweight Node.js (v20+) TypeScript service that connects a single WhatsApp number using [Baileys](https://github.com/WhiskeySockets/Baileys) and bridges incoming messages to the FastAPI enterprise retrieval backend.

---

## 1. Installation

From the repository root, enter the gateway directory and install dependencies:

```bash
cd whatsapp-gateway
npm install
```

---

## 2. Configuration

Create your local `.env` file from `.env.example`:

```bash
cp .env.example .env
```

Edit `.env` with your settings:

```ini
# FastAPI Backend URL
API_URL=http://127.0.0.1:8000

# Secret matching WHATSAPP_GATEWAY_SECRET in the backend .env
GATEWAY_SECRET=your-secure-secret-here

# Allow processing messages from group chats (default false for employee private chats)
ALLOW_GROUPS=false
```

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `API_URL` | `http://127.0.0.1:8000` | Base URL of the FastAPI backend service |
| `GATEWAY_SECRET` | *(required)* | Shared secret sent via `x-gateway-secret` header |
| `ALLOW_GROUPS` | `false` | When `false`, messages ending in `@g.us` are skipped |
| `LOG_LEVEL` | `info` | Pino logging level (`info`, `debug`, `warn`, `error`) |

---

## 3. Running the Gateway

Start in development mode with hot-reloading via `tsx`:

```bash
npm run dev
```

Or run directly:

```bash
npm start
```

---

## 4. How to Scan the QR Code

1. Start the gateway service. A QR code will be printed in the terminal.
2. Open WhatsApp on your mobile phone.
3. Navigate to:
   - **Android**: Tap the three vertical dots `⋮` (top-right) > **Linked devices** > **Link a device**.
   - **iOS**: Tap **Settings** (bottom-right) > **Linked devices** > **Link a device**.
4. Point your camera at the QR code displayed in the terminal.
5. Once scanned, the terminal will log:
   ```text
   Connected as <your_number>
   ```
6. Credentials are saved locally in `./auth_state`. On subsequent restarts, the gateway reconnects automatically without needing to re-scan.

---

## 5. Troubleshooting

### "WhatsApp session logged out"
- **Cause**: The device was unlinked from WhatsApp on your phone or the session token was revoked.
- **Fix**:
  1. Stop the gateway (`Ctrl + C`).
  2. Delete the `./auth_state` folder:
     ```bash
     # Windows PowerShell:
     Remove-Item -Recurse -Force ./auth_state
     
     # Linux/macOS:
     rm -rf ./auth_state
     ```
  3. Restart `npm run dev` and scan the newly generated QR code.

### "QR Code Not Showing" or Terminal Garbled
- **Small terminal window**: Expand your terminal window size so the entire QR code fits vertically and horizontally.
- **Already paired**: If `./auth_state` exists and the session is valid, Baileys will reconnect silently without displaying a QR code.
- **Connection timeouts**: If connection closes due to network interruptions, the gateway automatically retries with exponential backoff (2s up to 30s).

---

## 6. Architecture & Security

- **Message Processing**: Uses an in-memory sequential promise queue per JID to guarantee FIFO ordering per user.
- **Privacy**: Message body text is never logged at `info` level (only metadata: JID, message ID, push name).
- **Timeouts & Chunking**: Uses a 60-second AbortController timeout for backend RAG queries and splits replies exceeding 3000 characters along paragraph boundaries with a 600ms spacing between sends.
