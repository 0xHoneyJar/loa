"""cycle-109 Sprint 4 T4.7 — MODELINV envelope extensions tests.

Pins the additive contract:

  - chunked_review optional kwarg attaches to MODELINV payload.
  - streaming_recovery optional kwarg attaches to MODELINV payload.
  - Both omitted → payload shape unchanged (backward-compat).
  - Schema declares both as optional inline objects.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.audit.modelinv import emit_model_invoke_complete  # noqa: E402


def _capture_payload():
    captured: dict = {}

    def _fake_emit(level, event, payload, *_args, **_kwargs):
        captured.update(payload)

    return captured, _fake_emit


def _no_redaction_no_gate():
    return (
        patch(
            "loa_cheval.audit.modelinv.redact_payload_strings",
            side_effect=lambda x: x,
        ),
        patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"),
    )


# ---------------------------------------------------------------------------
# Kwarg attachment
# ---------------------------------------------------------------------------


def test_chunked_review_attaches_when_supplied():
    captured, fake = _capture_payload()
    rd, gate = _no_redaction_no_gate()
    snapshot = {
        "chunked": True,
        "chunks_reviewed": 3,
        "chunks_dropped": 0,
        "chunks_with_findings": 2,
        "chunks_aggregated_findings": 5,
        "cross_chunk_pass": False,
    }
    with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
        emit_model_invoke_complete(
            models_requested=["anthropic:claude-opus-4-7"],
            models_succeeded=["anthropic:claude-opus-4-7"],
            models_failed=[],
            operator_visible_warn=False,
            chunked_review=snapshot,
        )
    assert "chunked_review" in captured
    assert captured["chunked_review"]["chunked"] is True
    assert captured["chunked_review"]["chunks_reviewed"] == 3


def test_streaming_recovery_attaches_when_supplied():
    captured, fake = _capture_payload()
    rd, gate = _no_redaction_no_gate()
    sr = {
        "triggered": True,
        "tokens_before_abort": 200,
        "reason": "empty_content_window",
    }
    with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
        emit_model_invoke_complete(
            models_requested=["anthropic:claude-opus-4-7"],
            models_succeeded=[],
            models_failed=[{
                "model": "anthropic:claude-opus-4-7",
                "provider": "anthropic",
                "error_class": "EMPTY_CONTENT",
                "message_redacted": "stream aborted",
            }],
            operator_visible_warn=True,
            streaming_recovery=sr,
        )
    assert "streaming_recovery" in captured
    assert captured["streaming_recovery"]["triggered"] is True
    assert captured["streaming_recovery"]["reason"] == "empty_content_window"


def test_chunked_review_omitted_when_kwarg_absent():
    captured, fake = _capture_payload()
    rd, gate = _no_redaction_no_gate()
    with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
        emit_model_invoke_complete(
            models_requested=["anthropic:claude-opus-4-7"],
            models_succeeded=["anthropic:claude-opus-4-7"],
            models_failed=[],
            operator_visible_warn=False,
        )
    assert "chunked_review" not in captured


def test_streaming_recovery_omitted_when_kwarg_absent():
    captured, fake = _capture_payload()
    rd, gate = _no_redaction_no_gate()
    with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
        emit_model_invoke_complete(
            models_requested=["anthropic:claude-opus-4-7"],
            models_succeeded=["anthropic:claude-opus-4-7"],
            models_failed=[],
            operator_visible_warn=False,
        )
    assert "streaming_recovery" not in captured


# ---------------------------------------------------------------------------
# Schema declares the optional fields
# ---------------------------------------------------------------------------


def test_schema_declares_chunked_review_property():
    schema_path = (
        ROOT.parent.parent
        / ".claude" / "data" / "trajectory-schemas" / "model-events"
        / "model-invoke-complete.payload.schema.json"
    )
    schema = json.loads(schema_path.read_text())
    assert "chunked_review" in schema["properties"]
    cr = schema["properties"]["chunked_review"]
    assert cr["type"] == "object"
    assert "chunked" in cr["required"]


def test_schema_declares_streaming_recovery_property():
    schema_path = (
        ROOT.parent.parent
        / ".claude" / "data" / "trajectory-schemas" / "model-events"
        / "model-invoke-complete.payload.schema.json"
    )
    schema = json.loads(schema_path.read_text())
    assert "streaming_recovery" in schema["properties"]
    sr = schema["properties"]["streaming_recovery"]
    assert sr["type"] == "object"
    assert "triggered" in sr["required"]


def test_schema_chunked_review_not_in_required():
    """The top-level fields chunked_review + streaming_recovery MUST be
    OPTIONAL — adding them to required breaks every legacy emit."""
    schema_path = (
        ROOT.parent.parent
        / ".claude" / "data" / "trajectory-schemas" / "model-events"
        / "model-invoke-complete.payload.schema.json"
    )
    schema = json.loads(schema_path.read_text())
    top_required = schema.get("required", [])
    assert "chunked_review" not in top_required
    assert "streaming_recovery" not in top_required
