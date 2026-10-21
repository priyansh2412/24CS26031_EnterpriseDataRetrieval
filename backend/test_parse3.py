import re

with open("drive_html_test.html", "r", encoding="utf-8", errors="ignore") as f:
    text = f.read()

# Let's inspect snippet:
# <div class="JxSEve" aria-label="Code_of_Employee_Conduct.pdf PDF Shared" ... ssk='5:auSv138:1KyQk8lKaAl...'
# Let's see the full ssk or data attributes around JxSEve
matches = re.findall(r'class="JxSEve"[^>]*aria-label="([^"]+)"[^>]*ssk=\'([^\']+)\'', text)
print("Matches with ssk:", len(matches))
for label, ssk in matches:
    print(label, "-> ssk:", ssk)

# Also let's search for data-id or data-target or similar in that block
blocks = re.findall(r'<div[^>]*class="JxSEve"[^>]*>.*?</div>', text)
print("JxSEve blocks:", len(blocks))
if blocks:
    print("Block 0:", blocks[0][:300])

