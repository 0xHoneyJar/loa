"""Sprint 4A — model.invoke.complete `streaming` field test (T4A.5).

Tests the additive `streaming: bool` field added to the MODELINV audit
payload schema by Sprint 4A. Verifies:
  - Default behavior (no kill switch): streaming=True
  - LOA_CHEVAL_DISABLE_STREAMING=1: streaming=False
  - Explicit `streaming=False` argument overrides the env-derived default
  - Schema additionalProperties: false continues to admit the new field
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

HERE = Path(__file__).resolve().parent
ADAPTERS_ROOT = HERE.parent
if str(ADAPTERS_ROOT) not in sys.path:
    sys.path.insert(0, str(ADAPTERS_ROOT))

from loa_cheval.audit.modelinv import (
    _streaming_active,
    emit_model_invoke_complete,
)


def test_streaming_active_default_returns_true(monkeypatch):
    """No env var set → streaming detected as active (Sprint 4A default)."""
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    assert _streaming_active() is True


@pytest.mark.parametrize("kill_value", ["1", "true", "TRUE", "yes", "YES"])
def test_streaming_active_false_when_kill_switch_truthy(monkeypatch, kill_value):
    """LOA_CHEVAL_DISABLE_STREAMING in truthy set → streaming=False."""
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_value)
    assert _streaming_active() is False


@pytest.mark.parametrize("non_kill_value", ["", "0", "false", "no", "anything-else"])
def test_streaming_active_true_when_kill_switch_not_truthy(monkeypatch, non_kill_value):
    """Anything other than the truthy set → streaming stays True."""
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", non_kill_value)
    assert _streaming_active() is True


def test_emit_surfaces_streaming_field_true_by_default(monkeypatch):
    """emit_model_invoke_complete adds streaming:true to payload (default)."""
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)

    captured: dict = {}

    def fake_audit_emit(primitive_id, event_type, payload, log_path):
        captured["primitive_id"] = primitive_id
        captured["event_type"] = event_type
        captured["payload"] = payload

    # The emitter imports audit_emit lazily; patch the import target.
    with patch("loa_cheval.audit_envelope.audit_emit", side_effect=fake_audit_emit):
        emit_model_invoke_complete(
            models_requested=["anthropic:claude-opus-4-7"],
            models_succeeded=["anthropic:claude-opus-4-7"],
            models_failed=[],
            operator_visible_warn=False,
            invocation_latency_ms=1234,
        )

    assert captured["primitive_id"] == "MODELINV"
    assert captured["event_type"] == "model.invoke.complete"
    payload = captured["payload"]
    assert payload["streaming"] is True
    assert payload["kill_switch_active"] is False  # LOA_FORCE_LEGACY_MODELS not set
    assert payload["models_requested"] == ["anthropic:claude-opus-4-7"]


def test_emit_surfaces_streaming_field_false_when_kill_switch_set(monkeypatch):
    """LOA_CHEVAL_DISABLE_STREAMING=1 → streaming:false in payload."""
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    monkeypatch.delenv("LOA_FORCE_LEGACY_MODELS", raising=False)

    captured: dict = {}

    def fake_audit_emit(primitive_id, event_type, payload, log_path):
        captured["payload"] = payload

    with patch("loa_cheval.audit_envelope.audit_emit", side_effect=fake_audit_emit):
        emit_model_invoke_complete(
            models_requested=["openai:gpt-4o-mini"],
            models_succeeded=["openai:gpt-4o-mini"],
            models_failed=[],
            operator_visible_warn=False,
        )

    assert captured["payload"]["streaming"] is False


def test_emit_explicit_streaming_override_takes_precedence(monkeypatch):
    """Explicit `streaming=False` kwarg overrides the env-derived default.

    Useful for tests + dry-run paths that want to pin the field regardless
    of operator env-var state.
    """
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    # Default would emit streaming=True; we override to False.
    captured: dict = {}

    def fake_audit_emit(primitive_id, event_type, payload, log_path):
        captured["payload"] = payload

    with patch("loa_cheval.audit_envelope.audit_emit", side_effect=fake_audit_emit):
        emit_model_invoke_complete(
            models_requested=["google:gemini-2.5-flash"],
            models_succeeded=["google:gemini-2.5-flash"],
            models_failed=[],
            operator_visible_warn=False,
            streaming=False,
        )

    assert captured["payload"]["streaming"] is False


def test_payload_schema_admits_streaming_field():
    """The shipped schema includes `streaming` in properties (Sprint 4A)."""
    # tests/ → adapters/ → .claude/ → repo root
    repo_root = Path(__file__).resolve().parents[3]
    schema_path = (
        repo_root
        / ".claude"
        / "data"
        / "trajectory-schemas"
        / "model-events"
        / "model-invoke-complete.payload.schema.json"
    )
    with open(schema_path) as f:
        schema = json.load(f)

    assert "streaming" in schema["properties"], (
        "Sprint 4A schema bump: payload.properties.streaming must exist"
    )
    assert schema["properties"]["streaming"]["type"] == "boolean"
    # Backwards compat: still NOT in required (additive field).
    assert "streaming" not in schema.get("required", []), (
        "streaming MUST remain optional to preserve backwards compatibility "
        "with audit entries written before Sprint 4A"
    )
