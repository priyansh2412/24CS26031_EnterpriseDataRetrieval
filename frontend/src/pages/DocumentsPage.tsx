import { useEffect, useState, useRef } from "react";
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
  UploadCloud,
  FileSpreadsheet,
} from "lucide-react";
import {
  CompanyRoleItem,
  DocumentItem,
  EnterpriseDriveLinkItem,
  UserItem,
  request,
} from "../api";

function getFileTypeIcon(name: string) {
  const ext = (name || "").split(".").pop()?.toLowerCase();
  if (ext === "pdf") return <FileText size={18} style={{ color: "#ef4444" }} />;
  if (ext === "xlsx" || ext === "xls" || ext === "csv") return <FileSpreadsheet size={18} style={{ color: "#10b981" }} />;
  if (ext === "docx" || ext === "doc") return <FileText size={18} style={{ color: "#3b82f6" }} />;
  return <FileText size={18} style={{ color: "var(--accent)" }} />;
}

export default function DocumentsPage() {
  const [docs, setDocs] = useState<DocumentItem[]>([]);
  const [driveLinks, setDriveLinks] = useState<EnterpriseDriveLinkItem[]>([]);
  const [roles, setRoles] = useState<CompanyRoleItem[]>([]);
  const [employees, setEmployees] = useState<UserItem[]>([]);
  const [search, setSearch] = useState("");
  const [message, setMessage] = useState<{ type: "success" | "error"; text: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeId, setActiveId] = useState<string | null>(null);
  const [uploadingFile, setUploadingFile] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

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

  // Close modal on Escape
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setEditingDoc(null);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingFile(true);
    setMessage(null);
    try {
      const formData = new FormData();
      formData.append("file", file);
      await request("/api/ingest/upload", {
        method: "POST",
        body: formData,
      });
      setMessage({
        type: "success",
        text: `Document "${file.name}" uploaded and ingested into knowledge library!`,
      });
      await loadDocs("");
    } catch (err: any) {
      setMessage({
        type: "error",
        text: err?.message || "Failed to upload document",
      });
    } finally {
      setUploadingFile(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
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
    <div className="documents-page">
      {/* Header */}
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <FileText size={14} /> KNOWLEDGE LIBRARY & MULTI-TENANT DOCUMENT STORAGE
          </div>
          <h1>Enterprise Document Storage</h1>
          <p className="subheading">
            Ingest local files and connect Google Drive links to index documents into vector embeddings with granular ACL permissions.
          </p>
        </div>
      </header>

      {/* Global Alerts */}
      {message && (
        <div className={`alert-banner ${message.type} margin-bottom`}>
          {message.type === "success" ? <CheckCircle size={18} /> : <AlertCircle size={18} />}
          <span>{message.text}</span>
        </div>
      )}

      {/* Summary Metrics Counter */}
      <section className="metric-grid" style={{ marginBottom: "24px" }}>
        <div className="metric-card card-glass">
          <div className="metric-icon" style={{ background: "rgba(59, 130, 246, 0.12)", color: "#3b82f6" }}>
            <FileText size={22} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Ingested Documents</span>
            <span className="metric-value">{docs.length}</span>
            <span className="metric-sub">Across all folders</span>
          </div>
        </div>

        <div className="metric-card card-glass">
          <div className="metric-icon" style={{ background: "rgba(168, 85, 247, 0.12)", color: "#a855f7" }}>
            <Layers size={22} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Searchable Passages</span>
            <span className="metric-value">{totalChunks}</span>
            <span className="metric-sub">Semantic vector chunks</span>
          </div>
        </div>

        <div className="metric-card card-glass">
          <div className="metric-icon" style={{ background: "rgba(16, 185, 129, 0.12)", color: "#10b981" }}>
            <CheckCircle size={22} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Ready for Search</span>
            <span className="metric-value">{readyCount}</span>
            <span className="metric-sub">Fully indexed</span>
          </div>
        </div>

        <div className="metric-card card-glass">
          <div className="metric-icon" style={{ background: "rgba(245, 158, 11, 0.12)", color: "#f59e0b" }}>
            <ExternalLink size={22} />
          </div>
          <div className="metric-details">
            <span className="metric-label">Connected Drive Sources</span>
            <span className="metric-value">{driveLinks.length}</span>
            <span className="metric-sub">External repositories</span>
          </div>
        </div>
      </section>

      {/* Upload Dropzone */}
      <div
        className="dropzone-card"
        onClick={() => fileInputRef.current?.click()}
        onDragOver={(e) => e.preventDefault()}
        onDrop={(e) => {
          e.preventDefault();
          const file = e.dataTransfer.files?.[0];
          if (file) {
            const dt = new DataTransfer();
            dt.items.add(file);
            if (fileInputRef.current) {
              fileInputRef.current.files = dt.files;
              handleFileUpload({ target: fileInputRef.current } as any);
            }
          }
        }}
      >
        <input
          type="file"
          ref={fileInputRef}
          style={{ display: "none" }}
          accept=".pdf,.docx,.xlsx,.txt,.md,.csv,.pptx"
          onChange={handleFileUpload}
        />
        <div className="dropzone-icon">
          {uploadingFile ? <RefreshCw className="spin" size={24} /> : <UploadCloud size={24} />}
        </div>
        <div>
          <strong style={{ fontSize: "15px", color: "var(--text)", display: "block" }}>
            {uploadingFile ? "Ingesting document into vector store..." : "Click or drag & drop files to ingest"}
          </strong>
          <p style={{ margin: "4px 0 0", fontSize: "12.5px", color: "var(--text-muted)" }}>
            Supports PDF, DOCX, XLSX, TXT, CSV, PPTX (chunked with semantic embeddings)
          </p>
        </div>
      </div>

      {/* SECTION: ENTERPRISE GOOGLE DRIVE SOURCES */}
      <section className="drive-connect-card card-glass">
        <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "8px" }}>
          <Folder size={20} style={{ color: "var(--accent)" }} />
          <h3 style={{ margin: 0, fontSize: "18px", fontWeight: "800", color: "var(--text)" }}>
            Enterprise Google Drive Sources
          </h3>
        </div>
        <p style={{ margin: "0 0 18px 0", color: "var(--text-muted)", fontSize: "13.5px" }}>
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
              borderRadius: "var(--radius-md)",
              border: "1.5px solid var(--border)",
              background: "var(--surface)",
              color: "var(--text)",
              fontSize: "14px",
              outline: "none",
            }}
          />
          <button
            type="submit"
            className="btn btn-primary btn-pill"
            disabled={connectingDrive}
            style={{
              padding: "12px 24px",
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
                className="card"
                style={{
                  padding: "14px 16px",
                  display: "flex",
                  flexDirection: "column",
                  justifyContent: "space-between",
                  background: "var(--surface-2)",
                }}
              >
                <div>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "6px" }}>
                    <strong style={{ fontSize: "14.5px", color: "var(--text)" }}>{link.name}</strong>
                    <span className="badge-success">
                      {link.status || "synced"}
                    </span>
                  </div>

                  <a
                    href={link.drive_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{
                      fontSize: "12px",
                      color: "var(--accent)",
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

                  <div style={{ fontSize: "12px", color: "var(--text-muted)" }}>
                    {link.doc_count} document{link.doc_count === 1 ? "" : "s"} ingested
                  </div>
                </div>

                <div style={{ display: "flex", justifyContent: "flex-end", alignItems: "center", gap: "8px", marginTop: "12px", paddingTop: "10px", borderTop: "1px solid var(--border)" }}>
                  <button
                    type="button"
                    className="btn btn-secondary btn-pill"
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
                    style={{ background: "none", border: "none", cursor: "pointer", color: "var(--danger)", padding: "4px" }}
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
      {/* =========================================================================
          SECTION: INGESTED FOLDERS & FILES WITH DROPDOWN HIERARCHY
          ========================================================================= */}
      <section className="card-glass" style={{ padding: "24px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "12px", marginBottom: "20px" }}>
          <div>
            <h3 style={{ margin: 0, fontSize: "18px", fontWeight: "800", color: "var(--text)" }}>
              Ingested Drive Folders & Documents
            </h3>
            <p style={{ margin: "4px 0 0", color: "var(--text-muted)", fontSize: "13px" }}>
              Click any folder to expand or collapse its files. Use "Manage Access" to control department and individual employee permissions.
            </p>
          </div>

          <div style={{ display: "flex", alignItems: "center", gap: "8px", flex: "0 1 320px", position: "relative" }}>
            <Search size={16} style={{ position: "absolute", left: "12px", color: "var(--text-muted)" }} />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search documents..."
              style={{
                width: "100%",
                padding: "8px 12px 8px 36px",
                borderRadius: "var(--radius-md)",
                border: "1px solid var(--border)",
                background: "var(--surface)",
                color: "var(--text)",
                fontSize: "13px",
              }}
            />
          </div>
        </div>

        {/* Hierarchical Folder & Document Tree */}
        {loading ? (
          <div style={{ padding: "20px 0", display: "flex", flexDirection: "column", gap: "12px" }}>
            <div className="skeleton" style={{ height: "48px", borderRadius: "var(--radius-md)" }} />
            <div className="skeleton" style={{ height: "48px", borderRadius: "var(--radius-md)" }} />
            <div className="skeleton" style={{ height: "48px", borderRadius: "var(--radius-md)" }} />
          </div>
        ) : folderKeys.length === 0 ? (
          <div className="empty-state" style={{ padding: "40px" }}>
            <FileText size={36} style={{ color: "var(--text-muted)", marginBottom: "8px" }} />
            <strong>No Documents Ingested Yet</strong>
            <p style={{ margin: "4px 0 0", fontSize: "13px" }}>
              Upload a document or paste a Google Drive link above to ingest documents.
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
                  className="folder-accordion-item"
                >
                  {/* Folder Header (Dropdown Accordion Toggle) */}
                  <div
                    onClick={() => toggleFolder(folderPath)}
                    className="folder-header"
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                      {isExpanded ? <ChevronDown size={18} style={{ color: "var(--text-muted)" }} /> : <ChevronRight size={18} style={{ color: "var(--text-muted)" }} />}
                      {isExpanded ? <FolderOpen size={20} style={{ color: "var(--accent)" }} /> : <Folder size={20} style={{ color: "var(--accent)" }} />}
                      <div>
                        <strong style={{ fontSize: "15px", color: "var(--text)" }}>
                          {folderPath === "/" ? "Root Folder (/)" : folderPath}
                        </strong>
                        <span style={{ marginLeft: "10px", fontSize: "12px", color: "var(--text-muted)", fontWeight: "600" }}>
                          ({folderDocs.length} file{folderDocs.length === 1 ? "" : "s"})
                        </span>
                      </div>
                    </div>

                    <span style={{ fontSize: "12px", color: "var(--text-muted)" }}>
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

                        const isDrive = Boolean((doc as any).drive_file_id || (doc as any).source_type === "drive" || (doc as any).source === "drive");
                        const isTemp = Boolean((doc as any).source_type === "temp");

                        return (
                          <div
                            key={doc.id}
                            style={{
                              display: "flex",
                              alignItems: "center",
                              justifyContent: "space-between",
                              padding: "14px 20px",
                              borderTop: "1px solid var(--border)",
                              flexWrap: "wrap",
                              gap: "12px",
                              background: "var(--surface)",
                            }}
                          >
                            <div style={{ display: "flex", alignItems: "center", gap: "14px", flex: "1 1 340px" }}>
                              <div
                                style={{
                                  width: "38px",
                                  height: "38px",
                                  borderRadius: "var(--radius-md)",
                                  background: "var(--surface-2)",
                                  border: "1px solid var(--border)",
                                  display: "flex",
                                  alignItems: "center",
                                  justifyContent: "center",
                                  flexShrink: 0,
                                }}
                              >
                                {getFileTypeIcon(doc.name)}
                              </div>

                              <div>
                                <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "4px", flexWrap: "wrap" }}>
                                  <strong style={{ fontSize: "14px", color: "var(--text)" }}>{doc.name}</strong>
                                  
                                  {/* Source Badge */}
                                  <span className="chip" style={{ fontSize: "10.5px" }}>
                                    {isDrive ? "Google Drive" : isTemp ? "Temp" : "Local"}
                                  </span>

                                  {/* Status Badge */}
                                  <span className={doc.status === "ready" ? "badge-success" : "badge-warning"}>
                                    {doc.status === "ready" ? <CheckCircle size={10} /> : <Clock size={10} />}
                                    <span>{doc.status}</span>
                                  </span>
                                </div>

                                <p style={{ margin: "0 0 6px 0", fontSize: "12px", color: "var(--text-muted)" }}>
                                  {doc.chunk_count} passages ingested · Added {new Date(doc.created_at).toLocaleDateString()}
                                </p>

                                {/* Department Roles and Denied Counts */}
                                <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "6px" }}>
                                  <span style={{ fontSize: "11.5px", fontWeight: "600", color: "var(--text-muted)", display: "flex", alignItems: "center", gap: "4px" }}>
                                    <Shield size={12} style={{ color: "var(--accent)" }} /> Allowed:
                                  </span>
                                  {rolesList.map((r) => (
                                    <span
                                      key={r}
                                      className="chip"
                                      style={{
                                        fontSize: "10.5px",
                                        textTransform: "uppercase",
                                      }}
                                    >
                                      {r}
                                    </span>
                                  ))}

                                  {deniedList.length > 0 && (
                                    <span
                                      className="badge-danger"
                                      style={{
                                        fontSize: "10.5px",
                                        display: "inline-flex",
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
                                className="btn-pill btn-secondary"
                                title="Manage Access & Permissions"
                                onClick={() => openAccessModal(doc)}
                                style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "12px", padding: "6px 12px" }}
                              >
                                <Shield size={13} style={{ color: "var(--accent)" }} />
                                <span>Manage Access</span>
                              </button>

                              <button
                                className="btn-pill btn-secondary"
                                title="Re-index Chunks"
                                disabled={activeId === doc.id}
                                onClick={() => docAction(`/api/documents/${doc.id}/reingest`, "POST", doc.id)}
                                style={{ padding: "6px 10px", fontSize: "12px", display: "inline-flex", alignItems: "center", gap: "4px" }}
                              >
                                <RefreshCw size={13} className={activeId === doc.id ? "spin" : ""} />
                                <span>Reindex</span>
                              </button>

                              <button
                                className="btn-pill btn-secondary"
                                title="Generate Summary"
                                disabled={activeId === doc.id}
                                onClick={() => docAction(`/api/documents/${doc.id}/summary`, "POST", doc.id)}
                                style={{ padding: "6px 10px", fontSize: "12px", display: "inline-flex", alignItems: "center", gap: "4px" }}
                              >
                                <Sparkles size={13} />
                                <span>Summary</span>
                              </button>

                              <button
                                className="btn-pill"
                                title="Delete Document"
                                disabled={activeId === doc.id}
                                onClick={() => docAction(`/api/documents/${doc.id}`, "DELETE", doc.id)}
                                style={{
                                  padding: "6px 10px",
                                  fontSize: "12px",
                                  display: "inline-flex",
                                  alignItems: "center",
                                  gap: "4px",
                                  background: "var(--danger-soft)",
                                  color: "var(--danger)",
                                  border: "1px solid var(--danger)",
                                }}
                              >
                                <Trash2 size={13} />
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
        <div className="modal-overlay" onClick={() => setEditingDoc(null)}>
          <div
            className="modal-content animated-scale-up card-glass"
            onClick={(e) => e.stopPropagation()}
            style={{ maxWidth: "680px" }}
          >
            {/* Modal Header */}
            <header className="modal-header">
              <div className="glow-icon">
                <Shield size={20} />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: "17px", fontWeight: "800", color: "var(--text)" }}>
                  Manage Access Permissions
                </h3>
                <span style={{ fontSize: "12px", color: "var(--text-muted)" }}>
                  {editingDoc.name} ({editingDoc.folder_path || "/"})
                </span>
              </div>
              <button
                type="button"
                onClick={() => setEditingDoc(null)}
                className="close-btn"
                style={{ marginLeft: "auto" }}
                title="Close"
              >
                <X size={18} />
              </button>
            </header>

            {/* Modal Body */}
            <div className="modal-body" style={{ padding: "24px", overflowY: "auto", display: "flex", flexDirection: "column", gap: "22px" }}>
              {/* Section 1: Allowed Department Roles */}
              <div>
                <div style={{ fontSize: "13.5px", fontWeight: "700", color: "var(--text)", marginBottom: "4px" }}>
                  1. Allowed Departments & Roles
                </div>
                <p style={{ margin: "0 0 12px 0", fontSize: "12px", color: "var(--text-muted)" }}>
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
                          borderRadius: "var(--radius-md)",
                          border: `1.5px solid ${isChecked ? "var(--accent)" : "var(--border)"}`,
                          background: isChecked ? "var(--accent-soft)" : "var(--surface-2)",
                          color: isChecked ? "var(--accent)" : "var(--text)",
                          cursor: "pointer",
                          transition: "all 0.15s ease",
                        }}
                      >
                        <span style={{ fontSize: "13px", fontWeight: "700" }}>
                          {r.name}
                        </span>
                        {isChecked && <Check size={16} />}
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Section 2: Deny Specific Persons */}
              <div>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "4px" }}>
                  <div style={{ fontSize: "13.5px", fontWeight: "700", color: "var(--text)" }}>
                    2. Deny Access to Specific Employees (Blacklist)
                  </div>
                  <span style={{ fontSize: "12px", color: "var(--danger)", fontWeight: "600" }}>
                    {deniedUsers.length} employee{deniedUsers.length === 1 ? "" : "s"} denied
                  </span>
                </div>
                <p style={{ margin: "0 0 10px 0", fontSize: "12px", color: "var(--text-muted)" }}>
                  Even if their department has access above, selectively block specific individual employees from searching or accessing this file:
                </p>

                <input
                  type="text"
                  placeholder="Search employees to deny..."
                  value={employeeSearch}
                  onChange={(e) => setEmployeeSearch(e.target.value)}
                  style={{
                    width: "100%",
                    padding: "8px 12px",
                    borderRadius: "var(--radius-md)",
                    border: "1px solid var(--border)",
                    background: "var(--surface)",
                    color: "var(--text)",
                    fontSize: "13px",
                    marginBottom: "10px",
                  }}
                />

                <div
                  style={{
                    maxHeight: "180px",
                    overflowY: "auto",
                    border: "1px solid var(--border)",
                    borderRadius: "var(--radius-md)",
                    padding: "8px",
                    display: "flex",
                    flexDirection: "column",
                    gap: "6px",
                  }}
                >
                  {relevantEmployees.length === 0 ? (
                    <div style={{ textAlign: "center", padding: "14px", fontSize: "12px", color: "var(--text-muted)" }}>
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
                            borderRadius: "var(--radius-sm)",
                            background: isDenied ? "var(--danger-soft)" : "var(--surface-2)",
                            border: `1px solid ${isDenied ? "var(--danger)" : "var(--border)"}`,
                          }}
                        >
                          <div>
                            <strong style={{ fontSize: "13px", color: "var(--text)" }}>{empName}</strong>
                            <div style={{ fontSize: "11.5px", fontFamily: "var(--font-mono)", color: "var(--text-muted)" }}>
                              {emp.email} • {emp.role_key || emp.role}
                            </div>
                          </div>

                          <button
                            type="button"
                            onClick={() => toggleDenyUser(emp.email)}
                            style={{
                              padding: "4px 10px",
                              borderRadius: "var(--radius-full)",
                              fontSize: "11.5px",
                              fontWeight: "700",
                              cursor: "pointer",
                              border: "none",
                              background: isDenied ? "var(--danger)" : "var(--surface)",
                              color: isDenied ? "#ffffff" : "var(--text-muted)",
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
                <div style={{ background: "var(--surface-2)", padding: "12px 16px", borderRadius: "var(--radius-md)", border: "1px dashed var(--border)" }}>
                  <label style={{ display: "flex", alignItems: "center", gap: "10px", cursor: "pointer", fontSize: "13px", color: "var(--text)", fontWeight: "600" }}>
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
            <div className="modal-actions" style={{ padding: "16px 24px", borderTop: "1px solid var(--border)" }}>
              <button
                type="button"
                className="btn-outline btn-pill"
                onClick={() => setEditingDoc(null)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="btn-primary btn-pill"
                onClick={saveAccessPermissions}
                disabled={updatingAccess}
                style={{ display: "flex", alignItems: "center", gap: "6px" }}
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
