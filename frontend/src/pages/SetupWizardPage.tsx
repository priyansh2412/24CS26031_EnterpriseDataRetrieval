import React, { useState } from "react";
import { ShieldCheck, Plus, Trash2, ArrowRight, CheckCircle2, Layers, UserCheck, Building2, Lock } from "lucide-react";
import { CompanyRoleItem, request } from "../api";

interface SetupWizardProps {
  onSetupCompleted: () => void;
}

const DEFAULT_ROLES: CompanyRoleItem[] = [
  { name: "Executive Admin", key: "admin", rank_level: 1, description: "C-Suite & System Administrators (Full Access)" },
  { name: "Department Manager", key: "manager", rank_level: 2, description: "Department Leads & Operations Managers" },
  { name: "Team Lead", key: "team_lead", rank_level: 3, description: "Project Leads & Senior Engineers" },
  { name: "Staff Employee", key: "employee", rank_level: 4, description: "General Staff & Individual Contributors" },
];

export default function SetupWizardPage({ onSetupCompleted }: SetupWizardProps) {
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [companyName, setCompanyName] = useState("");
  const [roles, setRoles] = useState<CompanyRoleItem[]>(DEFAULT_ROLES);
  const [adminEmail, setAdminEmail] = useState("");
  const [adminPassword, setAdminPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleAddRole = () => {
    const nextRank = roles.length + 1;
    setRoles([
      ...roles,
      {
        name: `Custom Role ${nextRank}`,
        key: `role_${Date.now().toString().slice(-4)}`,
        rank_level: nextRank,
        description: "Custom organization role level",
      },
    ]);
  };

  const handleRemoveRole = (index: number) => {
    if (roles.length <= 1) return;
    const updated = roles.filter((_, i) => i !== index).map((r, idx) => ({ ...r, rank_level: idx + 1 }));
    setRoles(updated);
  };

  const handleRoleChange = (index: number, field: keyof CompanyRoleItem, value: any) => {
    const updated = [...roles];
    updated[index] = { ...updated[index], [field]: value };
    setRoles(updated);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!companyName.trim()) {
      setError("Please enter your organization or company name.");
      setStep(1);
      return;
    }

    if (adminPassword !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    if (adminPassword.length < 8) {
      setError("Administrator password must be at least 8 characters long.");
      return;
    }

    setLoading(true);

    try {
      await request("/api/setup/initialize", {
        method: "POST",
        body: JSON.stringify({
          company_name: companyName.trim(),
          roles,
          admin_email: adminEmail.trim(),
          admin_password: adminPassword,
        }),
      });

      onSetupCompleted();
    } catch (err: any) {
      setError(err.message || "Failed to initialize system setup.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="setup-wizard-overlay">
      <div className="setup-wizard-card">
        <header className="setup-header">
          <div className="brand-badge">
            <ShieldCheck size={28} />
          </div>
          <h2>Enterprise System Initialization</h2>
          <p>Initial Product Setup & Corporate Role Hierarchy Configuration</p>
        </header>

        {/* Step Indicator */}
        <div className="setup-steps-nav">
          <div className={`step-pill ${step >= 1 ? "active" : ""}`}>
            <span className="num">1</span>
            <span>Organization</span>
          </div>
          <div className="step-connector" />
          <div className={`step-pill ${step >= 2 ? "active" : ""}`}>
            <span className="num">2</span>
            <span>Role Hierarchy</span>
          </div>
          <div className="step-connector" />
          <div className={`step-pill ${step >= 3 ? "active" : ""}`}>
            <span className="num">3</span>
            <span>Root Administrator</span>
          </div>
        </div>

        {error && (
          <div className="alert-banner error margin-bottom">
            <span>{error}</span>
          </div>
        )}

        {/* STEP 1: Organization Details */}
        {step === 1 && (
          <div className="wizard-step-content">
            <div className="step-title-block">
              <Building2 size={20} />
              <h3>Step 1: Company Profile</h3>
            </div>
            <p className="step-sub">Enter the name of your organization. This will be branded across your retrieval workspace.</p>

            <div className="form-group margin-top">
              <label>Organization / Company Name</label>
              <input
                type="text"
                placeholder="e.g. Acme Global Enterprises"
                value={companyName}
                onChange={(e) => setCompanyName(e.target.value)}
                required
                autoFocus
              />
            </div>

            <div className="wizard-actions">
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => {
                  if (!companyName.trim()) {
                    setError("Please enter your organization name to continue.");
                    return;
                  }
                  setError(null);
                  setStep(2);
                }}
              >
                <span>Continue to Role Hierarchy</span>
                <ArrowRight size={16} />
              </button>
            </div>
          </div>
        )}

        {/* STEP 2: Custom Role Hierarchy Builder */}
        {step === 2 && (
          <div className="wizard-step-content">
            <div className="step-title-block">
              <Layers size={20} />
              <h3>Step 2: Corporate Role Hierarchy Configuration</h3>
            </div>
            <p className="step-sub">
              Define the organizational roles and their rank hierarchy. Lower rank numbers represent higher authority (Rank 1 = Highest Authority). Upper rank roles will have audit visibility over succeeding (lower) role levels.
            </p>

            <div className="role-hierarchy-list margin-top">
              {roles.map((r, idx) => (
                <div key={idx} className="role-card-item">
                  <div className="rank-badge">Rank {r.rank_level}</div>
                  <div className="role-fields">
                    <input
                      type="text"
                      placeholder="Role Display Name"
                      value={r.name}
                      onChange={(e) => handleRoleChange(idx, "name", e.target.value)}
                      className="role-name-input"
                    />
                    <input
                      type="text"
                      placeholder="key_identifier"
                      value={r.key}
                      onChange={(e) => handleRoleChange(idx, "key", e.target.value.toLowerCase().replace(/\s+/g, "_"))}
                      className="role-key-input"
                    />
                    <input
                      type="text"
                      placeholder="Role description..."
                      value={r.description || ""}
                      onChange={(e) => handleRoleChange(idx, "description", e.target.value)}
                      className="role-desc-input"
                    />
                  </div>
                  {roles.length > 1 && (
                    <button type="button" className="btn-icon danger" onClick={() => handleRemoveRole(idx)} title="Remove Role">
                      <Trash2 size={16} />
                    </button>
                  )}
                </div>
              ))}
            </div>

            <button type="button" className="btn btn-secondary margin-top" onClick={handleAddRole}>
              <Plus size={16} />
              <span>Add Custom Role Level</span>
            </button>

            <div className="wizard-actions">
              <button type="button" className="btn btn-outline" onClick={() => setStep(1)}>
                Back
              </button>
              <button type="button" className="btn btn-primary" onClick={() => setStep(3)}>
                <span>Continue to Admin Setup</span>
                <ArrowRight size={16} />
              </button>
            </div>
          </div>
        )}

        {/* STEP 3: Root Administrator Setup */}
        {step === 3 && (
          <form onSubmit={handleSubmit} className="wizard-step-content">
            <div className="step-title-block">
              <UserCheck size={20} />
              <h3>Step 3: Root Administrator Account</h3>
            </div>
            <p className="step-sub">Create the initial Rank 1 Administrator account for full system access and governance.</p>

            <div className="form-group margin-top">
              <label>Administrator Email Address</label>
              <input
                type="email"
                placeholder="admin@company.com"
                value={adminEmail}
                onChange={(e) => setAdminEmail(e.target.value)}
                required
              />
            </div>

            <div className="form-group">
              <label>Password</label>
              <input
                type="password"
                placeholder="At least 8 characters"
                value={adminPassword}
                onChange={(e) => setAdminPassword(e.target.value)}
                required
              />
            </div>

            <div className="form-group">
              <label>Confirm Password</label>
              <input
                type="password"
                placeholder="Re-enter password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
              />
            </div>

            <div className="wizard-actions">
              <button type="button" className="btn btn-outline" onClick={() => setStep(2)}>
                Back
              </button>
              <button type="submit" className="btn btn-success" disabled={loading}>
                {loading ? (
                  <span>Initializing...</span>
                ) : (
                  <>
                    <CheckCircle2 size={16} />
                    <span>Complete System Setup</span>
                  </>
                )}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
