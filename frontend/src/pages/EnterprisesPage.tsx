import React, { useEffect, useState } from "react";
import {
  Building2,
  Plus,
  ShieldCheck,
  Key,
  Copy,
  Check,
  Eye,
  EyeOff,
  RefreshCw,
  Search,
  AlertCircle,
  CheckCircle2,
  XCircle,
  Trash2,
  UserCheck,
  Activity,
  Layers,
} from "lucide-react";
import { EnterpriseCreatePayload, EnterpriseItem, UserProfile, request } from "../api";

interface EnterprisesPageProps {
  currentUser?: UserProfile | null;
}

export default function EnterprisesPage({ currentUser }: EnterprisesPageProps) {
  const [enterprises, setEnterprises] = useState<EnterpriseItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [error, setError] = useState("");
  const [successMessage, setSuccessMessage] = useState("");

  // Add Enterprise Modal State
  const [showAddModal, setShowAddModal] = useState(false);
  const [enterpriseName, setEnterpriseName] = useState("");
  const [adminEmail, setAdminEmail] = useState("");
  const [tempPassword, setTempPassword] = useState("");
  const [showTempPass, setShowTempPass] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [copiedId, setCopiedId] = useState<number | null>(null);
  const [copiedModalPass, setCopiedModalPass] = useState(false);
  const [visiblePasswords, setVisiblePasswords] = useState<Record<number, boolean>>({});

  const generateRandomPassword = () => {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*";
    let pwd = "EntPass#";
    for (let i = 0; i < 6; i++) {
      pwd += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    pwd += "!";
    setTempPassword(pwd);
  };

  const loadEnterprises = async () => {
    setLoading(true);
    setError("");
    try {
      const data = await request<EnterpriseItem[]>("/api/enterprises");
      setEnterprises(data);
    } catch (err) {
      setError((err as Error).message || "Failed to load enterprises");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadEnterprises();
  }, []);

  const handleOpenModal = () => {
    setEnterpriseName("");
    setAdminEmail("");
    generateRandomPassword();
    setShowTempPass(true);
    setShowAddModal(true);
    setError("");
    setSuccessMessage("");
  };

  const handleCreateEnterprise = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!enterpriseName.trim() || !adminEmail.trim()) {
      setError("Please fill in Enterprise Name and Admin Email.");
      return;
    }

    setSubmitting(true);
    setError("");
    setSuccessMessage("");

    try {
      const payload: EnterpriseCreatePayload = {
        enterprise_name: enterpriseName.trim(),
        admin_email: adminEmail.trim(),
        temp_password: tempPassword.trim(),
      };

      const created = await request<EnterpriseItem>("/api/enterprises", {
        method: "POST",
        body: JSON.stringify(payload),
      });

      setEnterprises([created, ...enterprises]);
      setSuccessMessage(
        `Successfully connected ${created.enterprise_name}! Admin credentials provisioned for ${created.admin_email}.`
      );
      setShowAddModal(false);
    } catch (err) {
      setError((err as Error).message || "Failed to create enterprise");
    } finally {
      setSubmitting(false);
    }
  };

  const handleToggleStatus = async (item: EnterpriseItem) => {
    setError("");
    setSuccessMessage("");
    const newStatus = !item.is_active;

    try {
      const updated = await request<EnterpriseItem>(`/api/enterprises/${item.id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ is_active: newStatus }),
      });

      setEnterprises((prev) =>
        prev.map((e) => (e.id === item.id ? updated : e))
      );

      setSuccessMessage(
        `Enterprise '${item.enterprise_name}' is now ${newStatus ? "Active (Login Enabled)" : "Deactivated (Login Disabled)"}.`
      );
    } catch (err) {
      setError((err as Error).message || "Failed to update status");
    }
  };

  const handleDelete = async (item: EnterpriseItem) => {
    if (!confirm(`Are you sure you want to delete enterprise '${item.enterprise_name}'? This will deactivate the admin account.`)) {
      return;
    }

    try {
      await request(`/api/enterprises/${item.id}`, { method: "DELETE" });
      setEnterprises((prev) => prev.filter((e) => e.id !== item.id));
      setSuccessMessage(`Enterprise '${item.enterprise_name}' has been deleted.`);
    } catch (err) {
      setError((err as Error).message || "Failed to delete enterprise");
    }
  };

  const copyToClipboard = (text: string, id: number) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const togglePasswordVisibility = (id: number) => {
    setVisiblePasswords((prev) => ({
      ...prev,
      [id]: !prev[id],
    }));
  };

  const filteredEnterprises = enterprises.filter((e) => {
    const q = searchQuery.toLowerCase();
    return (
      e.enterprise_name.toLowerCase().includes(q) ||
      e.admin_email.toLowerCase().includes(q) ||
      e.tenant_id.toLowerCase().includes(q)
    );
  });

  const totalCount = enterprises.length;
  const activeCount = enterprises.filter((e) => e.is_active).length;
  const inactiveCount = totalCount - activeCount;

  return (
    <div className="users-page">
      {/* Header */}
      <header className="page-heading">
        <div className="flex justify-between items-start w-full">
          <div>
            <div className="eyebrow">
              <Building2 size={14} /> ENTERPRISE TENANT MANAGEMENT
            </div>
            <h1>Connected Enterprises</h1>
            <p className="subheading">
              Manage connected enterprise portals, provision admin credentials, and toggle real-time account activation.
            </p>
          </div>
          <button className="btn-primary" onClick={handleOpenModal}>
            <Plus size={16} /> Add Connected Enterprise
          </button>
        </div>
      </header>

      {/* Stats Cards */}
      <div className="analytics-kpi-grid" style={{ marginBottom: "1.5rem" }}>
        <div className="kpi-card">
          <div className="kpi-label">TOTAL ENTERPRISES</div>
          <div className="kpi-value">{totalCount}</div>
          <div className="kpi-meta">Connected Client Organizations</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">ACTIVE PORTALS</div>
          <div className="kpi-value text-emerald-400">{activeCount}</div>
          <div className="kpi-meta">Admins Logged In & Operational</div>
        </div>
        <div className="kpi-card">
          <div className="kpi-label">DEACTIVATED</div>
          <div className="kpi-value text-amber-400">{inactiveCount}</div>
          <div className="kpi-meta">Access Suspended</div>
        </div>
      </div>

      {/* Alerts */}
      {error && (
        <div className="alert-banner error" style={{ marginBottom: "1rem" }}>
          <AlertCircle size={16} />
          <span>{error}</span>
        </div>
      )}
      {successMessage && (
        <div className="alert-banner success" style={{ marginBottom: "1rem" }}>
          <CheckCircle2 size={16} />
          <span>{successMessage}</span>
        </div>
      )}

      {/* Action Search Bar */}
      <div className="table-controls" style={{ marginBottom: "1rem" }}>
        <div className="search-box">
          <Search size={16} />
          <input
            type="text"
            placeholder="Search enterprise by name, admin email, or tenant..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
        <button className="btn-secondary" onClick={loadEnterprises} title="Refresh list">
          <RefreshCw size={14} /> Refresh
        </button>
      </div>

      {/* Enterprises Table */}
      <div className="table-card">
        {loading ? (
          <div className="loading-state">
            <RefreshCw className="spin" size={24} />
            <span>Loading enterprise directory...</span>
          </div>
        ) : filteredEnterprises.length === 0 ? (
          <div className="empty-state">
            <Building2 size={36} />
            <p>No connected enterprises found.</p>
            <button className="btn-primary" onClick={handleOpenModal}>
              <Plus size={14} /> Add First Enterprise
            </button>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>ENTERPRISE NAME</th>
                <th>ADMIN EMAIL</th>
                <th>TEMP PASSWORD</th>
                <th>TENANT ID</th>
                <th>CONNECTED DATE</th>
                <th>STATUS & ACCESS</th>
                <th>ACTIONS</th>
              </tr>
            </thead>
            <tbody>
              {filteredEnterprises.map((item) => {
                const isPassVisible = Boolean(visiblePasswords[item.id]);
                const isCopied = copiedId === item.id;

                return (
                  <tr key={item.id} className={!item.is_active ? "opacity-60" : ""}>
                    <td>
                      <div className="user-email-cell">
                        <div className="user-avatar bg-indigo-600 text-white">
                          <Building2 size={14} />
                        </div>
                        <div>
                          <strong>{item.enterprise_name}</strong>
                        </div>
                      </div>
                    </td>
                    <td>
                      <div className="flex items-center gap-1 text-sm font-medium">
                        <UserCheck size={14} className="text-blue-400" />
                        <span>{item.admin_email}</span>
                      </div>
                    </td>
                    <td>
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-xs px-2 py-1 bg-slate-900/60 border border-slate-700/50 rounded text-slate-200">
                          {isPassVisible ? item.temp_password : "••••••••••••"}
                        </span>
                        <button
                          type="button"
                          className="btn-icon text-slate-400 hover:text-slate-200"
                          onClick={() => togglePasswordVisibility(item.id)}
                          title={isPassVisible ? "Hide password" : "Show password"}
                        >
                          {isPassVisible ? <EyeOff size={14} /> : <Eye size={14} />}
                        </button>
                        <button
                          type="button"
                          className="btn-icon text-slate-400 hover:text-emerald-400"
                          onClick={() => copyToClipboard(item.temp_password, item.id)}
                          title="Copy credentials"
                        >
                          {isCopied ? <Check size={14} className="text-emerald-400" /> : <Copy size={14} />}
                        </button>
                      </div>
                    </td>
                    <td>
                      <span className="rank-tag-pill rank-4">
                        <Layers size={12} /> {item.tenant_id}
                      </span>
                    </td>
                    <td>
                      <span className="text-xs text-slate-400">
                        {item.created_at ? new Date(item.created_at).toLocaleDateString() : "—"}
                      </span>
                    </td>
                    <td>
                      <button
                        type="button"
                        onClick={() => handleToggleStatus(item)}
                        className={`status-pill ${item.is_active ? "active hover:bg-rose-500/20 hover:text-rose-400 hover:border-rose-500/40 cursor-pointer" : "inactive hover:bg-emerald-500/20 hover:text-emerald-400 hover:border-emerald-500/40 cursor-pointer"}`}
                        title={item.is_active ? "Click to Deactivate Enterprise" : "Click to Activate Enterprise"}
                      >
                        {item.is_active ? <CheckCircle2 size={12} /> : <XCircle size={12} />}
                        {item.is_active ? "Active (Click to Deactivate)" : "Deactivated (Click to Activate)"}
                      </button>
                    </td>
                    <td>
                      <button
                        type="button"
                        className="btn-link-action text-rose-400 hover:text-rose-300"
                        onClick={() => handleDelete(item)}
                        title="Delete enterprise"
                      >
                        <Trash2 size={14} />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>

      {/* Add Enterprise Modal */}
      {showAddModal && (
        <div className="modal-backdrop">
          <div className="modal-card">
            <div className="modal-header">
              <div className="flex items-center gap-2">
                <Building2 size={20} className="text-indigo-400" />
                <h3>Add Connected Enterprise</h3>
              </div>
              <button
                className="btn-icon"
                onClick={() => setShowAddModal(false)}
                type="button"
              >
                ✕
              </button>
            </div>

            <form onSubmit={handleCreateEnterprise} className="modal-form">
              <div className="form-group">
                <label>Enterprise / Organization Name *</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Apex Global Technologies"
                  value={enterpriseName}
                  onChange={(e) => setEnterpriseName(e.target.value)}
                />
              </div>

              <div className="form-group">
                <label>Enterprise Admin Email *</label>
                <input
                  type="email"
                  required
                  placeholder="e.g. admin@apextech.com"
                  value={adminEmail}
                  onChange={(e) => setAdminEmail(e.target.value)}
                />
                <span className="field-hint">
                  This email will be provisioned with Executive Administrator (Rank 1) permissions.
                </span>
              </div>

              <div className="form-group">
                <label>Temporary Password *</label>
                <div className="flex gap-2">
                  <div className="relative flex-1">
                    <input
                      type={showTempPass ? "text" : "password"}
                      required
                      value={tempPassword}
                      onChange={(e) => setTempPassword(e.target.value)}
                      className="w-full pr-10 font-mono"
                    />
                    <button
                      type="button"
                      className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-200"
                      onClick={() => setShowTempPass(!showTempPass)}
                    >
                      {showTempPass ? <EyeOff size={16} /> : <Eye size={16} />}
                    </button>
                  </div>
                  <button
                    type="button"
                    className="btn-secondary"
                    onClick={generateRandomPassword}
                    title="Generate new secure password"
                  >
                    <RefreshCw size={14} /> New
                  </button>
                  <button
                    type="button"
                    className="btn-secondary"
                    onClick={() => {
                      navigator.clipboard.writeText(tempPassword);
                      setCopiedModalPass(true);
                      setTimeout(() => setCopiedModalPass(false), 2000);
                    }}
                    title="Copy password"
                  >
                    {copiedModalPass ? <Check size={14} className="text-emerald-400" /> : <Copy size={14} />}
                  </button>
                </div>
                <span className="field-hint">
                  Share these credentials securely with the enterprise administrator for their initial login.
                </span>
              </div>

              <div className="modal-actions">
                <button
                  type="button"
                  className="btn-secondary"
                  onClick={() => setShowAddModal(false)}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="btn-primary"
                  disabled={submitting}
                >
                  {submitting ? "Provisioning..." : "Connect & Save Enterprise"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

