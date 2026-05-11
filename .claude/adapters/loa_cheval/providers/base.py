"""Provider adapter base class and HTTP client abstraction (SDD §4.2.3)."""

from __future__ import annotations

import json
import logging
import socket
import sys
import time
from abc import ABC, abstractmethod
from contextlib import contextmanager
from typing import Any, Dict, Iterator, List, Optional, Tuple

from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    ConfigError,
    ConnectionLostError,
    ContextTooLargeError,
    ModelConfig,
    ProviderConfig,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers")

# --- HTTP Client Abstraction ---

_HTTP_CLIENT: Optional[str] = None  # "httpx" | "urllib"
_HTTP2_AVAILABLE: Optional[bool] = None


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


def _detect_http2_available() -> bool:
    """Check whether the h2 package is importable (httpx HTTP/2 prerequisite).

    Cached per-process. The streaming transport (`http_post_stream`) negotiates
    HTTP/2 via ALPN when h2 is present. When h2 is missing, streaming still
    works over HTTP/1.1 — Sprint 4A's 2026-05-11 empirical testing confirmed
    Anthropic/OpenAI/Google all return correct content over HTTP/1.1
    streaming. HTTP/2 is preferred for high-concurrency robustness, not for
    correctness.

    Test-mode override: when `LOA_CHEVAL_FORCE_HTTP2_UNAVAILABLE=1` is set
    AND a pytest marker (`PYTEST_CURRENT_TEST`) is present, returns False
    even if h2 is installed. Used by the AC-4A.3 fallback regression pin.
    """
    global _HTTP2_AVAILABLE
    if _HTTP2_AVAILABLE is not None:
        return _HTTP2_AVAILABLE
    import os
    if (
        os.environ.get("LOA_CHEVAL_FORCE_HTTP2_UNAVAILABLE") == "1"
        and os.environ.get("PYTEST_CURRENT_TEST") is not None
    ):
        _HTTP2_AVAILABLE = False
        return _HTTP2_AVAILABLE
    try:
        import h2  # noqa: F401

        _HTTP2_AVAILABLE = True
    except ImportError:
        _HTTP2_AVAILABLE = False
        logger.warning(
            "h2 not installed — streaming will use HTTP/1.1 "
            "(less robust under high concurrency, but correct). "
            "Install with: pip install httpx[http2]"
        )
    return _HTTP2_AVAILABLE


def _reset_http_client_detection_for_tests() -> None:
    """Reset cached HTTP client + HTTP/2 detection.

    Tests that mock module-level imports must call this to bust the
    per-process cache. NOT for production code paths.
    """
    global _HTTP_CLIENT, _HTTP2_AVAILABLE
    _HTTP_CLIENT = None
    _HTTP2_AVAILABLE = None


# Sprint 4A (cycle-102, AC-4.5e): centralized kill-switch detection.
# Single source of truth — adapters AND audit-emit consume the SAME boolean.
# Closes DISS-001 (Sprint 4A reviewer adversarial finding 2026-05-11): without
# centralization, the 3 adapters used `== "1"` (strict, case-sensitive) while
# `modelinv._streaming_active` used case-insensitive `.lower() in ("1","true","yes")`.
# An operator setting `LOA_CHEVAL_DISABLE_STREAMING=true` would have routed
# through the streaming path while the audit chain recorded `streaming=false`
# — the exact silent-degradation pattern vision-019 M1 was built to detect,
# manifesting in the substrate that audits it.
_STREAMING_KILL_SWITCH_TRUTHY_VALUES = ("1", "true", "yes", "on")


