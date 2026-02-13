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
]

# URL query parameter patterns to redact
_URL_PARAM_PATTERN = re.compile(r"([?&])(api[_-]?key|token|secret|auth)=([^&\s]+)", re.IGNORECASE)

# Authorization header pattern
_AUTH_HEADER_PATTERN = re.compile(r"(Authorization:\s*Bearer\s+)\S+", re.IGNORECASE)
_XAPI_KEY_PATTERN = re.compile(r"(x-api-key:\s*)\S+", re.IGNORECASE)

REDACTED = "***REDACTED***"


def redact_string(value: str) -> str:
    """Redact known secret patterns from a string value.

    Replaces:
    - Env var values from known secret env vars
    - Authorization: Bearer headers
    - x-api-key headers
    - URL query parameters (api_key, token, secret, auth)
    """
    result = value

    # Redact known env var values
    for env_var in _SECRET_ENV_VARS:
        env_val = os.environ.get(env_var)
        if env_val and env_val in result:
            result = result.replace(env_val, REDACTED)

    # Also check LOA_ prefixed vars
    for key, val in os.environ.items():
        if key.startswith("LOA_") and val and len(val) > 8 and val in result:
            result = result.replace(val, REDACTED)

    # Redact Authorization headers
    result = _AUTH_HEADER_PATTERN.sub(rf"\1{REDACTED}", result)
    result = _XAPI_KEY_PATTERN.sub(rf"\1{REDACTED}", result)

    # Redact URL query parameters
    result = _URL_PARAM_PATTERN.sub(rf"\1\2={REDACTED}", result)

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
