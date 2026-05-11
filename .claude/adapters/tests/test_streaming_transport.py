"""Sprint 4A — Streaming-transport regression pins (AC-4A.1 + AC-4A.2 + AC-4A.3).

Tests `http_post_stream()` in `loa_cheval.providers.base`:

- **R1 (transport pin / AC-4A.1)**: mock httpx.Client.stream → 5-chunk SSE
  stream; assert iterator delivers chunks in order with correct status.
- **R2 (60s-wall regression / AC-4A.2)**: simulate the KF-002 layer 3
  failure mode (`RemoteProtocolError("Server disconnected without sending
  a response")`) on the non-streaming path; assert `ConnectionLostError`
  is raised. On the streaming path with the same simulated server-side
  delay-then-stream, assert the call completes successfully. This is the
  canonical anti-regression pin — without it, layer 3 could re-enter
  silently.
- **R3 (h2-missing fallback / AC-4A.3)**: force `_detect_http2_available`
  to return False; assert http_post_stream still functions (HTTP/1.1
  streaming).

The tests use stdlib `unittest.mock` rather than pytest-httpx so the test
suite has zero new test-time dependencies beyond httpx itself.
"""
from __future__ import annotations

import sys
import os
from contextlib import contextmanager
from typing import Iterator, List
from unittest.mock import MagicMock, patch

import pytest

# Make the adapters package importable
HERE = os.path.dirname(os.path.abspath(__file__))
ADAPTERS_ROOT = os.path.dirname(HERE)
if ADAPTERS_ROOT not in sys.path:
    sys.path.insert(0, ADAPTERS_ROOT)

from loa_cheval.providers import base  # noqa: E402
from loa_cheval.types import ConnectionLostError  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_http_detection_cache():
    """Bust the per-process HTTP client / HTTP/2 detection cache between tests.

    Without this, the first test's `_detect_http2_available()` result is
    cached and subsequent tests (especially R3) see stale state.
    """
    base._reset_http_client_detection_for_tests()
    yield
    base._reset_http_client_detection_for_tests()


# --- Helpers ---


def _make_streamed_response(status_code: int, chunks: List[bytes], http_version: str = "HTTP/2"):
    """Build a MagicMock that quacks like `httpx.Response` in streaming mode."""
    resp = MagicMock()
    resp.status_code = status_code
    resp.http_version = http_version
    resp.iter_bytes = MagicMock(return_value=iter(chunks))
    return resp


@contextmanager
def _mock_stream_ctx(response):
    """Mimic the return value of httpx.Client.stream(...) — a context manager."""
    yield response


# --- R1: transport pin (AC-4A.1) ---


def test_r1_stream_yields_chunks_in_order():
    """5-chunk mock stream → assembled iterator delivers chunks in order with status 200."""
    chunks = [
        b'event: message_start\ndata: {"type":"message_start"}\n\n',
        b'event: content_block_start\ndata: {"index":0}\n\n',
        b'event: content_block_delta\ndata: {"delta":{"text":"Hello"}}\n\n',
        b'event: content_block_delta\ndata: {"delta":{"text":", world"}}\n\n',
        b'event: message_stop\ndata: {"type":"message_stop"}\n\n',
    ]

    mock_response = _make_streamed_response(200, chunks)

    with patch("httpx.Client") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.stream.return_value = _mock_stream_ctx(mock_response)

        with base.http_post_stream(
            "https://example.test/v1/messages",
            headers={"content-type": "application/json"},
            body={"model": "test", "messages": []},
            connect_timeout=10.0,
            read_timeout=300.0,
        ) as resp:
            assert resp.status_code == 200
            assert resp.http_version == "HTTP/2"
            received = list(resp.iter_bytes())

    assert received == chunks
    mock_client.stream.assert_called_once_with(
        "POST",
        "https://example.test/v1/messages",
        headers={"content-type": "application/json"},
        content=b'{"model": "test", "messages": []}',
    )


def test_r1_stream_surfaces_4xx_status_without_raising():
    """4xx response: status_code accessible; body iterator yields the error JSON.

    Adapters route status >= 400 to their typed exception (RateLimitError,
    InvalidInputError, etc.) AFTER reading the body. The transport must
    NOT raise on 4xx.
    """
    err_body = b'{"error":{"message":"invalid_api_key"}}'
    mock_response = _make_streamed_response(401, [err_body])

    with patch("httpx.Client") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.stream.return_value = _mock_stream_ctx(mock_response)

        with base.http_post_stream(
            "https://example.test/v1/messages",
            headers={"content-type": "application/json"},
            body={"x": 1},
            read_timeout=10.0,
        ) as resp:
            assert resp.status_code == 401
            body = b"".join(resp.iter_bytes())

    assert body == err_body


# --- R2: 60s-wall regression pin (AC-4A.2) ---


