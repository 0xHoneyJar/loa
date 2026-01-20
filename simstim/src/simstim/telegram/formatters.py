"""Message formatters for Telegram notifications.

Provides formatting functions for permission requests, phase transitions,
and status messages with proper Markdown escaping and redaction.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from simstim.bridge.permission_queue import PermissionRequest
    from simstim.bridge.stdout_parser import ParsedPhase, PhaseType, RiskLevel


# Risk level emoji mapping
RISK_EMOJI: dict[str, str] = {
    "low": "🟢",
    "medium": "🟡",
    "high": "🟠",
    "critical": "🔴",
}

# Phase emoji mapping
PHASE_EMOJI: dict[str, str] = {
    "discovery": "🔍",
    "architecture": "🏗️",
    "sprint_planning": "📋",
    "implementation": "⚙️",
    "review": "👀",
    "audit": "🔒",
    "deployment": "🚀",
}

# Default redaction patterns
DEFAULT_REDACT_PATTERNS = [
    "password",
    "secret",
    "token",
    "api_key",
    "private_key",
    "credential",
    "auth",
]


def escape_markdown(text: str) -> str:
    """Escape special Markdown characters for Telegram.

    Args:
        text: Text to escape

    Returns:
        Escaped text safe for Markdown parsing
    """
    # Characters that need escaping in Telegram Markdown
    special_chars = ["_", "*", "[", "]", "(", ")", "~", "`", ">", "#", "+", "-", "=", "|", "{", "}", ".", "!"]
    for char in special_chars:
        text = text.replace(char, f"\\{char}")
    return text


def redact_sensitive(
    text: str,
    patterns: list[str] | None = None,
) -> str:
    """Redact sensitive information from text.

    Args:
        text: Text to redact
        patterns: Patterns to redact (uses defaults if None)

    Returns:
        Redacted text
    """
    patterns = patterns or DEFAULT_REDACT_PATTERNS
    result = text

    for pattern in patterns:
        # Match pattern followed by = or : and a value
        result = re.sub(
            rf"({re.escape(pattern)})\s*[=:]\s*\S+",
            r"\1=***REDACTED***",
            result,
            flags=re.IGNORECASE,
        )
        # Also match in paths
        result = re.sub(
            rf"/{re.escape(pattern)}(?:/|$)",
            "/***REDACTED***/",
            result,
            flags=re.IGNORECASE,
        )

    return result


def format_permission_request(
    request: PermissionRequest,
    timeout_seconds: int,
    redact_patterns: list[str] | None = None,
) -> str:
    """Format permission request for Telegram message.

    Args:
        request: Permission request to format
        timeout_seconds: Timeout duration for display
        redact_patterns: Patterns to redact (uses defaults if None)

    Returns:
        Formatted message string
    """
    risk_emoji = RISK_EMOJI.get(request.risk_level.value, "⚪")
    action_display = request.action.value.replace("_", " ").title()

    # Redact sensitive info from target and context
    safe_target = redact_sensitive(request.target, redact_patterns)
    safe_context = redact_sensitive(request.context, redact_patterns)

    # Format timeout display
    minutes = timeout_seconds // 60
    seconds = timeout_seconds % 60
    timeout_display = f"{minutes}:{seconds:02d}" if minutes else f"{seconds}s"

    # Build message - use HTML for better formatting
    lines = [
        "🔐 <b>Permission Request</b>",
        "",
        f"<b>Type:</b> {action_display}",
        f"<b>Target:</b> <code>{safe_target}</code>",
        f"<b>Risk:</b> {risk_emoji} {request.risk_level.value.upper()}",
    ]

    # Add context if available
    if safe_context.strip():
        # Truncate context if too long
        context_lines = safe_context.strip().split("\n")[-3:]  # Last 3 lines
        context_str = "\n".join(context_lines)
        if len(context_str) > 200:
            context_str = context_str[:197] + "..."
        lines.extend([
            "",
            "<b>Context:</b>",
            f"<pre>{context_str}</pre>",
        ])

    # Add timeout warning
    lines.extend([
        "",
        f"⏱️ Auto-deny in {timeout_display}",
    ])

    return "\n".join(lines)


def format_phase_notification(
    phase: ParsedPhase,
) -> str:
    """Format phase transition notification.

    Args:
        phase: Parsed phase transition

    Returns:
        Formatted message string
    """
    emoji = PHASE_EMOJI.get(phase.phase.value, "📌")
    phase_display = phase.phase.value.replace("_", " ").title()

    lines = [
        f"{emoji} <b>Phase: {phase_display}</b>",
    ]

    # Add metadata if present
    if phase.metadata:
        for key, value in phase.metadata.items():
            lines.append(f"  {key}: <code>{value}</code>")

    return "\n".join(lines)


def format_status(
    pending_count: int,
    current_phase: PhaseType | None = None,
    loa_running: bool = True,
    bot_connected: bool = True,
    policy_count: int = 0,
    auto_approved: int = 0,
    manual_approved: int = 0,
    denied: int = 0,
) -> str:
    """Format status message.

    Args:
        pending_count: Number of pending permission requests
        current_phase: Current Loa phase (if known)
        loa_running: Whether Loa process is running
        bot_connected: Whether bot is connected
        policy_count: Number of active auto-approve policies
        auto_approved: Count of auto-approved requests this session
        manual_approved: Count of manually approved requests this session
        denied: Count of denied requests this session

    Returns:
        Formatted status message
    """
    lines = [
        "📊 <b>Simstim Status</b>",
        "",
        f"<b>Connection:</b>",
        f"  Loa: {'✅ Running' if loa_running else '⏹️ Stopped'}",
        f"  Bot: {'✅ Online' if bot_connected else '❌ Offline'}",
    ]

    if current_phase:
        emoji = PHASE_EMOJI.get(current_phase.value, "📌")
        phase_display = current_phase.value.replace("_", " ").title()
        lines.append(f"  Phase: {emoji} {phase_display}")

    lines.extend([
        "",
        f"<b>Permissions:</b>",
        f"  Pending: <code>{pending_count}</code>",
        f"  Auto-approved: {auto_approved}",
        f"  Manual: {manual_approved}",
        f"  Denied: {denied}",
    ])

    if policy_count > 0:
        lines.extend([
            "",
            f"<b>Policies:</b> {policy_count} active",
        ])

    return "\n".join(lines)


def format_error(error: str, details: str | None = None) -> str:
    """Format error message.

    Args:
        error: Error message
        details: Additional details

    Returns:
        Formatted error message
    """
    lines = [
        "⚠️ <b>Error</b>",
        "",
        f"{error}",
    ]

    if details:
        lines.extend([
            "",
            f"<pre>{details[:500]}</pre>",  # Truncate long details
        ])

    return "\n".join(lines)


def format_response_confirmation(
    request_id: str,
    approved: bool,
    user_id: int,
    auto: bool = False,
    policy_name: str | None = None,
) -> str:
    """Format response confirmation message suffix.

    Args:
        request_id: Permission request ID
        approved: Whether request was approved
        user_id: ID of user who responded (0 for system)
        auto: Whether this was an auto-response
        policy_name: Name of policy that triggered auto-response

    Returns:
        Formatted confirmation suffix
    """
    status = "✅ Approved" if approved else "❌ Denied"

    if auto:
        if policy_name == "timeout":
            return f"\n\n{status} (timeout)"
        elif policy_name:
            return f"\n\n{status} by policy: {policy_name}"
        else:
            return f"\n\n{status} (auto)"
    else:
        return f"\n\n{status} by user {user_id}"
