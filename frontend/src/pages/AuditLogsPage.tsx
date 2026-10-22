import React, { useEffect, useState } from "react";
import {
  Activity,
  RefreshCw,
  ShieldAlert,
  Filter,
  Calendar,
  AlertTriangle,
  Info,
  AlertOctagon,
  Shield,
  Smartphone,
  Globe,
  ChevronDown,
  ChevronRight,
  Copy,
  Check,
  X,
  FileText,
  Search,
} from "lucide-react";
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

  // Expandable detail state
  const [expandedLogId, setExpandedLogId] = useState<string | number | null>(null);
  const [copiedLogId, setCopiedLogId] = useState<string | number | null>(null);

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
      (log.detail && log.detail.toLowerCase().includes(term)) ||
      (log.resource_type && log.resource_type.toLowerCase().includes(term))
    );
  });

  const toggleRow = (id: string | number) => {
    setExpandedLogId(prev => (prev === id ? null : id));
  };

  const copyDetail = (id: string | number, text: string) => {
    navigator.clipboard.writeText(text);
    setCopiedLogId(id);
    setTimeout(() => setCopiedLogId(null), 2000);
  };

  const getSeverityBadge = (sev: string) => {
    switch (sev) {
      case "CRITICAL":
        return (
          <span className="sev-badge critical">
            <AlertOctagon size={12} /> CRITICAL
          </span>
        );
      case "ERROR":
        return (
          <span className="sev-badge error">
            <AlertTriangle size={12} /> ERROR
          </span>
        );
      case "WARNING":
        return (
          <span className="sev-badge warning">
            <AlertTriangle size={12} /> WARNING
          </span>
        );
      default:
        return (
          <span className="sev-badge info">
            <Info size={12} /> INFO
          </span>
        );
    }
  };

  return (
    <div className="audit-page animate-fade-in">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <Activity size={14} /> SECURITY & HIERARCHICAL AUDIT LOGS
          </div>
          <h1>Hierarchical Access Audit Trail</h1>
          <p className="subheading">
            Audit logs are restricted to your rank authority level. You can watch event logs of{" "}
            <strong>succeeding (lower-level / subordinate)</strong> role users and system activities.
          </p>
        </div>
        <button
          className="btn-pill btn-secondary"
          onClick={loadLogsAndSubordinates}
          disabled={loading}
          title="Refresh audit trail"
        >
          <RefreshCw size={15} className={loading ? "spin" : ""} />
          <span>Refresh Trail</span>
        </button>
      </header>

      {error && (
        <div className="alert-banner error" style={{ marginBottom: "20px" }}>
          <AlertOctagon size={16} />
          <span>{error}</span>
          <button
            type="button"
            onClick={() => setError("")}
            style={{ marginLeft: "auto", background: "none", border: "none", cursor: "pointer", color: "inherit" }}
          >
            <X size={14} />
          </button>
        </div>
      )}

      {/* Multi-Filter Bar with Glass Styling */}
      <div className="audit-filter-bar margin-bottom">
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
          <div style={{ position: "relative", display: "flex", alignItems: "center" }}>
            <Search
              size={15}
              style={{ position: "absolute", left: "12px", color: "var(--text-muted)", pointerEvents: "none" }}
            />
            <input
              type="text"
              placeholder="Search action, details, user or resource..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              style={{ width: "100%", paddingLeft: "36px" }}
            />
            {searchTerm && (
              <button
                type="button"
                onClick={() => setSearchTerm("")}
                style={{
                  position: "absolute",
                  right: "10px",
                  background: "none",
                  border: "none",
                  color: "var(--text-muted)",
                  cursor: "pointer",
                }}
              >
                <X size={14} />
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Table Card Container with Sticky Header */}
      <div className="table-card">
        <div className="table-header">
          <div className="table-title">
            <ShieldAlert size={18} style={{ color: "var(--palette-sky)" }} />
            <h3>Hierarchical Event Trail ({filteredLogs.length} Records)</h3>
          </div>
          {searchTerm && (
            <span style={{ fontSize: "12.5px", color: "var(--text-muted)" }}>
              Filtered by: “{searchTerm}”
            </span>
          )}
        </div>

        <div className="table-scroll-container">
          <table className="enterprise-table">
            <thead>
              <tr>
                <th style={{ width: "36px" }}></th>
                <th style={{ minWidth: "160px" }}>Timestamp</th>
                <th style={{ minWidth: "110px" }}>Channel</th>
                <th style={{ minWidth: "110px" }}>Severity</th>
                <th style={{ minWidth: "200px" }}>User & Role Rank</th>
                <th style={{ minWidth: "130px" }}>Action</th>
                <th style={{ minWidth: "120px" }}>Resource</th>
                <th>Audit Detail</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                // Skeletons when loading
                Array.from({ length: 6 }).map((_, idx) => (
                  <tr key={`skel-${idx}`}>
                    <td><div className="skeleton" style={{ width: "16px", height: "16px", borderRadius: "4px" }} /></td>
                    <td><div className="skeleton" style={{ width: "130px", height: "16px", borderRadius: "4px" }} /></td>
                    <td><div className="skeleton" style={{ width: "70px", height: "16px", borderRadius: "10px" }} /></td>
                    <td><div className="skeleton" style={{ width: "65px", height: "16px", borderRadius: "10px" }} /></td>
                    <td><div className="skeleton" style={{ width: "160px", height: "16px", borderRadius: "4px" }} /></td>
                    <td><div className="skeleton" style={{ width: "90px", height: "16px", borderRadius: "4px" }} /></td>
                    <td><div className="skeleton" style={{ width: "80px", height: "16px", borderRadius: "4px" }} /></td>
                    <td><div className="skeleton" style={{ width: "220px", height: "16px", borderRadius: "4px" }} /></td>
                  </tr>
                ))
              ) : filteredLogs.length === 0 ? (
                <tr>
                  <td colSpan={8} style={{ padding: "48px 24px" }}>
                    <div className="empty-state" style={{ margin: "0 auto", maxWidth: "420px" }}>
                      <ShieldAlert size={36} style={{ color: "var(--text-muted)", marginBottom: "8px" }} />
                      <h4 style={{ margin: "0 0 4px", fontSize: "16px", color: "var(--text)" }}>
                        No Matching Audit Logs
                      </h4>
                      <p style={{ margin: 0, fontSize: "13px", color: "var(--text-muted)" }}>
                        {searchTerm || selectedSeverity !== "ALL" || selectedUser
                          ? "No audit records match your currently selected filters."
                          : "No event activity recorded for your subordinate access level yet."}
                      </p>
                    </div>
                  </td>
                </tr>
              ) : (
                filteredLogs.map((log) => {
                  const isExpanded = expandedLogId === log.id;
                  const isCopied = copiedLogId === log.id;
                  const detailString = log.detail || `Resource ID: ${log.resource_id || "N/A"}`;

                  return (
                    <React.Fragment key={log.id}>
                      <tr
                        className={`audit-expandable-row ${isExpanded ? "row-expanded" : ""}`}
                        onClick={() => toggleRow(log.id)}
                        title="Click to toggle full log metadata"
                      >
                        <td style={{ textAlign: "center", color: "var(--text-muted)" }}>
                          {isExpanded ? <ChevronDown size={15} /> : <ChevronRight size={15} />}
                        </td>
                        <td>
                          <div className="time-cell">
                            <Calendar size={13} />
                            <span>{new Date(log.created_at).toLocaleString()}</span>
                          </div>
                        </td>
                        <td>
                          <span className={`channel-badge ${log.channel === "whatsapp" ? "whatsapp" : "web"}`}>
                            {log.channel === "whatsapp" ? (
                              <>
                                <Smartphone size={12} /> WhatsApp
                              </>
                            ) : (
                              <>
                                <Globe size={12} /> Web
                              </>
                            )}
                          </span>
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
                          <span className="action-badge">{log.action}</span>
                        </td>
                        <td>
                          <span className="resource-tag">{log.resource_type}</span>
                        </td>
                        <td>
                          <span className="detail-text" title={detailString}>
                            {detailString}
                          </span>
                        </td>
                      </tr>

                      {/* Expandable Detail Panel */}
                      {isExpanded && (
                        <tr className="audit-expanded-row">
                          <td colSpan={8} style={{ padding: 0 }}>
                            <div className="audit-expanded-panel animate-fade-in">
                              <div className="audit-expanded-grid">
                                <div className="audit-expanded-item">
                                  <span className="audit-expanded-label">Log Record ID</span>
                                  <span className="audit-expanded-val font-mono">{log.id}</span>
                                </div>
                                <div className="audit-expanded-item">
                                  <span className="audit-expanded-label">Actor User ID</span>
                                  <span className="audit-expanded-val font-mono">{log.user_id ?? "N/A (System)"}</span>
                                </div>
                                <div className="audit-expanded-item">
                                  <span className="audit-expanded-label">Resource Type & ID</span>
                                  <span className="audit-expanded-val font-mono">
                                    {log.resource_type} / {log.resource_id ?? "None"}
                                  </span>
                                </div>
                                <div className="audit-expanded-item">
                                  <span className="audit-expanded-label">Channel Ingress</span>
                                  <span className="audit-expanded-val">
                                    {log.channel ? log.channel.toUpperCase() : "WEB APPLICATION"}
                                  </span>
                                </div>
                              </div>

                              <div style={{ marginTop: "12px", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "var(--radius-md)", padding: "12px 16px" }}>
                                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "6px" }}>
                                  <span className="audit-expanded-label">Raw Audit Event Payload</span>
                                  <button
                                    type="button"
                                    className="btn-pill btn-secondary"
                                    style={{ padding: "3px 10px", fontSize: "11.5px" }}
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      copyDetail(log.id, detailString);
                                    }}
                                  >
                                    {isCopied ? <Check size={12} className="text-emerald-500" /> : <Copy size={12} />}
                                    <span>{isCopied ? "Copied Payload" : "Copy Payload"}</span>
                                  </button>
                                </div>
                                <div style={{ fontFamily: "monospace", fontSize: "12.5px", color: "var(--text)", whiteSpace: "pre-wrap", wordBreak: "break-all", background: "var(--bg-subtle)", padding: "8px 12px", borderRadius: "6px" }}>
                                  {detailString}
                                </div>
                              </div>
                            </div>
                          </td>
                        </tr>
                      )}
                    </React.Fragment>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
