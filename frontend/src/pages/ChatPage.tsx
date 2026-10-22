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
  BookOpen,
} from "lucide-react";
import { TempDocItem, request } from "../api";

export type Citation = {
  document_id: number;
  document_name: string;
  chunk_index: number;
  text: string;
  score: number;
};

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

  // Expanded Citation Accordions State (map of messageId-citIndex -> boolean)
  const [expandedCitations, setExpandedCitations] = useState<{ [key: string]: boolean }>({});
  // Highlighted citation state (for scrolling from inline badges)
  const [highlightedCitation, setHighlightedCitation] = useState<string | null>(null);
  // Toggle for Prompts Tray
  const [showPromptsTray, setShowPromptsTray] = useState(false);

  // Temporary Document State
  const [tempDocs, setTempDocs] = useState<TempDocItem[]>([]);
  const [uploadingDoc, setUploadingDoc] = useState(false);
  const [uploadNotice, setUploadNotice] = useState("");

  const chatEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const msgRefs = useRef<{ [id: string]: HTMLDivElement | null }>({});
  const citationRefs = useRef<{ [key: string]: HTMLDivElement | null }>({});

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
      setUploadNotice(`"${file.name}" ingested into temporary vectors! You can now query it.`);
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

  // On mount, check sessions, temp docs, and quick-ask from Dashboard
  useEffect(() => {
    fetchSessions(true);
    fetchTempDocs();

    const storedQuickAsk = sessionStorage.getItem("atlas_quick_ask");
    if (storedQuickAsk) {
      sessionStorage.removeItem("atlas_quick_ask");
      // Trigger send for stored query
      setTimeout(() => {
        handleSend(storedQuickAsk);
      }, 250);
    }
  }, []);

  // Auto-scroll chat stream to bottom when new messages arrive
  useEffect(() => {
    if (!searchTerm.trim()) {
      chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, loading, searchTerm]);

  // Adjust textarea height automatically
  useEffect(() => {
    if (textareaRef.current) {
      textareaRef.current.style.height = "auto";
      textareaRef.current.style.height = `${Math.min(textareaRef.current.scrollHeight, 160)}px`;
    }
  }, [inputQuestion]);

  // Search match messages
  const searchMatches = searchTerm.trim()
    ? messages.filter((m) => m.text.toLowerCase().includes(searchTerm.toLowerCase()))
    : [];

  useEffect(() => {
    setActiveMatchIndex(0);
  }, [searchTerm]);

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

  // Dynamically load document names & analytics queries to build recommendation starter pills
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
                title: "HR Guidelines",
                query: `What is the leave policy in ${doc.name}?`,
              });
              generated.push({
                id: `doc-${idx}-2`,
                docName: doc.name,
                title: "Work Policy",
                query: `What are remote work guidelines in ${doc.name}?`,
              });
            } else if (cleanName.toLowerCase().includes("cyber") || cleanName.toLowerCase().includes("security")) {
              generated.push({
                id: `doc-${idx}-3`,
                docName: doc.name,
                title: "Security Standards",
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

        const unique = Array.from(new Map(generated.map((g) => [g.query, g])).values()).slice(0, 6);
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

  const handleNewChat = () => {
    setActiveSessionId(null);
    setMessages([]);
    setInputQuestion("");
    setError("");
    textareaRef.current?.focus();
  };

  const handleSelectSession = (sessionId: string) => {
    if (activeSessionId === sessionId) return;
    setActiveSessionId(sessionId);
    setSearchTerm("");
    loadSessionHistory(sessionId);
  };

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
    setShowPromptsTray(false);

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

  const toggleCitationAccordion = (key: string) => {
    setExpandedCitations((prev) => ({
      ...prev,
      [key]: !prev[key],
    }));
  };

  // Scroll to and expand citation when clicking inline [Source N] badge
  const scrollToCitation = (messageId: string, citationIdx: number) => {
    const key = `${messageId}-${citationIdx}`;
    setExpandedCitations((prev) => ({ ...prev, [key]: true }));
    setHighlightedCitation(key);
    setTimeout(() => {
      citationRefs.current[key]?.scrollIntoView({ behavior: "smooth", block: "center" });
    }, 50);
    setTimeout(() => setHighlightedCitation(null), 2500);
  };

  // Markdown-friendly formatter with clickable [Source N] badges
  const renderFormattedText = (messageId: string, text: string, citations?: Citation[]) => {
    // Regex for [Source N], [Source: N], [N]
    const parts = text.split(/(\[(?:Source\s*)?(?:\d+)\])/gi);

    return parts.map((part, i) => {
      const match = part.match(/\[(?:Source\s*)?(\d+)\]/i);
      if (match) {
        const num = parseInt(match[1], 10);
        const citIdx = num - 1;
        const exists = citations && citations[citIdx];

        return (
          <span
            key={i}
            className="inline-citation-badge"
            onClick={() => exists && scrollToCitation(messageId, citIdx)}
            title={exists ? `View Citation #${num}: ${citations[citIdx].document_name}` : `Citation [${num}]`}
          >
            {num}
          </span>
        );
      }
      return <span key={i}>{part}</span>;
    });
  };

  const activeSessionObj = sessions.find((s) => s.session_id === activeSessionId);

  return (
    <div className="chat-page">
      {/* Top Header */}
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
            <Search size={14} style={{ color: "var(--text-muted)" }} />
            <input
              type="text"
              placeholder="Search in chat..."
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

          <div className="chat-status-badge">
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
              <div className="empty-state" style={{ padding: "24px 12px" }}>
                <MessageSquare size={24} />
                <strong style={{ fontSize: "13px" }}>No sessions yet</strong>
                <p style={{ fontSize: "12px" }}>Click "+ New Search Session" to begin inquiry.</p>
              </div>
            ) : (
              sessions.map((sess) => {
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
              })
            )}
          </div>
        </aside>

        {/* Right Panel: Main Chatbot Feed & Glowing Input */}
        <div className="chatbot-spacious-container">
          {/* Chat Feed Scroll Area */}
          <div className="chat-feed-scroll">
            {messages.length === 0 ? (
              <div className="chatbot-welcome-state">
                <div className="welcome-avatar-glow">
                  <Bot size={34} />
                </div>
                <h2>{activeSessionObj ? activeSessionObj.title : "What would you like to know today?"}</h2>
                <p>
                  Ask any question grounded directly across your company handbooks, compliance policies, and uploaded files.
                </p>

                {/* Starter Question Chips */}
                {dynamicQueries.length > 0 && (
                  <div className="welcome-starters-grid">
                    {dynamicQueries.map((dq) => (
                      <div
                        key={dq.id}
                        className="starter-chip-card"
                        onClick={() => handleSend(dq.query)}
                      >
                        <Compass size={18} style={{ color: "var(--accent)", flexShrink: 0 }} />
                        <div>
                          <strong>{dq.title}</strong>
                          <span>{dq.query}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
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
                      className={`chat-message-row ${msg.sender === "user" ? "user-row" : "assistant-row"}`}
                    >
                      <div className={`message-avatar ${msg.sender}`}>
                        {msg.sender === "user" ? <User size={16} /> : <Bot size={18} />}
                      </div>

                      <div className="message-content-wrapper">
                        <div className="message-header-meta">
                          <span className="sender-name">
                            {msg.sender === "user" ? "You" : "Atlas AI Assistant"}
                          </span>
                          <span className="timestamp-tag">{msg.timestamp}</span>
                        </div>

                        <div className="message-bubble" style={{ border: isActiveTarget ? "2px solid var(--accent)" : undefined }}>
                          {/* Message Text with Formatted Inline Citations */}
                          <div className="bubble-text">
                            {msg.sender === "assistant"
                              ? renderFormattedText(msg.id, msg.text, msg.citations)
                              : msg.text}
                          </div>

                          {/* Sources Accordion Row (Expandable Citation Cards) */}
                          {msg.sender === "assistant" && msg.citations && msg.citations.length > 0 && (
                            <div className="sources-evidence-section">
                              <div className="sources-evidence-header">
                                <BookOpen size={13} style={{ color: "var(--accent)" }} />
                                <span>VERIFIED CITATIONS ({msg.citations.length})</span>
                              </div>

                              <div className="citations-cards-stack">
                                {msg.citations.map((citation, citIdx) => {
                                  const cardKey = `${msg.id}-${citIdx}`;
                                  const isExpanded = Boolean(expandedCitations[cardKey]);
                                  const matchPct = Math.round(citation.score * 100);
                                  const isHighlighted = highlightedCitation === cardKey;

                                  return (
                                    <div
                                      key={cardKey}
                                      ref={(el) => {
                                        citationRefs.current[cardKey] = el;
                                      }}
                                      className={`citation-card-item ${isHighlighted ? "highlighted" : ""}`}
                                    >
                                      <div
                                        className="citation-card-head"
                                        onClick={() => toggleCitationAccordion(cardKey)}
                                      >
                                        <div className="citation-card-left">
                                          <div className="citation-num-pill">{citIdx + 1}</div>
                                          <div>
                                            <strong className="citation-doc-title">{citation.document_name}</strong>
                                            <span style={{ fontSize: "11px", color: "var(--text-muted)", marginLeft: "8px" }}>
                                              Chunk {citation.chunk_index + 1}
                                            </span>
                                          </div>
                                        </div>

                                        <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                                          <span className="citation-score-badge">{matchPct}% match</span>
                                          {isExpanded ? <ChevronUp size={15} /> : <ChevronDown size={15} />}
                                        </div>
                                      </div>

                                      {isExpanded && (
                                        <div className="citation-card-body">
                                          <p style={{ margin: 0 }}>{citation.text}</p>
                                        </div>
                                      )}
                                    </div>
                                  );
                                })}
                              </div>
                            </div>
                          )}

                          {/* Assistant Actions (Copy & Helpful Feedback) */}
                          {msg.sender === "assistant" && (
                            <div className="bubble-actions">
                              {msg.query_log_id ? (
                                <div className="feedback">
                                  <span>Helpful?</span>
                                  <button
                                    className={`feedback-btn ${msg.feedbackGiven === true ? "selected" : ""}`}
                                    onClick={() => handleFeedback(msg.id, msg.query_log_id!, true)}
                                    aria-label="Helpful"
                                    title="Mark response as helpful"
                                  >
                                    <ThumbsUp size={13} />
                                  </button>
                                  <button
                                    className={`feedback-btn ${msg.feedbackGiven === false ? "selected" : ""}`}
                                    onClick={() => handleFeedback(msg.id, msg.query_log_id!, false)}
                                    aria-label="Not helpful"
                                    title="Mark response as not helpful"
                                  >
                                    <ThumbsDown size={13} />
                                  </button>
                                </div>
                              ) : (
                                <div />
                              )}

                              <button
                                className="btn-copy-bubble"
                                onClick={() => copyText(msg.id, msg.text)}
                                title="Copy answer to clipboard"
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
                        <span>Atlas is retrieving vector chunks & synthesizing answer…</span>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}

            <div ref={chatEndRef} />
          </div>

          {/* Alerts / Error Notices */}
          {error && <div className="alert-banner error margin-bottom" style={{ margin: "0 36px 12px" }}>{error}</div>}

          {uploadNotice && (
            <div
              className="alert-banner success"
              style={{ margin: "0 36px 12px", display: "flex", alignItems: "center", justifyContent: "space-between" }}
            >
              <span>{uploadNotice}</span>
              <button type="button" onClick={() => setUploadNotice("")}>
                <X size={14} />
              </button>
            </div>
          )}

          {/* =========================================================
              REFERENCE 3: GLOWING GLASS CHAT INPUT
              ========================================================= */}
          <div className="chatbot-input-bar-wrap">
            {/* Active Temporary Documents Chip */}
            {tempDocs.length > 0 && (
              <div className="temp-docs-chat-badge-bar">
                <Sparkles size={13} style={{ color: "var(--accent)" }} />
                <span style={{ fontSize: "12px", color: "var(--text-muted)" }}>Attached file (private to this session):</span>
                {tempDocs.map((doc) => (
                  <div key={doc.document_id} className="temp-doc-active-chip">
                    <FileText size={12} />
                    <span>{doc.name}</span>
                    <button
                      type="button"
                      onClick={() => handleDeleteTempDoc(doc.document_id)}
                      className="chip-remove-btn"
                      title="Remove temporary document"
                    >
                      <X size={12} />
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* Prompts Tray Popover */}
            {showPromptsTray && dynamicQueries.length > 0 && (
              <div className="prompts-popover-tray">
                <div className="prompts-tray-header">Suggested Prompts</div>
                <div className="prompts-tray-items">
                  {dynamicQueries.map((dq) => (
                    <button
                      key={dq.id}
                      type="button"
                      className="prompt-tray-item"
                      onClick={() => handleSend(dq.query)}
                    >
                      {dq.query}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {/* Glowing Glass Input Container (Reference 3) */}
            <div className="glowing-glass-input-wrapper">
              <div className="glowing-glass-input-inner">
                {/* Auto-growing Textarea */}
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
                      ? `Ask Atlas AI about "${tempDocs[0].name}" or enterprise files...`
                      : "Ask Atlas AI anything about your enterprise documents... (Enter to send, Shift+Enter for newline)"
                  }
                  className="chatbot-sticky-textarea"
                />

                {/* Bottom Action Toolbar inside the glowing box (Reference 3) */}
                <div className="glowing-input-toolbar">
                  <div className="toolbar-left-group">
                    {/* "Prompts" Pill (Reference 3) */}
                    <button
                      type="button"
                      className="prompts-pill-btn"
                      onClick={() => setShowPromptsTray(!showPromptsTray)}
                      title="Toggle suggested prompts"
                    >
                      <Sparkles size={14} />
                      <span>Prompts</span>
                    </button>

                    {/* Hidden file input */}
                    <input
                      type="file"
                      ref={fileInputRef}
                      style={{ display: "none" }}
                      accept=".pdf,.docx,.txt,.md,.csv,.json,.log,.pptx"
                      onChange={handleFileUpload}
                    />

                    {/* Paperclip Attach Icon (Reference 3) */}
                    <button
                      type="button"
                      className="chatbot-attach-btn"
                      onClick={() => fileInputRef.current?.click()}
                      disabled={uploadingDoc || loading}
                      title="Attach temporary file to query with Qdrant vectors"
                    >
                      {uploadingDoc ? <Loader2 size={16} className="animate-spin" /> : <Paperclip size={16} />}
                    </button>

                    {/* Grounded Status Pill */}
                    <div className="mic-status-pill">
                      <Zap size={11} style={{ color: "var(--accent)" }} />
                      <span>Grounded RAG</span>
                    </div>
                  </div>

                  {/* Round Send Button (Reference 3) */}
                  <button
                    type="button"
                    className="round-send-btn"
                    onClick={() => handleSend()}
                    disabled={loading || !inputQuestion.trim()}
                    title="Send message (Enter)"
                  >
                    {loading ? <Loader2 size={16} className="animate-spin" /> : <ArrowUp size={18} />}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