def test_r2_nonstreaming_raises_on_remote_protocol_error():
    """KF-002 layer 3 baseline: non-streaming http_post raises ConnectionLostError
    when the server closes TCP before sending a response. This pins the
    existing behavior; R2's streaming twin (below) MUST diverge from this.
    """
    import httpx

    body = {"model": "test", "messages": [{"role": "user", "content": "x" * 100_000}]}

    with patch("httpx.post") as mock_post:
        mock_post.side_effect = httpx.RemoteProtocolError(
            "Server disconnected without sending a response"
        )

        with pytest.raises(ConnectionLostError) as exc_info:
            base.http_post(
                "https://api.anthropic.test/v1/messages",
                headers={"x-api-key": "test"},
                body=body,
            )

    err = exc_info.value
    assert err.transport_class == "RemoteProtocolError"
    assert err.request_size_bytes > 100_000


def test_r2_streaming_survives_post_delay_first_byte():
    """KF-002 layer 3 anti-regression: when the server eventually streams
    correct content after a long pre-first-byte wait, http_post_stream
    delivers the chunks.

    We can't simulate a 65-second wall in CI (test would take 65+ seconds).
    Instead, we simulate the structural outcome: the streaming path
    receives valid chunks regardless of pre-first-byte wall time. The
    real-network validation lives in AC-4A.7 integration smoke.
    """
    delayed_chunks = [
        b'event: message_start\ndata: {"type":"message_start"}\n\n',
        b'event: content_block_delta\ndata: {"delta":{"text":"Delayed response"}}\n\n',
        b'event: message_stop\ndata: {}\n\n',
    ]

    mock_response = _make_streamed_response(200, delayed_chunks)

    with patch("httpx.Client") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.stream.return_value = _mock_stream_ctx(mock_response)

        body = {"model": "test", "messages": [{"role": "user", "content": "x" * 100_000}]}

        with base.http_post_stream(
            "https://api.anthropic.test/v1/messages",
            headers={"x-api-key": "test"},
            body=body,
            connect_timeout=10.0,
            read_timeout=300.0,
        ) as resp:
            assert resp.status_code == 200
            received = list(resp.iter_bytes())

    # Streaming path delivered the entire response despite simulated server-side delay.
    assert received == delayed_chunks


@pytest.mark.parametrize(
    "exc_factory,expected_class_name",
    [
        (lambda h: h.RemoteProtocolError("server disconnected mid-stream"), "RemoteProtocolError"),
        (lambda h: h.ReadTimeout("read timed out mid-stream"), "ReadTimeout"),
        (lambda h: h.WriteTimeout("write timed out mid-stream"), "WriteTimeout"),
        (lambda h: h.ConnectTimeout("connect timed out (rare in iter)"), "ConnectTimeout"),
        (lambda h: h.ReadError("read failed mid-stream"), "ReadError"),
        (lambda h: h.WriteError("write failed mid-stream"), "WriteError"),
        (lambda h: h.ConnectError("connect failed mid-stream"), "ConnectError"),
        (lambda h: h.PoolTimeout("pool exhausted mid-stream"), "PoolTimeout"),
    ],
)
def test_streaming_classifies_all_transport_errors_mid_iteration(exc_factory, expected_class_name):
    """Sprint 4A cycle-4 (BB F-001): mid-stream transport exceptions
    must be classified to ConnectionLostError, parity with the
    stream-init path. Cycle-3 BF-003 fix added httpx.TimeoutException
    to the stream-init except block but missed _byte_iter — a
    ReadTimeout mid-iteration escaped raw before this regression pin.
    """
    import httpx

    partial_chunks = [b"event: message_start\ndata: {}\n\n"]

    class _RaisingIterator:
        def __init__(self):
            self._i = 0

        def __iter__(self):
            return self

        def __next__(self):
            if self._i == 0:
                self._i += 1
                return partial_chunks[0]
            raise exc_factory(httpx)

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.http_version = "HTTP/2"
    mock_response.iter_bytes = MagicMock(return_value=_RaisingIterator())

    with patch("httpx.Client") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.stream.return_value = _mock_stream_ctx(mock_response)

        with pytest.raises(ConnectionLostError) as exc_info:
            with base.http_post_stream(
                "https://example.test/v1/messages",
                headers={},
                body={"x": 1},
            ) as resp:
                list(resp.iter_bytes())

    assert exc_info.value.transport_class == expected_class_name


def test_r2_streaming_propagates_connection_loss_during_iteration():
    """If httpx raises RemoteProtocolError mid-stream (network dies after
    some bytes arrive), the iterator wraps it as ConnectionLostError so
    the retry layer routes it correctly.
    """
    import httpx

    partial_chunks = [b'event: message_start\ndata: {}\n\n']

    class _RaisingIterator:
        """Iterator that yields one chunk then raises mid-stream."""
        def __init__(self):
            self._i = 0

        def __iter__(self):
            return self

        def __next__(self):
            if self._i == 0:
                self._i += 1
                return partial_chunks[0]
            raise httpx.RemoteProtocolError("connection lost mid-stream")

    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.http_version = "HTTP/2"
    mock_response.iter_bytes = MagicMock(return_value=_RaisingIterator())

    with patch("httpx.Client") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.stream.return_value = _mock_stream_ctx(mock_response)

        with pytest.raises(ConnectionLostError) as exc_info:
            with base.http_post_stream(
                "https://example.test/v1/messages",
                headers={},
                body={"x": 1},
            ) as resp:
                assert resp.status_code == 200
                # Consume the stream — the second iteration raises.
                list(resp.iter_bytes())

    assert exc_info.value.transport_class == "RemoteProtocolError"


