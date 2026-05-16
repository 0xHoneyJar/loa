"""PR #896 BB iter-1 FIND-003 — voices_planned shrinkage fix tests.

Pin the new behavior:
  - Without expected_voices_count: legacy shape (voices_planned = len(envelopes))
  - With expected_voices_count > len(envelopes): voices_planned reflects
    the EXPECTED cohort size; missing voices land in voices_dropped[].
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def _single_voice_envelope(voice: str = "voice-a", succeeded: bool = True) -> dict:
    """Build a minimal validated single-voice envelope shape."""
    if succeeded:
        return {
            "status": "APPROVED",
            "consensus_outcome": "consensus",
            "truncation_waiver_applied": False,
            "voices_planned": 1,
            "voices_succeeded": 1,
            "voices_succeeded_ids": [voice],
            "voices_dropped": [],
            "chain_health": "ok",
            "confidence_floor": "high",
            "rationale": "test single voice ok",
            "single_voice_call": True,
        }
    return {
        "status": "FAILED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": False,
        "voices_planned": 1,
        "voices_succeeded": 0,
        "voices_succeeded_ids": [],
        "voices_dropped": [{
            "voice": voice,
            "reason": "ChainExhausted",
            "exit_code": 12,
            "blocker_risk": "unknown",
        }],
        "chain_health": "exhausted",
        "confidence_floor": "low",
        "rationale": "test single voice failed",
        "single_voice_call": True,
    }


# ---------------------------------------------------------------------------
# Legacy: no expected_voices_count → voices_planned = len(envelopes)
# ---------------------------------------------------------------------------


def test_legacy_voices_planned_matches_envelope_count():
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    envs = [_single_voice_envelope("a"), _single_voice_envelope("b")]
    out = aggregate_envelopes(envs)
    assert out["voices_planned"] == 2
    assert out["voices_succeeded"] == 2


# ---------------------------------------------------------------------------
# FIND-003: expected_voices_count > observed → no shrinkage
# ---------------------------------------------------------------------------


def test_expected_three_observed_two_keeps_voices_planned_at_three():
    """The exact FIND-003 case: 2-of-3 degraded must NOT be silently
    promoted to APPROVED 2-of-2 by shrinking the denominator."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    envs = [_single_voice_envelope("a"), _single_voice_envelope("b")]
    out = aggregate_envelopes(envs, expected_voices_count=3)
    assert out["voices_planned"] == 3
    assert out["voices_succeeded"] == 2
    # The missing voice surfaces in voices_dropped
    assert len(out["voices_dropped"]) >= 1


def test_missing_voice_appears_in_voices_dropped_with_other_reason():
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    envs = [_single_voice_envelope("a"), _single_voice_envelope("b")]
    out = aggregate_envelopes(envs, expected_voices_count=3)
    # Find the synthesized missing-voice entry
    missing = [d for d in out["voices_dropped"] if d.get("reason") == "Other"]
    assert len(missing) == 1
    assert missing[0]["voice"].startswith("missing-voice-")
    assert missing[0]["blocker_risk"] == "unknown"


def test_two_missing_voices_synthesize_two_dropped_entries():
    """Edge case: only 1 envelope arrived in a 3-voice cohort."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    envs = [_single_voice_envelope("a")]
    out = aggregate_envelopes(envs, expected_voices_count=3)
    assert out["voices_planned"] == 3
    missing = [d for d in out["voices_dropped"] if d.get("reason") == "Other"]
    assert len(missing) == 2


def test_expected_equal_to_observed_is_legacy_shape():
    """No-op when expected_voices_count == len(envelopes)."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    envs = [_single_voice_envelope("a"), _single_voice_envelope("b")]
    out = aggregate_envelopes(envs, expected_voices_count=2)
    assert out["voices_planned"] == 2
    # No synthesized missing-voice entries
    missing = [d for d in out["voices_dropped"] if d.get("reason") == "Other"]
    assert len(missing) == 0


def test_expected_less_than_observed_does_not_truncate():
    """Defensive: expected < observed should NOT trigger shrinkage in
    the other direction. Legacy shape applies."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    envs = [_single_voice_envelope("a"), _single_voice_envelope("b")]
    out = aggregate_envelopes(envs, expected_voices_count=1)
    assert out["voices_planned"] == 2


def test_chain_health_degraded_when_voices_missing():
    """When a voice is missing, the aggregate cannot be chain_health=ok
    (the cohort is no longer fully-ok by definition)."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    envs = [_single_voice_envelope("a"), _single_voice_envelope("b")]
    out = aggregate_envelopes(envs, expected_voices_count=3)
    assert out["chain_health"] != "ok"


def test_status_not_approved_when_voice_missing():
    """The promote-to-APPROVED footgun: with 2-of-3 success but the
    third missing, status MUST NOT be APPROVED (the FIND-003 defect)."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    envs = [_single_voice_envelope("a"), _single_voice_envelope("b")]
    out = aggregate_envelopes(envs, expected_voices_count=3)
    assert out["status"] in ("DEGRADED", "FAILED")
