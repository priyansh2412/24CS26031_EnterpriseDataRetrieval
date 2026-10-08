import React, { useEffect, useState } from "react";
import { Users, UserPlus, Shield, CheckCircle, XCircle, AlertCircle, RefreshCw, Layers } from "lucide-react";
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
        <button className="btn-primary" onClick={() => setShowAddModal(true)}>
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

      <div className="table-card">
        <div className="table-header">
          <div className="table-title">
            <Shield size={18} />
            <h3>Organization Accounts ({users.length})</h3>
          </div>
          <button className="btn-icon" onClick={loadData} title="Refresh Users">
            <RefreshCw size={15} />
          </button>
        </div>

        {loading ? (
          <div className="table-loading">Loading organization accounts…</div>
        ) : (
          <table className="enterprise-table">
            <thead>
              <tr>
                <th>ID</th>
                <th>Email Address</th>
                <th>Hierarchy Rank Level</th>
                <th>Assigned Role Key</th>
                <th>Status</th>
                <th>Actions</th>
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
                      <span className="mono-id">#{u.id}</span>
                    </td>
                    <td>
                      <div className="user-email-cell">
                        <div className="user-avatar">{u.email[0].toUpperCase()}</div>
                        <strong>{u.email}</strong>
                      </div>
                    </td>
                    <td>
                      <span className={`rank-tag-pill rank-${u.rank_level}`}>
                        <Layers size={12} /> Rank {u.rank_level}
                      </span>
                    </td>
                    <td>
                      {canModify ? (
                        <select
                          className="role-select"
                          value={u.role_key || u.role}
                          onChange={(e) => handleUpdateRole(u.id, e.target.value)}
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
                        <span className="read-only-role">{u.role_key || u.role}</span>
                      )}
                    </td>
                    <td>
                      <span className={`status-pill ${u.is_active !== false ? "active" : "inactive"}`}>
                        {u.is_active !== false ? <CheckCircle size={12} /> : <XCircle size={12} />}
                        {u.is_active !== false ? "Active" : "Deactivated"}
                      </span>
                    </td>
                    <td>
                      {canModify ? (
                        <button
                          className="btn-link-action"
                          onClick={() => handleToggleStatus(u.id, u.is_active !== false)}
                        >
                          {u.is_active !== false ? "Deactivate" : "Activate"}
                        </button>
                      ) : (
                        <span className="muted-text">Higher / Equal Rank</span>
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
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div className="modal-icon">
                <UserPlus size={22} />
              </div>
              <div>
                <h3>Add User Account</h3>
                <p>Assign corporate role hierarchy & login credentials.</p>
              </div>
            </div>

            <form onSubmit={handleCreateUser} className="modal-body">
              <div className="form-field">
                <label>Work Email</label>
                <input
                  type="email"
                  required
                  value={newEmail}
                  onChange={(e) => setNewEmail(e.target.value)}
                  placeholder="user@company.com"
                />
              </div>

              <div className="form-field">
                <label>Initial Password</label>
                <input
                  type="password"
                  required
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  placeholder="Minimum 8 characters"
                />
              </div>

              <div className="form-field">
                <label>Company Role Level</label>
                <select value={newRoleKey} onChange={(e) => setNewRoleKey(e.target.value)}>
                  {companyRoles.map((r) => (
                    <option key={r.key} value={r.key}>
                      Rank {r.rank_level}: {r.name} ({r.description || r.key})
                    </option>
                  ))}
                </select>
              </div>

              <div className="modal-actions">
                <button type="button" className="btn-secondary" onClick={() => setShowAddModal(false)}>
                  Cancel
                </button>
                <button type="submit" className="btn-primary" disabled={creating}>
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
