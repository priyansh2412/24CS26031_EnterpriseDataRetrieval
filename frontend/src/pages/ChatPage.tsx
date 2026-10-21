import { useEffect, useRef, useState } from "react";
import {
  ArrowUp,
  Check,
  Copy,
  Sparkles,
  ThumbsDown,
  ThumbsUp,
  FileText,
  Zap,
  Bot,
  User,
  Compass,
  Search,
  X,
  ChevronUp,
  ChevronDown,
  Plus,
  MessageSquare,
  History,
  Trash2,
  Paperclip,
  Upload,
  Loader2,
} from "lucide-react";
import { TempDocItem, request } from "../api";

export type Citation = { document_id: number; document_name: string; chunk_index: number; text: string; score: number };

export interface ChatMessage {
  id: string;
  sender: "user" | "assistant";
  text: string;
  citations?: Citation[];
  query_log_id?: number;
  timestamp: string;
  feedbackGiven?: boolean | null;
  session_id?: string;
}

export interface ChatSession {
  session_id: string;
  title: string;
  created_at: string;
  message_count: number;
}

interface DocItem {
  id: number;
  name: string;
  summary?: string;
}

interface AnalyticsOverview {
  popular_queries: { query: string; count: number }[];
}

interface DynamicQuery {
  id: string;
  docName?: string;
  title: string;
  query: string;
}

