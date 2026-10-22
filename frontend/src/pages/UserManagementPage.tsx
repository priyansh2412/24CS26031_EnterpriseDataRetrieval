import React, { useEffect, useState } from "react";
import { Users, UserPlus, Shield, CheckCircle, XCircle, AlertCircle, RefreshCw, Layers, X } from "lucide-react";
import { CompanyRoleItem, UserProfile, request } from "../api";

interface UserManagementPageProps {
  currentUser?: UserProfile | null;
}

export default function UserManagementPage({ currentUser }: UserManagementPageProps) {
  const [users, setUsers] = useState<UserProfile[]>([]);
  const [companyRoles, setCompanyRoles] = useState<CompanyRoleItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  // Create User Modal
  const [showAddModal, setShowAddModal] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newRoleKey, setNewRoleKey] = useState("employee");
  const [creating, setCreating] = useState(false);

  const loadData = async () => {
    setLoading(true);
    setError("");
    try {
      const [usersData, rolesData] = await Promise.all([
        request<UserProfile[]>("/api/users"),
        request<CompanyRoleItem[]>("/api/setup/roles").catch(() => []),
      ]);
      setUsers(usersData);
      setCompanyRoles(rolesData);
      if (rolesData.length > 0 && !newRoleKey) {
        setNewRoleKey(rolesData[rolesData.length - 1].key);
      }
    } catch (err) {
      setError((err as Error).message || "Failed to load users");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  // Close modal on Escape
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setShowAddModal(false);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  const handleCreateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setMessage("");
    setError("");

    const targetRole = companyRoles.find((r) => r.key === newRoleKey);
    const assignedRank = targetRole ? targetRole.rank_level : 5;

    // Check rank level constraint
    if (currentUser && currentUser.rank_level > 1 && currentUser.role !== "admin") {
      if (assignedRank <= currentUser.rank_level) {
        setError(`Upper role restriction: You can only create users with a rank level subordinate to your own (Rank > ${currentUser.rank_level}).`);
        setCreating(false);
        return;
      }
    }

    try {
      const created = await request<UserProfile>("/api/users", {
        method: "POST",
        body: JSON.stringify({
          email: newEmail.trim(),
          password: newPassword,
          role_key: newRoleKey,
          rank_level: assignedRank,
        }),
      });
      setUsers((prev) => [...prev, created]);
      setMessage(`User ${created.email} created successfully at Rank ${created.rank_level}.`);
      setShowAddModal(false);
      setNewEmail("");
      setNewPassword("");
    } catch (err) {
      setError((err as Error).message || "Failed to create user.");
    } finally {
      setCreating(false);
    }
  };

  const handleUpdateRole = async (userId: string | number, roleKey: string) => {
    setMessage("");
    setError("");

    const targetRole = companyRoles.find((r) => r.key === roleKey);
    const assignedRank = targetRole ? targetRole.rank_level : 5;

    try {
      const updated = await request<UserProfile>(`/api/users/${userId}`, {
        method: "PATCH",
        body: JSON.stringify({ role_key: roleKey, rank_level: assignedRank }),
      });
      setUsers((prev) => prev.map((u) => (u.id === userId ? updated : u)));
      setMessage(`Updated user ${updated.email} role to ${roleKey} (Rank ${updated.rank_level}).`);
    } catch (err) {
      setError((err as Error).message || "Failed to update user role.");
    }
  };

  const handleToggleStatus = async (userId: string | number, currentActive: boolean) => {
    setMessage("");
    setError("");
    try {
      const updated = await request<UserProfile>(`/api/users/${userId}`, {
        method: "PATCH",
        body: JSON.stringify({ is_active: !currentActive }),
      });
      setUsers((prev) => prev.map((u) => (u.id === userId ? updated : u)));
      setMessage(`User account status updated.`);
    } catch (err) {
      setError((err as Error).message || "Failed to update user status.");
    }
  };

  return (
    <div className="users-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <Users size={14} /> HIERARCHICAL USER GOVERNANCE
          </div>
          <h1>Upper-Role User Management</h1>
          <p className="subheading">
            Upper role authority users can create, modify, and assign team projects to subordinate (succeeding level) users.
          </p>
        </div>
        <button className="btn-primary btn-pill" onClick={() => setShowAddModal(true)}>
          <UserPlus size={16} /> Add Subordinate User
        </button>
      </header>

      {message && (
        <div className="alert-banner success margin-bottom">
          <CheckCircle size={16} />
          <span>{message}</span>
        </div>
      )}

      {error && (
        <div className="alert-banner error margin-bottom">
          <AlertCircle size={16} />
          <span>{error}</span>
        </div>
      )}

      <div className="table-card card-glass" style={{ overflow: "hidden", borderRadius: "var(--radius-xl)" }}>
        <div className="table-header" style={{ padding: "18px 24px", borderBottom: "1px solid var(--border)", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <div className="table-title" style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <Shield size={18} style={{ color: "var(--accent)" }} />
            <h3 style={{ margin: 0, fontSize: "16px", fontWeight: "700", color: "var(--text)" }}>Organization Accounts ({users.length})</h3>
          </div>
          <button className="btn-icon" onClick={loadData} title="Refresh Users">
            <RefreshCw size={15} />
          </button>
        </div>

        {loading ? (
          <div style={{ padding: "24px", display: "flex", flexDirection: "column", gap: "12px" }}>
            <div className="skeleton" style={{ height: "40px", borderRadius: "var(--radius-md)" }} />
            <div className="skeleton" style={{ height: "40px", borderRadius: "var(--radius-md)" }} />
            <div className="skeleton" style={{ height: "40px", borderRadius: "var(--radius-md)" }} />
          </div>
        ) : (
          <table className="enterprise-table">
            <thead>
              <tr>
                <th>ID</th>
                <th>Email Address</th>
                <th>Hierarchy Rank</th>
                <th>Assigned Role</th>
                <th>Status</th>
                <th style={{ textAlign: "right" }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => {
                const canModify =
                  currentUser?.role === "admin" ||
                  currentUser?.rank_level === 1 ||
                  (currentUser?.rank_level && u.rank_level > currentUser.rank_level);

                return (
                  <tr key={u.id}>
                    <td>
                      <span className="mono-id" style={{ color: "var(--text-muted)" }}>#{u.id}</span>
                    </td>
                    <td>
                      <div className="user-email-cell" style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                        <div
                          className="user-avatar"
                          style={{
                            width: "34px",
                            height: "34px",
                            borderRadius: "var(--radius-full)",
                            background: "var(--palette-gradient)",
                            color: "#ffffff",
                            display: "grid",
                            placeItems: "center",
                            fontWeight: "700",
                            fontSize: "13px",
                            flexShrink: 0,
                            boxShadow: "0 2px 6px rgba(99, 102, 241, 0.2)",
                          }}
                        >
                          {u.email[0].toUpperCase()}
                        </div>
                        <div>
                          <strong style={{ color: "var(--text)", fontSize: "13.5px", display: "block" }}>{u.email}</strong>
                          {u.display_name && <span style={{ fontSize: "11px", color: "var(--text-muted)" }}>{u.display_name}</span>}
                        </div>
                      </div>
                    </td>
                    <td>
                      <span className="chip" style={{ fontWeight: "700", fontSize: "11.5px" }}>
                        <Layers size={12} style={{ color: "var(--accent)" }} /> Rank {u.rank_level}
                      </span>
                    </td>
                    <td>
                      {canModify ? (
                        <select
                          className="role-select"
                          value={u.role_key || u.role}
                          onChange={(e) => handleUpdateRole(u.id, e.target.value)}
                          style={{
                            padding: "6px 12px",
                            borderRadius: "var(--radius-full)",
                            border: "1px solid var(--border)",
                            background: "var(--surface)",
                            color: "var(--text)",
                            fontSize: "12.5px",
                            fontWeight: "600",
                            outline: "none",
                          }}
                        >
                          {companyRoles.length > 0 ? (
                            companyRoles.map((r) => (
                              <option key={r.key} value={r.key}>
                                {r.name} (Rank {r.rank_level})
                              </option>
                            ))
                          ) : (
                            <>
                              <option value="admin">Executive Admin (Rank 1)</option>
                              <option value="hr">HR Manager (Rank 2)</option>
                              <option value="manager">Manager (Rank 3)</option>
                              <option value="employee">Employee (Rank 4)</option>
                            </>
                          )}
                        </select>
                      ) : (
                        <span className="chip" style={{ textTransform: "uppercase", fontSize: "11px" }}>{u.role_key || u.role}</span>
                      )}
                    </td>
                    <td>
                      <span className={`status-pill ${u.is_active !== false ? "active" : "inactive"}`}>
                        {u.is_active !== false ? <CheckCircle size={12} /> : <XCircle size={12} />}
                        {u.is_active !== false ? "Active" : "Deactivated"}
                      </span>
                    </td>
                    <td style={{ textAlign: "right" }}>
                      {canModify ? (
                        <button
                          className="btn-pill btn-secondary"
                          onClick={() => handleToggleStatus(u.id, u.is_active !== false)}
                          style={{ padding: "4px 12px", fontSize: "12px" }}
                        >
                          {u.is_active !== false ? "Deactivate" : "Activate"}
                        </button>
                      ) : (
                        <span style={{ fontSize: "12px", color: "var(--text-muted)" }}>Protected</span>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* Add User Modal */}
      {showAddModal && (
        <div className="modal-overlay" onClick={() => setShowAddModal(false)}>
          <div className="modal-content animated-scale-up card-glass" onClick={(e) => e.stopPropagation()} style={{ maxWidth: "520px" }}>
            <header className="modal-header">
              <div className="glow-icon">
                <UserPlus size={20} />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "800", color: "var(--text)" }}>Add User Account</h3>
                <p style={{ margin: "2px 0 0", fontSize: "12px", color: "var(--text-muted)" }}>Assign corporate role hierarchy & login credentials.</p>
              </div>
              <button
                type="button"
                className="close-btn"
                style={{ marginLeft: "auto" }}
                onClick={() => setShowAddModal(false)}
                title="Close"
              >
                <X size={18} />
              </button>
            </header>

            <form onSubmit={handleCreateUser} className="modal-body" style={{ padding: "20px 24px" }}>
              <div className="form-group" style={{ marginBottom: "16px" }}>
                <label style={{ display: "block", fontSize: "12px", fontWeight: "600", color: "var(--text-muted)", marginBottom: "6px" }}>Work Email</label>
                <input
                  type="email"
                  required
                  value={newEmail}
                  onChange={(e) => setNewEmail(e.target.value)}
                  placeholder="user@company.com"
                  style={{
                    width: "100%",
                    padding: "10px 14px",
                    borderRadius: "var(--radius-md)",
                    border: "1px solid var(--border)",
                    background: "var(--surface)",
                    color: "var(--text)",
                    fontSize: "13.5px",
                    outline: "none",
                  }}
                />
              </div>

              <div className="form-group" style={{ marginBottom: "16px" }}>
                <label style={{ display: "block", fontSize: "12px", fontWeight: "600", color: "var(--text-muted)", marginBottom: "6px" }}>Initial Password</label>
                <input
                  type="password"
                  required
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  placeholder="Minimum 8 characters"
                  style={{
                    width: "100%",
                    padding: "10px 14px",
                    borderRadius: "var(--radius-md)",
                    border: "1px solid var(--border)",
                    background: "var(--surface)",
                    color: "var(--text)",
                    fontSize: "13.5px",
                    outline: "none",
                  }}
                />
              </div>

              <div className="form-group" style={{ marginBottom: "20px" }}>
                <label style={{ display: "block", fontSize: "12px", fontWeight: "600", color: "var(--text-muted)", marginBottom: "6px" }}>Company Role Level</label>
                <select
                  value={newRoleKey}
                  onChange={(e) => setNewRoleKey(e.target.value)}
                  style={{
                    width: "100%",
                    padding: "10px 14px",
                    borderRadius: "var(--radius-md)",
                    border: "1px solid var(--border)",
                    background: "var(--surface)",
                    color: "var(--text)",
                    fontSize: "13.5px",
                    outline: "none",
                  }}
                >
                  {companyRoles.map((r) => (
                    <option key={r.key} value={r.key}>
                      Rank {r.rank_level}: {r.name} ({r.description || r.key})
                    </option>
                  ))}
                </select>
              </div>

              <div className="modal-actions" style={{ padding: 0 }}>
                <button type="button" className="btn-outline btn-pill" onClick={() => setShowAddModal(false)}>
                  Cancel
                </button>
                <button type="submit" className="btn-primary btn-pill" disabled={creating}>
                  {creating ? "Creating..." : "Save User Account"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
