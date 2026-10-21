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
} from "lucide-react";
import { forgotPassword, login } from "../api";

interface LoginPageProps {
  onSuccess: () => void;
}

export default function LoginPage({ onSuccess }: LoginPageProps) {
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

  return (
    <main className="login-container">
      {/* Decorative ambient background mesh */}
      <div className="ambient-mesh-glow" />

      <div className="login-card-wrapper single-panel">
        {/* Login Form Panel */}
        <div className="login-form-panel">
          <div className="brand-header" style={{ marginBottom: "24px", justifyContent: "center" }}>
            <div className="brand-badge glow-effect">
              <ShieldCheck size={26} />
            </div>
            <div className="brand-title">
              <strong>Atlas Enterprise</strong>
              <span>Grounded Knowledge Portal</span>
            </div>
          </div>

          <form onSubmit={handleLogin} className="login-form">
            <div className="form-header">
              <div className="form-header-badge">
                <Lock size={16} />
                <span>SECURE AUTHENTICATION</span>
              </div>
              <h2>Sign In to Account</h2>
              <p>Only pre-existing accounts in database are authorized.</p>
            </div>

            {error && (
              <div className="alert-banner error animated-fade-in">
                <AlertCircle size={18} />
                <div className="alert-content">
                  <strong>Authentication Failed</strong>
                  <span>{error}</span>
                </div>
              </div>
            )}

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

            <button type="submit" className="login-submit-btn" disabled={loading}>
              {loading ? (
                <div className="btn-spinner-wrap">
                  <span className="spinner-dot" />
                  <span>Authenticating Credentials…</span>
                </div>
              ) : (
                <>
                  <span>Sign In to Workspace</span>
                  <ArrowRight size={18} />
                </>
              )}
            </button>

            <div className="security-notice">
              <Lock size={13} />
              <span>Protected by OAuth2 & JWT session encryption</span>
            </div>
          </form>
        </div>
      </div>

      {/* Forgot Password Modal */}
      {showForgotModal && (
        <div className="modal-overlay" onClick={() => setShowForgotModal(false)}>
          <div className="modal-content animated-scale-up" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div className="modal-icon glow-icon">
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
