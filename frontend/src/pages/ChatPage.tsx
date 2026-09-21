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
} from "lucide-react";
import { request } from "../api";

export type Citation = { document_id: number; document_name: string; chunk_index: number; text: string; score: number };

export interface ChatMessage {
  id: string;
  sender: "user" | "assistant";
  text: string;
  citations?: Citation[];
  query_log_id?: number;
  timestamp: string;
  feedbackGiven?: boolean | null;
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
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputQuestion, setInputQuestion] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [dynamicQueries, setDynamicQueries] = useState<DynamicQuery[]>([]);
  const [searchTerm, setSearchTerm] = useState("");
  const [activeMatchIndex, setActiveMatchIndex] = useState(0);

  const chatEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const msgRefs = useRef<{ [id: string]: HTMLDivElement | null }>({});

  // Auto-scroll chat stream to bottom when new messages arrive (unless user is searching)
  useEffect(() => {
    if (!searchTerm.trim()) {
      chatEndRef.current?.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, loading, searchTerm]);

  // Load chat history from DB on component mount (tab switch / re-login)
  useEffect(() => {
    async function loadChatHistory() {
      try {
        const history = await request<ChatMessage[]>("/api/chat/history");
        if (history && history.length > 0) {
          setMessages(history);
        }
      } catch {
        // Silently ignore if history is empty
      }
    }
    loadChatHistory();
  }, []);

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
      const result = await request<{ query_log_id: number; answer: string; citations: Citation[] }>("/api/chat/ask", {
        method: "POST",
        body: JSON.stringify({ question: queryText, top_k: 5 }),
      });

      const assistantMessage: ChatMessage = {
        id: `ast-${Date.now()}`,
        sender: "assistant",
        text: result.answer,
        citations: result.citations,
        query_log_id: result.query_log_id,
        timestamp: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
      };

      setMessages((prev) => [...prev, assistantMessage]);
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

  return (
    <div className="chat-page real-chatbot-layout">
      {/* Real Chatbot Page Header */}
      <header className="page-heading chatbot-top-header">
        <div>
          <div className="eyebrow chat-eyebrow">
            <Sparkles size={14} /> INTELLIGENT AI KNOWLEDGE CHATBOT
          </div>
          <h1 className="chat-main-title">
            Atlas <span className="highlight-text">Conversational AI</span>
          </h1>
        </div>

        <div className="header-actions">
          {/* Header Search Box with Match Navigation */}
          <div className="header-search-box">
            <Search size={15} className="search-icon" />
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

          <div className="online-indicator-badge chat-status-badge">
            <Zap size={13} />
            <span>RAG Engine Connected</span>
          </div>
        </div>
      </header>

      {/* Main Spacious Chat Container */}
      <div className="chatbot-spacious-container">
        {/* Chat Feed Area */}
        <div className="chat-feed-scroll">
          {messages.length === 0 ? (
            <div className="chatbot-welcome-state">
              <div className="welcome-avatar-glow">
                <Bot size={36} />
              </div>
              <h2>How can I help you today?</h2>
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

                        {/* Assistant Actions (Copy & Feedback) without whole source file content */}
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

        {/* Sticky Input Bar at Bottom */}
        <div className="chatbot-input-bar-wrap">
          <form
            onSubmit={(e) => {
              e.preventDefault();
              handleSend();
            }}
            className="chatbot-input-form"
          >
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
              placeholder="Ask Atlas AI anything about your enterprise documents..."
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

          {/* Referenced Source Files Small Section (Just File Names Below Input Field) */}
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

          {/* Dynamic Recommendations Section placed BELOW question input field */}
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
  );
}



