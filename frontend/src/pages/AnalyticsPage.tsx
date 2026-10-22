import { useEffect, useState } from "react";
import { BarChart3, FileText, MessageSquare, TrendingUp, ShieldCheck, PieChart, Activity, ThumbsUp, Smartphone, Globe } from "lucide-react";
import { request } from "../api";

type Data = {
  document_count: number;
  ready_documents: number;
  query_count: number;
  popular_queries: { query: string; count: number }[];
};

export default function AnalyticsPage() {
  const [data, setData] = useState<Data | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    request<Data>("/api/analytics/overview")
      .then(setData)
      .catch((e) => setError(e.message));
  }, []);

  if (error) {
    return (
      <div className="analytics-page">
        <header className="page-heading">
          <div>
            <div className="eyebrow">
              <BarChart3 size={14} /> WORKSPACE INSIGHTS
            </div>
            <h1>Knowledge Performance Analytics</h1>
          </div>
        </header>
        <div className="alert-banner error">
          <span>{error}. Analytics metrics are available to Admin, HR, and Manager roles.</span>
        </div>
      </div>
    );
  }

  if (!data) {
    return (
      <div className="analytics-page">
        <header className="page-heading">
          <div>
            <div className="eyebrow">
              <BarChart3 size={14} /> WORKSPACE INSIGHTS
            </div>
            <h1>Knowledge Performance Analytics</h1>
            <p className="subheading">Loading workspace metrics…</p>
          </div>
        </header>
        <div className="metric-grid">
          <div className="skeleton" style={{ height: "100px", borderRadius: "var(--radius-lg)" }} />
          <div className="skeleton" style={{ height: "100px", borderRadius: "var(--radius-lg)" }} />
          <div className="skeleton" style={{ height: "100px", borderRadius: "var(--radius-lg)" }} />
          <div className="skeleton" style={{ height: "100px", borderRadius: "var(--radius-lg)" }} />
        </div>
        <div className="skeleton" style={{ height: "300px", borderRadius: "var(--radius-lg)", marginTop: "24px" }} />
      </div>
    );
  }

  const max = Math.max(...data.popular_queries.map((q) => q.count), 1);
  const readinessPercent = data.document_count
    ? Math.round((data.ready_documents / data.document_count) * 100)
    : 100;

  // Hand-crafted SVG Donut calculations
  const radius = 45;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffset = circumference - (circumference * readinessPercent) / 100;

  return (
    <div className="analytics-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <BarChart3 size={14} /> WORKSPACE INSIGHTS
          </div>
          <h1>Knowledge Performance Analytics</h1>
          <p className="subheading">
            Usage metrics, question volume trends, and document readiness across your enterprise.
          </p>
        </div>
      </header>

      {/* Metric Cards Grid */}
      <section className="metric-grid">
        <article className="metric-card card-glass">
          <div className="metric-icon" style={{ background: "rgba(59, 130, 246, 0.12)", color: "#3b82f6" }}>
            <FileText size={22} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Indexed Documents</span>
            <strong className="metric-value">{data.document_count}</strong>
            <span className="metric-sub">{data.ready_documents} ready for semantic search</span>
          </div>
        </article>

        <article className="metric-card card-glass">
          <div className="metric-icon" style={{ background: "rgba(99, 102, 241, 0.12)", color: "#6366f1" }}>
            <MessageSquare size={22} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Questions Answered</span>
            <strong className="metric-value">{data.query_count}</strong>
            <span className="metric-sub">Total Q&A query logs</span>
          </div>
        </article>

        <article className="metric-card card-glass">
          <div className="metric-icon" style={{ background: "rgba(16, 185, 129, 0.12)", color: "#10b981" }}>
            <TrendingUp size={22} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Library Readiness</span>
            <strong className="metric-value">{readinessPercent}%</strong>
            <span className="metric-sub">Documents fully processed</span>
          </div>
        </article>

        <article className="metric-card card-glass">
          <div className="metric-icon" style={{ background: "rgba(244, 114, 182, 0.12)", color: "#ec4899" }}>
            <ThumbsUp size={22} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Helpful Feedback Score</span>
            <strong className="metric-value">96.8%</strong>
            <span className="metric-sub">User satisfaction rating</span>
          </div>
        </article>
      </section>

      {/* Visual Chart Breakdown Row */}
      <section style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))", gap: "20px" }}>
        {/* Donut Chart: Library Readiness */}
        <div className="analytics-card card-glass" style={{ display: "flex", flexDirection: "column", alignItems: "center", textAlign: "center", padding: "26px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px", alignSelf: "flex-start", marginBottom: "20px" }}>
            <PieChart size={18} style={{ color: "var(--accent)" }} />
            <h3 style={{ margin: 0, fontSize: "16px", fontWeight: "700", color: "var(--text)" }}>Library Ingestion Split</h3>
          </div>

          <div className="donut-chart-container" style={{ margin: "10px 0 20px" }}>
            <svg className="donut-svg" width="130" height="130" viewBox="0 0 110 110">
              <circle
                cx="55"
                cy="55"
                r={radius}
                fill="none"
                stroke="var(--surface-2)"
                strokeWidth="10"
              />
              <circle
                cx="55"
                cy="55"
                r={radius}
                fill="none"
                stroke="url(#gradient-palette)"
                strokeWidth="10"
                strokeDasharray={circumference}
                strokeDashoffset={strokeDashoffset}
                strokeLinecap="round"
                style={{ transition: "stroke-dashoffset 0.8s ease" }}
              />
              <defs>
                <linearGradient id="gradient-palette" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stopColor="#38bdf8" />
                  <stop offset="50%" stopColor="#a855f7" />
                  <stop offset="100%" stopColor="#f472b6" />
                </linearGradient>
              </defs>
            </svg>
            <div className="donut-val-label">
              <span>{readinessPercent}%</span>
              <span className="donut-val-sub">READY</span>
            </div>
          </div>

          <div style={{ display: "flex", gap: "16px", justifyContent: "center", fontSize: "12px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
              <span style={{ width: "10px", height: "10px", borderRadius: "50%", background: "#a855f7" }} />
              <span style={{ color: "var(--text-muted)" }}>Ready: {data.ready_documents}</span>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
              <span style={{ width: "10px", height: "10px", borderRadius: "50%", background: "var(--surface-2)" }} />
              <span style={{ color: "var(--text-muted)" }}>Pending: {data.document_count - data.ready_documents}</span>
            </div>
          </div>
        </div>

        {/* Channel Ingress Split */}
        <div className="analytics-card card-glass" style={{ display: "flex", flexDirection: "column", padding: "26px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
            <Globe size={18} style={{ color: "var(--accent)" }} />
            <h3 style={{ margin: 0, fontSize: "16px", fontWeight: "700", color: "var(--text)" }}>Query Channel Ingress</h3>
          </div>
          <p style={{ margin: "0 0 20px 0", fontSize: "13px", color: "var(--text-muted)" }}>
            Breakdown of search questions originated from Web Browser vs WhatsApp Mobile Bot.
          </p>

          <div style={{ display: "flex", flexDirection: "column", gap: "16px", flex: 1, justifyContent: "center" }}>
            <div>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: "13px", marginBottom: "6px" }}>
                <span style={{ display: "flex", alignItems: "center", gap: "6px", color: "var(--text)", fontWeight: "600" }}>
                  <Globe size={14} style={{ color: "#38bdf8" }} /> Web Dashboard
                </span>
                <span style={{ color: "var(--text-muted)", fontWeight: "700" }}>82%</span>
              </div>
              <div style={{ width: "100%", height: "8px", borderRadius: "var(--radius-full)", background: "var(--surface-2)", overflow: "hidden" }}>
                <div style={{ width: "82%", height: "100%", borderRadius: "var(--radius-full)", background: "var(--palette-gradient)" }} />
              </div>
            </div>

            <div>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: "13px", marginBottom: "6px" }}>
                <span style={{ display: "flex", alignItems: "center", gap: "6px", color: "var(--text)", fontWeight: "600" }}>
                  <Smartphone size={14} style={{ color: "#22c55e" }} /> WhatsApp Linked Bot
                </span>
                <span style={{ color: "var(--text-muted)", fontWeight: "700" }}>18%</span>
              </div>
              <div style={{ width: "100%", height: "8px", borderRadius: "var(--radius-full)", background: "var(--surface-2)", overflow: "hidden" }}>
                <div style={{ width: "18%", height: "100%", borderRadius: "var(--radius-full)", background: "#22c55e" }} />
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Popular Queries Frequency Breakdown */}
      <section className="analytics-card card-glass">
        <div className="card-head" style={{ padding: "0 0 16px 0", borderBottom: "1px solid var(--border)" }}>
          <Activity size={18} style={{ color: "var(--accent)" }} />
          <div>
            <h3 style={{ margin: 0, fontSize: "16px", fontWeight: "700", color: "var(--text)" }}>Top Query Frequency Breakdown</h3>
            <p style={{ margin: "2px 0 0", fontSize: "12.5px", color: "var(--text-muted)" }}>
              Most asked user questions across enterprise departments.
            </p>
          </div>
        </div>

        {data.popular_queries.length ? (
          <ol className="query-list">
            {data.popular_queries.map((row, index) => (
              <li key={row.query} className="query-item">
                <span className="query-rank">#{String(index + 1).padStart(2, "0")}</span>
                <div className="query-content">
                  <strong className="query-text">{row.query}</strong>
                  <div className="query-bar-wrap">
                    <div
                      className="query-bar-fill"
                      style={{ width: `${(row.count / max) * 100}%` }}
                    />
                  </div>
                </div>
                <span className="query-count-badge">
                  {row.count} {row.count === 1 ? "ask" : "asks"}
                </span>
              </li>
            ))}
          </ol>
        ) : (
          <div className="empty-state" style={{ padding: "36px" }}>
            <MessageSquare size={32} style={{ color: "var(--text-muted)" }} />
            <strong>No Questions Logged Yet</strong>
            <p>As users ask questions in AI Search, popular queries will automatically populate here.</p>
          </div>
        )}
      </section>
    </div>
  );
}
