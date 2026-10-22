import React, { useState, useEffect, useRef, useCallback } from "react";
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
  X,
  ArrowRight,
  Shield,
  Zap,
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

  // Determine active step (1, 2, or 3)
  const currentStep = status?.linked ? 3 : pending ? 2 : 1;

  return (
    <div className="linked-devices-page animate-fade-in">
      {/* Page Header */}
      <header className="page-heading" style={{ marginBottom: "24px" }}>
        <div>
          <div className="eyebrow">
            <MessageCircle size={14} /> MULTI-CHANNEL ASSISTANT ACCESS
          </div>
          <h1>Linked WhatsApp Devices</h1>
          <p className="subheading">
            Connect your personal or work WhatsApp number to interact with your enterprise knowledge base directly from chat.
          </p>
        </div>
        <button
          className="btn-pill btn-secondary"
          onClick={fetchStatus}
          disabled={loading || actionLoading}
          title="Refresh connection status"
        >
          <RefreshCw size={15} className={loading ? "spin" : ""} />
          <span>Refresh Status</span>
        </button>
      </header>

      {/* Notifications & Error Banners */}
      {error && (
        <div className="alert-banner error" style={{ marginBottom: "20px" }}>
          <AlertCircle size={16} />
          <span>{error}</span>
          <button
            type="button"
            onClick={() => setError(null)}
            style={{ marginLeft: "auto", background: "none", border: "none", cursor: "pointer", color: "inherit" }}
          >
            <X size={14} />
          </button>
        </div>
      )}

      {success && (
        <div className="alert-banner success" style={{ marginBottom: "20px" }}>
          <CheckCircle2 size={16} />
          <span>{success}</span>
          <button
            type="button"
            onClick={() => setSuccess(null)}
            style={{ marginLeft: "auto", background: "none", border: "none", cursor: "pointer", color: "inherit" }}
          >
            <X size={14} />
          </button>
        </div>
      )}

      {/* 3-Step Setup Stepper Card */}
      <div className="stepper-container">
        <div className={`stepper-step ${currentStep === 1 ? "active" : currentStep > 1 ? "completed" : ""}`}>
          <div className="stepper-num">
            {currentStep > 1 ? <Check size={14} /> : "1"}
          </div>
          <div className="stepper-info">
            <h4>Generate Code</h4>
            <p>Request 6-digit sync key</p>
          </div>
        </div>

        <div className={`stepper-step ${currentStep === 2 ? "active" : currentStep > 2 ? "completed" : ""}`}>
          <div className="stepper-num">
            {currentStep > 2 ? <Check size={14} /> : "2"}
          </div>
          <div className="stepper-info">
            <h4>Send WhatsApp Code</h4>
            <p>Send “LINK &lt;code&gt;” to bot</p>
          </div>
        </div>

        <div className={`stepper-step ${currentStep === 3 ? "active completed" : ""}`}>
          <div className="stepper-num">
            {currentStep === 3 ? <Check size={14} /> : "3"}
          </div>
          <div className="stepper-info">
            <h4>Device Linked</h4>
            <p>Query assistant anywhere</p>
          </div>
        </div>
      </div>

      {/* Main Content Area */}
      {loading ? (
        <div className="card-glass" style={{ padding: "48px 24px", textAlign: "center" }}>
          <RefreshCw size={28} className="spin" style={{ color: "var(--palette-sky)", margin: "0 auto 12px" }} />
          <h4 style={{ margin: "0 0 4px", fontSize: "16px", color: "var(--text)" }}>
            Checking Device Connection Status…
          </h4>
          <p style={{ margin: 0, fontSize: "13px", color: "var(--text-muted)" }}>
            Verifying your WhatsApp authentication records
          </p>
        </div>
      ) : status?.linked ? (
        /* STATE 3: LINKED */
        <div className="linked-container">
          {/* Status Overview Card */}
          <div className="card-glass" style={{ padding: "28px 32px", marginBottom: "24px" }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "16px" }}>
              <div style={{ display: "flex", gap: "18px", alignItems: "center" }}>
                <div
                  style={{
                    width: "56px",
                    height: "56px",
                    borderRadius: "16px",
                    background: "rgba(16, 185, 129, 0.12)",
                    color: "#059669",
                    display: "grid",
                    placeItems: "center",
                    flexShrink: 0,
                    border: "1px solid rgba(16, 185, 129, 0.25)",
                  }}
                >
                  <Smartphone size={28} />
                </div>
                <div>
                  <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "4px" }}>
                    <h3 style={{ margin: 0, fontSize: "20px", fontWeight: "700", color: "var(--text)" }}>
                      {status.wa_display_name || "Connected Mobile Device"}
                    </h3>
                    <span className="channel-badge whatsapp">
                      <span className="pulse-dot green" />
                      Active & Linked
                    </span>
                  </div>
                  <p style={{ margin: 0, color: "var(--text-muted)", fontSize: "13.5px" }}>
                    Verified on{" "}
                    <strong style={{ color: "var(--text)" }}>
                      {status.verified_at ? new Date(status.verified_at).toLocaleString() : "Active Session"}
                    </strong>
                  </p>
                </div>
              </div>

              {!showConfirmUnlink ? (
                <button
                  className="btn-pill btn-secondary"
                  onClick={() => setShowConfirmUnlink(true)}
                  disabled={actionLoading}
                  style={{ color: "#e11d48", borderColor: "rgba(244, 63, 94, 0.3)" }}
                >
                  <Unlink size={15} />
                  <span>Unlink Device</span>
                </button>
              ) : (
                <div style={{ display: "flex", alignItems: "center", gap: "8px", background: "var(--bg-subtle)", padding: "8px 12px", borderRadius: "var(--radius-pill)", border: "1px solid var(--border)" }}>
                  <span style={{ fontSize: "12.5px", color: "#e11d48", fontWeight: "600" }}>
                    Disconnect WhatsApp?
                  </span>
                  <button
                    className="btn-pill btn-primary"
                    style={{ background: "#e11d48", borderColor: "#e11d48", padding: "6px 14px", fontSize: "12px" }}
                    onClick={handleUnlink}
                    disabled={actionLoading}
                  >
                    {actionLoading ? "Unlinking…" : "Confirm Unlink"}
                  </button>
                  <button
                    className="btn-pill btn-secondary"
                    style={{ padding: "6px 12px", fontSize: "12px" }}
                    onClick={() => setShowConfirmUnlink(false)}
                    disabled={actionLoading}
                  >
                    Cancel
                  </button>
                </div>
              )}
            </div>

            <div style={{ marginTop: "20px", paddingTop: "16px", borderTop: "1px solid var(--border)", display: "flex", alignItems: "center", gap: "10px", color: "var(--text-muted)", fontSize: "13px" }}>
              <ShieldCheck size={18} style={{ color: "#10b981", flexShrink: 0 }} />
              <span>
                Your WhatsApp queries run through the enterprise RAG pipeline and adhere to your exact hierarchical role rank and ACL permissions.
              </span>
            </div>
          </div>

          {/* Bot Commands Guidance Card */}
          <div className="card-glass" style={{ padding: "28px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "12px" }}>
              <Terminal size={18} style={{ color: "var(--palette-sky)" }} />
              <h4 style={{ margin: 0, fontSize: "16px", fontWeight: "700", color: "var(--text)" }}>
                Available WhatsApp Bot Commands
              </h4>
            </div>
            <p style={{ color: "var(--text-muted)", fontSize: "13.5px", margin: "0 0 20px 0" }}>
              Send these commands anytime directly in your WhatsApp conversation with the enterprise assistant:
            </p>

            <div className="bot-commands-grid">
              <div className="bot-command-chip">
                <code>/help</code>
                <p>Displays quick guidance on how to ask questions and inspect retrieved citations directly in WhatsApp.</p>
              </div>

              <div className="bot-command-chip">
                <code>/new</code>
                <p>Clears current conversational memory and starts a clean query session with fresh context.</p>
              </div>

              <div className="bot-command-chip danger">
                <code>/unlink</code>
                <p>Revokes access for your WhatsApp number immediately from your phone without needing the web portal.</p>
              </div>
            </div>
          </div>
        </div>
      ) : pending ? (
        /* STATE 2: PENDING */
        <div className="card-glass" style={{ padding: "40px 28px", textAlign: "center" }}>
          <div style={{ maxWidth: "580px", margin: "0 auto" }}>
            <div
              style={{
                width: "60px",
                height: "60px",
                borderRadius: "18px",
                background: "rgba(56, 189, 248, 0.12)",
                color: "var(--palette-sky)",
                display: "grid",
                placeItems: "center",
                margin: "0 auto 16px",
                border: "1px solid rgba(56, 189, 248, 0.25)",
              }}
            >
              <Smartphone size={30} />
            </div>

            <h2 style={{ fontSize: "22px", fontWeight: "800", color: "var(--text)", margin: "0 0 8px" }}>
              Link Your WhatsApp Number
            </h2>
            <p style={{ color: "var(--text-muted)", fontSize: "14px", margin: "0 0 24px" }}>
              Send the verification code below to the enterprise bot number from WhatsApp.
            </p>

            {/* Verification Code Box */}
            <div className={`big-link-code-box ${isExpired ? "expired" : ""}`}>
              <span style={{ fontSize: "11.5px", fontWeight: "700", letterSpacing: "1px", color: isExpired ? "#e11d48" : "var(--palette-sky)", textTransform: "uppercase" }}>
                {isExpired ? "Verification Code Expired" : "Your 6-Digit Linking Code"}
              </span>

              <div className="big-link-code-text">
                {pending.code}
              </div>

              <div style={{ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: "13px", color: isExpired ? "#e11d48" : "var(--text-muted)", fontWeight: "600" }}>
                <Clock size={15} />
                <span>
                  {isExpired ? "Expired. Please generate a new code." : `Expires in ${formatTime(timeLeftMs)}`}
                </span>
              </div>
            </div>

            {/* Instruction Banner */}
            <div className="alert-banner info" style={{ textAlign: "left", justifyContent: "center", marginBottom: "24px" }}>
              <Info size={16} />
              <span>{pending.instruction}</span>
            </div>

            {/* Action Buttons */}
            {isExpired ? (
              <button
                className="btn-pill btn-primary"
                onClick={handleStartLink}
                disabled={actionLoading}
                style={{ width: "100%", justifyContent: "center", padding: "12px 20px" }}
              >
                <RefreshCw size={16} className={actionLoading ? "spin" : ""} />
                <span>Generate Fresh Code</span>
              </button>
            ) : (
              <div style={{ display: "flex", gap: "12px", justifyContent: "center", flexWrap: "wrap" }}>
                <button
                  className="btn-pill btn-primary"
                  onClick={handleCopyMessage}
                  title="Copy 'LINK <code>' message to clipboard"
                  style={{ minWidth: "170px", justifyContent: "center" }}
                >
                  {copied ? <Check size={16} /> : <Copy size={16} />}
                  <span>{copied ? "Copied Message!" : `Copy "LINK ${pending.code}"`}</span>
                </button>

                <a
                  href={waDirectUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn-pill btn-secondary"
                  style={{ minWidth: "160px", justifyContent: "center", textDecoration: "none" }}
                >
                  <ExternalLink size={16} />
                  <span>Open WhatsApp</span>
                </a>

                <button
                  className="btn-pill btn-secondary"
                  onClick={handleStartLink}
                  disabled={actionLoading}
                  title="Generate a new linking code"
                >
                  <RefreshCw size={15} className={actionLoading ? "spin" : ""} />
                  <span>New Code</span>
                </button>
              </div>
            )}

            <div style={{ marginTop: "24px", display: "flex", alignItems: "center", justifyContent: "center", gap: "8px", color: "var(--text-muted)", fontSize: "12.5px" }}>
              <span className="pulse-dot green" />
              <span>Waiting for message… Polling status automatically</span>
            </div>
          </div>
        </div>
      ) : (
        /* STATE 1: NOT LINKED */
        <div className="card-glass" style={{ padding: "48px 32px", textAlign: "center" }}>
          <div style={{ maxWidth: "580px", margin: "0 auto" }}>
            <div
              style={{
                width: "68px",
                height: "68px",
                borderRadius: "20px",
                margin: "0 auto 20px",
                background: "var(--palette-gradient)",
                display: "grid",
                placeItems: "center",
                color: "#fff",
                boxShadow: "0 6px 20px rgba(56, 189, 248, 0.3)",
              }}
            >
              <MessageCircle size={34} />
            </div>

            <h2 style={{ fontSize: "24px", fontWeight: "800", color: "var(--text)", margin: "0 0 10px" }}>
              Connect WhatsApp to Your Account
            </h2>

            <p style={{ color: "var(--text-muted)", fontSize: "14.5px", lineHeight: "1.6", margin: "0 0 28px" }}>
              Ask questions about your enterprise documents directly from WhatsApp. Your questions are answered using real-time retrieval with the exact same access permissions as the web portal.
            </p>

            <button
              className="btn-pill btn-primary"
              onClick={handleStartLink}
              disabled={actionLoading}
              style={{
                padding: "14px 32px",
                fontSize: "15px",
                fontWeight: "700",
                display: "inline-flex",
                alignItems: "center",
                gap: "10px",
                margin: "0 auto",
              }}
            >
              <Smartphone size={18} />
              <span>{actionLoading ? "Generating Code…" : "Generate Linking Code"}</span>
              <ArrowRight size={16} />
            </button>

            <div
              style={{
                marginTop: "36px",
                padding: "16px 20px",
                background: "var(--bg-subtle)",
                borderRadius: "var(--radius-lg)",
                border: "1px solid var(--border)",
                display: "flex",
                alignItems: "center",
                gap: "12px",
                textAlign: "left",
              }}
            >
              <ShieldCheck size={20} style={{ color: "var(--palette-sky)", flexShrink: 0 }} />
              <span style={{ fontSize: "12.5px", color: "var(--text-muted)" }}>
                <strong>Enterprise Security:</strong> WhatsApp messages are authenticated to your employee account. Subordinate role ranks and document security rules are enforced on every response.
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
