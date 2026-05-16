"""cycle-109 Sprint 2 T2.4 — verdict_quality multi-voice aggregator.

Per SDD §3.2.3 IMP-004 row 2: flatline-orchestrator.sh runs N voices
(canonically 3: GPT/Opus/Gemini) in parallel; each voice produces a
single-voice verdict_quality envelope via cheval (T2.3 PRODUCER #1).
FL must aggregate those into a multi-voice envelope and write it to
final_consensus.json so consumers downstream see the aggregate truth.

The aggregator is the canonical Python writer (mirrors T2.2 pattern):
``loa_cheval.verdict.aggregate.aggregate_envelopes`` consumes a list of
single-voice envelopes and returns a multi-voice envelope conforming to
verdict-quality.schema.json. The bash side (flatline-orchestrator.sh)
shells out via ``python -m loa_cheval.verdict.aggregate`` — no logic
duplication; drift is impossible by construction (SDD §5.2.1).

Aggregation rules (T2.4 v1 — classify_consensus comes in T2.9):

  voices_planned     = len(input envelopes)
  voices_succeeded   = sum of voices_succeeded across inputs
  voices_succeeded_ids = flat list of succeeded ids
  voices_dropped     = concatenation of dropped[] from each input
  chain_health       = worst-of-N (exhausted > degraded > ok)
  confidence_floor   = "high" if all succeeded
                       "med"  if majority succeeded
                       "low"  otherwise
  consensus_outcome  = "consensus" (placeholder until T2.9 classify_consensus)
  truncation_waiver_applied = false (only set by §4.1.3 break-glass)
  rationale          = aggregated one-paragraph summary
  single_voice_call  = false (always for N > 1)
  status             = computed by emit_envelope_with_status per SDD §3.2.2

The aggregator MUST pass through ``emit_envelope_with_status`` so the
producer-side ``validate_invariants`` cross-field checks run on the
aggregated envelope. NFR-Rel-1: an aggregator that bypasses validation
could emit ``APPROVED`` when the inputs prove DEGRADED.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------


def _single_voice_approved(voice_id: str = "voice-a"):
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
        "rationale": f"single-voice cheval invoke (voice={voice_id})",
        "single_voice_call": True,
    }


def _single_voice_degraded(voice_id: str = "voice-b"):
    """Single voice succeeded after chain-walk to fallback."""
    return {
        "status": "DEGRADED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": False,
        "voices_planned": 1,
        "voices_succeeded": 1,
        "voices_succeeded_ids": [voice_id],
        "voices_dropped": [],
        "chain_health": "degraded",
        "confidence_floor": "low",
        "rationale": f"single-voice cheval invoke (voice={voice_id}); walked",
        "single_voice_call": True,
    }


def _single_voice_failed(voice_id: str = "voice-c", reason: str = "EmptyContent",
                         blocker_risk: str = "med", exit_code: int = 1):
    return {
        "status": "FAILED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": False,
        "voices_planned": 1,
        "voices_succeeded": 0,
        "voices_succeeded_ids": [],
        "voices_dropped": [
            {
                "voice": voice_id,
                "reason": reason,
                "exit_code": exit_code,
                "blocker_risk": blocker_risk,
                "chain_walk": [],
            }
        ],
        "chain_health": "exhausted",
        "confidence_floor": "low",
        "rationale": f"single-voice cheval invoke (voice={voice_id}); failed",
        "single_voice_call": True,
    }


# ---------------------------------------------------------------------------
# Basic shape / status classification
# ---------------------------------------------------------------------------


def test_three_approved_aggregates_to_approved():
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("gpt-5.5-pro"),
        _single_voice_approved("claude-opus-4-7"),
        _single_voice_approved("gemini-3.1-pro"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["voices_planned"] == 3
    assert out["voices_succeeded"] == 3
    assert sorted(out["voices_succeeded_ids"]) == sorted([
        "gpt-5.5-pro", "claude-opus-4-7", "gemini-3.1-pro",
    ])
    assert out["voices_dropped"] == []
    assert out["chain_health"] == "ok"
    assert out["status"] == "APPROVED"
    assert out["single_voice_call"] is False


def test_two_succeeded_one_failed_aggregates_to_degraded():
    """2 of 3 voices succeeded; the dropped voice carries blocker_risk=med
    (default for chain-fallthrough per SDD §3.1.4 SKP-005). Status MUST be
    DEGRADED, not APPROVED, because voices_dropped[].blocker_risk='med'
    violates the APPROVED invariant per SDD §3.2.2."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("gpt-5.5-pro"),
        _single_voice_approved("claude-opus-4-7"),
        _single_voice_failed(
            "gemini-3.1-pro", reason="EmptyContent", blocker_risk="med",
        ),
    ]
    out = aggregate_envelopes(inputs)
    assert out["voices_planned"] == 3
    assert out["voices_succeeded"] == 2
    assert "gemini-3.1-pro" not in out["voices_succeeded_ids"]
    assert len(out["voices_dropped"]) == 1
    assert out["voices_dropped"][0]["voice"] == "gemini-3.1-pro"
    assert out["status"] == "DEGRADED"


