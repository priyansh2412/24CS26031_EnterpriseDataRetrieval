import { ArrowLeft, FileText, Quote } from "lucide-react";
import type { Citation } from "./ChatPage";

interface SourceAnswer {
  answer: string;
  citations: Citation[];
}

export default function SourcesPage({ answer, onAsk }: { answer: SourceAnswer | null; onAsk: () => void }) {
  if (!answer) {
    return (
      <div className="sources-page">
        <header className="page-heading">
          <div>
            <div className="eyebrow">
              <Quote size={14} /> ANSWER SOURCES
            </div>
            <h1>Verified Source Evidence</h1>
            <p className="subheading">Passages retrieved from vector database search appear here.</p>
          </div>
        </header>
        <section className="empty-state sources-empty">
          <Quote size={32} />
          <strong>No Answer Selected Yet</strong>
          <p>Ask Atlas AI Assistant a question first, then use inline citations to review evidence.</p>
          <button className="btn-primary" onClick={onAsk}>
            Ask Atlas Assistant
          </button>
        </section>
      </div>
    );
  }

  return (
    <div className="sources-page">
      <header className="page-heading">
        <div>
          <div className="eyebrow">
            <Quote size={14} /> ANSWER SOURCES
          </div>
          <h1>Verified Evidence ({answer.citations.length})</h1>
          <p className="subheading">
            Passages retrieved for: “{answer.answer.slice(0, 85)}{answer.answer.length > 85 ? "…" : ""}”
          </p>
        </div>
        <button className="btn-secondary" onClick={onAsk}>
          <ArrowLeft size={16} /> Back to Answer
        </button>
      </header>

      <section className="source-library">
        {answer.citations.map((citation: Citation, index: number) => {
          const matchScore = Math.round(citation.score * 100);
          return (
            <article className="source-document" key={`${citation.document_id}-${citation.chunk_index}`}>
              <div className="source-document-head">
                <span className="source-number">#{index + 1}</span>
                <div>
                  <strong>{citation.document_name}</strong>
                  <p>
                    Passage Chunk {citation.chunk_index + 1} · {matchScore}% Semantic Match
                  </p>
                </div>
                <FileText size={18} />
              </div>
              <div className="source-document-text">{citation.text}</div>
            </article>
          );
        })}
      </section>
    </div>
  );
}

