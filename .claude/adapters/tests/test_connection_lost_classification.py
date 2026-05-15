"""Test ConnectionLostError classification — issue #774.

Reproduces the bug where httpx connection-loss exceptions
(`RemoteProtocolError("Server disconnected without sending a response")`,
`ReadError`, `ConnectError`, `WriteError`, `ProtocolError`, `PoolTimeout`)
fall into the bare `except Exception:` arm in
`loa_cheval/providers/retry.py:223`, producing the operator-misleading
"Unexpected error from anthropic" log line and the proven-ineffective
`--per-call-max-tokens 4096` recommendation in operator-facing strings.

Pre-fix: bare exception arm catches httpx errors generically.
Post-fix: typed `ConnectionLostError` propagates; `cheval.py` surfaces
`failure_class: "PROVIDER_DISCONNECT"` in JSON-error stderr; remediation
hint correctly notes that `--per-call-max-tokens` does not address this
failure mode.

Test strategy: three focused tests, one per layer (transport / retry / CLI).
Mirrors `test_cheval_exception_scoping.py` style for the CLI test.
"""

from __future__ import annotations

import json
import sys
import types
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.types import (
    ConnectionLostError,
    RetriesExhaustedError,
)

# httpx is a runtime dependency of the adapter; the real package is required
# to construct the typed exception classes the test mocks against.
httpx = pytest.importorskip("httpx")

import cheval  # type: ignore[import-not-found]
from loa_cheval.providers import base as providers_base


# ---------------------------------------------------------------------------
# Layer 1 — Transport layer (http_post)
# ---------------------------------------------------------------------------

def test_http_post_classifies_remote_protocol_error_as_connection_lost():
    """`http_post` must catch httpx.RemoteProtocolError and re-raise as
    `ConnectionLostError` carrying provider, transport_class, and
    request_size_bytes. Pre-fix: httpx error propagates bare; post-fix: typed.
    """
    # Force httpx branch (not urllib fallback)
    providers_base._HTTP_CLIENT = "httpx"

    with patch("httpx.post") as mock_post:
        mock_post.side_effect = httpx.RemoteProtocolError(
            "Server disconnected without sending a response"
        )

        with pytest.raises(ConnectionLostError) as exc_info:
            providers_base.http_post(
                url="https://api.anthropic.com/v1/messages",
                headers={"x-api-key": "dummy"},
                body={"model": "claude-opus-4-7", "messages": []},
                connect_timeout=10.0,
                read_timeout=120.0,
            )

    err = exc_info.value
    # Provider is not embedded by http_post (it's transport-layer-agnostic);
    # provider attribution happens at the adapter layer where http_post is
    # called from. http_post sets transport_class + request_size_bytes only.
    assert err.transport_class == "RemoteProtocolError"
    assert err.request_size_bytes is not None and err.request_size_bytes > 0
    assert "Server disconnected" in str(err) or "RemoteProtocolError" in str(err)


def test_http_post_classifies_read_error_as_connection_lost():
    """`http_post` must also classify httpx.ReadError as ConnectionLostError
    (sibling case; same operator-facing failure mode)."""
    providers_base._HTTP_CLIENT = "httpx"

    with patch("httpx.post") as mock_post:
        mock_post.side_effect = httpx.ReadError("read mid-flight")

        with pytest.raises(ConnectionLostError) as exc_info:
            providers_base.http_post(
                url="https://api.openai.com/v1/chat/completions",
                headers={"authorization": "Bearer dummy"},
                body={"model": "gpt-5.5-pro", "messages": []},
            )

    assert exc_info.value.transport_class == "ReadError"


# ---------------------------------------------------------------------------
# Layer 2 — Retry layer (invoke_with_retry)
# ---------------------------------------------------------------------------

