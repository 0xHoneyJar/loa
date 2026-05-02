"""Redaction and sanitization layer (SDD §6.2, Sprint Task 1.9).

Ensures secrets never leak through:
- Exception messages and tracebacks
- HTTP client debug logging
- CLI output (--print-effective-config)
- Error responses
"""

from __future__ import annotations

import logging
import os
import re
import traceback
from typing import Any, Dict, List, Optional, Set

from loa_cheval.types import ChevalError

# Patterns that indicate sensitive values
_SENSITIVE_KEY_PATTERNS = re.compile(
    r"(auth|key|secret|token|password|credential|bearer)",
    re.IGNORECASE,
)

# Known env vars that contain secrets
_SECRET_ENV_VARS = [
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "MOONSHOT_API_KEY",
    "GOOGLE_API_KEY",
    # cycle-096 Sprint 1 Task 1.6 (NFR-Sec2 + NFR-Sec10) — Bedrock
    "AWS_BEARER_TOKEN_BEDROCK",
    "AWS_SECRET_ACCESS_KEY",  # SigV4 v2 path; redact pre-emptively
]

# URL query parameter patterns to redact
_URL_PARAM_PATTERN = re.compile(r"([?&])(api[_-]?key|token|secret|auth)=([^&\s]+)", re.IGNORECASE)

# Authorization header pattern
_AUTH_HEADER_PATTERN = re.compile(r"(Authorization:\s*Bearer\s+)\S+", re.IGNORECASE)
_XAPI_KEY_PATTERN = re.compile(r"(x-api-key:\s*)\S+", re.IGNORECASE)

# cycle-096 Sprint 1 Task 1.6 (NFR-Sec2) — Bedrock API Key prefix.
# Layer 2 (regex) defense — secondary to value-based redaction. Probe-confirmed
# 2026-05-02 the trial token starts ABSKR; safe match uses 4-char prefix to
# accommodate prefix evolution.
_BEDROCK_API_KEY_PATTERN = re.compile(r"ABSK[A-Za-z0-9+/=]{36,}")

# Layer 3 (length fallback) defense — catches base64-shaped strings of plausible
# token length when the regex prefix doesn't match (e.g., AWS evolves prefix).
#
# Cycle-096 NC-1 (review feedback) — original `\b[A-Za-z0-9+/=]{60,}\b` over-
# matched: SHA-256 hex digests (64 chars) and SHA-512 hex digests (128 chars)
# are pure A-F+digits and would trip the regex, redacting legitimate hashes.
#
# Refined pattern requires at least one base64-distinct character (`+`, `/`,
# or `=`) AND a minimum length of 60 chars. Pure-hex strings (which use only
# A-F and digits) pass through; base64-shaped tokens (which use the full
# A-Za-z0-9+/= alphabet) get caught.
_BEDROCK_LENGTH_FALLBACK_PATTERN = re.compile(
    r"\b(?=[A-Za-z0-9+/=]*[+/=])[A-Za-z0-9+/=]{60,}\b"
)

REDACTED = "***REDACTED***"


# cycle-096 Sprint 1 Task 1.6 (NFR-Sec10) — runtime value registry.
# Adapter __init__ calls register_value_redaction() with the resolved auth
# value; subsequent redact_string() calls scrub the literal value regardless
# of regex match. Defense-in-depth over the prefix-based regex.
_REGISTERED_VALUES: Set[str] = set()


def register_value_redaction(value: Optional[str]) -> None:
    """Register a literal secret value for value-based redaction.

    Called by adapter __init__ with the resolved env-var value. Subsequent
    ``redact_string()`` calls replace any occurrence of the literal value
    with ``REDACTED``, regardless of whether the regex pattern matches.

    No-op for None/empty/short values (avoids over-eager redaction of
    arbitrary substrings; Bedrock tokens are >> 8 chars so 16 is safe).
    """
    if not isinstance(value, str) or len(value) < 16:
        return
    _REGISTERED_VALUES.add(value)


def clear_registered_values() -> None:
    """Clear the registered-value set (token-rotation cache invalidation)."""
    _REGISTERED_VALUES.clear()


