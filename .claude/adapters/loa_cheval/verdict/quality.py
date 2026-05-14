"""cycle-109 Sprint 2 T2.2 — verdict-quality classifier (SDD §3.2.2).

Single canonical writer of ``verdict_quality.status`` per the SDD §3.2.2
classification contract:

  APPROVED:
    voices_succeeded == voices_planned
    AND chain_health == "ok"
    AND consensus_outcome == "consensus"
    AND every voices_dropped[].blocker_risk ∈ {unknown, low}
    AND chunks_dropped == 0

  DEGRADED:
    0 < voices_succeeded < voices_planned
    AND consensus_outcome == "consensus"
    AND no dropped voice carries blocker_risk = high
    AND chunks_dropped == 0

  FAILED (auto-promotion — any of):
    voices_succeeded == 0
    OR chain_health == "exhausted"
    OR consensus_outcome == "impossible"
    OR any voices_dropped[].blocker_risk == "high"
    OR chunks_dropped > 0 (unless truncation_waiver_applied == True;
                            v5 SKP-001 break-glass per SDD §4.1.3)

Producer-side invariants (v5 SKP-005 closure) enforced by
``validate_invariants`` BEFORE classification:

  - voices_planned >= 1
  - 0 <= voices_succeeded <= voices_planned
  - len(voices_succeeded_ids) == voices_succeeded
  - voices_succeeded_ids entries unique
  - NO voice slug in BOTH voices_succeeded_ids AND voices_dropped[].voice
  - len(voices_dropped) == voices_planned - voices_succeeded

Single producer entry-point (v5 SKP-003 closure): every emission path
(success + error envelopes per SDD §6.2; one per exit code) MUST flow
through ``emit_envelope_with_status`` so the status field is never
absent and never re-derived in caller code.

The bash twin at ``.claude/scripts/lib/verdict-quality.sh`` shells out
to this module via ``python -m loa_cheval.verdict.quality compute --json``
— no logic duplication; drift is impossible by construction per SDD §5.2.1.
"""

from __future__ import annotations

from typing import Any, Dict, List


_STATUS_APPROVED = "APPROVED"
_STATUS_DEGRADED = "DEGRADED"
_STATUS_FAILED = "FAILED"

_BLOCKER_RISK_HIGH = "high"
_BLOCKER_RISK_MED = "med"

_CHAIN_HEALTH_OK = "ok"
_CHAIN_HEALTH_EXHAUSTED = "exhausted"

_CONSENSUS_OUTCOME_CONSENSUS = "consensus"
_CONSENSUS_OUTCOME_IMPOSSIBLE = "impossible"


class EnvelopeInvariantViolation(ValueError):
    """Raised by ``validate_invariants`` when a producer-side cross-field
    invariant is violated. v5 SKP-005 closure: malformed envelopes are
    rejected BEFORE classification rather than producing a misleading
    status that consumers would then read.
    """


