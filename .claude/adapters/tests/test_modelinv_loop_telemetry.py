"""Cycle-114 FR-11 — per-iteration cost telemetry in the MODELINV envelope.

Verifies the env-derived loop_context / loop_iteration fields:
  - helper parses valid env, drops invalid (fail-safe)
  - emit surfaces them when set; omits them when absent (NFR-2 back-compat)
  - the shipped schema admits both fields (additionalProperties: false)
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

from loa_cheval.audit.modelinv import (  # noqa: E402
    _loop_telemetry,
    emit_model_invoke_complete,
)


def test_loop_telemetry_parses_valid_env(monkeypatch):
    monkeypatch.setenv("LOA_LOOP_CONTEXT", "bridge")
    monkeypatch.setenv("LOA_LOOP_ITERATION", "3")
    assert _loop_telemetry() == ("bridge", 3)


def test_loop_telemetry_none_when_absent(monkeypatch):
    monkeypatch.delenv("LOA_LOOP_CONTEXT", raising=False)
    monkeypatch.delenv("LOA_LOOP_ITERATION", raising=False)
    assert _loop_telemetry() == (None, None)


@pytest.mark.parametrize("bad_ctx", ["", "BRIDGE", "review", "nonsense"])
def test_loop_telemetry_drops_invalid_context(monkeypatch, bad_ctx):
    monkeypatch.setenv("LOA_LOOP_CONTEXT", bad_ctx)
    monkeypatch.setenv("LOA_LOOP_ITERATION", "2")
    ctx, it = _loop_telemetry()
    assert ctx is None
    assert it == 2


# "³"/"②" are isdigit()=True but int()-unparseable — the class that crashed the
# pre-fix isdigit() guard (FR-11 review finding 1); they MUST be dropped, not raise.
@pytest.mark.parametrize("bad_iter", ["0", "-1", "abc", "", "1.5", "³", "②"])
def test_loop_telemetry_drops_invalid_iteration(monkeypatch, bad_iter):
    monkeypatch.setenv("LOA_LOOP_CONTEXT", "audit")
    monkeypatch.setenv("LOA_LOOP_ITERATION", bad_iter)
    ctx, it = _loop_telemetry()
    assert ctx == "audit"
    assert it is None


def _emit_capture(monkeypatch):
    monkeypatch.delenv("LOA_FORCE_LEGACY_MODELS", raising=False)
    captured: dict = {}

    def fake_audit_emit(primitive_id, event_type, payload, log_path):
        captured["payload"] = payload

    with patch("loa_cheval.audit_envelope.audit_emit", side_effect=fake_audit_emit):
        emit_model_invoke_complete(
            models_requested=["anthropic:claude-opus-4-8"],
            models_succeeded=["anthropic:claude-opus-4-8"],
            models_failed=[],
            operator_visible_warn=False,
        )
    return captured["payload"]


def test_emit_surfaces_loop_fields_when_env_set(monkeypatch):
    monkeypatch.setenv("LOA_LOOP_CONTEXT", "bridge")
    monkeypatch.setenv("LOA_LOOP_ITERATION", "2")
    payload = _emit_capture(monkeypatch)
    assert payload["loop_context"] == "bridge"
    assert payload["loop_iteration"] == 2


def test_emit_omits_loop_fields_when_env_absent(monkeypatch):
    monkeypatch.delenv("LOA_LOOP_CONTEXT", raising=False)
    monkeypatch.delenv("LOA_LOOP_ITERATION", raising=False)
    payload = _emit_capture(monkeypatch)
    assert "loop_context" not in payload
    assert "loop_iteration" not in payload


def test_payload_schema_admits_loop_fields():
    repo_root = Path(__file__).resolve().parents[3]
    schema_path = (
        repo_root
        / ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json"
    )
    schema = json.loads(schema_path.read_text())
    assert "loop_context" in schema["properties"]
    assert "loop_iteration" in schema["properties"]
    assert schema["properties"]["loop_context"]["enum"] == ["bridge", "audit", "e2e", "spiral"]
    # still optional — not added to required (NFR-2 back-compat)
    assert "loop_context" not in schema["required"]
    assert "loop_iteration" not in schema["required"]
