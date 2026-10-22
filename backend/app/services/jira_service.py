import logging
import re
from typing import Any
import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class JiraError(Exception):
    """Custom sanitized exception for Jira API errors."""
    pass


def _get_base_url() -> str:
    url = (settings.jira_base_url or "").strip().rstrip("/")
    if url and not url.startswith("http://") and not url.startswith("https://"):
        url = f"https://{url}"
    return url


def _get_auth() -> tuple[str, str]:
    return (settings.jira_email.strip(), settings.jira_api_token.strip())


def text_to_adf(text: str) -> dict[str, Any]:
    """
    Converts plain text into Atlassian Document Format (ADF) doc version 1.
    Each non-empty line becomes a paragraph.
    """
    lines = [line.strip() for line in (text or "").split("\n") if line.strip()]
    if not lines:
        return {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "paragraph",
                    "content": []
                }
            ]
        }

    paragraphs = []
    for line in lines:
        paragraphs.append({
            "type": "paragraph",
            "content": [
                {
                    "type": "text",
                    "text": line
                }
            ]
        })

    return {
        "version": 1,
        "type": "doc",
        "content": paragraphs
    }


def _sanitize_error_response(resp: httpx.Response) -> str:
    """Extract error messages from Jira response without leaking sensitive info."""
    status_code = resp.status_code
    if status_code in (401, 403):
        return f"Jira authentication failed ({status_code}). Please verify JIRA_EMAIL and JIRA_API_TOKEN."
    if status_code == 404:
        return f"Jira resource or project key not found ({status_code}). Please verify JIRA_BASE_URL and project key."
    if status_code == 429:
        return "Jira API rate limit exceeded (429). Please wait and try again."

    try:
        data = resp.json()
        error_msgs = data.get("errorMessages", [])
        field_errors = data.get("errors", {})
        combined = []
        if error_msgs:
            combined.extend(error_msgs)
        if field_errors:
            for field, msg in field_errors.items():
                combined.append(f"{field}: {msg}")
        if combined:
            return f"Jira API error ({status_code}): {'; '.join(combined)}"
    except Exception:
        pass

    clean_text = resp.text[:200].replace("\n", " ").strip()
    return f"Jira API error ({status_code}): {clean_text or 'Unknown error'}"


def test_connection() -> dict[str, Any]:
    """Test Jira connection using GET /rest/api/3/myself."""
    base_url = _get_base_url()
    if not base_url or not settings.jira_email or not settings.jira_api_token:
        raise JiraError("Jira is not configured. Missing base URL, email, or API token.")

    endpoint = f"{base_url}/rest/api/3/myself"
    try:
        with httpx.Client(timeout=15.0) as client:
            resp = client.get(
                endpoint,
                auth=_get_auth(),
                headers={"Accept": "application/json"}
            )
            if resp.status_code != 200:
                raise JiraError(_sanitize_error_response(resp))
            data = resp.json()
            return {
                "active": data.get("active", False),
                "account_id": data.get("accountId"),
                "display_name": data.get("displayName"),
                "email": data.get("emailAddress")
            }
    except httpx.TimeoutException:
        raise JiraError("Jira API request timed out after 15 seconds.")
    except httpx.RequestError as exc:
        raise JiraError(f"Failed to connect to Jira: {exc}")


def find_account_id(email: str | None = None, name_hint: str | None = None) -> str | None:
    """
    Search Jira user directory for active human account matching email or name.
    GET /rest/api/3/user/search?query=...
    Never raises; returns None on failure.
    """
    base_url = _get_base_url()
    if not base_url or not settings.jira_email or not settings.jira_api_token:
        return None

    queries = []
    if email and email.strip():
        queries.append(email.strip())
    if name_hint and name_hint.strip() and name_hint.strip() not in queries:
        queries.append(name_hint.strip())

    if not queries:
        return None

    try:
        with httpx.Client(timeout=15.0) as client:
            for q in queries:
                resp = client.get(
                    f"{base_url}/rest/api/3/user/search",
                    params={"query": q, "maxResults": 5},
                    auth=_get_auth(),
                    headers={"Accept": "application/json"}
                )
                if resp.status_code == 200:
                    users = resp.json()
                    for u in users:
                        if u.get("active", False) and u.get("accountType") != "app":
                            acc_id = u.get("accountId")
                            if acc_id:
                                return str(acc_id)
    except Exception as exc:
        logger.warning(f"find_account_id exception: {exc}")

    return None