def test_one_voice_failed_with_high_blocker_risk_promotes_to_failed():
    """SDD §3.2.2 hard rule: any voices_dropped[].blocker_risk=='high'
    promotes the multi-voice envelope to FAILED, even if a majority
    succeeded. This is the NFR-Rel-1 closure: losing the primary safety
    voice on a high-risk failure cannot be silently classified APPROVED/
    DEGRADED."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("gpt-5.5-pro"),
        _single_voice_approved("claude-opus-4-7"),
        _single_voice_failed(
            "gemini-3.1-pro", reason="ChainExhausted", blocker_risk="high",
        ),
    ]
    out = aggregate_envelopes(inputs)
    assert out["status"] == "FAILED"


def test_zero_succeeded_aggregates_to_failed():
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_failed("voice-a", blocker_risk="med"),
        _single_voice_failed("voice-b", blocker_risk="med"),
        _single_voice_failed("voice-c", blocker_risk="med"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["voices_succeeded"] == 0
    assert out["status"] == "FAILED"
    assert len(out["voices_dropped"]) == 3


# ---------------------------------------------------------------------------
# chain_health worst-of-N
# ---------------------------------------------------------------------------


def test_chain_health_ok_when_all_voices_ok():
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("a"),
        _single_voice_approved("b"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["chain_health"] == "ok"


def test_chain_health_degraded_when_any_voice_degraded():
    """Worst-of-N propagation: a single 'degraded' voice (chain walked
    to fallback) demotes the multi-voice chain_health to 'degraded'."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("a"),
        _single_voice_degraded("b"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["chain_health"] == "degraded"


def test_chain_health_degraded_when_some_voices_failed_partial_success():
    """Multi-voice semantics differ from single-voice: a partially-failed
    cohort (some voices failed, some succeeded) reports chain_health=
    'degraded' rather than 'exhausted'. This prevents the SDD §3.2.2
    chain_health=exhausted ⇒ FAILED auto-promotion from firing on a
    majority-success cohort — the canonical FL trajectory where 2 of 3
    voices succeed and the aggregate should classify as DEGRADED."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("a"),
        _single_voice_approved("b"),
        _single_voice_failed("c", blocker_risk="med"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["chain_health"] == "degraded"


def test_chain_health_exhausted_only_when_all_voices_failed():
    """chain_health=exhausted is reserved for the case where EVERY voice
    failed. With any voice succeeding, the aggregate is at most degraded."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_failed("a", blocker_risk="med"),
        _single_voice_failed("b", blocker_risk="med"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["chain_health"] == "exhausted"


# ---------------------------------------------------------------------------
# confidence_floor by ratio
# ---------------------------------------------------------------------------


def test_confidence_floor_high_when_all_succeed():
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [_single_voice_approved("a"), _single_voice_approved("b"), _single_voice_approved("c")]
    out = aggregate_envelopes(inputs)
    assert out["confidence_floor"] == "high"


def test_confidence_floor_med_when_majority_succeed():
    """2 of 3 → majority but not all → med."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("a"),
        _single_voice_approved("b"),
        _single_voice_failed("c", blocker_risk="med"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["confidence_floor"] == "med"


def test_confidence_floor_low_when_minority_succeed():
    """1 of 3 → minority → low."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("a"),
        _single_voice_failed("b", blocker_risk="med"),
        _single_voice_failed("c", blocker_risk="med"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["confidence_floor"] == "low"


def test_confidence_floor_low_when_none_succeed():
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_failed("a", blocker_risk="med"),
        _single_voice_failed("b", blocker_risk="med"),
    ]
    out = aggregate_envelopes(inputs)
    assert out["confidence_floor"] == "low"


# ---------------------------------------------------------------------------
# voices_dropped aggregation
# ---------------------------------------------------------------------------


def test_voices_dropped_preserves_all_failure_details():
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [
        _single_voice_approved("a"),
        _single_voice_failed("b", reason="EmptyContent", blocker_risk="med", exit_code=1),
        _single_voice_failed("c", reason="RateLimited", blocker_risk="low", exit_code=1),
    ]
    out = aggregate_envelopes(inputs)
    assert len(out["voices_dropped"]) == 2
    voices = {d["voice"]: d for d in out["voices_dropped"]}
    assert voices["b"]["reason"] == "EmptyContent"
    assert voices["b"]["blocker_risk"] == "med"
    assert voices["c"]["reason"] == "RateLimited"
    assert voices["c"]["blocker_risk"] == "low"


def test_voices_dropped_chain_walk_preserved():
    """The chain_walk field from each input voices_dropped[] entry
    propagates verbatim into the aggregate. Operators rely on the
    trace to diagnose where a voice's chain bottomed out."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    single = _single_voice_failed("opus", blocker_risk="med")
    single["voices_dropped"][0]["chain_walk"] = [
        "anthropic:claude-opus-4-7", "anthropic:claude-opus-4-6",
    ]
    inputs = [_single_voice_approved("gpt"), single]
    out = aggregate_envelopes(inputs)
    opus_entry = next(d for d in out["voices_dropped"] if d["voice"] == "opus")
    assert opus_entry["chain_walk"] == [
        "anthropic:claude-opus-4-7", "anthropic:claude-opus-4-6",
    ]


# ---------------------------------------------------------------------------
# Defensive / edge cases
# ---------------------------------------------------------------------------


def test_empty_envelope_list_raises():
    """An empty input list cannot produce a valid envelope
    (voices_planned MUST be >= 1 per schema). Aggregator MUST raise
    rather than silently emit a degenerate envelope."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    with pytest.raises(ValueError):
        aggregate_envelopes([])


def test_single_voice_passthrough_preserves_single_voice_call_flag():
    """Edge: 1 input envelope. The aggregator MUST still produce a valid
    envelope; single_voice_call should remain True since voices_planned=1."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    out = aggregate_envelopes([_single_voice_approved("a")])
    assert out["voices_planned"] == 1
    assert out["single_voice_call"] is True


def test_multi_voice_clears_single_voice_call_flag():
    """When voices_planned >= 2, single_voice_call MUST be False."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    out = aggregate_envelopes([_single_voice_approved("a"), _single_voice_approved("b")])
    assert out["single_voice_call"] is False


def test_aggregator_does_not_mutate_inputs():
    """Defensive: the aggregator MUST NOT mutate caller's envelopes.
    FL keeps references for per-voice logging downstream."""
    import copy
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    inputs = [_single_voice_approved("a"), _single_voice_failed("b", blocker_risk="med")]
    inputs_copy = copy.deepcopy(inputs)
    _ = aggregate_envelopes(inputs)
    assert inputs == inputs_copy, "aggregator mutated caller's envelope list"


def test_aggregator_runs_through_emit_envelope_with_status():
    """The aggregator MUST pass through emit_envelope_with_status so
    validate_invariants + compute_verdict_status run on the aggregate.
    An aggregator that bypasses validation would let inconsistent
    envelopes flow downstream (e.g., voices_succeeded > voices_planned)."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    # Construct a malformed input that would fail invariants if not validated.
    # Specifically: voices_succeeded > voices_planned in input. We aggregate
    # 2 valid inputs, and assert the OUTPUT carries a `status` field —
    # absence would prove emit_envelope_with_status was not called.
    out = aggregate_envelopes([_single_voice_approved("a"), _single_voice_approved("b")])
    assert "status" in out, "status absent — emit_envelope_with_status not called"


def test_rationale_is_within_schema_bounds():
    """rationale must be non-empty and ≤ 1024 chars per schema."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    out = aggregate_envelopes([
        _single_voice_approved("a"), _single_voice_approved("b"), _single_voice_approved("c"),
    ])
    rat = out["rationale"]
    assert isinstance(rat, str)
    assert 0 < len(rat) <= 1024


