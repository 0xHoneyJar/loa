"""Epistemic scope filtering for remote model requests (SDD §4.1.2, Sprint 9).

Filters context (system prompts, appended messages) based on a model's
context_access trust scopes before sending to a remote provider adapter.

Implements Ostrom Principle #1 applied to knowledge: models only receive
information their epistemic trust scopes permit.

Context access dimensions:
  architecture:    full | summary | none  — SDD, PRD, protocol docs
  business_logic:  full | redacted | none — implementation code
  security:        full | redacted | none — audit findings, CVEs
  lore:            full | summary | none  — institutional knowledge

When context_access is missing entirely, all dimensions default to "full"
(backward compatible with pre-v7 model-permissions).

Modes:
  enforce: Filter messages before sending (default when wired in)
  audit:   Log what would be filtered but pass messages unmodified

Language limitations (BB-502):
  Function body redaction (_FUNCTION_BODY_PATTERN) supports Python, JavaScript,
  and class definitions. Go func, Rust fn, Java methods without 'function'
  keyword, and arrow functions are not detected. This is best-effort content
  reduction, not a security boundary.
"""

from __future__ import annotations

import logging
import os
import re
from copy import deepcopy
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger("loa_cheval.routing.context_filter")

# Summary truncation limit (BB-505: extracted from hardcoded value)
ARCHITECTURE_SUMMARY_MAX_CHARS = 500

# Default context_access: all dimensions fully open
DEFAULT_CONTEXT_ACCESS: Dict[str, str] = {
    "architecture": "full",
    "business_logic": "full",
    "security": "full",
    "lore": "full",
}

# Patterns for identifying content categories in messages
_ARCHITECTURE_MARKERS = re.compile(
    r"(?:^#+\s*(?:Software Design|System Architecture|SDD|PRD|Technical Design|API Design|Data Model)"
    r"|(?:## (?:Overview|Architecture|Components|Interfaces|Endpoints)))",
    re.MULTILINE | re.IGNORECASE,
)

_SECURITY_MARKERS = re.compile(
    r"(?:CVE-\d{4}-\d+|VULN-|SECURITY:|audit finding|vulnerability|"
    r"## (?:Security|Audit|Vulnerability|Findings)|"
    r"OWASP|injection|XSS|CSRF|(?:secret|credential) (?:leak|exposure))",
    re.MULTILINE | re.IGNORECASE,
)

# Note (BB-507): context:\s*['\"] may false-positive on non-lore YAML fields.
# Acceptable for content reduction (not a security boundary). Tighten if needed.
_LORE_MARKERS = re.compile(
    r"(?:^#+\s*(?:Lore|Vision|Bridgebuilder|Retrospective)"
    r"|(?:lore_index|vision_registry|institutional knowledge)"
    r"|context:\s*['\"])",
    re.MULTILINE | re.IGNORECASE,
)

# Patterns for function/method bodies in code.
# Language support: Python (def/async def), JavaScript (function), class definitions.
# Does NOT match: Go func, Rust fn, Java methods, arrow functions (=>) — see BB-502.
_FUNCTION_BODY_PATTERN = re.compile(
    r"((?:def |async def |function |class )\w+[^{:]*[{:])"  # signature
    r"(.*?)"  # body
    r"(?=(?:def |async def |function |class |\Z))",  # next def or end
    re.DOTALL,
)


def get_context_access(trust_scopes: Optional[Dict[str, Any]]) -> Dict[str, str]:
    """Extract context_access from trust_scopes, with defaults.

    Args:
        trust_scopes: The model's trust_scopes dict (may or may not have context_access).

    Returns:
        Resolved context_access dict with all 4 dimensions.
    """
    if not trust_scopes:
        return dict(DEFAULT_CONTEXT_ACCESS)

    raw = trust_scopes.get("context_access")
    if not raw or not isinstance(raw, dict):
        return dict(DEFAULT_CONTEXT_ACCESS)

    return {
        "architecture": raw.get("architecture", "full"),
        "business_logic": raw.get("business_logic", "full"),
        "security": raw.get("security", "full"),
        "lore": raw.get("lore", "full"),
    }


