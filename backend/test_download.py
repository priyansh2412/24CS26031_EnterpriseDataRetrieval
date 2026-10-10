import requests

file_id = "1KyQk8lKaAl_Oh8PmyYF4Rd29vxUSbJJT"
url = f"https://drive.google.com/uc?export=download&id={file_id}"
resp = requests.get(url, headers={"User-Agent": "Mozilla/5.0"})
print("Status:", resp.status_code, "Length:", len(resp.content))
if resp.status_code == 200:
    print("Content header:", resp.content[:20])

