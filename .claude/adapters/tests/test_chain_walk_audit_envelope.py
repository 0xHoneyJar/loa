"""cycle-104 Sprint 2 (T2.5 + T2.6 / SDD §5.3) — chain-walk integration.

Pins the cheval.cmd_invoke chain-walk behavior end-to-end:

  1. Primary EmptyContentError → walk to next entry → success on fallback.
     models_failed[0] records primary, models_succeeded records fallback,
     final_model_id + transport reflect the fallback entry.

  2. Every entry returns EmptyContentError → chain exhausted → exit
     CHAIN_EXHAUSTED (12) for multi-entry chains. models_failed[] is in
     walk order.

  3. Single-entry chain that exhausts → preserves cycle-103 exit codes
     (RETRIES_EXHAUSTED / RATE_LIMITED / etc.) — backward compat.

  4. Non-retryable error (BudgetExceededError) → surfaces immediately,
     does NOT walk to next entry.

  5. Capability mismatch on entry → walks, records CAPABILITY_MISS with
     missing_capabilities list.

  6. config_observed records the headless_mode + source on every emit.

These tests run cheval.cmd_invoke() with mocked adapters + provider config.
The MODELINV emit is patched at audit_emit so we can capture the payload
without writing to .run/model-invoke.jsonl.
"""

from __future__ import annotations

import json
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.types import (
    BudgetExceededError,
    CompletionRequest,
    CompletionResult,
    RetriesExhaustedError,
    Usage,
)
from loa_cheval.routing.types import EmptyContentError

import cheval  # type: ignore[import-not-found]


def _make_args() -> object:
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
    args.mock_fixture_dir = None
    args.max_input_tokens = None
    return args


def _multi_entry_config():
    """Two-entry within-company chain: openai gpt-5.5-pro → openai codex-headless."""
    return {
        "aliases": {
            "gpt-5.5-pro": "openai:gpt-5.5-pro",
            "codex-headless": "openai:codex-headless",
        },
        "providers": {
            "openai": {
                "type": "openai",
                "endpoint": "https://api.openai.com/v1",
                "auth": "dummy",
                "models": {
                    "gpt-5.5-pro": {
                        "capabilities": ["chat"],
                        "context_window": 200000,
                        "fallback_chain": ["openai:codex-headless"],
                    },
                    "codex-headless": {
                        "kind": "cli",
                        "capabilities": ["chat"],
                        "context_window": 128000,
                    },
                },
            },
        },
        "feature_flags": {"metering": False},
    }


def _single_entry_config():
    """Single-entry chain — backward-compat path."""
    return {
        "aliases": {"gpt-5.5-pro": "openai:gpt-5.5-pro"},
        "providers": {
            "openai": {
                "type": "openai",
                "endpoint": "https://api.openai.com/v1",
                "auth": "dummy",
                "models": {
                    "gpt-5.5-pro": {
                        "capabilities": ["chat"],
                        "context_window": 200000,
                    },
                },
            },
        },
        "feature_flags": {"metering": False},
    }


def _capture_modelinv():
    captured: dict = {}

    def _fake(level, event, payload, *_a, **_kw):
        captured.update(payload)

    return captured, _fake


def _build_completion_result(model_id: str, provider: str) -> CompletionResult:
    return CompletionResult(
        content="ok",
        model=model_id,
        provider=provider,
        usage=Usage(input_tokens=10, output_tokens=5),
        latency_ms=42,
        tool_calls=None,
        thinking=None,
        metadata={"streaming": True},
    )


# Patch persona loader to skip filesystem read.
@pytest.fixture(autouse=True)
def _no_persona(monkeypatch):
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)


# ----------------------------------------------------------------------------
# Test 1: Primary EmptyContentError → walk to next → success on fallback.
# ----------------------------------------------------------------------------


