"""cycle-109 Sprint 2 T2.4 — verdict_quality multi-voice aggregator
(CONSUMER #2 per SDD §3.2.3 IMP-004).

flatline-orchestrator.sh runs N voices (canonically 3: GPT/Opus/Gemini)
in parallel, each producing a single-voice verdict_quality envelope via
the cheval cmd_invoke producer (T2.3 PRODUCER #1). This module
aggregates those into a multi-voice envelope conforming to
verdict-quality.schema.json, which FL writes to final_consensus.json.

Per SDD §5.2.1 the aggregator is the canonical Python writer:
flatline-orchestrator.sh shells out via
``python -m loa_cheval.verdict.aggregate <file1> <file2> ...``. No jq
logic in bash — drift impossible by construction.

Aggregation contract (T2.4 v1):

  voices_planned        = len(inputs)
  voices_succeeded      = sum of voices_succeeded across inputs
  voices_succeeded_ids  = flat list of succeeded ids
  voices_dropped        = concatenation of dropped[] from each input
  chain_health          = "exhausted" iff voices_succeeded == 0
                          "ok"         iff voices_succeeded == voices_planned
                                          AND every input chain_health == "ok"
                          "degraded"   otherwise (any sub-optimal voice state
                                          while at least one voice succeeded —
                                          including a single-voice chain-walk
                                          to fallback OR a fully-failed voice
                                          alongside successful peers)
  confidence_floor      = "high" if all succeeded
                          "med"  if majority succeeded (>= half)
                          "low"  otherwise
  consensus_outcome     = "consensus" (T2.4 placeholder; T2.9 replaces
                          with classify_consensus per SDD §3.2.2.1)
  truncation_waiver_applied = false
  rationale             = one-paragraph aggregate summary
  single_voice_call     = (voices_planned == 1)
  status                = computed by emit_envelope_with_status per
                          SDD §3.2.2 (so any voices_dropped[].blocker_risk
                          == "high" properly promotes to FAILED)

The aggregator passes the final envelope through emit_envelope_with_status
so validate_invariants + compute_verdict_status run on the aggregate
shape; this closes the NFR-Rel-1 invariant that "clean ⇒ APPROVED only on
full success" cannot be bypassed by a buggy aggregator emitting status
directly.
"""

from __future__ import annotations

import copy
from typing import Any, Dict, List, Optional

from .consensus import classify_consensus
from .quality import emit_envelope_with_status


_CHAIN_HEALTH_OK = "ok"
_CHAIN_HEALTH_DEGRADED = "degraded"
_CHAIN_HEALTH_EXHAUSTED = "exhausted"


