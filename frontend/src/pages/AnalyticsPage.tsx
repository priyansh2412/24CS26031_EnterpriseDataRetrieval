import { useEffect, useState } from "react";
import { BarChart3, FileText, MessageSquare, TrendingUp, ShieldCheck, PieChart, Activity } from "lucide-react";
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
    return <div className="table-loading">Loading workspace performance insights…</div>;
  }

  const max = Math.max(...data.popular_queries.map((q) => q.count), 1);
  const readinessPercent = data.document_count
    ? Math.round((data.ready_documents / data.document_count) * 100)
    : 100;

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
        <article className="metric-card">
          <div className="metric-icon icon-blue">
            <FileText size={20} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Indexed Documents</span>
            <strong className="metric-value">{data.document_count}</strong>
            <span className="metric-sub">{data.ready_documents} ready for semantic search</span>
          </div>
        </article>

        <article className="metric-card">
          <div className="metric-icon icon-indigo">
            <MessageSquare size={20} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Questions Answered</span>
            <strong className="metric-value">{data.query_count}</strong>
            <span className="metric-sub">Total Q&A query logs</span>
          </div>
        </article>

        <article className="metric-card">
          <div className="metric-icon icon-emerald">
            <TrendingUp size={20} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Library Readiness</span>
            <strong className="metric-value">{readinessPercent}%</strong>
            <span className="metric-sub">Documents fully processed</span>
          </div>
        </article>
      </section>

      {/* Popular Queries Frequency Breakdown */}
      <section className="analytics-card">
        <div className="card-head">
          <Activity size={18} />
          <div>
            <h3>Top Query Frequency Breakdown</h3>
            <p>Most asked user questions across departments.</p>
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
          <div className="empty-state">
            <MessageSquare size={32} />
            <strong>No Questions Logged Yet</strong>
            <p>As users ask questions in AI Search, popular queries will automatically populate here.</p>
          </div>
        )}
      </section>
    </div>
  );
}