def test_retry_propagates_connection_lost_through_retries_exhausted():
    """When `adapter.complete()` raises `ConnectionLostError` repeatedly,
    `invoke_with_retry` must:
    - count it against the retry budget (transient classification)
    - NOT fall into the bare `except Exception:` arm (no "Unexpected error" log)
    - on exhaustion, raise `RetriesExhaustedError` carrying typed metadata
      (`last_error_class` / `last_error_context`) so cheval.py can surface
      `failure_class: PROVIDER_DISCONNECT` in JSON-error output.
    """
    from loa_cheval.providers.retry import invoke_with_retry
    from loa_cheval.types import CompletionRequest

    fake_adapter = MagicMock()
    fake_adapter.provider = "anthropic"
    fake_adapter.auth_type = "http_api"
    fake_adapter.complete.side_effect = ConnectionLostError(
        provider="anthropic",
        transport_class="RemoteProtocolError",
        request_size_bytes=42000,
    )

    request = CompletionRequest(
        messages=[{"role": "user", "content": "test"}],
        model="claude-opus-4-7",
        max_tokens=4096,
    )

    fake_config = {
        "providers": {"anthropic": {"type": "anthropic"}},
        "retry": {"max_retries": 2, "max_total_attempts": 6, "base_delay_seconds": 0.0},
    }

    # Patch circuit-breaker IO + sleep to keep test hermetic and fast
    with patch("loa_cheval.providers.retry._record_failure"), \
         patch("loa_cheval.providers.retry._record_success"), \
         patch("loa_cheval.providers.retry._check_circuit_breaker", return_value="CLOSED"), \
         patch("loa_cheval.providers.retry.time.sleep"):
        with pytest.raises(RetriesExhaustedError) as exc_info:
            invoke_with_retry(
                adapter=fake_adapter,
                request=request,
                config=fake_config,
            )

    err = exc_info.value
    # The typed metadata must be carried on the exception so cheval.py
    # can surface failure_class without parsing strings.
    assert err.context.get("last_error_class") == "ConnectionLostError", (
        f"Expected last_error_class='ConnectionLostError' on the typed "
        f"RetriesExhaustedError context, got context={err.context!r}"
    )
    last_ctx = err.context.get("last_error_context") or {}
    assert last_ctx.get("provider") == "anthropic"
    assert last_ctx.get("transport_class") == "RemoteProtocolError"


# ---------------------------------------------------------------------------
# Layer 3 — CLI layer (cheval.cmd_invoke)
# ---------------------------------------------------------------------------

def _make_args() -> object:
    """Construct a minimal valid argparse.Namespace for cmd_invoke()."""
    args = types.SimpleNamespace()
    args.agent = "flatline-reviewer"
    args.input = None
    args.prompt = "test prompt"
    args.system = None
    args.model = None
    args.max_tokens = 4096
    args.output_format = "text"
    args.json_errors = True
    args.timeout = 30
    args.include_thinking = False
    args.async_mode = False
    args.poll_id = None
    args.cancel_id = None
    args.dry_run = False
    args.print_config = False
    args.validate_bindings = False
    return args


