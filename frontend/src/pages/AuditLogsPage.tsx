import { useEffect, useState } from "react";
import { Activity, RefreshCw, ShieldAlert, Filter, Calendar, AlertTriangle, Info, AlertOctagon, CheckCircle, Shield } from "lucide-react";
import { AuditLogItem, SubordinateUserItem, request } from "../api";

export default function AuditLogsPage() {
  const [logs, setLogs] = useState<AuditLogItem[]>([]);
  const [subordinates, setSubordinates] = useState<SubordinateUserItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  
  // Filters
  const [selectedUser, setSelectedUser] = useState<string>("");
  const [selectedSeverity, setSelectedSeverity] = useState<string>("ALL");
  const [searchTerm, setSearchTerm] = useState("");

  const loadLogsAndSubordinates = async () => {
    setLoading(true);
    setError("");
    try {
      // Build query string
      const queryParams = new URLSearchParams();
      if (selectedUser) queryParams.append("target_user_id", selectedUser);
      if (selectedSeverity && selectedSeverity !== "ALL") queryParams.append("severity", selectedSeverity);

      const [logData, subData] = await Promise.all([
        request<AuditLogItem[]>(`/api/audit-logs?${queryParams.toString()}`),
        request<SubordinateUserItem[]>("/api/audit-logs/subordinates").catch(() => []),
      ]);

      setLogs(logData);
      setSubordinates(subData);
    } catch (err) {
      setError((err as Error).message || "Failed to load audit logs");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadLogsAndSubordinates();
  }, [selectedUser, selectedSeverity]);

  const filteredLogs = logs.filter((log) => {
    if (!searchTerm) return true;
    const term = searchTerm.toLowerCase();
    return (
      log.action.toLowerCase().includes(term) ||
      (log.user_email && log.user_email.toLowerCase().includes(term)) ||
      (log.detail && log.detail.toLowerCase().includes(term))
    );
  });

  const getSeverityBadge = (sev: string) => {
    switch (sev) {
      case "CRITICAL":
        return <span className="sev-badge critical"><AlertOctagon size={12} /> CRITICAL</span>;
      case "ERROR":
        return <span className="sev-badge error"><AlertTriangle size={12} /> ERROR</span>;
      case "WARNING":
        return <span className="sev-badge warning"><AlertTriangle size={12} /> WARNING</span>;
      default:
        return <span className="sev-badge info"><Info size={12} /> INFO</span>;
    }
  };

  return (
    <div className="audit-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <Activity size={14} /> SECURITY & HIERARCHICAL AUDIT LOGS
          </div>
          <h1>Hierarchical Access Audit Trail</h1>
          <p className="subheading">
            Audit logs are restricted to your rank authority level. You can watch event logs of <strong>succeeding (lower-level / subordinate)</strong> role users and system activities.
          </p>
        </div>
        <button className="btn-secondary" onClick={loadLogsAndSubordinates}>
          <RefreshCw size={15} /> Refresh Audit Trail
        </button>
      </header>

      {error && <div className="alert-banner error margin-bottom">{error}</div>}

      {/* Multi-Filter Bar */}
      <div className="audit-filter-bar card margin-bottom">
        <div className="filter-group">
          <label>Filter Subordinate User:</label>
          <select value={selectedUser} onChange={(e) => setSelectedUser(e.target.value)}>
            <option value="">All Subordinate & Succeeding Users</option>
            {subordinates.map((sub) => (
              <option key={sub.id} value={sub.id}>
                {sub.email} (Rank {sub.rank_level}: {sub.role_key})
              </option>
            ))}
          </select>
        </div>

        <div className="filter-group">
          <label>Event Severity:</label>
          <div className="severity-pills">
            {["ALL", "INFO", "WARNING", "ERROR", "CRITICAL"].map((sev) => (
              <button
                key={sev}
                type="button"
                className={`sev-pill ${selectedSeverity === sev ? "active" : ""} ${sev.toLowerCase()}`}
                onClick={() => setSelectedSeverity(sev)}
              >
                {sev}
              </button>
            ))}
          </div>
        </div>

        <div className="filter-group flex-grow">
          <label>Search Keyword:</label>
          <div className="table-filter">
            <Filter size={14} />
            <input
              type="text"
              placeholder="Search action or details..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </div>
      </div>

      <div className="table-card">
        <div className="table-header">
          <div className="table-title">
            <ShieldAlert size={18} />
            <h3>Hierarchical Event Trail ({filteredLogs.length} Records)</h3>
          </div>
        </div>

        {loading ? (
          <div className="table-loading">Loading hierarchical audit logs…</div>
        ) : (
          <table className="enterprise-table">
            <thead>
              <tr>
                <th>Timestamp</th>
                <th>Severity</th>
                <th>User & Role Rank</th>
                <th>Action</th>
                <th>Resource</th>
                <th>Audit Detail</th>
              </tr>
            </thead>
            <tbody>
              {filteredLogs.length === 0 ? (
                <tr>
                  <td colSpan={6} className="empty-table-cell">
                    No matching audit logs found for your subordinate access level.
                  </td>
                </tr>
              ) : (
                filteredLogs.map((log) => (
                  <tr key={log.id}>
                    <td>
                      <div className="time-cell">
                        <Calendar size={13} />
                        <span>{new Date(log.created_at).toLocaleString()}</span>
                      </div>
                    </td>
                    <td>{getSeverityBadge(log.severity)}</td>
                    <td>
                      <div className="user-rank-cell">
                        <strong className="user-email-text">{log.user_email || "System/Guest"}</strong>
                        {log.user_rank_level !== null && log.user_rank_level > 0 && (
                          <span className="rank-tag" title={`Rank ${log.user_rank_level}`}>
                            <Shield size={11} /> Rank {log.user_rank_level} ({log.user_role_key})
                          </span>
                        )}
                      </div>
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
                ))
              )}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