# --- R3: h2-missing fallback (AC-4A.3) ---


def test_r3_streaming_falls_back_to_http11_when_h2_missing(monkeypatch):
    """When `h2` is unavailable, http_post_stream still functions on HTTP/1.1.

    We force `_detect_http2_available` to return False via the test-mode
    env-var (gated behind PYTEST_CURRENT_TEST). httpx.Client must be
    constructed with `http2=False`.
    """
    monkeypatch.setenv("LOA_CHEVAL_FORCE_HTTP2_UNAVAILABLE", "1")
    # PYTEST_CURRENT_TEST is auto-set by pytest, gating the override.

    base._reset_http_client_detection_for_tests()
    assert base._detect_http2_available() is False

    chunks = [b'event: ping\n\n', b'event: done\n\n']
    mock_response = _make_streamed_response(200, chunks, http_version="HTTP/1.1")

    with patch("httpx.Client") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.stream.return_value = _mock_stream_ctx(mock_response)

        with base.http_post_stream(
            "https://example.test/v1/messages",
            headers={},
            body={"x": 1},
        ) as resp:
            assert resp.status_code == 200
            assert resp.http_version == "HTTP/1.1"
            received = list(resp.iter_bytes())

    assert received == chunks
    # Critical assertion: Client was constructed with http2=False.
    call_kwargs = mock_client_cls.call_args.kwargs
    assert call_kwargs.get("http2") is False, (
        f"expected http2=False on Client construction; got {call_kwargs}"
    )


def test_r3_test_mode_override_ignored_outside_pytest(monkeypatch):
    """The h2-unavailable env-var override is gated behind PYTEST_CURRENT_TEST
    so production paths can't be tricked into reporting h2 missing.

    Note: pytest itself sets PYTEST_CURRENT_TEST, so we have to unset it
    inside this test to verify the production path. Restore after.
    """
    monkeypatch.setenv("LOA_CHEVAL_FORCE_HTTP2_UNAVAILABLE", "1")
    monkeypatch.delenv("PYTEST_CURRENT_TEST", raising=False)
    base._reset_http_client_detection_for_tests()

    # Real value depends on whether h2 is installed; we only assert that the
    # override env-var alone (no pytest marker) does NOT force False when h2
    # IS importable. If h2 is genuinely missing in the test env, this test
    # is effectively a no-op (the detector returns False legitimately).
    try:
        import h2  # noqa: F401
        h2_present = True
    except ImportError:
        h2_present = False

    result = base._detect_http2_available()
    if h2_present:
        assert result is True, (
            "env-var override should be ignored outside pytest; "
            "h2 is installed so detector must return True"
        )
    else:
        assert result is False  # Legitimate: h2 not installed.


# --- Exception-class coverage ---


@pytest.mark.parametrize(
    "exc_factory,expected_class_name",
    [
        (lambda h: h.RemoteProtocolError("server disconnected"), "RemoteProtocolError"),
        (lambda h: h.ReadError("read failed"), "ReadError"),
        (lambda h: h.WriteError("write failed"), "WriteError"),
        (lambda h: h.ConnectError("connect failed"), "ConnectError"),
        (lambda h: h.PoolTimeout("pool exhausted"), "PoolTimeout"),
        # Sprint 4A cycle-3 (BF-003): timeout exceptions also map to
        # ConnectionLostError so retry.py routes them via the typed-transient
        # arm. Without this, raw httpx.TimeoutException would leak past the
        # ConnectionLostError taxonomy.
        (lambda h: h.ConnectTimeout("connect timed out"), "ConnectTimeout"),
        (lambda h: h.ReadTimeout("read timed out"), "ReadTimeout"),
        (lambda h: h.WriteTimeout("write timed out"), "WriteTimeout"),
    ],
)
def test_streaming_classifies_all_transport_errors_during_init(exc_factory, expected_class_name):
    """Every transport exception raised on stream-open is classified as
    ConnectionLostError — parity with the non-streaming twin (issue #774).
    """
    import httpx

    with patch("httpx.Client") as mock_client_cls:
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.stream.side_effect = exc_factory(httpx)

        with pytest.raises(ConnectionLostError) as exc_info:
            with base.http_post_stream(
                "https://example.test/v1/messages",
                headers={},
                body={"x": 1},
            ):
                pass

    assert exc_info.value.transport_class == expected_class_name
