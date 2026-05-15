"""cycle-109 Sprint 2 T2.3 — MODELINV v1.3 envelope verdict_quality additive
field tests.

Pins the contract between cheval.cmd_invoke (PRODUCER #1 per SDD §3.2.3
IMP-004) and the MODELINV audit emitter:

  1. ``emit_model_invoke_complete`` accepts a ``verdict_quality`` kwarg
     carrying the validated, status-stamped envelope built by
     ``loa_cheval.verdict.quality.emit_envelope_with_status``.

  2. When supplied, the envelope is attached to the MODELINV payload as
     the ``verdict_quality`` field (per SDD §3.3.1 v1.3 additive shape).

  3. Backward-compat invariant: when the kwarg is omitted, no
     ``verdict_quality`` field appears in the payload — legacy callers
     are unaffected.

  4. Schema additivity: the MODELINV payload schema permits
     ``verdict_quality`` as an optional property. The redaction pass and
     the secret-shape gate run AFTER attachment so credentials inside a
     misbuilt envelope rationale still get scrubbed.

This file pairs with ``test_blocker_risk_classifier.py`` (the input
side) and the bats integration test ``tests/unit/cheval-cmd-invoke-
verdict-quality.bats`` (the end-to-end cmd_invoke path).
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import patch

import pytest  # noqa: F401

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.audit.modelinv import emit_model_invoke_complete  # noqa: E402


def _emitter_capture():
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


def _baseline_envelope_approved():
    """A well-formed APPROVED envelope; producer-side validated."""
    return {
        "status": "APPROVED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": False,
        "voices_planned": 1,
        "voices_succeeded": 1,
        "voices_succeeded_ids": ["claude-opus-4-7"],
        "voices_dropped": [],
        "chain_health": "ok",
        "confidence_floor": "low",
        "rationale": "single-voice cheval invoke; chain_health=ok",
        "single_voice_call": True,
    }


def _baseline_envelope_failed_chain_exhausted():
    return {
        "status": "FAILED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": False,
        "voices_planned": 1,
        "voices_succeeded": 0,
        "voices_succeeded_ids": [],
        "voices_dropped": [
            {
                "voice": "claude-opus-4-7",
                "reason": "ChainExhausted",
                "exit_code": 11,
                "blocker_risk": "high",
                "chain_walk": [
                    "anthropic:claude-opus-4-7",
                    "anthropic:claude-opus-4-6",
                    "anthropic:claude-headless",
                ],
            }
        ],
        "chain_health": "exhausted",
        "confidence_floor": "low",
        "rationale": "single-voice cheval invoke; chain exhausted after 3 entries",
        "single_voice_call": True,
    }


class TestVerdictQualityAttachment:
    def test_verdict_quality_kwarg_attaches_to_payload(self):
        """The verdict_quality envelope is attached verbatim to the MODELINV
        payload when caller supplies it. T2.3 PRODUCER #1 contract."""
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        envelope = _baseline_envelope_approved()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4-7"],
                models_succeeded=["anthropic:claude-opus-4-7"],
                models_failed=[],
                operator_visible_warn=False,
                final_model_id="anthropic:claude-opus-4-7",
                transport="http",
                verdict_quality=envelope,
            )
        assert "verdict_quality" in captured
        # Validate every required field round-trips
        for k in (
            "status", "consensus_outcome", "truncation_waiver_applied",
            "voices_planned", "voices_succeeded", "voices_succeeded_ids",
            "voices_dropped", "chain_health", "confidence_floor", "rationale",
        ):
            assert captured["verdict_quality"][k] == envelope[k], (
                f"field {k!r} did not round-trip: "
                f"got {captured['verdict_quality'].get(k)!r}, "
                f"expected {envelope[k]!r}"
            )

    def test_verdict_quality_omitted_when_kwarg_not_supplied(self):
        """Backward compat: callers that don't pass verdict_quality MUST
        produce a payload without the field (additionalProperties:false
        on the schema is not violated by absent fields)."""
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4-7"],
                models_succeeded=["anthropic:claude-opus-4-7"],
                models_failed=[],
                operator_visible_warn=False,
            )
        assert "verdict_quality" not in captured

    def test_verdict_quality_failed_envelope_attaches_for_chain_exhausted(self):
        """FAILED envelopes (e.g., chain exhausted) MUST flow through the
        same attachment path. SDD §6.2 routes error envelopes through
        emit_envelope_with_status; the emitter does not filter on status."""
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        envelope = _baseline_envelope_failed_chain_exhausted()
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4-7"],
                models_succeeded=[],
                models_failed=[
                    {
                        "model": "anthropic:claude-opus-4-7",
                        "provider": "anthropic",
                        "error_class": "RETRIES_EXHAUSTED",
                        "message_redacted": "all retries failed",
                    }
                ],
                operator_visible_warn=True,
                verdict_quality=envelope,
            )
        assert captured["verdict_quality"]["status"] == "FAILED"
        assert captured["verdict_quality"]["chain_health"] == "exhausted"
        assert len(captured["verdict_quality"]["voices_dropped"]) == 1

    def test_verdict_quality_defensive_copy(self):
        """Emitter MUST NOT mutate the caller's envelope dict. Callers may
        keep references for logging / downstream consumers."""
        captured, fake = _emitter_capture()
        rd, gate = _no_redaction_no_gate()
        envelope = _baseline_envelope_approved()
        envelope_copy = {
            k: (list(v) if isinstance(v, list) else v) for k, v in envelope.items()
        }
        with patch("loa_cheval.audit_envelope.audit_emit", fake), rd, gate:
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4-7"],
                models_succeeded=["anthropic:claude-opus-4-7"],
                models_failed=[],
                operator_visible_warn=False,
                verdict_quality=envelope,
            )
        # Envelope unchanged after emit
        assert envelope == envelope_copy, "emitter mutated caller's envelope"


