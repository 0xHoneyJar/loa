"""Cycle-108 sprint-2 T2.J — MODELINV pricing_snapshot envelope tests.

SDD §20.9 ATK-A20 closure: the envelope captures pricing at invocation time
so historical pricing changes don't retroactively rewrite cost reports.

Test coverage:
  - Full pricing snapshot (input/output/reasoning/per_task/pricing_mode)
  - Minimal pricing snapshot (input/output only)
  - Required-key gate (missing input_per_mtok → field DROPPED, not emitted)
  - None values coerced/dropped
  - Schema validation still passes with additionalProperties: false
  - Legacy callers (no pricing_snapshot kwarg) → field absent from envelope
"""
from __future__ import annotations

import json
import os
import sys
import types
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".claude" / "adapters"))

from loa_cheval.audit.modelinv import (  # noqa: E402
    emit_model_invoke_complete,
    _reset_writer_version_cache_for_tests,
)


@pytest.fixture(autouse=True)
def _reset_caches(monkeypatch):
    _reset_writer_version_cache_for_tests()
    monkeypatch.delenv("LOA_REPLAY_CONTEXT", raising=False)
    yield
    _reset_writer_version_cache_for_tests()


def _capture_payload(monkeypatch, **kwargs):
    captured = {}

    def _fake_audit_emit(primitive_id, event_type, payload, log_path):
        captured["payload"] = payload

    fake_module = types.ModuleType("loa_cheval.audit_envelope")
    fake_module.audit_emit = _fake_audit_emit
    monkeypatch.setitem(sys.modules, "loa_cheval.audit_envelope", fake_module)
    monkeypatch.delenv("LOA_MODELINV_AUDIT_DISABLE", raising=False)

    emit_model_invoke_complete(
        models_requested=["anthropic:claude-opus-4-7"],
        models_succeeded=["anthropic:claude-opus-4-7"],
        models_failed=[],
        operator_visible_warn=False,
        **kwargs,
    )
    return captured.get("payload")


def test_pricing_snapshot_full(monkeypatch):
    """All five pricing fields present."""
    snapshot = {
        "input_per_mtok": 10_000_000,
        "output_per_mtok": 30_000_000,
        "reasoning_per_mtok": 5_000_000,
        "per_task_micro_usd": 0,
        "pricing_mode": "token",
    }
    payload = _capture_payload(monkeypatch, pricing_snapshot=snapshot)
    assert payload is not None
    assert "pricing_snapshot" in payload
    ps = payload["pricing_snapshot"]
    assert ps["input_per_mtok"] == 10_000_000
    assert ps["output_per_mtok"] == 30_000_000
    assert ps["reasoning_per_mtok"] == 5_000_000
    assert ps["pricing_mode"] == "token"


def test_pricing_snapshot_minimal(monkeypatch):
    """Only required keys (input + output) — schema-valid."""
    snapshot = {"input_per_mtok": 1_750_000, "output_per_mtok": 14_000_000}
    payload = _capture_payload(monkeypatch, pricing_snapshot=snapshot)
    assert payload is not None
    ps = payload["pricing_snapshot"]
    assert ps["input_per_mtok"] == 1_750_000
    assert ps["output_per_mtok"] == 14_000_000
    assert "reasoning_per_mtok" not in ps
    assert "per_task_micro_usd" not in ps
    assert "pricing_mode" not in ps


def test_pricing_snapshot_drops_zero_optional_fields(monkeypatch):
    """Zero values for optional fields are coerced — int(0) is still 0
    so should be emitted (operator could legitimately have $0 pricing).
    """
    snapshot = {
        "input_per_mtok": 0,
        "output_per_mtok": 0,
        "pricing_mode": "task",
    }
    payload = _capture_payload(monkeypatch, pricing_snapshot=snapshot)
    assert payload is not None
    ps = payload["pricing_snapshot"]
    assert ps["input_per_mtok"] == 0
    assert ps["output_per_mtok"] == 0
    assert ps["pricing_mode"] == "task"


def test_pricing_snapshot_missing_required_drops_field(monkeypatch):
    """If a caller passes a snapshot without input_per_mtok, the whole
    pricing_snapshot field is DROPPED from the envelope (schema gate).
    """
    snapshot = {"output_per_mtok": 30_000_000}  # missing input
    payload = _capture_payload(monkeypatch, pricing_snapshot=snapshot)
    assert payload is not None
    assert "pricing_snapshot" not in payload


def test_pricing_snapshot_none_values_filtered(monkeypatch):
    """Explicit None values for optional keys → dropped; required must remain."""
    snapshot = {
        "input_per_mtok": 1000,
        "output_per_mtok": 2000,
        "reasoning_per_mtok": None,
        "per_task_micro_usd": None,
        "pricing_mode": None,
    }
    payload = _capture_payload(monkeypatch, pricing_snapshot=snapshot)
    assert payload is not None
    ps = payload["pricing_snapshot"]
    assert "reasoning_per_mtok" not in ps
    assert "per_task_micro_usd" not in ps
    assert "pricing_mode" not in ps


def test_pricing_snapshot_absent_when_not_passed(monkeypatch):
    """Legacy callers (no pricing_snapshot kwarg) → field is absent."""
    payload = _capture_payload(monkeypatch, role="review")
    assert payload is not None
    assert "pricing_snapshot" not in payload


def test_pricing_snapshot_passes_schema_validation(monkeypatch):
    """Verify additionalProperties: false still holds after T2.J schema bump."""
    try:
        import jsonschema
    except ImportError:
        pytest.skip("jsonschema not installed")

    schema_path = ROOT / ".claude" / "data" / "trajectory-schemas" / "model-events" / "model-invoke-complete.payload.schema.json"
    with schema_path.open() as f:
        schema = json.load(f)

    snapshot = {
        "input_per_mtok": 10_000_000,
        "output_per_mtok": 30_000_000,
        "reasoning_per_mtok": 5_000_000,
        "per_task_micro_usd": 100_000,
        "pricing_mode": "hybrid",
    }
    payload = _capture_payload(monkeypatch, pricing_snapshot=snapshot)
    jsonschema.validate(payload, schema)


def test_pricing_snapshot_rejects_unknown_subkey(monkeypatch):
    """Schema's additionalProperties:false on the nested object rejects unknown keys."""
    try:
        import jsonschema
    except ImportError:
        pytest.skip("jsonschema not installed")

    schema_path = ROOT / ".claude" / "data" / "trajectory-schemas" / "model-events" / "model-invoke-complete.payload.schema.json"
    with schema_path.open() as f:
        schema = json.load(f)

    payload = {
        "models_requested": ["anthropic:claude-opus-4-7"],
        "models_succeeded": ["anthropic:claude-opus-4-7"],
        "models_failed": [],
        "operator_visible_warn": False,
        "pricing_snapshot": {
            "input_per_mtok": 100,
            "output_per_mtok": 200,
            "unknown_key": "should-fail",
        },
    }
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(payload, schema)
