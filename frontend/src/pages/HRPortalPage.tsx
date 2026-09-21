import { useState } from "react";
import { BookOpen, HelpCircle, FileText, CheckCircle, ShieldCheck, Download, Search } from "lucide-react";

interface HRPortalPageProps {
  onAskQuestion: (q: string) => void;
}

export default function HRPortalPage({ onAskQuestion }: HRPortalPageProps) {
  const [selectedTopic, setSelectedTopic] = useState("conduct");
  const [filterText, setFilterText] = useState("");

  const topics = [
    { id: "conduct", title: "1. Code of Conduct & Ethics", desc: "Equal opportunity, confidentiality, professional demeanor." },
    { id: "hours", title: "2. Hours & Remote Work", desc: "Core business hours, hybrid work, VPN security." },
    { id: "leave", title: "3. Leave & Paid Time Off", desc: "22 days PTO, sick leave, caregiver policy." },
    { id: "benefits", title: "4. Benefits & Compensation", desc: "Medical insurance, performance reviews, $1,500 learning stipend." },
  ];

  const policyContent: Record<string, string> = {
    conduct: `1. CODE OF CONDUCT & WORKPLACE ETHICS

1.1 Equal Opportunity & Inclusion:
Atlas Enterprise is committed to maintaining a workplace free from discrimination and harassment. All employment decisions are based on merit, qualifications, and business needs.

1.2 Integrity & Confidentiality:
Employees must protect company proprietary information, trade secrets, and customer data. Sharing confidential data outside authorized channels is strictly prohibited.

1.3 Professional Demeanor:
Respectful communication, open collaboration, and accountability are core values expected from every team member across all communication channels and office locations.`,
    hours: `2. WORKING HOURS & REMOTE WORK POLICY

2.1 Core Working Hours:
Standard core business hours are 09:00 AM to 05:00 PM local time. Flexible timing may be arranged with manager approval.

2.2 Hybrid & Remote Work Guidelines:
- Employees are eligible for hybrid work (up to 3 days remote per week) subject to manager approval.
- Remote work environments must maintain data security standards (encrypted VPN, secure Wi-Fi).
- Core availability on company Slack/Teams is required during scheduled work hours.`,
    leave: `3. LEAVE & VACATION POLICY

3.1 Paid Time Off (PTO):
- Full-time employees accrue 22 business days of PTO annually.
- Unused PTO up to 5 days can be carried over into the next calendar year.

3.2 Sick & Medical Leave:
- 10 days of paid sick leave are provided annually.
- Doctor certification is required for medical absences exceeding 3 consecutive days.

3.3 Parental & Family Leave:
- Primary caregiver leave: 16 weeks fully paid.
- Secondary caregiver leave: 6 weeks fully paid.`,
    benefits: `4. BENEFITS, COMPENSATION & PERFORMANCE REVIEWS

4.1 Performance Appraisals:
Formal performance evaluations occur semi-annually (June and December). Promotions and salary adjustments are aligned with annual review results.

4.2 Health & Wellness:
Atlas Enterprise provides comprehensive health, dental, and vision insurance for all eligible employees and their dependents starting on Day 1 of employment.

4.3 Learning & Professional Development:
Each employee is allocated an annual stipend of $1,500 for courses, certifications, conferences, and technical books relevant to their professional role.`
  };

  const sampleQuestions = [
    "What is our annual PTO policy?",
    "What is the annual learning stipend amount?",
    "What are the remote work guidelines?",
    "How many weeks of primary caregiver leave are provided?",
  ];

  return (
    <div className="hr-portal-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <BookOpen size={14} /> HR HANDBOOK & POLICIES
          </div>
          <h1>HR Management Portal</h1>
          <p className="subheading">
            Official employee guidelines, handbook regulations, and policy document references.
          </p>
        </div>
        <div className="policy-badge">
          <ShieldCheck size={16} /> HR-POLICY-2026-V4
        </div>
      </header>

      {/* Quick HR Policy Q&A Launcher */}
      <section className="hr-qa-banner">
        <div className="qa-text">
          <HelpCircle size={20} />
          <div>
            <strong>Have an HR Policy Question?</strong>
            <p>Click any common query below to search directly using grounded AI retrieval.</p>
          </div>
        </div>
        <div className="qa-chips">
          {sampleQuestions.map((q) => (
            <button key={q} className="qa-chip" onClick={() => onAskQuestion(q)}>
              <span>{q}</span>
            </button>
          ))}
        </div>
      </section>

      {/* Main Handbook Content Layout */}
      <div className="hr-layout">
        <aside className="hr-sidebar">
          <div className="hr-search">
            <Search size={16} />
            <input
              type="text"
              placeholder="Search handbook section..."
              value={filterText}
              onChange={(e) => setFilterText(e.target.value)}
            />
          </div>

          <nav className="hr-nav">
            {topics
              .filter((t) => t.title.toLowerCase().includes(filterText.toLowerCase()) || t.desc.toLowerCase().includes(filterText.toLowerCase()))
              .map((t) => (
                <button
                  key={t.id}
                  className={`hr-nav-item ${selectedTopic === t.id ? "active" : ""}`}
                  onClick={() => setSelectedTopic(t.id)}
                >
                  <strong>{t.title}</strong>
                  <span>{t.desc}</span>
                </button>
              ))}
          </nav>
        </aside>

        <section className="hr-reader-card">
          <div className="reader-header">
            <div className="reader-title">
              <FileText size={18} />
              <h3>{topics.find((t) => t.id === selectedTopic)?.title}</h3>
            </div>
            <button
              className="btn-secondary-sm"
              onClick={() => {
                const blob = new Blob([policyContent[selectedTopic]], { type: "text/plain" });
                const url = URL.createObjectURL(blob);
                const a = document.createElement("a");
                a.href = url;
                a.download = `HR_Policy_${selectedTopic}.txt`;
                a.click();
              }}
            >
              <Download size={14} /> Download Policy
            </button>
          </div>

          <div className="reader-body">
            <pre>{policyContent[selectedTopic]}</pre>
          </div>

          <div className="reader-footer">
            <CheckCircle size={15} />
            <span>Approved by HR Operations Department (hr@example.com)</span>
          </div>
        </section>
      </div>
    </div>
  );
}
