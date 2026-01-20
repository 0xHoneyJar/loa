"""Deep link generation for Loa quality gate files.

Generates links for quick navigation to feedback files,
sprint directories, and specific file locations.
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import quote

if TYPE_CHECKING:
    pass


def generate_file_link(
    path: Path | str,
    line_number: int | None = None,
    *,
    scheme: str = "file",
    base_url: str | None = None,
) -> str:
    """Generate a deep link to a file.

    Args:
        path: Path to the file
        line_number: Optional line number for editors
        scheme: URL scheme ("file", "vscode", "cursor", "github")
        base_url: Base URL for web-based schemes (required for "github")

    Returns:
        Deep link URL string
    """
    path = Path(path)

    if scheme == "file":
        # file:// URL for local files
        url = f"file://{path.absolute()}"
        if line_number:
            # Most editors support #line syntax
            url += f"#L{line_number}"
        return url

    elif scheme == "vscode":
        # vscode://file/path:line:column
        url = f"vscode://file/{path.absolute()}"
        if line_number:
            url += f":{line_number}"
        return url

    elif scheme == "cursor":
        # cursor://file/path:line
        url = f"cursor://file/{path.absolute()}"
        if line_number:
            url += f":{line_number}"
        return url

    elif scheme == "github":
        if not base_url:
            raise ValueError("base_url required for GitHub links")
        # GitHub blob URL: base_url/blob/branch/path#L123
        encoded_path = quote(str(path))
        url = f"{base_url}/blob/main/{encoded_path}"
        if line_number:
            url += f"#L{line_number}"
        return url

    else:
        # Default to file:// scheme
        return f"file://{path.absolute()}"


def generate_sprint_link(
    sprint_id: str,
    file_type: str = "reviewer",
    *,
    grimoire_root: Path | None = None,
    scheme: str = "file",
) -> str:
    """Generate a link to a sprint file.

    Args:
        sprint_id: Sprint identifier (e.g., "sprint-1")
        file_type: Type of file ("reviewer", "engineer-feedback", "auditor-sprint-feedback")
        grimoire_root: Root path for grimoires (default: grimoires/loa)
        scheme: URL scheme for the link

    Returns:
        Deep link to the sprint file
    """
    root = grimoire_root or Path("grimoires/loa")
    file_map = {
        "reviewer": "reviewer.md",
        "engineer-feedback": "engineer-feedback.md",
        "auditor-sprint-feedback": "auditor-sprint-feedback.md",
        "completed": "COMPLETED",
    }

    filename = file_map.get(file_type, f"{file_type}.md")
    path = root / "a2a" / sprint_id / filename

    return generate_file_link(path, scheme=scheme)


def generate_notes_link(
    *,
    grimoire_root: Path | None = None,
    scheme: str = "file",
) -> str:
    """Generate a link to NOTES.md.

    Args:
        grimoire_root: Root path for grimoires (default: grimoires/loa)
        scheme: URL scheme for the link

    Returns:
        Deep link to NOTES.md
    """
    root = grimoire_root or Path("grimoires/loa")
    path = root / "NOTES.md"
    return generate_file_link(path, scheme=scheme)


def generate_feedback_link(
    feedback_type: str,
    sprint_id: str | None = None,
    *,
    grimoire_root: Path | None = None,
    scheme: str = "file",
) -> str:
    """Generate a link to a feedback file.

    Args:
        feedback_type: Type of feedback ("engineer" or "auditor")
        sprint_id: Sprint identifier (required)
        grimoire_root: Root path for grimoires (default: grimoires/loa)
        scheme: URL scheme for the link

    Returns:
        Deep link to the feedback file
    """
    if not sprint_id:
        raise ValueError("sprint_id is required for feedback links")

    file_type = (
        "engineer-feedback" if feedback_type == "engineer" else "auditor-sprint-feedback"
    )
    return generate_sprint_link(sprint_id, file_type, grimoire_root=grimoire_root, scheme=scheme)


def format_telegram_link(url: str, text: str) -> str:
    """Format a link for Telegram HTML messages.

    Args:
        url: The URL to link to
        text: Display text for the link

    Returns:
        HTML-formatted link string
    """
    return f'<a href="{url}">{text}</a>'


def generate_quick_links(
    sprint_id: str | None = None,
    *,
    grimoire_root: Path | None = None,
    scheme: str = "file",
    include_notes: bool = True,
) -> dict[str, str]:
    """Generate a set of quick links for Telegram notifications.

    Args:
        sprint_id: Optional sprint identifier for sprint-specific links
        grimoire_root: Root path for grimoires
        scheme: URL scheme for links
        include_notes: Include NOTES.md link

    Returns:
        Dictionary of link names to URLs
    """
    links = {}

    if include_notes:
        links["notes"] = generate_notes_link(grimoire_root=grimoire_root, scheme=scheme)

    if sprint_id:
        links["reviewer"] = generate_sprint_link(
            sprint_id, "reviewer", grimoire_root=grimoire_root, scheme=scheme
        )
        links["engineer_feedback"] = generate_sprint_link(
            sprint_id, "engineer-feedback", grimoire_root=grimoire_root, scheme=scheme
        )
        links["auditor_feedback"] = generate_sprint_link(
            sprint_id, "auditor-sprint-feedback", grimoire_root=grimoire_root, scheme=scheme
        )

    return links


def format_quick_links_message(
    links: dict[str, str],
    *,
    header: str = "📎 Quick Links",
) -> str:
    """Format quick links for a Telegram message.

    Args:
        links: Dictionary of link names to URLs
        header: Header text for the links section

    Returns:
        Formatted message string with HTML links
    """
    if not links:
        return ""

    display_names = {
        "notes": "📋 NOTES.md",
        "reviewer": "📝 Reviewer Report",
        "engineer_feedback": "🔧 Engineer Feedback",
        "auditor_feedback": "🔒 Auditor Feedback",
    }

    lines = [f"<b>{header}</b>"]
    for key, url in links.items():
        name = display_names.get(key, key.replace("_", " ").title())
        lines.append(format_telegram_link(url, name))

    return "\n".join(lines)
