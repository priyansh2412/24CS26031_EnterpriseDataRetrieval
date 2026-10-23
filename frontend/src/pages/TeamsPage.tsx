import React, { useEffect, useRef, useState } from "react";
import {
  Users,
  Plus,
  MessageSquare,
  FolderKanban,
  UserPlus,
  Trash2,
  Send,
  ShieldCheck,
  FileText,
  CheckCircle2,
  Search,
  Crown,
  X,
  Paperclip,
  Upload,
  Loader2,
  Sparkles,
  Tag,
  ExternalLink,
  Calendar,
  Clock,
  User,
  AlertCircle,
  Check,
  ChevronDown,
  ChevronUp,
} from "lucide-react";
import {
  TeamChatMessageItem,
  TeamItem,
  UserProfile,
  TempDocItem,
  JiraLinkItem,
  JiraStatus,
  request,
  getJiraStatus,
  updateTeamJiraSettings,
  listTeamJiraIssues,
  confirmJiraSuggestion,
  dismissJiraSuggestion,
} from "../api";

interface TeamsPageProps {
  currentUser: UserProfile | null;
}

function formatDueDateTime(dueDate?: string | null, dueTime?: string | null): string {
  let datePart = "";
  if (dueDate) {
    try {
      const [y, m, d] = dueDate.split("-");
      if (y && m && d) {
        const dt = new Date(parseInt(y, 10), parseInt(m, 10) - 1, parseInt(d, 10));
        datePart = dt.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
      } else {
        datePart = dueDate;
      }
    } catch {
      datePart = dueDate;
    }
  }

  let timePart = "";
  if (dueTime) {
    try {
      const [h, min] = dueTime.split(":");
      const hour = parseInt(h, 10);
      const ampm = hour >= 12 ? "PM" : "AM";
      const hour12 = hour % 12 || 12;
      timePart = `${hour12}:${min} ${ampm} IST`;
    } catch {
      timePart = `${dueTime} IST`;
    }
  }

  if (datePart && timePart) return `${datePart}, ${timePart}`;
  if (datePart) return datePart;
  if (timePart) return timePart;
  return "";
}

