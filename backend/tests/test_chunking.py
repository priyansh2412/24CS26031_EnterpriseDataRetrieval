from app.services.ingestion import chunk_text

def test_chunking_has_overlap():
    words = " ".join(f"word{i}" for i in range(700))
    chunks = chunk_text(words, size=500, overlap=75)
    assert len(chunks) == 2
    assert "word425" in chunks[0] and "word425" in chunks[1]
