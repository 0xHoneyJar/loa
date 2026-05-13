"""Cycle-108 sprint-1 T1.F — MODELINV v1.2 envelope tests.

Validates the envelope additive bump for advisor-strategy fields:
  - role, tier, tier_source, tier_resolution, sprint_kind
  - writer_version (from SoT file)
  - invocation_chain
  - replay_marker (env-controlled)

Backward-compat property: omitting all new args produces a v1.1-shape
envelope (only writer_version + the existing fields appear).
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".claude" / "adapters"))

from loa_cheval.audit.modelinv import (  # noqa: E402
    emit_model_invoke_complete,
    _read_writer_version,
    _reset_writer_version_cache_for_tests,
)


@pytest.fixture(autouse=True)
def _reset_caches(monkeypatch):
    _reset_writer_version_cache_for_tests()
    # Disable audit_emit side effects to keep tests hermetic
    monkeypatch.setenv("LOA_MODELINV_AUDIT_DISABLE", "1")
    monkeypatch.delenv("LOA_REPLAY_CONTEXT", raising=False)
    yield
    _reset_writer_version_cache_for_tests()


# --- writer_version SoT ------------------------------------------------------

def test_writer_version_reads_from_sot_file():
    """SoT file exists and reads cleanly."""
    version = _read_writer_version()
    assert version == "1.2"


def test_writer_version_is_cached():
    """Reads twice; second read uses cache."""
    v1 = _read_writer_version()
    v2 = _read_writer_version()
    assert v1 == v2 == "1.2"


# --- v1.2 envelope shape -----------------------------------------------------

def _capture_payload(monkeypatch, **kwargs):
    """Helper: run emit_model_invoke_complete and capture the payload pre-emit.

    Uses LOA_MODELINV_AUDIT_DISABLE=1 to skip the audit_emit, but we need to
    inspect the payload itself. We patch audit_emit to intercept.
    """
    captured = {}

    def _fake_audit_emit(primitive_id, event_type, payload, log_path):
        captured["primitive_id"] = primitive_id
        captured["event_type"] = event_type
        captured["payload"] = payload
        captured["log_path"] = log_path

    # Patch the import inside emit_model_invoke_complete by temporarily
    # injecting a fake audit_envelope module.
    import types
    fake_module = types.ModuleType("loa_cheval.audit_envelope")
    fake_module.audit_emit = _fake_audit_emit
    monkeypatch.setitem(sys.modules, "loa_cheval.audit_envelope", fake_module)

    # Re-enable audit_emit so our fake gets called
    monkeypatch.delenv("LOA_MODELINV_AUDIT_DISABLE", raising=False)

    emit_model_invoke_complete(
        models_requested=["anthropic:claude-opus-4-7"],
        models_succeeded=["anthropic:claude-opus-4-7"],
        models_failed=[],
        operator_visible_warn=False,
        **kwargs,
    )
    return captured.get("payload")


def test_v12_envelope_with_all_advisor_fields(monkeypatch):
    """Full v1.2 envelope: every advisor-strategy field populated."""
    payload = _capture_payload(
        monkeypatch,
        role="implementation",
        tier="executor",
        tier_source="per_skill_override",
        tier_resolution="static:abc123def456",
        sprint_kind="glue",
        invocation_chain=["implement", "run-sprint-plan"],
    )
    assert payload is not None
    assert payload["role"] == "implementation"
    assert payload["tier"] == "executor"
    assert payload["tier_source"] == "per_skill_override"
    assert payload["tier_resolution"] == "static:abc123def456"
    assert payload["sprint_kind"] == "glue"
    assert payload["invocation_chain"] == ["implement", "run-sprint-plan"]
    assert payload["writer_version"] == "1.2"


def test_v11_legacy_envelope_when_no_advisor_fields(monkeypatch):
    """Backward-compat: omitting all new args produces v1.1-shape payload
    (only writer_version is unconditionally added)."""
    payload = _capture_payload(monkeypatch)
    assert payload is not None
    # Existing v1.1 fields present
    assert "models_requested" in payload
    assert "models_succeeded" in payload
    assert "models_failed" in payload
    assert "operator_visible_warn" in payload
    # New v1.2 fields ABSENT (they're truly optional)
    assert "role" not in payload
    assert "tier" not in payload
    assert "tier_source" not in payload
    assert "tier_resolution" not in payload
    assert "sprint_kind" not in payload
    assert "invocation_chain" not in payload
    # writer_version IS present (unconditional cycle-108+ marker)
    assert payload["writer_version"] == "1.2"


def test_partial_v12_envelope(monkeypatch):
    """Only some advisor fields populated — the rest stay absent."""
    payload = _capture_payload(
        monkeypatch,
        role="review",
        tier="advisor",
    )
    assert payload is not None
    assert payload["role"] == "review"
    assert payload["tier"] == "advisor"
    # Other advisor fields NOT in payload (no None defaults)
    assert "tier_source" not in payload
    assert "tier_resolution" not in payload
    assert "sprint_kind" not in payload
    assert "invocation_chain" not in payload


def test_replay_marker_from_env(monkeypatch):
    """LOA_REPLAY_CONTEXT=1 adds replay_marker:true to the envelope."""
    monkeypatch.setenv("LOA_REPLAY_CONTEXT", "1")
    payload = _capture_payload(monkeypatch, role="implementation")
    assert payload is not None
    assert payload.get("replay_marker") is True


def test_replay_marker_absent_when_env_unset(monkeypatch):
    """Without LOA_REPLAY_CONTEXT, replay_marker is absent from envelope."""
    monkeypatch.delenv("LOA_REPLAY_CONTEXT", raising=False)
    payload = _capture_payload(monkeypatch, role="implementation")
    assert payload is not None
    assert "replay_marker" not in payload


# --- Schema conformance (additionalProperties: false stays satisfied) --------

def test_v12_payload_passes_schema_validation(monkeypatch):
    """Validate captured v1.2 payload against the (extended) schema."""
    try:
        import jsonschema
    except ImportError:
        pytest.skip("jsonschema not installed")

    schema_path = ROOT / ".claude" / "data" / "trajectory-schemas" / "model-events" / "model-invoke-complete.payload.schema.json"
    with schema_path.open() as f:
        schema = json.load(f)

    payload = _capture_payload(
        monkeypatch,
        role="implementation",
        tier="executor",
        tier_source="per_skill_override",
        tier_resolution="static:1234abcd",
        sprint_kind="testing",
        invocation_chain=["implement"],
    )
    # additionalProperties:false means undeclared fields would fail.
    # If we get here without error, all new fields are properly declared.
    jsonschema.validate(payload, schema)


def test_v11_legacy_payload_passes_schema_validation(monkeypatch):
    """Legacy v1.1-shape payload (with cycle-108's unconditional writer_version)
    still validates."""
    try:
        import jsonschema
    except ImportError:
        pytest.skip("jsonschema not installed")

    schema_path = ROOT / ".claude" / "data" / "trajectory-schemas" / "model-events" / "model-invoke-complete.payload.schema.json"
    with schema_path.open() as f:
        schema = json.load(f)

    payload = _capture_payload(monkeypatch)
    jsonschema.validate(payload, schema)
