"""Cycle-100 T2.3 — Multi-turn replay harness (FR-4).

Replays each `multi_turn_conditioning` vector via:

1. Load companion fixtures/replay/<vector_id>.json
2. Substitute `__FIXTURE:_make_evil_body_<id>__` placeholders with fixture
   function output (runtime payload construction per NFR-Sec1)
3. For each turn, invoke `sanitize_for_session_start` in a fresh subprocess
   (validates SUT statelessness; aggregation is harness-side per IMP-006)
4. Per-turn assertion: count_redactions(turn_stdout) == expected_per_turn[i]
5. Final-state assertion: aggregated stdout matches expected_outcome
6. Emit one audit-log entry per vector

Per-turn budget: timeout=10s aggregate per multi-turn vector (IMP-002).
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

import pytest

# Path injection — conftest sets up sys.path for `corpus_loader`; the
# fixtures dir is added by substitute_runtime_payloads on demand.
import corpus_loader

# Locate SUT and audit_writer relative to this file.
_THIS = Path(__file__).resolve()
_REPO_ROOT = _THIS.parent.parent.parent.parent
_SUT_LIB = _REPO_ROOT / ".claude/scripts/lib/context-isolation-lib.sh"
_AUDIT_LIB = _THIS.parent / "lib/audit_writer.sh"

# Marker registry — must mirror the authoritative file at
# .claude/data/lore/agent-network/jailbreak-redaction-markers.txt.
_MARKER_RE = re.compile(
    r"\[(?:TOOL-CALL-PATTERN-REDACTED|ROLE-SWITCH-PATTERN-REDACTED|CODE-FENCE-ESCAPED)\]"
)

# Cypherpunk H1 closure (Sprint 2 review): scope marker counting to the
# inside of the L2 `<untrusted-content>...</untrusted-content>` envelope so
# that future SDD revisions adding marker-name strings to the NOTE block
# don't silently inflate per-turn counts. The intent is "markers the SUT
# *injected*", not "marker-shaped substrings anywhere on stdout."
_ENVELOPE_BODY_RE = re.compile(
    r"<untrusted-content[^>]*>(.*?)</untrusted-content>", re.DOTALL
)

# Per-vector aggregate budget (NFR-Perf2 / IMP-002 ReDoS containment).
_PER_VECTOR_TIMEOUT_SEC = 10


def _count_redactions(stdout: str) -> int:
    """Count L1/L2 marker occurrences within the L2 envelope body only.

    Cypherpunk H1 closure: we deliberately do NOT scan the trailing NOTE
    block (which is fixed framing prose) so that future edits to that
    prose cannot silently shift the per-turn count contract.
    """
    body_matches = _ENVELOPE_BODY_RE.findall(stdout)
    if not body_matches:
        # Envelope absent entirely — fall back to whole-stdout scan so a
        # SUT failure that bypasses L2 wrapping is still observable.
        return len(_MARKER_RE.findall(stdout))
    return sum(len(_MARKER_RE.findall(body)) for body in body_matches)


def _invoke_sanitize_subprocess(
    content: str, source: str = "L7", turn_timeout: float = 5.0
) -> Tuple[str, str, int]:
    """Invoke sanitize_for_session_start in a fresh subprocess.

    Per SDD §4.4: each turn MUST run in a fresh subprocess to validate
    the SUT's stateless-sanitizer assumption.

    Cypherpunk H3 closure: caller-supplied `turn_timeout` (clamped to the
    smaller of 5s and the remaining aggregate budget) prevents a turn
    from running past the per-vector aggregate budget.

    Returns (stdout, stderr, exit_code).
    """
    effective_timeout = max(0.1, min(5.0, turn_timeout))
    cmd = [
        "bash",
        "-c",
        'source "$1"; sanitize_for_session_start "$2" "$3"',
        "_",
        str(_SUT_LIB),
        source,
        content,
    ]
    try:
        r = subprocess.run(
            cmd, capture_output=True, text=True, timeout=effective_timeout
        )
        return r.stdout, r.stderr, r.returncode
    except subprocess.TimeoutExpired as e:
        return "", f"TIMEOUT-REDOS-SUSPECT: turn exceeded {effective_timeout}s ({e})", 124


def _emit_audit_run_entry(
    vector_id: str, category: str, defense_layer: str, status: str, reason: str
) -> None:
    """Best-effort audit emission via the bash audit_writer. Failure is
    logged to stderr but never fails the test (audit is observability,
    not a gate)."""
    if not _AUDIT_LIB.is_file():
        return
    cmd = [
        "bash",
        "-c",
        (
            'source "$1"; audit_writer_init >/dev/null; '
            'audit_emit_run_entry "$2" "$3" "$4" "$5" "$6"'
        ),
        "_",
        str(_AUDIT_LIB),
        vector_id,
        category,
        defense_layer,
        status,
        reason,
    ]
    try:
        r = subprocess.run(
            cmd, capture_output=True, text=True, timeout=5, check=False
        )
    except (subprocess.TimeoutExpired, OSError) as e:  # pragma: no cover
        sys.stderr.write(f"audit emit failed for {vector_id}: {e}\n")
        return
    # Cypherpunk M4 closure: subprocess.run with check=False returns the
    # CompletedProcess regardless of exit code. Without an explicit
    # returncode check, a non-zero audit_writer exit (e.g., schema reject,
    # flock contention) goes silently dropped — exactly the F10 class the
    # bash side closed in Sprint 1.
    if r.returncode != 0:
        sys.stderr.write(
            f"audit emit returned non-zero ({r.returncode}) for "
            f"{vector_id}: stderr={r.stderr[:200]!r}\n"
        )
        if os.environ.get("LOA_JAILBREAK_STRICT_AUDIT") == "1":
            raise RuntimeError(
                f"audit emission failed under STRICT_AUDIT mode: "
                f"{vector_id} rc={r.returncode}"
            )


def _multi_turn_vectors() -> List[corpus_loader.Vector]:
    """Load multi_turn_conditioning vectors. Pytest parametrize wants a
    list (not a generator) so it can collect ids upfront."""
    return list(corpus_loader.iter_active(category="multi_turn_conditioning"))


def _assert_final_outcome(
    expected_outcome: str,
    final_state: str,
    last_stdout: str,
    last_exit: int,
    last_stderr: str,
) -> None:
    """Apply outcome-assertion semantics to the AGGREGATED final state per
    SDD §4.4 IMP-006. Mirrors runner.bats `assert_outcome` for single-shot."""
    if expected_outcome == "redacted":
        assert _MARKER_RE.search(final_state), (
            f"expected `redacted` final outcome but no L1/L2 marker found "
            f"in aggregated final_state (last_exit={last_exit})"
        )
    elif expected_outcome == "wrapped":
        # Last turn's stdout should be wrapped per L2; final aggregated
        # state may contain multiple wrap envelopes (one per turn).
        # Sprint-3 BB iter-2 F-001 closure: also assert the last turn's SUT
        # exit==0. Otherwise a SUT crash that still emits the envelope
        # opener+closer (e.g., partial output before fault) would satisfy
        # the substring checks while masking execution failure as a pass.
        # Mirrors runner.bats `wrapped` semantics which already check exit.
        assert last_exit == 0, (
            f"expected `wrapped` outcome with clean exit, got exit "
            f"{last_exit}; last_stderr[0..200]={last_stderr[:200]!r}"
        )
        assert "<untrusted-content" in last_stdout, (
            f"expected `wrapped` outcome: last turn stdout missing "
            f"<untrusted-content> opener"
        )
        assert "</untrusted-content>" in last_stdout, (
            f"expected `wrapped` outcome: last turn stdout missing "
            f"</untrusted-content> closer"
        )
        assert not _MARKER_RE.search(final_state), (
            f"expected `wrapped` (no L1 marker) but found one in "
            f"aggregated final_state — vector should be marked `redacted`"
        )
    elif expected_outcome == "rejected":
        assert last_exit != 0, (
            f"expected `rejected` outcome but last turn exit_code=0"
        )
        assert "BLOCKER:" in last_stderr, (
            f"expected `rejected` outcome but last turn stderr missing "
            f"BLOCKER: line"
        )
    elif expected_outcome == "passed-through-unchanged":
        # Pure-passthrough is the L2-bypass case (no wrap); not a typical
        # multi-turn outcome but support for completeness.
        # L1 closure: pin a non-empty stdout so a SUT crash producing
        # empty output does not satisfy the negation by accident.
        assert "<untrusted-content" not in last_stdout, (
            f"expected `passed-through-unchanged` but L2 envelope present"
        )
        assert last_stdout.strip() != "", (
            f"expected `passed-through-unchanged` but stdout is empty "
            f"(SUT crash?); last_exit={last_exit}, last_stderr={last_stderr[:200]!r}"
        )
    else:
        pytest.fail(f"unknown expected_outcome: {expected_outcome}")


@pytest.mark.parametrize(
    "vector",
    _multi_turn_vectors(),
    ids=lambda v: v.vector_id,
)
def test_multi_turn_vector(vector: corpus_loader.Vector) -> None:
    """Replay one multi-turn vector through the SUT.

    See module docstring for flow. Failure messages include vector_id +
    turn index + redaction-count delta per SDD §4.4 contract.
    """
    fixture = corpus_loader.load_replay_fixture(vector.vector_id)
    fixture = corpus_loader.substitute_runtime_payloads(fixture, vector)

    expected_per_turn: Optional[List[int]] = fixture.get("expected_per_turn_redactions")
    fixture_outcome = fixture.get("expected_outcome", vector.expected_outcome)
    if fixture_outcome != vector.expected_outcome:
        pytest.fail(
            f"{vector.vector_id}: replay JSON expected_outcome "
            f"({fixture_outcome!r}) does not match corpus expected_outcome "
            f"({vector.expected_outcome!r}) — author must reconcile"
        )

    aggregate_start = time.monotonic()
    actual_outputs: List[Tuple[str, str, int]] = []

    for i, turn in enumerate(fixture["turns"]):
        # Aggregate budget: enforce IMP-002 across all turns of this vector.
        # Cypherpunk H3 closure (Sprint 2 review): pass `remaining` to the
        # subprocess timeout so a turn cannot consume past the per-vector
        # budget. Previous design only checked elapsed BETWEEN turns;
        # a turn launched at elapsed=9.9s could still run for a fresh
        # 5s subprocess timeout = 14.9s total.
        elapsed = time.monotonic() - aggregate_start
        remaining = _PER_VECTOR_TIMEOUT_SEC - elapsed
        if remaining <= 0:
            _emit_audit_run_entry(
                vector.vector_id,
                vector.category,
                vector.defense_layer,
                "fail",
                f"AGGREGATE-TIMEOUT: exceeded {_PER_VECTOR_TIMEOUT_SEC}s "
                f"at turn {i}",
            )
            pytest.fail(
                f"{vector.vector_id}: aggregate per-vector budget exceeded "
                f"({_PER_VECTOR_TIMEOUT_SEC}s) at turn {i}"
            )

        stdout, stderr, exit_code = _invoke_sanitize_subprocess(
            turn["content"], turn_timeout=remaining
        )
        actual_outputs.append((stdout, stderr, exit_code))

        if expected_per_turn is not None and i < len(expected_per_turn):
            actual_count = _count_redactions(stdout)
            expected_count = expected_per_turn[i]
            if actual_count != expected_count:
                _emit_audit_run_entry(
                    vector.vector_id,
                    vector.category,
                    vector.defense_layer,
                    "fail",
                    f"PER-TURN-COUNT-MISMATCH: turn {i} expected "
                    f"{expected_count}, got {actual_count}",
                )
                pytest.fail(
                    f"{vector.vector_id} turn {i}: expected "
                    f"{expected_count} redactions, got {actual_count}\n"
                    f"  delta = {actual_count - expected_count:+d}\n"
                    f"  stdout[0..200] = {stdout[:200]!r}"
                )

    final_state = "".join(s for s, _, _ in actual_outputs)
    last_stdout, last_stderr, last_exit = actual_outputs[-1]

    try:
        _assert_final_outcome(
            vector.expected_outcome,
            final_state,
            last_stdout,
            last_exit,
            last_stderr,
        )
    except AssertionError as e:
        _emit_audit_run_entry(
            vector.vector_id,
            vector.category,
            vector.defense_layer,
            "fail",
            f"FINAL-OUTCOME-MISMATCH: {e}",
        )
        raise

    _emit_audit_run_entry(
        vector.vector_id,
        vector.category,
        vector.defense_layer,
        "pass",
        "",
    )


def test_replay_harness_module_imports() -> None:
    """Smoke test: the harness module + corpus_loader extensions import."""
    assert hasattr(corpus_loader, "load_replay_fixture")
    assert hasattr(corpus_loader, "substitute_runtime_payloads")
    assert hasattr(corpus_loader, "FixtureMissing")
    assert hasattr(corpus_loader, "ReplayFixtureMissing")
    assert _SUT_LIB.is_file(), f"SUT not found at {_SUT_LIB}"
