"""cycle-109 Sprint 4 T4.3 — aggregate_findings + IMP-006 fixtures.

Per SDD §5.4.2 conflict-resolution algorithm:

  1. Same (file, line, finding_class) → dedupe, keep highest severity,
     union evidence_anchors.
  2. Same (file, line) different class → keep both, annotate
     cross_chunk_overlap.
  3. Same class different line → keep both.
  4. Conflicting severity for same logical finding → escalate to max,
     annotate severity_escalated_from with the min severity seen.
  5. Finding spans chunk boundary → cross-chunk pass (second-stage; T4.4).

Five IMP-006 fixture cases from sprint plan §AC:

  - dedupe-same                            (case 1)
  - dedupe-different-class                 (case 2)
  - different-line-same-class              (case 3)
  - severity-escalation                    (case 4)
  - cross-chunk-overlap (annotation)       (case 5; full pass = T4.4)
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def _finding(
    id_, file_, line, finding_class, severity, *, evidence=None,
):
    """Construct a Finding for fixture use."""
    from loa_cheval.chunking import Finding

    return Finding(
        id=id_,
        file=file_,
        line=line,
        finding_class=finding_class,
        severity=severity,
        evidence_anchors=list(evidence or []),
    )


def _chunk_findings(chunk_index, files, findings):
    from loa_cheval.chunking import ChunkFindings

    return ChunkFindings(chunk_index=chunk_index, files=files, findings=findings)


# ---------------------------------------------------------------------------
# Case 1: dedupe same (file, line, finding_class)
# ---------------------------------------------------------------------------


def test_imp006_case1_dedupe_same_anchor():
    """Two chunks emit a finding at the same (file, line, class). The
    aggregator collapses them into one finding."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH"),
        ]),
        _chunk_findings(1, ["src/b.py"], [
            _finding("F2", "src/a.py", 10, "auth", "HIGH"),
        ]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.findings) == 1
    assert result.findings[0].file == "src/a.py"
    assert result.findings[0].line == 10
    assert result.findings[0].finding_class == "auth"


def test_imp006_case1_dedupe_unions_evidence_anchors():
    """Deduping preserves evidence_anchors from all instances."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH", evidence=["src/a.py:10"]),
        ]),
        _chunk_findings(1, ["src/b.py"], [
            _finding("F2", "src/a.py", 10, "auth", "HIGH", evidence=["src/a.py:11", "src/a.py:12"]),
        ]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.findings) == 1
    anchors = set(result.findings[0].evidence_anchors)
    assert anchors == {"src/a.py:10", "src/a.py:11", "src/a.py:12"}


# ---------------------------------------------------------------------------
# Case 2: same (file, line) different class
# ---------------------------------------------------------------------------


def test_imp006_case2_same_anchor_different_class_keeps_both():
    """Two findings at the same (file, line) but different
    finding_class are kept as separate findings."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH"),
            _finding("F2", "src/a.py", 10, "logging", "MED"),
        ]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.findings) == 2
    classes = {f.finding_class for f in result.findings}
    assert classes == {"auth", "logging"}


def test_imp006_case2_same_anchor_different_class_annotates_overlap():
    """Cross-class same-anchor findings populate cross_chunk_overlaps
    as informational annotation pairs."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH"),
            _finding("F2", "src/a.py", 10, "logging", "MED"),
        ]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.cross_chunk_overlaps) == 1
    pair = result.cross_chunk_overlaps[0]
    assert pair[0].file == pair[1].file == "src/a.py"
    assert pair[0].line == pair[1].line == 10
    assert pair[0].finding_class != pair[1].finding_class


# ---------------------------------------------------------------------------
# Case 3: different line same class
# ---------------------------------------------------------------------------


def test_imp006_case3_different_line_same_class_keeps_both():
    """Findings at different lines of the same file + same class are
    separate findings."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH"),
            _finding("F2", "src/a.py", 20, "auth", "HIGH"),
        ]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.findings) == 2
    lines = {f.line for f in result.findings}
    assert lines == {10, 20}


# ---------------------------------------------------------------------------
# Case 4: severity escalation
# ---------------------------------------------------------------------------


def test_imp006_case4_severity_escalation_takes_max():
    """Same (file, line, class) with different severities collapses to
    the MAX severity; severity_escalated_from records the MIN."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "LOW"),
        ]),
        _chunk_findings(1, ["src/b.py"], [
            _finding("F2", "src/a.py", 10, "auth", "BLOCKER"),
        ]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.findings) == 1
    assert result.findings[0].severity == "BLOCKER"
    assert result.findings[0].severity_escalated_from == "LOW"


def test_imp006_case4_escalation_with_three_severities():
    """Three severity inputs: max wins; severity_escalated_from = min."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [_finding("F1", "src/a.py", 10, "auth", "LOW")]),
        _chunk_findings(1, ["src/b.py"], [_finding("F2", "src/a.py", 10, "auth", "MED")]),
        _chunk_findings(2, ["src/c.py"], [_finding("F3", "src/a.py", 10, "auth", "HIGH")]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.findings) == 1
    assert result.findings[0].severity == "HIGH"
    assert result.findings[0].severity_escalated_from == "LOW"


