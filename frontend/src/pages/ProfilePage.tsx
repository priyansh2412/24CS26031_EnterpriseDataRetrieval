import { useState } from "react";
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
    <div className="profile-page animate-fade-in" style={{ maxWidth: "1000px", margin: "0 auto" }}>
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <UserCheck size={14} /> ADMINISTRATOR PROFILE
          </div>
          <h1>Admin Account & Security</h1>
          <p className="subheading">
            Review your administrator identity, active enterprise workspace, and manage your account credentials.
          </p>
        </div>
      </header>

      {/* Profile Overview Card */}
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1.2fr", gap: "24px", marginTop: "20px" }}>
        {/* Left: Identity Details */}
        <section className="settings-card" style={{ height: "fit-content" }}>
          <div className="card-head">
            <Shield size={18} />
            <h3>Identity & Hierarchy Details</h3>
          </div>
          <div className="card-body" style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "16px", paddingBottom: "16px", borderBottom: "1px solid var(--border)" }}>
              <div
                style={{
                  width: "56px",
                  height: "56px",
                  borderRadius: "14px",
                  background: "linear-gradient(135deg, var(--accent), #4f46e5)",
                  color: "#fff",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: "22px",
                  fontWeight: "700",
                  boxShadow: "0 4px 12px rgba(37,99,235,0.25)",
                }}
              >
                {user?.email?.[0]?.toUpperCase() || "A"}
              </div>
              <div>
                <strong style={{ fontSize: "16px", display: "block" }}>{user?.email}</strong>
                <span className={`role-badge ${userRole}`} style={{ marginTop: "4px" }}>
                  RANK {user?.rank_level ?? 1}: {userRole.toUpperCase()}
                </span>
              </div>
            </div>

            <div className="info-row">
              <span className="info-label">Connected Enterprise</span>
              <strong className="info-val" style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                <Building2 size={14} style={{ color: "var(--accent)" }} />
                {enterpriseName}
              </strong>
            </div>

            {user?.tenant_id && (
              <div className="info-row">
                <span className="info-label">Enterprise Tenant Space</span>
                <code
                  style={{
                    background: "var(--bg-subtle)",
                    padding: "3px 8px",
                    borderRadius: "6px",
                    fontSize: "12px",
                    fontFamily: "monospace",
                  }}
                >
                  {user.tenant_id}
                </code>
              </div>
            )}

            <div className="info-row">
              <span className="info-label">Account Status</span>
              <span className="status-pill active">
                <CheckCircle2 size={12} /> {user?.is_active ? "Active & Authorized" : "Inactive"}
              </span>
            </div>

            <div className="info-row">
              <span className="info-label">Privilege Level</span>
              <strong className="info-val" style={{ color: "var(--accent)" }}>
                Executive Root Control (Rank {user?.rank_level ?? 1})
              </strong>
            </div>

            {user?.created_at && (
              <div className="info-row">
                <span className="info-label">Account Registered</span>
                <span className="info-val" style={{ fontSize: "13px", color: "var(--text-muted)" }}>
                  <Clock size={12} style={{ display: "inline", marginRight: "4px" }} />
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
        <section className="settings-card">
          <div className="card-head">
            <Key size={18} />
            <h3>Change Password</h3>
          </div>
          <div className="card-body">
            <p style={{ fontSize: "13px", color: "var(--text-muted)", marginBottom: "16px" }}>
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
              <div className="form-group">
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", marginBottom: "6px" }}>
                  Current Password
                </label>
                <div style={{ position: "relative" }}>
                  <input
                    type={showCurrentPassword ? "text" : "password"}
                    className="input-field"
                    placeholder="Enter your current password"
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
                  >
                    {showCurrentPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>

              {/* New Password */}
              <div className="form-group">
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", marginBottom: "6px" }}>
                  New Password
                </label>
                <div style={{ position: "relative" }}>
                  <input
                    type={showNewPassword ? "text" : "password"}
                    className="input-field"
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
                  >
                    {showNewPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                  </button>
                </div>
              </div>

              {/* Confirm New Password */}
              <div className="form-group">
                <label style={{ display: "block", fontSize: "13px", fontWeight: "600", marginBottom: "6px" }}>
                  Confirm New Password
                </label>
                <input
                  type="password"
                  className="input-field"
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
                  className="btn btn-primary"
                  disabled={loading}
                  style={{ display: "flex", alignItems: "center", gap: "8px" }}
                >
                  <Lock size={16} />
                  <span>{loading ? "Updating Password..." : "Update Password"}</span>
                </button>
              </div>
            </form>
          </div>
        </section>
      </div>
    </div>
  );
}

