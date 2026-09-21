import { useEffect, useState } from "react";
import { FileText, FolderUp, RefreshCw, Search, Sparkles, Trash2, Shield, CheckCircle, Clock, AlertTriangle, Layers, Lock } from "lucide-react";
import { request } from "../api";

export type Doc = {
  id: number;
  name: string;
  source: string;
  status: string;
  chunk_count: number;
  access_roles?: string;
  summary?: string;
  created_at: string;
};

export default function DocumentsPage() {
  const [docs, setDocs] = useState<Doc[]>([]);
  const [search, setSearch] = useState("");
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(true);
  const [ingesting, setIngesting] = useState(false);
  const [activeId, setActiveId] = useState<number | null>(null);

  // Document Role Access Modal
  const [editingDoc, setEditingDoc] = useState<Doc | null>(null);
  const [selectedRoles, setSelectedRoles] = useState<string[]>([]);
  const [updatingAccess, setUpdatingAccess] = useState(false);

  const availableRoles = ["admin", "hr", "manager", "finance", "employee"];

  const load = async (term = search) => {
    setLoading(true);
    try {
      setDocs(
        await request<Doc[]>(
          `/api/documents${term ? `?search=${encodeURIComponent(term)}` : ""}`
        )
      );
    } catch (e) {
      setMessage((e as Error).message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load("");
  }, []);

  async function ingest() {
    setIngesting(true);
    setMessage("");
    try {
      const rows = await request<Doc[]>("/api/documents/ingest/local", { method: "POST" });
      setDocs(rows);
      setMessage(
        rows.length
          ? `${rows.length} document${rows.length === 1 ? "" : "s"} indexed into vector storage.`
          : "No new supported files found in local data directory."
      );
    } catch (e) {
      setMessage((e as Error).message);
    } finally {
      setIngesting(false);
    }
  }

  async function action(path: string, method = "POST", id?: number) {
    setActiveId(id ?? null);
    setMessage("");
    try {
      const updated = await request<Doc>(path, { method });
      if (method === "DELETE") {
        setDocs((items) => items.filter((doc) => doc.id !== id));
        setMessage("Document removed from knowledge library.");
      } else {
        setDocs((items) => items.map((doc) => (doc.id === updated.id ? updated : doc)));
        setMessage(
          path.endsWith("/summary")
            ? "AI summary generated successfully."
            : "Document re-indexed successfully."
        );
      }
    } catch (e) {
      setMessage((e as Error).message);
    } finally {
      setActiveId(null);
    }
  }

  const openAccessModal = (doc: Doc) => {
    setEditingDoc(doc);
    try {
      const parsed = JSON.parse(doc.access_roles || '["admin", "hr", "finance", "manager", "employee"]');
      setSelectedRoles(parsed);
    } catch {
      setSelectedRoles(["admin", "hr", "manager", "employee"]);
    }
  };

  const saveAccessRoles = async () => {
    if (!editingDoc) return;
    setUpdatingAccess(true);
    try {
      const updated = await request<Doc>(`/api/documents/${editingDoc.id}/access`, {
        method: "PUT",
        body: JSON.stringify({ roles: selectedRoles }),
      });
      setDocs((items) => items.map((d) => (d.id === updated.id ? updated : d)));
      setMessage(`Access permissions updated for ${editingDoc.name}`);
      setEditingDoc(null);
    } catch (e) {
      setMessage((e as Error).message);
    } finally {
      setUpdatingAccess(false);
    }
  };

  const toggleRole = (r: string) => {
    if (selectedRoles.includes(r)) {
      if (selectedRoles.length === 1) return; // Must keep at least one role
      setSelectedRoles(selectedRoles.filter((item) => item !== r));
    } else {
      setSelectedRoles([...selectedRoles, r]);
    }
  };

  const readyCount = docs.filter((d) => d.status === "ready").length;
  const totalChunks = docs.reduce((acc, d) => acc + d.chunk_count, 0);

  return (
    <div className="documents-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <FileText size={14} /> KNOWLEDGE LIBRARY
          </div>
          <h1>Enterprise Document Storage</h1>
          <p className="subheading">
            Index, summarize, and manage role-based access controls for internal files.
          </p>
        </div>
        <button className="btn-primary" onClick={ingest} disabled={ingesting}>
          {ingesting ? <RefreshCw className="spin" size={16} /> : <FolderUp size={16} />}
          <span>{ingesting ? "Indexing Vector DB…" : "Index Local Data Folder"}</span>
        </button>
      </header>

      {/* Summary Metrics Counter */}
      <section className="library-summary-cards">
        <div className="summary-stat-card">
          <div className="stat-icon icon-blue">
            <FileText size={20} />
          </div>
          <div>
            <strong className="stat-number">{docs.length}</strong>
            <span className="stat-label">Indexed Documents</span>
          </div>
        </div>

        <div className="summary-stat-card">
          <div className="stat-icon icon-indigo">
            <Layers size={20} />
          </div>
          <div>
            <strong className="stat-number">{totalChunks}</strong>
            <span className="stat-label">Searchable Passages</span>
          </div>
        </div>

        <div className="summary-stat-card">
          <div className="stat-icon icon-emerald">
            <CheckCircle size={20} />
          </div>
          <div>
            <strong className="stat-number">{readyCount}</strong>
            <span className="stat-label">Ready for Answers</span>
          </div>
        </div>
      </section>

      {/* Main Document Table Card */}
      <section className="library-card">
        <div className="library-tools">
          <div className="search-field">
            <Search size={16} />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && load()}
              placeholder="Filter documents by title..."
            />
            <button onClick={() => load()} aria-label="Search">
              Search
            </button>
          </div>
          <span className="doc-count-tag">{docs.length} Documents</span>
        </div>

        {message && (
          <div className={`alert-banner ${message.includes("successfully") || message.includes("indexed") ? "success" : "error"}`}>
            <span>{message}</span>
          </div>
        )}

        <div className="document-list">
          {loading ? (
            <div className="empty-state">Loading document library…</div>
          ) : docs.length ? (
            docs.map((doc) => {
              let rolesList: string[] = [];
              try {
                rolesList = JSON.parse(doc.access_roles || '["admin", "hr", "manager", "employee"]');
              } catch {
                rolesList = ["admin"];
              }

              return (
                <article className="document-row" key={doc.id}>
                  <div className="document-icon-wrap">
                    <FileText size={22} />
                  </div>

                  <div className="document-info">
                    <div className="document-title-row">
                      <strong className="doc-title-text">{doc.name}</strong>
                      <span className={`status-pill ${doc.status}`}>
                        {doc.status === "ready" ? <CheckCircle size={12} /> : <Clock size={12} />}
                        {doc.status}
                      </span>
                    </div>

                    <p className="doc-summary-text">
                      {doc.summary || `${doc.chunk_count} passages · Added ${new Date(doc.created_at).toLocaleDateString()}`}
                    </p>

                    <div className="doc-roles-bar">
                      <Lock size={12} />
                      <span className="roles-label">Access:</span>
                      {rolesList.map((r) => (
                        <span key={r} className={`role-badge ${r}`}>
                          {r}
                        </span>
                      ))}
                    </div>
                  </div>

                  <div className="document-actions">
                    <button
                      className="btn-icon-action"
                      title="Manage Role Access"
                      onClick={() => openAccessModal(doc)}
                    >
                      <Shield size={16} />
                    </button>

                    <button
                      className="btn-icon-action"
                      title="Re-index Chunks"
                      disabled={activeId === doc.id}
                      onClick={() => action(`/api/documents/${doc.id}/reingest`, "POST", doc.id)}
                    >
                      <RefreshCw size={16} />
                    </button>

                    <button
                      className="btn-icon-action"
                      title="Generate Summary"
                      disabled={activeId === doc.id}
                      onClick={() => action(`/api/documents/${doc.id}/summary`, "POST", doc.id)}
                    >
                      <Sparkles size={16} />
                    </button>

                    <button
                      className="btn-icon-action danger"
                      title="Delete Document"
                      disabled={activeId === doc.id}
                      onClick={() => action(`/api/documents/${doc.id}`, "DELETE", doc.id)}
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                </article>
              );
            })
          ) : (
            <div className="empty-state">
              <FileText size={32} />
              <strong>No Documents Found</strong>
              <p>Place PDF, TXT, or DOCX files in <code>backend/data</code> and click "Index Local Data Folder".</p>
            </div>
          )}
        </div>
      </section>

      {/* Access Permission Modal */}
      {editingDoc && (
        <div className="modal-overlay" onClick={() => setEditingDoc(null)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div className="modal-icon">
                <Shield size={22} />
              </div>
              <div>
                <h3>Configure Document Access</h3>
                <p>Select which roles are permitted to search "{editingDoc.name}"</p>
              </div>
            </div>

            <div className="modal-body">
              <div className="roles-checkbox-grid">
                {availableRoles.map((r) => {
                  const isChecked = selectedRoles.includes(r);
                  return (
                    <button
                      key={r}
                      type="button"
                      className={`role-select-box ${isChecked ? "active" : ""}`}
                      onClick={() => toggleRole(r)}
                    >
                      <span className={`role-badge ${r}`}>{r.toUpperCase()}</span>
                      <CheckCircle size={16} className={`check-icon ${isChecked ? "visible" : ""}`} />
                    </button>
                  );
                })}
              </div>

              <div className="modal-actions">
                <button type="button" className="btn-secondary" onClick={() => setEditingDoc(null)}>
                  Cancel
                </button>
                <button type="button" className="btn-primary" onClick={saveAccessRoles} disabled={updatingAccess}>
                  {updatingAccess ? "Updating..." : "Save Role Permissions"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
