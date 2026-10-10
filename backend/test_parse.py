import re

with open("drive_html_test.html", "r", encoding="utf-8", errors="ignore") as f:
    text = f.read()

title_m = re.search(r"<title>(.*?)</title>", text)
if title_m:
    clean_title = title_m.group(1).split(" - Google Drive")[0].split(" - ")[0].strip()
    print("Folder Title:", clean_title)

# Search for matches in data
# Google Drive HTML includes data in window['_DRIVE_ivd'] or AF_initDataCallback
# Let's inspect instances of file IDs or names
files = []
# Pattern: ["ID", ["Name", ...]] or similar
for match in re.finditer(r'\["([a-zA-Z0-9_-]{25,40})",\["([^"\\]+)"', text):
    fid, fname = match.groups()
    files.append((fid, fname))

print("Found file matches:", len(files))
for fid, fname in files[:20]:
    print(f"ID: {fid} | Name: {fname}")

