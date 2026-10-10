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
  LayoutGrid,
  Table as TableIcon,
  Calendar,
  Sparkles,
  X,
  ExternalLink,
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
  const [viewMode, setViewMode] = useState<"grid" | "table">("grid");

  // Add Enterprise Modal State
  const [showAddModal, setShowAddModal] = useState(false);
  const [enterpriseName, setEnterpriseName] = useState("");
  const [adminEmail, setAdminEmail] = useState("");
  const [tempPassword, setTempPassword] = useState("");
  const [showTempPass, setShowTempPass] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [copiedId, setCopiedId] = useState<number | null>(null);
  const [copiedTenantId, setCopiedTenantId] = useState<number | null>(null);
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

  const copyTenantId = (text: string, id: number) => {
    navigator.clipboard.writeText(text);
    setCopiedTenantId(id);
    setTimeout(() => setCopiedTenantId(null), 2000);
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
    <div className="ent-page-container">
      {/* Top Banner / Heading Card */}
      <div className="ent-header-card">
        <div className="ent-header-left">
          <div className="ent-eyebrow">
            <Building2 size={14} /> ENTERPRISE TENANT MANAGEMENT
          </div>
          <h1 className="ent-title">Connected Enterprises</h1>
          <p className="ent-subtitle">
            Manage connected enterprise portals, provision admin credentials, and toggle real-time account activation.
          </p>
        </div>
        <button className="btn-primary ent-add-btn" onClick={handleOpenModal}>
          <Plus size={16} /> Add Connected Enterprise
        </button>
      </div>

      {/* KPI Stats in Card Structure */}
      <div className="ent-stats-grid">
        <div className="ent-stat-card card-total">
          <div className="ent-stat-top">
            <span className="ent-stat-label">TOTAL ENTERPRISES</span>
            <div className="ent-stat-icon-wrap icon-blue">
              <Building2 size={20} />
            </div>
          </div>
          <div className="ent-stat-value">{totalCount}</div>
          <div className="ent-stat-meta">
            <span className="ent-dot dot-blue" />
            Connected Client Organizations
          </div>
        </div>

        <div className="ent-stat-card card-active">
          <div className="ent-stat-top">
            <span className="ent-stat-label">ACTIVE PORTALS</span>
            <div className="ent-stat-icon-wrap icon-green">
              <ShieldCheck size={20} />
            </div>
          </div>
          <div className="ent-stat-value text-emerald-500">{activeCount}</div>
          <div className="ent-stat-meta">
            <span className="ent-dot dot-green" />
            Admins Logged In & Operational
          </div>
        </div>

        <div className="ent-stat-card card-inactive">
          <div className="ent-stat-top">
            <span className="ent-stat-label">DEACTIVATED</span>
            <div className="ent-stat-icon-wrap icon-amber">
              <AlertCircle size={20} />
            </div>
          </div>
          <div className="ent-stat-value text-amber-500">{inactiveCount}</div>
          <div className="ent-stat-meta">
            <span className="ent-dot dot-amber" />
            Access Suspended
          </div>
        </div>
      </div>

      {/* Notification Alerts */}
      {error && (
        <div className="alert-banner error" style={{ marginBottom: "1rem" }}>
          <AlertCircle size={16} />
          <span>{error}</span>
          <button type="button" onClick={() => setError("")} style={{ marginLeft: "auto", background: "none", border: "none", cursor: "pointer", color: "inherit" }}>
            <X size={14} />
          </button>
        </div>
      )}
      {successMessage && (
        <div className="alert-banner success" style={{ marginBottom: "1rem" }}>
          <CheckCircle2 size={16} />
          <span>{successMessage}</span>
          <button type="button" onClick={() => setSuccessMessage("")} style={{ marginLeft: "auto", background: "none", border: "none", cursor: "pointer", color: "inherit" }}>
            <X size={14} />
          </button>
        </div>
      )}

      {/* Action Toolbar Card */}
      <div className="ent-toolbar-card">
        <div className="ent-search-wrapper">
          <Search size={16} className="ent-search-icon" />
          <input
            type="text"
            className="ent-search-input"
            placeholder="Search enterprise by name, admin email, or tenant..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
          {searchQuery && (
            <button className="ent-search-clear" onClick={() => setSearchQuery("")}>
              ✕
            </button>
          )}
        </div>

        <div className="ent-toolbar-actions">
          {/* View Mode Toggle: Grid Cards vs Table */}
          <div className="ent-view-toggle">
            <button
              type="button"
              className={`ent-view-btn ${viewMode === "grid" ? "active" : ""}`}
              onClick={() => setViewMode("grid")}
              title="Card Grid View"
            >
              <LayoutGrid size={15} />
              <span>Cards</span>
            </button>
            <button
              type="button"
              className={`ent-view-btn ${viewMode === "table" ? "active" : ""}`}
              onClick={() => setViewMode("table")}
              title="Table View"
            >
              <TableIcon size={15} />
              <span>Table</span>
            </button>
          </div>

          <button className="btn-secondary ent-refresh-btn" onClick={loadEnterprises} title="Refresh directory">
            <RefreshCw size={14} className={loading ? "spin" : ""} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* Content Area: Grid Cards View or Table View */}
      {loading ? (
        <div className="ent-loading-card">
          <RefreshCw className="spin" size={28} />
          <span>Loading connected enterprise directory...</span>
        </div>
      ) : filteredEnterprises.length === 0 ? (
        <div className="ent-empty-card">
          <div className="empty-icon-wrap">
            <Building2 size={36} />
          </div>
          <h3>No connected enterprises found</h3>
          <p>
            {searchQuery
              ? `No enterprises matching "${searchQuery}". Try a different search query.`
              : "Connect client organizations to provision dedicated enterprise tenants."}
          </p>
          <button className="btn-primary" onClick={handleOpenModal}>
            <Plus size={15} /> Add First Enterprise
          </button>
        </div>
      ) : viewMode === "grid" ? (
        /* CARD GRID STRUCTURE */
        <div className="ent-cards-grid">
          {filteredEnterprises.map((item) => {
            const isPassVisible = Boolean(visiblePasswords[item.id]);
            const isCopied = copiedId === item.id;
            const isTenantCopied = copiedTenantId === item.id;

            return (
              <div
                key={item.id}
                className={`ent-company-card ${!item.is_active ? "ent-company-card-deactivated" : ""}`}
              >
                {/* Card Top: Avatar, Name, Status Badge */}
                <div className="ent-card-header">
                  <div className="ent-card-brand">
                    <div className="ent-avatar-badge">
                      <Building2 size={18} />
                    </div>
                    <div className="ent-brand-info">
                      <h3 className="ent-company-name">{item.enterprise_name}</h3>
                      <span className="ent-rank-label">Executive Administrator (Rank 1)</span>
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={() => handleToggleStatus(item)}
                    className={`ent-status-badge ${item.is_active ? "badge-active" : "badge-deactivated"}`}
                    title={item.is_active ? "Click to Deactivate Account" : "Click to Activate Account"}
                  >
                    <span className="status-indicator-dot" />
                    <span>{item.is_active ? "Active" : "Deactivated"}</span>
                  </button>
                </div>

                {/* Card Body: Details in Mini-Cards */}
                <div className="ent-card-body">
                  {/* Admin Email Box */}
                  <div className="ent-detail-box">
                    <span className="ent-detail-label">ADMINISTRATOR EMAIL</span>
                    <div className="ent-detail-content">
                      <UserCheck size={14} className="text-blue-500" />
                      <span className="ent-email-text">{item.admin_email}</span>
                    </div>
                  </div>

                  {/* Temporary Password Box */}
                  <div className="ent-detail-box">
                    <span className="ent-detail-label">PROVISIONED PASSWORD</span>
                    <div className="ent-password-row">
                      <code className="ent-password-pill">
                        {isPassVisible ? item.temp_password : "••••••••••••"}
                      </code>
                      <button
                        type="button"
                        className="ent-icon-btn"
                        onClick={() => togglePasswordVisibility(item.id)}
                        title={isPassVisible ? "Hide password" : "Reveal password"}
                      >
                        {isPassVisible ? <EyeOff size={14} /> : <Eye size={14} />}
                      </button>
                      <button
                        type="button"
                        className={`ent-icon-btn ${isCopied ? "copied" : ""}`}
                        onClick={() => copyToClipboard(item.temp_password, item.id)}
                        title="Copy credentials"
                      >
                        {isCopied ? <Check size={14} className="text-emerald-500" /> : <Copy size={14} />}
                      </button>
                    </div>
                  </div>

                  {/* Tenant ID Box */}
                  <div className="ent-detail-box">
                    <span className="ent-detail-label">TENANT IDENTIFIER</span>
                    <div className="ent-tenant-row">
                      <Layers size={13} className="text-indigo-400" />
                      <code className="ent-tenant-text">{item.tenant_id}</code>
                      <button
                        type="button"
                        className="ent-icon-btn"
                        onClick={() => copyTenantId(item.tenant_id, item.id)}
                        title="Copy Tenant ID"
                      >
                        {isTenantCopied ? <Check size={12} className="text-emerald-500" /> : <Copy size={12} />}
                      </button>
                    </div>
                  </div>

                  {/* Connected Date Box */}
                  <div className="ent-detail-box">
                    <span className="ent-detail-label">CONNECTED SINCE</span>
                    <div className="ent-detail-content">
                      <Calendar size={13} className="text-slate-400" />
                      <span className="ent-date-text">
                        {item.created_at ? new Date(item.created_at).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : "—"}
                      </span>
                    </div>
                  </div>
                </div>

                {/* Card Footer: Action Buttons */}
                <div className="ent-card-footer">
                  <button
                    type="button"
                    onClick={() => handleToggleStatus(item)}
                    className={`ent-toggle-action-btn ${item.is_active ? "btn-deactivate" : "btn-activate"}`}
                  >
                    {item.is_active ? <XCircle size={14} /> : <CheckCircle2 size={14} />}
                    <span>{item.is_active ? "Suspend Access" : "Activate Portal"}</span>
                  </button>

                  <button
                    type="button"
                    className="ent-delete-btn"
                    onClick={() => handleDelete(item)}
                    title="Delete enterprise"
                  >
                    <Trash2 size={15} />
                    <span>Delete</span>
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      ) : (
        /* TABLE CARD STRUCTURE */
        <div className="ent-table-card">
          <table className="data-table ent-data-table">
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
                  <tr key={item.id} className={!item.is_active ? "row-deactivated" : ""}>
                    <td>
                      <div className="user-email-cell">
                        <div className="user-avatar bg-indigo-600 text-white">
                          <Building2 size={14} />
                        </div>
                        <div>
                          <strong className="ent-table-name">{item.enterprise_name}</strong>
                          <div className="text-xs text-slate-400">Rank 1 Admin</div>
                        </div>
                      </div>
                    </td>
                    <td>
                      <div className="flex items-center gap-1.5 text-sm font-medium">
                        <UserCheck size={14} className="text-blue-400" />
                        <span>{item.admin_email}</span>
                      </div>
                    </td>
                    <td>
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-xs px-2.5 py-1 bg-slate-900/60 border border-slate-700/50 rounded-md text-slate-200">
                          {isPassVisible ? item.temp_password : "••••••••••••"}
                        </span>
                        <button
                          type="button"
                          className="btn-icon"
                          onClick={() => togglePasswordVisibility(item.id)}
                          title={isPassVisible ? "Hide password" : "Show password"}
                        >
                          {isPassVisible ? <EyeOff size={14} /> : <Eye size={14} />}
                        </button>
                        <button
                          type="button"
                          className="btn-icon"
                          onClick={() => copyToClipboard(item.temp_password, item.id)}
                          title="Copy password"
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
                      <span className="text-xs text-slate-400 font-mono">
                        {item.created_at ? new Date(item.created_at).toLocaleDateString() : "—"}
                      </span>
                    </td>
                    <td>
                      <button
                        type="button"
                        onClick={() => handleToggleStatus(item)}
                        className={`status-pill ${item.is_active ? "active cursor-pointer" : "inactive cursor-pointer"}`}
                        title={item.is_active ? "Click to Deactivate Enterprise" : "Click to Activate Enterprise"}
                      >
                        {item.is_active ? <CheckCircle2 size={12} /> : <XCircle size={12} />}
                        {item.is_active ? "Active" : "Deactivated"}
                      </button>
                    </td>
                    <td>
                      <button
                        type="button"
                        className="btn-link-action text-rose-400 hover:text-rose-300"
                        onClick={() => handleDelete(item)}
                        title="Delete enterprise"
                      >
                        <Trash2 size={15} />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Add Enterprise Modal (Enhanced Card Structure) */}
      {showAddModal && (
        <div className="ent-modal-overlay" onClick={() => setShowAddModal(false)}>
          <div className="ent-modal-card animated-scale-up" onClick={(e) => e.stopPropagation()}>
            {/* Modal Header */}
            <div className="ent-modal-header">
              <div className="ent-modal-icon-badge">
                <Building2 size={22} />
              </div>
              <div className="ent-modal-title-wrap">
                <h3>Add Connected Enterprise</h3>
                <p>Provision a new enterprise tenant and master administrator credentials.</p>
              </div>
              <button
                className="ent-modal-close-btn"
                onClick={() => setShowAddModal(false)}
                type="button"
                title="Close modal"
              >
                <X size={18} />
              </button>
            </div>

            {/* Modal Form */}
            <form onSubmit={handleCreateEnterprise} className="ent-modal-form">
              <div className="ent-form-group">
                <label className="ent-form-label">
                  Enterprise / Organization Name <span className="text-rose-500">*</span>
                </label>
                <input
                  type="text"
                  required
                  className="ent-form-input"
                  placeholder="e.g. Apex Global Technologies"
                  value={enterpriseName}
                  onChange={(e) => setEnterpriseName(e.target.value)}
                />
              </div>

              <div className="ent-form-group">
                <label className="ent-form-label">
                  Enterprise Admin Email <span className="text-rose-500">*</span>
                </label>
                <input
                  type="email"
                  required
                  className="ent-form-input"
                  placeholder="e.g. admin@apextech.com"
                  value={adminEmail}
                  onChange={(e) => setAdminEmail(e.target.value)}
                />
                <span className="ent-field-hint">
                  This email will be provisioned with Executive Administrator (Rank 1) permissions.
                </span>
              </div>

              <div className="ent-form-group">
                <label className="ent-form-label">
                  Temporary Password <span className="text-rose-500">*</span>
                </label>
                <div className="ent-password-input-group">
                  <div className="ent-input-relative">
                    <input
                      type={showTempPass ? "text" : "password"}
                      required
                      value={tempPassword}
                      onChange={(e) => setTempPassword(e.target.value)}
                      className="ent-form-input ent-input-mono"
                    />
                    <button
                      type="button"
                      className="ent-input-eye-btn"
                      onClick={() => setShowTempPass(!showTempPass)}
                      title={showTempPass ? "Hide password" : "Show password"}
                    >
                      {showTempPass ? <EyeOff size={16} /> : <Eye size={16} />}
                    </button>
                  </div>
                  <button
                    type="button"
                    className="btn-secondary ent-btn-aux"
                    onClick={generateRandomPassword}
                    title="Generate new secure password"
                  >
                    <RefreshCw size={14} /> New
                  </button>
                  <button
                    type="button"
                    className="btn-secondary ent-btn-aux"
                    onClick={() => {
                      navigator.clipboard.writeText(tempPassword);
                      setCopiedModalPass(true);
                      setTimeout(() => setCopiedModalPass(false), 2000);
                    }}
                    title="Copy password"
                  >
                    {copiedModalPass ? <Check size={14} className="text-emerald-500" /> : <Copy size={14} />}
                  </button>
                </div>
                <span className="ent-field-hint">
                  Share these credentials securely with the enterprise administrator for their initial login.
                </span>
              </div>

              {/* Modal Actions */}
              <div className="ent-modal-actions">
                <button
                  type="button"
                  className="btn-secondary"
                  onClick={() => setShowAddModal(false)}
                  disabled={submitting}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="btn-primary ent-btn-submit"
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
