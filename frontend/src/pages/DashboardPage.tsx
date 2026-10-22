import { useState, useEffect } from "react";
import {
  FileText,
  MessageSquare,
  ShieldCheck,
  Users,
  Sparkles,
  BarChart3,
  Activity,
  ArrowRight,
  TrendingUp,
  Search,
  CheckCircle2,
  Layers,
  Building2,
  FolderKanban,
  MessageCircle,
} from "lucide-react";
import { request } from "../api";

interface User {
  id: string | number;
  email: string;
  role: string;
  role_key?: string;
  rank_level?: number;
  enterprise_name?: string;
}

interface DashboardPageProps {
  user: User | null;
  onNavigate: (path: string) => void;
}

interface AnalyticsOverview {
  document_count: number;
  ready_documents: number;
  query_count: number;
  popular_queries: { query: string; count: number }[];
}

export default function DashboardPage({ user, onNavigate }: DashboardPageProps) {
  const [analyticsData, setAnalyticsData] = useState<AnalyticsOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [quickQuery, setQuickQuery] = useState("");

  const userRank = user?.rank_level ?? 5;
  const userRole = user?.role_key || user?.role || "employee";
  const isAdmin = user?.role === "admin" || userRank === 1;
  const username = user?.email?.split("@")[0] || "Team Member";

  useEffect(() => {
    // Attempt to load analytics overview for stats (admin/managers or general)
    request<AnalyticsOverview>("/api/analytics/overview")
      .then((data) => {
        setAnalyticsData(data);
      })
      .catch(() => {
        setAnalyticsData(null);
      })
      .finally(() => {
        setLoading(false);
      });
  }, []);

  const handleQuickAsk = (e: React.FormEvent) => {
    e.preventDefault();
    if (!quickQuery.trim()) {
      onNavigate("/chat");
      return;
    }
    // Store quick query so ChatPage can immediately pick it up
    sessionStorage.setItem("atlas_quick_ask", quickQuery.trim());
    onNavigate("/chat");
  };

  const handleSelectQuery = (q: string) => {
    sessionStorage.setItem("atlas_quick_ask", q);
    onNavigate("/chat");
  };

  const readinessPercent = analyticsData?.document_count
    ? Math.round((analyticsData.ready_documents / analyticsData.document_count) * 100)
    : 100;

  const maxQueryCount = analyticsData?.popular_queries?.length
    ? Math.max(...analyticsData.popular_queries.map((q) => q.count), 1)
    : 1;

  return (
    <div className="dashboard-page animate-fade-in">
      {/* 1. Greeting Hero Banner & Quick Ask */}
      <section className="dash-hero-banner">
        <div className="dash-hero-top">
          <div className="dash-hero-title">
            <div className="eyebrow">
              <Sparkles size={14} /> KNOWLEDGE WORKSPACE
            </div>
            <h2>Welcome back, {username} 👋</h2>
            <p>
              Your enterprise repository is active with verified vector embeddings and rank-based access control.
            </p>
          </div>

          <div style={{ display: "flex", gap: "10px", alignItems: "center" }}>
            <span className="role-badge" style={{ padding: "6px 14px", fontSize: "12px" }}>
              <ShieldCheck size={14} style={{ marginRight: "4px" }} />
              Rank {userRank}: {userRole.toUpperCase()}
            </span>
          </div>
        </div>

        {/* Quick Ask Search Input Bar */}
        <form onSubmit={handleQuickAsk} className="dash-quick-ask">
          <Search size={18} style={{ color: "var(--text-muted)", marginRight: "4px" }} />
          <input
            type="text"
            placeholder="Ask Atlas AI anything across all indexed enterprise documents..."
            value={quickQuery}
            onChange={(e) => setQuickQuery(e.target.value)}
          />
          <button type="submit" className="dash-quick-ask-btn">
            <span>Ask AI</span>
            <ArrowRight size={15} />
          </button>
        </form>
      </section>

      {/* 2. Stat Cards Grid */}
      <section className="dash-stats-grid">
        {loading ? (
          <>
            <div className="stat-card skeleton" style={{ height: "96px" }} />
            <div className="stat-card skeleton" style={{ height: "96px" }} />
            <div className="stat-card skeleton" style={{ height: "96px" }} />
            <div className="stat-card skeleton" style={{ height: "96px" }} />
          </>
        ) : (
          <>
            <div className="stat-card" onClick={() => isAdmin && onNavigate("/documents")} style={{ cursor: isAdmin ? "pointer" : "default" }}>
              <div className="stat-card-icon blue">
                <FileText size={22} />
              </div>
              <div className="stat-card-info">
                <span className="stat-card-val">{analyticsData ? analyticsData.document_count : "—"}</span>
                <span className="stat-card-label">Indexed Documents</span>
              </div>
            </div>

            <div className="stat-card" onClick={() => onNavigate("/chat")} style={{ cursor: "pointer" }}>
              <div className="stat-card-icon indigo">
                <MessageSquare size={22} />
              </div>
              <div className="stat-card-info">
                <span className="stat-card-val">{analyticsData ? analyticsData.query_count : "0"}</span>
                <span className="stat-card-label">Questions Answered</span>
              </div>
            </div>

            <div className="stat-card">
              <div className="stat-card-icon emerald">
                <TrendingUp size={22} />
              </div>
              <div className="stat-card-info">
                <span className="stat-card-val">{analyticsData ? `${readinessPercent}%` : "100%"}</span>
                <span className="stat-card-label">Knowledge Readiness</span>
              </div>
            </div>

            <div className="stat-card" onClick={() => onNavigate("/profile")} style={{ cursor: "pointer" }}>
              <div className="stat-card-icon amber">
                <ShieldCheck size={22} />
              </div>
              <div className="stat-card-info">
                <span className="stat-card-val">Rank {userRank}</span>
                <span className="stat-card-label">{user?.enterprise_name || "Enterprise Workspace"}</span>
              </div>
            </div>
          </>
        )}
      </section>

      {/* 3. Middle Split: Handcrafted Activity Chart & Popular Queries */}
      <section className="dash-middle-split">
        {/* Hand-built SVG Activity Chart */}
        <div className="dash-panel-card">
          <div className="dash-panel-head">
            <h3>
              <Activity size={18} style={{ color: "var(--accent)" }} />
              Query Volume & Knowledge Activity
            </h3>
            <span className="badge badge-accent">Live Telemetry</span>
          </div>

          <div className="dash-chart-container">
            {analyticsData?.popular_queries && analyticsData.popular_queries.length > 0 ? (
              <div style={{ display: "flex", flexDirection: "column", gap: "10px", width: "100%" }}>
                {/* Handcrafted Inline SVG Bar Chart */}
                <svg className="handcrafted-svg-chart" viewBox="0 0 500 160">
                  <defs>
                    <linearGradient id="barGradient" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#4f46e5" stopOpacity="0.9" />
                      <stop offset="100%" stopColor="#3b82f6" stopOpacity="0.4" />
                    </linearGradient>
                    <linearGradient id="lineGrad" x1="0" y1="0" x2="1" y2="0">
                      <stop offset="0%" stopColor="#818cf8" />
                      <stop offset="100%" stopColor="#06b6d4" />
                    </linearGradient>
                  </defs>

                  {/* Horizontal Gridlines */}
                  <line x1="30" y1="20" x2="480" y2="20" stroke="var(--border)" strokeDasharray="3 3" />
                  <line x1="30" y1="70" x2="480" y2="70" stroke="var(--border)" strokeDasharray="3 3" />
                  <line x1="30" y1="120" x2="480" y2="120" stroke="var(--border)" />

                  {/* Dynamic SVG Bars based on real queries */}
                  {analyticsData.popular_queries.slice(0, 5).map((q, idx) => {
                    const barWidth = 44;
                    const spacing = 90;
                    const x = 50 + idx * spacing;
                    const barHeight = Math.max(16, (q.count / maxQueryCount) * 90);
                    const y = 120 - barHeight;

                    return (
                      <g key={q.query + idx}>
                        <rect
                          x={x}
                          y={y}
                          width={barWidth}
                          height={barHeight}
                          rx={6}
                          fill="url(#barGradient)"
                          style={{ transition: "all 0.3s ease" }}
                        />
                        <text
                          x={x + barWidth / 2}
                          y={y - 6}
                          textAnchor="middle"
                          fill="var(--text)"
                          fontSize="11"
                          fontWeight="700"
                        >
                          {q.count}
                        </text>
                        <text
                          x={x + barWidth / 2}
                          y={138}
                          textAnchor="middle"
                          fill="var(--text-muted)"
                          fontSize="10"
                        >
                          Q{idx + 1}
                        </text>
                      </g>
                    );
                  })}
                </svg>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: "12px", color: "var(--text-muted)" }}>
                  <span>Aggregated query trends by frequency</span>
                  <span>Top {Math.min(5, analyticsData.popular_queries.length)} Questions</span>
                </div>
              </div>
            ) : (
              <div className="empty-state" style={{ padding: "30px" }}>
                <Activity size={32} />
                <strong>No Query Activity Recorded Yet</strong>
                <p>Telemetry trends will automatically populate as questions are asked in AI Search.</p>
              </div>
            )}
          </div>
        </div>

        {/* Top / Recent User Queries */}
        <div className="dash-panel-card">
          <div className="dash-panel-head">
            <h3>
              <Sparkles size={17} style={{ color: "var(--accent)" }} />
              Top Questions Across Teams
            </h3>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: "8px", flex: 1 }}>
            {analyticsData?.popular_queries && analyticsData.popular_queries.length > 0 ? (
              analyticsData.popular_queries.slice(0, 4).map((q, idx) => (
                <div
                  key={idx}
                  onClick={() => handleSelectQuery(q.query)}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "10px 14px",
                    borderRadius: "var(--radius-md)",
                    background: "var(--surface-2)",
                    border: "1px solid var(--border)",
                    cursor: "pointer",
                    transition: "all 0.18s ease",
                  }}
                  className="card-interactive"
                >
                  <div style={{ display: "flex", alignItems: "center", gap: "10px", minWidth: 0 }}>
                    <span style={{ fontSize: "11px", fontWeight: "700", color: "var(--accent)" }}>
                      #{idx + 1}
                    </span>
                    <span style={{ fontSize: "13px", fontWeight: "500", color: "var(--text)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                      {q.query}
                    </span>
                  </div>
                  <span className="badge badge-accent" style={{ flexShrink: 0, fontSize: "10.5px" }}>
                    {q.count} {q.count === 1 ? "ask" : "asks"}
                  </span>
                </div>
              ))
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                {[
                  "What is our annual paid leave policy?",
                  "What are remote work security guidelines?",
                  "What learning stipends are provided?",
                ].map((sample, idx) => (
                  <div
                    key={idx}
                    onClick={() => handleSelectQuery(sample)}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "space-between",
                      padding: "10px 14px",
                      borderRadius: "var(--radius-md)",
                      background: "var(--surface-2)",
                      border: "1px solid var(--border)",
                      cursor: "pointer",
                    }}
                    className="card-interactive"
                  >
                    <span style={{ fontSize: "13px", color: "var(--text)" }}>{sample}</span>
                    <ArrowRight size={14} style={{ color: "var(--accent)" }} />
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </section>

      {/* 4. Authorized Workspace Modules Grid */}
      <div className="dash-section-title">
        <h3>Authorized Workspace Modules</h3>
      </div>

      <div className="dash-modules-grid">
        {/* Module 1: AI Search Assistant (All Users) */}
        <div className="dash-module-card" onClick={() => onNavigate("/chat")}>
          <div className="module-icon icon-blue">
            <MessageSquare size={22} />
          </div>
          <div className="module-info">
            <h4>AI Search Sessions</h4>
            <p>Interactive RAG search with grounded citations directly verified from your files.</p>
          </div>
          <ArrowRight size={16} className="card-arrow" />
        </div>

        {/* Module 2: WhatsApp Integration (All Users) */}
        <div className="dash-module-card" onClick={() => onNavigate("/linked-devices")}>
          <div className="module-icon icon-green">
            <MessageCircle size={22} />
          </div>
          <div className="module-info">
            <h4>Linked WhatsApp Devices</h4>
            <p>Connect your WhatsApp to query your enterprise knowledge base directly on mobile.</p>
          </div>
          <ArrowRight size={16} className="card-arrow" />
        </div>

        {/* Modules for Non-Admin Ranks */}
        {!isAdmin && (
          <>
            <div className="dash-module-card" onClick={() => onNavigate("/teams")}>
              <div className="module-icon icon-purple">
                <FolderKanban size={22} />
              </div>
              <div className="module-info">
                <h4>Team Workspaces</h4>
                <p>Collaborate with team members, discuss tasks, and share project knowledge sessions.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>

            <div className="dash-module-card" onClick={() => onNavigate("/profile")}>
              <div className="module-icon icon-emerald">
                <ShieldCheck size={22} />
              </div>
              <div className="module-info">
                <h4>My Profile</h4>
                <p>Review employee identity, rank authority level, and manage login credentials.</p>
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
                <p>Connect Drive links, browse folder trees, and set fine-grained role ACLs.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>

            <div className="dash-module-card" onClick={() => onNavigate("/analytics")}>
              <div className="module-icon icon-amber">
                <BarChart3 size={22} />
              </div>
              <div className="module-info">
                <h4>Usage & Insights</h4>
                <p>Monitor document readiness, question volume, and team query frequency trends.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>

            <div className="dash-module-card" onClick={() => onNavigate("/users")}>
              <div className="module-icon icon-purple">
                <Users size={22} />
              </div>
              <div className="module-info">
                <h4>User Governance</h4>
                <p>Manage accounts, assign company roles, and configure hierarchy permissions.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>

            <div className="dash-module-card" onClick={() => onNavigate("/audit-logs")}>
              <div className="module-icon icon-rose">
                <Activity size={22} />
              </div>
              <div className="module-info">
                <h4>Security Audit Trail</h4>
                <p>Review hierarchical events, document access requests, and channel logs.</p>
              </div>
              <ArrowRight size={16} className="card-arrow" />
            </div>
          </>
        )}
      </div>
    </div>
  );
}