def validate_invariants(envelope: Dict[str, Any]) -> None:
    """Run producer-side cross-field invariants. Raises
    ``EnvelopeInvariantViolation`` with a stable message identifier on
    the first failure (callers route per message-prefix).

    Invariants per SDD §3.2.2 + v5 SKP-005 + v6 SKP-003:

      INV-1  voices_planned >= 1
      INV-2  0 <= voices_succeeded <= voices_planned
      INV-3  len(voices_succeeded_ids) == voices_succeeded
      INV-4  voices_succeeded_ids entries unique
      INV-5  NO voice slug in BOTH voices_succeeded_ids AND voices_dropped[].voice
      INV-6  len(voices_dropped) == voices_planned - voices_succeeded
    """
    voices_planned = envelope.get("voices_planned")
    voices_succeeded = envelope.get("voices_succeeded")
    voices_succeeded_ids = envelope.get("voices_succeeded_ids") or []
    voices_dropped = envelope.get("voices_dropped") or []

    if not isinstance(voices_planned, int) or voices_planned < 1:
        raise EnvelopeInvariantViolation(
            f"INV-1: voices_planned must be int >= 1; got {voices_planned!r}"
        )
    if not isinstance(voices_succeeded, int) or voices_succeeded < 0:
        raise EnvelopeInvariantViolation(
            f"INV-2: voices_succeeded must be int >= 0; got {voices_succeeded!r}"
        )
    if voices_succeeded > voices_planned:
        raise EnvelopeInvariantViolation(
            f"INV-2: voices_succeeded ({voices_succeeded}) exceeds "
            f"voices_planned ({voices_planned})"
        )

    if len(voices_succeeded_ids) != voices_succeeded:
        raise EnvelopeInvariantViolation(
            f"INV-3: len(voices_succeeded_ids)={len(voices_succeeded_ids)} "
            f"does not match voices_succeeded={voices_succeeded}"
        )

    if len(set(voices_succeeded_ids)) != len(voices_succeeded_ids):
        # Find the duplicate(s) for the error message.
        seen = set()
        dups: List[str] = []
        for vid in voices_succeeded_ids:
            if vid in seen:
                dups.append(vid)
            seen.add(vid)
        raise EnvelopeInvariantViolation(
            f"INV-4: voices_succeeded_ids contains duplicates: {dups!r}"
        )

    dropped_voice_set = {
        d.get("voice") for d in voices_dropped if isinstance(d, dict)
    }
    overlap = dropped_voice_set & set(voices_succeeded_ids)
    if overlap:
        raise EnvelopeInvariantViolation(
            f"INV-5: voice(s) appear in BOTH voices_succeeded_ids AND "
            f"voices_dropped[].voice: {sorted(overlap)!r}"
        )

    expected_dropped = voices_planned - voices_succeeded
    if len(voices_dropped) != expected_dropped:
        raise EnvelopeInvariantViolation(
            f"INV-6: len(voices_dropped)={len(voices_dropped)} does not match "
            f"voices_planned - voices_succeeded = {expected_dropped}"
        )


def compute_verdict_status(envelope: Dict[str, Any]) -> str:
    """Return the canonical status string for the envelope per SDD §3.2.2.

    This function is the SOLE canonical writer of the verdict_quality.status
    field (SKP-001 closure). Consumers MUST read status from envelopes
    rather than re-derive it from sub-fields; the consumer-lint
    ``tools/lint-verdict-consumers.py`` (Sprint 2 T2.8) enforces this.

    The function does NOT call ``validate_invariants`` — callers should
    use ``emit_envelope_with_status`` for the validated producer path,
    or call ``validate_invariants`` separately. This separation exists
    so consumers reading a third-party envelope can compute the status
    they expect to see (defensive reconciliation) without re-raising on
    upstream-side invariant violations.

    Returns: one of ``"APPROVED"``, ``"DEGRADED"``, ``"FAILED"``.
    """
    voices_planned = int(envelope.get("voices_planned") or 0)
    voices_succeeded = int(envelope.get("voices_succeeded") or 0)
    voices_dropped = envelope.get("voices_dropped") or []
    chain_health = envelope.get("chain_health", _CHAIN_HEALTH_OK)
    consensus_outcome = envelope.get(
        "consensus_outcome", _CONSENSUS_OUTCOME_CONSENSUS,
    )
    chunks_dropped = int(envelope.get("chunks_dropped") or 0)
    truncation_waiver_applied = bool(
        envelope.get("truncation_waiver_applied", False)
    )

    # FAILED auto-promotion paths (any one triggers FAILED).
    if voices_succeeded == 0:
        return _STATUS_FAILED
    if chain_health == _CHAIN_HEALTH_EXHAUSTED:
        return _STATUS_FAILED
    if consensus_outcome == _CONSENSUS_OUTCOME_IMPOSSIBLE:
        return _STATUS_FAILED
    for entry in voices_dropped:
        if isinstance(entry, dict) and entry.get("blocker_risk") == _BLOCKER_RISK_HIGH:
            return _STATUS_FAILED
    if chunks_dropped > 0 and not truncation_waiver_applied:
        return _STATUS_FAILED

    # APPROVED conditions (all must hold; chunks_dropped > 0 is acceptable
    # iff truncation_waiver_applied per v5 SKP-001).
    full_success = voices_succeeded == voices_planned
    chain_ok = chain_health == _CHAIN_HEALTH_OK
    consensus_ok = consensus_outcome == _CONSENSUS_OUTCOME_CONSENSUS
    # The FAILED check above ruled out any high-risk drops; the APPROVED
    # check additionally requires no med-risk drops.
    no_med_drops = not any(
        isinstance(d, dict) and d.get("blocker_risk") == _BLOCKER_RISK_MED
        for d in voices_dropped
    )
    chunks_clean = chunks_dropped == 0 or truncation_waiver_applied

    if full_success and chain_ok and consensus_ok and no_med_drops and chunks_clean:
        return _STATUS_APPROVED

    # Anything that survived FAILED auto-promotion and didn't make APPROVED
    # is DEGRADED. Per SDD §3.2.2 row 2 this requires partial success +
    # consensus + no high-risk drops + chunks_clean — which is what the
    # remaining state must satisfy (FAILED ruled out high-risk + impossible
    # + zero-succeeded + chunks_dropped-without-waiver).
    return _STATUS_DEGRADED


