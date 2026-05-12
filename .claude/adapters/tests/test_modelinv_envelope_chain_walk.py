"""cycle-104 Sprint 2 (T2.6 / SDD §3.4) — MODELINV v1.1 envelope shape.

Pins the chain-walk audit-envelope contract:

  1. `final_model_id` is present + valid `provider:model_id` when chain succeeds.
  2. `transport` is `"http"` or `"cli"` matching the final entry's `adapter_kind`.
  3. `config_observed` carries the observed `headless_mode` and its source
     (`env` / `config` / `default`).
  4. `models_failed[]` items can carry the additive `provider` and
     `missing_capabilities` fields without breaking schema validation.
  5. Backward compat: single-model emitters that don't supply the new args
     produce a payload byte-identical to cycle-103 output.

These tests run the emitter in isolation (no real adapter). The chain-walk
audit-envelope integration test (test_chain_walk_audit_envelope.py) covers
the cheval.cmd_invoke side.
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.audit.modelinv import emit_model_invoke_complete  # noqa: E402


def _emitter_capture():
    """Patch audit_emit and capture the payload that would be persisted."""
    captured: dict = {}

    def _fake_emit(level, event, payload, *_args, **_kwargs):
        captured.update(payload)

    return captured, _fake_emit


def _no_redaction_no_gate():
    """Bypass redactor + gate so we can assert on the raw payload shape."""
    return (
        patch(
            "loa_cheval.audit.modelinv.redact_payload_strings",
            side_effect=lambda x: x,
        ),
        patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"),
    )


class TestFinalModelIdField:
    def test_final_model_id_present_when_provided(self):
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=[
                    "openai:gpt-5.5-pro",
                    "openai:gpt-5.3-codex",
                ],
                models_succeeded=["openai:gpt-5.3-codex"],
                models_failed=[{
                    "model": "openai:gpt-5.5-pro",
                    "provider": "openai",
                    "error_class": "EMPTY_CONTENT",
                    "message_redacted": "empty content",
                }],
                operator_visible_warn=False,
                final_model_id="openai:gpt-5.3-codex",
                transport="http",
            )
        assert captured["final_model_id"] == "openai:gpt-5.3-codex"

    def test_final_model_id_absent_when_not_supplied(self):
        """Backward compat — single-model emitters that don't pass the new
        kwarg produce a payload without the `final_model_id` key."""
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4-7"],
                models_succeeded=["anthropic:claude-opus-4-7"],
                models_failed=[],
                operator_visible_warn=False,
            )
        assert "final_model_id" not in captured


class TestTransportField:
    def test_transport_http_accepted(self):
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["openai:gpt-5.5-pro"],
                models_succeeded=["openai:gpt-5.5-pro"],
                models_failed=[],
                operator_visible_warn=False,
                final_model_id="openai:gpt-5.5-pro",
                transport="http",
            )
        assert captured["transport"] == "http"

    def test_transport_cli_accepted(self):
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["openai:codex-headless"],
                models_succeeded=["openai:codex-headless"],
                models_failed=[],
                operator_visible_warn=False,
                final_model_id="openai:codex-headless",
                transport="cli",
            )
        assert captured["transport"] == "cli"

    def test_invalid_transport_value_rejected(self):
        """Defensive: emitter refuses an unknown transport literal."""
        rd, gate = _no_redaction_no_gate()
        with patch(
            "loa_cheval.audit_envelope.audit_emit",
            side_effect=AssertionError("should not be called"),
        ), rd, gate:
            with pytest.raises(ValueError) as exc:
                emit_model_invoke_complete(
                    models_requested=["openai:gpt-5.5-pro"],
                    models_succeeded=["openai:gpt-5.5-pro"],
                    models_failed=[],
                    operator_visible_warn=False,
                    transport="grpc",  # unknown
                )
            assert "transport" in str(exc.value)


class TestConfigObservedField:
    def test_config_observed_round_trips(self):
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["openai:gpt-5.5-pro"],
                models_succeeded=["openai:gpt-5.5-pro"],
                models_failed=[],
                operator_visible_warn=False,
                config_observed={
                    "headless_mode": "prefer-api",
                    "headless_mode_source": "config",
                },
            )
        assert captured["config_observed"] == {
            "headless_mode": "prefer-api",
            "headless_mode_source": "config",
        }

    def test_config_observed_absent_when_not_supplied(self):
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4-7"],
                models_succeeded=["anthropic:claude-opus-4-7"],
                models_failed=[],
                operator_visible_warn=False,
            )
        assert "config_observed" not in captured


class TestModelsFailedAdditiveFields:
    def test_provider_and_missing_capabilities_pass_through(self):
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=[
                    "openai:gpt-5.5-pro",
                    "openai:codex-headless",
                ],
                models_succeeded=[],
                models_failed=[
                    {
                        "model": "openai:codex-headless",
                        "provider": "openai",
                        "error_class": "CAPABILITY_MISS",
                        "message_redacted": "missing capabilities: ['tools']",
                        "missing_capabilities": ["tools"],
                    },
                ],
                operator_visible_warn=False,
            )
        assert len(captured["models_failed"]) == 1
        item = captured["models_failed"][0]
        assert item["provider"] == "openai"
        assert item["missing_capabilities"] == ["tools"]
        assert item["error_class"] == "CAPABILITY_MISS"


class TestBackwardCompatSingleModel:
    """Pre-T2.6 single-model emitters produce identical payloads (the new
    fields are absent, not null). Catches a regression where someone might
    "helpfully" default the new fields to a non-None value.
    """

    def test_legacy_single_model_payload_keys(self):
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4-7"],
                models_succeeded=["anthropic:claude-opus-4-7"],
                models_failed=[],
                operator_visible_warn=False,
                invocation_latency_ms=1234,
            )
        # Required + retained cycle-103 fields present
        assert set(captured.keys()) >= {
            "models_requested",
            "models_succeeded",
            "models_failed",
            "operator_visible_warn",
            "kill_switch_active",
            "streaming",
            "invocation_latency_ms",
        }
        # cycle-104 additive fields ABSENT (not null)
        assert "final_model_id" not in captured
        assert "transport" not in captured
        assert "config_observed" not in captured
