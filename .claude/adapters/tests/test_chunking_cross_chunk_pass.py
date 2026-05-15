"""cycle-109 Sprint 4 T4.4 — cross-chunk pass mechanism tests.

Per SDD §5.4.3:

  1. detect_boundary_findings: identify findings whose evidence_anchors
     span >1 chunk (e.g., shell-injection sanitizer in chunk N, sink in
     chunk N+1).
  2. second_stage_review: build synthetic combined chunk from spanning
     slices; re-dispatch through cheval; bounded ONCE per call; size ≤
     effective_input_ceiling × 0.4.
  3. merge_with_second_stage: fold findings back; annotate
     cross_chunk_pass=true + chunk_indices set.

T4.4 must remain TESTABLE without a live cheval invocation — tests
inject a fixture dispatch function. Production uses the default
cheval-shelling-out impl.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def _finding(id_, file_, line, finding_class, severity, *, evidence=None,
             chunk_indices=None, cross_chunk_pass=False):
    from loa_cheval.chunking import Finding

    return Finding(
        id=id_,
        file=file_,
        line=line,
        finding_class=finding_class,
        severity=severity,
        evidence_anchors=list(evidence or []),
        chunk_indices=list(chunk_indices or []),
        cross_chunk_pass=cross_chunk_pass,
    )


def _chunk_findings(chunk_index, files, findings):
    from loa_cheval.chunking import ChunkFindings
    return ChunkFindings(chunk_index=chunk_index, files=files, findings=findings)


# ---------------------------------------------------------------------------
# detect_boundary_findings
# ---------------------------------------------------------------------------


def test_detect_boundary_no_candidates_when_anchors_stay_within_chunk():
    """A finding whose evidence_anchors all reference files in ONE chunk
    is not a boundary candidate."""
    from loa_cheval.chunking.aggregate import detect_boundary_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py", "src/b.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH",
                     evidence=["src/a.py:10", "src/b.py:5"]),
        ]),
        _chunk_findings(1, ["src/c.py"], []),
    ]
    aggregated = list(per_chunk[0].findings)
    candidates = detect_boundary_findings(aggregated, per_chunk)
    assert candidates == []


def test_detect_boundary_candidate_when_anchors_span_chunks():
    """A finding whose evidence_anchors reference files across multiple
    chunks IS a boundary candidate."""
    from loa_cheval.chunking.aggregate import detect_boundary_findings

    per_chunk = [
        _chunk_findings(0, ["src/sanitizer.py"], [
            _finding("F1", "src/sink.py", 42, "shell-injection", "BLOCKER",
                     evidence=["src/sanitizer.py:10", "src/sink.py:42"]),
        ]),
        _chunk_findings(1, ["src/sink.py"], []),
    ]
    aggregated = list(per_chunk[0].findings)
    candidates = detect_boundary_findings(aggregated, per_chunk)
    assert len(candidates) == 1
    assert candidates[0].id == "F1"


def test_detect_boundary_no_evidence_anchors_is_not_a_candidate():
    """Findings with no evidence_anchors can't span chunks (no signal)."""
    from loa_cheval.chunking.aggregate import detect_boundary_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH", evidence=[]),
        ]),
    ]
    candidates = detect_boundary_findings(per_chunk[0].findings, per_chunk)
    assert candidates == []


def test_detect_boundary_anchor_in_missing_chunk_is_not_a_candidate():
    """Evidence anchors that reference files NOT present in any chunk
    don't trigger boundary detection — only cross-chunk-confirmed
    spans qualify."""
    from loa_cheval.chunking.aggregate import detect_boundary_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH",
                     evidence=["src/a.py:10", "src/elsewhere.py:5"]),
        ]),
    ]
    candidates = detect_boundary_findings(per_chunk[0].findings, per_chunk)
    # src/elsewhere.py is not in any chunk → no boundary span detected
    assert candidates == []


