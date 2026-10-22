import { useState } from "react";
import {
  ShieldCheck,
  Eye,
  EyeOff,
  KeyRound,
  ArrowRight,
  CheckCircle2,
  AlertCircle,
  Lock,
  Sun,
  Moon,
  Sparkles,
  Zap,
} from "lucide-react";
import { forgotPassword, login } from "../api";

interface LoginPageProps {
  onSuccess: () => void;
  theme?: "light" | "dark";
  onToggleTheme?: () => void;
}

export default function LoginPage({ onSuccess, theme = "light", onToggleTheme }: LoginPageProps) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // Forgot Password Modal State
  const [showForgotModal, setShowForgotModal] = useState(false);
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotLoading, setForgotLoading] = useState(false);
  const [forgotMessage, setForgotMessage] = useState("");
  const [forgotError, setForgotError] = useState("");

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await login(email, password);
      onSuccess();
    } catch (err) {
      setError((err as Error).message || "Invalid credentials");
    } finally {
      setLoading(false);
    }
  };

  const handleForgotPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setForgotError("");
    setForgotMessage("");
    setForgotLoading(true);
    try {
      const res = await forgotPassword(forgotEmail);
      setForgotMessage(res.message || "Password reset instructions recorded.");
    } catch (err) {
      setForgotError((err as Error).message || "Email address not found in database.");
    } finally {
      setForgotLoading(false);
    }
  };

  // Quick Demo Helper
  const fillCredentials = (demoEmail: string, demoPass: string) => {
    setEmail(demoEmail);
    setPassword(demoPass);
  };

  return (
    <main className={`login-container ${theme}-theme`}>
      {/* Decorative ambient background mesh blobs */}
      <div className="ambient-bg-glow ambient-blob-1" />
      <div className="ambient-bg-glow ambient-blob-2" />

      {/* Theme Toggle in Top Right */}
      {onToggleTheme && (
        <div className="login-theme-pill-wrap">
          <button
            type="button"
            className="theme-toggle-btn"
            onClick={onToggleTheme}
            title={`Switch to ${theme === "light" ? "Dark" : "Light"} theme`}
          >
            {theme === "light" ? <Moon size={14} /> : <Sun size={14} />}
            <span>{theme === "light" ? "Dark Theme" : "Light Theme"}</span>
          </button>
        </div>
      )}

      <div className="login-split-wrapper">
        {/* Left: Brand Panel (Reference 1 & 2) */}
        <div className="login-brand-panel">
          <div className="login-brand-top">
            <div className="brand-mark">
              <ShieldCheck size={24} />
            </div>
            <div className="brand-copy">
              <strong>Atlas Enterprise</strong>
              <span>Grounded Knowledge Portal</span>
            </div>
          </div>

          <div className="login-hero-copy">
            <div className="eyebrow" style={{ marginBottom: "12px" }}>
              <Sparkles size={14} /> NEXT-GEN ENTERPRISE INTELLIGENCE
            </div>
            <h1 className="login-editorial-headline">
              Ask your company's knowledge, <br />
              <em>get answers</em> you can <span className="accent-word">trust</span>
            </h1>
            <p className="login-sub-line">
              Vector-grounded AI search, citations directly verified against your source documents,
              strict hierarchical role governance, and WhatsApp multi-channel collaboration.
            </p>
          </div>

          {/* Frosted Glass Stat Pill (Reference 1) */}
          <div className="glass-stat-pill">
            <div className="stat-pill-item">
              <span className="stat-pill-val">100%</span>
              <span className="stat-pill-label">Cited Answers</span>
            </div>
            <div className="stat-pill-sep" />
            <div className="stat-pill-item">
              <span className="stat-pill-val">Role-Based</span>
              <span className="stat-pill-label">Access Control</span>
            </div>
            <div className="stat-pill-sep" />
            <div className="stat-pill-item">
              <span className="stat-pill-val">WhatsApp</span>
              <span className="stat-pill-label">Multi-Device</span>
            </div>
          </div>
        </div>

        {/* Right: Glass Login Card */}
        <div className="login-form-panel">
          <div className="form-header">
            <div className="form-header-badge">
              <Lock size={13} />
              <span>SECURE ACCESS</span>
            </div>
            <h2>Sign In to Account</h2>
            <p>Access your organization’s grounded knowledge workspace.</p>
          </div>

          {error && (
            <div className="alert-banner error animated-fade-in">
              <AlertCircle size={18} />
              <div className="alert-content">
                <strong>Authentication Failed: </strong>
                <span>{error}</span>
              </div>
            </div>
          )}

          <form onSubmit={handleLogin} className="login-form">
            <div className="form-field">
              <label htmlFor="login-email">Registered Email Address</label>
              <input
                id="login-email"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="name@company.com"
                autoComplete="email"
                className="input"
              />
            </div>

            <div className="form-field">
              <div className="field-label-row">
                <label htmlFor="login-password">Password</label>
                <button
                  type="button"
                  className="link-btn"
                  onClick={() => {
                    setForgotEmail(email);
                    setForgotError("");
                    setForgotMessage("");
                    setShowForgotModal(true);
                  }}
                >
                  Forgot password?
                </button>
              </div>

              <div className="password-input-wrap">
                <input
                  id="login-password"
                  type={showPassword ? "text" : "password"}
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter account password"
                  autoComplete="current-password"
                  className="input"
                />
                <button
                  type="button"
                  className="eye-toggle-btn"
                  onClick={() => setShowPassword(!showPassword)}
                  title={showPassword ? "Hide password" : "Show password"}
                  aria-label={showPassword ? "Hide password" : "Show password"}
                >
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
            </div>

            {/* Quick Demo Pre-fill helpers */}
            <div style={{ display: "flex", gap: "6px", alignItems: "center", flexWrap: "wrap", margin: "2px 0 6px" }}>
              <span style={{ fontSize: "11px", color: "var(--text-muted)", fontWeight: "600" }}>DEMO SHORTCUTS:</span>
              <button
                type="button"
                className="chip-btn"
                style={{ padding: "3px 9px", fontSize: "11px" }}
                onClick={() => fillCredentials("admin@example.com", "AdminPass123!")}
              >
                Admin (Rank 1)
              </button>
              <button
                type="button"
                className="chip-btn"
                style={{ padding: "3px 9px", fontSize: "11px" }}
                onClick={() => fillCredentials("manager@example.com", "ManagerPass123!")}
              >
                Manager (Rank 3)
              </button>
              <button
                type="button"
                className="chip-btn"
                style={{ padding: "3px 9px", fontSize: "11px" }}
                onClick={() => fillCredentials("employee@example.com", "EmployeePass123!")}
              >
                Employee (Rank 4)
              </button>
            </div>

            <button type="submit" className="login-submit-btn" disabled={loading}>
              {loading ? (
                <>
                  <div className="spinner-dot" />
                  <span>Authenticating Credentials…</span>
                </>
              ) : (
                <>
                  <span>Sign In to Workspace</span>
                  <ArrowRight size={18} />
                </>
              )}
            </button>

            <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: "6px", color: "var(--text-muted)", fontSize: "12px", marginTop: "12px" }}>
              <Lock size={12} />
              <span>Protected by OAuth2 & JWT session encryption</span>
            </div>
          </form>
        </div>
      </div>

      {/* Forgot Password Modal */}
      {showForgotModal && (
        <div className="modal-overlay" onClick={() => setShowForgotModal(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div className="modal-icon">
                <KeyRound size={22} />
              </div>
              <div>
                <h3>Reset Account Password</h3>
                <p>Verify your registered email address below.</p>
              </div>
            </div>

            <form onSubmit={handleForgotPassword} className="modal-body">
              {forgotError && (
                <div className="alert-banner error">
                  <AlertCircle size={16} />
                  <span>{forgotError}</span>
                </div>
              )}

              {forgotMessage && (
                <div className="alert-banner success">
                  <CheckCircle2 size={16} />
                  <span>{forgotMessage}</span>
                </div>
              )}

              <div className="form-field">
                <label>Registered Work Email</label>
                <input
                  type="email"
                  required
                  value={forgotEmail}
                  onChange={(e) => setForgotEmail(e.target.value)}
                  placeholder="user@example.com"
                  className="input"
                />
              </div>

              <div className="modal-actions">
                <button
                  type="button"
                  className="btn-secondary"
                  onClick={() => setShowForgotModal(false)}
                >
                  Close
                </button>
                <button type="submit" className="btn-primary" disabled={forgotLoading}>
                  {forgotLoading ? "Checking DB..." : "Submit Reset Request"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </main>
  );
}
