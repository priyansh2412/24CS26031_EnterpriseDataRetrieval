import re

with open("drive_html_test.html", "r", encoding="utf-8", errors="ignore") as f:
    text = f.read()

# Look for occurrences of .pdf or other known document extensions in text
extensions = [".pdf", ".docx", ".txt", ".xlsx", ".csv", ".pptx"]
for ext in extensions:
    matches = [m.start() for m in re.finditer(re.escape(ext), text, re.IGNORECASE)]
    print(f"Extension {ext}: {len(matches)} occurrences")
    if matches:
        for idx in matches[:5]:
            snippet = text[max(0, idx - 80):min(len(text), idx + 80)]
            print("Snippet:", repr(snippet))

