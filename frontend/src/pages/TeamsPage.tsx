import React, { useEffect, useState } from "react";
import { Users, Plus, MessageSquare, FolderKanban, UserPlus, Trash2, Send, ShieldCheck, FileText, CheckCircle2 } from "lucide-react";
import { TeamChatMessageItem, TeamItem, UserProfile, request } from "../api";

interface TeamsPageProps {
  currentUser: UserProfile | null;
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
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [teamRole, setTeamRole] = useState("member");

  // Shared Chat State
  const [chatMessages, setChatMessages] = useState<TeamChatMessageItem[]>([]);
  const [inputMessage, setInputMessage] = useState("");
  const [sendingChat, setSendingChat] = useState(false);

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
    } catch (err) {
      console.error("Failed to load team chat", err);
    }
  };

  useEffect(() => {
    loadTeamsAndUsers();
  }, []);

  useEffect(() => {
    if (activeTeamId) {
      loadTeamChat(activeTeamId);
    }
  }, [activeTeamId]);

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
      setSelectedUserId(null);
    } catch (err) {
      alert((err as Error).message || "Failed to add member to team");
    }
  };

  const handleRemoveMember = async (teamId: number, userId: number) => {
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
        body: JSON.stringify({ message: messageText }),
      });

      setChatMessages((prev) => [...prev, newMsg]);
    } catch (err) {
      alert((err as Error).message || "Failed to send chat message");
    } finally {
      setSendingChat(false);
    }
  };

  const currentTeam = teams.find((t) => t.id === activeTeamId);

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
        <aside className="teams-sidebar-card card">
          <div className="card-header-title">
            <FolderKanban size={16} />
            <span>Active Project Teams ({teams.length})</span>
          </div>

          <div className="team-list">
            {teams.length === 0 ? (
              <div className="empty-subtext">No active project teams yet. Click "Build New Team" to create one.</div>
            ) : (
              teams.map((t) => (
                <div
                  key={t.id}
                  className={`team-item-card ${activeTeamId === t.id ? "active" : ""}`}
                  onClick={() => setActiveTeamId(t.id)}
                >
                  <div className="team-item-title">{t.name}</div>
                  <div className="team-project-tag">Project: {t.project_name}</div>
                  <div className="team-meta">{t.members.length} Members</div>
                </div>
              ))
            )}
          </div>
        </aside>

        {/* Right Area: Team Workspace & Shared Chatbot */}
        {currentTeam ? (
          <main className="team-workspace-card card">
            <header className="team-workspace-header">
              <div>
                <h2>{currentTeam.name}</h2>
                <div className="project-badge">
                  <FolderKanban size={14} /> Project Scope: {currentTeam.project_name}
                </div>
                {currentTeam.description && <p className="team-desc">{currentTeam.description}</p>}
              </div>
              <button className="btn-secondary" onClick={() => setShowAddMemberModal(true)}>
                <UserPlus size={15} /> Add Member
              </button>
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

            {/* Shared Chatbot Section */}
            <div className="team-chat-container">
              <div className="chat-section-header">
                <MessageSquare size={16} />
                <span>Shared Team Chatbot Assistant ({currentTeam.project_name})</span>
              </div>

              <div className="team-chat-messages">
                {chatMessages.length === 0 ? (
                  <div className="empty-chat-state">
                    <MessageSquare size={32} />
                    <p>No query history in this project team yet.</p>
                    <span>Ask a question below to query enterprise documents in project scope.</span>
                  </div>
                ) : (
                  chatMessages.map((msg) => (
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
                  ))
                )}
              </div>

              {/* Chat Input Bar */}
              <form onSubmit={handleSendChat} className="team-chat-input-form">
                <input
                  type="text"
                  placeholder={`Ask Team AI Assistant about ${currentTeam.project_name}...`}
                  value={inputMessage}
                  onChange={(e) => setInputMessage(e.target.value)}
                  disabled={sendingChat}
                />
                <button type="submit" className="btn-primary" disabled={sendingChat || !inputMessage.trim()}>
                  {sendingChat ? "Querying..." : <Send size={16} />}
                </button>
              </form>
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

      {/* CREATE TEAM MODAL */}
      {showCreateModal && (
        <div className="modal-backdrop">
          <div className="modal-card">
            <header className="modal-header">
              <h3>Build New Project Team</h3>
              <button className="close-btn" onClick={() => setShowCreateModal(false)}>
                ×
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

              <div className="modal-footer">
                <button type="button" className="btn-outline" onClick={() => setShowCreateModal(false)}>
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
      {showAddMemberModal && (
        <div className="modal-backdrop">
          <div className="modal-card">
            <header className="modal-header">
              <h3>Add User to {currentTeam?.name}</h3>
              <button className="close-btn" onClick={() => setShowAddMemberModal(false)}>
                ×
              </button>
            </header>
            <form onSubmit={handleAddMember} className="modal-body">
              <div className="form-group">
                <label>Select User</label>
                <select
                  value={selectedUserId || ""}
                  onChange={(e) => setSelectedUserId(Number(e.target.value))}
                  required
                >
                  <option value="">-- Choose User Account --</option>
                  {allUsers
                    .filter((u) => !currentTeam?.members.some((m) => m.user_id === u.id))
                    .map((u) => (
                      <option key={u.id} value={u.id}>
                        {u.email} (Rank {u.rank_level}: {u.role_key})
                      </option>
                    ))}
                </select>
              </div>

              <div className="form-group">
                <label>Team Role</label>
                <select value={teamRole} onChange={(e) => setTeamRole(e.target.value)}>
                  <option value="member">Team Member</option>
                  <option value="lead">Team Lead</option>
                </select>
              </div>

              <div className="modal-footer">
                <button type="button" className="btn-outline" onClick={() => setShowAddMemberModal(false)}>
                  Cancel
                </button>
                <button type="submit" className="btn-primary" disabled={!selectedUserId}>
                  Add to Team
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
