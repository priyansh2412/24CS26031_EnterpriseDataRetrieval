import { useEffect, useState } from "react";
import { Activity, RefreshCw, ShieldAlert, Filter, Calendar } from "lucide-react";
import { request } from "../api";

interface AuditLog {
  id: number;
  user_id: number | null;
  user_email: string;
  action: string;
  resource_type: string;
  resource_id: string | null;
  detail: string | null;
  created_at: string;
}

export default function AuditLogsPage() {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [filterAction, setFilterAction] = useState("");

  const loadLogs = async () => {
    setLoading(true);
    setError("");
    try {
      const data = await request<AuditLog[]>("/api/audit-logs");
      setLogs(data);
    } catch (err) {
      setError((err as Error).message || "Failed to load audit logs");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadLogs();
  }, []);

  const filteredLogs = logs.filter((log) => {
    if (!filterAction) return true;
    return log.action.toLowerCase().includes(filterAction.toLowerCase()) || log.user_email.toLowerCase().includes(filterAction.toLowerCase());
  });

  return (
    <div className="audit-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <Activity size={14} /> SECURITY & SYSTEM AUDIT
          </div>
          <h1>Access Audit Log</h1>
          <p className="subheading">
            Historical audit trail of user access, document ingestion, query executions, and role changes.
          </p>
        </div>
        <button className="btn-secondary" onClick={loadLogs}>
          <RefreshCw size={15} /> Refresh Logs
        </button>
      </header>

      {error && <div className="alert-banner error margin-bottom">{error}</div>}

      <div className="table-card">
        <div className="table-header">
          <div className="table-title">
            <ShieldAlert size={18} />
            <h3>Security Event Trail ({filteredLogs.length})</h3>
          </div>
          <div className="table-filter">
            <Filter size={15} />
            <input
              type="text"
              placeholder="Filter by user or action..."
              value={filterAction}
              onChange={(e) => setFilterAction(e.target.value)}
            />
          </div>
        </div>

        {loading ? (
          <div className="table-loading">Loading audit records…</div>
        ) : (
          <table className="enterprise-table">
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>User Account</th>
                <th>Action Performed</th>
                <th>Resource Type</th>
                <th>Details</th>
              </tr>
            </thead>
            <tbody>
              {filteredLogs.map((log) => (
                <tr key={log.id}>
                  <td>
                    <div className="time-cell">
                      <Calendar size={13} />
                      <span>{new Date(log.created_at).toLocaleString()}</span>
                    </div>
                  </td>
                  <td>
                    <strong className="user-email-text">{log.user_email}</strong>
                  </td>
                  <td>
                    <span className={`action-badge ${log.action}`}>{log.action}</span>
                  </td>
                  <td>
                    <span className="resource-tag">{log.resource_type}</span>
                  </td>
                  <td>
                    <span className="detail-text">{log.detail || `Resource ID: ${log.resource_id || "N/A"}`}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