def aggregate_envelopes(
    envelopes: List[Dict[str, Any]],
    findings_per_voice: Optional[List[List[Dict[str, Any]]]] = None,
    expected_voices_count: Optional[int] = None,
) -> Dict[str, Any]:
    """Aggregate N single-voice envelopes into a multi-voice envelope.

    Args:
      envelopes: list of validated verdict_quality envelopes, one per
        voice. Each MUST have ``voices_planned == 1`` (single-voice)
        though this is not strictly enforced — non-conforming inputs
        will produce a structurally-valid aggregate but the semantics
        may be surprising.
      findings_per_voice: optional (T2.9). When provided, the multi-voice
        ``consensus_outcome`` is computed via
        ``loa_cheval.verdict.consensus.classify_consensus`` per SDD
        §3.2.2.1. When omitted, falls back to the T2.4 ``"consensus"``
        placeholder (preserves backward compat for callers that don't
        have per-voice findings handy yet).
      expected_voices_count: PR #896 BB iter-1 FIND-003 closure. When
        provided and > len(envelopes), the aggregate's `voices_planned`
        uses this value (the EXPECTED cohort size, not the OBSERVED
        envelope count), and the missing voices appear in `voices_dropped`
        as synthesized `EnvelopeMissing` entries. Without this argument
        the legacy behavior holds: ``voices_planned = len(envelopes)``,
        which the BB iter-1 review flagged as the "2-of-3 degraded silently
        promoted to APPROVED 2-of-2" defect.

    Returns:
      A validated, status-stamped multi-voice envelope.

    Raises:
      ValueError: if ``envelopes`` is empty (the schema requires
        ``voices_planned >= 1`` so a zero-voice envelope cannot exist).
      EnvelopeInvariantViolation: if the aggregate fails
        ``validate_invariants``.
    """
    if not envelopes:
        raise ValueError(
            "aggregate_envelopes requires at least one input envelope "
            "(verdict-quality.schema.json requires voices_planned >= 1)"
        )

    # Deep-copy inputs to avoid mutating caller's data — callers may
    # keep references for per-voice logging downstream.
    inputs = [copy.deepcopy(e) for e in envelopes]

    # FIND-003 closure: voices_planned reflects the EXPECTED cohort size
    # when the caller knows it (e.g., the flatline orchestrator counted
    # 3 input files but only 2 produced verdict_quality envelopes). The
    # legacy shape uses len(inputs) which silently elides missing voices.
    observed_count = len(inputs)
    if expected_voices_count is not None and expected_voices_count > observed_count:
        voices_planned = int(expected_voices_count)
        _missing_count = voices_planned - observed_count
    else:
        voices_planned = observed_count
        _missing_count = 0

    # Sum succeeded counts + concatenate succeeded ids.
    voices_succeeded = 0
    voices_succeeded_ids: List[str] = []
    voices_dropped: List[Dict[str, Any]] = []
    all_inputs_ok = True
    truncation_waiver_any = False

    for env in inputs:
        voices_succeeded += int(env.get("voices_succeeded") or 0)
        succeeded_ids = env.get("voices_succeeded_ids") or []
        if isinstance(succeeded_ids, list):
            voices_succeeded_ids.extend(str(s) for s in succeeded_ids)

        dropped = env.get("voices_dropped") or []
        if isinstance(dropped, list):
            for d in dropped:
                if isinstance(d, dict):
                    voices_dropped.append(copy.deepcopy(d))

        if env.get("chain_health", _CHAIN_HEALTH_OK) != _CHAIN_HEALTH_OK:
            all_inputs_ok = False

        if env.get("truncation_waiver_applied"):
            truncation_waiver_any = True

    # FIND-003: synthesize voices_dropped entries for the missing envelopes
    # so the audit trail explicitly shows the gap (vs silently shrinking
    # the denominator). Reason maps to "Other" (the schema's catch-all);
    # the rationale string carries the human-readable "missing envelope"
    # context. blocker_risk=unknown is the safe default per schema
    # description — consumers can treat unknown as med via the
    # blocker_risk_override.unknown_treated_as_med_until_priors toggle.
    # all_inputs_ok flips false because the cohort is no longer fully-ok.
    if _missing_count > 0:
        for _i in range(_missing_count):
            voices_dropped.append({
                "voice": f"missing-voice-{_i + 1}",
                "reason": "Other",
                "exit_code": 0,
                "blocker_risk": "unknown",
            })
        all_inputs_ok = False

    # Multi-voice chain_health semantics differ from the single-voice case:
    # "exhausted" only when EVERY voice failed (voices_succeeded == 0).
    # Otherwise — partial success — the aggregate is at most "degraded"
    # so the SDD §3.2.2 'chain_health=exhausted ⇒ FAILED' auto-promotion
    # doesn't fire on majority-success cohorts (the canonical FL trajectory).
    if voices_succeeded == 0:
        chain_health = _CHAIN_HEALTH_EXHAUSTED
    elif voices_succeeded == voices_planned and all_inputs_ok:
        chain_health = _CHAIN_HEALTH_OK
    else:
        chain_health = _CHAIN_HEALTH_DEGRADED

    # Confidence floor by ratio. Half (or more) succeeded = med; all = high.
    if voices_succeeded == voices_planned:
        confidence_floor = "high"
    elif voices_succeeded * 2 >= voices_planned and voices_succeeded > 0:
        confidence_floor = "med"
    else:
        confidence_floor = "low"

    rationale = _build_aggregate_rationale(
        voices_planned=voices_planned,
        voices_succeeded=voices_succeeded,
        chain_health=chain_health,
        voices_dropped=voices_dropped,
    )

    # cycle-109 Sprint 2 T2.9 — classify_consensus when caller provided
    # per-voice findings. Without findings_per_voice we fall back to the
    # T2.4 placeholder (matches single-voice substrate calls and tests
    # that don't exercise the consensus path).
    if findings_per_voice is not None and findings_per_voice:
        # Compute against a partial envelope shell — classify_consensus
        # only reads voices_succeeded so we pass a minimal dict.
        consensus_outcome = classify_consensus(
            {"voices_succeeded": voices_succeeded}, findings_per_voice,
        )
    else:
        consensus_outcome = "consensus"

    envelope: Dict[str, Any] = {
        "consensus_outcome": consensus_outcome,  # T2.9: classify_consensus or T2.4 placeholder
        "truncation_waiver_applied": truncation_waiver_any,
        "voices_planned": voices_planned,
        "voices_succeeded": voices_succeeded,
        "voices_succeeded_ids": voices_succeeded_ids,
        "voices_dropped": voices_dropped,
        "chain_health": chain_health,
        "confidence_floor": confidence_floor,
        "rationale": rationale,
        "single_voice_call": voices_planned == 1,
    }
    # emit_envelope_with_status runs validate_invariants then stamps
    # status per SDD §3.2.2. Any voices_dropped[].blocker_risk == "high"
    # auto-promotes to FAILED via the hard rule in compute_verdict_status.
    return emit_envelope_with_status(envelope)


