import { useState, useEffect } from "react";
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
          <div className="eyebrow" style={{ display: "flex", alignItems: "center", gap: "6px", color: "#2563eb", fontWeight: "700" }}>
            <Settings size={14} /> WORKSPACE & ORGANIZATIONAL HIERARCHY
          </div>
          <h1 style={{ fontSize: "28px", fontWeight: "800", color: "#0f172a", margin: "6px 0" }}>Workspace Settings</h1>
          <p className="subheading" style={{ color: "#64748b", fontSize: "14px", margin: 0 }}>
            Configure organizational role ranks and manage employee directory profiles.
          </p>
        </div>
      </header>

      {/* Feedback Alerts */}
      {feedback && (
        <div
          className={`alert-banner ${feedback.type}`}
          style={{
            marginBottom: "20px",
            padding: "12px 16px",
            borderRadius: "8px",
            display: "flex",
            alignItems: "center",
            gap: "10px",
            background: feedback.type === "success" ? "#ecfdf5" : "#fef2f2",
            color: feedback.type === "success" ? "#065f46" : "#991b1b",
            border: `1px solid ${feedback.type === "success" ? "#a7f3d0" : "#fecaca"}`,
          }}
        >
          {feedback.type === "success" ? <CheckCircle size={18} /> : <AlertCircle size={18} />}
          <span style={{ fontSize: "14px", fontWeight: "500" }}>{feedback.message}</span>
        </div>
      )}

      {/* Tabs Navigation: Exactly 2 Tabs as Requested */}
      <div
        style={{
          display: "flex",
          gap: "12px",
          borderBottom: "2px solid #e2e8f0",
          paddingBottom: "12px",
          marginBottom: "28px",
        }}
      >
        <button
          className={`btn ${activeTab === "roles" ? "btn-primary" : "btn-secondary"}`}
          onClick={() => setActiveTab("roles")}
          style={{
            display: "flex",
            alignItems: "center",
            gap: "8px",
            padding: "10px 20px",
            fontSize: "14px",
            fontWeight: "700",
            borderRadius: "8px",
          }}
        >
          <Award size={18} />
          <span>Role & Hierarchy</span>
        </button>

        <button
          className={`btn ${activeTab === "employees" ? "btn-primary" : "btn-secondary"}`}
          onClick={() => setActiveTab("employees")}
          style={{
            display: "flex",
            alignItems: "center",
            gap: "8px",
            padding: "10px 20px",
            fontSize: "14px",
            fontWeight: "700",
            borderRadius: "8px",
          }}
        >
          <Users size={18} />
          <span>Employees</span>
        </button>
      </div>

      {/* =========================================================================
          TAB 1: Role & Hierarchy
          ========================================================================= */}
      {activeTab === "roles" && (
        <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
          {/* Action Toolbar */}
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              flexWrap: "wrap",
              gap: "16px",
              padding: "18px 24px",
              background: "#ffffff",
              borderRadius: "12px",
              border: "1px solid #e2e8f0",
              boxShadow: "0 1px 3px rgba(0,0,0,0.03)",
            }}
          >
            <div>
              <h3 style={{ margin: 0, fontSize: "18px", fontWeight: "800", color: "#0f172a" }}>
                Role Hierarchy Management
              </h3>
              <p style={{ margin: "4px 0 0", color: "#64748b", fontSize: "13px" }}>
                Generate sequential rank levels and assign organizational roles with ranks (2, 3, 4...).
              </p>
            </div>

            {isAdmin && (
              <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                {/* Add Rank Button: automatically generates next rank */}
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={handleAddRank}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "8px",
                    padding: "9px 16px",
                    fontWeight: "600",
                    fontSize: "13px",
                    border: "1px solid #cbd5e1",
                    background: "#f8fafc",
                  }}
                  title="Generate the next numerical rank level"
                >
                  <Layers size={16} style={{ color: "#475569" }} />
                  <span>Add Rank</span>
                </button>

                {/* Add Role Button */}
                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={handleOpenAddRole}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "8px",
                    padding: "9px 18px",
                    fontWeight: "700",
                    fontSize: "13px",
                  }}
                >
                  <Plus size={16} />
                  <span>Add Role</span>
                </button>
              </div>
            )}
          </div>

          {/* Active Rank Progression Ladder */}
          <div
            style={{
              padding: "16px 20px",
              background: "#ffffff",
              borderRadius: "12px",
              border: "1px solid #e2e8f0",
            }}
          >
            <div style={{ fontSize: "12px", fontWeight: "700", color: "#64748b", marginBottom: "10px", textTransform: "uppercase", letterSpacing: "0.5px" }}>
              Available Rank Hierarchy Levels
            </div>
            <div style={{ display: "flex", flexWrap: "wrap", gap: "8px", alignItems: "center" }}>
              <span
                style={{
                  padding: "6px 14px",
                  borderRadius: "20px",
                  fontSize: "13px",
                  fontWeight: "700",
                  background: "#eff6ff",
                  color: "#1d4ed8",
                  border: "1px solid #bfdbfe",
                }}
              >
                Rank 1 (Admin / Root)
              </span>
              {allAvailableRanks.map((rk) => (
                <span
                  key={rk}
                  style={{
                    padding: "6px 14px",
                    borderRadius: "20px",
                    fontSize: "13px",
                    fontWeight: "700",
                    background: "#f8fafc",
                    color: "#334155",
                    border: "1px solid #cbd5e1",
                  }}
                >
                  Rank {rk}
                </span>
              ))}
            </div>
          </div>

          {/* Roles Cards Grid */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", gap: "16px" }}>
            {roles.map((r) => {
              const count = getEmployeesForRole(r).length;
              return (
                <div
                  key={r.id || r.key}
                  style={{
                    background: "#ffffff",
                    borderRadius: "12px",
                    border: "1px solid #e2e8f0",
                    padding: "20px",
                    display: "flex",
                    flexDirection: "column",
                    justifyContent: "space-between",
                    boxShadow: "0 1px 3px rgba(0,0,0,0.03)",
                    borderLeft: `5px solid ${r.rank_level === 1 ? "#2563eb" : r.rank_level === 2 ? "#8b5cf6" : r.rank_level === 3 ? "#0ea5e9" : "#64748b"}`,
                  }}
                >
                  <div>
                    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: "12px" }}>
                      <div>
                        <strong style={{ fontSize: "17px", color: "#0f172a", display: "block" }}>{r.name}</strong>
                        <span style={{ fontSize: "12px", fontFamily: "monospace", color: "#64748b" }}>
                          key: {r.key}
                        </span>
                      </div>
                      <span
                        style={{
                          padding: "4px 12px",
                          borderRadius: "20px",
                          fontSize: "12px",
                          fontWeight: "800",
                          background: r.rank_level === 1 ? "#eff6ff" : "#f1f5f9",
                          color: r.rank_level === 1 ? "#1d4ed8" : "#334155",
                          border: `1px solid ${r.rank_level === 1 ? "#bfdbfe" : "#cbd5e1"}`,
                        }}
                      >
                        RANK {r.rank_level}
                      </span>
                    </div>

                    <p style={{ fontSize: "13px", color: "#64748b", margin: "0 0 16px 0", minHeight: "36px" }}>
                      {r.description || `Role level ${r.rank_level} hierarchy designation.`}
                    </p>

                    <div style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "12px", color: "#475569" }}>
                      <Users size={14} style={{ color: "#94a3b8" }} />
                      <strong>{count}</strong> {count === 1 ? "Employee" : "Employees"} assigned
                    </div>
                  </div>

                  {isAdmin && r.key !== "admin" && r.key !== "employee" && (
                    <div
                      style={{
                        display: "flex",
                        justifyContent: "flex-end",
                        gap: "8px",
                        paddingTop: "14px",
                        marginTop: "16px",
                        borderTop: "1px solid #f1f5f9",
                      }}
                    >
                      <button
                        type="button"
                        onClick={() => r.id && handleDeleteRole(r.id, r.name)}
                        style={{
                          background: "none",
                          border: "none",
                          cursor: "pointer",
                          color: "#ef4444",
                          fontSize: "12px",
                          display: "flex",
                          alignItems: "center",
                          gap: "4px",
                          padding: "4px 8px",
                          borderRadius: "6px",
                        }}
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
        <div style={{ display: "flex", flexDirection: "column", gap: "32px" }}>
          {roles.map((role) => {
            const roleEmployees = getEmployeesForRole(role);

            return (
              <section
                key={role.id || role.key}
                style={{
                  background: "#ffffff",
                  borderRadius: "14px",
                  border: "1px solid #e2e8f0",
                  padding: "24px",
                  boxShadow: "0 1px 4px rgba(0,0,0,0.03)",
                }}
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
                    borderBottom: "1px solid #f1f5f9",
                    marginBottom: "18px",
                  }}
                >
                  <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
                    <div
                      style={{
                        width: "36px",
                        height: "36px",
                        borderRadius: "10px",
                        background: role.rank_level === 1 ? "#eff6ff" : role.rank_level === 2 ? "#faf5ff" : "#f0fdf4",
                        color: role.rank_level === 1 ? "#2563eb" : role.rank_level === 2 ? "#7c3aed" : "#16a34a",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        fontWeight: "700",
                      }}
                    >
                      <Shield size={18} />
                    </div>
                    <div>
                      <h3 style={{ margin: 0, fontSize: "18px", fontWeight: "800", color: "#0f172a" }}>
                        {role.name}
                      </h3>
                      <div style={{ display: "flex", alignItems: "center", gap: "8px", marginTop: "3px" }}>
                        <span
                          style={{
                            padding: "2px 8px",
                            borderRadius: "12px",
                            fontSize: "11px",
                            fontWeight: "700",
                            background: "#f1f5f9",
                            color: "#334155",
                          }}
                        >
                          Rank {role.rank_level}
                        </span>
                        <span style={{ fontSize: "12px", color: "#64748b" }}>
                          • {roleEmployees.length} {roleEmployees.length === 1 ? "member" : "members"}
                        </span>
                      </div>
                    </div>
                  </div>

                  {isAdmin && (
                    <button
                      type="button"
                      className="btn btn-primary"
                      onClick={() => handleOpenAddEmployee(role)}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: "6px",
                        padding: "8px 16px",
                        fontSize: "13px",
                        fontWeight: "700",
                        borderRadius: "8px",
                      }}
                    >
                      <UserPlus size={15} />
                      <span>Add Info</span>
                    </button>
                  )}
                </div>

                {/* Employees List: Long Rectangle Cards */}
                {roleEmployees.length === 0 ? (
                  <div
                    style={{
                      padding: "24px",
                      textAlign: "center",
                      background: "#f8fafc",
                      borderRadius: "10px",
                      border: "1px dashed #cbd5e1",
                      color: "#64748b",
                      fontSize: "13.5px",
                    }}
                  >
                    No employees added to <strong>{role.name}</strong> yet. Click the{" "}
                    <strong>Add Info</strong> button above to add someone.
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
                            background: "#ffffff",
                            borderRadius: "10px",
                            border: "1px solid #e2e8f0",
                            boxShadow: "0 1px 2px rgba(0,0,0,0.03)",
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
                                background: "linear-gradient(135deg, #eff6ff 0%, #dbeafe 100%)",
                                color: "#2563eb",
                                display: "flex",
                                alignItems: "center",
                                justifyItems: "center",
                                justifyContent: "center",
                                fontWeight: "800",
                                fontSize: "15px",
                                border: "1px solid #bfdbfe",
                                flexShrink: 0,
                              }}
                            >
                              {initial}
                            </div>
                            <div>
                              <div style={{ fontWeight: "700", color: "#0f172a", fontSize: "15px" }}>
                                {displayName}
                              </div>
                              <div style={{ fontSize: "12px", color: "#64748b" }}>
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
                              color: "#334155",
                              fontSize: "13.5px",
                              flex: "1 1 240px",
                            }}
                          >
                            <Mail size={15} style={{ color: "#94a3b8" }} />
                            <span style={{ fontFamily: "monospace", color: "#1e293b", fontWeight: "500" }}>
                              {emp.email}
                            </span>
                          </div>

                          {/* 3. Rank */}
                          <div style={{ display: "flex", alignItems: "center", gap: "14px" }}>
                            <span
                              style={{
                                padding: "5px 14px",
                                borderRadius: "20px",
                                fontSize: "12px",
                                fontWeight: "700",
                                background: "#f1f5f9",
                                color: "#334155",
                                border: "1px solid #cbd5e1",
                              }}
                            >
                              Rank {emp.rank_level ?? role.rank_level}
                            </span>

                            {isAdmin && (
                              <button
                                type="button"
                                onClick={() => handleDeleteEmployee(emp.id, displayName)}
                                style={{
                                  background: "none",
                                  border: "none",
                                  cursor: "pointer",
                                  color: "#94a3b8",
                                  padding: "6px",
                                  borderRadius: "6px",
                                  transition: "color 0.15s ease",
                                }}
                                onMouseEnter={(e) => (e.currentTarget.style.color = "#ef4444")}
                                onMouseLeave={(e) => (e.currentTarget.style.color = "#94a3b8")}
                                title="Remove Employee"
                              >
                                <Trash2 size={16} />
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
            <section
              style={{
                background: "#ffffff",
                borderRadius: "14px",
                border: "1px solid #e2e8f0",
                padding: "24px",
              }}
            >
              <div style={{ paddingBottom: "12px", borderBottom: "1px solid #f1f5f9", marginBottom: "16px" }}>
                <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "700", color: "#0f172a" }}>
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
                      background: "#ffffff",
                      borderRadius: "10px",
                      border: "1px solid #e2e8f0",
                    }}
                  >
                    <div style={{ fontWeight: "700", color: "#0f172a", fontSize: "14px" }}>
                      {emp.display_name || emp.email.split("@")[0]}
                    </div>
                    <div style={{ fontFamily: "monospace", color: "#334155", fontSize: "13px" }}>
                      {emp.email}
                    </div>
                    <span
                      style={{
                        padding: "4px 12px",
                        borderRadius: "20px",
                        fontSize: "12px",
                        fontWeight: "700",
                        background: "#f1f5f9",
                        color: "#475569",
                      }}
                    >
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
        <div
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: "rgba(15, 23, 42, 0.6)",
            backdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000,
            padding: "20px",
          }}
        >
          <div
            style={{
              background: "#ffffff",
              borderRadius: "14px",
              width: "100%",
              maxWidth: "460px",
              boxShadow: "0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: "18px 24px",
                borderBottom: "1px solid #e2e8f0",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                <Award size={18} style={{ color: "#2563eb" }} />
                <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "700", color: "#0f172a" }}>Add New Role</h3>
              </div>
              <button
                type="button"
                onClick={() => setIsAddingRole(false)}
                style={{ background: "none", border: "none", cursor: "pointer", color: "#94a3b8" }}
              >
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleSaveRole} style={{ padding: "24px", display: "flex", flexDirection: "column", gap: "18px" }}>
              {/* Option: Name of Role (Text box) */}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#334155", marginBottom: "6px" }}>
                  Name of Role *
                </label>
                <input
                  type="text"
                  className="input-field"
                  placeholder="e.g. HR, Finance, Operations, Team Lead"
                  value={newRoleName}
                  onChange={(e) => setNewRoleName(e.target.value)}
                  required
                  autoFocus
                  style={{ width: "100%", padding: "10px 14px", borderRadius: "8px", border: "1px solid #cbd5e1" }}
                />
              </div>

              {/* Option: Rank he can select */}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#334155", marginBottom: "6px" }}>
                  Select Rank *
                </label>
                <select
                  className="input-field"
                  value={newRoleRank}
                  onChange={(e) => setNewRoleRank(Number(e.target.value))}
                  required
                  style={{ width: "100%", padding: "10px 14px", borderRadius: "8px", border: "1px solid #cbd5e1" }}
                >
                  {allAvailableRanks.map((rk) => (
                    <option key={rk} value={rk}>
                      Rank {rk}
                    </option>
                  ))}
                </select>
                <span style={{ fontSize: "12px", color: "#64748b", marginTop: "4px", display: "block" }}>
                  Need a higher rank? Click <strong>Add Rank</strong> on the dashboard to generate the next level.
                </span>
              </div>

              <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "8px" }}>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setIsAddingRole(false)}
                  style={{ padding: "8px 16px" }}
                >
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary" style={{ padding: "8px 20px" }}>
                  Add Role
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
        <div
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: "rgba(15, 23, 42, 0.6)",
            backdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000,
            padding: "20px",
          }}
        >
          <div
            style={{
              background: "#ffffff",
              borderRadius: "14px",
              width: "100%",
              maxWidth: "500px",
              boxShadow: "0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: "18px 24px",
                borderBottom: "1px solid #e2e8f0",
              }}
            >
              <div>
                <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "700", color: "#0f172a" }}>
                  Add Employee Info
                </h3>
                <span style={{ fontSize: "12px", color: "#64748b" }}>
                  Assigning to <strong>{selectedRoleForEmployee.name}</strong> (Rank {selectedRoleForEmployee.rank_level})
                </span>
              </div>
              <button
                type="button"
                onClick={() => setSelectedRoleForEmployee(null)}
                style={{ background: "none", border: "none", cursor: "pointer", color: "#94a3b8" }}
              >
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleSaveEmployee} style={{ padding: "24px", display: "flex", flexDirection: "column", gap: "16px" }}>
              {/* Employee Name */}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#334155", marginBottom: "6px" }}>
                  Employee Name *
                </label>
                <input
                  type="text"
                  className="input-field"
                  placeholder={`e.g. John Doe (${selectedRoleForEmployee.name})`}
                  value={empName}
                  onChange={(e) => setEmpName(e.target.value)}
                  required
                  autoFocus
                  style={{ width: "100%", padding: "10px 14px", borderRadius: "8px", border: "1px solid #cbd5e1" }}
                />
              </div>

              {/* Employee Email ID */}
              <div>
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", color: "#334155", marginBottom: "6px" }}>
                  Employee Email ID *
                </label>
                <input
                  type="email"
                  className="input-field"
                  placeholder="e.g. employee@company.com"
                  value={empEmail}
                  onChange={(e) => setEmpEmail(e.target.value)}
                  required
                  style={{ width: "100%", padding: "10px 14px", borderRadius: "8px", border: "1px solid #cbd5e1" }}
                />
              </div>

              {/* Temporary Password (Generated for one-time setup) */}
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "6px" }}>
                  <label style={{ fontSize: "13px", fontWeight: "600", color: "#334155" }}>
                    One-Time Temporary Password
                  </label>
                  <button
                    type="button"
                    onClick={() => {
                      setEmpTempPassword(generateTemporaryPassword(12));
                      setCopiedPassword(false);
                    }}
                    style={{
                      background: "none",
                      border: "none",
                      color: "#2563eb",
                      fontSize: "12px",
                      cursor: "pointer",
                      display: "flex",
                      alignItems: "center",
                      gap: "4px",
                      fontWeight: "600",
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
                    style={{
                      flex: 1,
                      padding: "10px 14px",
                      borderRadius: "8px",
                      border: "1px solid #cbd5e1",
                      background: "#f8fafc",
                      fontFamily: "monospace",
                      fontSize: "14px",
                      fontWeight: "700",
                      color: "#0f172a",
                    }}
                  />
                  <button
                    type="button"
                    onClick={handleCopyPassword}
                    className="btn btn-secondary"
                    style={{ display: "flex", alignItems: "center", gap: "4px", padding: "10px 14px" }}
                    title="Copy Password"
                  >
                    {copiedPassword ? <Check size={16} style={{ color: "#16a34a" }} /> : <Copy size={16} />}
                  </button>
                </div>
                <span style={{ fontSize: "11.5px", color: "#64748b", marginTop: "4px", display: "block" }}>
                  This temporary password is automatically generated. The employee can use it to log in and change their password.
                </span>
              </div>

              <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px", marginTop: "12px" }}>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setSelectedRoleForEmployee(null)}
                  style={{ padding: "8px 16px" }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="btn btn-primary"
                  disabled={isSubmittingEmp}
                  style={{ padding: "8px 20px" }}
                >
                  {isSubmittingEmp ? "Saving..." : "Save Employee"}
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
        <div
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: "rgba(15, 23, 42, 0.6)",
            backdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 1000,
            padding: "20px",
          }}
        >
          <div
            style={{
              background: "#ffffff",
              borderRadius: "14px",
              width: "100%",
              maxWidth: "480px",
              boxShadow: "0 25px 50px -12px rgba(0, 0, 0, 0.25)",
              overflow: "hidden",
            }}
          >
            <div
              style={{
                padding: "20px 24px",
                background: "#f0fdf4",
                borderBottom: "1px solid #bbf7d0",
                display: "flex",
                alignItems: "center",
                gap: "12px",
              }}
            >
              <div
                style={{
                  width: "36px",
                  height: "36px",
                  borderRadius: "50%",
                  background: "#22c55e",
                  color: "#ffffff",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                }}
              >
                <Check size={20} />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "800", color: "#14532d" }}>
                  Employee Added Successfully!
                </h3>
                <span style={{ fontSize: "12px", color: "#166534" }}>
                  Here are the one-time login credentials for distribution.
                </span>
              </div>
            </div>

            <div style={{ padding: "24px", display: "flex", flexDirection: "column", gap: "14px" }}>
              <div style={{ background: "#f8fafc", padding: "14px 18px", borderRadius: "10px", border: "1px solid #e2e8f0" }}>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "8px" }}>
                  <span style={{ fontSize: "12px", color: "#64748b" }}>NAME</span>
                  <strong style={{ fontSize: "13px", color: "#0f172a" }}>{createdCredentials.name}</strong>
                </div>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "8px" }}>
                  <span style={{ fontSize: "12px", color: "#64748b" }}>EMAIL</span>
                  <span style={{ fontSize: "13px", fontFamily: "monospace", color: "#0f172a" }}>{createdCredentials.email}</span>
                </div>
                <div style={{ display: "flex", justifyContent: "space-between", marginBottom: "8px" }}>
                  <span style={{ fontSize: "12px", color: "#64748b" }}>ROLE & RANK</span>
                  <strong style={{ fontSize: "13px", color: "#0f172a" }}>
                    {createdCredentials.role} (Rank {createdCredentials.rank})
                  </strong>
                </div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", paddingTop: "8px", borderTop: "1px dashed #cbd5e1" }}>
                  <span style={{ fontSize: "12px", fontWeight: "700", color: "#1e293b" }}>TEMP PASSWORD</span>
                  <span
                    style={{
                      fontSize: "14px",
                      fontFamily: "monospace",
                      fontWeight: "800",
                      color: "#2563eb",
                      background: "#eff6ff",
                      padding: "2px 8px",
                      borderRadius: "6px",
                      border: "1px solid #bfdbfe",
                    }}
                  >
                    {createdCredentials.password}
                  </span>
                </div>
              </div>

              <div style={{ display: "flex", gap: "10px" }}>
                <button
                  type="button"
                  className="btn btn-primary"
                  onClick={handleCopyCredentials}
                  style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center", gap: "6px" }}
                >
                  {copiedCreds ? <Check size={16} /> : <Copy size={16} />}
                  <span>{copiedCreds ? "Credentials Copied!" : "Copy Credentials"}</span>
                </button>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setCreatedCredentials(null)}
                  style={{ padding: "8px 16px" }}
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
