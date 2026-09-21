import { useState } from "react";
import {
  ShieldCheck,
  Eye,
  EyeOff,
  KeyRound,
  ArrowRight,
  CheckCircle2,
  AlertCircle,
  Sparkles,
  UserCheck,
  Lock,
  Zap,
  FileCheck,
  Activity,
  Layers,
} from "lucide-react";
import { forgotPassword, login } from "../api";

interface LoginPageProps {
  onSuccess: () => void;
}

export default function LoginPage({ onSuccess }: LoginPageProps) {
  const [email, setEmail] = useState("admin@example.com");
  const [password, setPassword] = useState("AdminPass123!");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // Forgot Password Modal State
  const [showForgotModal, setShowForgotModal] = useState(false);
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotLoading, setForgotLoading] = useState(false);
  const [forgotMessage, setForgotMessage] = useState("");
  const [forgotError, setForgotError] = useState("");

  const presets = [
    { label: "Admin", email: "admin@example.com", pass: "AdminPass123!", role: "admin", icon: ShieldCheck, desc: "All modules & settings" },
    { label: "HR Manager", email: "hr@example.com", pass: "HrPass123!", role: "hr", icon: UserCheck, desc: "HR Portal & Docs" },
    { label: "Manager", email: "manager@example.com", pass: "ManagerPass123!", role: "manager", icon: Activity, desc: "Analytics & Search" },
    { label: "Employee", email: "employee@example.com", pass: "EmployeePass123!", role: "employee", icon: Layers, desc: "Search & Handbook" },
  ];

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

  const applyPreset = (p: typeof presets[0]) => {
    setEmail(p.email);
    setPassword(p.pass);
    setError("");
  };

  return (
    <main className="login-container">
      {/* Decorative ambient background mesh */}
      <div className="ambient-mesh-glow" />

      <div className="login-card-wrapper">
        {/* Visual Brand Hero Panel */}
        <div className="login-brand-panel">
          <div className="brand-header">
            <div className="brand-badge glow-effect">
              <ShieldCheck size={26} />
            </div>
            <div className="brand-title">
              <strong>Atlas Enterprise</strong>
              <span>Grounded Knowledge Portal</span>
            </div>
          </div>

          <div className="login-hero-copy">
            <div className="hero-tag pulse-tag">
              <Zap size={14} /> GROUNDED DATA RETRIEVAL
            </div>
            <h1>Empowering decision-making with trusted data.</h1>
            <p>
              Access company policies, employee handbooks, and enterprise analytics
              grounded directly on your organization's internal knowledge base.
            </p>

            <div className="hero-feature-list">
              <div className="feature-item">
                <FileCheck size={16} />
                <span>Citation-First AI Search</span>
              </div>
              <div className="feature-item">
                <ShieldCheck size={16} />
                <span>Fine-Grained RBAC Permissions</span>
              </div>
              <div className="feature-item">
                <Activity size={16} />
                <span>Real-Time Security Audit Logs</span>
              </div>
            </div>
          </div>

          <div className="login-preset-box">
            <div className="preset-label">
              <UserCheck size={14} /> SELECT EXISTING DB ACCOUNT FOR QUICK LOGIN
            </div>
            <div className="preset-pills">
              {presets.map((p) => {
                const Icon = p.icon;
                const isActive = email === p.email;
                return (
                  <button
                    key={p.role}
                    type="button"
                    className={`preset-pill ${isActive ? "active" : ""}`}
                    onClick={() => applyPreset(p)}
                  >
                    <Icon size={16} className={`role-icon ${p.role}`} />
                    <div className="preset-text">
                      <strong>{p.label}</strong>
                      <small>{p.desc}</small>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* Login Form Panel */}
        <div className="login-form-panel">
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
