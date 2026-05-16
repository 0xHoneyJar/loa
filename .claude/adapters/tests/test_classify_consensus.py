"""cycle-109 Sprint 2 T2.9 — classify_consensus algorithm per SDD §3.2.2.1
(SKP-001 v6 closure). Tests the new consensus-outcome classifier.

Algorithm summary (SDD §3.2.2.1):
  1. Trivial: voices_succeeded < 2 → "consensus"
  2. Per-finding BLOCKER cross-voice comparison.
  3. If ANY BLOCKER from V₁ is contradicted (same location, non-BLOCKER
     severity) by V₂ → "impossible".
  4. Edge case: BLOCKER with no location field — single-voice signal,
     treat as "consensus" (absence of corroboration is NOT contradiction).
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


def _envelope_for(voices_succeeded: int, voices_planned: int = 3):
    """Minimal envelope shell for classify_consensus tests."""
    return {
        "voices_planned": voices_planned,
        "voices_succeeded": voices_succeeded,
        "voices_succeeded_ids": [f"voice-{i}" for i in range(voices_succeeded)],
        "voices_dropped": [],
        "chain_health": "ok" if voices_succeeded == voices_planned else "degraded",
    }


def _finding(severity: str, file_path: str = "src/app.py",
             line_number: int = 42, title: str = "issue"):
    return {
        "severity": severity,
        "file_path": file_path,
        "line_number": line_number,
        "title": title,
    }


# ---------------------------------------------------------------------------
# Trivial cases
# ---------------------------------------------------------------------------


def test_zero_succeeded_returns_consensus():
    """voices_succeeded=0: no findings to compare — trivially 'consensus'."""
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=0)
    assert classify_consensus(env, []) == "consensus"


def test_one_succeeded_returns_consensus():
    """Single voice: no peer to contradict — trivially 'consensus'."""
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=1)
    findings = [[_finding("BLOCKER")]]
    assert classify_consensus(env, findings) == "consensus"


def test_two_voices_no_blockers_returns_consensus():
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=2)
    findings = [
        [_finding("HIGH"), _finding("LOW")],
        [_finding("MED")],
    ]
    assert classify_consensus(env, findings) == "consensus"


# ---------------------------------------------------------------------------
# Multi-voice agreement
# ---------------------------------------------------------------------------


def test_all_voices_emit_same_blocker_returns_consensus():
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=3)
    findings = [
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("BLOCKER", "src/auth.py", 100)],
    ]
    assert classify_consensus(env, findings) == "consensus"


def test_blocker_plus_high_at_same_location_is_consensus():
    """SDD §3.2.2.1 fixture: V₁=BLOCKER, V₂=HIGH at same location → consensus
    (both voices flag the issue; severity differs but both >= HIGH)."""
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=2)
    findings = [
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("HIGH", "src/auth.py", 100)],
    ]
    assert classify_consensus(env, findings) == "consensus"


# ---------------------------------------------------------------------------
# Contradiction → impossible
# ---------------------------------------------------------------------------


def test_blocker_v1_plus_low_v2_at_same_location_is_impossible():
    """SDD §3.2.2.1 canonical contradiction fixture: V₁=BLOCKER vs V₂=LOW at
    same location → impossible. The substrate cannot agree on safety status."""
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=2)
    findings = [
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("LOW", "src/auth.py", 100)],
    ]
    assert classify_consensus(env, findings) == "impossible"


def test_blocker_v1_plus_med_v2_at_same_location_is_impossible():
    """MED is non-BLOCKER (per SDD: 'any severity < HIGH'). Wait — SDD says
    'classify it as non-BLOCKER (any severity < HIGH)'. MED < HIGH so MED
    counts as contradiction."""
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=2)
    findings = [
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("MED", "src/auth.py", 100)],
    ]
    assert classify_consensus(env, findings) == "impossible"


def test_blocker_v1_plus_high_v2_at_different_location_is_consensus():
    """V₁=BLOCKER + V₂=LOW at DIFFERENT location — no contradiction at the
    same location → consensus."""
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=2)
    findings = [
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("LOW", "src/db.py", 200)],  # different file
    ]
    assert classify_consensus(env, findings) == "consensus"


def test_contradiction_only_needs_one_blocker_pair():
    """Multiple BLOCKERs: ANY one contradicted pair → impossible."""
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=3)
    findings = [
        [_finding("BLOCKER", "src/auth.py", 100),
         _finding("BLOCKER", "src/db.py", 200)],
        [_finding("BLOCKER", "src/auth.py", 100),  # agrees
         _finding("LOW", "src/db.py", 200)],        # contradicts!
        [_finding("HIGH", "src/auth.py", 100)],
    ]
    assert classify_consensus(env, findings) == "impossible"


# ---------------------------------------------------------------------------
# Edge case: BLOCKER without location
# ---------------------------------------------------------------------------


def test_blocker_without_location_no_corroboration_is_consensus():
    """SDD §3.2.2.1 edge case: structural BLOCKER (no location field) from
    one voice without corroboration → consensus (single-voice signal, not
    contradiction). Absence of agreement is NOT the same as contradiction."""
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=3)
    findings = [
        [{"severity": "BLOCKER", "title": "missing tests"}],  # no location
        [_finding("HIGH", "src/foo.py", 10)],
        [_finding("MED", "src/bar.py", 20)],
    ]
    assert classify_consensus(env, findings) == "consensus"


# ---------------------------------------------------------------------------
# Forbidden output values
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("voices_succeeded,findings_count", [(0, 0), (1, 1), (2, 2), (3, 3)])
def test_output_is_always_valid_enum(voices_succeeded, findings_count):
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=voices_succeeded)
    findings = [[_finding("HIGH")] for _ in range(findings_count)]
    result = classify_consensus(env, findings)
    assert result in {"consensus", "impossible"}


# ---------------------------------------------------------------------------
# Determinism (golden-fixture friendly)
# ---------------------------------------------------------------------------


def test_classify_consensus_is_deterministic():
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=2)
    findings = [
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("LOW", "src/auth.py", 100)],
    ]
    first = classify_consensus(env, findings)
    for _ in range(5):
        assert classify_consensus(env, findings) == first


def test_classify_consensus_does_not_mutate_inputs():
    import copy
    from loa_cheval.verdict.consensus import classify_consensus

    env = _envelope_for(voices_succeeded=2)
    findings = [
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("LOW", "src/auth.py", 100)],
    ]
    env_copy = copy.deepcopy(env)
    findings_copy = copy.deepcopy(findings)
    _ = classify_consensus(env, findings)
    assert env == env_copy, "classify_consensus mutated envelope"
    assert findings == findings_copy, "classify_consensus mutated findings list"


# ---------------------------------------------------------------------------
# Aggregator integration
# ---------------------------------------------------------------------------


def test_aggregate_envelopes_accepts_findings_per_voice():
    """T2.9 wires classify_consensus into aggregate_envelopes via an optional
    findings_per_voice kwarg. When provided, the multi-voice envelope's
    consensus_outcome reflects the algorithm. When omitted, falls back to the
    T2.4 'consensus' placeholder."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    def _single_voice_with_findings(voice_id):
        return {
            "status": "APPROVED",
            "consensus_outcome": "consensus",
            "truncation_waiver_applied": False,
            "voices_planned": 1,
            "voices_succeeded": 1,
            "voices_succeeded_ids": [voice_id],
            "voices_dropped": [],
            "chain_health": "ok",
            "confidence_floor": "low",
            "rationale": "test",
            "single_voice_call": True,
        }

    inputs = [
        _single_voice_with_findings("a"),
        _single_voice_with_findings("b"),
    ]
    findings_per_voice = [
        [_finding("BLOCKER", "src/auth.py", 100)],
        [_finding("LOW", "src/auth.py", 100)],
    ]
    out = aggregate_envelopes(inputs, findings_per_voice=findings_per_voice)
    assert out["consensus_outcome"] == "impossible"
    # FAILED auto-promotion because consensus_outcome == impossible (SDD §3.2.2)
    assert out["status"] == "FAILED"


def test_aggregate_envelopes_findings_per_voice_omitted_keeps_consensus():
    """Backward compat: omitting findings_per_voice keeps the T2.4
    'consensus' placeholder."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    def _single_voice_approved(voice_id):
        return {
            "status": "APPROVED",
            "consensus_outcome": "consensus",
            "truncation_waiver_applied": False,
            "voices_planned": 1,
            "voices_succeeded": 1,
            "voices_succeeded_ids": [voice_id],
            "voices_dropped": [],
            "chain_health": "ok",
            "confidence_floor": "low",
            "rationale": "test",
            "single_voice_call": True,
        }

    out = aggregate_envelopes([_single_voice_approved("a"), _single_voice_approved("b")])
    assert out["consensus_outcome"] == "consensus"