def is_all_full(context_access: Dict[str, str]) -> bool:
    """Check if all dimensions are 'full' (no filtering needed)."""
    return all(v == "full" for v in context_access.values())


def _summarize_architecture(text: str) -> str:
    """Reduce architecture content to headers + first paragraph.

    Truncates to ARCHITECTURE_SUMMARY_MAX_CHARS total content characters.
    """
    lines = text.split("\n")
    result: List[str] = []
    chars = 0
    in_first_paragraph = False

    for line in lines:
        # Always keep headers
        if line.startswith("#"):
            result.append(line)
            chars += len(line)
            in_first_paragraph = True
            continue

        # Keep first paragraph content after each header
        if in_first_paragraph and line.strip():
            if chars < ARCHITECTURE_SUMMARY_MAX_CHARS:
                result.append(line)
                chars += len(line)
            else:
                result.append("[... content summarized ...]")
                in_first_paragraph = False
        elif not line.strip():
            in_first_paragraph = False
            result.append("")

    return "\n".join(result)


def _redact_function_bodies(text: str) -> str:
    """Replace function/method bodies with [redacted], keeping signatures."""

    def replacer(match: re.Match) -> str:
        signature = match.group(1)
        return signature + "\n    [redacted]\n"

    return _FUNCTION_BODY_PATTERN.sub(replacer, text)


def _strip_security_content(text: str) -> str:
    """Remove security-tagged sections from text.

    Scope (BB-503): Detects security content via header-level sections
    (Security/Audit/Vulnerability/Findings) and inline markers (CVE refs,
    OWASP keywords). Security discussions embedded in non-security-headed
    sections without explicit markers may pass through. This is a content
    reduction heuristic, not a leak-proof security boundary.
    """
    lines = text.split("\n")
    result: List[str] = []
    in_security_section = False

    for line in lines:
        # Check if entering a security section
        if re.match(r"^#{1,4}\s*(?:Security|Audit|Vulnerability|Findings)", line, re.IGNORECASE):
            in_security_section = True
            continue

        # Check if leaving security section (next top-level header)
        if in_security_section and re.match(r"^#{1,3}\s+", line) and not re.match(
            r"^#{1,4}\s*(?:Security|Audit|Vulnerability|Findings)", line, re.IGNORECASE
        ):
            in_security_section = False

        if not in_security_section:
            # Also strip inline CVE references and vulnerability markers
            cleaned = _SECURITY_MARKERS.sub("[security content filtered]", line)
            result.append(cleaned)

    return "\n".join(result)


def _summarize_lore(text: str) -> str:
    """Reduce lore to short fields only, stripping context blocks."""
    lines = text.split("\n")
    result: List[str] = []
    in_context_block = False

    for line in lines:
        # Skip context: blocks (keep short: fields)
        if re.match(r"\s*context:\s*['\"|>]", line):
            in_context_block = True
            continue
        if in_context_block:
            # End of context block: next field at same/lower indent, or blank line
            if re.match(r"\s*\w+:", line) and not line.strip().startswith("-"):
                in_context_block = False
            elif not line.strip():
                in_context_block = False
                continue
            else:
                continue

        result.append(line)

    return "\n".join(result)


