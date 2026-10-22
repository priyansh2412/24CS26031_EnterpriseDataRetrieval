import React, { useState } from "react";
import {
  Shield,
  Key,
  CheckCircle2,
  AlertCircle,
  Building2,
  Clock,
  UserCheck,
  Lock,
  Eye,
  EyeOff,
  Sparkles,
  Layers,
} from "lucide-react";
import { UserProfile, request } from "../api";

interface ProfilePageProps {
  user: UserProfile | null;
  onProfileUpdated?: () => void;
}

export default function ProfilePage({ user, onProfileUpdated }: ProfilePageProps) {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showCurrentPassword, setShowCurrentPassword] = useState(false);
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    setSuccessMessage(null);
    setErrorMessage(null);

    if (!currentPassword) {
      setErrorMessage("Please enter your current password.");
      return;
    }

    if (newPassword.length < 6) {
      setErrorMessage("New password must be at least 6 characters long.");
      return;
    }

    if (newPassword !== confirmPassword) {
      setErrorMessage("New password and confirmation do not match.");
      return;
    }

    setLoading(true);
    try {
      const res = await request<{ status: string; message: string }>("/api/auth/change-password", {
        method: "POST",
        body: JSON.stringify({
          current_password: currentPassword,
          new_password: newPassword,
        }),
      });

      setSuccessMessage(res.message || "Password updated successfully!");
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      if (onProfileUpdated) onProfileUpdated();
    } catch (err: any) {
      setErrorMessage(err?.message || "Failed to update password. Please verify current password.");
    } finally {
      setLoading(false);
    }
  };

  const userRole = user?.role_key || user?.role || "admin";
  const enterpriseName = user?.enterprise_name || "Primary Enterprise Workspace";

  return (
    <div className="profile-page animate-fade-in" style={{ maxWidth: "1050px", margin: "0 auto", paddingBottom: "60px" }}>
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <UserCheck size={14} /> ADMINISTRATOR PROFILE
          </div>
          <h1>Account & Security Profile</h1>
          <p className="subheading">
            Review your administrator identity, active enterprise workspace, and manage your account credentials.
          </p>
        </div>
      </header>

      {/* Profile Overview Card Grid */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(360px, 1fr))", gap: "24px", marginTop: "24px" }}>
        {/* Left: Identity Details Card */}
        <section className="card-glass" style={{ padding: "28px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "20px" }}>
            <Shield size={18} style={{ color: "var(--palette-sky)" }} />
            <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "700", color: "var(--text)" }}>
              Identity & Hierarchy Authority
            </h3>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "16px", paddingBottom: "16px", borderBottom: "1px solid var(--border)" }}>
              <div
                style={{
                  width: "56px",
                  height: "56px",
                  borderRadius: "16px",
                  background: "var(--palette-gradient)",
                  color: "#fff",
                  display: "grid",
                  placeItems: "center",
                  fontSize: "22px",
                  fontWeight: "800",
                  boxShadow: "0 4px 14px rgba(168, 85, 247, 0.25)",
                  flexShrink: 0,
                }}
              >
                {user?.email?.[0]?.toUpperCase() || "A"}
              </div>
              <div>
                <strong style={{ fontSize: "16px", display: "block", color: "var(--text)" }}>{user?.email}</strong>
                <span className="badge-accent" style={{ marginTop: "6px", display: "inline-block" }}>
                  RANK {user?.rank_level ?? 1}: {userRole.toUpperCase()}
                </span>
              </div>
            </div>

            <div className="info-row" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ fontSize: "13px", color: "var(--text-muted)", fontWeight: "600" }}>Connected Enterprise</span>
              <strong style={{ fontSize: "13.5px", color: "var(--text)", display: "flex", alignItems: "center", gap: "6px" }}>
                <Building2 size={14} style={{ color: "var(--palette-sky)" }} />
                {enterpriseName}
              </strong>
            </div>

            {user?.tenant_id && (
              <div className="info-row" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <span style={{ fontSize: "13px", color: "var(--text-muted)", fontWeight: "600" }}>Enterprise Tenant ID</span>
                <code
                  style={{
                    background: "var(--bg-subtle)",
                    border: "1px solid var(--border)",
                    padding: "3px 8px",
                    borderRadius: "6px",
                    fontSize: "12px",
                    fontFamily: "monospace",
                    color: "var(--text)",
                  }}
                >
                  {user.tenant_id}
                </code>
              </div>
            )}

            <div className="info-row" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ fontSize: "13px", color: "var(--text-muted)", fontWeight: "600" }}>Account Status</span>
              <span className="badge-success" style={{ display: "inline-flex", alignItems: "center", gap: "5px" }}>
                <CheckCircle2 size={12} /> {user?.is_active ? "Active & Authorized" : "Inactive"}
              </span>
            </div>

            <div className="info-row" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <span style={{ fontSize: "13px", color: "var(--text-muted)", fontWeight: "600" }}>Privilege Scope</span>
              <strong style={{ fontSize: "13px", color: "var(--palette-sky)" }}>
                Executive Root Control (Rank {user?.rank_level ?? 1})
              </strong>
            </div>

            {user?.created_at && (
              <div className="info-row" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <span style={{ fontSize: "13px", color: "var(--text-muted)", fontWeight: "600" }}>Account Created</span>
                <span style={{ fontSize: "13px", color: "var(--text-muted)", display: "flex", alignItems: "center", gap: "4px" }}>
                  <Clock size={12} />
                  {new Date(user.created_at).toLocaleDateString("en-US", {
                    month: "short",
                    day: "numeric",
                    year: "numeric",
                  })}
                </span>
              </div>
            )}
          </div>
        </section>

        {/* Right: Change Password Card */}
        <section className="card-glass" style={{ padding: "28px" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "10px", marginBottom: "12px" }}>
            <Key size={18} style={{ color: "var(--palette-sky)" }} />
            <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "700", color: "var(--text)" }}>
              Change Password
            </h3>
          </div>
          <p style={{ fontSize: "13px", color: "var(--text-muted)", margin: "0 0 20px 0" }}>
            Ensure your administrator account stays protected with a strong, distinct password.
          </p>

          {successMessage && (
            <div className="alert-banner success" style={{ marginBottom: "16px" }}>
              <CheckCircle2 size={16} />
              <span>{successMessage}</span>
            </div>
          )}

          {errorMessage && (
            <div className="alert-banner error" style={{ marginBottom: "16px" }}>
              <AlertCircle size={16} />
              <span>{errorMessage}</span>
            </div>
          )}

          <form onSubmit={handlePasswordChange} style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            {/* Current Password */}
            <div className="form-group" style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
              <label style={{ fontSize: "12.5px", fontWeight: "700", color: "var(--text)" }}>
                Current Password
              </label>
              <div style={{ position: "relative" }}>
                <input
                  type={showCurrentPassword ? "text" : "password"}
                  className="ent-form-input"
                  placeholder="Enter current password"
                  value={currentPassword}
                  onChange={(e) => setCurrentPassword(e.target.value)}
                  required
                  style={{ width: "100%", paddingRight: "40px" }}
                />
                <button
                  type="button"
                  onClick={() => setShowCurrentPassword(!showCurrentPassword)}
                  style={{
                    position: "absolute",
                    right: "12px",
                    top: "50%",
                    transform: "translateY(-50%)",
                    background: "none",
                    border: "none",
                    cursor: "pointer",
                    color: "var(--text-muted)",
                    display: "flex",
                    alignItems: "center",
                  }}
                  title={showCurrentPassword ? "Hide password" : "Show password"}
                >
                  {showCurrentPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
            </div>

            {/* New Password */}
            <div className="form-group" style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
              <label style={{ fontSize: "12.5px", fontWeight: "700", color: "var(--text)" }}>
                New Password
              </label>
              <div style={{ position: "relative" }}>
                <input
                  type={showNewPassword ? "text" : "password"}
                  className="ent-form-input"
                  placeholder="Enter minimum 6 characters"
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  required
                  style={{ width: "100%", paddingRight: "40px" }}
                />
                <button
                  type="button"
                  onClick={() => setShowNewPassword(!showNewPassword)}
                  style={{
                    position: "absolute",
                    right: "12px",
                    top: "50%",
                    transform: "translateY(-50%)",
                    background: "none",
                    border: "none",
                    cursor: "pointer",
                    color: "var(--text-muted)",
                    display: "flex",
                    alignItems: "center",
                  }}
                  title={showNewPassword ? "Hide password" : "Show password"}
                >
                  {showNewPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
            </div>

            {/* Confirm New Password */}
            <div className="form-group" style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
              <label style={{ fontSize: "12.5px", fontWeight: "700", color: "var(--text)" }}>
                Confirm New Password
              </label>
              <input
                type="password"
                className="ent-form-input"
                placeholder="Re-enter your new password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
                style={{ width: "100%" }}
              />
            </div>

            <div style={{ marginTop: "8px", display: "flex", justifyContent: "flex-end" }}>
              <button
                type="submit"
                className="btn-pill btn-primary"
                disabled={loading}
                style={{ display: "inline-flex", alignItems: "center", gap: "8px" }}
              >
                <Lock size={15} />
                <span>{loading ? "Updating Password…" : "Update Password"}</span>
              </button>
            </div>
          </form>
        </section>
      </div>
    </div>
  );
}