def emit_envelope_with_status(envelope: Dict[str, Any]) -> Dict[str, Any]:
    """Single producer entry-point per v5 SKP-003 closure.

    Pipeline:
      1. ``validate_invariants`` — raises ``EnvelopeInvariantViolation``
         on malformed input. Producer MUST NOT emit an unvalidated envelope.
      2. ``compute_verdict_status`` — writes the canonical status field.
      3. Return the mutated envelope (the input dict is mutated in-place
         AND returned; callers can rely on either reference).

    Error paths (SDD §6.2) flow through this same function with the same
    invariant-then-classify ordering; the consumer-lint
    ``tools/lint-verdict-producers.py`` (Sprint 2 T2.8) blocks emission
    paths that bypass this helper.
    """
    validate_invariants(envelope)
    envelope["status"] = compute_verdict_status(envelope)
    return envelope


# ---------------------------------------------------------------------------
# CLI entry-point — bash twin shells out here for byte-identical behavior.
# ---------------------------------------------------------------------------


def _cli_main(argv: List[str] | None = None) -> int:
    """`python -m loa_cheval.verdict.quality compute < envelope.json` →
    prints the status string to stdout. Bash twin
    .claude/scripts/lib/verdict-quality.sh uses this as a subprocess.

    `python -m loa_cheval.verdict.quality emit < envelope.json` → prints
    the validated + status-stamped envelope as JSON to stdout.

    Exit codes:
      0 success
      2 EnvelopeInvariantViolation
      3 malformed JSON input
      64 usage error
    """
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(
        prog="loa_cheval.verdict.quality",
        description="Verdict-quality classifier (cycle-109 Sprint 2 T2.2)",
    )
    parser.add_argument(
        "subcommand", choices=("compute", "emit"),
        help="compute: print status to stdout; emit: print validated envelope",
    )
    args = parser.parse_args(argv)

    try:
        envelope = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"[verdict-quality] malformed JSON input: {e}", file=sys.stderr)
        return 3

    if args.subcommand == "compute":
        try:
            status = compute_verdict_status(envelope)
        except Exception as e:  # pragma: no cover - defensive
            print(f"[verdict-quality] compute failed: {e}", file=sys.stderr)
            return 2
        print(status)
        return 0

    # subcommand == "emit"
    try:
        out = emit_envelope_with_status(envelope)
    except EnvelopeInvariantViolation as e:
        print(f"[verdict-quality] invariant violation: {e}", file=sys.stderr)
        return 2
    print(json.dumps(out, separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":  # pragma: no cover
    import sys
    sys.exit(_cli_main())
