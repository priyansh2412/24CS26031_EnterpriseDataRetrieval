import React, { useState, useEffect } from "react";
import {
  Settings,
  Award,
  Users,
  Plus,
  Trash2,
  Mail,
  Copy,
  Check,
  RefreshCw,
  AlertCircle,
  CheckCircle,
  Layers,
  UserPlus,
  Key,
  X,
  Shield,
} from "lucide-react";
import { CompanyRoleItem, UserProfile, UserItem, request } from "../api";

function generateTemporaryPassword(length = 12): string {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghjkmnpqrstuvwxyz";
  const digits = "23456789";
  const specials = "!@#$%&*";
  const all = upper + lower + digits + specials;

  // Ensure at least one from each group
  let pwd = "";
  pwd += upper.charAt(Math.floor(Math.random() * upper.length));
  pwd += lower.charAt(Math.floor(Math.random() * lower.length));
  pwd += digits.charAt(Math.floor(Math.random() * digits.length));
  pwd += specials.charAt(Math.floor(Math.random() * specials.length));

  for (let i = 4; i < length; i++) {
    pwd += all.charAt(Math.floor(Math.random() * all.length));
  }
  // Shuffle
  return pwd
    .split("")
    .sort(() => 0.5 - Math.random())
    .join("");
}

