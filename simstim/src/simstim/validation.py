"""Input validation module for Simstim.

Security Note: This module provides strict input validation to prevent
command injection and other input-based attacks (CWE-78).

All user input that may be passed to shell commands or external processes
MUST be validated through this module.
"""

from __future__ import annotations

import re
import shlex
from typing import NamedTuple


class ValidationResult(NamedTuple):
    """Result of input validation."""

    valid: bool
    sanitized: str | None
    error: str | None


# Allowlist of valid Loa phase commands
# These are the only commands that can be invoked via /start_phase
ALLOWED_PHASE_COMMANDS = frozenset({
    "/plan-and-analyze",
    "/architect",
    "/sprint-plan",
    "/implement",
    "/review-sprint",
    "/audit-sprint",
    "/deploy-production",
    "/mount",
    "/ride",
    "/audit",
    "/audit-deployment",
    "/translate",
    "/contribute",
    "/update-loa",
    "/validate",
    "/run",
    "/run-status",
    "/run-halt",
    "/run-resume",
    "/ledger",
    "/archive-cycle",
    "/retrospective",
    "/skill-audit",
    "/feedback",
})

# Pattern for valid sprint identifiers (sprint-N where N is 1-99)
SPRINT_PATTERN = re.compile(r'^sprint-([1-9][0-9]?)$')

# Pattern for valid cycle labels (alphanumeric with hyphens, max 50 chars)
CYCLE_LABEL_PATTERN = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9\s\-_]{0,48}[a-zA-Z0-9]?$')

# Characters that are NEVER allowed in any input (shell metacharacters)
DANGEROUS_CHARS = frozenset({
    ';', '&', '|', '$', '`', '\\', '\n', '\r',
    '>', '<', '(', ')', '{', '}', '[', ']',
    '!', '#', '*', '?', '~',
})


def validate_phase_command(command: str) -> ValidationResult:
    """Validate a Loa phase command for safe execution.

    Args:
        command: Raw command string from user input (e.g., "/implement sprint-1")

    Returns:
        ValidationResult with sanitized command if valid

    Security:
        - Only allowlisted commands are accepted
        - Arguments are validated against expected patterns
        - Shell metacharacters are rejected
    """
    if not command or not isinstance(command, str):
        return ValidationResult(False, None, "Command cannot be empty")

    # SECURITY: Check for dangerous characters BEFORE any normalization
    # This must happen first to prevent newline injection and other attacks
    for char in DANGEROUS_CHARS:
        if char in command:
            return ValidationResult(
                False, None,
                f"Invalid character in command: {repr(char)}"
            )

    # Strip and normalize whitespace (safe now that dangerous chars are rejected)
    command = " ".join(command.split())

    # Check for empty command after normalization (whitespace-only input)
    if not command:
        return ValidationResult(False, None, "Command cannot be empty")

    # Split into command and arguments
    parts = command.split(maxsplit=1)
    base_command = parts[0]
    args = parts[1] if len(parts) > 1 else ""

    # Validate base command is in allowlist
    if base_command not in ALLOWED_PHASE_COMMANDS:
        return ValidationResult(
            False, None,
            f"Unknown command: {base_command}. "
            f"Allowed commands: {', '.join(sorted(ALLOWED_PHASE_COMMANDS)[:5])}..."
        )

    # Validate arguments based on command type
    validation_error = _validate_command_args(base_command, args)
    if validation_error:
        return ValidationResult(False, None, validation_error)

    # Construct safe command using shlex.quote for any arguments
    if args:
        # Re-parse and quote each argument for safety
        safe_args = " ".join(shlex.quote(arg) for arg in shlex.split(args))
        sanitized = f"{base_command} {safe_args}"
    else:
        sanitized = base_command

    return ValidationResult(True, sanitized, None)


def _validate_command_args(command: str, args: str) -> str | None:
    """Validate command arguments based on command type.

    Args:
        command: Base command (e.g., "/implement")
        args: Argument string

    Returns:
        Error message if invalid, None if valid
    """
    # Commands that require sprint argument
    sprint_commands = {"/implement", "/review-sprint", "/audit-sprint", "/run"}

    if command in sprint_commands:
        if not args:
            return f"{command} requires a sprint argument (e.g., sprint-1)"

        # First arg should be sprint-N
        first_arg = args.split()[0]
        if not SPRINT_PATTERN.match(first_arg):
            return (
                f"Invalid sprint format: {first_arg}. "
                "Expected format: sprint-N where N is 1-99"
            )

    # Commands that require a label argument
    label_commands = {"/archive-cycle"}

    if command in label_commands:
        if not args:
            return f"{command} requires a label argument"

        # Unquote if quoted
        label = args.strip("'\"")
        if not CYCLE_LABEL_PATTERN.match(label):
            return (
                f"Invalid label format: {label}. "
                "Labels must be alphanumeric with hyphens/underscores, max 50 chars"
            )

    # Commands that take optional path arguments
    path_commands = {"/translate", "/validate", "/audit"}

    if command in path_commands and args:
        # Validate each argument is a reasonable path (no shell metacharacters)
        for arg in shlex.split(args):
            for char in DANGEROUS_CHARS:
                if char in arg:
                    return f"Invalid character in argument: {repr(char)}"

    return None


def validate_callback_request_id(request_id: str) -> ValidationResult:
    """Validate a permission request ID from callback data.

    Args:
        request_id: Request ID string (should be alphanumeric with hyphens)

    Returns:
        ValidationResult with sanitized ID if valid
    """
    if not request_id or not isinstance(request_id, str):
        return ValidationResult(False, None, "Request ID cannot be empty")

    # Request IDs should be alphanumeric with hyphens (UUID-like)
    if not re.match(r'^[a-zA-Z0-9\-]{8,64}$', request_id):
        return ValidationResult(
            False, None,
            "Invalid request ID format"
        )

    return ValidationResult(True, request_id, None)


def sanitize_for_display(text: str, max_length: int = 200) -> str:
    """Sanitize text for safe display in messages.

    Args:
        text: Raw text to sanitize
        max_length: Maximum length for output

    Returns:
        Sanitized text safe for display
    """
    if not text:
        return ""

    # Remove or escape potentially dangerous characters
    # (prevent HTML/Markdown injection in Telegram messages)
    text = text.replace("<", "&lt;").replace(">", "&gt;")

    # Truncate to max length
    if len(text) > max_length:
        text = text[:max_length - 3] + "..."

    return text