def redact_string(value: str) -> str:
    """Redact known secret patterns from a string value.

    Layer order (cycle-096 Sprint 1 Task 1.6 / SDD §6.4.1):

    * **Layer 1 (PRIMARY)**: value-based redaction — registered values
      (via :func:`register_value_redaction`) and known-env-var values are
      scrubbed regardless of whether they match a regex. This catches all
      valid token leaks, not just AWS-pattern-matching ones.
    * **Layer 2 (SECONDARY)**: regex match — Authorization/x-api-key headers,
      URL query params, and the Bedrock API Key prefix pattern.
    * **Layer 3 (TERTIARY)**: length-based fallback for base64-shaped strings
      that could be tokens. Intentionally low-precision; false-positive
      redaction is acceptable.

    Both layers fire on every call — neither is sufficient alone.
    """
    result = value

    # Layer 1a — explicitly registered secret values (NFR-Sec10).
    for registered in _REGISTERED_VALUES:
        if registered and registered in result:
            result = result.replace(registered, REDACTED)

    # Layer 1b — known env var values
    for env_var in _SECRET_ENV_VARS:
        env_val = os.environ.get(env_var)
        if env_val and env_val in result:
            result = result.replace(env_val, REDACTED)

    # Layer 1c — LOA_ prefixed vars
    for key, val in os.environ.items():
        if key.startswith("LOA_") and val and len(val) > 8 and val in result:
            result = result.replace(val, REDACTED)

    # Layer 2 — header patterns
    result = _AUTH_HEADER_PATTERN.sub(rf"\1{REDACTED}", result)
    result = _XAPI_KEY_PATTERN.sub(rf"\1{REDACTED}", result)

    # Layer 2 — URL query parameters
    result = _URL_PARAM_PATTERN.sub(rf"\1\2={REDACTED}", result)

    # Layer 2 — Bedrock API Key prefix (NFR-Sec2)
    result = _BEDROCK_API_KEY_PATTERN.sub(REDACTED, result)

    # Layer 3 — length-based fallback (only fires on long base64-shaped
    # strings; conservative threshold avoids false-positive on normal text).
    # We do NOT redact short-but-base64-shaped strings because that would
    # over-redact legitimate IDs / hashes / etc.
    result = _BEDROCK_LENGTH_FALLBACK_PATTERN.sub(REDACTED, result)

    return result


def redact_exception(exc: Exception) -> str:
    """Redact sensitive information from an exception message."""
    return redact_string(str(exc))


def redact_traceback(tb_str: str) -> str:
    """Redact sensitive information from a traceback string."""
    return redact_string(tb_str)


def safe_format_exception(exc: Exception) -> str:
    """Format an exception with redacted traceback for safe stderr output."""
    tb = traceback.format_exception(type(exc), exc, exc.__traceback__)
    full_tb = "".join(tb)
    return redact_traceback(full_tb)


def wrap_provider_error(exc: Exception, provider: str) -> ChevalError:
    """Wrap a raw provider exception with redacted error message.

    Strips auth headers, env var values, and API keys from the error.
    """
    msg = redact_exception(exc)
    return ChevalError(
        code="API_ERROR",
        message=f"Provider '{provider}' error: {msg}",
        retryable=True,
        context={"provider": provider, "original_type": type(exc).__name__},
    )


def configure_http_logging() -> None:
    """Configure HTTP client loggers to prevent auth header leakage.

    Sets httpx and urllib3 loggers to WARNING level to prevent
    debug-level logging of Authorization headers.
    """
    for logger_name in ["httpx", "httpcore", "urllib3", "http.client"]:
        logging.getLogger(logger_name).setLevel(logging.WARNING)


def redact_headers(headers: Dict[str, str]) -> Dict[str, str]:
    """Return a copy of headers with sensitive values redacted."""
    redacted = {}
    for key, value in headers.items():
        if _SENSITIVE_KEY_PATTERNS.search(key):
            redacted[key] = REDACTED
        else:
            redacted[key] = value
    return redacted


def redact_config_value(key: str, value: Any) -> Any:
    """Redact a config value if it appears to be sensitive.

    Handles LazyValue instances without triggering resolution.
    """
    # Handle LazyValue without importing (avoid circular import)
    if hasattr(value, "raw") and hasattr(value, "resolve"):
        return f"{REDACTED} (lazy: {value.raw})"
    if isinstance(value, str):
        # Check if the key name suggests sensitivity
        if _SENSITIVE_KEY_PATTERNS.search(key):
            return REDACTED
        # Check for interpolation tokens (already handled by interpolation.py)
        if "{env:" in value or "{file:" in value:
            return f"{REDACTED} (from {value})"
    elif isinstance(value, dict):
        return {k: redact_config_value(k, v) for k, v in value.items()}
    elif isinstance(value, list):
        return [redact_config_value(key, item) for item in value]
    return value
