import re
import requests

url = 'https://drive.google.com/drive/folders/1I9x9ihja3-FIVT7urWgZsTKWWvU4kjE7?usp=drive_link'
resp = requests.get(url, headers={'User-Agent': 'Mozilla/5.0'})
text = resp.text

title_m = re.search(r'<title>(.*?)</title>', text)
folder_name = 'Google Drive Folder'
if title_m:
    raw = title_m.group(1)
    clean = re.sub(r' - Google Drive.*', '', raw).strip()
    clean = clean.encode('ascii', 'ignore').decode('ascii').strip()
    folder_name = clean or folder_name

print('Clean folder name:', folder_name)

items = []
seen = set()
matches = re.findall(r'class="JxSEve"[^>]*aria-label="([^"]+)"[^>]*ssk=\'([^\']+)\'', text)
for label, ssk in matches:
    m = re.search(r':([a-zA-Z0-9_-]{20,45})-0-16', ssk)
    if m:
        item_id = m.group(1)
        clean_label = re.sub(r'\s+(PDF|Google Docs|Google Sheets|Shared).*$', '', label).strip()
        if item_id not in seen:
            seen.add(item_id)
            items.append({'id': item_id, 'name': clean_label})

print('Found items count:', len(items))
for it in items:
    print(it['id'], "->", it['name'])

