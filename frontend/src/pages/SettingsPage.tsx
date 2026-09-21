import { Settings, Shield, Server, CheckCircle, Info } from "lucide-react";

interface User {
  id: number;
  email: string;
  role: string;
}

export default function SettingsPage({ user }: { user: User | null }) {
  return (
    <div className="settings-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <Settings size={14} /> SYSTEM CONFIGURATION
          </div>
          <h1>Workspace Settings</h1>
          <p className="subheading">
            Environment specifications, system status, and user session parameters.
          </p>
        </div>
      </header>

      <div className="settings-grid">
        {/* User Profile Card */}
        <section className="settings-card">
          <div className="card-head">
            <Shield size={18} />
            <h3>User Account & Active Session</h3>
          </div>
          <div className="card-body">
            <div className="info-row">
              <span className="info-label">Account Email</span>
              <strong className="info-val">{user?.email || "admin@example.com"}</strong>
            </div>
            <div className="info-row">
              <span className="info-label">Assigned Role</span>
              <span className={`role-badge ${user?.role || "admin"}`}>
                {(user?.role || "admin").toUpperCase()}
              </span>
            </div>
            <div className="info-row">
              <span className="info-label">Authentication Token</span>
              <span className="status-pill active">
                <CheckCircle size={12} /> JWT Active (24 Hours)
              </span>
            </div>
          </div>
        </section>

        {/* Backend & DB System Status */}
        <section className="settings-card">
          <div className="card-head">
            <Server size={18} />
            <h3>Backend Infrastructure</h3>
          </div>
          <div className="card-body">
            <div className="info-row">
              <span className="info-label">API Base URL</span>
              <strong className="info-val">http://localhost:8000</strong>
            </div>
            <div className="info-row">
              <span className="info-label">Database Driver</span>
              <strong className="info-val">SQLite (rag.db)</strong>
            </div>
            <div className="info-row">
              <span className="info-label">Vector Store</span>
              <strong className="info-val">ChromaDB / FAISS Embeddings</strong>
            </div>
          </div>
        </section>

        {/* Role Privileges Overview */}
        <section className="settings-card full-width">
          <div className="card-head">
            <Info size={18} />
            <h3>Role Privilege Hierarchy</h3>
          </div>
          <div className="card-body">
            <div className="privilege-grid">
              <div className="privilege-box">
                <span className="role-dot admin" />
                <strong>ADMIN</strong>
                <p>Full system rights: AI Search, Knowledge Library, Analytics, User Management, Audit Logs.</p>
              </div>
              <div className="privilege-box">
                <span className="role-dot hr" />
                <strong>HR MANAGER</strong>
                <p>Access to AI Search, Knowledge Library, Analytics & Settings.</p>
              </div>
              <div className="privilege-box">
                <span className="role-dot manager" />
                <strong>MANAGER / FINANCE</strong>
                <p>Access to AI Search, Knowledge Library, Analytics & Settings.</p>
              </div>
              <div className="privilege-box">
                <span className="role-dot employee" />
                <strong>EMPLOYEE</strong>
                <p>Access to AI Search, permitted Documents, & Settings.</p>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
