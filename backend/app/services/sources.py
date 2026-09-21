"""Optional source adapters. Keep cloud credentials outside the application database."""
from pathlib import Path


def download_google_drive_folder(folder_id: str, destination: Path, credentials_file: str) -> list[Path]:
    """Download files from one Drive folder; call this from a background worker in production."""
    from google.oauth2.service_account import Credentials
    from googleapiclient.discovery import build
    destination.mkdir(parents=True, exist_ok=True)
    credentials = Credentials.from_service_account_file(credentials_file, scopes=["https://www.googleapis.com/auth/drive.readonly"])
    service = build("drive", "v3", credentials=credentials)
    files = service.files().list(q=f"'{folder_id}' in parents and trashed=false", fields="files(id,name,mimeType)").execute().get("files", [])
    downloaded: list[Path] = []
    for item in files:
        # Google-native files require export endpoints; this adapter deliberately accepts binary Office/PDF files.
        if item["mimeType"].startswith("application/vnd.google-apps"):
            continue
        target = destination / item["name"]
        content = service.files().get_media(fileId=item["id"]).execute()
        target.write_bytes(content); downloaded.append(target)
    return downloaded


def download_s3_prefix(bucket: str, prefix: str, destination: Path) -> list[Path]:
    """Optional S3 adapter; install boto3 only when this source is enabled."""
    import boto3
    destination.mkdir(parents=True, exist_ok=True)
    client = boto3.client("s3")
    results: list[Path] = []
    for page in client.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            key = item["Key"]
            if key.endswith("/"): continue
            target = destination / Path(key).name
            client.download_file(bucket, key, str(target)); results.append(target)
    return results
