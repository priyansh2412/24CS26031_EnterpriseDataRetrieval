import { useState } from "react";
import { UserProfile, request } from "../api";
import { UserCheck, Shield, Key, CheckCircle, AlertCircle, Building, Mail, Hash } from "lucide-react";

interface ProfilePageProps {
  user: UserProfile | null;
  onProfileUpdated?: () => void;
}

export default function ProfilePage({ user, onProfileUpdated }: ProfilePageProps) {
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [feedback, setFeedback] = useState<{ type: "success" | "error"; message: string } | null>(null);

  const handleChangePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setFeedback(null);

    if (newPassword.length < 6) {
      setFeedback({ type: "error", message: "New password must be at least 6 characters long." });
      return;
    }

    if (newPassword !== confirmPassword) {
      setFeedback({ type: "error", message: "New passwords do not match." });
      return;
    }

    setLoading(true);
    try {
      await request("/api/auth/change-password", {
        method: "POST",
        body: JSON.stringify({
          current_password: currentPassword,
          new_password: newPassword,
        }),
      });

      setFeedback({ type: "success", message: "Password updated successfully!" });
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      if (onProfileUpdated) {
        onProfileUpdated();
      }
    } catch (err: any) {
      setFeedback({ type: "error", message: err.message || "Failed to update password." });
    } finally {
      setLoading(false);
    }
  };

  const userRole = user?.role_key || user?.role || "employee";

  return (
    <div className="profile-page animate-fade-in" style={{ maxWidth: "800px", margin: "0 auto", paddingBottom: "60px" }}>
      <header className="page-heading" style={{ marginBottom: "24px" }}>
        <div>
          <div className="eyebrow" style={{ display: "flex", alignItems: "center", gap: "6px", color: "#2563eb", fontWeight: "700" }}>
            <UserCheck size={14} /> EMPLOYEE ACCOUNT & SECURITY
          </div>
          <h1 style={{ fontSize: "28px", fontWeight: "800", color: "#0f172a", margin: "6px 0" }}>User Profile</h1>
          <p className="subheading" style={{ color: "#64748b", fontSize: "14px", margin: 0 }}>
            Manage your authenticated account identity, organizational rank, and credentials.
          </p>
        </div>
      </header>

      {/* Account Details Card */}
      <div className="dash-module-card" style={{ padding: "28px", marginBottom: "24px" }}>
        <h3 style={{ margin: "0 0 18px", fontSize: "17px", fontWeight: "700" }}>Account Identity</h3>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "16px" }}>
          <div style={{ padding: "14px", borderRadius: "8px", background: "#f8fafc", border: "1px solid #e2e8f0" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "#64748b", fontSize: "12px", marginBottom: "4px" }}>
              <Mail size={13} /> Email Address
            </div>
            <strong style={{ fontSize: "14px", color: "#0f172a" }}>{user?.email || "Unknown"}</strong>
          </div>

          <div style={{ padding: "14px", borderRadius: "8px", background: "#f8fafc", border: "1px solid #e2e8f0" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "#64748b", fontSize: "12px", marginBottom: "4px" }}>
              <Shield size={13} /> Organizational Role
            </div>
            <strong style={{ fontSize: "14px", color: "#0f172a", textTransform: "capitalize" }}>{userRole}</strong>
          </div>

          <div style={{ padding: "14px", borderRadius: "8px", background: "#f8fafc", border: "1px solid #e2e8f0" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "#64748b", fontSize: "12px", marginBottom: "4px" }}>
              <Hash size={13} /> Rank Level
            </div>
            <strong style={{ fontSize: "14px", color: "#0f172a" }}>Rank {user?.rank_level ?? 5}</strong>
          </div>

          <div style={{ padding: "14px", borderRadius: "8px", background: "#f8fafc", border: "1px solid #e2e8f0" }}>
            <div style={{ display: "flex", alignItems: "center", gap: "6px", color: "#64748b", fontSize: "12px", marginBottom: "4px" }}>
              <Building size={13} /> Enterprise Workspace
            </div>
            <strong style={{ fontSize: "14px", color: "#0f172a" }}>{user?.enterprise_name || "Atlas Enterprise"}</strong>
          </div>
        </div>
      </div>

      {/* Change Password Card */}
      <div className="dash-module-card" style={{ padding: "28px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "16px" }}>
          <Key size={18} style={{ color: "#2563eb" }} />
          <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "700" }}>Change Password</h3>
        </div>

        {feedback && (
          <div className={`alert-banner ${feedback.type} margin-bottom`}>
            {feedback.type === "success" ? <CheckCircle size={16} /> : <AlertCircle size={16} />}
            <span>{feedback.message}</span>
          </div>
        )}

        <form onSubmit={handleChangePassword}>
          <div style={{ marginBottom: "16px" }}>
            <label style={{ display: "block", fontSize: "13px", fontWeight: "600", marginBottom: "6px", color: "#334155" }}>
              Current Password
            </label>
            <input
              type="password"
              className="input-field"
              value={currentPassword}
              onChange={(e) => setCurrentPassword(e.target.value)}
              required
              placeholder="Enter your current password"
              style={{ width: "100%", padding: "10px 14px", borderRadius: "8px", border: "1px solid #cbd5e1" }}
            />
          </div>

          <div style={{ marginBottom: "16px" }}>
            <label style={{ display: "block", fontSize: "13px", fontWeight: "600", marginBottom: "6px", color: "#334155" }}>
              New Password
            </label>
            <input
              type="password"
              className="input-field"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              required
              minLength={6}
              placeholder="At least 6 characters"
              style={{ width: "100%", padding: "10px 14px", borderRadius: "8px", border: "1px solid #cbd5e1" }}
            />
          </div>

          <div style={{ marginBottom: "22px" }}>
            <label style={{ display: "block", fontSize: "13px", fontWeight: "600", marginBottom: "6px", color: "#334155" }}>
              Confirm New Password
            </label>
            <input
              type="password"
              className="input-field"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              required
              minLength={6}
              placeholder="Repeat your new password"
              style={{ width: "100%", padding: "10px 14px", borderRadius: "8px", border: "1px solid #cbd5e1" }}
            />
          </div>

          <button
            type="submit"
            className="btn-primary"
            disabled={loading}
            style={{ padding: "10px 22px", fontSize: "14px" }}
          >
            {loading ? "Updating Password..." : "Update Password"}
          </button>
        </form>
      </div>
    </div>
  );
}