def test_detect_boundary_anchor_path_with_line_suffix_parses():
    """Evidence anchors use the canonical `path:line` form. The detector
    parses the path portion (everything before the last `:`) so the
    chunk-membership lookup works."""
    from loa_cheval.chunking.aggregate import detect_boundary_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH",
                     evidence=["src/a.py:10", "src/b.py:20"]),
        ]),
        _chunk_findings(1, ["src/b.py"], []),
    ]
    candidates = detect_boundary_findings(per_chunk[0].findings, per_chunk)
    assert len(candidates) == 1


# ---------------------------------------------------------------------------
# second_stage_review
# ---------------------------------------------------------------------------


def test_second_stage_review_empty_input_returns_empty():
    from loa_cheval.chunking.aggregate import second_stage_review

    assert second_stage_review([]) == []


def test_second_stage_review_calls_dispatch_fn_with_synthetic_chunk():
    """second_stage_review builds a synthetic combined chunk from the
    boundary candidates' evidence + re-dispatches through cheval. Tests
    inject a fixture dispatch_fn to avoid live model calls."""
    from loa_cheval.chunking.aggregate import second_stage_review

    boundary = [
        _finding("F1", "src/sink.py", 42, "shell-injection", "BLOCKER",
                 evidence=["src/sanitizer.py:10", "src/sink.py:42"]),
    ]

    captured = {}

    def fake_dispatch(input_text: str) -> list:
        captured["input_text"] = input_text
        # Return a "confirmed" second-stage finding
        return [
            _finding("F1-stage2", "src/sink.py", 42, "shell-injection",
                     "BLOCKER", evidence=["src/sanitizer.py:10", "src/sink.py:42"]),
        ]

    result = second_stage_review(boundary, dispatch_fn=fake_dispatch)
    # Dispatch was called
    assert "input_text" in captured
    # Every returned finding carries cross_chunk_pass=True
    assert len(result) == 1
    assert result[0].cross_chunk_pass is True


def test_second_stage_review_dispatch_fn_failure_returns_empty():
    """If the dispatch fn raises (cheval error, network glitch), the
    second-stage gracefully returns empty rather than aborting the
    aggregation pipeline."""
    from loa_cheval.chunking.aggregate import second_stage_review

    boundary = [
        _finding("F1", "src/sink.py", 42, "auth", "HIGH",
                 evidence=["src/a.py:1", "src/b.py:2"]),
    ]

    def failing_dispatch(input_text: str) -> list:
        raise RuntimeError("simulated cheval failure")

    result = second_stage_review(boundary, dispatch_fn=failing_dispatch)
    assert result == []


def test_second_stage_review_bounded_once_per_call():
    """Per SDD §5.4.3: second-stage runs at most ONCE per chunked call.
    The dispatch_fn invocation count for a non-trivial candidate list
    is exactly 1 (one synthetic combined chunk for all candidates)."""
    from loa_cheval.chunking.aggregate import second_stage_review

    boundary = [
        _finding("F1", "src/a.py", 10, "x", "HIGH", evidence=["src/a.py:1"]),
        _finding("F2", "src/b.py", 20, "y", "MED", evidence=["src/b.py:1"]),
        _finding("F3", "src/c.py", 30, "z", "LOW", evidence=["src/c.py:1"]),
    ]

    call_count = {"n": 0}

    def counting_dispatch(input_text: str) -> list:
        call_count["n"] += 1
        return []

    second_stage_review(boundary, dispatch_fn=counting_dispatch)
    assert call_count["n"] == 1


# ---------------------------------------------------------------------------
# merge_with_second_stage
# ---------------------------------------------------------------------------


def test_merge_with_empty_second_stage_returns_aggregated_unchanged():
    from loa_cheval.chunking.aggregate import merge_with_second_stage

    aggregated = [
        _finding("F1", "src/a.py", 10, "auth", "HIGH"),
    ]
    merged = merge_with_second_stage(aggregated, [])
    assert len(merged) == 1
    assert merged[0].id == "F1"