def create_issue(
    project_key: str,
    summary: str,
    description_text: str,
    due_date: str | None = None,
    labels: list[str] | None = None,
    assignee_account_id: str | None = None,
) -> dict[str, Any]:
    """
    Creates a Jira Cloud issue via POST /rest/api/3/issue.
    Returns: {"key": issue_key, "url": issue_url, "dropped_fields": dropped_fields}
    If Jira returns 400 due to optional fields, retries once without them.
    """
    base_url = _get_base_url()
    if not base_url or not settings.jira_email or not settings.jira_api_token:
        raise JiraError("Jira is not configured. Missing base URL, email, or API token.")

    clean_summary = (summary or "Task from Atlas Team Chat").strip()[:250]
    clean_labels = [re.sub(r"[^\w-]", "-", l.strip()) for l in (labels or []) if l.strip()]

    issue_type_name = (settings.jira_default_issue_type or "Task").strip()

    fields: dict[str, Any] = {
        "project": {"key": project_key.strip()},
        "issuetype": {"name": issue_type_name},
        "summary": clean_summary,
        "description": text_to_adf(description_text)
    }

    if due_date and due_date.strip():
        fields["duedate"] = due_date.strip()
    if clean_labels:
        fields["labels"] = clean_labels
    if assignee_account_id and assignee_account_id.strip():
        fields["assignee"] = {"accountId": assignee_account_id.strip()}

    endpoint = f"{base_url}/rest/api/3/issue"
    dropped_fields: list[str] = []

    try:
        with httpx.Client(timeout=15.0) as client:
            resp = client.post(
                endpoint,
                json={"fields": fields},
                auth=_get_auth(),
                headers={"Content-Type": "application/json", "Accept": "application/json"}
            )

            # Check if 400 occurred with optional fields that can be dropped
            has_optional = bool("duedate" in fields or "labels" in fields or "assignee" in fields)
            if resp.status_code == 400 and has_optional:
                logger.warning(f"Jira issue creation returned 400. Retrying without optional fields: {resp.text}")
                dropped_notes = []
                if "duedate" in fields:
                    dropped_fields.append("duedate")
                    dropped_notes.append(f"Due date: {fields.pop('duedate')}")
                if "labels" in fields:
                    dropped_fields.append("labels")
                    dropped_notes.append(f"Labels: {', '.join(fields.pop('labels'))}")
                if "assignee" in fields:
                    dropped_fields.append("assignee")
                    dropped_notes.append(f"Assignee ID: {fields.pop('assignee').get('accountId')}")

                new_desc = description_text
                if dropped_notes:
                    new_desc += "\n\nNote: The following fields could not be set directly in Jira:\n" + "\n".join(dropped_notes)
                fields["description"] = text_to_adf(new_desc)

                resp = client.post(
                    endpoint,
                    json={"fields": fields},
                    auth=_get_auth(),
                    headers={"Content-Type": "application/json", "Accept": "application/json"}
                )

            if resp.status_code not in (200, 201):
                raise JiraError(_sanitize_error_response(resp))

            data = resp.json()
            issue_key = data.get("key")
            if not issue_key:
                raise JiraError("Jira issue created but response missing 'key'.")

            issue_url = f"{base_url}/browse/{issue_key}"
            return {
                "key": issue_key,
                "url": issue_url,
                "dropped_fields": dropped_fields
            }

    except httpx.TimeoutException:
        raise JiraError("Jira API request timed out after 15 seconds.")
    except httpx.RequestError as exc:
        raise JiraError(f"Failed to connect to Jira: {exc}")