def _streaming_disabled() -> bool:
    """Return True iff the operator has set the streaming kill switch.

    Case-insensitive match against `_STREAMING_KILL_SWITCH_TRUTHY_VALUES`.
    Centralized here so adapters AND `modelinv._streaming_active` consume
    identical semantics — the boolean MUST agree at adapter-call time and
    audit-emit time, otherwise the audit chain records a lie.

    Truthy values: `1`, `true`, `yes`, `on` (case-insensitive). Anything
    else (including unset, empty string, `0`, `false`, `no`, `off`) leaves
    streaming active.
    """
    import os
    val = os.environ.get("LOA_CHEVAL_DISABLE_STREAMING", "").strip().lower()
    return val in _STREAMING_KILL_SWITCH_TRUTHY_VALUES


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
        # Issue #774: classify connection-loss exceptions as ConnectionLostError
        # so the retry layer can route them with provider-aware semantics
        # rather than dropping them into the bare `except Exception:` arm.
        # Sanitization: only the transport class name and request size are
        # attached; raw body, headers, and auth are NEVER carried on the
        # exception (they remain in the local `encoded`/`headers` scope).
        try:
            resp = httpx.post(url, headers=headers, content=encoded, timeout=timeout)
        except (
            httpx.RemoteProtocolError,
            httpx.ReadError,
            httpx.WriteError,
            httpx.ConnectError,
            httpx.PoolTimeout,
            httpx.ProtocolError,
        ) as exc:
            raise ConnectionLostError(
                transport_class=type(exc).__name__,
                request_size_bytes=len(encoded),
                message=f"{type(exc).__name__}: {exc}",
            ) from exc
        return resp.status_code, resp.json()
    else:
        import http.client
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
        except http.client.RemoteDisconnected as e:
            # Issue #774: urllib branch parity with the httpx branch above.
            raise ConnectionLostError(
                transport_class="urllib.RemoteDisconnected",
                request_size_bytes=len(encoded),
                message=f"RemoteDisconnected: {e}",
            ) from e
        except urllib.error.URLError as e:
            # Server-disconnect / connection-reset shapes surface as URLError
            # with reasons like ConnectionResetError, BrokenPipeError, etc.
            reason_repr = repr(e.reason) if hasattr(e, "reason") else str(e)
            disconnect_markers = (
                "ConnectionReset",
                "BrokenPipe",
                "Connection aborted",
                "Server disconnected",
            )
            if any(m in reason_repr for m in disconnect_markers):
                raise ConnectionLostError(
                    transport_class="urllib.URLError",
                    request_size_bytes=len(encoded),
                    message=f"URLError: {reason_repr}",
                ) from e
            return 503, {"error": {"message": "URLError: %s" % e.reason}}
        except socket.timeout:
            return 504, {"error": {"message": "Request timed out"}}


# --- Streaming HTTP transport (Sprint 4A, AC-4.5e structural fix for KF-002 layer 3) ---


class StreamingResponse:
    """Lightweight wrapper around a streaming HTTP response.

    Exposes the two pieces of information adapters need before consuming the
    body: the status code (to short-circuit on 4xx/5xx) and an `iter_bytes()`
    iterator over response chunks. The underlying client lifecycle is managed
    by the `http_post_stream` context manager; do not retain references to a
    StreamingResponse outside the `with` block.
    """

    __slots__ = ("status_code", "http_version", "_iter")

    def __init__(self, status_code: int, http_version: str, byte_iter: Iterator[bytes]):
        self.status_code = status_code
        self.http_version = http_version
        self._iter = byte_iter

    def iter_bytes(self) -> Iterator[bytes]:
        """Yield response body chunks as raw bytes."""
        return self._iter