def test_primary_empty_content_walks_to_fallback(capsys):
    cfg = _multi_entry_config()
    fake_binding = MagicMock(temperature=0.7, capability_class=None)
    fake_resolved = MagicMock(provider="openai", model_id="gpt-5.5-pro")
    fake_provider_cfg = MagicMock()

    # Two adapters: primary raises EmptyContentError, fallback returns result.
    primary_adapter = MagicMock()
    fallback_adapter = MagicMock()
    fallback_result = _build_completion_result("codex-headless", "openai")

    # invoke_with_retry uses the adapter passed in — we just need to side_effect
    # based on which adapter is in play. Easier: side_effect by call count.
    calls = {"n": 0}

    def _retry_side(_adapter, _req, _cfg, budget_hook=None):
        calls["n"] += 1
        if calls["n"] == 1:
            raise EmptyContentError(
                provider="openai", model_id="gpt-5.5-pro",
                reason="content was empty",
            )
        return fallback_result

    captured, fake_emit = _capture_modelinv()

    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=fake_provider_cfg), \
         patch.object(cheval, "get_adapter", side_effect=[primary_adapter, fallback_adapter]), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        exit_code = cheval.cmd_invoke(_make_args())

    out = capsys.readouterr()
    assert exit_code == cheval.EXIT_CODES["SUCCESS"], out.err
    assert calls["n"] == 2, f"Expected 2 dispatches (primary + fallback), got {calls['n']}"

    # MODELINV payload should record both entries.
    assert captured["models_requested"] == [
        "openai:gpt-5.5-pro",
        "openai:codex-headless",
    ]
    assert captured["models_succeeded"] == ["openai:codex-headless"]
    assert len(captured["models_failed"]) == 1
    assert captured["models_failed"][0]["model"] == "openai:gpt-5.5-pro"
    assert captured["models_failed"][0]["provider"] == "openai"
    assert captured["models_failed"][0]["error_class"] == "EMPTY_CONTENT"
    assert captured["final_model_id"] == "openai:codex-headless"
    assert captured["transport"] == "cli"
    assert captured["config_observed"]["headless_mode"] == "prefer-api"
    assert captured["config_observed"]["headless_mode_source"] == "default"


# ----------------------------------------------------------------------------
# Test 2: All entries EmptyContentError → chain exhausted (multi-entry).
# ----------------------------------------------------------------------------


def test_chain_exhausted_when_every_entry_fails(capsys):
    cfg = _multi_entry_config()
    fake_binding = MagicMock(temperature=0.7, capability_class=None)
    fake_resolved = MagicMock(provider="openai", model_id="gpt-5.5-pro")

    def _retry_side(_adapter, _req, _cfg, budget_hook=None):
        raise EmptyContentError(
            provider="openai", model_id=_req.model, reason="empty",
        )

    captured, fake_emit = _capture_modelinv()

    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        exit_code = cheval.cmd_invoke(_make_args())

    out = capsys.readouterr()
    assert exit_code == cheval.EXIT_CODES["CHAIN_EXHAUSTED"], out.err

    # Multi-entry: error JSON code is CHAIN_EXHAUSTED.
    stderr_json = None
    for line in out.err.splitlines():
        line = line.strip()
        if line.startswith("{") and "CHAIN_EXHAUSTED" in line:
            stderr_json = json.loads(line)
            break
    assert stderr_json is not None, out.err
    assert stderr_json["code"] == "CHAIN_EXHAUSTED"
    assert stderr_json["retryable"] is False
    assert stderr_json["models_failed_count"] == 2

    # MODELINV: walk order preserved, no models_succeeded, transport/final null.
    assert [m["model"] for m in captured["models_failed"]] == [
        "openai:gpt-5.5-pro",
        "openai:codex-headless",
    ]
    assert captured["models_succeeded"] == []
    assert "final_model_id" not in captured  # never set on exhaustion
    assert "transport" not in captured


# ----------------------------------------------------------------------------
# Test 3: Single-entry chain preserves cycle-103 exit code.
# ----------------------------------------------------------------------------