class TestSchemaAdditivity:
    """Pin that the JSON Schema accepts verdict_quality. This catches the
    case where the impl adds the kwarg + payload field but forgets to bump
    the schema, which would cause the redaction-gate to fail downstream."""

    def test_schema_declares_verdict_quality_property(self):
        import json

        schema_path = (
            Path(__file__).resolve().parents[3]
            / ".claude"
            / "data"
            / "trajectory-schemas"
            / "model-events"
            / "model-invoke-complete.payload.schema.json"
        )
        schema = json.loads(schema_path.read_text())
        assert "verdict_quality" in schema["properties"], (
            "model-invoke-complete.payload.schema.json missing "
            "'verdict_quality' property — additionalProperties:false will "
            "reject envelopes with the new field"
        )

    def test_schema_verdict_quality_is_object_type(self):
        import json

        schema_path = (
            Path(__file__).resolve().parents[3]
            / ".claude"
            / "data"
            / "trajectory-schemas"
            / "model-events"
            / "model-invoke-complete.payload.schema.json"
        )
        schema = json.loads(schema_path.read_text())
        vq = schema["properties"]["verdict_quality"]
        # Either a direct $ref to verdict-quality.schema.json OR a typed
        # inline object. Both are acceptable; downstream tooling validates
        # against the verdict-quality schema separately.
        assert (
            vq.get("type") == "object"
            or "$ref" in vq
        ), (
            "verdict_quality schema must be a typed object or $ref to "
            f"the verdict-quality schema; got {vq!r}"
        )

    def test_schema_verdict_quality_is_optional(self):
        """verdict_quality MUST NOT be added to the top-level `required`
        array — that would break every legacy MODELINV emit path that
        doesn't (yet) carry the envelope."""
        import json

        schema_path = (
            Path(__file__).resolve().parents[3]
            / ".claude"
            / "data"
            / "trajectory-schemas"
            / "model-events"
            / "model-invoke-complete.payload.schema.json"
        )
        schema = json.loads(schema_path.read_text())
        required = schema.get("required", [])
        assert "verdict_quality" not in required, (
            "verdict_quality MUST be optional — adding it to required "
            "breaks every pre-T2.3 caller and every legacy audit-log entry"
        )


class TestVerdictQualitySurvivesRedaction:
    """The redaction pass must not strip the verdict_quality field. NFR-Sec-4
    says rationale text is scrubbed of credentials, but the field itself
    must remain intact."""

    def test_envelope_survives_redact_pass(self):
        """With real redactor + gate, an envelope WITHOUT secrets passes
        through end-to-end."""
        captured: dict = {}

        def _fake_emit(level, event, payload, *_args, **_kwargs):
            captured.update(payload)

        envelope = _baseline_envelope_approved()
        with patch("loa_cheval.audit_envelope.audit_emit", _fake_emit):
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4-7"],
                models_succeeded=["anthropic:claude-opus-4-7"],
                models_failed=[],
                operator_visible_warn=False,
                verdict_quality=envelope,
            )
        assert "verdict_quality" in captured
        # The status field survives byte-identical
        assert captured["verdict_quality"]["status"] == "APPROVED"