@contextmanager
def http_post_stream(
    url: str,
    headers: Dict[str, str],
    body: Dict[str, Any],
    connect_timeout: float = 10.0,
    read_timeout: float = 120.0,
) -> Iterator[StreamingResponse]:
    """Stream an HTTP POST response — Sprint 4A structural fix for KF-002 layer 3.

    Context-manager API that mirrors `httpx.Client.stream()`. Usage:

        with http_post_stream(url, headers, body, connect_timeout=10, read_timeout=300) as resp:
            if resp.status_code >= 400:
                ...
            for chunk in resp.iter_bytes():
                ...

    Why streaming exists separately from `http_post`:

    The non-streaming `http_post` blocks until the server emits the entire
    response body. For LLM inference at high input scales (≥30K tokens for
    reasoning models), pre-first-byte wall-clock can exceed 60 seconds.
    Intermediaries (Cloudflare edge, ALBs) observe an idle TCP connection
    and close it, surfacing as `httpx.RemoteProtocolError("Server
    disconnected without sending a response")`. Streaming eliminates this
    failure class by construction — the server begins emitting tokens
    immediately, so the connection is never idle from the intermediary's
    point of view. See `grimoires/loa/known-failures.md` KF-002 layer 3.

    Transport semantics:

    - HTTP/2 is enabled when the `h2` package is importable (detected once
      per process via `_detect_http2_available`). HTTP/1.1 is used as
      fallback when h2 is missing — both protocols pass the streaming
      regression pin (AC-4A.3 R3).
    - Exception classification matches the non-streaming twin: any
      `httpx.{RemoteProtocolError,ReadError,WriteError,ConnectError,
      PoolTimeout,ProtocolError}` raised during request initiation OR while
      consuming the stream is converted to `ConnectionLostError` so the
      retry layer (`retry.py:invoke_with_retry`) routes it with
      provider-aware semantics rather than the bare `except Exception` arm.
    - The urllib fallback path streams via `response.read(CHUNK_SIZE)`
      iteration; HTTP/2 is unavailable on urllib (Python stdlib limit).

    Sanitization: only `type(exc).__name__` and the request-body byte size
    are attached to the raised `ConnectionLostError`. Raw body, headers,
    and auth never escape the local scope.
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

        http2_enabled = _detect_http2_available()
        session = httpx.Client(http2=http2_enabled, timeout=timeout)
        stream_cm = None
        try:
            try:
                stream_cm = session.stream(
                    "POST", url, headers=headers, content=encoded
                )
                resp = stream_cm.__enter__()
            except (
                httpx.RemoteProtocolError,
                httpx.ReadError,
                httpx.WriteError,
                httpx.ConnectError,
                httpx.PoolTimeout,
                httpx.ProtocolError,
            ) as exc:
                raise ConnectionLostError(
                    transport_class=type(exc).__name__,
                    request_size_bytes=len(encoded),
                    message=f"{type(exc).__name__}: {exc}",
                ) from exc

            def _byte_iter() -> Iterator[bytes]:
                try:
                    for chunk in resp.iter_bytes():
                        yield chunk
                except (
                    httpx.RemoteProtocolError,
                    httpx.ReadError,
                    httpx.WriteError,
                    httpx.ConnectError,
                    httpx.PoolTimeout,
                    httpx.ProtocolError,
                ) as exc:
                    raise ConnectionLostError(
                        transport_class=type(exc).__name__,
                        request_size_bytes=len(encoded),
                        message=f"{type(exc).__name__}: {exc}",
                    ) from exc

            yield StreamingResponse(
                status_code=resp.status_code,
                http_version=resp.http_version,
                byte_iter=_byte_iter(),
            )
        finally:
            if stream_cm is not None:
                try:
                    stream_cm.__exit__(None, None, None)
                except Exception:
                    pass
            try:
                session.close()
            except Exception:
                pass
    else:
        # urllib fallback — HTTP/1.1 only, no HTTP/2. Streams via .read(N).
        import http.client
        import urllib.error
        import urllib.request

        req = urllib.request.Request(
            url, data=encoded, headers=headers, method="POST"
        )
        total_timeout = connect_timeout + read_timeout
        try:
            handle = urllib.request.urlopen(req, timeout=total_timeout)
        except urllib.error.HTTPError as e:
            # 4xx/5xx — drain body so callers can still parse the error JSON.
            body_bytes = e.read() if e.fp else b""

            def _err_iter() -> Iterator[bytes]:
                if body_bytes:
                    yield body_bytes

            yield StreamingResponse(
                status_code=e.code,
                http_version="HTTP/1.1",
                byte_iter=_err_iter(),
            )
            return
        except (urllib.error.URLError, http.client.RemoteDisconnected) as exc:
            raise ConnectionLostError(
                transport_class=f"urllib.{type(exc).__name__}",
                request_size_bytes=len(encoded),
                message=f"{type(exc).__name__}: {exc}",
            ) from exc
        except socket.timeout as exc:
            raise ConnectionLostError(
                transport_class="urllib.socket.timeout",
                request_size_bytes=len(encoded),
                message=f"socket.timeout: {exc}",
            ) from exc

        def _stdlib_iter() -> Iterator[bytes]:
            try:
                chunk_size = 8192
                while True:
                    chunk = handle.read(chunk_size)
                    if not chunk:
                        break
                    yield chunk
            except (http.client.RemoteDisconnected, urllib.error.URLError) as exc:
                raise ConnectionLostError(
                    transport_class=f"urllib.{type(exc).__name__}",
                    request_size_bytes=len(encoded),
                    message=f"{type(exc).__name__}: {exc}",
                ) from exc
            finally:
                try:
                    handle.close()
                except Exception:
                    pass

        yield StreamingResponse(
            status_code=getattr(handle, "status", 200),
            http_version="HTTP/1.1",
            byte_iter=_stdlib_iter(),
        )


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
