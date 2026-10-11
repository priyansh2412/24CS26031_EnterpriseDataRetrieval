import { useState, useEffect, useRef, useCallback } from "react";
import {
  MessageCircle,
  Copy,
  ExternalLink,
  Check,
  CheckCircle2,
  AlertCircle,
  Info,
  Clock,
  RefreshCw,
  Unlink,
  ShieldCheck,
  Terminal,
  Smartphone,
  Sparkles,
} from "lucide-react";
import {
  linkStart,
  linkStatus,
  linkDelete,
  WhatsAppLinkStatusResponse,
  WhatsAppLinkStartResponse,
} from "../api";

export default function LinkedDevicesPage() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [status, setStatus] = useState<WhatsAppLinkStatusResponse | null>(null);
  const [pending, setPending] = useState<WhatsAppLinkStartResponse | null>(null);
  const [timeLeftMs, setTimeLeftMs] = useState<number>(0);
  const [copied, setCopied] = useState(false);
  const [actionLoading, setActionLoading] = useState(false);
  const [showConfirmUnlink, setShowConfirmUnlink] = useState(false);

  const pollTimerRef = useRef<number | null>(null);
  const countdownTimerRef = useRef<number | null>(null);

  // Clear timers helper
  const clearTimers = useCallback(() => {
    if (pollTimerRef.current !== null) {
      window.clearInterval(pollTimerRef.current);
      pollTimerRef.current = null;
    }
    if (countdownTimerRef.current !== null) {
      window.clearInterval(countdownTimerRef.current);
      countdownTimerRef.current = null;
    }
  }, []);

  // Fetch initial link status
  const fetchStatus = useCallback(async () => {
    try {
      setError(null);
      const res = await linkStatus();
      setStatus(res);
      if (res.linked) {
        setPending(null);
        clearTimers();
      }
    } catch (err: any) {
      setError(err?.message || "Failed to load WhatsApp link status");
    } finally {
      setLoading(false);
    }
  }, [clearTimers]);

  useEffect(() => {
    fetchStatus();
    return () => clearTimers();
  }, [fetchStatus, clearTimers]);

  // Handle countdown & 3s polling when in pending state
  useEffect(() => {
    if (!pending || status?.linked) {
      clearTimers();
      return;
    }

    const expiresAt = new Date(pending.expires_at).getTime();

    // 1. Countdown timer (1s interval)
    const updateCountdown = () => {
      const remaining = Math.max(0, expiresAt - Date.now());
      setTimeLeftMs(remaining);
      if (remaining <= 0) {
        clearTimers();
      }
    };

    updateCountdown();
    countdownTimerRef.current = window.setInterval(updateCountdown, 1000);

    // 2. Status Poller (3s interval)
    pollTimerRef.current = window.setInterval(async () => {
      try {
        const res = await linkStatus();
        if (res.linked) {
          setStatus(res);
          setPending(null);
          clearTimers();
          setSuccess("WhatsApp number successfully connected!");
        }
      } catch {
        // Silent poll error
      }
    }, 3000);

    return () => {
      clearTimers();
    };
  }, [pending, status?.linked, clearTimers]);

  // Start linking flow (POST /api/whatsapp/link/start)
  const handleStartLink = async () => {
    setActionLoading(true);
    setError(null);
    setSuccess(null);
    try {
      const res = await linkStart();
      setPending(res);
      const initialRemaining = Math.max(0, new Date(res.expires_at).getTime() - Date.now());
      setTimeLeftMs(initialRemaining);
    } catch (err: any) {
      setError(err?.message || "Failed to generate linking code");
    } finally {
      setActionLoading(false);
    }
  };

  // Unlink flow (DELETE /api/whatsapp/link)
  const handleUnlink = async () => {
    setActionLoading(true);
    setError(null);
    setSuccess(null);
    try {
      await linkDelete();
      setStatus({ linked: false });
      setPending(null);
      setShowConfirmUnlink(false);
      clearTimers();
      setSuccess("WhatsApp connection successfully revoked.");
    } catch (err: any) {
      setError(err?.message || "Failed to unlink WhatsApp device");
    } finally {
      setActionLoading(false);
    }
  };

  // Copy LINK <code> to clipboard
  const handleCopyMessage = async () => {
    if (!pending?.code) return;
    const msg = `LINK ${pending.code}`;
    try {
      await navigator.clipboard.writeText(msg);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setError("Failed to copy to clipboard. Please copy manually.");
    }
  };

  // Format mm:ss
  const formatTime = (ms: number): string => {
    if (ms <= 0) return "00:00";
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes.toString().padStart(2, "0")}:${seconds.toString().padStart(2, "0")}`;
  };

  const isExpired = pending !== null && timeLeftMs <= 0;
  const botDigits = (pending?.bot_number || "").replace(/\D/g, "");
  const waDirectUrl = pending
    ? `https://wa.me/${botDigits}?text=LINK%20${encodeURIComponent(pending.code)}`
    : "#";

  return (
    <div className="linked-devices-page animate-fade-in" style={{ maxWidth: "1050px", margin: "0 auto", paddingBottom: "60px" }}>
      {/* Page Header */}
      <header className="page-heading" style={{ marginBottom: "24px" }}>
        <div>
          <div className="eyebrow" style={{ display: "flex", alignItems: "center", gap: "6px", color: "#2563eb", fontWeight: "700" }}>
            <MessageCircle size={14} /> MULTI-CHANNEL ASSISTANT ACCESS
          </div>
          <h1 style={{ fontSize: "28px", fontWeight: "800", color: "#0f172a", margin: "6px 0" }}>
            Linked WhatsApp Devices
          </h1>
          <p className="subheading" style={{ color: "#64748b", fontSize: "14px", margin: 0 }}>
            Connect your personal or work WhatsApp number to interact with your enterprise knowledge base directly from chat.
          </p>
        </div>
        <button
          className="btn-secondary"
          onClick={fetchStatus}
          disabled={loading || actionLoading}
          title="Refresh connection status"
        >
          <RefreshCw size={15} className={loading ? "animate-spin" : ""} />
          <span>Refresh Status</span>
        </button>
      </header>

      {/* Notifications & Error Banners */}
      {error && (
        <div className="alert-banner error margin-bottom">
          <AlertCircle size={16} />
          <span>{error}</span>
        </div>
      )}

      {success && (
        <div className="alert-banner success margin-bottom">
          <CheckCircle2 size={16} />
          <span>{success}</span>
        </div>
      )}

      {/* Main Body State Machine */}
      {loading ? (
        <div className="dash-module-card" style={{ padding: "48px", textAlign: "center" }}>
          <RefreshCw size={24} className="animate-spin" style={{ margin: "0 auto 12px", color: "#2563eb" }} />
          <p style={{ color: "#64748b", fontSize: "14px", margin: 0 }}>Checking device connection status...</p>
        </div>
      ) : status?.linked ? (
        /* STATE 3: LINKED */
        <div className="linked-container">
          {/* Status Overview Card */}
          <div className="dash-module-card linked-success-card" style={{ padding: "32px", marginBottom: "24px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: "16px" }}>
              <div style={{ display: "flex", gap: "18px", alignItems: "center" }}>
                <div className="module-icon icon-green" style={{ width: "52px", height: "52px" }}>
                  <Smartphone size={26} />
                </div>
                <div>
                  <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "4px" }}>
                    <h3 style={{ margin: 0, fontSize: "20px", fontWeight: "700" }}>
                      {status.wa_display_name || "Connected Device"}
                    </h3>
                    <span className="channel-badge whatsapp" style={{ display: "inline-flex", alignItems: "center", gap: "5px" }}>
                      <span className="pulse-dot green" />
                      Connected
                    </span>
                  </div>
                  <p style={{ margin: 0, color: "#64748b", fontSize: "13.5px" }}>
                    Verified on{" "}
                    <strong>
                      {status.verified_at ? new Date(status.verified_at).toLocaleString() : "Active"}
                    </strong>
                  </p>
                </div>
              </div>

              {!showConfirmUnlink ? (
                <button
                  className="btn-secondary"
                  onClick={() => setShowConfirmUnlink(true)}
                  disabled={actionLoading}
                  style={{ color: "#dc2626", borderColor: "#fecaca" }}
                >
                  <Unlink size={16} />
                  <span>Unlink Device</span>
                </button>
              ) : (
                <div className="confirm-unlink-box" style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                  <span style={{ fontSize: "13px", color: "#b91c1c", fontWeight: "500" }}>
                    Disconnect this WhatsApp number?
                  </span>
                  <button
                    className="btn-primary"
                    style={{ background: "#dc2626", borderColor: "#dc2626", padding: "6px 12px", fontSize: "12.5px" }}
                    onClick={handleUnlink}
                    disabled={actionLoading}
                  >
                    {actionLoading ? "Unlinking..." : "Confirm Unlink"}
                  </button>
                  <button
                    className="btn-secondary"
                    style={{ padding: "6px 12px", fontSize: "12.5px" }}
                    onClick={() => setShowConfirmUnlink(false)}
                    disabled={actionLoading}
                  >
                    Cancel
                  </button>
                </div>
              )}
            </div>

            <div style={{ marginTop: "24px", paddingTop: "20px", borderTop: "1px solid #f1f5f9", display: "flex", alignItems: "center", gap: "10px", color: "#475569", fontSize: "13.5px" }}>
              <ShieldCheck size={18} style={{ color: "#16a34a", flexShrink: 0 }} />
              <span>
                Your WhatsApp queries run through the enterprise RAG pipeline and adhere to your exact hierarchical role rank and ACL permissions.
              </span>
            </div>
          </div>

          {/* WhatsApp Commands Guidance Card */}
          <div className="dash-module-card" style={{ padding: "28px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "16px" }}>
              <Terminal size={18} style={{ color: "#2563eb" }} />
              <h4 style={{ margin: 0, fontSize: "16px", fontWeight: "700" }}>Available WhatsApp Bot Commands</h4>
            </div>
            <p style={{ color: "#64748b", fontSize: "13.5px", margin: "0 0 18px 0" }}>
              Send these commands anytime directly in your WhatsApp conversation with the enterprise bot:
            </p>

            <div className="bot-commands-grid" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))", gap: "16px" }}>
              <div className="command-tile" style={{ padding: "16px", borderRadius: "8px", background: "#f8fafc", border: "1px solid #e2e8f0" }}>
                <code style={{ fontSize: "14px", fontWeight: "700", color: "#2563eb" }}>/help</code>
                <p style={{ margin: "6px 0 0", fontSize: "12.5px", color: "#64748b" }}>
                  Displays information on how to interact with the assistant, ask questions, and list commands.
                </p>
              </div>

              <div className="command-tile" style={{ padding: "16px", borderRadius: "8px", background: "#f8fafc", border: "1px solid #e2e8f0" }}>
                <code style={{ fontSize: "14px", fontWeight: "700", color: "#2563eb" }}>/new</code>
                <p style={{ margin: "6px 0 0", fontSize: "12.5px", color: "#64748b" }}>
                  Clears current conversational memory and starts a fresh inquiry session.
                </p>
              </div>

              <div className="command-tile" style={{ padding: "16px", borderRadius: "8px", background: "#f8fafc", border: "1px solid #e2e8f0" }}>
                <code style={{ fontSize: "14px", fontWeight: "700", color: "#dc2626" }}>/unlink</code>
                <p style={{ margin: "6px 0 0", fontSize: "12.5px", color: "#64748b" }}>
                  Revokes access for your WhatsApp number immediately from your phone without needing the web app.
                </p>
              </div>
            </div>
          </div>
        </div>
      ) : pending ? (
        /* STATE 2: PENDING (After POST link/start) */
        <div className="dash-module-card pending-link-card" style={{ padding: "36px", textAlign: "center" }}>
          <div style={{ maxWidth: "560px", margin: "0 auto" }}>
            <div className="module-icon icon-blue" style={{ width: "56px", height: "56px", margin: "0 auto 16px" }}>
              <Smartphone size={28} />
            </div>

            <h2 style={{ fontSize: "22px", fontWeight: "800", color: "#0f172a", margin: "0 0 8px" }}>
              Link Your WhatsApp Number
            </h2>
            <p style={{ color: "#64748b", fontSize: "14px", margin: "0 0 24px" }}>
              Send the verification code below to the enterprise bot number from WhatsApp.
            </p>

            {/* Verification Code Box */}
            <div
              className="link-code-container"
              style={{
                background: isExpired ? "#fef2f2" : "#f0fdf4",
                border: `2px dashed ${isExpired ? "#fca5a5" : "#86efac"}`,
                borderRadius: "14px",
                padding: "24px 20px",
                marginBottom: "20px",
              }}
            >
              <span style={{ fontSize: "12px", fontWeight: "700", letterSpacing: "1px", color: isExpired ? "#991b1b" : "#166534", textTransform: "uppercase" }}>
                {isExpired ? "Verification Code Expired" : "Your 6-Digit Linking Code"}
              </span>
              <div
                className="big-link-code"
                style={{
                  fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
                  fontSize: "38px",
                  fontWeight: "800",
                  letterSpacing: "8px",
                  color: isExpired ? "#991b1b" : "#15803d",
                  margin: "8px 0",
                }}
              >
                {pending.code}
              </div>

              {/* Countdown / Expiration Display */}
              <div style={{ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: "13px", color: isExpired ? "#b91c1c" : "#15803d", fontWeight: "600" }}>
                <Clock size={15} />
                <span>
                  {isExpired ? "Expired" : `Expires in ${formatTime(timeLeftMs)}`}
                </span>
              </div>
            </div>

            {/* Instruction from Backend */}
            <div className="alert-banner info margin-bottom" style={{ textAlign: "left", justifyContent: "center" }}>
              <Info size={16} />
              <span>{pending.instruction}</span>
            </div>

            {/* Action Buttons */}
            {isExpired ? (
              <div style={{ marginTop: "24px" }}>
                <button
                  className="btn-primary"
                  onClick={handleStartLink}
                  disabled={actionLoading}
                  style={{ width: "100%", justifyContent: "center", padding: "12px 20px" }}
                >
                  <RefreshCw size={16} className={actionLoading ? "animate-spin" : ""} />
                  <span>Generate New Code</span>
                </button>
              </div>
            ) : (
              <div style={{ display: "flex", gap: "12px", justifyContent: "center", flexWrap: "wrap", marginTop: "20px" }}>
                <button
                  className="btn-primary"
                  onClick={handleCopyMessage}
                  title="Copy 'LINK <code>' message to clipboard"
                  style={{ minWidth: "160px", justifyContent: "center" }}
                >
                  {copied ? <Check size={16} /> : <Copy size={16} />}
                  <span>{copied ? "Copied Message!" : `Copy "LINK ${pending.code}"`}</span>
                </button>

                <a
                  href={waDirectUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-secondary"
                  style={{ minWidth: "160px", justifyContent: "center", textDecoration: "none" }}
                >
                  <ExternalLink size={16} />
                  <span>Open WhatsApp</span>
                </a>

                <button
                  className="btn-secondary"
                  onClick={handleStartLink}
                  disabled={actionLoading}
                  title="Generate a new linking code"
                >
                  <RefreshCw size={15} className={actionLoading ? "animate-spin" : ""} />
                  <span>New Code</span>
                </button>
              </div>
            )}

            <div style={{ marginTop: "24px", display: "flex", alignItems: "center", justifyContent: "center", gap: "8px", color: "#64748b", fontSize: "12.5px" }}>
              <span className="pulse-dot blue" />
              <span>Waiting for message... Polling status automatically</span>
            </div>
          </div>
        </div>
      ) : (
        /* STATE 1: NOT LINKED */
        <div className="dash-module-card not-linked-card" style={{ padding: "48px 32px", textAlign: "center" }}>
          <div style={{ maxWidth: "560px", margin: "0 auto" }}>
            <div
              className="module-icon icon-blue"
              style={{
                width: "68px",
                height: "68px",
                margin: "0 auto 20px",
                background: "linear-gradient(135deg, #eff6ff, #dbeafe)",
                color: "#2563eb",
              }}
            >
              <MessageCircle size={36} />
            </div>

            <h2 style={{ fontSize: "24px", fontWeight: "800", color: "#0f172a", margin: "0 0 12px" }}>
              Connect WhatsApp to Your Account
            </h2>

            <p style={{ color: "#475569", fontSize: "15px", lineHeight: "1.6", margin: "0 0 28px" }}>
              Ask questions about your documents from WhatsApp. Your access rules are exactly the same as on the website.
            </p>

            <button
              className="btn-primary"
              onClick={handleStartLink}
              disabled={actionLoading}
              style={{
                padding: "14px 28px",
                fontSize: "15px",
                fontWeight: "700",
                borderRadius: "10px",
                margin: "0 auto",
                display: "inline-flex",
                alignItems: "center",
                gap: "10px",
                boxShadow: "0 4px 14px rgba(37, 99, 235, 0.25)",
              }}
            >
              <Smartphone size={18} />
              <span>{actionLoading ? "Generating Code..." : "Link WhatsApp"}</span>
            </button>

            <div
              style={{
                marginTop: "36px",
                padding: "16px 20px",
                background: "#f8fafc",
                borderRadius: "10px",
                border: "1px solid #e2e8f0",
                display: "flex",
                alignItems: "center",
                gap: "12px",
                textAlign: "left",
              }}
            >
              <ShieldCheck size={20} style={{ color: "#2563eb", flexShrink: 0 }} />
              <span style={{ fontSize: "13px", color: "#64748b" }}>
                Enterprise Security: Messages are authorized through your authenticated employee identity. Your role rank and access restrictions are strictly enforced.
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