def test_single_entry_chain_preserves_legacy_exit_code(capsys):
    """A primary with no fallback declared must surface the original
    cycle-103 exit code (RETRIES_EXHAUSTED), not the new CHAIN_EXHAUSTED."""
    cfg = _single_entry_config()
    fake_binding = MagicMock(temperature=0.7, capability_class=None)
    fake_resolved = MagicMock(provider="openai", model_id="gpt-5.5-pro")

    def _retry_side(_adapter, _req, _cfg, budget_hook=None):
        raise RetriesExhaustedError(
            total_attempts=4,
            last_error="Server disconnected",
        )

    captured, fake_emit = _capture_modelinv()

    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        exit_code = cheval.cmd_invoke(_make_args())

    out = capsys.readouterr()
    assert exit_code == cheval.EXIT_CODES["RETRIES_EXHAUSTED"], out.err

    stderr_json = None
    for line in out.err.splitlines():
        line = line.strip()
        if line.startswith("{") and "RETRIES_EXHAUSTED" in line:
            stderr_json = json.loads(line)
            break
    assert stderr_json is not None, out.err
    assert stderr_json["code"] == "RETRIES_EXHAUSTED"


# ----------------------------------------------------------------------------
# Test 4: BudgetExceededError surfaces immediately (no walk).
# ----------------------------------------------------------------------------


def test_budget_exceeded_does_not_walk(capsys):
    cfg = _multi_entry_config()
    fake_binding = MagicMock(temperature=0.7, capability_class=None)
    fake_resolved = MagicMock(provider="openai", model_id="gpt-5.5-pro")

    calls = {"n": 0}

    def _retry_side(_adapter, _req, _cfg, budget_hook=None):
        calls["n"] += 1
        raise BudgetExceededError(spent=100, limit=50)

    captured, fake_emit = _capture_modelinv()

    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        exit_code = cheval.cmd_invoke(_make_args())

    out = capsys.readouterr()
    assert exit_code == cheval.EXIT_CODES["BUDGET_EXCEEDED"], out.err
    assert calls["n"] == 1, (
        f"BudgetExceededError must NOT walk to next entry; got {calls['n']} dispatches"
    )
    # Only the primary should be in models_failed.
    assert len(captured["models_failed"]) == 1
    assert captured["models_failed"][0]["error_class"] == "BUDGET_EXHAUSTED"


# ----------------------------------------------------------------------------
# Test 5: Capability mismatch records missing_capabilities + walks.
# ----------------------------------------------------------------------------


def test_capability_miss_records_missing_and_walks(capsys, monkeypatch):
    """Force the request to require an unsupported capability on the primary;
    chain should walk to the (also-capability-missing) fallback and exhaust.
    Both models_failed entries carry CAPABILITY_MISS + missing_capabilities."""
    cfg = _multi_entry_config()
    # Strip 'tools' from BOTH entries so requires-tools forces a miss everywhere.
    fake_binding = MagicMock(temperature=0.7, capability_class=None)
    fake_resolved = MagicMock(provider="openai", model_id="gpt-5.5-pro")

    # Inject metadata.requires_capabilities = ["tools"] via patched CompletionRequest.
    # Easier: patch capability_gate.check to return ok=False, missing=("tools",).
    from loa_cheval.routing.types import CapabilityCheckResult

    def _fake_check(_req, entry):
        return CapabilityCheckResult(ok=False, missing=("tools",))

    captured, fake_emit = _capture_modelinv()

    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.routing.capability_gate.check", side_effect=_fake_check), \
         patch("loa_cheval.providers.retry.invoke_with_retry") as _mock_retry, \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        exit_code = cheval.cmd_invoke(_make_args())
        # invoke_with_retry must NEVER be called when every entry skips capability.
        _mock_retry.assert_not_called()

    assert exit_code == cheval.EXIT_CODES["CHAIN_EXHAUSTED"]
    # Both entries recorded as CAPABILITY_MISS with missing list.
    assert len(captured["models_failed"]) == 2
    for item in captured["models_failed"]:
        assert item["error_class"] == "CAPABILITY_MISS"
        assert item["missing_capabilities"] == ["tools"]