def filter_message_content(content: str, context_access: Dict[str, str]) -> str:
    """Filter a single message's content based on epistemic trust scopes.

    Args:
        content: The message text to filter.
        context_access: Resolved context_access dict.

    Returns:
        Filtered content string.
    """
    if not content:
        return content

    result = content

    # Architecture filtering
    arch_level = context_access.get("architecture", "full")
    if arch_level == "none" and _ARCHITECTURE_MARKERS.search(result):
        # Strip architecture sections entirely
        lines = result.split("\n")
        filtered: List[str] = []
        in_arch = False
        for line in lines:
            if _ARCHITECTURE_MARKERS.match(line):
                in_arch = True
                continue
            if in_arch and re.match(r"^#{1,3}\s+", line) and not _ARCHITECTURE_MARKERS.match(line):
                in_arch = False
            if not in_arch:
                filtered.append(line)
        result = "\n".join(filtered)
    elif arch_level == "summary" and _ARCHITECTURE_MARKERS.search(result):
        result = _summarize_architecture(result)

    # Business logic filtering
    bl_level = context_access.get("business_logic", "full")
    if bl_level == "none":
        # Strip all code blocks
        result = re.sub(r"```[\s\S]*?```", "[code block filtered]", result)
    elif bl_level == "redacted":
        # Redact function bodies within code blocks
        def redact_code_block(match: re.Match) -> str:
            block = match.group(0)
            lang_line = block.split("\n", 1)[0]
            code = block[len(lang_line) + 1 : -3] if block.endswith("```") else block[len(lang_line) + 1 :]
            redacted = _redact_function_bodies(code)
            return lang_line + "\n" + redacted + ("```" if block.endswith("```") else "")

        result = re.sub(r"```\w*\n[\s\S]*?```", redact_code_block, result)

    # Security filtering
    sec_level = context_access.get("security", "full")
    if sec_level == "none":
        result = _strip_security_content(result)
    elif sec_level == "redacted":
        # Redact specific vulnerability details but keep section headers
        result = re.sub(
            r"(CVE-\d{4}-\d+)",
            "[CVE-redacted]",
            result,
        )

    # Lore filtering
    lore_level = context_access.get("lore", "full")
    if lore_level == "none" and _LORE_MARKERS.search(result):
        lines = result.split("\n")
        filtered_lines: List[str] = []
        in_lore = False
        for line in lines:
            if _LORE_MARKERS.match(line):
                in_lore = True
                continue
            if in_lore and re.match(r"^#{1,3}\s+", line) and not _LORE_MARKERS.match(line):
                in_lore = False
            if not in_lore:
                filtered_lines.append(line)
        result = "\n".join(filtered_lines)
    elif lore_level == "summary" and _LORE_MARKERS.search(result):
        result = _summarize_lore(result)

    return result


def filter_context(
    messages: List[Dict[str, Any]],
    trust_scopes: Optional[Dict[str, Any]],
    *,
    is_native_runtime: bool = False,
) -> List[Dict[str, Any]]:
    """Filter message context based on a model's epistemic trust scopes.

    Applied after agent binding resolution, before adapter.complete().
    Native runtime models bypass filtering entirely (they have file access anyway).

    Args:
        messages: List of message dicts with 'role' and 'content'.
        trust_scopes: The model's trust_scopes from model-permissions.yaml.
        is_native_runtime: If True, skip all filtering.

    Returns:
        Filtered copy of messages (original list is not mutated).
    """
    # Native runtime models bypass filtering
    if is_native_runtime:
        return messages

    context_access = get_context_access(trust_scopes)

    # If all dimensions are full, no filtering needed
    if is_all_full(context_access):
        return messages

    filtered_dimensions = {k: v for k, v in context_access.items() if v != "full"}
    logger.info(
        "context_filtered",
        extra={"dimensions": filtered_dimensions},
    )

    filtered = deepcopy(messages)
    for msg in filtered:
        content = msg.get("content", "")
        if isinstance(content, str) and content:
            msg["content"] = filter_message_content(content, context_access)
        elif content and not isinstance(content, str):
            # BB-504: Non-string content (list/dict) bypasses filtering.
            # Log warning so audit trail captures unfiltered structured content.
            logger.warning(
                "context_filter_non_string_passthrough type=%s role=%s",
                type(content).__name__,
                msg.get("role", "unknown"),
            )

    return filtered


# --- Permissions Loader (BB-501: bridge enforcement to invocation path) ---

_PERMISSIONS_CACHE: Optional[Dict[str, Any]] = None
_PERMISSIONS_MTIME: float = 0.0  # Last-modified time for file-stat invalidation


