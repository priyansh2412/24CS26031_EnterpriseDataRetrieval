import { useEffect, useState } from "react";
import { Users, UserPlus, Shield, CheckCircle, XCircle, AlertCircle, RefreshCw, Lock } from "lucide-react";
import { request } from "../api";

interface UserItem {
  id: number;
  email: string;
  role: string;
  is_active?: boolean;
}

export default function UserManagementPage() {
  const [users, setUsers] = useState<UserItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  // Create User Modal
  const [showAddModal, setShowAddModal] = useState(false);
  const [newEmail, setNewEmail] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newRole, setNewRole] = useState("employee");
  const [creating, setCreating] = useState(false);

  const loadUsers = async () => {
    setLoading(true);
    setError("");
    try {
      const data = await request<UserItem[]>("/api/users");
      setUsers(data);
    } catch (err) {
      setError((err as Error).message || "Failed to load users");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadUsers();
  }, []);

  const handleCreateUser = async (e: React.FormEvent) => {
    e.preventDefault();
    setCreating(true);
    setMessage("");
    setError("");
    try {
      const created = await request<UserItem>("/api/users", {
        method: "POST",
        body: JSON.stringify({ email: newEmail.trim(), password: newPassword, role: newRole }),
      });
      setUsers((prev) => [...prev, created]);
      setMessage(`User ${created.email} created successfully.`);
      setShowAddModal(false);
      setNewEmail("");
      setNewPassword("");
    } catch (err) {
      setError((err as Error).message || "Failed to create user.");
    } finally {
      setCreating(false);
    }
  };

  const handleUpdateRole = async (userId: number, role: string) => {
    try {
      const updated = await request<UserItem>(`/api/users/${userId}`, {
        method: "PATCH",
        body: JSON.stringify({ role }),
      });
      setUsers((prev) => prev.map((u) => (u.id === userId ? updated : u)));
      setMessage(`User ${updated.email} role updated to ${role}.`);
    } catch (err) {
      setError((err as Error).message || "Failed to update user role.");
    }
  };

  const handleToggleStatus = async (userId: number, currentActive: boolean) => {
    try {
      const updated = await request<UserItem>(`/api/users/${userId}`, {
        method: "PATCH",
        body: JSON.stringify({ is_active: !currentActive }),
      });
      setUsers((prev) => prev.map((u) => (u.id === userId ? updated : u)));
      setMessage(`User status updated.`);
    } catch (err) {
      setError((err as Error).message || "Failed to update user status.");
    }
  };

  const roleColors: Record<string, string> = {
    admin: "role-badge admin",
    hr: "role-badge hr",
    manager: "role-badge manager",
    finance: "role-badge finance",
    employee: "role-badge employee",
    user: "role-badge employee",
  };

  return (
    <div className="users-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <Users size={14} /> ADMINISTRATION
          </div>
          <h1>User & Role Management</h1>
          <p className="subheading">
            Control registered accounts in SQLite DB and configure role-based access permissions.
          </p>
        </div>
        <button className="btn-primary" onClick={() => setShowAddModal(true)}>
          <UserPlus size={16} /> Add New DB User
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
            <h3>Registered Database Users ({users.length})</h3>
          </div>
          <button className="btn-icon" onClick={loadUsers} title="Refresh Users">
            <RefreshCw size={15} />
          </button>
        </div>

        {loading ? (
          <div className="table-loading">Loading database users…</div>
        ) : (
          <table className="enterprise-table">
            <thead>
              <tr>
                <th>User ID</th>
                <th>Email Address</th>
                <th>Assigned Role</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.map((u) => (
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
                    <select
                      className={`role-select ${u.role}`}
                      value={u.role}
                      onChange={(e) => handleUpdateRole(u.id, e.target.value)}
                    >
                      <option value="admin">Admin</option>
                      <option value="hr">HR</option>
                      <option value="manager">Manager</option>
                      <option value="finance">Finance</option>
                      <option value="employee">Employee</option>
                    </select>
                  </td>
                  <td>
                    <span className={`status-pill ${u.is_active !== false ? "active" : "inactive"}`}>
                      {u.is_active !== false ? <CheckCircle size={12} /> : <XCircle size={12} />}
                      {u.is_active !== false ? "Active" : "Inactive"}
                    </span>
                  </td>
                  <td>
                    <button
                      className="btn-link-action"
                      onClick={() => handleToggleStatus(u.id, u.is_active !== false)}
                    >
                      {u.is_active !== false ? "Deactivate" : "Activate"}
                    </button>
                  </td>
                </tr>
              ))}
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
                <h3>Add New DB User</h3>
                <p>Create a pre-authorized database account.</p>
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
                  placeholder="newuser@example.com"
                />
              </div>

              <div className="form-field">
                <label>Password</label>
                <input
                  type="password"
                  required
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  placeholder="Minimum 8 characters"
                />
              </div>

              <div className="form-field">
                <label>System Role</label>
                <select value={newRole} onChange={(e) => setNewRole(e.target.value)}>
                  <option value="employee">Employee (Search & View)</option>
                  <option value="hr">HR Manager (HR Portal & Docs)</option>
                  <option value="manager">Department Manager (Analytics & Docs)</option>
                  <option value="finance">Finance Lead (Analytics & Docs)</option>
                  <option value="admin">Administrator (Full Rights)</option>
                </select>
              </div>

              <div className="modal-actions">
                <button type="button" className="btn-secondary" onClick={() => setShowAddModal(false)}>
                  Cancel
                </button>
                <button type="submit" className="btn-primary" disabled={creating}>
                  {creating ? "Creating..." : "Save DB User"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