export default function TeamsPage({ currentUser }: TeamsPageProps) {
  const [teams, setTeams] = useState<TeamItem[]>([]);
  const [allUsers, setAllUsers] = useState<UserProfile[]>([]);
  const [activeTeamId, setActiveTeamId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  // Create Team Modal State
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [teamName, setTeamName] = useState("");
  const [projectName, setProjectName] = useState("");
  const [description, setDescription] = useState("");
  const [creating, setCreating] = useState(false);

  // Add Member State
  const [showAddMemberModal, setShowAddMemberModal] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<string>("");
  const [userSearchTerm, setUserSearchTerm] = useState("");
  const [teamRole, setTeamRole] = useState("member");
  const [addingMember, setAddingMember] = useState(false);

  // Shared Chat State & Mode Toggle
  const [chatMessages, setChatMessages] = useState<TeamChatMessageItem[]>([]);
  const [inputMessage, setInputMessage] = useState("");
  const [sendingChat, setSendingChat] = useState(false);
  const [chatMode, setChatMode] = useState<"ai" | "team">("ai");

  // Team Temporary Documents State
  const [teamTempDocs, setTeamTempDocs] = useState<TempDocItem[]>([]);
  const [uploadingTeamDoc, setUploadingTeamDoc] = useState(false);
  const teamFileInputRef = useRef<HTMLInputElement>(null);

  // Jira Integration State
  const [jiraStatus, setJiraStatus] = useState<JiraStatus | null>(null);
  const [linkedJiraIssues, setLinkedJiraIssues] = useState<JiraLinkItem[]>([]);
  const [jiraBarOpen, setJiraBarOpen] = useState(false);
  const [showJiraModal, setShowJiraModal] = useState(false);
  const [jiraProjectKeyInput, setJiraProjectKeyInput] = useState("");
  const [savingJiraSettings, setSavingJiraSettings] = useState(false);
  const [confirmingLinkId, setConfirmingLinkId] = useState<number | null>(null);
  const [dismissingLinkId, setDismissingLinkId] = useState<number | null>(null);

  // Polling & Scroll Refs
  const chatContainerRef = useRef<HTMLDivElement>(null);
  const lastSigRef = useRef<string>("");
  const inFlightActionRef = useRef<boolean>(false);

  const loadTeamsAndUsers = async () => {
    setLoading(true);
    setError("");
    try {
      const [teamsData, usersData] = await Promise.all([
        request<TeamItem[]>("/api/teams"),
        request<UserProfile[]>("/api/users").catch(() => []),
      ]);
      setTeams(teamsData);
      setAllUsers(usersData);
      if (teamsData.length > 0 && !activeTeamId) {
        setActiveTeamId(teamsData[0].id);
      }
    } catch (err) {
      setError((err as Error).message || "Failed to load teams");
    } finally {
      setLoading(false);
    }
  };

  const loadTeamChat = async (tId: number) => {
    try {
      const chatData = await request<TeamChatMessageItem[]>(`/api/teams/${tId}/chat`);
      setChatMessages(chatData);
      lastSigRef.current = chatData
        .map((m) => `${m.id}:${m.message_type || "ai"}:${m.jira?.id || 0}:${m.jira?.status || ""}`)
        .join("|");
    } catch (err) {
      console.error("Failed to load team chat", err);
    }
  };

  const loadTeamTempDocs = async (tId: number) => {
    try {
      const docs = await request<TempDocItem[]>(`/api/teams/${tId}/temp-docs`);
      setTeamTempDocs(docs || []);
    } catch {
      setTeamTempDocs([]);
    }
  };

  const loadLinkedJiraIssues = async (tId: number) => {
    try {
      const issues = await listTeamJiraIssues(tId);
      setLinkedJiraIssues(issues || []);
    } catch {
      setLinkedJiraIssues([]);
    }
  };

  // Initial load
  useEffect(() => {
    loadTeamsAndUsers();
    getJiraStatus().then(setJiraStatus).catch(() => setJiraStatus(null));
  }, []);

  // When active team changes
  useEffect(() => {
    if (activeTeamId) {
      loadTeamChat(activeTeamId);
      loadTeamTempDocs(activeTeamId);
      loadLinkedJiraIssues(activeTeamId);
      lastSigRef.current = "";
    }
  }, [activeTeamId]);

  // Close modals on Escape key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setShowCreateModal(false);
        setShowAddMemberModal(false);
        setShowJiraModal(false);
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  // Polling every 4 seconds while active and visible
  useEffect(() => {
    if (!activeTeamId) return;

    const poll = async () => {
      if (typeof document !== "undefined" && document.visibilityState !== "visible") return;
      if (sendingChat || inFlightActionRef.current) return;

      try {
        const [chatData, issuesData] = await Promise.all([
          request<TeamChatMessageItem[]>(`/api/teams/${activeTeamId}/chat`),
          listTeamJiraIssues(activeTeamId).catch(() => []),
        ]);

        const sig = chatData
          .map((m) => `${m.id}:${m.message_type || "ai"}:${m.jira?.id || 0}:${m.jira?.status || ""}`)
          .join("|");

        if (sig !== lastSigRef.current) {
          lastSigRef.current = sig;

          const container = chatContainerRef.current;
          const isNearBottom = container
            ? container.scrollHeight - container.scrollTop - container.clientHeight < 120
            : true;

          setChatMessages(chatData);

          if (isNearBottom) {
            setTimeout(() => {
              if (chatContainerRef.current) {
                chatContainerRef.current.scrollTop = chatContainerRef.current.scrollHeight;
              }
            }, 60);
          }
        }

        setLinkedJiraIssues(issuesData || []);
      } catch {
        // Suppress background poll errors
      }
    };

    const intervalId = setInterval(poll, 4000);

    const handleVisibility = () => {
      if (document.visibilityState === "visible") {
        poll();
      }
    };
    document.addEventListener("visibilitychange", handleVisibility);

    return () => {
      clearInterval(intervalId);
      document.removeEventListener("visibilitychange", handleVisibility);
    };
  }, [activeTeamId, sendingChat]);

  const handleTeamFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !activeTeamId) return;
    setUploadingTeamDoc(true);
    try {
      const formData = new FormData();
      formData.append("file", file);
      await request<TempDocItem>(`/api/teams/${activeTeamId}/upload-temp`, {
        method: "POST",
        body: formData,
      });
      await loadTeamTempDocs(activeTeamId);
    } catch (err) {
      alert((err as Error).message || "Failed to upload team document");
    } finally {
      setUploadingTeamDoc(false);
      if (teamFileInputRef.current) teamFileInputRef.current.value = "";
    }
  };

  const handleDeleteTeamTempDoc = async (docId: string) => {
    if (!activeTeamId) return;
    try {
      await request(`/api/teams/${activeTeamId}/temp-docs/${docId}`, { method: "DELETE" });
      await loadTeamTempDocs(activeTeamId);
    } catch (err) {
      alert((err as Error).message || "Failed to remove team document");
    }
  };

  const handleCreateTeam = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!teamName.trim() || !projectName.trim()) return;

    setCreating(true);
    try {
      const newTeam = await request<TeamItem>("/api/teams", {
        method: "POST",
        body: JSON.stringify({
          name: teamName.trim(),
          project_name: projectName.trim(),
          description: description.trim(),
        }),
      });
      setTeams([newTeam, ...teams]);
      setActiveTeamId(newTeam.id);
      setShowCreateModal(false);
      setTeamName("");
      setProjectName("");
      setDescription("");
    } catch (err) {
      alert((err as Error).message || "Failed to create team");
    } finally {
      setCreating(false);
    }
  };

  const handleAddMember = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeTeamId || !selectedUserId) return;

    setAddingMember(true);
    try {
      const updatedTeam = await request<TeamItem>(`/api/teams/${activeTeamId}/members`, {
        method: "POST",
        body: JSON.stringify({
          user_id: selectedUserId,
          role_in_team: teamRole,
        }),
      });

      setTeams(teams.map((t) => (t.id === activeTeamId ? updatedTeam : t)));
      setShowAddMemberModal(false);
      setSelectedUserId("");
      setUserSearchTerm("");
      setTeamRole("member");
    } catch (err) {
      alert((err as Error).message || "Failed to add member to team");
    } finally {
      setAddingMember(false);
    }
  };

  const handleRemoveMember = async (teamId: number, userId: string | number) => {
    if (!confirm("Are you sure you want to remove this member from the team?")) return;
    try {
      await request(`/api/teams/${teamId}/members/${userId}`, { method: "DELETE" });
      loadTeamsAndUsers();
    } catch (err) {
      alert((err as Error).message || "Failed to remove member");
    }
  };

  const handleSendChat = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeTeamId || !inputMessage.trim() || sendingChat) return;

    const messageText = inputMessage.trim();
    setInputMessage("");
    setSendingChat(true);

    try {
      const newMsg = await request<TeamChatMessageItem>(`/api/teams/${activeTeamId}/chat`, {
        method: "POST",
        body: JSON.stringify({ message: messageText, mode: chatMode }),
      });

      setChatMessages((prev) => [...prev, newMsg]);
      setTimeout(() => {
        if (chatContainerRef.current) {
          chatContainerRef.current.scrollTop = chatContainerRef.current.scrollHeight;
        }
      }, 50);
    } catch (err) {
      alert((err as Error).message || "Failed to send chat message");
    } finally {
      setSendingChat(false);
    }
  };

  const handleConfirmSuggestion = async (linkId: number) => {
    if (confirmingLinkId) return;
    setConfirmingLinkId(linkId);
    inFlightActionRef.current = true;
    try {
      const updated = await confirmJiraSuggestion(linkId);
      setChatMessages((prev) =>
        prev.map((msg) => (msg.jira && msg.jira.id === linkId ? { ...msg, jira: updated } : msg))
      );
      if (activeTeamId) {
        loadLinkedJiraIssues(activeTeamId);
      }
    } catch (err) {
      const msg = (err as Error).message || "Failed to create Jira issue";
      alert(msg);
      if (activeTeamId) {
        loadTeamChat(activeTeamId);
      }
    } finally {
      setConfirmingLinkId(null);
      inFlightActionRef.current = false;
    }
  };

  const handleDismissSuggestion = async (linkId: number) => {
    if (dismissingLinkId) return;
    setDismissingLinkId(linkId);
    inFlightActionRef.current = true;
    try {
      await dismissJiraSuggestion(linkId);
      setChatMessages((prev) =>
        prev.map((msg) =>
          msg.jira && msg.jira.id === linkId
            ? { ...msg, jira: { ...msg.jira, status: "dismissed" } }
            : msg
        )
      );
    } catch (err) {
      alert((err as Error).message || "Failed to dismiss suggestion");
    } finally {
      setDismissingLinkId(null);
      inFlightActionRef.current = false;
    }
  };

  const currentTeam = teams.find((t) => t.id === activeTeamId);

  const isLeadOrAdmin = Boolean(
    currentUser &&
    currentTeam && (
      currentUser.rank_level <= 2 ||
      currentUser.role === "admin" ||
      currentUser.role_key === "admin" ||
      String(currentTeam.created_by_id) === String(currentUser.id) ||
      currentTeam.members.some(
        (m) => String(m.user_id) === String(currentUser.id) && m.role_in_team === "lead"
      )
    )
  );

  const openJiraSettingsModal = () => {
    if (currentTeam) {
      setJiraProjectKeyInput(currentTeam.jira_project_key || "");
    }
    getJiraStatus().then(setJiraStatus).catch(() => {});
    setShowJiraModal(true);
  };

  const handleSaveJiraSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeTeamId) return;
    setSavingJiraSettings(true);
    try {
      const res = await updateTeamJiraSettings(activeTeamId, jiraProjectKeyInput.trim() || null);
      setTeams((prev) =>
        prev.map((t) => (t.id === activeTeamId ? { ...t, jira_project_key: res.jira_project_key } : t))
      );
      setShowJiraModal(false);
    } catch (err) {
      alert((err as Error).message || "Failed to update Jira settings");
    } finally {
      setSavingJiraSettings(false);
    }
  };

  return (
    <div className="teams-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <Users size={14} /> ENTERPRISE TEAMS & PROJECT CHATBOTS
          </div>
          <h1>Team Workspaces & Shared Project Chatbots</h1>
          <p className="subheading">
            Build teams for specific company projects and collaborate with a shared team AI search assistant.
          </p>
        </div>
        <button className="btn-primary" onClick={() => setShowCreateModal(true)}>
          <Plus size={16} /> Build New Team
        </button>
      </header>

      {error && <div className="alert-banner error margin-bottom">{error}</div>}

      <div className="teams-layout">
        {/* Left Sidebar: Team List */}
        <aside className="teams-sidebar-card card-glass">
          <div className="teams-sidebar-header">
            <div className="card-header-title">
              <FolderKanban size={16} />
              <span>Project Teams ({teams.length})</span>
            </div>
            <button
              type="button"
              className="btn-pill btn-primary"
              style={{ fontSize: "12px", padding: "4px 10px" }}
              onClick={() => setShowCreateModal(true)}
              title="Build New Team"
            >
              <Plus size={13} /> New team
            </button>
          </div>

          <div className="team-list">
            {teams.length === 0 ? (
              <div className="empty-subtext" style={{ padding: "24px 16px", textAlign: "center", color: "var(--text-muted)", fontSize: "12.5px" }}>
                No active project teams yet. Click "New team" to create one.
              </div>
            ) : (
              teams.map((t) => (
                <div
                  key={t.id}
                  className={`team-item-card ${activeTeamId === t.id ? "active" : ""}`}
                  onClick={() => setActiveTeamId(t.id)}
                >
                  <div className="team-avatar">{(t.name || "T").slice(0, 2).toUpperCase()}</div>
                  <div className="team-item-info">
                    <div className="team-item-title">{t.name}</div>
                    <div className="team-project-tag">
                      <FolderKanban size={12} /> {t.project_name}
                    </div>
                    <div className="team-meta">{t.members.length} members</div>
                  </div>
                </div>
              ))
            )}
          </div>
        </aside>

        {/* Right Area: Team Workspace & Shared Chatbot */}
        {currentTeam ? (
          <main className="team-workspace-card card-glass">
            <header className="team-workspace-header">
              <div>
                <h2>{currentTeam.name}</h2>
                <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap", marginTop: "4px" }}>
                  <div className="project-badge">
                    <FolderKanban size={14} /> Project Scope: {currentTeam.project_name}
                  </div>
                  {/* Overlapping member avatar stack */}
                  <div className="avatar-stack">
                    {currentTeam.members.slice(0, 5).map((m) => (
                      <div
                        key={m.id}
                        className="avatar-stack-item"
                        title={`${m.user_email} (${m.role_in_team})`}
                      >
                        {(m.user_email || "U").slice(0, 1).toUpperCase()}
                      </div>
                    ))}
                    {currentTeam.members.length > 5 && (
                      <div className="avatar-stack-more">
                        +{currentTeam.members.length - 5}
                      </div>
                    )}
                  </div>
                </div>
                {currentTeam.description && <p className="team-desc">{currentTeam.description}</p>}
              </div>
              <div className="team-header-actions">
                <button
                  type="button"
                  className="btn-pill btn-secondary jira-header-btn"
                  onClick={openJiraSettingsModal}
                  title="Configure Jira project integration for this team"
                >
                  <Tag size={14} />
                  <span>Jira</span>
                  <span className={`jira-status-dot ${jiraStatus?.configured ? "connected" : "disconnected"}`} />
                </button>
                <button
                  type="button"
                  className="btn-pill btn-secondary"
                  onClick={() => setShowAddMemberModal(true)}
                >
                  <UserPlus size={15} />
                  <span>Add member</span>
                </button>
              </div>
            </header>

            {/* Team Members Strip */}
            <div className="members-strip">
              <span className="strip-title">TEAM MEMBERS:</span>
              <div className="members-pills">
                {currentTeam.members.map((m) => (
                  <span key={m.id} className="member-pill">
                    <span className="member-email">{m.user_email}</span>
                    <span className="role-tag">{m.role_in_team}</span>
                    {currentUser && currentUser.rank_level <= 2 && (
                      <button
                        type="button"
                        className="remove-member-btn"
                        onClick={() => handleRemoveMember(currentTeam.id, m.user_id)}
                        title="Remove member"
                      >
                        ×
                      </button>
                    )}
                  </span>
                ))}
              </div>
            </div>

            {/* Linked Jira Issues Collapsible Bar */}
            <div className="jira-linked-bar">
              <div className="jira-linked-header" onClick={() => setJiraBarOpen(!jiraBarOpen)}>
                <div className="jira-linked-header-left">
                  <Tag size={13} className="jira-bar-icon" />
                  <span className="jira-linked-title">LINKED JIRA ISSUES ({linkedJiraIssues.length}):</span>
                </div>
                <div className="jira-linked-header-right">
                  {linkedJiraIssues.length > 0 && !jiraBarOpen && (
                    <span className="jira-latest-badge">
                      Latest: {linkedJiraIssues[0].jira_key}
                    </span>
                  )}
                  <button type="button" className="jira-collapse-btn" aria-label="Toggle linked Jira issues">
                    {jiraBarOpen ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                  </button>
                </div>
              </div>

              {jiraBarOpen && (
                <div className="jira-linked-content">
                  {linkedJiraIssues.length === 0 ? (
                    <div className="jira-linked-empty">
                      No Jira issues created from team chat yet. Messages containing tasks or meetings will offer a "Create Jira task?" button.
                    </div>
                  ) : (
                    <div className="jira-issues-list">
                      {linkedJiraIssues.map((issue) => (
                        <a
                          key={issue.id}
                          href={issue.jira_url || "#"}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="jira-issue-pill"
                          title={`Open ${issue.jira_key} in Jira Cloud`}
                        >
                          <span className="jira-pill-key">{issue.jira_key}</span>
                          <span className="jira-pill-title">{issue.title}</span>
                          <ExternalLink size={11} className="jira-pill-external" />
                        </a>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Shared Chatbot Section */}
            <div className="team-chat-container">
              <div className="chat-section-header">
                <MessageSquare size={16} />
                <span>Shared Team Chatbot Assistant ({currentTeam.project_name})</span>
              </div>

              <div className="team-chat-messages" ref={chatContainerRef}>
                {chatMessages.length === 0 ? (
                  <div className="empty-chat-state">
                    <MessageSquare size={32} />
                    <p>No query history in this project team yet.</p>
                    <span>Send a message to your team or ask the AI assistant questions about documents.</span>
                  </div>
                ) : (
                  chatMessages.map((msg) => {
                    const isTeamMsg = msg.message_type === "team";

                    if (isTeamMsg) {
                      const isOwn = currentUser && msg.user_email === currentUser.email;
                      // Team mode: Single bubble for team members
                      return (
                        <div key={msg.id} className="team-chat-thread team-mode-thread">
                          <div className={`chat-msg team-member-msg ${isOwn ? "own-msg" : "other-msg"}`}>
                            <div className="msg-header">
                              <strong className="sender">{isOwn ? "You" : msg.user_email}</strong>
                              <span className="time">{new Date(msg.created_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</span>
                            </div>
                            <div className="msg-body">{msg.message}</div>
                          </div>

                          {/* Jira Suggestion Card */}
                          {msg.jira && msg.jira.status !== "dismissed" && (
                            <div className={`jira-suggestion-card status-${msg.jira.status}`}>
                              {msg.jira.status === "creating" ? (
                                <div className="jira-card-loading">
                                  <Loader2 size={16} className="spin-animate" />
                                  <span>Creating Jira issue...</span>
                                </div>
                              ) : msg.jira.status === "created" ? (
                                <div className="jira-card-created">
                                  <div className="jira-created-row">
                                    <span className="jira-created-label">Linked to Jira:</span>
                                    <a
                                      href={msg.jira.jira_url || "#"}
                                      target="_blank"
                                      rel="noopener noreferrer"
                                      className="jira-key-badge"
                                      title="Open issue in Jira Cloud"
                                    >
                                      <Tag size={12} />
                                      <span>{msg.jira.jira_key}</span>
                                      <ExternalLink size={11} />
                                    </a>
                                    {msg.jira.assigned_in_jira === false && msg.jira.assignee_hint && (
                                      <span
                                        className="jira-unassigned-note"
                                        title="Assignee was not mapped to an active Jira account"
                                      >
                                        (Unassigned in Jira)
                                      </span>
                                    )}
                                  </div>
                                </div>
                              ) : (
                                // "pending" or "failed"
                                <>
                                  <div className="jira-card-header">
                                    <div className="jira-card-title-wrap">
                                      <Sparkles size={14} className="jira-sparkle-icon" />
                                      <strong>Create Jira task?</strong>
                                    </div>
                                    <span className="jira-suggestion-title">{msg.jira.title}</span>
                                  </div>

                                  <div className="jira-chips-row">
                                    <span className={`jira-chip chip-intent-${msg.jira.intent}`}>
                                      {msg.jira.intent === "meeting" ? <Calendar size={12} /> : <Tag size={12} />}
                                      <span>
                                        {msg.jira.intent === "meeting"
                                          ? "Meeting"
                                          : msg.jira.intent === "deadline"
                                          ? "Deadline"
                                          : "Task"}
                                      </span>
                                    </span>

                                    <span className="jira-chip chip-assignee">
                                      <User size={12} />
                                      <span>{msg.jira.assignee_name || msg.jira.assignee_hint || "Unassigned"}</span>
                                    </span>

                                    {(msg.jira.due_date || msg.jira.due_time) && (
                                      <span className="jira-chip chip-due">
                                        <Clock size={12} />
                                        <span>{formatDueDateTime(msg.jira.due_date, msg.jira.due_time)}</span>
                                      </span>
                                    )}
                                  </div>

                                  {msg.jira.status === "failed" && msg.jira.error_message && (
                                    <div className="jira-card-error">
                                      <AlertCircle size={13} />
                                      <span>{msg.jira.error_message}</span>
                                    </div>
                                  )}

                                  <div className="jira-card-actions">
                                    <button
                                      type="button"
                                      className="btn-jira-create"
                                      onClick={() => handleConfirmSuggestion(msg.jira!.id)}
                                      disabled={confirmingLinkId === msg.jira.id || dismissingLinkId === msg.jira.id}
                                    >
                                      {confirmingLinkId === msg.jira.id ? (
                                        <>
                                          <Loader2 size={13} className="spin-animate" />
                                          <span>Creating...</span>
                                        </>
                                      ) : (
                                        <>
                                          <Plus size={13} />
                                          <span>{msg.jira.status === "failed" ? "Retry" : "Create"}</span>
                                        </>
                                      )}
                                    </button>
                                    <button
                                      type="button"
                                      className="btn-jira-dismiss"
                                      onClick={() => handleDismissSuggestion(msg.jira!.id)}
                                      disabled={confirmingLinkId === msg.jira.id || dismissingLinkId === msg.jira.id}
                                    >
                                      {dismissingLinkId === msg.jira.id ? (
                                        <Loader2 size={13} className="spin-animate" />
                                      ) : (
                                        "Dismiss"
                                      )}
                                    </button>
                                  </div>
                                </>
                              )}
                            </div>
                          )}
                        </div>
                      );
                    }

                    // AI mode (default/legacy behavior unchanged)
                    return (
                      <div key={msg.id} className="team-chat-thread">
                        <div className="chat-msg user-msg">
                          <div className="msg-header">
                            <strong className="sender">{msg.user_email}</strong>
                            <span className="time">{new Date(msg.created_at).toLocaleTimeString()}</span>
                          </div>
                          <div className="msg-body">{msg.message}</div>
                        </div>

                        <div className="chat-msg assistant-msg">
                          <div className="msg-header">
                            <strong className="sender">
                              <ShieldCheck size={14} /> Team AI Assistant
                            </strong>
                          </div>
                          <div className="msg-body">{msg.response}</div>

                          {msg.citations && msg.citations.length > 0 && (
                            <div className="citations-list">
                              <div className="citations-head">Retrieved Sources:</div>
                              {msg.citations.map((c, idx) => (
                                <div key={idx} className="citation-chip">
                                  <FileText size={12} />
                                  <span>{c.document_name} (Chunk #{c.chunk_index})</span>
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      </div>
                    );
                  })
                )}
              </div>

              {/* Active Temporary Team Documents */}
              {teamTempDocs.length > 0 && (
                <div className="temp-docs-chat-badge-bar team-temp-badge-bar">
                  <div className="temp-docs-badge-label">
                    <Sparkles size={13} style={{ color: "#2563eb" }} />
                    <span>Attached Team Documents (Scoped to {currentTeam.name}):</span>
                  </div>
                  <div className="temp-docs-chips-list">
                    {teamTempDocs.map((doc) => (
                      <div key={doc.document_id} className="temp-doc-active-chip">
                        <FileText size={13} className="chip-file-icon" />
                        <span className="chip-file-name" title={doc.name}>{doc.name}</span>
                        <span className="chip-chunks-count">({doc.chunk_count} chunks in Qdrant)</span>
                        <button
                          type="button"
                          onClick={() => handleDeleteTeamTempDoc(doc.document_id)}
                          className="chip-remove-btn"
                          title="Remove document from team Qdrant vectors"
                        >
                          <X size={13} />
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Mode Toggle Control Bar */}
              <div className="chat-mode-control-bar">
                <div className="segmented" role="radiogroup" aria-label="Chat Mode">
                  <button
                    type="button"
                    className={`segmented-btn ${chatMode === "ai" ? "active" : ""}`}
                    onClick={() => setChatMode("ai")}
                    title="Ask the Team AI Assistant questions about documents and project scope"
                  >
                    <Sparkles size={13} />
                    <span>Ask AI</span>
                  </button>
                  <button
                    type="button"
                    className={`segmented-btn ${chatMode === "team" ? "active" : ""}`}
                    onClick={() => setChatMode("team")}
                    title="Send a message to team members. Tasks & meetings can be exported to Jira."
                  >
                    <Users size={13} />
                    <span>Message team</span>
                  </button>
                </div>
                {chatMode === "team" && (
                  <span className="chat-mode-hint">
                    Visible to teammates. Tasks and meetings can be sent to Jira.
                  </span>
                )}
              </div>

              {/* Chat Input Bar */}
              <div className="team-chat-input-wrap">
                <form onSubmit={handleSendChat} className="glowing-glass-input-wrapper">
                  <input
                    type="file"
                    ref={teamFileInputRef}
                    style={{ display: "none" }}
                    accept=".pdf,.docx,.txt,.md,.csv,.json,.log,.pptx"
                    onChange={handleTeamFileUpload}
                  />
                  <div className="glowing-glass-input-inner">
                    <input
                      type="text"
                      className="chatbot-sticky-textarea"
                      style={{ minHeight: "38px", padding: "6px 8px" }}
                      placeholder={
                        chatMode === "team"
                          ? `Message teammates in ${currentTeam.name} (e.g. Rahul, finish the API in 2 days)...`
                          : teamTempDocs.length > 0
                          ? `Ask Team AI Assistant about "${teamTempDocs[0].name}" or ${currentTeam.project_name}...`
                          : `Ask Team AI Assistant about ${currentTeam.project_name}...`
                      }
                      value={inputMessage}
                      onChange={(e) => setInputMessage(e.target.value)}
                      disabled={sendingChat}
                    />
                    <div className="glowing-input-toolbar">
                      <div className="toolbar-left-group">
                        <button
                          type="button"
                          className="chatbot-attach-btn"
                          onClick={() => teamFileInputRef.current?.click()}
                          disabled={uploadingTeamDoc || sendingChat}
                          title="Upload document to ingest temporarily for this team workspace"
                        >
                          {uploadingTeamDoc ? <Loader2 size={16} className="animate-spin" /> : <Paperclip size={16} />}
                        </button>
                        <div className="mic-status-pill">
                          <Sparkles size={11} style={{ color: "var(--accent)" }} />
                          <span>{chatMode === "team" ? "Team Channel" : "Team RAG"}</span>
                        </div>
                      </div>
                      <button
                        type="submit"
                        className="round-send-btn"
                        disabled={sendingChat || !inputMessage.trim()}
                        title="Send message"
                      >
                        {sendingChat ? <Loader2 size={16} className="animate-spin" /> : <Send size={15} />}
                      </button>
                    </div>
                  </div>
                </form>
              </div>
            </div>
          </main>
        ) : (
          <div className="team-workspace-card card empty-state">
            <Users size={36} />
            <h3>Select a Team</h3>
            <p>Choose an active team from the list on the left or create a new team.</p>
          </div>
        )}
      </div>

      {/* JIRA SETTINGS MODAL */}
      {showJiraModal && currentTeam && (
        <div className="modal-overlay" onClick={() => setShowJiraModal(false)}>
          <div className="modal-content animated-scale-up jira-settings-modal" onClick={(e) => e.stopPropagation()}>
            <header className="modal-header">
              <div className="glow-icon">
                <Tag size={22} />
              </div>
              <div>
                <h3>Jira Integration Settings</h3>
                <p>Connect team workspace <strong>{currentTeam.name}</strong> to Jira Cloud</p>
              </div>
              <button
                type="button"
                className="close-btn"
                style={{ marginLeft: "auto" }}
                onClick={() => setShowJiraModal(false)}
                title="Close"
              >
                <X size={18} />
              </button>
            </header>

            <div className="modal-body jira-modal-body">
              {/* Status Box */}
              <div className="jira-status-card">
                <div className="jira-status-row">
                  <span className="jira-status-label">Status:</span>
                  {jiraStatus?.configured ? (
                    <span className="jira-status-pill connected">
                      <Check size={12} /> Connected to Jira Cloud
                    </span>
                  ) : (
                    <span className="jira-status-pill disconnected">
                      <AlertCircle size={12} /> Jira Credentials Missing
                    </span>
                  )}
                </div>
                <div className="jira-status-row">
                  <span className="jira-status-label">Base URL:</span>
                  <span className="jira-status-value">{jiraStatus?.base_url || "Not configured in backend"}</span>
                </div>
                <div className="jira-status-row">
                  <span className="jira-status-label">Default Project:</span>
                  <span className="jira-status-value">{jiraStatus?.default_project_key || "None"}</span>
                </div>
              </div>

              <div className="jira-notice-box">
                Messages sent in <strong>"Message team"</strong> mode are analyzed by AI to automatically suggest actionable tasks, deadlines, and meetings for Jira.
              </div>

              {/* Project Key Form */}
              <form onSubmit={handleSaveJiraSettings} className="jira-settings-form">
                <div className="form-group">
                  <label>Team Jira Project Key</label>
                  <input
                    type="text"
                    placeholder={jiraStatus?.default_project_key || "e.g. KAN"}
                    value={jiraProjectKeyInput}
                    onChange={(e) => setJiraProjectKeyInput(e.target.value.toUpperCase())}
                    disabled={!isLeadOrAdmin || savingJiraSettings}
                  />
                  <span className="form-help-text">
                    {isLeadOrAdmin
                      ? "Enter the Jira Project Key (e.g. KAN, PROJ). Leave empty to use system default."
                      : "Only team leads or enterprise admins can change the project key."}
                  </span>
                </div>

                <div className="modal-actions">
                  <button
                    type="button"
                    className="btn-outline"
                    onClick={() => setShowJiraModal(false)}
                    disabled={savingJiraSettings}
                  >
                    Close
                  </button>
                  {isLeadOrAdmin && (
                    <button type="submit" className="btn-primary" disabled={savingJiraSettings}>
                      {savingJiraSettings ? "Saving..." : "Save Settings"}
                    </button>
                  )}
                </div>
              </form>
            </div>
          </div>
        </div>
      )}

      {/* CREATE TEAM MODAL */}
      {showCreateModal && (
        <div className="modal-overlay" onClick={() => setShowCreateModal(false)}>
          <div className="modal-content animated-scale-up" onClick={(e) => e.stopPropagation()}>
            <header className="modal-header">
              <div className="glow-icon">
                <FolderKanban size={22} />
              </div>
              <div>
                <h3>Build New Project Team</h3>
                <p>Create a dedicated enterprise workspace and shared project chatbot</p>
              </div>
              <button
                type="button"
                className="close-btn"
                style={{ marginLeft: "auto" }}
                onClick={() => setShowCreateModal(false)}
                title="Close"
              >
                <X size={18} />
              </button>
            </header>
            <form onSubmit={handleCreateTeam} className="modal-body">
              <div className="form-group">
                <label>Team Name</label>
                <input
                  type="text"
                  placeholder="e.g. Cybersecurity Audit Team"
                  value={teamName}
                  onChange={(e) => setTeamName(e.target.value)}
                  required
                />
              </div>
              <div className="form-group">
                <label>Project Name / Scope</label>
                <input
                  type="text"
                  placeholder="e.g. Project Sentinel AI"
                  value={projectName}
                  onChange={(e) => setProjectName(e.target.value)}
                  required
                />
              </div>
              <div className="form-group">
                <label>Description (Optional)</label>
                <textarea
                  placeholder="Describe team objectives and project context..."
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  rows={3}
                />
              </div>

              <div className="modal-actions">
                <button type="button" className="btn-outline" onClick={() => setShowCreateModal(false)} disabled={creating}>
                  Cancel
                </button>
                <button type="submit" className="btn-primary" disabled={creating}>
                  {creating ? "Creating Team..." : "Create Team"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ADD MEMBER MODAL */}
      {showAddMemberModal && currentTeam && (
        <div className="modal-overlay" onClick={() => setShowAddMemberModal(false)}>
          <div className="modal-content add-member-modal animated-scale-up" onClick={(e) => e.stopPropagation()}>
            <header className="modal-header">
              <div className="glow-icon">
                <UserPlus size={22} />
              </div>
              <div>
                <h3>Add Member to {currentTeam.name}</h3>
                <p>Assign colleague to Project: <strong>{currentTeam.project_name}</strong></p>
              </div>
              <button
                type="button"
                className="close-btn"
                style={{ marginLeft: "auto" }}
                onClick={() => setShowAddMemberModal(false)}
                title="Close"
              >
                <X size={18} />
              </button>
            </header>

            <form onSubmit={handleAddMember} className="team-member-modal-body">
              {/* Hierarchy Policy Banner */}
              {(() => {
                const myRank = currentUser?.rank_level ?? 5;
                const isSysAdmin = currentUser?.email === "system@gmailexample.com" || (currentUser?.role === "admin" && myRank === 0);
                return (
                  <div className={`hierarchy-info-banner ${isSysAdmin ? "sysadmin-banner" : ""}`}>
                    <div className="hierarchy-banner-icon">
                      {isSysAdmin ? <Crown size={16} /> : <ShieldCheck size={16} />}
                    </div>
                    <div className="hierarchy-banner-text">
                      {isSysAdmin ? (
                        <span>
                          <strong>System Admin Access:</strong> You can assign colleagues across any enterprise rank level.
                        </span>
                      ) : (
                        <span>
                          <strong>Hierarchy RBAC Active:</strong> As <strong>Rank {myRank}</strong> ({currentUser?.role_key || currentUser?.role || "Staff"}), you can only assign colleagues ranked strictly below your level (<strong>Ranks {myRank + 1} to 5</strong>).
                        </span>
                      )}
                    </div>
                  </div>
                );
              })()}

              {/* Search Colleagues */}
              {(() => {
                const myRank = currentUser?.rank_level ?? 5;
                const isSysAdmin = currentUser?.email === "system@gmailexample.com" || (currentUser?.role === "admin" && myRank === 0);

                const eligibleColleagues = allUsers
                  .filter((u) => !currentTeam.members.some((m) => String(m.user_id) === String(u.id)))
                  .filter((u) => String(u.id) !== String(currentUser?.id))
                  .filter((u) => {
                    if (isSysAdmin) return true;
                    if (currentUser?.tenant_id && u.tenant_id && String(currentUser.tenant_id) !== String(u.tenant_id)) {
                      return false;
                    }
                    return (u.rank_level ?? 5) > myRank;
                  });

                const searchedCandidates = eligibleColleagues.filter((u) => {
                  if (!userSearchTerm.trim()) return true;
                  const q = userSearchTerm.toLowerCase();
                  return (
                    u.email.toLowerCase().includes(q) ||
                    (u.role_key && u.role_key.toLowerCase().includes(q)) ||
                    (u.role && u.role.toLowerCase().includes(q)) ||
                    (u.display_name && u.display_name.toLowerCase().includes(q))
                  );
                });

                return (
                  <>
                    <div className="form-group">
                      <div className="label-with-badge">
                        <label style={{ fontSize: "12px", fontWeight: 700, color: "var(--text-muted)" }}>
                          Select Colleague
                        </label>
                        <span className="candidate-count-tag">
                          {searchedCandidates.length} eligible
                        </span>
                      </div>
                      <div className="team-search-box">
                        <Search size={15} className="search-icon" />
                        <input
                          type="text"
                          placeholder="Search by email, name, or role..."
                          value={userSearchTerm}
                          onChange={(e) => setUserSearchTerm(e.target.value)}
                        />
                        {userSearchTerm && (
                          <button
                            type="button"
                            className="clear-search-btn"
                            onClick={() => setUserSearchTerm("")}
                            title="Clear search"
                          >
                            <X size={13} />
                          </button>
                        )}
                      </div>
                    </div>

                    {/* Scrollable Candidate Cards */}
                    <div className="candidate-users-list">
                      {searchedCandidates.map((u) => {
                        const isSelected = selectedUserId === String(u.id);
                        const initial = (u.display_name || u.email || "U").charAt(0).toUpperCase();
                        const rankVal = u.rank_level ?? 5;
                        return (
                          <div
                            key={String(u.id)}
                            className={`candidate-user-card ${isSelected ? "selected" : ""}`}
                            onClick={() => setSelectedUserId(String(u.id))}
                          >
                            <div className="user-card-left">
                              <div className={`user-avatar-circle rank-avatar-${rankVal}`}>
                                {initial}
                              </div>
                              <div className="user-card-info">
                                <div className="user-card-top-row">
                                  <span className="user-card-name">
                                    {u.display_name || u.email.split("@")[0]}
                                  </span>
                                  <span className={`rank-badge-pill rank-${rankVal}`}>
                                    Rank {rankVal}
                                  </span>
                                </div>
                                <span className="user-card-email">{u.email}</span>
                                <div className="user-card-sub">
                                  <span className="role-key-pill">{u.role_key || u.role}</span>
                                  {u.enterprise_name && <span className="tenant-pill">{u.enterprise_name}</span>}
                                </div>
                              </div>
                            </div>
                            <div className="user-card-right">
                              {isSelected ? (
                                <CheckCircle2 size={18} className="check-icon-active" />
                              ) : (
                                <div className="select-radio-circle" />
                              )}
                            </div>
                          </div>
                        );
                      })}

                      {eligibleColleagues.length === 0 && (
                        <div className="candidate-empty-state">
                          <AlertCircle size={28} className="empty-icon" />
                          <div className="empty-title">
                            {myRank >= 5
                              ? "No Subordinate Colleagues Below Your Rank"
                              : "No Available Colleagues"}
                          </div>
                          <p className="empty-desc">
                            {myRank >= 5
                              ? `You are at Rank ${myRank} (baseline employee rank). Company RBAC policy requires Rank 4 or higher to add subordinate team members.`
                              : `All colleagues below your rank (Rank ${myRank}) are already in this team, or no other colleagues exist.`}
                          </p>
                        </div>
                      )}

                      {eligibleColleagues.length > 0 && searchedCandidates.length === 0 && (
                        <div className="candidate-empty-state">
                          <Search size={24} className="empty-icon" />
                          <div className="empty-title">No Matching Colleagues</div>
                          <p className="empty-desc">
                            No eligible colleague found matching "{userSearchTerm}".
                          </p>
                        </div>
                      )}
                    </div>
                  </>
                );
              })()}

              {/* Team Role Cards */}
              <div className="form-group">
                <label style={{ fontSize: "12px", fontWeight: 700, color: "var(--text-muted)" }}>
                  Assign Role in Team
                </label>
                <div className="role-selection-grid">
                  <div
                    className={`role-option-card ${teamRole === "member" ? "active" : ""}`}
                    onClick={() => setTeamRole("member")}
                  >
                    <div className="role-option-title">
                      <Users size={15} /> <span>Team Member</span>
                    </div>
                    <div className="role-option-desc">Collaborator with team workspace RAG search & chat access</div>
                  </div>

                  <div
                    className={`role-option-card ${teamRole === "lead" ? "active" : ""}`}
                    onClick={() => setTeamRole("lead")}
                  >
                    <div className="role-option-title">
                      <Crown size={15} /> <span>Team Lead</span>
                    </div>
                    <div className="role-option-desc">Project lead with membership management permissions</div>
                  </div>
                </div>
              </div>

              {/* Modal Actions */}
              <div className="modal-actions">
                <button
                  type="button"
                  className="btn-outline"
                  onClick={() => setShowAddMemberModal(false)}
                  disabled={addingMember}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="btn-primary"
                  disabled={!selectedUserId || addingMember}
                >
                  {addingMember ? (
                    <>
                      <Loader2 size={15} className="spin-animate" />
                      <span>Adding Member...</span>
                    </>
                  ) : (
                    <>
                      <UserPlus size={15} />
                      <span>Add to Team</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}