def test_merge_appends_new_second_stage_findings():
    """Second-stage findings at a NEW anchor get appended to the
    aggregated set, carrying cross_chunk_pass=True."""
    from loa_cheval.chunking.aggregate import merge_with_second_stage

    aggregated = [
        _finding("F1", "src/a.py", 10, "auth", "HIGH"),
    ]
    second = [
        _finding("F2", "src/b.py", 20, "shell-injection", "BLOCKER",
                 cross_chunk_pass=True),
    ]
    merged = merge_with_second_stage(aggregated, second)
    assert len(merged) == 2
    ccp_findings = [f for f in merged if f.cross_chunk_pass]
    assert len(ccp_findings) == 1
    assert ccp_findings[0].id == "F2"


def test_merge_dedupes_overlapping_findings():
    """If second-stage CONFIRMS an aggregated finding (same file, line,
    class), the merged result keeps ONE copy with cross_chunk_pass=True
    and the highest severity."""
    from loa_cheval.chunking.aggregate import merge_with_second_stage

    aggregated = [
        _finding("F1", "src/sink.py", 42, "shell-injection", "MED"),
    ]
    second = [
        _finding("F1-stage2", "src/sink.py", 42, "shell-injection",
                 "BLOCKER", cross_chunk_pass=True),
    ]
    merged = merge_with_second_stage(aggregated, second)
    assert len(merged) == 1
    assert merged[0].severity == "BLOCKER"
    assert merged[0].cross_chunk_pass is True


def test_merge_severity_escalation_applies_to_second_stage_too():
    """If aggregated says MED at an anchor and second-stage says HIGH,
    the merged finding gets HIGH severity + severity_escalated_from."""
    from loa_cheval.chunking.aggregate import merge_with_second_stage

    aggregated = [
        _finding("F1", "src/x.py", 10, "auth", "MED"),
    ]
    second = [
        _finding("F1-s2", "src/x.py", 10, "auth", "HIGH",
                 cross_chunk_pass=True),
    ]
    merged = merge_with_second_stage(aggregated, second)
    assert len(merged) == 1
    assert merged[0].severity == "HIGH"
    assert merged[0].severity_escalated_from == "MED"


# ---------------------------------------------------------------------------
# Integration: aggregate_findings with T4.4 unblocked
# ---------------------------------------------------------------------------


def test_aggregate_findings_invokes_second_stage_when_candidates_present(monkeypatch):
    """End-to-end: aggregate_findings should detect a cross-chunk
    candidate, invoke second_stage_review, merge results, and flip
    second_stage_invoked=True."""
    from loa_cheval.chunking import aggregate as agg

    per_chunk = [
        _chunk_findings(0, ["src/sanitizer.py"], [
            _finding("F1", "src/sink.py", 42, "shell-injection", "MED",
                     evidence=["src/sanitizer.py:10", "src/sink.py:42"]),
        ]),
        _chunk_findings(1, ["src/sink.py"], []),
    ]

    # Inject fixture dispatch via monkeypatch so the production default
    # (cheval-shell-out) is replaced for the test.
    def fake_dispatch(input_text: str) -> list:
        return [
            _finding("F1-s2", "src/sink.py", 42, "shell-injection",
                     "BLOCKER", cross_chunk_pass=True),
        ]

    monkeypatch.setattr(agg, "_default_dispatch_fn", fake_dispatch, raising=False)

    result = agg.aggregate_findings(per_chunk)
    assert result.second_stage_invoked is True
    # The escalated finding is in the merged set
    boundary_finding = next(
        (f for f in result.findings if f.file == "src/sink.py"), None,
    )
    assert boundary_finding is not None
    # Severity should escalate from MED → BLOCKER via the second-stage
    assert boundary_finding.severity == "BLOCKER"


def test_aggregate_findings_no_boundary_keeps_second_stage_invoked_false():
    """When no findings span chunk boundaries, second_stage_invoked stays
    False — the cross-chunk pass is skipped."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH",
                     evidence=["src/a.py:10"]),
        ]),
    ]
    result = aggregate_findings(per_chunk)
    assert result.second_stage_invoked is False