def test_cmd_invoke_emits_failure_class_provider_disconnect(capsys):
    """When invoke_with_retry raises RetriesExhaustedError with typed
    last_error_class='ConnectionLostError', cheval.cmd_invoke must emit a
    JSON error on stderr that includes `failure_class: "PROVIDER_DISCONNECT"`
    plus sanitized typed context (transport_class + request_size_bytes).
    NO request body, headers, or auth values may appear in the output.
    """
    fake_resolved = MagicMock(provider="anthropic", model_id="claude-opus-4-7")
    fake_binding = MagicMock(temperature=0.7)
    fake_provider_cfg = MagicMock()
    fake_adapter = MagicMock()

    fake_config = {
        "providers": {
            "anthropic": {
                "type": "anthropic",
                "endpoint": "https://api.anthropic.com/v1/messages",
                "auth": "dummy",
                "models": {"claude-opus-4-7": {"capabilities": ["chat"], "context_window": 200000}},
            },
        },
        "feature_flags": {"metering": False},
    }

    typed_exhausted = RetriesExhaustedError(
        total_attempts=3,
        last_error="ConnectionLostError: Server disconnected without sending a response",
        last_error_class="ConnectionLostError",
        last_error_context={
            "provider": "anthropic",
            "transport_class": "RemoteProtocolError",
            "request_size_bytes": 42000,
        },
    )

    with patch.object(cheval, "load_config", return_value=(fake_config, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=fake_provider_cfg), \
         patch.object(cheval, "get_adapter", return_value=fake_adapter), \
         patch("loa_cheval.providers.retry.invoke_with_retry") as mock_retry:

        mock_retry.side_effect = typed_exhausted

        args = _make_args()
        exit_code = cheval.cmd_invoke(args)

    captured = capsys.readouterr()

    assert exit_code == cheval.EXIT_CODES["RETRIES_EXHAUSTED"]

    # Find the JSON line on stderr
    json_line = None
    for line in captured.err.splitlines():
        line = line.strip()
        if line.startswith("{") and "RETRIES_EXHAUSTED" in line:
            json_line = line
            break
    assert json_line is not None, (
        f"Expected RETRIES_EXHAUSTED JSON on stderr; stderr was:\n{captured.err}"
    )

    payload = json.loads(json_line)
    assert payload.get("failure_class") == "PROVIDER_DISCONNECT", (
        f"Expected failure_class='PROVIDER_DISCONNECT' in JSON-error stderr, "
        f"got payload={payload!r}"
    )
    # Sanitization: typed-context fields surfaced without sensitive payload
    assert payload.get("transport_class") == "RemoteProtocolError"
    assert payload.get("request_size_bytes") == 42000
    # No raw body/headers/auth
    assert "x-api-key" not in captured.err
    assert "Bearer" not in captured.err


def test_cmd_invoke_does_not_recommend_per_call_max_tokens(capsys):
    """Operator-facing JSON-error output for PROVIDER_DISCONNECT must NOT
    suggest the proven-ineffective `--per-call-max-tokens 4096` remedy
    (cheval.py defaults to 4096 already, so the recommendation was a no-op).
    """
    fake_resolved = MagicMock(provider="anthropic", model_id="claude-opus-4-7")
    fake_binding = MagicMock(temperature=0.7)
    fake_provider_cfg = MagicMock()
    fake_adapter = MagicMock()

    fake_config = {
        "providers": {
            "anthropic": {
                "type": "anthropic",
                "endpoint": "https://api.anthropic.com/v1/messages",
                "auth": "dummy",
                "models": {"claude-opus-4-7": {"capabilities": ["chat"], "context_window": 200000}},
            },
        },
        "feature_flags": {"metering": False},
    }

    typed_exhausted = RetriesExhaustedError(
        total_attempts=3,
        last_error="ConnectionLostError: Server disconnected without sending a response",
        last_error_class="ConnectionLostError",
        last_error_context={
            "provider": "anthropic",
            "transport_class": "RemoteProtocolError",
            "request_size_bytes": 42000,
        },
    )

    with patch.object(cheval, "load_config", return_value=(fake_config, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=fake_provider_cfg), \
         patch.object(cheval, "get_adapter", return_value=fake_adapter), \
         patch("loa_cheval.providers.retry.invoke_with_retry") as mock_retry:

        mock_retry.side_effect = typed_exhausted
        args = _make_args()
        cheval.cmd_invoke(args)

    captured = capsys.readouterr()

    # The misleading recommendation MUST NOT appear in stderr for the
    # PROVIDER_DISCONNECT failure class (cheval.py default already = 4096).
    assert "--per-call-max-tokens 4096" not in captured.err, (
        f"cheval CLI surfaced the proven-ineffective `--per-call-max-tokens 4096` "
        f"recommendation for PROVIDER_DISCONNECT (issue #774). stderr:\n{captured.err}"
    )