def _build_aggregate_rationale(
    *,
    voices_planned: int,
    voices_succeeded: int,
    chain_health: str,
    voices_dropped: List[Dict[str, Any]],
) -> str:
    """One-paragraph aggregate summary. NFR-Sec-4-safe (no credentials /
    endpoint URLs — only voice slugs which match ^[A-Za-z0-9._-]+$).
    Bounded to schema's max 1024 chars; truncates if many dropped voices
    push the rationale past the limit."""
    parts: List[str] = [
        f"multi-voice aggregate ({voices_succeeded}/{voices_planned} succeeded);"
        f" chain_health={chain_health}",
    ]
    if voices_dropped:
        dropped_summaries: List[str] = []
        for d in voices_dropped:
            v = str(d.get("voice", "?"))
            r = str(d.get("reason", "?"))
            br = str(d.get("blocker_risk", "?"))
            dropped_summaries.append(f"{v}({r}/{br})")
        # Bound the joined list so a 30-voice cohort with verbose entries
        # cannot push the rationale past 1024 chars (schema rejects).
        joined = ", ".join(dropped_summaries)
        if len(joined) > 800:
            joined = joined[:797] + "..."
        parts.append(f"dropped: {joined}")
    result = "; ".join(parts)
    if len(result) > 1024:
        result = result[:1021] + "..."
    return result


# ---------------------------------------------------------------------------
# CLI entry-point — bash twin (flatline-orchestrator.sh) shells out here.
# ---------------------------------------------------------------------------


def _cli_main(argv: Optional[List[str]] = None) -> int:
    """`python -m loa_cheval.verdict.aggregate <file1> <file2> ...`

    Reads each path as a single-voice envelope JSON, aggregates, and
    prints the multi-voice envelope as compact JSON to stdout.

    Exit codes:
      0   success
      2   EnvelopeInvariantViolation OR ValueError on aggregation
      3   malformed JSON input OR missing file
      64  usage error (no input files supplied)
    """
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(
        prog="loa_cheval.verdict.aggregate",
        description="Aggregate single-voice verdict_quality envelopes "
                    "into a multi-voice envelope (cycle-109 Sprint 2 T2.4)",
    )
    parser.add_argument(
        "files", nargs="*",
        help="Paths to single-voice verdict_quality envelope JSON files.",
    )
    parser.add_argument(
        "--expected-voices-count",
        type=int,
        default=None,
        help=(
            "PR #896 BB iter-1 FIND-003: pass the EXPECTED cohort size "
            "(distinct from len(files), which counts envelopes actually "
            "produced). When supplied and greater than len(files), the "
            "missing voices appear as Other-reason voices_dropped entries "
            "instead of being silently elided from voices_planned."
        ),
    )
    args = parser.parse_args(argv)

    if not args.files:
        parser.print_usage(file=sys.stderr)
        print(
            "error: at least one envelope file path is required",
            file=sys.stderr,
        )
        return 64

    envelopes: List[Dict[str, Any]] = []
    for path in args.files:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                envelopes.append(json.load(fh))
        except FileNotFoundError as e:
            print(
                f"[verdict-aggregate] file not found: {path}: {e}",
                file=sys.stderr,
            )
            return 3
        except json.JSONDecodeError as e:
            print(
                f"[verdict-aggregate] malformed JSON in {path}: {e}",
                file=sys.stderr,
            )
            return 3
        except OSError as e:
            print(
                f"[verdict-aggregate] cannot read {path}: "
                f"{type(e).__name__}: {e}",
                file=sys.stderr,
            )
            return 3

    # Lazy import here so the validation-failure exit-code path doesn't
    # need quality.py to load successfully (defensive against test envs
    # that mock the dependency).
    from .quality import EnvelopeInvariantViolation

    try:
        out = aggregate_envelopes(
            envelopes,
            expected_voices_count=args.expected_voices_count,
        )
    except EnvelopeInvariantViolation as e:
        print(f"[verdict-aggregate] invariant violation: {e}", file=sys.stderr)
        return 2
    except ValueError as e:
        print(f"[verdict-aggregate] value error: {e}", file=sys.stderr)
        return 2

    print(json.dumps(out, separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":  # pragma: no cover
    import sys
    sys.exit(_cli_main())
