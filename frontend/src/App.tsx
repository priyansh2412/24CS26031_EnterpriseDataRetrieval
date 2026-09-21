import { useEffect, useState } from "react";
import {
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
} from "lucide-react";
import ChatPage from "./pages/ChatPage";
import DocumentsPage from "./pages/DocumentsPage";
import AnalyticsPage from "./pages/AnalyticsPage";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import UserManagementPage from "./pages/UserManagementPage";
import AuditLogsPage from "./pages/AuditLogsPage";
import SettingsPage from "./pages/SettingsPage";
import { request, token } from "./api";

export type User = { id: number; email: string; role: string };

type NavRoute = {
  id: string;
  path: string;
  label: string;
  icon: any;
  roles?: string[];
};

const NAV_ITEMS: NavRoute[] = [
  { id: "dashboard", path: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { id: "chat", path: "/chat", label: "AI Search Assistant", icon: MessageSquare },
  { id: "documents", path: "/documents", label: "Knowledge Library", icon: Files },
  { id: "analytics", path: "/analytics", label: "Analytics & Insights", icon: BarChart3, roles: ["admin", "hr", "manager", "finance"] },
  { id: "users", path: "/users", label: "User Management", icon: Users, roles: ["admin"] },
  { id: "audit-logs", path: "/audit-logs", label: "Security Audit Logs", icon: Activity, roles: ["admin"] },
  { id: "settings", path: "/settings", label: "Workspace Settings", icon: Settings },
];

export default function App() {
  const [authenticated, setAuthenticated] = useState(Boolean(token()));
  const [user, setUser] = useState<User | null>(null);
  const [currentPath, setCurrentPath] = useState(window.location.pathname || "/dashboard");
  const [theme, setTheme] = useState<"light" | "dark">(() => {
    return (localStorage.getItem("rag_theme") as "light" | "dark") || "light";
  });

  useEffect(() => {
    localStorage.setItem("rag_theme", theme);
  }, [theme]);

  const toggleTheme = () => {
    setTheme((prev) => (prev === "light" ? "dark" : "light"));
  };

  // Sync state with authentication & fetch user profile
  useEffect(() => {
    if (authenticated) {
      request<User>("/api/auth/me")
        .then((userData) => {
          setUser(userData);
          // Default root path redirect to /dashboard
          if (window.location.pathname === "/" || window.location.pathname === "") {
            navigate("/dashboard");
          }
        })
        .catch(() => {
          localStorage.removeItem("rag_token");
          setAuthenticated(false);
        });
    }
  }, [authenticated]);

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
  };

  if (!authenticated) {
    return <LoginPage onSuccess={() => setAuthenticated(true)} />;
  }

  const userRole = user?.role || "employee";

  // Filter navigation items by role access
  const allowedNav = NAV_ITEMS.filter((item) => {
    if (!item.roles) return true;
    return item.roles.includes(userRole);
  });

  // Verify route authorization for direct URL entries
  const activeNavItem = NAV_ITEMS.find((item) => item.path === currentPath);
  const isAuthorized = !activeNavItem?.roles || activeNavItem.roles.includes(userRole);

  return (
    <main className={`app-shell ${theme}-theme`}>
      {/* Enterprise Sidebar */}
      <aside className="sidebar">
        <div className="sidebar-top">
          <div className="brand-mark">
            <ShieldCheck size={20} />
          </div>
          <div className="brand-copy">
            <strong>Atlas Enterprise</strong>
            <span>Knowledge Workspace</span>
          </div>
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
            <ShieldCheck size={16} />
            <span>Grounded Retrieval Augmented Generation (RAG)</span>
          </div>

          <div className="profile">
            <div className="avatar">{user?.email?.[0]?.toUpperCase() || "A"}</div>
            <div className="profile-details">
              <strong>{user?.email?.split("@")[0] || "User"}</strong>
              <span className={`role-badge ${userRole}`}>{userRole}</span>
            </div>
            <button
              onClick={() => {
                localStorage.removeItem("rag_token");
                setAuthenticated(false);
              }}
              title="Sign Out"
              aria-label="Sign Out"
              className="sign-out-btn"
            >
              <LogOut size={17} />
            </button>
          </div>
        </div>
      </aside>

      {/* Main Content View Container */}
      <div className="app-main-wrapper">
        {/* Top Enterprise Navigation Header */}
        <header className="top-nav-bar">
          <div className="breadcrumb">
            <span>Atlas</span>
            <span className="sep">/</span>
            <strong className="current-page-title">
              {activeNavItem ? activeNavItem.label : "Dashboard"}
            </strong>
          </div>

          <div className="top-nav-right-actions">
            <button
              className="theme-toggle-btn"
              onClick={toggleTheme}
              title={`Switch to ${theme === "light" ? "Dark Black" : "Light"} Theme`}
            >
              {theme === "light" ? <Moon size={15} /> : <Sun size={15} />}
              <span>{theme === "light" ? "Dark Theme" : "Light Theme"}</span>
            </button>

            <div className="top-user-pill">
              <span className={`role-badge ${userRole}`}>{userRole.toUpperCase()}</span>
              <span className="user-email-tag">{user?.email}</span>
            </div>
          </div>
        </header>

        <section className={`app-content ${currentPath === "/chat" ? "chat-mode" : ""}`}>
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

          {currentPath === "/documents" && <DocumentsPage />}

          {currentPath === "/analytics" && isAuthorized && <AnalyticsPage />}

          {currentPath === "/users" && isAuthorized && <UserManagementPage />}

          {currentPath === "/audit-logs" && isAuthorized && <AuditLogsPage />}

          {currentPath === "/settings" && <SettingsPage user={user} />}
        </section>
      </div>
    </main>
  );
}

