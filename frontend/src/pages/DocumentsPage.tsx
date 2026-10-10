import { useEffect, useState } from "react";
import {
  FileText,
  RefreshCw,
  Search,
  Sparkles,
  Trash2,
  Shield,
  CheckCircle,
  Clock,
  Layers,
  Folder,
  ExternalLink,
  Plus,
  UserX,
  Check,
  X,
  AlertCircle,
  ChevronDown,
  ChevronRight,
  FolderOpen,
} from "lucide-react";
import {
  CompanyRoleItem,
  DocumentItem,
  EnterpriseDriveLinkItem,
  UserItem,
  request,
} from "../api";

export default function DocumentsPage() {
  const [docs, setDocs] = useState<DocumentItem[]>([]);
  const [driveLinks, setDriveLinks] = useState<EnterpriseDriveLinkItem[]>([]);
  const [roles, setRoles] = useState<CompanyRoleItem[]>([]);
  const [employees, setEmployees] = useState<UserItem[]>([]);
  const [search, setSearch] = useState("");
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeId, setActiveId] = useState<string | null>(null);

  // Add Google Drive Link Input State (Clean single input box in section)
  const [driveUrl, setDriveUrl] = useState("");
  const [connectingDrive, setConnectingDrive] = useState(false);

  // Folder collapse / dropdown state (map of folder path to boolean open)
  const [expandedFolders, setExpandedFolders] = useState<Record<string, boolean>>({});

  // Manage Access Modal State
  const [editingDoc, setEditingDoc] = useState<DocumentItem | null>(null);
  const [selectedRoles, setSelectedRoles] = useState<string[]>([]);
  const [deniedUsers, setDeniedUsers] = useState<string[]>([]);
  const [applyToFolder, setApplyToFolder] = useState(false);
  const [updatingAccess, setUpdatingAccess] = useState(false);
  const [employeeSearch, setEmployeeSearch] = useState("");

  const loadDocs = async (term = search) => {
    try {
      const data = await request<DocumentItem[]>(
        `/api/documents${term ? `?search=${encodeURIComponent(term)}` : ""}`
      );
      setDocs(data);
    } catch (e: any) {
      console.warn("Could not load documents:", e);
    }
  };

  const loadDriveLinks = async () => {
    try {
      const data = await request<EnterpriseDriveLinkItem[]>("/api/drive-links");
      setDriveLinks(data);
    } catch (e: any) {
      console.warn("Could not load drive links:", e);
    }
  };

  const loadRoles = async () => {
    try {
      const data = await request<CompanyRoleItem[]>("/api/setup/roles");
      setRoles(data);
    } catch (e: any) {
      console.warn("Could not load roles:", e);
    }
  };

  const loadEmployees = async () => {
    try {
      const data = await request<UserItem[]>("/api/users");
      setEmployees(data);
    } catch (e: any) {
      console.warn("Could not load employees:", e);
    }
  };

  useEffect(() => {
    setLoading(true);
    Promise.all([loadDocs(""), loadDriveLinks(), loadRoles(), loadEmployees()]).finally(() => {
      setLoading(false);
    });
  }, []);

  // Set default open state for folders when docs change
  useEffect(() => {
    const initialExpanded: Record<string, boolean> = {};
    docs.forEach((d) => {
      const folder = d.folder_path || "/";
      if (initialExpanded[folder] === undefined) {
        initialExpanded[folder] = true; // default expand
      }
    });
    setExpandedFolders((prev) => ({ ...initialExpanded, ...prev }));
  }, [docs]);

  const toggleFolder = (folderPath: string) => {
    setExpandedFolders((prev) => ({
      ...prev,
      [folderPath]: !prev[folderPath],
    }));
  };

  // Connect & Ingest Google Drive Link
  const handleAddDriveLink = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanUrl = driveUrl.trim();
    if (!cleanUrl) {
      setMessage({ type: "error", text: "Please paste a valid Google Drive URL." });
      return;
    }

    setConnectingDrive(true);
    setMessage(null);

    try {
      const newLink = await request<EnterpriseDriveLinkItem>("/api/drive-links", {
        method: "POST",
        body: JSON.stringify({
          drive_url: cleanUrl,
        }),
      });

      setDriveLinks((prev) => [newLink, ...prev.filter((l) => l.id !== newLink.id)]);
      setMessage({
        type: "success",
        text: `Google Drive source '${newLink.name}' connected! Documents and folder contents ingested successfully.`,
      });
      setDriveUrl("");
      await loadDocs("");
      await loadDriveLinks();
    } catch (err: any) {
      setMessage({ type: "error", text: err?.message || "Failed to connect and ingest Google Drive link." });
    } finally {
      setConnectingDrive(false);
    }
  };

  // Sync Drive Link
  const handleSyncDriveLink = async (link: EnterpriseDriveLinkItem) => {
    setMessage(null);
    try {
      const updated = await request<EnterpriseDriveLinkItem>(`/api/drive-links/${link.id}/sync`, {
        method: "POST",
      });
      setDriveLinks((prev) => prev.map((l) => (l.id === updated.id ? updated : l)));
      setMessage({ type: "success", text: `Google Drive source '${link.name}' re-synchronized.` });
      await loadDocs("");
    } catch (err: any) {
      setMessage({ type: "error", text: err?.message || "Failed to sync Google Drive link." });
    }
  };

  // Delete Drive Link
  const handleDeleteDriveLink = async (linkId: number, linkName: string) => {
    if (!window.confirm(`Are you sure you want to disconnect '${linkName}' and remove its documents?`))
      return;
    setMessage(null);
    try {
      await request(`/api/drive-links/${linkId}`, { method: "DELETE" });
      setDriveLinks((prev) => prev.filter((l) => l.id !== linkId));
      setMessage({ type: "success", text: `Google Drive source '${linkName}' removed.` });
      await loadDocs("");
    } catch (err: any) {
      setMessage({ type: "error", text: err?.message || "Failed to remove Google Drive link." });
    }
  };

  // Document Actions (re-index, summarize, delete)
  async function docAction(path: string, method = "POST", docId?: string) {
    setActiveId(docId ?? null);
    setMessage(null);
    try {
      const updated = await request<DocumentItem>(path, { method });
      if (method === "DELETE") {
        setDocs((items) => items.filter((doc) => doc.id !== docId));
        setMessage({ type: "success", text: "Document removed from knowledge library." });
      } else {
        setDocs((items) => items.map((doc) => (doc.id === updated.id ? updated : doc)));
        setMessage({
          type: "success",
          text: path.endsWith("/summary")
            ? "AI summary generated successfully."
            : "Document re-indexed successfully.",
        });
      }
    } catch (e: any) {
      setMessage({ type: "error", text: e?.message || "Operation failed" });
    } finally {
      setActiveId(null);
    }
  }

  // Open Manage Access Modal
  const openAccessModal = (doc: DocumentItem) => {
    setEditingDoc(doc);
    setApplyToFolder(false);
    setEmployeeSearch("");

    try {
      const parsedRoles = JSON.parse(doc.access_roles || "[]");
      setSelectedRoles(Array.isArray(parsedRoles) ? parsedRoles : ["admin", "hr", "finance", "manager", "employee"]);
    } catch {
      setSelectedRoles(["admin", "hr", "finance", "manager", "employee"]);
    }

    try {
      const parsedDenied = JSON.parse(doc.denied_users || "[]");
      setDeniedUsers(Array.isArray(parsedDenied) ? parsedDenied : []);
    } catch {
      setDeniedUsers([]);
    }
  };

  const toggleRole = (rKey: string) => {
    const lowerKey = rKey.toLowerCase();
    if (selectedRoles.includes(lowerKey)) {
      if (selectedRoles.length === 1) return;
      setSelectedRoles(selectedRoles.filter((item) => item !== lowerKey));
    } else {
      setSelectedRoles([...selectedRoles, lowerKey]);
    }
  };

  const toggleDenyUser = (userEmail: string) => {
    const cleanEmail = userEmail.toLowerCase();
    if (deniedUsers.includes(cleanEmail)) {
      setDeniedUsers(deniedUsers.filter((u) => u !== cleanEmail));
    } else {
      setDeniedUsers([...deniedUsers, cleanEmail]);
    }
  };

  const saveAccessPermissions = async () => {
    if (!editingDoc) return;
    setUpdatingAccess(true);
    setMessage(null);

    try {
      const updated = await request<DocumentItem>(`/api/documents/${editingDoc.id}/access`, {
        method: "PUT",
        body: JSON.stringify({
          roles: selectedRoles,
          denied_users: deniedUsers,
          apply_to_folder: applyToFolder,
        }),
      });

      setDocs((items) =>
        items.map((d) => {
          if (d.id === updated.id) return updated;
          if (applyToFolder && d.folder_path === editingDoc.folder_path) {
            return {
              ...d,
              access_roles: updated.access_roles,
              denied_users: updated.denied_users,
            };
          }
          return d;
        })
      );

      setMessage({
        type: "success",
        text: `Permissions & Qdrant ACL vector payloads updated for '${editingDoc.name}'${
          applyToFolder ? ` and folder '${editingDoc.folder_path || "/"}'` : ""
        }!`,
      });
      setEditingDoc(null);
    } catch (e: any) {
      setMessage({ type: "error", text: e?.message || "Failed to update access permissions." });
    } finally {
      setUpdatingAccess(false);
    }
  };

  // Group documents by folder path for hierarchical tree/dropdown display
  const filteredDocs = docs.filter((d) => {
    if (!search.trim()) return true;
    return d.name.toLowerCase().includes(search.toLowerCase());
  });

  const docsByFolder: Record<string, DocumentItem[]> = {};
  filteredDocs.forEach((d) => {
    const folder = d.folder_path || "/";
    if (!docsByFolder[folder]) {
      docsByFolder[folder] = [];
    }
    docsByFolder[folder].push(d);
  });

  const folderKeys = Object.keys(docsByFolder).sort();

  const relevantEmployees = employees.filter((emp) => {
    const empRole = (emp.role_key || emp.role || "employee").toLowerCase();
    const matchesRole = selectedRoles.includes(empRole) || empRole === "employee" || empRole === "admin";
    if (!matchesRole) return false;
    if (employeeSearch.trim()) {
      const q = employeeSearch.toLowerCase();
      return (
        emp.email.toLowerCase().includes(q) ||
        (emp.display_name && emp.display_name.toLowerCase().includes(q))
      );
    }
    return true;
  });

  const totalChunks = docs.reduce((acc, cur) => acc + (cur.chunk_count || 0), 0);
  const readyCount = docs.filter((d) => d.status === "ready").length;

  return (
    <div className="documents-page" style={{ padding: "0 4px" }}>
      {/* Header */}
      <header className="page-heading" style={{ marginBottom: "24px" }}>
        <div>
          <div className="eyebrow" style={{ display: "flex", alignItems: "center", gap: "6px", color: "#2563eb", fontWeight: "700" }}>
            <FileText size={14} /> KNOWLEDGE LIBRARY & MULTI-TENANT DOCUMENT STORAGE
          </div>
          <h1 style={{ fontSize: "28px", fontWeight: "800", color: "#0f172a", margin: "6px 0" }}>Enterprise Document Storage</h1>
          <p className="subheading" style={{ color: "#64748b", fontSize: "14px", margin: 0 }}>
            Connect Google Drive links to automatically ingest documents, browse folders, and manage fine-grained access permissions.
          </p>
        </div>
      </header>

      {/* Global Alerts */}
      {message && (
        <div
          className={`alert-banner ${message.type}`}
          style={{
            marginBottom: "20px",
            padding: "12px 16px",
            borderRadius: "8px",
            display: "flex",
            alignItems: "center",
            gap: "10px",
            background: message.type === "success" ? "#ecfdf5" : "#fef2f2",
            color: message.type === "success" ? "#065f46" : "#991b1b",
            border: `1px solid ${message.type === "success" ? "#a7f3d0" : "#fecaca"}`,
          }}
        >
          {message.type === "success" ? <CheckCircle size={18} /> : <AlertCircle size={18} />}
          <span style={{ fontSize: "14px", fontWeight: "500" }}>{message.text}</span>
        </div>
      )}

      {/* Summary Metrics Counter */}
      <section className="library-summary-cards" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "16px", marginBottom: "24px" }}>
        <div className="summary-stat-card" style={{ background: "#ffffff", padding: "18px 20px", borderRadius: "12px", border: "1px solid #e2e8f0", display: "flex", alignItems: "center", gap: "14px" }}>
          <div className="stat-icon icon-blue" style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#eff6ff", color: "#2563eb", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <FileText size={22} />
          </div>
          <div>
            <strong className="stat-number" style={{ fontSize: "22px", fontWeight: "800", color: "#0f172a", display: "block" }}>{docs.length}</strong>
            <span className="stat-label" style={{ fontSize: "12px", color: "#64748b" }}>Ingested Documents</span>
          </div>
        </div>

        <div className="summary-stat-card" style={{ background: "#ffffff", padding: "18px 20px", borderRadius: "12px", border: "1px solid #e2e8f0", display: "flex", alignItems: "center", gap: "14px" }}>
          <div className="stat-icon icon-indigo" style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#eef2ff", color: "#4f46e5", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Layers size={22} />
          </div>
          <div>
            <strong className="stat-number" style={{ fontSize: "22px", fontWeight: "800", color: "#0f172a", display: "block" }}>{totalChunks}</strong>
            <span className="stat-label" style={{ fontSize: "12px", color: "#64748b" }}>Searchable Passages</span>
          </div>
        </div>

        <div className="summary-stat-card" style={{ background: "#ffffff", padding: "18px 20px", borderRadius: "12px", border: "1px solid #e2e8f0", display: "flex", alignItems: "center", gap: "14px" }}>
          <div className="stat-icon icon-emerald" style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#ecfdf5", color: "#10b981", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <CheckCircle size={22} />
          </div>
          <div>
            <strong className="stat-number" style={{ fontSize: "22px", fontWeight: "800", color: "#0f172a", display: "block" }}>{readyCount}</strong>
            <span className="stat-label" style={{ fontSize: "12px", color: "#64748b" }}>Ready for Search</span>
          </div>
        </div>

        <div className="summary-stat-card" style={{ background: "#ffffff", padding: "18px 20px", borderRadius: "12px", border: "1px solid #e2e8f0", display: "flex", alignItems: "center", gap: "14px" }}>
          <div className="stat-icon icon-amber" style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#fef3c7", color: "#d97706", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <ExternalLink size={22} />
          </div>
          <div>
            <strong className="stat-number" style={{ fontSize: "22px", fontWeight: "800", color: "#0f172a", display: "block" }}>{driveLinks.length}</strong>
            <span className="stat-label" style={{ fontSize: "12px", color: "#64748b" }}>Connected Drive Sources</span>
          </div>
        </div>
      </section>

      {/* =========================================================================
          SECTION: ENTERPRISE GOOGLE DRIVE SOURCES (ONLY BOX FOR ADD LINK)
          ========================================================================= */}
      <section
        style={{
          background: "#ffffff",
          borderRadius: "14px",
          border: "1px solid #e2e8f0",
          padding: "24px",
          marginBottom: "28px",
          boxShadow: "0 1px 3px rgba(0,0,0,0.03)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "8px" }}>
          <Folder size={20} style={{ color: "#2563eb" }} />
          <h3 style={{ margin: 0, fontSize: "18px", fontWeight: "800", color: "#0f172a" }}>
            Enterprise Google Drive Sources
          </h3>
        </div>
        <p style={{ margin: "0 0 18px 0", color: "#64748b", fontSize: "13.5px" }}>
          Paste any Google Drive folder or document link. The title, folder structure, and files are automatically detected and ingested.
        </p>

        {/* Clean Single Input Box for Adding Multiple Links */}
        <form onSubmit={handleAddDriveLink} style={{ display: "flex", gap: "12px", alignItems: "center", flexWrap: "wrap" }}>
          <input
            type="url"
            placeholder="Paste Google Drive folder or document URL (e.g., https://drive.google.com/drive/folders/...)"
            value={driveUrl}
            onChange={(e) => setDriveUrl(e.target.value)}
            required
            disabled={connectingDrive}
            style={{
              flex: "1 1 400px",
              padding: "12px 16px",
              borderRadius: "10px",
              border: "1.5px solid #cbd5e1",
              fontSize: "14px",
              outline: "none",
              transition: "border-color 0.2s",
            }}
          />
          <button
            type="submit"
            className="btn btn-primary"
            disabled={connectingDrive}
            style={{
              padding: "12px 24px",
              borderRadius: "10px",
              display: "flex",
              alignItems: "center",
              gap: "8px",
              fontWeight: "700",
              fontSize: "14px",
              whiteSpace: "nowrap",
            }}
          >
            {connectingDrive ? <RefreshCw className="spin" size={16} /> : <Plus size={16} />}
            <span>{connectingDrive ? "Connecting & Ingesting…" : "Add Link"}</span>
          </button>
        </form>

        {/* Connected Drive Sources List */}
        {driveLinks.length > 0 && (
          <div style={{ marginTop: "22px", display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", gap: "14px" }}>
            {driveLinks.map((link) => (
              <div
                key={link.id}
                style={{
                  background: "#f8fafc",
                  borderRadius: "10px",
                  border: "1px solid #e2e8f0",
                  padding: "14px 16px",
                  display: "flex",
                  flexDirection: "column",
                  justifyContent: "space-between",
                }}
              >
                <div>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "6px" }}>
                    <strong style={{ fontSize: "14.5px", color: "#0f172a" }}>{link.name}</strong>
                    <span
                      style={{
                        padding: "2px 8px",
                        borderRadius: "10px",
                        fontSize: "11px",
                        fontWeight: "700",
                        background: "#ecfdf5",
                        color: "#065f46",
                      }}
                    >
                      {link.status || "synced"}
                    </span>
                  </div>

                  <a
                    href={link.drive_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{
                      fontSize: "12px",
                      color: "#2563eb",
                      textDecoration: "none",
                      display: "flex",
                      alignItems: "center",
                      gap: "4px",
                      wordBreak: "break-all",
                      marginBottom: "8px",
                    }}
                  >
                    <span>{link.drive_url.length > 40 ? `${link.drive_url.slice(0, 40)}…` : link.drive_url}</span>
                    <ExternalLink size={12} />
                  </a>

                  <div style={{ fontSize: "12px", color: "#64748b" }}>
                    {link.doc_count} document{link.doc_count === 1 ? "" : "s"} ingested
                  </div>
                </div>

                <div style={{ display: "flex", justifyContent: "flex-end", alignItems: "center", gap: "8px", marginTop: "12px", paddingTop: "10px", borderTop: "1px solid #e2e8f0" }}>
                  <button
                    type="button"
                    className="btn btn-secondary"
                    onClick={() => handleSyncDriveLink(link)}
                    title="Re-synchronize documents"
                    style={{ padding: "4px 10px", fontSize: "12px", display: "flex", alignItems: "center", gap: "4px" }}
                  >
                    <RefreshCw size={12} />
                    <span>Sync</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => handleDeleteDriveLink(link.id, link.name)}
                    title="Disconnect Google Drive Link"
                    style={{ background: "none", border: "none", cursor: "pointer", color: "#ef4444", padding: "4px" }}
                  >
                    <Trash2 size={15} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* =========================================================================
          SECTION: INGESTED FOLDERS & FILES WITH DROPDOWN HIERARCHY
          ========================================================================= */}
      <section className="library-card" style={{ background: "#ffffff", borderRadius: "14px", border: "1px solid #e2e8f0", padding: "24px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "12px", marginBottom: "20px" }}>
          <div>
            <h3 style={{ margin: 0, fontSize: "18px", fontWeight: "800", color: "#0f172a" }}>
              Ingested Drive Folders & Documents
            </h3>
            <p style={{ margin: "4px 0 0", color: "#64748b", fontSize: "13px" }}>
              Click any folder to expand or collapse its files. Use "Manage Access" to control department and individual employee permissions.
            </p>
          </div>

          <div className="search-field" style={{ display: "flex", alignItems: "center", gap: "8px", flex: "0 1 300px" }}>
            <Search size={16} style={{ color: "#94a3b8" }} />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search documents..."
              style={{ width: "100%", padding: "8px 12px", borderRadius: "8px", border: "1px solid #cbd5e1", fontSize: "13px" }}
            />
          </div>
        </div>

        {/* Hierarchical Folder & Document Tree */}
        {loading ? (
          <div className="empty-state" style={{ textAlign: "center", padding: "30px", color: "#64748b" }}>
            Loading document library…
          </div>
        ) : folderKeys.length === 0 ? (
          <div className="empty-state" style={{ textAlign: "center", padding: "40px", color: "#64748b" }}>
            <FileText size={36} style={{ color: "#94a3b8", marginBottom: "8px" }} />
            <strong style={{ display: "block", fontSize: "16px", color: "#0f172a" }}>No Documents Ingested Yet</strong>
            <p style={{ margin: "4px 0 0", fontSize: "13px" }}>
              Paste a Google Drive link in the box above and click "Add Link" to ingest documents.
            </p>
          </div>
        ) : (
          <div style={{ display: "flex", flexDirection: "column", gap: "16px" }}>
            {folderKeys.map((folderPath) => {
              const folderDocs = docsByFolder[folderPath] || [];
              const isExpanded = expandedFolders[folderPath] ?? true;

              return (
                <div
                  key={folderPath}
                  style={{
                    border: "1px solid #e2e8f0",
                    borderRadius: "12px",
                    overflow: "hidden",
                    background: "#ffffff",
                  }}
                >
                  {/* Folder Header (Dropdown Accordion Toggle) */}
                  <div
                    onClick={() => toggleFolder(folderPath)}
                    style={{
                      background: "#f8fafc",
                      padding: "14px 18px",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "space-between",
                      cursor: "pointer",
                      userSelect: "none",
                      borderBottom: isExpanded ? "1px solid #e2e8f0" : "none",
                    }}
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                      {isExpanded ? <ChevronDown size={18} style={{ color: "#64748b" }} /> : <ChevronRight size={18} style={{ color: "#64748b" }} />}
                      {isExpanded ? <FolderOpen size={20} style={{ color: "#2563eb" }} /> : <Folder size={20} style={{ color: "#2563eb" }} />}
                      <div>
                        <strong style={{ fontSize: "15px", color: "#0f172a" }}>
                          {folderPath === "/" ? "Root Folder (/)" : folderPath}
                        </strong>
                        <span style={{ marginLeft: "10px", fontSize: "12px", color: "#64748b", fontWeight: "600" }}>
                          ({folderDocs.length} file{folderDocs.length === 1 ? "" : "s"})
                        </span>
                      </div>
                    </div>

                    <span style={{ fontSize: "12px", color: "#64748b" }}>
                      {isExpanded ? "Click to collapse" : "Click to view files"}
                    </span>
                  </div>

                  {/* Files inside this folder */}
                  {isExpanded && (
                    <div style={{ display: "flex", flexDirection: "column" }}>
                      {folderDocs.map((doc) => {
                        let rolesList: string[] = [];
                        try {
                          rolesList = JSON.parse(doc.access_roles || "[]");
                        } catch {
                          rolesList = ["admin", "employee"];
                        }

                        let deniedList: string[] = [];
                        try {
                          deniedList = JSON.parse(doc.denied_users || "[]");
                        } catch {
                          deniedList = [];
                        }

                        return (
                          <div
                            key={doc.id}
                            style={{
                              display: "flex",
                              alignItems: "center",
                              justifyContent: "space-between",
                              padding: "14px 20px",
                              borderTop: "1px solid #f1f5f9",
                              flexWrap: "wrap",
                              gap: "12px",
                            }}
                          >
                            <div style={{ display: "flex", alignItems: "center", gap: "14px", flex: "1 1 340px" }}>
                              <div
                                style={{
                                  width: "36px",
                                  height: "36px",
                                  borderRadius: "8px",
                                  background: "#eff6ff",
                                  color: "#2563eb",
                                  display: "flex",
                                  alignItems: "center",
                                  justifyContent: "center",
                                  flexShrink: 0,
                                }}
                              >
                                <FileText size={18} />
                              </div>

                              <div>
                                <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "4px" }}>
                                  <strong style={{ fontSize: "14px", color: "#0f172a" }}>{doc.name}</strong>
                                  <span
                                    style={{
                                      padding: "2px 7px",
                                      borderRadius: "10px",
                                      fontSize: "11px",
                                      fontWeight: "700",
                                      background: doc.status === "ready" ? "#ecfdf5" : "#fef3c7",
                                      color: doc.status === "ready" ? "#065f46" : "#b45309",
                                      display: "flex",
                                      alignItems: "center",
                                      gap: "3px",
                                    }}
                                  >
                                    {doc.status === "ready" ? <CheckCircle size={10} /> : <Clock size={10} />}
                                    {doc.status}
                                  </span>
                                </div>

                                <p style={{ margin: "0 0 6px 0", fontSize: "12px", color: "#64748b" }}>
                                  {doc.chunk_count} passages ingested · Added {new Date(doc.created_at).toLocaleDateString()}
                                </p>

                                {/* Department Roles and Denied Counts */}
                                <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "6px" }}>
                                  <span style={{ fontSize: "11.5px", fontWeight: "600", color: "#475569", display: "flex", alignItems: "center", gap: "4px" }}>
                                    <Shield size={12} style={{ color: "#2563eb" }} /> Allowed:
                                  </span>
                                  {rolesList.map((r) => (
                                    <span
                                      key={r}
                                      style={{
                                        padding: "1px 7px",
                                        borderRadius: "10px",
                                        fontSize: "10.5px",
                                        fontWeight: "700",
                                        background: "#eff6ff",
                                        color: "#1d4ed8",
                                        border: "1px solid #bfdbfe",
                                        textTransform: "uppercase",
                                      }}
                                    >
                                      {r}
                                    </span>
                                  ))}

                                  {deniedList.length > 0 && (
                                    <span
                                      style={{
                                        padding: "1px 7px",
                                        borderRadius: "10px",
                                        fontSize: "10.5px",
                                        fontWeight: "700",
                                        background: "#fef2f2",
                                        color: "#991b1b",
                                        border: "1px solid #fecaca",
                                        display: "flex",
                                        alignItems: "center",
                                        gap: "3px",
                                      }}
                                    >
                                      <UserX size={10} />
                                      {deniedList.length} Denied
                                    </span>
                                  )}
                                </div>
                              </div>
                            </div>

                            {/* Actions Toolbar */}
                            <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                              <button
                                className="btn btn-secondary"
                                title="Manage Access & Permissions"
                                onClick={() => openAccessModal(doc)}
                                style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "12.5px", padding: "6px 12px" }}
                              >
                                <Shield size={14} style={{ color: "#2563eb" }} />
                                <span>Manage Access</span>
                              </button>

                              <button
                                className="btn-icon-action"
                                title="Re-index Chunks"
                                disabled={activeId === doc.id}
                                onClick={() => docAction(`/api/documents/${doc.id}/reingest`, "POST", doc.id)}
                                style={{ padding: "6px", border: "1px solid #cbd5e1", borderRadius: "6px", background: "none", cursor: "pointer" }}
                              >
                                <RefreshCw size={14} />
                              </button>

                              <button
                                className="btn-icon-action"
                                title="Generate Summary"
                                disabled={activeId === doc.id}
                                onClick={() => docAction(`/api/documents/${doc.id}/summary`, "POST", doc.id)}
                                style={{ padding: "6px", border: "1px solid #cbd5e1", borderRadius: "6px", background: "none", cursor: "pointer" }}
                              >
                                <Sparkles size={14} />
                              </button>

                              <button
                                className="btn-icon-action danger"
                                title="Delete Document"
                                disabled={activeId === doc.id}
                                onClick={() => docAction(`/api/documents/${doc.id}`, "DELETE", doc.id)}
                                style={{ padding: "6px", border: "1px solid #fecaca", borderRadius: "6px", background: "none", cursor: "pointer", color: "#ef4444" }}
                              >
                                <Trash2 size={14} />
                              </button>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </section>

      {/* =========================================================================
          MODAL: MANAGE ACCESS (ALLOWED ROLES + DENIED EMPLOYEES + QDRANT ACL)
          ========================================================================= */}
      {editingDoc && (
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
              maxWidth: "680px",
              maxHeight: "90vh",
              display: "flex",
              flexDirection: "column",
              boxShadow: "0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04)",
              overflow: "hidden",
            }}
          >
            {/* Modal Header */}
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                padding: "20px 24px",
                borderBottom: "1px solid #e2e8f0",
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                <div style={{ width: "36px", height: "36px", borderRadius: "8px", background: "#eff6ff", color: "#2563eb", display: "flex", alignItems: "center", justifyContent: "center" }}>
                  <Shield size={20} />
                </div>
                <div>
                  <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "800", color: "#0f172a" }}>
                    Manage Access Permissions
                  </h3>
                  <span style={{ fontSize: "12px", color: "#64748b" }}>
                    {editingDoc.name} ({editingDoc.folder_path || "/"})
                  </span>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setEditingDoc(null)}
                style={{ background: "none", border: "none", cursor: "pointer", color: "#94a3b8" }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Modal Body */}
            <div style={{ padding: "24px", overflowY: "auto", display: "flex", flexDirection: "column", gap: "22px" }}>
              {/* Section 1: Allowed Department Roles */}
              <div>
                <div style={{ fontSize: "13.5px", fontWeight: "700", color: "#0f172a", marginBottom: "4px" }}>
                  1. Allowed Departments & Roles
                </div>
                <p style={{ margin: "0 0 12px 0", fontSize: "12px", color: "#64748b" }}>
                  Select which departments have access to view and search this document (matches Workspace Settings roles dynamically):
                </p>

                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(130px, 1fr))", gap: "10px" }}>
                  {roles.map((r) => {
                    const isChecked = selectedRoles.includes(r.key.toLowerCase());
                    return (
                      <button
                        key={r.key}
                        type="button"
                        onClick={() => toggleRole(r.key)}
                        style={{
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "space-between",
                          padding: "10px 14px",
                          borderRadius: "8px",
                          border: `1.5px solid ${isChecked ? "#2563eb" : "#cbd5e1"}`,
                          background: isChecked ? "#eff6ff" : "#ffffff",
                          cursor: "pointer",
                          transition: "all 0.15s ease",
                        }}
                      >
                        <span style={{ fontSize: "13px", fontWeight: "700", color: isChecked ? "#1d4ed8" : "#334155" }}>
                          {r.name}
                        </span>
                        {isChecked && <Check size={16} style={{ color: "#2563eb" }} />}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Section 2: Deny Specific Persons */}
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "4px" }}>
                  <div style={{ fontSize: "13.5px", fontWeight: "700", color: "#0f172a" }}>
                    2. Deny Access to Specific Employees (Blacklist)
                  </div>
                  <span style={{ fontSize: "12px", color: "#ef4444", fontWeight: "600" }}>
                    {deniedUsers.length} employee{deniedUsers.length === 1 ? "" : "s"} denied
                  </span>
                </div>
                <p style={{ margin: "0 0 10px 0", fontSize: "12px", color: "#64748b" }}>
                  Even if their department has access above, selectively block specific individual employees from searching or accessing this file:
                </p>

                <input
                  type="text"
                  placeholder="Search employees to deny..."
                  value={employeeSearch}
                  onChange={(e) => setEmployeeSearch(e.target.value)}
                  style={{ width: "100%", padding: "8px 12px", borderRadius: "8px", border: "1px solid #cbd5e1", fontSize: "13px", marginBottom: "10px" }}
                />

                <div
                  style={{
                    maxHeight: "180px",
                    overflowY: "auto",
                    border: "1px solid #e2e8f0",
                    borderRadius: "8px",
                    padding: "8px",
                    display: "flex",
                    flexDirection: "column",
                    gap: "6px",
                  }}
                >
                  {relevantEmployees.length === 0 ? (
                    <div style={{ textAlign: "center", padding: "14px", fontSize: "12px", color: "#94a3b8" }}>
                      No matching employees found in allowed departments.
                    </div>
                  ) : (
                    relevantEmployees.map((emp) => {
                      const isDenied = deniedUsers.includes(emp.email.toLowerCase());
                      const empName = emp.display_name || emp.email.split("@")[0];

                      return (
                        <div
                          key={emp.id}
                          style={{
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "space-between",
                            padding: "8px 12px",
                            borderRadius: "6px",
                            background: isDenied ? "#fef2f2" : "#f8fafc",
                            border: `1px solid ${isDenied ? "#fecaca" : "#e2e8f0"}`,
                          }}
                        >
                          <div>
                            <strong style={{ fontSize: "13px", color: "#0f172a" }}>{empName}</strong>
                            <div style={{ fontSize: "11.5px", fontFamily: "monospace", color: "#64748b" }}>
                              {emp.email} • {emp.role_key || emp.role}
                            </div>
                          </div>

                          <button
                            type="button"
                            onClick={() => toggleDenyUser(emp.email)}
                            style={{
                              padding: "4px 10px",
                              borderRadius: "6px",
                              fontSize: "12px",
                              fontWeight: "700",
                              cursor: "pointer",
                              border: "none",
                              background: isDenied ? "#ef4444" : "#ffffff",
                              color: isDenied ? "#ffffff" : "#475569",
                              boxShadow: isDenied ? "none" : "0 1px 2px rgba(0,0,0,0.05)",
                            }}
                          >
                            {isDenied ? "DENIED" : "Allow"}
                          </button>
                        </div>
                      );
                    })
                  )}
                </div>
              </div>

              {/* Section 3: Folder Propagation Toggle */}
              {editingDoc.folder_path && editingDoc.folder_path !== "/" && (
                <div style={{ background: "#f8fafc", padding: "12px 16px", borderRadius: "8px", border: "1px dashed #cbd5e1" }}>
                  <label style={{ display: "flex", alignItems: "center", gap: "10px", cursor: "pointer", fontSize: "13px", color: "#0f172a", fontWeight: "600" }}>
                    <input
                      type="checkbox"
                      checked={applyToFolder}
                      onChange={(e) => setApplyToFolder(e.target.checked)}
                      style={{ width: "16px", height: "16px", cursor: "pointer" }}
                    />
                    <span>
                      Apply these permissions and deny rules to ALL documents inside folder '{editingDoc.folder_path}'
                    </span>
                  </label>
                </div>
              )}
            </div>

            {/* Modal Footer */}
            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                gap: "10px",
                padding: "16px 24px",
                borderTop: "1px solid #e2e8f0",
                background: "#f8fafc",
              }}
            >
              <button
                type="button"
                className="btn btn-secondary"
                onClick={() => setEditingDoc(null)}
                style={{ padding: "8px 16px" }}
              >
                Cancel
              </button>
              <button
                type="button"
                className="btn btn-primary"
                onClick={saveAccessPermissions}
                disabled={updatingAccess}
                style={{ padding: "8px 20px", display: "flex", alignItems: "center", gap: "6px" }}
              >
                {updatingAccess ? "Updating Qdrant ACLs…" : "Save & Update Vector ACL"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
