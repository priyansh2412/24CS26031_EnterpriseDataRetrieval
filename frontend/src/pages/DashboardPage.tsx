import { FileText, MessageSquare, ShieldCheck, Users, Sparkles, BarChart3, Activity, ArrowRight, Building2 } from "lucide-react";

interface User {
  id: string | number;
  email: string;
  role: string;
}

interface DashboardPageProps {
  user: User | null;
  onNavigate: (path: string) => void;
}

export default function DashboardPage({ user, onNavigate }: DashboardPageProps) {
  const roleName = (user?.role || "employee").toUpperCase();

  const isRole = (roles: string[]) => roles.includes(user?.role || "employee");

  return (
    <div className="dashboard-page">
      {/* Authorized Modules Grid */}
      <div className="dash-section-title">
        <h3>Authorized Workspace Modules</h3>
      </div>

      <div className="dash-modules-grid">
        <div className="dash-module-card" onClick={() => onNavigate("/chat")}>
          <div className="module-icon icon-blue">
            <MessageSquare size={22} />
          </div>
          <div className="module-info">
            <h4>AI Search Assistant</h4>
            <p>Interactive RAG search with grounded citations directly below answers.</p>
          </div>
          <ArrowRight size={16} className="card-arrow" />
        </div>

        <div className="dash-module-card" onClick={() => onNavigate("/documents")}>
          <div className="module-icon icon-indigo">
            <FileText size={22} />
          </div>
          <div className="module-info">
            <h4>Knowledge Library</h4>
            <p>Access indexed enterprise files, manage role access, and generate summaries.</p>
          </div>
          <ArrowRight size={16} className="card-arrow" />
        </div>

        {isRole(["admin", "hr", "manager", "finance"]) && (
          <div className="dash-module-card" onClick={() => onNavigate("/analytics")}>
            <div className="module-icon icon-amber">
              <BarChart3 size={22} />
            </div>
            <div className="module-info">
              <h4>Usage & Insights</h4>
              <p>Monitor document readiness, question volume, and search activity.</p>
            </div>
            <ArrowRight size={16} className="card-arrow" />
          </div>
        )}

        {isRole(["admin"]) && (
          <>
            <div className="dash-module-card" onClick={() => onNavigate("/users")}>
              <div className="module-icon icon-purple">
                <Users size={22} />
              </div>
              <div className="module-info">
                <h4>User Management</h4>
                <p>Manage database accounts, assign roles, and toggle user access.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>

            <div className="dash-module-card" onClick={() => onNavigate("/audit-logs")}>
              <div className="module-icon icon-rose">
                <Activity size={22} />
              </div>
              <div className="module-info">
                <h4>Security Audit Trail</h4>
                <p>Track access requests, document modifications, and security logs.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>
          </>
        )}
      </div>
    </div>
  );
}
