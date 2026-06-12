"""Provider adapter base class and HTTP client abstraction (SDD §4.2.3)."""

from __future__ import annotations

import json
import logging
import os
import signal
import socket
import subprocess
import sys
import threading
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
    except ImportError as exc:
        _HTTP2_AVAILABLE = False
        # Sprint 4A cycle-3 (BF/F10): include the underlying exception class
        # and message so a broken h2 install (partial install, version
        # conflict, ImportError raised from h2's own dependencies, etc.) is
        # distinguishable from a clean "h2 not installed" state. Production
        # deployments investigating HTTP/1.1 fallback need this diagnostic.
        logger.warning(
            "h2 unavailable (%s: %s) — streaming will use HTTP/1.1 "
            "(less robust under high concurrency, but correct). "
            "Install with: pip install httpx[http2]",
            type(exc).__name__,
            exc,
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
                # Sprint 4A cycle-3 (BF-003): include timeout exceptions in the
                # mapping. httpx.TimeoutException is the parent of
                # {Connect,Read,Write}Timeout; without this entry, a timeout
                # raised during stream-open OR mid-stream iteration would leak
                # as a raw httpx exception bypassing the ConnectionLostError
                # taxonomy that retry.py uses for typed-transient routing.
                httpx.TimeoutException,
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
                    # Sprint 4A cycle-4 (BB F-001): mid-stream timeout
                    # classification. BF-003 / cycle-3 added httpx.TimeoutException
                    # to the stream-INIT except block but missed this _byte_iter
                    # block — a ReadTimeout fired DURING iteration (after the
                    # connection is open and bytes are flowing) escaped raw,
                    # bypassing the ConnectionLostError taxonomy that retry.py
                    # uses for typed-transient routing. Streaming has three
                    # error sites (open / mid / close); the taxonomy MUST cover
                    # all three.
                    httpx.TimeoutException,
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


# -----------------------------------------------------------------------------
# Headless adapter subprocess env helper (closes issues #879 / #880)
# -----------------------------------------------------------------------------

# Auth-class env vars that headless adapters MUST strip from their subprocess
# environment by default. The CLI tools (claude / codex / gemini) prefer their
# OAuth-subscription auth path, but if any of these vars are exported in the
# parent process the CLI falls back to API mode — defeating the headless
# adapter's purpose. Operators who explicitly want API-mode routing through
# the CLI opt in via LOA_HEADLESS_KEEP_API_KEY=1.
#
# Two sub-classes are scrubbed:
#   1. Credential vars — the secret itself (ANTHROPIC_API_KEY, OPENAI_API_KEY,
#      GOOGLE_API_KEY, GEMINI_API_KEY, GOOGLE_APPLICATION_CREDENTIALS).
#   2. Auth-mode-selector vars — flags that flip the CLI's auth strategy
#      off the persisted OAuth subscription path even when no credential
#      is present. For gemini, verified against gemini-cli's
#      `packages/core/src/core/contentGenerator.ts::getAuthTypeFromEnv()`:
#        - GOOGLE_GENAI_USE_GCA=true             → AuthType.LOGIN_WITH_GOOGLE
#        - GOOGLE_GENAI_USE_VERTEXAI=true        → AuthType.USE_VERTEX_AI
#        - GOOGLE_GEMINI_BASE_URL=<url>          → AuthType.GATEWAY
#        - GEMINI_CLI_USE_COMPUTE_ADC=true       → AuthType.COMPUTE_ADC
#      (`CLOUD_SHELL=true` also routes to COMPUTE_ADC but is set by Google
#      Cloud Shell as a legitimate environment signal; scrubbing it would
#      surprise operators running cheval from Cloud Shell, so it stays.)
#      The codex + claude CLIs have no analogous env-var selectors as of
#      2026-05-20 (sprint-bug-173 audit); their auth-mode is selected by
#      CLI flags (claude `--bare`) or by file presence (`~/.codex/auth.json`),
#      not env vars. See KF-013 for the recurring-class taxonomy.
_HEADLESS_STRIPPED_AUTH_VARS: tuple = (
    "ANTHROPIC_API_KEY",
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "GEMINI_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
    "GOOGLE_GENAI_USE_VERTEXAI",
    "GOOGLE_GENAI_USE_GCA",
    "GOOGLE_GEMINI_BASE_URL",
    "GEMINI_CLI_USE_COMPUTE_ADC",
)


def build_headless_subprocess_env(parent_env=None) -> Dict[str, str]:
    """Return an env dict suitable for headless adapter subprocess.run(env=...).

    Default: copy parent env (or os.environ if parent_env is None) and remove
    every entry in `_HEADLESS_STRIPPED_AUTH_VARS` — both the credential
    sub-class (e.g., GOOGLE_API_KEY) and the auth-mode-selector sub-class
    (e.g., GOOGLE_GENAI_USE_VERTEXAI). Operator opt-out via
    `LOA_HEADLESS_KEEP_API_KEY=1` preserves ALL entries verbatim
    (credentials AND mode-selectors — the opt-in is a full env-bypass,
    not credential-only).

    The kwarg is ALWAYS supposed to be passed explicitly by callers — even
    when no key needs stripping. The headless adapter's contract is
    "never inherit subprocess env"; an explicit env= makes the contract
    visible at the call site.

    Closes issues #879 / #880 (and symmetric for codex / gemini).
    """
    import os as _os
    base = dict(parent_env if parent_env is not None else _os.environ)
    keep_opt_in = base.get("LOA_HEADLESS_KEEP_API_KEY", "").strip().lower() in (
        "1", "true", "yes", "on",
    )
    if keep_opt_in:
        return base
    for var in _HEADLESS_STRIPPED_AUTH_VARS:
        base.pop(var, None)
    return base


# --- Headless subprocess with process-group kill (#982 / sprint-bug-196) ----

# Per-stream cap for captured CLI output. Mirrors doctor.py's C2-closure
# rationale: a runaway/malicious CLI flooding stdout must not buffer unbounded
# in memory. 64 MiB comfortably exceeds any legitimate completion payload.
_PGKILL_MAX_BYTES_DEFAULT = 64 * 1024 * 1024


class SubprocessOutputCapExceeded(RuntimeError):
    """A headless CLI exceeded the per-stream output byte cap.

    Sprint-bug-196 iteration-1 (cross-model B2): a capped-but-successful
    CompletedProcess would let a truncated JSONL prefix parse as a valid,
    silently incomplete model answer. Exceeding the cap is a provider
    failure — adapters convert this to ProviderUnavailableError so the
    fallback chain advances. run_subprocess_pgkill kills the process group
    before this propagates.
    """


def _pgkill_stdin_writer(proc: subprocess.Popen, payload: bytes) -> None:
    """Feed pre-encoded `input=` on a side thread so the read loop drains.

    Writing a large prompt (> pipe buffer, ~64 KiB) from the main thread
    before reading would deadlock against a child that writes output while
    consuming stdin. BrokenPipe means the child exited or closed stdin
    early — subprocess.run swallows that too. ValueError covers the
    timeout-path race where run_subprocess_pgkill's finally block closes
    proc.stdin while this thread is mid-write ("I/O operation on closed
    file") — without it the daemon thread dumps a traceback onto our
    stderr, polluting orchestrator diagnostics.

    #1011 delta 1 (salvaged from PR #983, credit @notzerker): the payload
    arrives as BYTES — encoding happens in the MAIN thread so a lone
    surrogate raises UnicodeEncodeError immediately instead of being
    swallowed here as a ValueError subclass, which left stdin open and a
    stdin-reading CLI waiting for EOF until the full ~610s timeout.
    """
    try:
        proc.stdin.write(payload)
        proc.stdin.close()
    except (BrokenPipeError, OSError, ValueError):
        pass


def _pgkill_capture(
    proc: subprocess.Popen,
    *,
    max_bytes: int,
    timeout_s: float,
) -> Tuple[bytes, bytes, int]:
    """Read stdout + stderr with byte-cap and deadline — NEVER proc.communicate().

    Port of doctor.py's _capture_with_byte_cap (cycle-110 C2 closure) to the
    completion path. communicate() blocks until the pipe write-ends close,
    which includes any grandchild that inherited them — exactly the #982
    unbounded-hang mechanism.

    Raises:
        subprocess.TimeoutExpired: on deadline exceed, or when both pipes are
            closed but the child (or a pipe-holding descendant) is still
            running. The caller kills the process group.
    """
    import select

    deadline = time.monotonic() + timeout_s
    stdout_buf = bytearray()
    stderr_buf = bytearray()
    stdout_fd = proc.stdout.fileno() if proc.stdout else -1
    stderr_fd = proc.stderr.fileno() if proc.stderr else -1
    open_fds = [fd for fd in (stdout_fd, stderr_fd) if fd >= 0]

    while open_fds:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            # #1011 delta 3: carry partial output — stderr often holds the
            # CLI's throttle/error message (diagnostics, MODELINV later).
            raise subprocess.TimeoutExpired(
                proc.args, timeout_s,
                output=bytes(stdout_buf), stderr=bytes(stderr_buf),
            )
        readable, _, _ = select.select(open_fds, [], [], remaining)
        if not readable:
            raise subprocess.TimeoutExpired(
                proc.args, timeout_s,
                output=bytes(stdout_buf), stderr=bytes(stderr_buf),
            )
        for fd in readable:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                chunk = b""
            if not chunk:
                open_fds.remove(fd)
                continue
            if fd == stdout_fd:
                if len(stdout_buf) + len(chunk) > max_bytes:
                    # Iter-1 B2: never return truncated output as success —
                    # the caller kills the process group, adapters convert
                    # to ProviderUnavailableError (chain advances).
                    raise SubprocessOutputCapExceeded(
                        f"stdout exceeded the {max_bytes}-byte cap"
                    )
                stdout_buf.extend(chunk)
            elif fd == stderr_fd:
                if len(stderr_buf) + len(chunk) > max_bytes:
                    raise SubprocessOutputCapExceeded(
                        f"stderr exceeded the {max_bytes}-byte cap"
                    )
                stderr_buf.extend(chunk)
    if proc.poll() is None:
        # Pipes closed, child still alive — bounded wait, then treat as
        # timeout so the caller performs the process-group kill (doctor.py
        # BB iter-1 #907 F-001 closure).
        try:
            proc.wait(timeout=max(0.1, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            raise
    rc = proc.returncode
    if rc is None:
        raise subprocess.TimeoutExpired(
            proc.args, timeout_s,
            output=bytes(stdout_buf), stderr=bytes(stderr_buf),
        )
    return bytes(stdout_buf), bytes(stderr_buf), rc


def run_subprocess_pgkill(
    cmd: List[str],
    *,
    input: Optional[str] = None,
    timeout: float,
    env: Optional[Dict[str, str]] = None,
    max_bytes: int = _PGKILL_MAX_BYTES_DEFAULT,
) -> subprocess.CompletedProcess:
    """Drop-in for subprocess.run(capture_output=True, text=True) that kills
    the WHOLE process tree on timeout.

    Closes #982: subprocess.run's timeout path kills only the immediate
    child. An agentic CLI's grandchildren (1) survive as orphans, still
    consuming the rate-limited subscription, and (2) hold the inherited
    stdout/stderr write-ends, so run()'s post-kill communicate() drain blocks
    until they exit — the observed unbounded hang with no fallback-chain
    advance. doctor.py shipped the correct pattern (cycle-110) on the
    health-probe path only; this is that pattern as a shared completion-path
    helper.

    Contract parity with the subprocess.run call shape it replaces:
    returns CompletedProcess[str]; raises subprocess.TimeoutExpired on
    deadline (after SIGKILLing the process group) and FileNotFoundError when
    cmd[0] is absent; `input=` is fed without large-prompt deadlock; stdin is
    DEVNULL when `input=` is not given. Divergence from subprocess.run:
    output beyond max_bytes raises SubprocessOutputCapExceeded (group killed
    first) instead of buffering unbounded — truncated output must never
    masquerade as a successful completion.

    Known limitation (shared with doctor.py's probe path): killpg reaps only
    descendants that remain in the child's process group. A CLI that
    double-forks + setsid escapes the group and survives — acceptable for
    the known agentic CLIs, which do not daemonize their workers.
    """
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        # The child leads its own process group so one killpg reaps the
        # entire CLI tree (start_new_session ⇒ setsid in the child).
        start_new_session=True,
        bufsize=0,
        close_fds=True,
        env=env,
    )
    try:
        if input is not None:
            # #1011 delta 1: encode HERE (main thread) — UnicodeEncodeError
            # propagates through the except-BaseException teardown below,
            # reaping the just-spawned child instead of burning the timeout.
            payload = input.encode("utf-8")
            threading.Thread(
                target=_pgkill_stdin_writer, args=(proc, payload), daemon=True
            ).start()
        stdout_b, stderr_b, rc = _pgkill_capture(
            proc, max_bytes=max_bytes, timeout_s=timeout
        )
    except BaseException:
        # Every post-Popen failure — deadline, injected error, KeyboardInterrupt —
        # tears down the process group. ProcessLookupError-safe (C6 pattern).
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        except PermissionError:
            # #1011 delta 2: EPERM (e.g. a setuid descendant joined the
            # group) must not replace the in-flight exception — fall back
            # to killing the direct child.
            try:
                proc.kill()
            except ProcessLookupError:
                pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        raise
    finally:
        for stream in (proc.stdout, proc.stderr, proc.stdin):
            if stream:
                try:
                    stream.close()
                except OSError:
                    pass
    return subprocess.CompletedProcess(
        cmd,
        rc,
        stdout_b.decode("utf-8", errors="replace"),
        stderr_b.decode("utf-8", errors="replace"),
    )


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
    """Base class for model provider adapters (SDD §4.2.3).

    Cycle-110 sprint-2b2a: `auth_type` class attribute declares which
    auth_type bucket this adapter's circuit-breaker writes route to
    (per FR-2.3 / SDD §3.2). Subclasses override:

    | Adapter                       | auth_type   |
    |-------------------------------|-------------|
    | OpenAIAdapter / GoogleAdapter | "http_api"  |
    | AnthropicAdapter              | "http_api"  |
    | BedrockAdapter                | "aws_iam"   |
    | ClaudeHeadlessAdapter         | "headless"  |
    | CodexHeadlessAdapter          | "headless"  |
    | GeminiHeadlessAdapter         | "headless"  |

    Eliminates the sprint-1 `getattr(adapter, "auth_type", "http_api")` fallback
    (closes BB #903 F-001 + F7 fully — adapter labels itself at construction).
    """

    # Default — overridden by subclasses. The default itself is informational:
    # any concrete HTTP-API adapter inherits this; bedrock + headless override.
    auth_type: str = "http_api"

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
