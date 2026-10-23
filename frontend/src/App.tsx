import { useEffect, useState } from "react";
import {
  Building2,
  BarChart3,
  Files,
  LogOut,
  MessageSquare,
  ShieldCheck,
  LayoutDashboard,
  Users,
  Activity,
  Settings,
  AlertCircle,
  Sun,
  Moon,
  FolderKanban,
  UserCheck,
  MessageCircle,
  Menu,
  X,
  Sparkles,
} from "lucide-react";
import ChatPage from "./pages/ChatPage";
import DocumentsPage from "./pages/DocumentsPage";
import AnalyticsPage from "./pages/AnalyticsPage";
import LoginPage from "./pages/LoginPage";
import HomePage from "./pages/HomePage";
import DashboardPage from "./pages/DashboardPage";
import UserManagementPage from "./pages/UserManagementPage";
import AuditLogsPage from "./pages/AuditLogsPage";
import SettingsPage from "./pages/SettingsPage";
import SetupWizardPage from "./pages/SetupWizardPage";
import TeamsPage from "./pages/TeamsPage";
import ProfilePage from "./pages/ProfilePage";
import LinkedDevicesPage from "./pages/LinkedDevicesPage";
import SystemEnterprisePortal from "./pages/SystemEnterprisePortal";
import { SetupStatus, UserProfile, request, token, clearAuthToken } from "./api";

type NavRoute = {
  id: string;
  path: string;
  label: string;
  icon: any;
  roles?: string[];
  hideForAdmin?: boolean;
};

