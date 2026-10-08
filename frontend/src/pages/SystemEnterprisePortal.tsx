import React, { useEffect, useState } from "react";
import {
  Building2,
  ShieldCheck,
  KeyRound,
  Eye,
  EyeOff,
  LogOut,
  Sun,
  Moon,
  AlertCircle,
  Zap,
  ArrowRight,
  Layers,
} from "lucide-react";
import EnterprisesPage from "./EnterprisesPage";
import { UserProfile, login, request, token } from "../api";

interface SystemEnterprisePortalProps {
  theme: "light" | "dark";
  onToggleTheme: () => void;
}

export default function SystemEnterprisePortal({
  theme,
  onToggleTheme,
}: SystemEnterprisePortalProps) {
  const [systemUser, setSystemUser] = useState<UserProfile | null>(null);
  const [checkingAuth, setCheckingAuth] = useState(true);

  // Direct Login Dialog Box State
  const [email, setEmail] = useState("system@gmailexample.com");
  const [password, setPassword] = useState("System123@");
  const [showPassword, setShowPassword] = useState(false);
  const [loginLoading, setLoginLoading] = useState(false);
  const [loginError, setLoginError] = useState("");

  const verifySystemUser = async () => {
    setCheckingAuth(true);
    const currentToken = token();
    if (!currentToken) {
      setSystemUser(null);
      setCheckingAuth(false);
      return;
    }

    try {
      const me = await request<UserProfile>("/api/auth/me");
      if (me.email === "system@gmailexample.com" || me.role === "admin") {
        setSystemUser(me);
      } else {
        setSystemUser(null);
      }
    } catch {
      setSystemUser(null);
    } finally {
      setCheckingAuth(false);
    }
  };

  useEffect(() => {
    verifySystemUser();
  }, []);

  const handleSystemLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoginError("");
    setLoginLoading(true);

    try {
      await login(email.trim(), password);
      const me = await request<UserProfile>("/api/auth/me");
      setSystemUser(me);
    } catch (err) {
      setLoginError((err as Error).message || "Invalid System Super-Admin credentials.");
    } finally {
      setLoginLoading(false);
    }
  };

  const handleLogout = () => {
    localStorage.removeItem("rag_token");
    setSystemUser(null);
    setEmail("system@gmailexample.com");
    setPassword("System123@");
  };

  if (checkingAuth) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-slate-950 text-slate-300">
        <div className="flex flex-col items-center gap-3">
          <Building2 size={32} className="animate-pulse text-indigo-400" />
          <span>Verifying System Gateway Authorization...</span>
        </div>
      </div>
    );
  }

  // 1. If not logged in as system super-admin, show direct dedicated login dialog box
  if (!systemUser) {
    return (
      <main className={`login-container ${theme}-theme`}>
        <div className="ambient-mesh-glow" />

        <div className="login-card-wrapper" style={{ maxWidth: "520px" }}>
          <div className="login-form-panel" style={{ width: "100%", padding: "2.5rem" }}>
            <div className="form-header text-center" style={{ marginBottom: "2rem" }}>
              <div
                className="brand-badge glow-effect"
                style={{
                  margin: "0 auto 1rem auto",
                  width: "56px",
                  height: "56px",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  borderRadius: "16px",
                  background: "linear-gradient(135deg, #4f46e5 0%, #7c3aed 100%)",
                }}
              >
                <Building2 size={30} className="text-white" />
              </div>
              <h2 style={{ fontSize: "1.75rem", fontWeight: 700, color: "var(--text-primary)" }}>
                Enterprise Gateway
              </h2>
              <p style={{ color: "var(--text-secondary)", fontSize: "0.9rem", marginTop: "0.25rem" }}>
                System Super-Admin portal for managing connected client enterprises.
              </p>
            </div>

            {loginError && (
              <div className="alert-banner error" style={{ marginBottom: "1.25rem" }}>
                <AlertCircle size={16} />
                <span>{loginError}</span>
              </div>
            )}

            <form onSubmit={handleSystemLogin} className="login-form">
              <div className="form-group">
                <label>System Admin Email</label>
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="system@gmailexample.com"
                  className="font-mono text-sm"
                />
              </div>

              <div className="form-group">
                <label>Master Password</label>
                <div className="relative">
                  <input
                    type={showPassword ? "text" : "password"}
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="System123@"
                    className="w-full pr-10 font-mono text-sm"
                  />
                  <button
                    type="button"
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200"
                    onClick={() => setShowPassword(!showPassword)}
                  >
                    {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>

              <div
                style={{
                  padding: "0.75rem 1rem",
                  borderRadius: "8px",
                  backgroundColor: "rgba(99, 102, 241, 0.08)",
                  border: "1px solid rgba(99, 102, 241, 0.2)",
                  fontSize: "0.8rem",
                  color: "var(--text-secondary)",
                  marginBottom: "1rem",
                }}
              >
                <strong className="text-indigo-400">Fixed Credentials:</strong>
                <div className="font-mono mt-1 text-xs">
                  Email: <code>system@gmailexample.com</code>
                  <br />
                  Password: <code>System123@</code>
                </div>
              </div>

              <button
                type="submit"
                className="btn-primary w-full justify-center"
                disabled={loginLoading}
                style={{ padding: "0.85rem", fontSize: "1rem" }}
              >
                {loginLoading ? "Authenticating..." : "Authorize & Enter Enterprise Portal"}
                <ArrowRight size={18} />
              </button>
            </form>
          </div>
        </div>
      </main>
    );
  }

  // 2. Once logged in as system super-admin: Display dedicated single-tab dashboard
  return (
    <main className={`app-shell ${theme}-theme`}>
      {/* Dedicated Single-Tab Sidebar */}
      <aside className="sidebar" style={{ width: "260px" }}>
        <div className="sidebar-top">
          <div className="brand-mark bg-indigo-600 text-white">
            <Building2 size={20} />
          </div>
          <div className="brand-copy">
            <strong>System Control</strong>
            <span>Enterprise Gateway</span>
          </div>
        </div>

        <div className="workspace-label">
          <span>PORTAL MODULE</span>
          <i />
        </div>

        {/* ONLY ONE TAB: Connected Enterprises */}
        <nav className="sidebar-nav">
          <button className="nav-item active" style={{ width: "100%" }}>
            <Building2 size={18} />
            <span>Connected Enterprises</span>
          </button>
        </nav>

        <div className="sidebar-bottom">
          <div className="secure-note" style={{ marginBottom: "1rem" }}>
            <ShieldCheck size={14} className="text-indigo-400" />
            <span>Master System Mode Active</span>
          </div>
          <button className="btn-logout" onClick={handleLogout} style={{ width: "100%" }}>
            <LogOut size={16} />
            <span>Exit Portal</span>
          </button>
        </div>
      </aside>

      {/* Main Content Pane */}
      <div className="main-pane">
        {/* Top Header */}
        <header className="top-header">
          <div className="header-breadcrumbs">
            <span className="crumb-app">SYSTEM GATEWAY</span>
            <span className="crumb-sep">/</span>
            <span className="crumb-current">Connected Enterprises</span>
          </div>

          <div className="header-controls">
            <button
              className="btn-theme-toggle"
              onClick={onToggleTheme}
              title={`Switch to ${theme === "light" ? "Dark" : "Light"} theme`}
            >
              {theme === "light" ? <Moon size={15} /> : <Sun size={15} />}
              <span>{theme === "light" ? "Dark Theme" : "Light Theme"}</span>
            </button>

            <div className="top-user-pill">
              <span className="role-badge" style={{ background: "#4f46e5", color: "#fff" }}>
                SUPER-ADMIN
              </span>
              <span className="user-email-tag">{systemUser.email}</span>
            </div>
          </div>
        </header>

        {/* Content Area with Only Connected Enterprises */}
        <section className="app-content">
          <EnterprisesPage currentUser={systemUser} />
        </section>
      </div>
    </main>
  );
}

