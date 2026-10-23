import { useState, useRef, useEffect } from "react";
import {
  ShieldCheck,
  Search,
  ArrowRight,
  Sparkles,
  Lock,
  FileText,
  Users,
  MessageCircle,
  FolderKanban,
  CheckCircle2,
  Layers,
  ChevronRight,
  Eye,
  EyeOff,
  KeyRound,
  AlertCircle,
  Sun,
  Moon,
  Zap,
  Activity,
  Check,
  Star,
  ExternalLink,
  Bot,
  Database,
  ArrowUpRight,
} from "lucide-react";
import { forgotPassword, login } from "../api";

interface HomePageProps {
  onSuccess: () => void;
  theme: "light" | "dark";
  onToggleTheme: () => void;
  initialTab?: "home" | "features" | "architecture" | "signin";
}

export default function HomePage({
  onSuccess,
  theme,
  onToggleTheme,
  initialTab = "home",
}: HomePageProps) {
  const [activeTab, setActiveTab] = useState<"home" | "features" | "architecture" | "signin">(initialTab);

  // Authentication State
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [authLoading, setAuthLoading] = useState(false);
  const [authError, setAuthError] = useState("");

  // Hero Quick Email / Question
  const [heroInput, setHeroInput] = useState("");

  // Forgot Password Modal State
  const [showForgotModal, setShowForgotModal] = useState(false);
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotLoading, setForgotLoading] = useState(false);
  const [forgotMessage, setForgotMessage] = useState("");
  const [forgotError, setForgotError] = useState("");

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setAuthError("");
    setAuthLoading(true);
    try {
      await login(email, password);
      onSuccess();
    } catch (err) {
      setAuthError((err as Error).message || "Invalid credentials");
    } finally {
      setAuthLoading(false);
    }
  };

  const handleForgotPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setForgotError("");
    setForgotMessage("");
    setForgotLoading(true);
    try {
      const res = await forgotPassword(forgotEmail);
      setForgotMessage(res.message || "Password reset instructions recorded.");
    } catch (err) {
      setForgotError((err as Error).message || "Email address not found in database.");
    } finally {
      setForgotLoading(false);
    }
  };

  const fillDemo = (demoEmail: string, demoPass: string) => {
    setEmail(demoEmail);
    setPassword(demoPass);
    setActiveTab("signin");
  };

  const handleHeroSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (heroInput.includes("@")) {
      setEmail(heroInput);
      setActiveTab("signin");
    } else if (heroInput.trim()) {
      sessionStorage.setItem("atlas_quick_ask", heroInput.trim());
      setActiveTab("signin");
    } else {
      setActiveTab("signin");
    }
  };

  return (
    <div className={`homepage-wrapper ${theme}-theme`}>
      {/* =========================================================================
          1. TOP FLOATING GLASS NAVBAR WITH TABS (As requested by user)
          ========================================================================= */}
      <header className="hp-navbar">
        <div className="hp-nav-container">
          {/* Brand Logo */}
          <div className="hp-brand" onClick={() => setActiveTab("home")} style={{ cursor: "pointer" }}>
            <div className="hp-logo-mark">
              <ShieldCheck size={20} />
            </div>
            <div className="hp-brand-text">
              <strong>Atlas</strong>
              <span>Enterprise RAG</span>
            </div>
          </div>

          {/* Navigation Tabs */}
          <nav className="hp-tabs-nav">
            <button
              type="button"
              className={`hp-tab-btn ${activeTab === "home" ? "active" : ""}`}
              onClick={() => setActiveTab("home")}
            >
              Home
            </button>
            <button
              type="button"
              className={`hp-tab-btn ${activeTab === "features" ? "active" : ""}`}
              onClick={() => setActiveTab("features")}
            >
              Features
            </button>
            <button
              type="button"
              className={`hp-tab-btn ${activeTab === "architecture" ? "active" : ""}`}
              onClick={() => setActiveTab("architecture")}
            >
              Architecture
            </button>
            <button
              type="button"
              className={`hp-tab-btn hp-tab-auth ${activeTab === "signin" ? "active" : ""}`}
              onClick={() => setActiveTab("signin")}
            >
              <Lock size={13} />
              <span>Sign In</span>
            </button>
          </nav>

          {/* Right Header Actions */}
          <div className="hp-nav-right">
            <button
              type="button"
              className="theme-toggle-btn"
              onClick={onToggleTheme}
              title={`Switch to ${theme === "light" ? "Dark" : "Light"} Theme`}
            >
              {theme === "light" ? <Moon size={14} /> : <Sun size={14} />}
              <span>{theme === "light" ? "Dark" : "Light"}</span>
            </button>

            <button
              type="button"
              className="hp-cta-nav-btn"
              onClick={() => setActiveTab("signin")}
            >
              <span>Get Started</span>
              <ArrowRight size={14} />
            </button>
          </div>
        </div>
      </header>

      {/* =========================================================================
          TAB 1: HOME (Hero Section with Video + Scrollable Feature Stories)
          ========================================================================= */}
      {activeTab === "home" && (
        <main className="hp-main-content">
          {/* Reference Video Hero Section */}
          <section className="hp-hero-section">
            {/* Background Video (Vertically flipped scaleY(-1) as requested in reference prompt) */}
            <div className="hp-video-wrapper">
              <video
                autoPlay
                loop
                muted
                playsInline
                className="hp-bg-video"
                src="https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260302_085640_276ea93b-d7da-4418-a09b-2aa5b490e838.mp4"
              />
              {/* White Gradient Overlay blending seamlessly into page background */}
              <div className="hp-video-gradient-overlay" />
            </div>

            {/* Editorial Centered Content Container */}
            <div className="hp-hero-content-container">
              {/* Live Badge */}
              <div className="hp-announcement-pill">
                <span className="pulse-dot green" />
                <span>Next-Gen RAG 2.4 Is Live</span>
                <ChevronRight size={14} />
              </div>

              {/* Main Headline (Geist/Inter 80px + Instrument Serif Italic 100px) */}
              <h1 className="hp-main-heading">
                Simple <em className="hp-serif-word">management</em> for your remote team
              </h1>

              {/* Description */}
              <p className="hp-hero-description">
                Easily handle all your enterprise knowledge tasks, from document search and Google Drive sync
                to WhatsApp assistance and collaborative team workspaces.
              </p>

              {/* Email / Action Input Navbar (Rounded 40px with Tactile CTA Button) */}
              <form onSubmit={handleHeroSubmit} className="hp-email-navbar-container">
                <input
                  type="text"
                  placeholder="Enter your work email address"
                  value={heroInput}
                  onChange={(e) => setHeroInput(e.target.value)}
                  className="hp-email-input"
                />
                <button type="submit" className="hp-tactile-cta-button">
                  <span>Create Free Account</span>
                  <ArrowRight size={16} />
                </button>
              </form>

              {/* Social Proof Badge */}
              <div className="hp-social-proof-bar">
                <div className="hp-stars-row">
                  {[...Array(5)].map((_, i) => (
                    <Star key={i} size={14} fill="#f59e0b" color="#f59e0b" />
                  ))}
                </div>
                <span className="hp-review-text">
                  <strong>1,020+ Verified Inquiries</strong> & enterprise security evaluations
                </span>
              </div>
            </div>
          </section>

          {/* =========================================================================
              SCROLLABLE FEATURE EXPLANATION SECTION
              ========================================================================= */}
          <section className="hp-features-overview-section">
            <div className="hp-section-header">
              <div className="eyebrow">
                <Sparkles size={14} /> COMPLETE KNOWLEDGE RETRIEVAL STACK
              </div>
              <h2>Everything your organization needs for trusted AI answers</h2>
              <p>
                Eliminate hallucinations. Atlas connects directly to your corporate documents, Google Drive,
                and communication channels with zero-leak role boundaries.
              </p>
            </div>

            {/* Grid of 6 Core Website Features */}
            <div className="hp-features-grid">
              {/* Feature 1: Grounded RAG */}
              <div className="hp-feature-card">
                <div className="hp-feature-icon icon-blue">
                  <Bot size={24} />
                </div>
                <h3>Grounded Semantic Search & Citations</h3>
                <p>
                  Every answer produced by Atlas AI includes clickable [Source N] badges linked directly to
                  underlying document chunks, page numbers, and semantic similarity scores.
                </p>
                <ul className="hp-feature-bullets">
                  <li><Check size={14} /> Qdrant dense vector search with cosine reranking</li>
                  <li><Check size={14} /> Expandable citation accordions with exact snippets</li>
                  <li><Check size={14} /> Thumbs up/down feedback logging for continuous improvement</li>
                </ul>
              </div>

              {/* Feature 2: 5-Tier Role Hierarchy */}
              <div className="hp-feature-card">
                <div className="hp-feature-icon icon-indigo">
                  <ShieldCheck size={24} />
                </div>
                <h3>5-Tier Hierarchical Governance</h3>
                <p>
                  Enterprise-grade RBAC controls enforce that users only retrieve information authorized for
                  their specific company rank level.
                </p>
                <ul className="hp-feature-bullets">
                  <li><Check size={14} /> Rank 1: Executive Admin (Full system control & user admin)</li>
                  <li><Check size={14} /> Rank 2: HR & Operations (Handbooks, benefits, PTO policies)</li>
                  <li><Check size={14} /> Rank 3-5: Managers, Team Leads & Staff (Scoped project access)</li>
                </ul>
              </div>

              {/* Feature 3: Google Drive Sync */}
              <div className="hp-feature-card">
                <div className="hp-feature-icon icon-emerald">
                  <Database size={24} />
                </div>
                <h3>Multi-Tenant Drive Integration</h3>
                <p>
                  Connect any corporate Google Drive folder or document URL. Atlas automatically maps
                  folder trees, processes PDFs, Docs, spreadsheets, and ingests them into vector stores.
                </p>
                <ul className="hp-feature-bullets">
                  <li><Check size={14} /> Single clean input box for adding multiple Drive folders</li>
                  <li><Check size={14} /> Per-document and per-folder ACL override controls</li>
                  <li><Check size={14} /> Real-time status indicators (indexing, ready, processed)</li>
                </ul>
              </div>

              {/* Feature 4: WhatsApp Bot Assistant */}
              <div className="hp-feature-card">
                <div className="hp-feature-icon icon-green">
                  <MessageCircle size={24} />
                </div>
                <h3>WhatsApp Multi-Device Assistant</h3>
                <p>
                  Employees can link their mobile phone via a simple 6-digit verification code to chat with
                  the enterprise knowledge base directly on WhatsApp.
                </p>
                <ul className="hp-feature-bullets">
                  <li><Check size={14} /> Secure identity binding with OAuth2 session verification</li>
                  <li><Check size={14} /> Bot commands: /help, /new (reset session), /unlink</li>
                  <li><Check size={14} /> Strict rank restrictions enforced on mobile identical to web</li>
                </ul>
              </div>

              {/* Feature 5: Team Workspaces & Jira */}
              <div className="hp-feature-card">
                <div className="hp-feature-icon icon-purple">
                  <FolderKanban size={24} />
                </div>
                <h3>Team Workspaces & Jira Automation</h3>
                <p>
                  Collaborate in shared project workspaces with a toggle between "Ask AI" and "Message Team".
                  AI detects action items and generates 1-click Jira ticket suggestions.
                </p>
                <ul className="hp-feature-bullets">
                  <li><Check size={14} /> 4-second live polling for collaborative discussions</li>
                  <li><Check size={14} /> Automated Jira issue extraction with assignee & due date hints</li>
                  <li><Check size={14} /> Temporary file uploads private to the current team workspace</li>
                </ul>
              </div>

              {/* Feature 6: Audit Logs & Telemetry */}
              <div className="hp-feature-card">
                <div className="hp-feature-icon icon-rose">
                  <Activity size={24} />
                </div>
                <h3>Hierarchical Audit Trail & Telemetry</h3>
                <p>
                  Audit logs follow strict authority scoping: users can review logs of succeeding (subordinate)
                  rank roles while upper executive records remain strictly protected.
                </p>
                <ul className="hp-feature-bullets">
                  <li><Check size={14} /> Filter by severity: INFO, WARNING, ERROR, CRITICAL</li>
                  <li><Check size={14} /> Multi-channel breakdown: Web vs. WhatsApp requests</li>
                  <li><Check size={14} /> Live query frequency breakdown and popular questions trend</li>
                </ul>
              </div>
            </div>
          </section>

          {/* =========================================================================
              INTERACTIVE DEMO / QUICK ACCESS BANNER
              ========================================================================= */}
          <section className="hp-cta-banner-section">
            <div className="hp-cta-glass-card">
              <div className="hp-cta-text">
                <h2>Experience Grounded Enterprise Intelligence</h2>
                <p>
                  Explore with pre-configured demo roles or authenticate with your work email to start querying.
                </p>
              </div>

              <div className="hp-cta-buttons-group">
                <button
                  type="button"
                  className="hp-tactile-cta-button"
                  onClick={() => fillDemo("admin@example.com", "AdminPass123!")}
                >
                  <span>Admin Demo (Rank 1)</span>
                  <ArrowRight size={16} />
                </button>
                <button
                  type="button"
                  className="hp-glass-pill-btn"
                  onClick={() => fillDemo("manager@example.com", "ManagerPass123!")}
                >
                  <span>Manager Demo (Rank 3)</span>
                </button>
                <button
                  type="button"
                  className="hp-glass-pill-btn"
                  onClick={() => fillDemo("employee@example.com", "EmployeePass123!")}
                >
                  <span>Staff Demo (Rank 4)</span>
                </button>
              </div>
            </div>
          </section>
        </main>
      )}

      {/* =========================================================================
          TAB 2: FEATURES DEEP DIVE (Dedicated Page Tab)
          ========================================================================= */}
      {activeTab === "features" && (
        <main className="hp-page-tab-content">
          <div className="hp-subpage-header">
            <div className="eyebrow">
              <Sparkles size={14} /> ENTERPRISE PLATFORM CAPABILITIES
            </div>
            <h1>Engineered for Accuracy, Security & Speed</h1>
            <p>
              Atlas combines vector semantic retrieval with strict organizational role hierarchy to ensure every answer
              is verifiable and confidential.
            </p>
          </div>

          <div className="hp-deep-features-list">
            <div className="hp-deep-feature-row">
              <div className="hp-deep-text">
                <span className="badge badge-accent">CORE ENGINE</span>
                <h2>Grounded Answers with Verified Citations</h2>
                <p>
                  Unlike generic chatbots that hallucinate, Atlas retrieves exact text passages from your indexed
                  enterprise handbooks and policy documents before generating a response.
                </p>
                <div className="hp-pill-list">
                  <span className="chip"><Check size={13} /> Clickable [Source N] Markers</span>
                  <span className="chip"><Check size={13} /> Page & Chunk Breakdown</span>
                  <span className="chip"><Check size={13} /> Full Passage Snippet Review</span>
                </div>
              </div>
              <div className="hp-deep-preview card-glass">
                <div className="preview-chat-bubble assistant">
                  <div className="bubble-header">
                    <Bot size={16} />
                    <strong>Atlas AI Assistant</strong>
                  </div>
                  <p>
                    Full-time employees accrue 22 business days of PTO annually. Up to 5 unused PTO days can be
                    carried over into the next calendar year{" "}
                    <span className="inline-citation-badge">1</span>.
                  </p>
                  <div className="preview-citation-pill">
                    <FileText size={12} />
                    <span>Source 1: HR_Handbook_2026.pdf (Chunk 4 · 94% match)</span>
                  </div>
                </div>
              </div>
            </div>

            <div className="hp-deep-feature-row reverse">
              <div className="hp-deep-text">
                <span className="badge badge-success">DATA INTEGRATION</span>
                <h2>Instant Google Drive & Multi-Tenant Sync</h2>
                <p>
                  Paste any Google Drive link to index entire department folders. Drive links automatically
                  crawl child directories, extract PDFs, DOCX, text files, and synchronize permissions.
                </p>
                <div className="hp-pill-list">
                  <span className="chip"><Check size={13} /> Single URL Connect</span>
                  <span className="chip"><Check size={13} /> Incremental Ingestion</span>
                  <span className="chip"><Check size={13} /> Drive Folder Trees</span>
                </div>
              </div>
              <div className="hp-deep-preview card-glass">
                <div className="preview-drive-box">
                  <div className="preview-drive-head">
                    <Database size={16} style={{ color: "#2563eb" }} />
                    <strong>Connected Drive Source: Engineering Handbooks</strong>
                  </div>
                  <div className="preview-drive-stat">
                    <span>14 Files Ingested</span>
                    <span className="badge badge-success">100% Vectorized</span>
                  </div>
                </div>
              </div>
            </div>

            <div className="hp-deep-feature-row">
              <div className="hp-deep-text">
                <span className="badge badge-warning">MOBILE & CHAT</span>
                <h2>WhatsApp Enterprise Assistant</h2>
                <p>
                  Bring enterprise knowledge to your employees' pockets. Generate a 6-digit linking code to verify
                  any WhatsApp number. All queries adhere to the user's role rank.
                </p>
                <div className="hp-pill-list">
                  <span className="chip"><Check size={13} /> Fast 6-Digit Code Auth</span>
                  <span className="chip"><Check size={13} /> Mobile Citations</span>
                  <span className="chip"><Check size={13} /> Remote Workforce Ready</span>
                </div>
              </div>
              <div className="hp-deep-preview card-glass">
                <div className="preview-wa-box">
                  <div className="wa-bubble incoming">
                    <span className="wa-sender">Atlas WhatsApp Bot</span>
                    <p>What would you like to know from company policies?</p>
                  </div>
                  <div className="wa-bubble outgoing">
                    <p>What are the remote work security guidelines?</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </main>
      )}

      {/* =========================================================================
          TAB 3: ARCHITECTURE & SECURITY (Dedicated Page Tab)
          ========================================================================= */}
      {activeTab === "architecture" && (
        <main className="hp-page-tab-content">
          <div className="hp-subpage-header">
            <div className="eyebrow">
              <Layers size={14} /> SYSTEM ARCHITECTURE & SECURITY
            </div>
            <h1>How Atlas Grounded Retrieval Works</h1>
            <p>
              An end-to-end overview of our ingestion, indexing, hierarchical ACL filters, and RAG synthesis pipeline.
            </p>
          </div>

          <div className="hp-pipeline-container card-glass">
            <div className="pipeline-steps-grid">
              <div className="pipeline-step-item">
                <div className="pipeline-number">01</div>
                <h4>Document Ingestion</h4>
                <p>Extracts text from PDF, DOCX, TXT, and Drive sources, preserving headings and metadata.</p>
              </div>

              <div className="pipeline-arrow">→</div>

              <div className="pipeline-step-item">
                <div className="pipeline-number">02</div>
                <h4>Chunking & Vectors</h4>
                <p>Splits text into overlapping semantic passages and calculates 384/768-dim embeddings.</p>
              </div>

              <div className="pipeline-arrow">→</div>

              <div className="pipeline-step-item">
                <div className="pipeline-number">03</div>
                <h4>Qdrant Vector DB</h4>
                <p>Stores vectors with tenant_id, role access list, and denied user IDs in Qdrant collections.</p>
              </div>

              <div className="pipeline-arrow">→</div>

              <div className="pipeline-step-item">
                <div className="pipeline-number">04</div>
                <h4>Hierarchical Filter</h4>
                <p>Filters candidates strictly by user's rank authority level before passing to generator.</p>
              </div>

              <div className="pipeline-arrow">→</div>

              <div className="pipeline-step-item">
                <div className="pipeline-number">05</div>
                <h4>Grounded Synthesis</h4>
                <p>LLM answers question citing verified chunk numbers with zero hallucinated content.</p>
              </div>
            </div>
          </div>

          {/* Role Hierarchy Visualizer */}
          <div className="hp-hierarchy-card card-glass" style={{ marginTop: "32px", padding: "28px" }}>
            <div className="dash-panel-head">
              <h3>
                <ShieldCheck size={20} style={{ color: "var(--accent)" }} />
                5-Tier Hierarchical Access Control Matrix
              </h3>
            </div>
            <p style={{ color: "var(--text-muted)", fontSize: "14px", margin: "0 0 20px 0" }}>
              Atlas prevents information leakage by ensuring that lower ranks cannot query documents restricted to higher authority tiers.
            </p>

            <div className="hierarchy-tiers-list">
              <div className="tier-row tier-1">
                <span className="tier-badge">Rank 1 · Executive Admin</span>
                <span className="tier-desc">Full system access: all documents, upper-role management, audit logs, Drive connections.</span>
              </div>
              <div className="tier-row tier-2">
                <span className="tier-badge">Rank 2 · HR Manager</span>
                <span className="tier-desc">Company policies, employee handbooks, PTO regulations, and HR department records.</span>
              </div>
              <div className="tier-row tier-3">
                <span className="tier-badge">Rank 3 · Operations Manager</span>
                <span className="tier-desc">Cross-department operations, logistics guidelines, and team project documentation.</span>
              </div>
              <div className="tier-row tier-4">
                <span className="tier-badge">Rank 4 · Team Lead</span>
                <span className="tier-desc">Collaborative team workspaces, Jira integration, and team-specific temporary files.</span>
              </div>
              <div className="tier-row tier-5">
                <span className="tier-badge">Rank 5 · General Employee</span>
                <span className="tier-desc">Approved general staff documentation, interactive AI search sessions, and personal profile.</span>
              </div>
            </div>
          </div>
        </main>
      )}

      {/* =========================================================================
          TAB 4: SIGN IN / AUTHENTICATION (Dedicated Tab on Homepage as requested)
          ========================================================================= */}
      {activeTab === "signin" && (
        <main className="hp-signin-tab-content">
          <div className="hp-signin-ambient-blob hp-blob-1" />
          <div className="hp-signin-ambient-blob hp-blob-2" />
          <div className="login-split-wrapper" style={{ margin: "40px auto", maxWidth: "980px" }}>
            {/* Left Brand Panel */}
            <div className="login-brand-panel">
              <div className="login-brand-top">
                <div className="brand-mark">
                  <ShieldCheck size={24} />
                </div>
                <div className="brand-copy">
                  <strong>Atlas Enterprise</strong>
                  <span>Grounded Knowledge Portal</span>
                </div>
              </div>

              <div className="login-hero-copy">
                <div className="eyebrow" style={{ marginBottom: "10px" }}>
                  <Sparkles size={14} /> SECURE AUTHENTICATION
                </div>
                <h2 className="login-editorial-headline" style={{ fontSize: "32px" }}>
                  Sign in to your <br />
                  <em className="hp-serif-word">knowledge</em> workspace
                </h2>
                <p className="login-sub-line">
                  Access your organization's vector search engine, verified citations, and team workspaces.
                </p>
              </div>

              {/* Demo Shortcuts */}
              <div className="hp-auth-demo-box">
                <span style={{ fontSize: "12px", fontWeight: "700", color: "var(--text-muted)", display: "block", marginBottom: "8px" }}>
                  INSTANT DEMO PRE-SETS:
                </span>
                <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
                  <button
                    type="button"
                    className="chip-btn"
                    style={{ justifyContent: "space-between" }}
                    onClick={() => {
                      setEmail("admin@example.com");
                      setPassword("AdminPass123!");
                    }}
                  >
                    <span><strong>Admin</strong> (Executive Rank 1)</span>
                    <ArrowRight size={13} />
                  </button>
                  <button
                    type="button"
                    className="chip-btn"
                    style={{ justifyContent: "space-between" }}
                    onClick={() => {
                      setEmail("manager@example.com");
                      setPassword("ManagerPass123!");
                    }}
                  >
                    <span><strong>Manager</strong> (Department Rank 3)</span>
                    <ArrowRight size={13} />
                  </button>
                  <button
                    type="button"
                    className="chip-btn"
                    style={{ justifyContent: "space-between" }}
                    onClick={() => {
                      setEmail("employee@example.com");
                      setPassword("EmployeePass123!");
                    }}
                  >
                    <span><strong>Staff</strong> (Collaborator Rank 4)</span>
                    <ArrowRight size={13} />
                  </button>
                  <button
                    type="button"
                    className="chip-btn"
                    style={{
                      justifyContent: "space-between",
                      marginTop: "4px",
                      background: "rgba(99, 102, 241, 0.08)",
                      border: "1px solid rgba(99, 102, 241, 0.3)"
                    }}
                    onClick={() => {
                      window.location.href = "/enterprises";
                    }}
                    title="Launch Master Super-Admin Enterprise Portal"
                  >
                    <span><strong style={{ color: "var(--accent)" }}>Super-Admin Gateway</strong> (Tenant Management)</span>
                    <ArrowRight size={13} style={{ color: "var(--accent)" }} />
                  </button>
                </div>
              </div>
            </div>

            {/* Right Form Panel */}
            <div className="login-form-panel">
              <div className="form-header">
                <div className="form-header-badge">
                  <Lock size={13} />
                  <span>WORKSPACE LOGIN</span>
                </div>
                <h2>Enter Credentials</h2>
                <p>Sign in using registered corporate email.</p>
              </div>

              {authError && (
                <div className="alert-banner error">
                  <AlertCircle size={18} />
                  <span>{authError}</span>
                </div>
              )}

              <form onSubmit={handleLogin} className="login-form">
                <div className="form-field">
                  <label htmlFor="hp-email">Registered Email Address</label>
                  <input
                    id="hp-email"
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="name@company.com"
                    autoComplete="email"
                    className="input"
                  />
                </div>

                <div className="form-field">
                  <div className="field-label-row">
                    <label htmlFor="hp-password">Password</label>
                    <button
                      type="button"
                      className="link-btn"
                      onClick={() => {
                        setForgotEmail(email);
                        setForgotError("");
                        setForgotMessage("");
                        setShowForgotModal(true);
                      }}
                    >
                      Forgot password?
                    </button>
                  </div>

                  <div className="password-input-wrap">
                    <input
                      id="hp-password"
                      type={showPassword ? "text" : "password"}
                      required
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      placeholder="Enter account password"
                      autoComplete="current-password"
                      className="input"
                    />
                    <button
                      type="button"
                      className="eye-toggle-btn"
                      onClick={() => setShowPassword(!showPassword)}
                      title={showPassword ? "Hide password" : "Show password"}
                    >
                      {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                    </button>
                  </div>
                </div>

                <button type="submit" className="login-submit-btn" disabled={authLoading}>
                  {authLoading ? "Authenticating Credentials…" : "Sign In to Workspace"}
                  <ArrowRight size={18} />
                </button>

                <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: "6px", color: "var(--text-muted)", fontSize: "12px", marginTop: "12px" }}>
                  <Lock size={12} />
                  <span>Protected by OAuth2 & JWT session encryption</span>
                </div>
              </form>
            </div>
          </div>
        </main>
      )}

      {/* =========================================================================
          FOOTER
          ========================================================================= */}
      <footer className="hp-footer">
        <div className="hp-footer-container">
          <div className="hp-footer-brand">
            <div className="hp-logo-mark" style={{ width: "32px", height: "32px" }}>
              <ShieldCheck size={16} />
            </div>
            <strong>Atlas Enterprise RAG</strong>
            <span style={{ color: "var(--text-muted)", fontSize: "12px" }}>
              — Grounded Semantic Intelligence & Multi-Channel Assistance
            </span>
          </div>

          <div className="hp-footer-links">
            <button type="button" onClick={() => setActiveTab("home")}>Home</button>
            <button type="button" onClick={() => setActiveTab("features")}>Features</button>
            <button type="button" onClick={() => setActiveTab("architecture")}>Architecture</button>
            <button type="button" onClick={() => setActiveTab("signin")}>Sign In</button>
          </div>
        </div>
      </footer>

      {/* Forgot Password Modal */}
      {showForgotModal && (
        <div className="modal-overlay" onClick={() => setShowForgotModal(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <div className="modal-icon">
                <KeyRound size={22} />
              </div>
              <div>
                <h3>Reset Account Password</h3>
                <p>Verify your registered email address below.</p>
              </div>
            </div>

            <form onSubmit={handleForgotPassword} className="modal-body">
              {forgotError && (
                <div className="alert-banner error">
                  <AlertCircle size={16} />
                  <span>{forgotError}</span>
                </div>
              )}

              {forgotMessage && (
                <div className="alert-banner success">
                  <CheckCircle2 size={16} />
                  <span>{forgotMessage}</span>
                </div>
              )}

              <div className="form-field">
                <label>Registered Work Email</label>
                <input
                  type="email"
                  required
                  value={forgotEmail}
                  onChange={(e) => setForgotEmail(e.target.value)}
                  placeholder="user@example.com"
                  className="input"
                />
              </div>

              <div className="modal-actions">
                <button
                  type="button"
                  className="btn-secondary"
                  onClick={() => setShowForgotModal(false)}
                >
                  Close
                </button>
                <button type="submit" className="btn-primary" disabled={forgotLoading}>
                  {forgotLoading ? "Checking DB..." : "Submit Reset Request"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