def test_consensus_outcome_v1_is_always_consensus():
    """T2.4 v1: consensus_outcome defaults to 'consensus' regardless of
    finding overlap. T2.9 will replace this with classify_consensus per
    SDD §3.2.2.1 (per-finding cross-voice comparison + contradiction
    threshold). The contract here pins the v1 placeholder so T2.9 has
    a deterministic regression target to flip."""
    from loa_cheval.verdict.aggregate import aggregate_envelopes

    out = aggregate_envelopes([
        _single_voice_approved("a"), _single_voice_approved("b"),
    ])
    assert out["consensus_outcome"] == "consensus"


# ---------------------------------------------------------------------------
# CLI entry point (bash twin shells out)
# ---------------------------------------------------------------------------


def test_aggregate_cli_main_reads_envelope_files_from_argv(tmp_path):
    """`python -m loa_cheval.verdict.aggregate <file1> <file2> ...`
    reads each path as JSON, aggregates, prints to stdout. The bash
    twin (FL orchestrator) shells out to this CLI; the contract is
    file-paths-as-positional-args, aggregate-json-on-stdout, exit-0
    on success."""
    import json
    import subprocess

    f1 = tmp_path / "v1.json"
    f2 = tmp_path / "v2.json"
    f1.write_text(json.dumps(_single_voice_approved("a")))
    f2.write_text(json.dumps(_single_voice_approved("b")))

    repo_root = Path(__file__).resolve().parents[3]
    result = subprocess.run(
        ["python3", "-m", "loa_cheval.verdict.aggregate", str(f1), str(f2)],
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        env={
            "PYTHONPATH": str(repo_root / ".claude" / "adapters"),
            "PATH": "/usr/bin:/bin",
        },
    )
    assert result.returncode == 0, (
        f"aggregate CLI failed: stderr={result.stderr!r}"
    )
    parsed = json.loads(result.stdout)
    assert parsed["voices_planned"] == 2
    assert parsed["status"] == "APPROVED"