def invalidate_permissions_cache() -> None:
    """Invalidate the permissions cache (BB-601).

    Call this in tests or when model-permissions.yaml changes during a session.
    """
    global _PERMISSIONS_CACHE, _PERMISSIONS_MTIME
    _PERMISSIONS_CACHE = None
    _PERMISSIONS_MTIME = 0.0


def _load_permissions() -> Dict[str, Any]:
    """Load model-permissions.yaml with file-stat cache invalidation (BB-601).

    The cache is invalidated when the file's mtime changes, supporting
    long-running sessions where permissions may be updated.
    """
    global _PERMISSIONS_CACHE, _PERMISSIONS_MTIME

    # Check file stat for invalidation
    claude_dir = Path(__file__).resolve().parents[3]  # .claude/
    permissions_path = claude_dir / "data" / "model-permissions.yaml"

    if permissions_path.exists():
        current_mtime = permissions_path.stat().st_mtime
        if _PERMISSIONS_CACHE is not None and current_mtime == _PERMISSIONS_MTIME:
            return _PERMISSIONS_CACHE
        # File changed or first load — invalidate
        if current_mtime != _PERMISSIONS_MTIME:
            _PERMISSIONS_CACHE = None
            _PERMISSIONS_MTIME = current_mtime

    if _PERMISSIONS_CACHE is not None:
        return _PERMISSIONS_CACHE

    if not permissions_path.exists():
        logger.warning("model-permissions.yaml not found at %s", permissions_path)
        _PERMISSIONS_CACHE = {}
        return _PERMISSIONS_CACHE

    try:
        import yaml
        with open(permissions_path, "r") as f:
            data = yaml.safe_load(f)
        _PERMISSIONS_CACHE = data.get("model_permissions", {})
    except Exception as e:
        logger.warning("Failed to load model-permissions.yaml: %s", e)
        _PERMISSIONS_CACHE = {}

    return _PERMISSIONS_CACHE


def lookup_trust_scopes(provider: str, model_id: str) -> Optional[Dict[str, Any]]:
    """Look up trust_scopes for a provider:model_id from model-permissions.yaml.

    Returns None if model not found (defaults to no filtering).
    """
    permissions = _load_permissions()
    model_key = f"{provider}:{model_id}"
    entry = permissions.get(model_key, {})
    return entry.get("trust_scopes")


def audit_filter_context(
    messages: List[Dict[str, Any]],
    provider: str,
    model_id: str,
    *,
    is_native_runtime: bool = False,
) -> List[Dict[str, Any]]:
    """Audit-mode context filtering (BB-501, BB-512).

    Runs the full filtering pipeline but only LOGS what would be filtered.
    Returns the ORIGINAL messages unmodified. This provides visibility into
    filtering behavior before enforcement is enabled.

    Args:
        messages: Original message list (not mutated).
        provider: Resolved provider name.
        model_id: Resolved model ID.
        is_native_runtime: If True, skip audit.

    Returns:
        The original messages (unmodified).
    """
    if is_native_runtime:
        return messages

    trust_scopes = lookup_trust_scopes(provider, model_id)
    context_access = get_context_access(trust_scopes)

    if is_all_full(context_access):
        return messages

    filtered_dimensions = {k: v for k, v in context_access.items() if v != "full"}

    # Run filtering on a copy to compute what would change
    filtered = filter_context(messages, trust_scopes, is_native_runtime=False)

    # Count changes
    original_chars = sum(
        len(m.get("content", "")) for m in messages
        if isinstance(m.get("content"), str)
    )
    filtered_chars = sum(
        len(m.get("content", "")) for m in filtered
        if isinstance(m.get("content"), str)
    )
    chars_removed = original_chars - filtered_chars

    logger.warning(
        "context_filter_audit model=%s:%s dimensions=%s "
        "original_chars=%d filtered_chars=%d chars_removed=%d",
        provider,
        model_id,
        filtered_dimensions,
        original_chars,
        filtered_chars,
        chars_removed,
    )

    # Return ORIGINAL messages unmodified (audit mode)
    return messages
