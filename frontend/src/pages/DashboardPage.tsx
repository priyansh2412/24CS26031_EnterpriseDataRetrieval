import { FileText, MessageSquare, ShieldCheck, Users, Sparkles, BarChart3, Activity, ArrowRight, Building2 } from "lucide-react";

interface User {
  id: string | number;
  email: string;
  role: string;
  role_key?: string;
  rank_level?: number;
}

interface DashboardPageProps {
  user: User | null;
  onNavigate: (path: string) => void;
}

export default function DashboardPage({ user, onNavigate }: DashboardPageProps) {
  const userRank = user?.rank_level ?? 5;
  const isAdmin = user?.role === "admin" || userRank === 1;

  return (
    <div className="dashboard-page">
      {/* Authorized Modules Grid */}
      <div className="dash-section-title">
        <h3>Authorized Workspace Modules</h3>
      </div>

      <div className="dash-modules-grid">
        {/* Module 1: AI Search Assistant (Both Admin & Employees) */}
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

        {/* Modules for Ranks other than 1 (Rank 2, 3, etc.) */}
        {!isAdmin && (
          <>
            <div className="dash-module-card" onClick={() => onNavigate("/teams")}>
              <div className="module-icon icon-purple">
                <Users size={22} />
              </div>
              <div className="module-info">
                <h4>Team Workspaces</h4>
                <p>Collaborate with team members and share project knowledge sessions.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>

            <div className="dash-module-card" onClick={() => onNavigate("/profile")}>
              <div className="module-icon icon-emerald">
                <ShieldCheck size={22} />
              </div>
              <div className="module-info">
                <h4>My Profile</h4>
                <p>View your employee account details, current rank level, and security settings.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>
          </>
        )}

        {/* Modules strictly for Rank 1 (Admin) */}
        {isAdmin && (
          <>
            <div className="dash-module-card" onClick={() => onNavigate("/documents")}>
              <div className="module-icon icon-indigo">
                <FileText size={22} />
              </div>
              <div className="module-info">
                <h4>Knowledge Library</h4>
                <p>Access indexed enterprise files, connect Drive sources, and manage role access.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>

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