export default function ChatPage() {
  const [sessions, setSessions] = useState<ChatSession[]>([]);
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputQuestion, setInputQuestion] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [dynamicQueries, setDynamicQueries] = useState<DynamicQuery[]>([]);
  const [searchTerm, setSearchTerm] = useState("");
  const [activeMatchIndex, setActiveMatchIndex] = useState(0);

  // Temporary Document State (Scoped to current user's session only)
  const [tempDocs, setTempDocs] = useState<TempDocItem[]>([]);
  const [uploadingDoc, setUploadingDoc] = useState(false);
  const [uploadNotice, setUploadNotice] = useState("");

  const chatEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const msgRefs = useRef<{ [id: string]: HTMLDivElement | null }>({});

  const fetchTempDocs = async () => {
    try {
      const docs = await request<TempDocItem[]>("/api/chat/temp-docs");
      setTempDocs(docs || []);
    } catch {
      setTempDocs([]);
    }
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingDoc(true);
    setError("");
    setUploadNotice("");
    try {
      const formData = new FormData();
      formData.append("file", file);
      if (activeSessionId) {
        formData.append("session_id", activeSessionId);
      }
      await request<TempDocItem>("/api/chat/upload-temp", {
        method: "POST",
        body: formData,
      });
      setUploadNotice(`"${file.name}" ingested into temporary Qdrant vectors! You can now ask questions about it.`);
      await fetchTempDocs();
    } catch (err) {
      setError((err as Error).message || "Failed to upload document");
    } finally {
      setUploadingDoc(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const handleDeleteTempDoc = async (docId: string) => {
    try {
      await request(`/api/chat/temp-docs/${encodeURIComponent(docId)}`, { method: "DELETE" });
      setTempDocs((prev) => prev.filter((d) => d.document_id !== docId));
      setUploadNotice("");
    } catch (err) {
      setError((err as Error).message || "Failed to remove temporary document");
    }
  };

  // Fetch past search sessions from backend
  const fetchSessions = async (autoSelectFirst = false) => {
    try {
      const sessList = await request<ChatSession[]>("/api/chat/sessions");
      setSessions(sessList || []);
      if (autoSelectFirst && sessList && sessList.length > 0 && !activeSessionId) {
        setActiveSessionId(sessList[0].session_id);
        loadSessionHistory(sessList[0].session_id);
      }
    } catch {
      setSessions([]);
    }
  };

  // Load chat history for a given search session
  const loadSessionHistory = async (sessId: string) => {
    try {
      setLoading(true);
      const history = await request<ChatMessage[]>(`/api/chat/history?session_id=${encodeURIComponent(sessId)}`);
      setMessages(history || []);
    } catch {
      setMessages([]);
    } finally {
      setLoading(false);
    }
  };

  // On mount, load sessions list & temp docs
  useEffect(() => {
    fetchSessions(true);
    fetchTempDocs();
  }, []);

  // Auto-scroll chat stream to bottom when new messages arrive (unless user is searching)
  useEffect(() => {
    if (!searchTerm.trim()) {
      chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, loading, searchTerm]);

  // Compute search match messages
  const searchMatches = searchTerm.trim()
    ? messages.filter((m) => m.text.toLowerCase().includes(searchTerm.toLowerCase()))
    : [];

  // Reset active match index when search term changes
  useEffect(() => {
    setActiveMatchIndex(0);
  }, [searchTerm]);

  // Smoothly scroll to the active search match message when search term or match index changes
  useEffect(() => {
    if (searchMatches.length > 0) {
      const validIndex = Math.min(activeMatchIndex, searchMatches.length - 1);
      const targetMsg = searchMatches[validIndex];
      if (targetMsg && msgRefs.current[targetMsg.id]) {
        msgRefs.current[targetMsg.id]?.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    }
  }, [searchTerm, activeMatchIndex, searchMatches.length]);

  const handleNextMatch = () => {
    if (searchMatches.length > 0) {
      setActiveMatchIndex((prev) => (prev + 1) % searchMatches.length);
    }
  };

  const handlePrevMatch = () => {
    if (searchMatches.length > 0) {
      setActiveMatchIndex((prev) => (prev - 1 + searchMatches.length) % searchMatches.length);
    }
  };

  // Dynamically load document names & analytics queries to build recommendation pills
  useEffect(() => {
    async function loadDynamicPrompts() {
      try {
        const [docs, analytics] = await Promise.all([
          request<DocItem[]>("/api/documents").catch(() => []),
          request<AnalyticsOverview>("/api/analytics/overview").catch(() => null),
        ]);

        const generated: DynamicQuery[] = [];

        if (analytics?.popular_queries?.length) {
          analytics.popular_queries.slice(0, 2).forEach((pq, idx) => {
            generated.push({
              id: `pop-${idx}`,
              title: "Popular Ask",
              query: pq.query,
            });
          });
        }

        if (docs?.length) {
          docs.slice(0, 4).forEach((doc, idx) => {
            const cleanName = doc.name.replace(/\.[^/.]+$/, "");
            if (cleanName.toLowerCase().includes("handbook") || cleanName.toLowerCase().includes("hr")) {
              generated.push({
                id: `doc-${idx}-1`,
                docName: doc.name,
                title: cleanName,
                query: `What is the leave policy in ${doc.name}?`,
              });
              generated.push({
                id: `doc-${idx}-2`,
                docName: doc.name,
                title: cleanName,
                query: `What are remote work guidelines in ${doc.name}?`,
              });
            } else if (cleanName.toLowerCase().includes("cyber") || cleanName.toLowerCase().includes("security")) {
              generated.push({
                id: `doc-${idx}-3`,
                docName: doc.name,
                title: cleanName,
                query: `What are key security rules in ${doc.name}?`,
              });
            } else {
              generated.push({
                id: `doc-${idx}-gen`,
                docName: doc.name,
                title: cleanName,
                query: `Summarize key information from ${doc.name}`,
              });
            }
          });
        }

        if (!generated.length) {
          generated.push(
            { id: "f1", title: "HR Policy", query: "What is our annual paid leave policy?" },
            { id: "f2", title: "Security Rules", query: "What are the remote work security guidelines?" },
            { id: "f3", title: "Benefits", query: "What learning stipends are provided?" },
            { id: "f4", title: "Ethics", query: "What are the rules regarding confidentiality?" }
          );
        }

        const unique = Array.from(new Map(generated.map((g) => [g.query, g])).values()).slice(0, 4);
        setDynamicQueries(unique);
      } catch {
        setDynamicQueries([
          { id: "f1", title: "HR Policy", query: "What is our annual paid leave policy?" },
          { id: "f2", title: "Security Rules", query: "What are the remote work security guidelines?" },
        ]);
      }
    }

    loadDynamicPrompts();
  }, []);

  // Handle starting a fresh new chat search session
  const handleNewChat = () => {
    setActiveSessionId(null);
    setMessages([]);
    setInputQuestion("");
    setError("");
    textareaRef.current?.focus();
  };

  // Switch to a selected past search session
  const handleSelectSession = (sessionId: string) => {
    if (activeSessionId === sessionId) return;
    setActiveSessionId(sessionId);
    setSearchTerm("");
    loadSessionHistory(sessionId);
  };

  // Delete a specific search session
  const handleDeleteSession = async (sessionId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    try {
      await request(`/api/chat/sessions/${encodeURIComponent(sessionId)}`, { method: "DELETE" });
      const updatedSessions = sessions.filter((s) => s.session_id !== sessionId);
      setSessions(updatedSessions);
      if (activeSessionId === sessionId) {
        if (updatedSessions.length > 0) {
          setActiveSessionId(updatedSessions[0].session_id);
          loadSessionHistory(updatedSessions[0].session_id);
        } else {
          handleNewChat();
        }
      }
    } catch (err) {
      setError((err as Error).message || "Failed to delete session");
    }
  };

  // Send a new query to current or new search session
  const handleSend = async (textToSend = inputQuestion) => {
    const queryText = textToSend.trim();
    if (!queryText || loading) return;

    const userMessage: ChatMessage = {
      id: `usr-${Date.now()}`,
      sender: "user",
      text: queryText,
      timestamp: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
    };

    setMessages((prev) => [...prev, userMessage]);
    setInputQuestion("");
    setError("");
    setLoading(true);

    try {
      const result = await request<{ query_log_id: number; answer: string; citations: Citation[]; session_id: string }>(
        "/api/chat/ask",
        {
          method: "POST",
          body: JSON.stringify({ question: queryText, top_k: 5, session_id: activeSessionId || undefined }),
        }
      );

      const assistantMessage: ChatMessage = {
        id: `ast-${Date.now()}`,
        sender: "assistant",
        text: result.answer,
        citations: result.citations,
        query_log_id: result.query_log_id,
        timestamp: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
        session_id: result.session_id,
      };

      setMessages((prev) => [...prev, assistantMessage]);

      // If it was a new chat session, register the newly generated session_id
      if (!activeSessionId && result.session_id) {
        setActiveSessionId(result.session_id);
      }
      fetchSessions();
    } catch (e) {
      setError((e as Error).message || "Failed to retrieve answer");
    } finally {
      setLoading(false);
    }
  };

  const handleFeedback = async (messageId: string, queryLogId: number, is_positive: boolean) => {
    try {
      await request("/api/feedback", {
        method: "POST",
        body: JSON.stringify({ query_log_id: queryLogId, is_positive }),
      });
      setMessages((prev) =>
        prev.map((msg) => (msg.id === messageId ? { ...msg, feedbackGiven: is_positive } : msg))
      );
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const copyText = async (id: string, text: string) => {
    await navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 1600);
  };

  // Extract unique referenced source file names from the latest assistant message
  const lastAssistantMsg = [...messages].reverse().find((m) => m.sender === "assistant" && m.citations && m.citations.length > 0);
  const referencedFileNames = Array.from(new Set(lastAssistantMsg?.citations?.map((c) => c.document_name) || []));

  const activeSessionObj = sessions.find((s) => s.session_id === activeSessionId);

  return (
    <div className="chat-page real-chatbot-layout">
      {/* Real Chatbot Page Header */}
      <header className="page-heading chatbot-top-header">
        <div>
          <div className="eyebrow chat-eyebrow">
            <Sparkles size={14} /> AI SEARCH SESSIONS & CONVERSATIONAL ASSISTANT
          </div>
          <h1 className="chat-main-title">
            Atlas <span className="highlight-text">Search Sessions</span>
          </h1>
        </div>

        <div className="header-actions">
          {/* Header Search Box with Match Navigation */}
          <div className="header-search-box">
            <Search size={15} className="search-icon" />
            <input
              type="text"
              placeholder="Search in active chat..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="header-search-input"
            />
            {searchTerm.trim() && (
              <div className="search-match-nav">
                <span className="search-count-badge">
                  {searchMatches.length > 0 ? `${activeMatchIndex + 1}/${searchMatches.length}` : "0"}
                </span>
                {searchMatches.length > 0 && (
                  <>
                    <button className="search-nav-btn" onClick={handlePrevMatch} title="Previous match">
                      <ChevronUp size={13} />
                    </button>
                    <button className="search-nav-btn" onClick={handleNextMatch} title="Next match">
                      <ChevronDown size={13} />
                    </button>
                  </>
                )}
                <button className="search-clear-btn" onClick={() => setSearchTerm("")} title="Clear search">
                  <X size={13} />
                </button>
              </div>
            )}
          </div>

          <div className="online-indicator-badge chat-status-badge">
            <Zap size={13} />
            <span>RAG Engine Connected</span>
          </div>
        </div>
      </header>

      {/* Main Split Layout: Past Search Sessions Sidebar + Chatbot Workspace */}
      <div className="chat-sessions-split-layout">
        {/* Left Panel: Past Search Sessions Menu */}
        <aside className="sessions-sidebar-panel">
          <div className="sessions-panel-header">
            <button className="new-session-btn" onClick={handleNewChat}>
              <Plus size={16} />
              <span>New Search Session</span>
            </button>
          </div>

          <div className="sessions-list-wrap">
            <div className="sessions-section-title">
              <History size={13} />
              <span>PAST SEARCH SESSIONS ({sessions.length})</span>
            </div>

            {sessions.length === 0 ? (
              <div className="empty-sessions-note">
                <MessageSquare size={24} />
                <p>No past search sessions yet. Click "+ New Search Session" to begin!</p>
              </div>
            ) : (
              <div className="sessions-items-list">
                {sessions.map((sess) => {
                  const isActive = activeSessionId === sess.session_id;
                  return (
                    <div
                      key={sess.session_id}
                      className={`session-item-card ${isActive ? "active" : ""}`}
                      onClick={() => handleSelectSession(sess.session_id)}
                    >
                      <MessageSquare size={16} className="session-card-icon" />
                      <div className="session-card-info">
                        <strong className="session-card-title">{sess.title}</strong>
                        <div className="session-card-meta">
                          <span className="session-card-date">{sess.created_at}</span>
                          <span className="session-card-badge">{sess.message_count} msgs</span>
                        </div>
                      </div>
                      <button
                        className="session-delete-btn"
                        onClick={(e) => handleDeleteSession(sess.session_id, e)}
                        title="Delete session"
                      >
                        <Trash2 size={13} />
                      </button>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </aside>

        {/* Right Panel: Main Chatbot Container */}
        <div className="chatbot-spacious-container">
          {/* Chat Feed Area */}
          <div className="chat-feed-scroll">
            {messages.length === 0 ? (
              <div className="chatbot-welcome-state">
                <div className="welcome-avatar-glow">
                  <Bot size={36} />
                </div>
                <h2>{activeSessionObj ? activeSessionObj.title : "Start a New Search Session"}</h2>
                <p>Ask questions grounded directly on your organization’s uploaded documents and handbooks.</p>
              </div>
            ) : (
              <div className="chat-stream-list">
                {messages.map((msg) => {
                  const isMatch = Boolean(searchTerm.trim() && msg.text.toLowerCase().includes(searchTerm.toLowerCase()));
                  const activeTargetMsg = searchMatches[activeMatchIndex];
                  const isActiveTarget = isMatch && activeTargetMsg && activeTargetMsg.id === msg.id;

                  return (
                    <div
                      key={msg.id}
                      ref={(el) => {
                        msgRefs.current[msg.id] = el;
                      }}
                      className={`chat-message-row ${msg.sender === "user" ? "user-row" : "assistant-row"} ${
                        isMatch ? "search-match-row" : ""
                      }`}
                    >
                      <div className={`message-avatar ${msg.sender}`}>
                        {msg.sender === "user" ? <User size={16} /> : <Bot size={18} />}
                      </div>

                      <div className="message-content-wrapper">
                        <div className="message-header-meta">
                          <strong className="sender-name">
                            {msg.sender === "user" ? "You" : "Atlas AI Assistant"}
                          </strong>
                          <span className="timestamp-tag">{msg.timestamp}</span>
                        </div>

                        <div
                          className={`message-bubble ${
                            isActiveTarget ? "search-active-target" : isMatch ? "search-highlight-bubble" : ""
                          }`}
                        >
                          <div className="bubble-text">{msg.text}</div>

                          {/* Assistant Actions (Copy & Feedback) */}
                          {msg.sender === "assistant" && (
                            <div className="bubble-actions">
                              {msg.query_log_id && (
                                <div className="feedback">
                                  <span>Helpful?</span>
                                  <button
                                    className={`feedback-btn ${msg.feedbackGiven === true ? "selected" : ""}`}
                                    onClick={() => handleFeedback(msg.id, msg.query_log_id!, true)}
                                    aria-label="Helpful"
                                  >
                                    <ThumbsUp size={13} />
                                  </button>
                                  <button
                                    className={`feedback-btn ${msg.feedbackGiven === false ? "selected" : ""}`}
                                    onClick={() => handleFeedback(msg.id, msg.query_log_id!, false)}
                                    aria-label="Not helpful"
                                  >
                                    <ThumbsDown size={13} />
                                  </button>
                                </div>
                              )}

                              <button
                                className="btn-copy-bubble"
                                onClick={() => copyText(msg.id, msg.text)}
                              >
                                {copiedId === msg.id ? <Check size={13} /> : <Copy size={13} />}
                                <span>{copiedId === msg.id ? "Copied" : "Copy"}</span>
                              </button>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}

                {loading && (
                  <div className="chat-message-row assistant-row">
                    <div className="message-avatar assistant">
                      <Bot size={18} />
                    </div>
                    <div className="message-content-wrapper">
                      <div className="message-bubble thinking-bubble">
                        <div className="thinking-dots">
                          <span />
                          <span />
                          <span />
                        </div>
                        <span>Atlas is retrieving vector chunks & generating answer…</span>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}

            <div ref={chatEndRef} />
          </div>

          {/* Error Alert */}
          {error && <div className="alert-banner error margin-bottom">{error}</div>}

          {/* Success / Status Notice */}
          {uploadNotice && (
            <div className="alert-banner success margin-bottom" style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
              <span>{uploadNotice}</span>
              <button type="button" onClick={() => setUploadNotice("")} style={{ background: "none", border: "none", cursor: "pointer", color: "inherit" }}>
                <X size={14} />
              </button>
            </div>
          )}

          {/* Sticky Input Bar at Bottom */}
          <div className="chatbot-input-bar-wrap">
            {/* Active Temporary Documents Pills */}
            {tempDocs.length > 0 && (
              <div className="temp-docs-chat-badge-bar">
                <div className="temp-docs-badge-label">
                  <Sparkles size={13} style={{ color: "#2563eb" }} />
                  <span>Your Attached Temporary Document (Private to this chat):</span>
                </div>
                <div className="temp-docs-chips-list">
                  {tempDocs.map((doc) => (
                    <div key={doc.document_id} className="temp-doc-active-chip">
                      <FileText size={13} className="chip-file-icon" />
                      <span className="chip-file-name" title={doc.name}>{doc.name}</span>
                      <span className="chip-chunks-count">({doc.chunk_count} chunks in Qdrant)</span>
                      <button
                        type="button"
                        onClick={() => handleDeleteTempDoc(doc.document_id)}
                        className="chip-remove-btn"
                        title="Remove document from temporary Qdrant vectors"
                      >
                        <X size={13} />
                      </button>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <form
              onSubmit={(e) => {
                e.preventDefault();
                handleSend();
              }}
              className="chatbot-input-form"
            >
              {/* Hidden file input */}
              <input
                type="file"
                ref={fileInputRef}
                style={{ display: "none" }}
                accept=".pdf,.docx,.txt,.md,.csv,.json,.log,.pptx"
                onChange={handleFileUpload}
              />
              <button
                type="button"
                className="chatbot-attach-btn"
                onClick={() => fileInputRef.current?.click()}
                disabled={uploadingDoc || loading}
                title="Upload document to ingest temporarily into Qdrant for this chat"
              >
                {uploadingDoc ? <Loader2 size={18} className="spin-animate" /> : <Paperclip size={18} />}
              </button>

              <textarea
                ref={textareaRef}
                rows={1}
                value={inputQuestion}
                onChange={(e) => setInputQuestion(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    handleSend();
                  }
                }}
                placeholder={
                  tempDocs.length > 0
                    ? `Ask Atlas AI about "${tempDocs[0].name}" or your enterprise documents...`
                    : "Ask Atlas AI anything about your enterprise documents..."
                }
                className="chatbot-sticky-textarea"
              />
              <button
                type="submit"
                className="chatbot-send-btn"
                disabled={loading || !inputQuestion.trim()}
                title="Send question"
              >
                <ArrowUp size={18} />
              </button>
            </form>

            {/* Referenced Source Files Small Section */}
            {referencedFileNames.length > 0 && (
              <div className="referenced-sources-small-bar">
                <div className="sources-small-header">
                  <FileText size={13} />
                  <span>REFERENCED SOURCE FILES:</span>
                </div>
                <div className="sources-small-tags">
                  {referencedFileNames.map((fileName, idx) => (
                    <span key={`ref-file-${idx}`} className="source-file-pill">
                      <FileText size={12} className="pill-icon" />
                      <span className="pill-name">{fileName}</span>
                    </span>
                  ))}
                </div>
              </div>
            )}

            {/* Dynamic Recommendations Section */}
            {dynamicQueries.length > 0 && (
              <div className="dynamic-recommendations-wrapper recommendations-below-input">
                <div className="recommendations-header">
                  <Compass size={13} />
                  <span>DYNAMIC SUGGESTED QUERIES (FROM YOUR DB)</span>
                </div>
                <div className="recommendations-scroll-row">
                  {dynamicQueries.map((dq) => (
                    <button
                      key={dq.id}
                      className="recommendation-chip-btn"
                      onClick={() => handleSend(dq.query)}
                      disabled={loading}
                    >
                      <FileText size={13} className="chip-icon" />
                      <div className="chip-content">
                        <strong className="chip-title">{dq.title}</strong>
                        <span className="chip-query-text">{dq.query}</span>
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