export default function SettingsPage({ user }: { user: UserProfile | null }) {
  const [activeTab, setActiveTab] = useState<"roles" | "employees">("roles");
  const [roles, setRoles] = useState<CompanyRoleItem[]>([]);
  const [employees, setEmployees] = useState<UserItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [feedback, setFeedback] = useState<{ type: "success" | "error"; message: string } | null>(null);

  // Custom dynamically generated ranks
  const [customRanks, setCustomRanks] = useState<number[]>([]);

  // Add Role Modal State
  const [isAddingRole, setIsAddingRole] = useState(false);
  const [newRoleName, setNewRoleName] = useState("");
  const [newRoleRank, setNewRoleRank] = useState<number>(2);

  // Add Employee Info Modal State
  const [selectedRoleForEmployee, setSelectedRoleForEmployee] = useState<CompanyRoleItem | null>(null);
  const [empName, setEmpName] = useState("");
  const [empEmail, setEmpEmail] = useState("");
  const [empTempPassword, setEmpTempPassword] = useState("");
  const [copiedPassword, setCopiedPassword] = useState(false);
  const [isSubmittingEmp, setIsSubmittingEmp] = useState(false);

  // Success One-Time Credentials Modal
  const [createdCredentials, setCreatedCredentials] = useState<{
    name: string;
    email: string;
    role: string;
    rank: number;
    password: string;
  } | null>(null);
  const [copiedCreds, setCopiedCreds] = useState(false);

  const fetchRoles = async () => {
    try {
      const data = await request<CompanyRoleItem[]>("/api/setup/roles");
      setRoles(data);
    } catch (e) {
      console.error("Failed to load roles", e);
    }
  };

  const fetchEmployees = async () => {
    try {
      const data = await request<UserItem[]>("/api/users");
      setEmployees(data);
    } catch (e) {
      console.error("Failed to load employees", e);
    }
  };

  useEffect(() => {
    setLoading(true);
    Promise.all([fetchRoles(), fetchEmployees()]).finally(() => setLoading(false));
  }, []);

  // Close modals on Escape key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setIsAddingRole(false);
        setSelectedRoleForEmployee(null);
        setCreatedCredentials(null);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  // Compute all available ranks: base ranks + ranks from existing roles + custom ranks generated via "Add Rank"
  const baseRanks = [2, 3, 4, 5];
  const roleRanks = roles.map((r) => r.rank_level);
  const allAvailableRanks = Array.from(new Set([...baseRanks, ...roleRanks, ...customRanks]))
    .filter((r) => r >= 2)
    .sort((a, b) => a - b);

  // "Add Rank" Button Logic: generates next sequential rank number
  const handleAddRank = () => {
    const highestRank = allAvailableRanks.length > 0 ? Math.max(...allAvailableRanks) : 5;
    const nextRank = highestRank + 1;
    if (!customRanks.includes(nextRank)) {
      setCustomRanks((prev) => [...prev, nextRank]);
    }
    setNewRoleRank(nextRank);
    setFeedback({
      type: "success",
      message: `Rank Level ${nextRank} generated successfully! You can now assign roles to Rank ${nextRank}.`,
    });
  };

  // Open "Add Role" Modal
  const handleOpenAddRole = () => {
    setNewRoleName("");
    setNewRoleRank(allAvailableRanks[0] || 2);
    setIsAddingRole(true);
    setFeedback(null);
  };

  // Save New Role
  const handleSaveRole = async (e: React.FormEvent) => {
    e.preventDefault();
    setFeedback(null);

    const trimmedName = newRoleName.trim();
    if (!trimmedName) {
      setFeedback({ type: "error", message: "Role Name is required." });
      return;
    }

    const generatedKey = trimmedName.toLowerCase().replace(/[^a-z0-9]+/g, "_");

    try {
      await request<CompanyRoleItem>("/api/setup/roles", {
        method: "POST",
        body: JSON.stringify({
          name: trimmedName,
          key: generatedKey,
          rank_level: Number(newRoleRank),
          description: `${trimmedName} departmental role (Rank Level ${newRoleRank})`,
          permissions: ["chat", "documents:view"],
        }),
      });

      setFeedback({
        type: "success",
        message: `Role '${trimmedName}' with Rank Level ${newRoleRank} added successfully!`,
      });
      setIsAddingRole(false);
      setNewRoleName("");
      fetchRoles();
    } catch (err: any) {
      setFeedback({ type: "error", message: err?.message || "Failed to save role." });
    }
  };

  // Delete Role
  const handleDeleteRole = async (roleId: number, roleName: string) => {
    if (!window.confirm(`Are you sure you want to delete the role '${roleName}'?`)) return;
    setFeedback(null);

    try {
      await request(`/api/setup/roles/${roleId}`, { method: "DELETE" });
      setFeedback({ type: "success", message: `Role '${roleName}' deleted from hierarchy.` });
      fetchRoles();
    } catch (err: any) {
      setFeedback({ type: "error", message: err?.message || "Failed to delete role." });
    }
  };

  // Open "Add Info" Modal for a Specific Role
  const handleOpenAddEmployee = (role: CompanyRoleItem) => {
    setSelectedRoleForEmployee(role);
    setEmpName("");
    setEmpEmail("");
    setEmpTempPassword(generateTemporaryPassword(12));
    setCopiedPassword(false);
    setFeedback(null);
  };

  // Save Employee Info
  const handleSaveEmployee = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedRoleForEmployee) return;

    const trimmedName = empName.trim();
    const trimmedEmail = empEmail.trim();

    if (!trimmedName || !trimmedEmail) {
      setFeedback({ type: "error", message: "Employee Name and Email ID are required." });
      return;
    }

    setIsSubmittingEmp(true);
    setFeedback(null);

    try {
      await request<UserItem>("/api/users", {
        method: "POST",
        body: JSON.stringify({
          email: trimmedEmail,
          display_name: trimmedName,
          password: empTempPassword,
          role_key: selectedRoleForEmployee.key,
          role: selectedRoleForEmployee.key === "admin" ? "admin" : "employee",
          rank_level: selectedRoleForEmployee.rank_level,
        }),
      });

      // Prepare credentials for one-time display modal
      setCreatedCredentials({
        name: trimmedName,
        email: trimmedEmail,
        role: selectedRoleForEmployee.name,
        rank: selectedRoleForEmployee.rank_level,
        password: empTempPassword,
      });

      setSelectedRoleForEmployee(null);
      setEmpName("");
      setEmpEmail("");
      setEmpTempPassword("");
      fetchEmployees();
    } catch (err: any) {
      setFeedback({ type: "error", message: err?.message || "Failed to add employee info." });
    } finally {
      setIsSubmittingEmp(false);
    }
  };

  // Delete Employee
  const handleDeleteEmployee = async (userId: string | number, identifier: string) => {
    if (!window.confirm(`Are you sure you want to remove employee '${identifier}'?`)) return;
    setFeedback(null);

    try {
      await request(`/api/users/${userId}`, { method: "DELETE" });
      setFeedback({ type: "success", message: `Employee '${identifier}' removed successfully.` });
      fetchEmployees();
    } catch (err: any) {
      setFeedback({ type: "error", message: err?.message || "Failed to remove employee." });
    }
  };

  // Copy password to clipboard
  const handleCopyPassword = () => {
    navigator.clipboard.writeText(empTempPassword);
    setCopiedPassword(true);
    setTimeout(() => setCopiedPassword(false), 2000);
  };

  // Copy full credentials to clipboard
  const handleCopyCredentials = () => {
    if (!createdCredentials) return;
    const text = `Enterprise Employee Credentials:\nName: ${createdCredentials.name}\nEmail: ${createdCredentials.email}\nRole: ${createdCredentials.role} (Rank ${createdCredentials.rank})\nOne-Time Temp Password: ${createdCredentials.password}\nLogin at: ${window.location.origin}/login`;
    navigator.clipboard.writeText(text);
    setCopiedCreds(true);
    setTimeout(() => setCopiedCreds(false), 2000);
  };

  // Filter employees for a specific role
  const getEmployeesForRole = (role: CompanyRoleItem) => {
    return employees.filter((emp) => {
      if (emp.role_key && emp.role_key.toLowerCase() === role.key.toLowerCase()) {
        return true;
      }
      if (emp.role && emp.role.toLowerCase() === role.key.toLowerCase()) {
        return true;
      }
      if (!emp.role_key && emp.rank_level === role.rank_level) {
        return true;
      }
      return false;
    });
  };

  // Find unassigned employees that don't match any role
  const unassignedEmployees = employees.filter((emp) => {
    const matched = roles.some(
      (r) =>
        (emp.role_key && emp.role_key.toLowerCase() === r.key.toLowerCase()) ||
        (emp.role && emp.role.toLowerCase() === r.key.toLowerCase()) ||
        (!emp.role_key && emp.rank_level === r.rank_level)
    );
    return !matched;
  });

  const isAdmin = user?.role === "admin" || user?.rank_level === 1 || user?.email === "system@gmailexample.com";

  return (
    <div className="settings-page animate-fade-in" style={{ maxWidth: "1150px", margin: "0 auto", paddingBottom: "60px" }}>
      {/* Page Header */}
      <header className="page-heading" style={{ marginBottom: "24px" }}>
        <div>
          <div className="eyebrow">
            <Settings size={14} /> WORKSPACE & ORGANIZATIONAL HIERARCHY
          </div>
          <h1>Workspace Settings</h1>
          <p className="subheading">
            Configure organizational role ranks and manage employee directory profiles.
          </p>
        </div>
      </header>

      {/* Feedback Alerts */}
      {feedback && (
        <div
          className={`alert-banner ${feedback.type}`}
          style={{ marginBottom: "24px" }}
        >
          {feedback.type === "success" ? <CheckCircle size={18} /> : <AlertCircle size={18} />}
          <span>{feedback.message}</span>
          <button
            type="button"
            onClick={() => setFeedback(null)}
            style={{ marginLeft: "auto", background: "none", border: "none", cursor: "pointer", color: "inherit" }}
          >
            <X size={14} />
          </button>
        </div>
      )}

      {/* Tabs Navigation: Segmented Style */}
      <div className="segmented" style={{ maxWidth: "380px", marginBottom: "28px" }}>
        <button
          type="button"
          className={`seg-btn ${activeTab === "roles" ? "active" : ""}`}
          onClick={() => setActiveTab("roles")}
        >
          <Award size={16} />
          <span>Role & Hierarchy</span>
        </button>

        <button
          type="button"
          className={`seg-btn ${activeTab === "employees" ? "active" : ""}`}
          onClick={() => setActiveTab("employees")}
        >
          <Users size={16} />
          <span>Employees ({employees.length})</span>
        </button>
      </div>

      {/* =========================================================================
          TAB 1: Role & Hierarchy
          ========================================================================= */}
      {activeTab === "roles" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
          {/* Action Toolbar Card */}
          <div className="card-glass" style={{ padding: "20px 24px" }}>
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                flexWrap: "wrap",
                gap: "16px",
              }}
            >
              <div>
                <h3 style={{ margin: 0, fontSize: "18px", fontWeight: "800", color: "var(--text)" }}>
                  Role Hierarchy Management
                </h3>
                <p style={{ margin: "4px 0 0", color: "var(--text-muted)", fontSize: "13px" }}>
                  Generate sequential rank levels and assign organizational roles with ranks (2, 3, 4…).
                </p>
              </div>

              {isAdmin && (
                <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                  <button
                    type="button"
                    className="btn-pill btn-secondary"
                    onClick={handleAddRank}
                    title="Generate the next numerical rank level"
                  >
                    <Layers size={15} />
                    <span>Add Rank</span>
                  </button>

                  <button
                    type="button"
                    className="btn-pill btn-primary"
                    onClick={handleOpenAddRole}
                  >
                    <Plus size={15} />
                    <span>Add Role</span>
                  </button>
                </div>
              )}
            </div>

            {/* Active Rank Progression Ladder */}
            <div style={{ marginTop: "18px", paddingTop: "14px", borderTop: "1px solid var(--border)" }}>
              <div style={{ fontSize: "11px", fontWeight: "700", color: "var(--text-muted)", marginBottom: "10px", textTransform: "uppercase", letterSpacing: "0.5px" }}>
                Active Rank Hierarchy Levels
              </div>
              <div style={{ display: "flex", flexWrap: "wrap", gap: "8px", alignItems: "center" }}>
                <span className="badge-accent">
                  Rank 1 (Admin / Root)
                </span>
                {allAvailableRanks.map((rk) => (
                  <span
                    key={rk}
                    className="chip"
                    style={{ fontWeight: "700" }}
                  >
                    Rank {rk}
                  </span>
                ))}
              </div>
            </div>
          </div>

          {/* Roles Cards Grid */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", gap: "18px" }}>
            {roles.map((r) => {
              const count = getEmployeesForRole(r).length;
              return (
                <div
                  key={r.id || r.key}
                  className="card-glass"
                  style={{
                    padding: "22px",
                    display: "flex",
                    flexDirection: "column",
                    justifyContent: "space-between",
                    borderLeft: `4px solid ${r.rank_level === 1 ? "var(--palette-sky)" : r.rank_level === 2 ? "var(--palette-purple)" : r.rank_level === 3 ? "var(--palette-pink)" : "var(--palette-amber)"}`,
                  }}
                >
                  <div>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "12px" }}>
                      <div>
                        <strong style={{ fontSize: "17px", color: "var(--text)", display: "block" }}>{r.name}</strong>
                        <span style={{ fontSize: "12px", fontFamily: "monospace", color: "var(--text-muted)" }}>
                          key: {r.key}
                        </span>
                      </div>
                      <span className={r.rank_level === 1 ? "badge-accent" : "badge-info"}>
                        RANK {r.rank_level}
                      </span>
                    </div>

                    <p style={{ fontSize: "13px", color: "var(--text-muted)", margin: "0 0 16px 0", minHeight: "36px" }}>
                      {r.description || `Role level ${r.rank_level} hierarchy designation.`}
                    </p>

                    <div style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "12.5px", color: "var(--text-muted)" }}>
                      <Users size={14} style={{ color: "var(--palette-sky)" }} />
                      <strong style={{ color: "var(--text)" }}>{count}</strong> {count === 1 ? "Employee" : "Employees"} assigned
                    </div>
                  </div>

                  {isAdmin && r.key !== "admin" && r.key !== "employee" && (
                    <div
                      style={{
                        display: "flex",
                        justifyContent: "flex-end",
                        paddingTop: "14px",
                        marginTop: "16px",
                        borderTop: "1px solid var(--border)",
                      }}
                    >
                      <button
                        type="button"
                        onClick={() => r.id && handleDeleteRole(r.id, r.name)}
                        className="ent-delete-btn"
                        title="Delete Role"
                      >
                        <Trash2 size={14} />
                        <span>Delete</span>
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* =========================================================================
          TAB 2: Employees
          ========================================================================= */}
      {activeTab === "employees" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "28px" }}>
          {roles.map((role) => {
            const roleEmployees = getEmployeesForRole(role);

            return (
              <section
                key={role.id || role.key}
                className="card-glass"
                style={{ padding: "24px" }}
              >
                {/* Section Header: Role Name, Rank Badge, and "Add Info" Button */}
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    alignItems: "center",
                    flexWrap: "wrap",
                    gap: "12px",
                    paddingBottom: "16px",
                    borderBottom: "1px solid var(--border)",
                    marginBottom: "18px",
                  }}
                >
                  <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                    <div
                      style={{
                        width: "38px",
                        height: "38px",
                        borderRadius: "10px",
                        background: role.rank_level === 1 ? "rgba(56, 189, 248, 0.12)" : "rgba(168, 85, 247, 0.12)",
                        color: role.rank_level === 1 ? "var(--palette-sky)" : "var(--palette-purple)",
                        display: "grid",
                        placeItems: "center",
                        fontWeight: "700",
                      }}
                    >
                      <Shield size={18} />
                    </div>
                    <div>
                      <h3 style={{ margin: 0, fontSize: "18px", fontWeight: "800", color: "var(--text)" }}>
                        {role.name}
                      </h3>
                      <div style={{ display: "flex", alignItems: "center", gap: "8px", marginTop: "3px" }}>
                        <span className="chip" style={{ fontSize: "11px", padding: "2px 8px" }}>
                          Rank {role.rank_level}
                        </span>
                        <span style={{ fontSize: "12px", color: "var(--text-muted)" }}>
                          • {roleEmployees.length} {roleEmployees.length === 1 ? "member" : "members"}
                        </span>
                      </div>
                    </div>
                  </div>

                  {isAdmin && (
                    <button
                      type="button"
                      className="btn-pill btn-primary"
                      onClick={() => handleOpenAddEmployee(role)}
                    >
                      <UserPlus size={15} />
                      <span>Add Employee</span>
                    </button>
                  )}
                </div>

                {/* Employees List */}
                {roleEmployees.length === 0 ? (
                  <div
                    style={{
                      padding: "24px",
                      textAlign: "center",
                      background: "var(--bg-subtle)",
                      borderRadius: "var(--radius-lg)",
                      border: "1px dashed var(--border)",
                      color: "var(--text-muted)",
                      fontSize: "13.5px",
                    }}
                  >
                    No employees added to <strong>{role.name}</strong> yet. Click the{" "}
                    <strong>Add Employee</strong> button above to invite someone.
                  </div>
                ) : (
                  <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
                    {roleEmployees.map((emp) => {
                      const displayName = emp.display_name || emp.email.split("@")[0];
                      const initial = (displayName || "E").charAt(0).toUpperCase();

                      return (
                        <div
                          key={emp.id}
                          style={{
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "space-between",
                            flexWrap: "wrap",
                            gap: "16px",
                            padding: "14px 20px",
                            background: "var(--surface)",
                            borderRadius: "var(--radius-lg)",
                            border: "1px solid var(--border)",
                            boxShadow: "var(--shadow-xs)",
                            transition: "all 0.15s ease",
                          }}
                        >
                          {/* 1. Name */}
                          <div style={{ display: "flex", alignItems: "center", gap: "14px", minWidth: "220px" }}>
                            <div
                              style={{
                                width: "40px",
                                height: "40px",
                                borderRadius: "10px",
                                background: "var(--palette-gradient)",
                                color: "#fff",
                                display: "grid",
                                placeItems: "center",
                                fontWeight: "800",
                                fontSize: "15px",
                                flexShrink: 0,
                                boxShadow: "0 2px 8px rgba(56, 189, 248, 0.25)",
                              }}
                            >
                              {initial}
                            </div>
                            <div>
                              <div style={{ fontWeight: "700", color: "var(--text)", fontSize: "14.5px" }}>
                                {displayName}
                              </div>
                              <div style={{ fontSize: "12px", color: "var(--text-muted)" }}>
                                {role.name}
                              </div>
                            </div>
                          </div>

                          {/* 2. Email ID */}
                          <div
                            style={{
                              display: "flex",
                              alignItems: "center",
                              gap: "8px",
                              fontSize: "13.5px",
                              flex: "1 1 240px",
                            }}
                          >
                            <Mail size={15} style={{ color: "var(--text-muted)" }} />
                            <span style={{ fontFamily: "monospace", color: "var(--text)", fontWeight: "500" }}>
                              {emp.email}
                            </span>
                          </div>

                          {/* 3. Rank & Actions */}
                          <div style={{ display: "flex", alignItems: "center", gap: "14px" }}>
                            <span className="chip" style={{ fontWeight: "700" }}>
                              Rank {emp.rank_level ?? role.rank_level}
                            </span>

                            {isAdmin && (
                              <button
                                type="button"
                                onClick={() => handleDeleteEmployee(emp.id, displayName)}
                                className="ent-delete-btn"
                                title="Remove Employee"
                              >
                                <Trash2 size={15} />
                              </button>
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </section>
            );
          })}

          {/* Unassigned employees if any exist in database */}
          {unassignedEmployees.length > 0 && (
            <section className="card-glass" style={{ padding: "24px" }}>
              <div style={{ paddingBottom: "12px", borderBottom: "1px solid var(--border)", marginBottom: "16px" }}>
                <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "700", color: "var(--text)" }}>
                  Other Workspace Staff ({unassignedEmployees.length})
                </h3>
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
                {unassignedEmployees.map((emp) => (
                  <div
                    key={emp.id}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "space-between",
                      padding: "14px 20px",
                      background: "var(--surface)",
                      borderRadius: "var(--radius-lg)",
                      border: "1px solid var(--border)",
                    }}
                  >
                    <div style={{ fontWeight: "700", color: "var(--text)", fontSize: "14px" }}>
                      {emp.display_name || emp.email.split("@")[0]}
                    </div>
                    <div style={{ fontFamily: "monospace", color: "var(--text-muted)", fontSize: "13px" }}>
                      {emp.email}
                    </div>
                    <span className="chip">
                      Rank {emp.rank_level}
                    </span>
                  </div>
                ))}
              </div>
            </section>
          )}
        </div>
      )}

      {/* =========================================================================
          MODAL: Add Role Dialog
          ========================================================================= */}
      {isAddingRole && (
        <div className="ent-modal-overlay" onClick={() => setIsAddingRole(false)}>
          <div className="ent-modal-card animated-scale-up" onClick={(e) => e.stopPropagation()}>
            <div className="ent-modal-header">
              <div className="ent-modal-icon-badge">
                <Award size={20} />
              </div>
              <div className="ent-modal-title-wrap">
                <h3>Add New Role</h3>
                <p>Define an organizational role designation and assign a hierarchy rank.</p>
              </div>
              <button
                type="button"
                className="ent-modal-close-btn"
                onClick={() => setIsAddingRole(false)}
                title="Close modal"
              >
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleSaveRole} className="ent-modal-form">
              <div className="ent-form-group">
                <label className="ent-form-label">Name of Role *</label>
                <input
                  type="text"
                  className="ent-form-input"
                  placeholder="e.g. HR, Finance, Operations, Team Lead"
                  value={newRoleName}
                  onChange={(e) => setNewRoleName(e.target.value)}
                  required
                  autoFocus
                />
              </div>

              <div className="ent-form-group">
                <label className="ent-form-label">Select Rank *</label>
                <select
                  className="ent-form-input"
                  value={newRoleRank}
                  onChange={(e) => setNewRoleRank(Number(e.target.value))}
                  required
                >
                  {allAvailableRanks.map((rk) => (
                    <option key={rk} value={rk}>
                      Rank {rk}
                    </option>
                  ))}
                </select>
                <span className="ent-field-hint">
                  Need a higher rank? Click <strong>Add Rank</strong> on the dashboard to generate the next level.
                </span>
              </div>

              <div className="ent-modal-actions">
                <button
                  type="button"
                  className="btn-pill btn-secondary"
                  onClick={() => setIsAddingRole(false)}
                >
                  Cancel
                </button>
                <button type="submit" className="btn-pill btn-primary">
                  Save Role
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* =========================================================================
          MODAL: Add Employee Info Dialog
          ========================================================================= */}
      {selectedRoleForEmployee && (
        <div className="ent-modal-overlay" onClick={() => setSelectedRoleForEmployee(null)}>
          <div className="ent-modal-card animated-scale-up" onClick={(e) => e.stopPropagation()}>
            <div className="ent-modal-header">
              <div className="ent-modal-icon-badge">
                <UserPlus size={20} />
              </div>
              <div className="ent-modal-title-wrap">
                <h3>Add Employee Info</h3>
                <p>
                  Assigning to <strong>{selectedRoleForEmployee.name}</strong> (Rank {selectedRoleForEmployee.rank_level})
                </p>
              </div>
              <button
                type="button"
                className="ent-modal-close-btn"
                onClick={() => setSelectedRoleForEmployee(null)}
                title="Close modal"
              >
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleSaveEmployee} className="ent-modal-form">
              <div className="ent-form-group">
                <label className="ent-form-label">Employee Name *</label>
                <input
                  type="text"
                  className="ent-form-input"
                  placeholder={`e.g. John Doe (${selectedRoleForEmployee.name})`}
                  value={empName}
                  onChange={(e) => setEmpName(e.target.value)}
                  required
                  autoFocus
                />
              </div>

              <div className="ent-form-group">
                <label className="ent-form-label">Employee Email ID *</label>
                <input
                  type="email"
                  className="ent-form-input"
                  placeholder="e.g. employee@company.com"
                  value={empEmail}
                  onChange={(e) => setEmpEmail(e.target.value)}
                  required
                />
              </div>

              <div className="ent-form-group">
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <label className="ent-form-label">One-Time Temporary Password</label>
                  <button
                    type="button"
                    onClick={() => {
                      setEmpTempPassword(generateTemporaryPassword(12));
                      setCopiedPassword(false);
                    }}
                    style={{
                      background: "none",
                      border: "none",
                      color: "var(--palette-sky)",
                      fontSize: "12px",
                      cursor: "pointer",
                      display: "flex",
                      alignItems: "center",
                      gap: "4px",
                      fontWeight: "700",
                    }}
                  >
                    <RefreshCw size={12} /> Regenerate
                  </button>
                </div>

                <div style={{ display: "flex", gap: "8px" }}>
                  <input
                    type="text"
                    readOnly
                    value={empTempPassword}
                    className="ent-form-input font-mono"
                    style={{ fontWeight: "700" }}
                  />
                  <button
                    type="button"
                    onClick={handleCopyPassword}
                    className="btn-pill btn-secondary"
                    title="Copy Password"
                  >
                    {copiedPassword ? <Check size={16} className="text-emerald-500" /> : <Copy size={16} />}
                  </button>
                </div>
                <span className="ent-field-hint">
                  This temporary password is automatically generated. The employee can use it to log in and change their password.
                </span>
              </div>

              <div className="ent-modal-actions">
                <button
                  type="button"
                  className="btn-pill btn-secondary"
                  onClick={() => setSelectedRoleForEmployee(null)}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="btn-pill btn-primary"
                  disabled={isSubmittingEmp}
                >
                  {isSubmittingEmp ? "Saving…" : "Save Employee"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* =========================================================================
          MODAL: One-Time Credentials Display After Creation
          ========================================================================= */}
      {createdCredentials && (
        <div className="ent-modal-overlay" onClick={() => setCreatedCredentials(null)}>
          <div className="ent-modal-card animated-scale-up" onClick={(e) => e.stopPropagation()}>
            <div
              style={{
                padding: "20px 24px",
                background: "rgba(16, 185, 129, 0.1)",
                borderBottom: "1px solid rgba(16, 185, 129, 0.25)",
                display: "flex",
                alignItems: "center",
                gap: "12px",
              }}
            >
              <div
                style={{
                  width: "38px",
                  height: "38px",
                  borderRadius: "50%",
                  background: "#10b981",
                  color: "#ffffff",
                  display: "grid",
                  placeItems: "center",
                  flexShrink: 0,
                }}
              >
                <Check size={20} />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "800", color: "var(--text)" }}>
                  Employee Added Successfully!
                </h3>
                <span style={{ fontSize: "12.5px", color: "var(--text-muted)" }}>
                  Here are the one-time login credentials for distribution.
                </span>
              </div>
            </div>

            <div style={{ padding: "24px", display: "flex", flexDirection: "column", gap: "16px" }}>
              <div style={{ background: "var(--bg-subtle)", padding: "16px 20px", borderRadius: "var(--radius-lg)", border: "1px solid var(--border)" }}>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "8px" }}>
                  <span style={{ fontSize: "12px", color: "var(--text-muted)", fontWeight: "600" }}>NAME</span>
                  <strong style={{ fontSize: "13.5px", color: "var(--text)" }}>{createdCredentials.name}</strong>
                </div>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "8px" }}>
                  <span style={{ fontSize: "12px", color: "var(--text-muted)", fontWeight: "600" }}>EMAIL</span>
                  <span style={{ fontSize: "13px", fontFamily: "monospace", color: "var(--text)" }}>{createdCredentials.email}</span>
                </div>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "8px" }}>
                  <span style={{ fontSize: "12px", color: "var(--text-muted)", fontWeight: "600" }}>ROLE & RANK</span>
                  <strong style={{ fontSize: "13px", color: "var(--palette-sky)" }}>
                    {createdCredentials.role} (Rank {createdCredentials.rank})
                  </strong>
                </div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingTop: "10px", borderTop: "1px dashed var(--border)" }}>
                  <span style={{ fontSize: "12px", fontWeight: "700", color: "var(--text)" }}>TEMP PASSWORD</span>
                  <span
                    style={{
                      fontSize: "14px",
                      fontFamily: "monospace",
                      fontWeight: "800",
                      color: "var(--palette-sky)",
                      background: "rgba(56, 189, 248, 0.12)",
                      padding: "3px 10px",
                      borderRadius: "6px",
                      border: "1px solid rgba(56, 189, 248, 0.25)",
                    }}
                  >
                    {createdCredentials.password}
                  </span>
                </div>
              </div>

              <div style={{ display: "flex", gap: "10px" }}>
                <button
                  type="button"
                  className="btn-pill btn-primary"
                  onClick={handleCopyCredentials}
                  style={{ flex: 1, justifyContent: "center" }}
                >
                  {copiedCreds ? <Check size={16} /> : <Copy size={16} />}
                  <span>{copiedCreds ? "Credentials Copied!" : "Copy Credentials"}</span>
                </button>
                <button
                  type="button"
                  className="btn-pill btn-secondary"
                  onClick={() => setCreatedCredentials(null)}
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