def test_imp006_case4_no_escalation_when_all_severities_equal():
    """If all severities are the same, severity_escalated_from stays None
    (no actual escalation occurred)."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [_finding("F1", "src/a.py", 10, "auth", "HIGH")]),
        _chunk_findings(1, ["src/b.py"], [_finding("F2", "src/a.py", 10, "auth", "HIGH")]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.findings) == 1
    assert result.findings[0].severity == "HIGH"
    assert result.findings[0].severity_escalated_from is None


# ---------------------------------------------------------------------------
# Case 5: cross-chunk-overlap annotation (T4.3 scope; full pass = T4.4)
# ---------------------------------------------------------------------------


def test_imp006_case5_cross_chunk_overlap_pair_recorded():
    """When two findings overlap on (file, line) but came from different
    CHUNKS (not just different finding entries), the cross_chunk_overlaps
    list still records the pair. T4.4 fills in the second-stage review;
    T4.3 just annotates."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/a.py"], [
            _finding("F1", "src/a.py", 10, "auth", "HIGH"),
        ]),
        _chunk_findings(1, ["src/b.py"], [
            _finding("F2", "src/a.py", 10, "logging", "MED"),
        ]),
    ]
    result = aggregate_findings(per_chunk)
    assert len(result.findings) == 2
    assert len(result.cross_chunk_overlaps) == 1


# ---------------------------------------------------------------------------
# Observability counts
# ---------------------------------------------------------------------------


def test_chunks_reviewed_count_matches_input_length():
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["a.py"], [_finding("F1", "a.py", 1, "x", "HIGH")]),
        _chunk_findings(1, ["b.py"], []),
        _chunk_findings(2, ["c.py"], [_finding("F2", "c.py", 1, "x", "LOW")]),
    ]
    result = aggregate_findings(per_chunk)
    assert result.chunks_reviewed == 3


def test_chunks_with_findings_count_matches_non_empty_chunks():
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["a.py"], [_finding("F1", "a.py", 1, "x", "HIGH")]),
        _chunk_findings(1, ["b.py"], []),
        _chunk_findings(2, ["c.py"], [_finding("F2", "c.py", 1, "x", "LOW")]),
    ]
    result = aggregate_findings(per_chunk)
    assert result.chunks_with_findings == 2


def test_second_stage_invoked_false_when_no_boundary_candidates():
    """Until T4.4 lands the cross-chunk pass, second_stage_invoked
    should always be False (no boundary detection fires)."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["a.py"], [_finding("F1", "a.py", 1, "x", "HIGH")]),
    ]
    result = aggregate_findings(per_chunk)
    assert result.second_stage_invoked is False


# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------


def test_empty_per_chunk_list_returns_empty_aggregated():
    from loa_cheval.chunking.aggregate import aggregate_findings

    result = aggregate_findings([])
    assert result.findings == []
    assert result.cross_chunk_overlaps == []
    assert result.chunks_reviewed == 0
    assert result.chunks_with_findings == 0
    assert result.second_stage_invoked is False


def test_all_empty_chunks_returns_empty_findings():
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["a.py"], []),
        _chunk_findings(1, ["b.py"], []),
    ]
    result = aggregate_findings(per_chunk)
    assert result.findings == []
    assert result.chunks_reviewed == 2
    assert result.chunks_with_findings == 0


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------


def test_aggregate_findings_is_deterministic():
    """Same inputs MUST produce same outputs. Finding order in the
    output list MUST be deterministic (e.g., sorted by (file, line,
    class)) so downstream consumers can compare snapshots."""
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["src/z.py"], [_finding("F1", "src/z.py", 10, "auth", "HIGH")]),
        _chunk_findings(1, ["src/a.py"], [_finding("F2", "src/a.py", 5, "validation", "MED")]),
    ]
    first = aggregate_findings(per_chunk)
    for _ in range(3):
        again = aggregate_findings(per_chunk)
        # Compare by (file, line, class) tuples
        first_keys = [(f.file, f.line, f.finding_class) for f in first.findings]
        again_keys = [(f.file, f.line, f.finding_class) for f in again.findings]
        assert first_keys == again_keys


def test_aggregate_findings_does_not_mutate_input():
    """Inputs must not be mutated — callers may inspect per_chunk
    after aggregation."""
    import copy
    from loa_cheval.chunking.aggregate import aggregate_findings

    per_chunk = [
        _chunk_findings(0, ["a.py"], [_finding("F1", "a.py", 1, "x", "HIGH")]),
    ]
    snapshot = copy.deepcopy(per_chunk)
    _ = aggregate_findings(per_chunk)
    # Compare the snapshot against the post-call state field-by-field.
    assert len(per_chunk) == len(snapshot)
    assert per_chunk[0].findings[0].id == snapshot[0].findings[0].id
    assert per_chunk[0].findings[0].severity == snapshot[0].findings[0].severity
