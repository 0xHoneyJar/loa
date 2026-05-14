"""cycle-109 Sprint 2 T2.2 — verdict-quality classifier (SDD §3.2.2).

Tests for `loa_cheval.verdict.quality.compute_verdict_status` (the sole
canonical writer of `verdict_quality.status`) and `validate_invariants`
(pre-classification cross-field checks per v5 SKP-005 closure).

Per SDD §3.2.2 the classification table:

  APPROVED:
    voices_succeeded == voices_planned
    AND chain_health == "ok"
    AND consensus_outcome == "consensus"
    AND every voices_dropped[].blocker_risk ∈ {unknown, low}
    AND chunks_dropped == 0

  DEGRADED:
    0 < voices_succeeded < voices_planned
    AND remaining voices reached consensus (consensus_outcome == "consensus")
    AND no dropped voice carries blocker_risk = high
    AND chunks_dropped == 0

  FAILED (auto-promotion — any of):
    voices_succeeded == 0
    OR chain_health == "exhausted"
    OR consensus_outcome == "impossible"
    OR any voices_dropped[].blocker_risk == "high"
    OR chunks_dropped > 0 (unless truncation_waiver_applied == true,
                            which is v5 SKP-001 break-glass per §4.1.3)
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _baseline_envelope(**overrides):
    """Well-formed APPROVED envelope; per-test overrides mutate fields."""
    env = {
        "status": "PLACEHOLDER",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": False,
        "voices_planned": 3,
        "voices_succeeded": 3,
        "voices_succeeded_ids": ["opus", "gpt-5.5-pro", "gemini-3.1-pro"],
        "voices_dropped": [],
        "chain_health": "ok",
        "confidence_floor": "high",
        "rationale": "All 3 voices succeeded; consensus reached",
    }
    env.update(overrides)
    return env


def _dropped(voice, reason="EmptyContent", exit_code=1, blocker_risk="unknown"):
    return {
        "voice": voice,
        "reason": reason,
        "exit_code": exit_code,
        "blocker_risk": blocker_risk,
    }


# ---------------------------------------------------------------------------
# APPROVED conditions (SDD §3.2.2 row 1)
# ---------------------------------------------------------------------------


class TestAPPROVED:
    def test_all_voices_succeeded_consensus_chain_ok_no_drops(self):
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope()
        assert compute_verdict_status(env) == "APPROVED"

    def test_voices_dropped_with_blocker_risk_low_still_approves(self):
        # voices_dropped with low risk doesn't preclude APPROVED — but the
        # cohort must still have voices_succeeded == voices_planned, so this
        # case is voices_planned=4 with 3 succeeded + 1 dropped-low. That
        # is DEGRADED per the table (voices_succeeded < voices_planned).
        # So APPROVED stays narrow: 3/3 succeeded, no drops, full chain.
        # This test pins the boundary.
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            voices_planned=4,
            voices_succeeded=3,
            voices_succeeded_ids=["opus", "gpt-5.5-pro", "gemini-3.1-pro"],
            voices_dropped=[_dropped("haiku", blocker_risk="low")],
        )
        # DEGRADED — voices_succeeded < voices_planned
        assert compute_verdict_status(env) == "DEGRADED"


# ---------------------------------------------------------------------------
# DEGRADED conditions (SDD §3.2.2 row 2)
# ---------------------------------------------------------------------------


class TestDEGRADED:
    def test_partial_success_consensus_no_high_risk(self):
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            voices_planned=3,
            voices_succeeded=2,
            voices_succeeded_ids=["opus", "gpt-5.5-pro"],
            voices_dropped=[_dropped("gemini-3.1-pro", blocker_risk="med")],
            chain_health="degraded",
            confidence_floor="med",
            rationale="gemini-3.1-pro dropped (EmptyContent); remaining voices reached consensus",
        )
        assert compute_verdict_status(env) == "DEGRADED"

    def test_partial_success_chain_health_ok_via_within_company_fallback(self):
        # Within-company chain walked to a fallback that succeeded —
        # chain_health is "degraded" not "ok" because the primary failed.
        # Some FL configs may still report chain_health=ok if the fallback
        # is in the same provider; covered as DEGRADED via voices_succeeded
        # < voices_planned check.
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            voices_planned=3,
            voices_succeeded=2,
            voices_succeeded_ids=["opus", "gpt-5.5-pro"],
            voices_dropped=[_dropped("gemini-3.1-pro", blocker_risk="unknown")],
            chain_health="degraded",
            confidence_floor="med",
            rationale="gemini dropped; chain walked unsuccessfully",
        )
        assert compute_verdict_status(env) == "DEGRADED"


# ---------------------------------------------------------------------------
# FAILED auto-promotion paths (SDD §3.2.2 row 3)
# ---------------------------------------------------------------------------


class TestFAILED:
    def test_voices_succeeded_zero(self):
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            voices_planned=3,
            voices_succeeded=0,
            voices_succeeded_ids=[],
            voices_dropped=[
                _dropped("opus", reason="EmptyContent", blocker_risk="med"),
                _dropped("gpt-5.5-pro", reason="EmptyContent", blocker_risk="med"),
                _dropped("gemini-3.1-pro", reason="EmptyContent", blocker_risk="med"),
            ],
            chain_health="exhausted",
            confidence_floor="low",
            rationale="all 3 voices dropped",
        )
        assert compute_verdict_status(env) == "FAILED"

    def test_chain_exhausted(self):
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            voices_planned=3,
            voices_succeeded=1,
            voices_succeeded_ids=["opus"],
            voices_dropped=[
                _dropped("gpt-5.5-pro", reason="ChainExhausted", blocker_risk="med"),
                _dropped("gemini-3.1-pro", reason="ChainExhausted", blocker_risk="med"),
            ],
            chain_health="exhausted",
            confidence_floor="low",
            rationale="two voices' chains exhausted",
        )
        assert compute_verdict_status(env) == "FAILED"

    def test_consensus_impossible(self):
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            consensus_outcome="impossible",
            rationale="opus + gpt-5.5-pro disagree on BLOCKER classification",
        )
        # All 3 voices succeeded but contradicted each other.
        assert compute_verdict_status(env) == "FAILED"

    def test_any_dropped_voice_blocker_risk_high(self):
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            voices_planned=3,
            voices_succeeded=2,
            voices_succeeded_ids=["opus", "gpt-5.5-pro"],
            voices_dropped=[_dropped("gemini-3.1-pro", blocker_risk="high")],
            chain_health="degraded",
            confidence_floor="med",
            rationale="gemini dropped with high blocker_risk",
        )
        assert compute_verdict_status(env) == "FAILED"

    def test_chunks_dropped_without_waiver(self):
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            chunked=True,
            chunks_reviewed=4,
            chunks_dropped=1,
            chunks_aggregated_findings=12,
            rationale="1 of 5 chunks dropped mid-review",
        )
        assert compute_verdict_status(env) == "FAILED"

    def test_chunks_dropped_with_waiver_does_not_promote(self):
        # v5 SKP-001 break-glass: when truncation_waiver_applied is true,
        # chunks_dropped > 0 does NOT auto-promote to FAILED. The verdict
        # follows the standard table (here: 3/3 succeeded → APPROVED).
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            chunked=True,
            chunks_reviewed=4,
            chunks_dropped=1,
            chunks_aggregated_findings=12,
            truncation_waiver_applied=True,
            rationale="1 of 5 chunks dropped; waiver applied per §4.1.3 break-glass",
        )
        assert compute_verdict_status(env) == "APPROVED"


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------


class TestEdges:
    def test_single_voice_call_succeeded(self):
        # voices_planned=1, voices_succeeded=1 — APPROVED. FR-2.9
        # single_voice_call flag suppresses consensus inference; the
        # classifier still says APPROVED because the only voice succeeded
        # and chain_health is ok.
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            voices_planned=1,
            voices_succeeded=1,
            voices_succeeded_ids=["opus"],
            single_voice_call=True,
            rationale="BB single-pass against opus",
        )
        assert compute_verdict_status(env) == "APPROVED"

    def test_single_voice_call_failed(self):
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(
            voices_planned=1,
            voices_succeeded=0,
            voices_succeeded_ids=[],
            voices_dropped=[_dropped("opus", reason="EmptyContent", blocker_risk="high")],
            chain_health="exhausted",
            confidence_floor="low",
            single_voice_call=True,
            rationale="single-voice BB run; only voice dropped",
        )
        assert compute_verdict_status(env) == "FAILED"


# ---------------------------------------------------------------------------
# validate_invariants (v5 SKP-005 closure)
# ---------------------------------------------------------------------------


class TestValidateInvariants:
    def test_well_formed_envelope_passes(self):
        from loa_cheval.verdict.quality import validate_invariants
        env = _baseline_envelope()
        validate_invariants(env)  # does not raise

    def test_voices_planned_zero_raises(self):
        from loa_cheval.verdict.quality import (
            EnvelopeInvariantViolation,
            validate_invariants,
        )
        env = _baseline_envelope(voices_planned=0)
        with pytest.raises(EnvelopeInvariantViolation):
            validate_invariants(env)

    def test_voices_succeeded_exceeds_planned_raises(self):
        from loa_cheval.verdict.quality import (
            EnvelopeInvariantViolation,
            validate_invariants,
        )
        env = _baseline_envelope(voices_succeeded=4)
        with pytest.raises(EnvelopeInvariantViolation):
            validate_invariants(env)

    def test_voices_succeeded_negative_raises(self):
        from loa_cheval.verdict.quality import (
            EnvelopeInvariantViolation,
            validate_invariants,
        )
        env = _baseline_envelope(voices_succeeded=-1)
        with pytest.raises(EnvelopeInvariantViolation):
            validate_invariants(env)

    def test_succeeded_ids_length_mismatch_raises(self):
        from loa_cheval.verdict.quality import (
            EnvelopeInvariantViolation,
            validate_invariants,
        )
        env = _baseline_envelope(
            voices_succeeded=3,
            voices_succeeded_ids=["opus", "gpt-5.5-pro"],  # only 2
        )
        with pytest.raises(EnvelopeInvariantViolation):
            validate_invariants(env)

    def test_succeeded_ids_duplicate_raises(self):
        from loa_cheval.verdict.quality import (
            EnvelopeInvariantViolation,
            validate_invariants,
        )
        env = _baseline_envelope(
            voices_succeeded_ids=["opus", "opus", "gpt-5.5-pro"],
        )
        with pytest.raises(EnvelopeInvariantViolation):
            validate_invariants(env)

    def test_voice_in_both_succeeded_and_dropped_raises(self):
        # SKP-003 v6 closure: cross-set invariant.
        from loa_cheval.verdict.quality import (
            EnvelopeInvariantViolation,
            validate_invariants,
        )
        env = _baseline_envelope(
            voices_planned=3,
            voices_succeeded=2,
            voices_succeeded_ids=["opus", "gpt-5.5-pro"],
            voices_dropped=[_dropped("gpt-5.5-pro", blocker_risk="med")],
            chain_health="degraded",
            confidence_floor="med",
        )
        with pytest.raises(EnvelopeInvariantViolation):
            validate_invariants(env)

    def test_dropped_count_mismatches_planned_minus_succeeded_raises(self):
        # Per v5 SKP-005: len(voices_dropped) == voices_planned - voices_succeeded
        from loa_cheval.verdict.quality import (
            EnvelopeInvariantViolation,
            validate_invariants,
        )
        env = _baseline_envelope(
            voices_planned=3,
            voices_succeeded=2,
            voices_succeeded_ids=["opus", "gpt-5.5-pro"],
            voices_dropped=[],  # should have 1 entry for the missing voice
            chain_health="degraded",
            confidence_floor="med",
        )
        with pytest.raises(EnvelopeInvariantViolation):
            validate_invariants(env)


# ---------------------------------------------------------------------------
# Sole writer contract (SKP-001 closure)
# ---------------------------------------------------------------------------


class TestSoleWriter:
    def test_compute_overwrites_caller_supplied_status(self):
        # The status field is OUTPUT-only — callers passing a pre-set status
        # see it replaced. The function is the sole writer per SDD §3.2.2.
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope(status="FAILED")  # caller tries to spoof
        # Conditions are APPROVED-shaped; compute_verdict_status returns
        # APPROVED regardless of the caller-supplied status string.
        assert compute_verdict_status(env) == "APPROVED"

    def test_compute_returns_string_not_dict(self):
        # The function returns the status enum value; the caller is
        # responsible for assigning it to envelope["status"] via
        # emit_envelope_with_status (the single producer entry-point per
        # v5 SKP-003).
        from loa_cheval.verdict.quality import compute_verdict_status
        env = _baseline_envelope()
        result = compute_verdict_status(env)
        assert isinstance(result, str)
        assert result in ("APPROVED", "DEGRADED", "FAILED")


# ---------------------------------------------------------------------------
# emit_envelope_with_status — single producer entry-point (v5 SKP-003)
# ---------------------------------------------------------------------------


class TestEmitEnvelopeWithStatus:
    def test_emit_writes_status_field(self):
        from loa_cheval.verdict.quality import emit_envelope_with_status
        env = _baseline_envelope()
        env.pop("status")
        out = emit_envelope_with_status(env)
        assert out["status"] == "APPROVED"

    def test_emit_validates_invariants_before_classification(self):
        from loa_cheval.verdict.quality import (
            EnvelopeInvariantViolation,
            emit_envelope_with_status,
        )
        env = _baseline_envelope(voices_planned=0)
        with pytest.raises(EnvelopeInvariantViolation):
            emit_envelope_with_status(env)

    def test_emit_preserves_other_fields(self):
        from loa_cheval.verdict.quality import emit_envelope_with_status
        env = _baseline_envelope(rationale="custom rationale text")
        out = emit_envelope_with_status(env)
        assert out["rationale"] == "custom rationale text"
        assert out["voices_planned"] == 3
        assert out["consensus_outcome"] == "consensus"
