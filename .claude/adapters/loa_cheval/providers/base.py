"""Provider adapter base class and HTTP client abstraction (SDD §4.2.3)."""

from __future__ import annotations

import json
import logging
import socket
import sys
import time
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional, Tuple

from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    ConfigError,
    ContextTooLargeError,
    ModelConfig,
    ProviderConfig,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers")

# --- HTTP Client Abstraction ---

_HTTP_CLIENT: Optional[str] = None  # "httpx" | "urllib"


def _detect_http_client() -> str:
    """Detect available HTTP client. Prefer httpx, fall back to urllib."""
    global _HTTP_CLIENT
    if _HTTP_CLIENT is not None:
        return _HTTP_CLIENT
    try:
        import httpx  # noqa: F401

        _HTTP_CLIENT = "httpx"
    except ImportError:
        logger.warning(
            "httpx not installed — falling back to urllib.request "
            "(no HTTP/2, no connection pooling, basic timeout handling). "
            "Install with: pip install httpx>=0.24.0"
        )
        _HTTP_CLIENT = "urllib"
    return _HTTP_CLIENT


def http_post(
    url: str,
    headers: Dict[str, str],
    body: Dict[str, Any],
    connect_timeout: float = 10.0,
    read_timeout: float = 120.0,
) -> Tuple[int, Dict[str, Any]]:
    """Send HTTP POST and return (status_code, response_json).

    Uses httpx if available, falls back to urllib.request.
    """
    client = _detect_http_client()
    encoded = json.dumps(body).encode("utf-8")

    if client == "httpx":
        import httpx

        timeout = httpx.Timeout(
            connect=connect_timeout,
            read=read_timeout,
            write=30.0,
            pool=10.0,
        )
        resp = httpx.post(url, headers=headers, content=encoded, timeout=timeout)
        return resp.status_code, resp.json()
    else:
        import urllib.request
        import urllib.error

        req = urllib.request.Request(
            url,
            data=encoded,
            headers=headers,
            method="POST",
        )
        # urllib only supports a single timeout value
        total_timeout = connect_timeout + read_timeout
        try:
            with urllib.request.urlopen(req, timeout=total_timeout) as resp:
                resp_body = resp.read().decode("utf-8")
                return resp.status, json.loads(resp_body)
        except urllib.error.HTTPError as e:
            resp_body = e.read().decode("utf-8") if e.fp else "{}"
            try:
                return e.code, json.loads(resp_body)
            except json.JSONDecodeError:
                return e.code, {"error": {"message": resp_body}}
        except urllib.error.URLError as e:
            return 503, {"error": {"message": "URLError: %s" % e.reason}}
        except socket.timeout:
            return 504, {"error": {"message": "Request timed out"}}


# --- Token Estimation ---


def estimate_tokens(messages: List[Dict[str, Any]]) -> int:
    """Best-effort token estimation (SDD §4.2.4).

    Priority: tiktoken (OpenAI) > heuristic (len/3.5).
    """
    text = ""
    for msg in messages:
        content = msg.get("content", "")
        if isinstance(content, str):
            text += content
        elif isinstance(content, list):
            # Anthropic content blocks
            for block in content:
                if isinstance(block, dict) and "text" in block:
                    text += block["text"]

    try:
        import tiktoken

        enc = tiktoken.get_encoding("cl100k_base")
        return len(enc.encode(text))
    except (ImportError, Exception):
        pass

    # Heuristic: ~3.5 chars per token (conservative for English)
    return int(len(text) / 3.5)


def enforce_context_window(
    request: CompletionRequest,
    model_config: ModelConfig,
) -> CompletionRequest:
    """Check input fits within model context window (SDD §4.2.4).

    Raises ContextTooLargeError if not.
    """
    context_window = model_config.context_window
    reserved_output = request.max_tokens
    available = context_window - reserved_output

    estimated = estimate_tokens(request.messages)
    if estimated > available:
        raise ContextTooLargeError(
            estimated_tokens=estimated,
            available=available,
            context_window=context_window,
        )
    return request


# --- Base Adapter ---


class ProviderAdapter(ABC):
    """Base class for model provider adapters (SDD §4.2.3)."""

    def __init__(self, config: ProviderConfig):
        self.config = config
        self.provider = config.name

    @abstractmethod
    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Send completion request, return normalized result."""

    @abstractmethod
    def validate_config(self) -> List[str]:
        """Validate provider-specific config. Return list of error strings."""

    @abstractmethod
    def health_check(self) -> bool:
        """Quick health probe. Returns True if provider is reachable."""

    def _get_auth_header(self) -> str:
        """Get the resolved auth value from config.

        Handles LazyValue resolution: str(LazyValue) calls resolve() which
        triggers env var lookup via the credential provider chain.

        LazyValue contract: callers should expect ConfigError on any resolution
        failure. All exceptions during str() conversion (KeyError for missing
        env vars, OSError for file-based credentials, ValueError for malformed
        credentials, RuntimeError from provider chains) are caught and wrapped
        in ConfigError with the original exception type for debugging.
        The outer cmd_invoke() handler remains as defense-in-depth.
        """
        auth = self.config.auth
        if auth is None:
            raise ConfigError(
                f"No auth configured for provider '{self.provider}'."
            )
        if not isinstance(auth, str):
            try:
                auth = str(auth)
            except Exception as exc:
                raise ConfigError(
                    f"Failed to resolve API key for provider '{self.provider}' "
                    f"({type(exc).__name__}): {exc}."
                ) from exc
        if not auth or not auth.strip():
            raise ConfigError(
                f"API key is empty for provider '{self.provider}'."
            )
        return auth

    def _get_model_config(self, model_id: str) -> ModelConfig:
        """Look up model config by ID. Returns default if not found."""
        return self.config.models.get(model_id, ModelConfig())