const NAV_ITEMS: NavRoute[] = [
  { id: "dashboard", path: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { id: "chat", path: "/chat", label: "AI Search Sessions", icon: MessageSquare },
  { id: "teams", path: "/teams", label: "Team Workspaces", icon: FolderKanban, hideForAdmin: true },
  { id: "documents", path: "/documents", label: "Knowledge Library", icon: Files },
  { id: "analytics", path: "/analytics", label: "Analytics & Insights", icon: BarChart3, roles: ["admin", "hr", "manager", "finance"] },
  { id: "users", path: "/users", label: "User Management", icon: Users },
  { id: "audit-logs", path: "/audit-logs", label: "Hierarchical Audit Logs", icon: Activity },
  { id: "linked-devices", path: "/linked-devices", label: "Linked WhatsApp Devices", icon: MessageCircle },
  { id: "settings", path: "/settings", label: "Workspace Settings", icon: Settings },
  { id: "profile", path: "/profile", label: "Admin Profile", icon: UserCheck },
];

export default function App() {
  const [setupInitialized, setSetupInitialized] = useState<boolean | null>(null);
  const [authenticated, setAuthenticated] = useState(Boolean(token()));
  const [user, setUser] = useState<UserProfile | null>(null);
  const [currentPath, setCurrentPath] = useState(window.location.pathname || "/dashboard");
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [theme, setTheme] = useState<"light" | "dark">(() => {
    return (localStorage.getItem("rag_theme") as "light" | "dark") || "light";
  });

  // 1. Check system setup initialization status on app load
  const checkSetupStatus = () => {
    request<SetupStatus>("/api/setup/status")
      .then((status) => {
        setSetupInitialized(status.is_initialized);
      })
      .catch(() => {
        setSetupInitialized(true);
      });
  };

  const fetchUserProfile = () => {
    if (authenticated) {
      request<UserProfile>("/api/auth/me")
        .then((userData) => {
          setUser(userData);
          if (window.location.pathname === "/" || window.location.pathname === "") {
            navigate("/dashboard");
          }
        })
        .catch(() => {
          clearAuthToken();
          setAuthenticated(false);
        });
    }
  };

  useEffect(() => {
    checkSetupStatus();
  }, []);

  useEffect(() => {
    localStorage.setItem("rag_theme", theme);
    document.body.className = `${theme}-theme`;
  }, [theme]);

  const toggleTheme = () => {
    setTheme((prev) => (prev === "light" ? "dark" : "light"));
  };

  // Sync state with authentication & fetch user profile
  useEffect(() => {
    if (authenticated && setupInitialized) {
      fetchUserProfile();
    }
  }, [authenticated, setupInitialized]);

  // Handle browser back/forward buttons
  useEffect(() => {
    const handlePopState = () => {
      setCurrentPath(window.location.pathname || "/dashboard");
    };
    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  const navigate = (path: string) => {
    window.history.pushState({}, "", path);
    setCurrentPath(path);
    setSidebarOpen(false);
  };

  // Direct standalone route for /enterprises System Portal
  if (currentPath === "/enterprises" || window.location.pathname === "/enterprises") {
    return <SystemEnterprisePortal theme={theme} onToggleTheme={toggleTheme} />;
  }

  // Render Setup Wizard if system onboarding setup is required
  if (setupInitialized === false) {
    return (
      <SetupWizardPage
        onSetupCompleted={() => {
          setSetupInitialized(true);
        }}
      />
    );
  }

  if (!authenticated) {
    return (
      <HomePage
        onSuccess={() => {
          setAuthenticated(true);
          fetchUserProfile();
        }}
        theme={theme}
        onToggleTheme={toggleTheme}
      />
    );
  }

  if (currentPath === "/home") {
    return (
      <HomePage
        onSuccess={() => navigate("/dashboard")}
        theme={theme}
        onToggleTheme={toggleTheme}
      />
    );
  }

  const userRole = user?.role_key || user?.role || "employee";
  const userRank = user?.rank_level ?? 5;
  const isAdmin = user?.role === "admin" || userRank === 1;

  // Filter navigation items by role access:
  // For Rank 1 (Admin):
  //   - Dashboard, AI Search Sessions, Knowledge Library, Analytics & Insights, User Management, Hierarchical Audit Logs, Workspace Settings, Admin Profile
  //   - Team Workspaces is hidden for Admin
  // For Ranks other than 1 (Rank 2, 3, 4, etc.):
  //   - Strictly only 4 tabs: 1. Dashboard, 2. AI Search Sessions, 3. Team Workspaces, 4. My Profile
  const isSuperAdmin = user?.email === "system@gmailexample.com" || (user?.rank_level ?? 5) === 0 || user?.role_key === "system_admin";

  const allowedNav = NAV_ITEMS.filter((item) => {
    if (isAdmin) {
      if (item.hideForAdmin) return false;
      return true;
    } else {
      return ["dashboard", "chat", "teams", "linked-devices", "profile"].includes(item.id);
    }
  }).map((item) => {
    if (item.id === "profile") {
      return {
        ...item,
        label: isAdmin ? "Admin Profile" : "My Profile",
      };
    }
    return item;
  });

  if (isSuperAdmin && !allowedNav.some((i) => i.id === "enterprises")) {
    allowedNav.unshift({
      id: "enterprises",
      path: "/enterprises",
      label: "Enterprise Gateway",
      icon: Building2,
    });
  }

  const activeNavItem = NAV_ITEMS.find((item) => item.path === currentPath);
  const isAuthorized = isAdmin
    ? currentPath !== "/teams"
    : ["/dashboard", "/chat", "/teams", "/linked-devices", "/profile", "/"].includes(currentPath);

  return (
    <main className={`app-shell ${theme}-theme`}>
      {/* Decorative blurred background ambient blobs */}
      <div className="ambient-bg-glow ambient-blob-1" />
      <div className="ambient-bg-glow ambient-blob-2" />

      {/* Mobile Backdrop Overlay */}
      <div
        className={`sidebar-backdrop ${sidebarOpen ? "mobile-open" : ""}`}
        onClick={() => setSidebarOpen(false)}
        aria-hidden="true"
      />

      {/* Modern B2B SaaS Sidebar */}
      <aside className={`sidebar ${sidebarOpen ? "mobile-open" : ""}`}>
        <div className="sidebar-top">
          <div className="brand-mark">
            <ShieldCheck size={22} />
          </div>
          <div className="brand-copy">
            <strong>Atlas Enterprise</strong>
            <span>{user?.enterprise_name || "Knowledge Workspace"}</span>
          </div>
          <button
            className="btn-icon mobile-menu-btn"
            style={{ marginLeft: "auto", display: sidebarOpen ? "grid" : "none" }}
            onClick={() => setSidebarOpen(false)}
            title="Close navigation"
          >
            <X size={18} />
          </button>
        </div>

        <div className="workspace-label">
          <span>NAVIGATION MODULES</span>
          <i />
        </div>

        <nav className="sidebar-nav">
          {allowedNav.map((item) => {
            const isActive = currentPath === item.path;
            const Icon = item.icon;
            return (
              <button
                key={item.id}
                className={`nav-item ${isActive ? "active" : ""}`}
                onClick={() => navigate(item.path)}
              >
                <Icon size={18} />
                <span>{item.label}</span>
              </button>
            );
          })}
        </nav>

        <div className="sidebar-bottom">
          <div className="secure-note">
            <ShieldCheck size={15} />
            <span>Grounded Enterprise RAG (v2.4)</span>
          </div>

          <div
            className="profile-card"
            onClick={() => navigate("/profile")}
            style={{ cursor: "pointer" }}
            title="Click to view Profile & Security Settings"
          >
            <div className="avatar">{user?.email?.[0]?.toUpperCase() || "A"}</div>
            <div className="profile-details">
              <span className="profile-name">{user?.email?.split("@")[0] || "User"}</span>
              <span className="role-badge">
                Rank {user?.rank_level ?? 5}: {userRole}
              </span>
            </div>
            <button
              onClick={(e) => {
                e.stopPropagation();
                clearAuthToken();
                setAuthenticated(false);
              }}
              title="Sign Out"
              aria-label="Sign Out"
              className="sign-out-btn"
            >
              <LogOut size={16} />
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content View Container */}
      <div className="app-main-wrapper">
        {/* Top Enterprise Navigation Header */}
        <header className="top-nav-bar">
          <div className="top-nav-left">
            <button
              className="mobile-menu-btn"
              onClick={() => setSidebarOpen(true)}
              title="Open Navigation"
              aria-label="Open Navigation"
            >
              <Menu size={20} />
            </button>

            <div className="breadcrumb">
              <span onClick={() => navigate("/home")} style={{ cursor: "pointer", transition: "color 0.15s" }} title="View Homepage & Features">Atlas</span>
              <span className="sep">/</span>
              <strong className="current-page-title">
                {activeNavItem ? activeNavItem.label : "Dashboard"}
              </strong>
            </div>
          </div>

          <div className="top-nav-right-actions">
            <button
              className="theme-toggle-btn"
              onClick={toggleTheme}
              title={`Switch to ${theme === "light" ? "Dark" : "Light"} Theme`}
            >
              {theme === "light" ? <Moon size={14} /> : <Sun size={14} />}
              <span>{theme === "light" ? "Dark" : "Light"}</span>
            </button>

            <div
              className="top-user-pill"
              onClick={() => navigate("/profile")}
              style={{ cursor: "pointer" }}
              title="Click to view Profile"
            >
              <span className="role-badge">RANK {user?.rank_level ?? 5}</span>
              <span className="user-email-tag">{user?.email}</span>
            </div>
          </div>
        </header>

        <section className={`app-content ${currentPath === "/chat" ? "chat-mode" : ""} ${currentPath === "/teams" ? "teams-mode" : ""}`}>
          {!isAuthorized && (
            <div className="alert-banner error margin-bottom">
              <AlertCircle size={16} />
              <span>Insufficient privileges to access {currentPath}. Redirected to Dashboard.</span>
            </div>
          )}

          {(!isAuthorized || currentPath === "/dashboard" || currentPath === "/") && (
            <DashboardPage user={user} onNavigate={navigate} />
          )}

          {currentPath === "/chat" && <ChatPage />}

          {currentPath === "/teams" && !isAdmin && <TeamsPage currentUser={user} />}

          {currentPath === "/teams" && isAdmin && (
            <div className="alert-banner info">
              <AlertCircle size={16} />
              <span>Team Workspaces module is designated for team members and project collaborators.</span>
            </div>
          )}

          {currentPath === "/documents" && <DocumentsPage />}

          {currentPath === "/analytics" && isAuthorized && <AnalyticsPage />}

          {currentPath === "/users" && <UserManagementPage currentUser={user} />}

          {currentPath === "/audit-logs" && <AuditLogsPage />}

          {currentPath === "/linked-devices" && isAuthorized && <LinkedDevicesPage />}

          {currentPath === "/settings" && <SettingsPage user={user} />}

          {currentPath === "/profile" && <ProfilePage user={user} onProfileUpdated={fetchUserProfile} />}
        </section>
      </div>
    </main>
  );
}
