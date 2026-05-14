"""cycle-109 Sprint 4 T4.1 — chunking package scaffold tests.

Pins the type-contract surface that T4.2-T4.4 fill in: types are
importable + constructable, stub functions exist with the documented
signatures, NotImplementedError fires for T4.2-T4.4 paths.

After T4.2-T4.4 land, the NotImplementedError tests flip to behavior
tests; the type-contract tests stay (and serve as a regression guard
against accidental schema breakage).
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# Package importability
# ---------------------------------------------------------------------------


def test_chunking_package_is_importable():
    """T4.1: the package itself + the type re-exports load cleanly."""
    import loa_cheval.chunking  # noqa: F401
    from loa_cheval.chunking import (  # noqa: F401
        Chunk,
        ChunkFindings,
        AggregatedFindings,
        Finding,
        SEVERITY_RANK,
    )


def test_chunker_module_is_importable():
    from loa_cheval.chunking import chunker  # noqa: F401


def test_aggregate_module_is_importable():
    from loa_cheval.chunking import aggregate  # noqa: F401


# ---------------------------------------------------------------------------
# Type contract: Finding
# ---------------------------------------------------------------------------


def test_finding_has_required_minimum_fields():
    from loa_cheval.chunking import Finding

    f = Finding(
        id="IMP-001",
        file="src/auth.ts",
        line=42,
        finding_class="null-safety",
        severity="BLOCKER",
    )
    assert f.id == "IMP-001"
    assert f.file == "src/auth.ts"
    assert f.line == 42
    assert f.finding_class == "null-safety"
    assert f.severity == "BLOCKER"


def test_finding_aggregation_fields_default_to_neutral():
    """Aggregation-time fields default to neutral values so producer-side
    code can construct a Finding before aggregation runs."""
    from loa_cheval.chunking import Finding

    f = Finding(id="x", file="y", line=1, finding_class="z", severity="LOW")
    assert f.description == ""
    assert f.evidence_anchors == []
    assert f.severity_escalated_from is None
    assert f.cross_chunk_pass is False
    assert f.chunk_indices == []


def test_finding_supports_evidence_anchors_list():
    from loa_cheval.chunking import Finding

    f = Finding(
        id="x", file="y", line=1, finding_class="z", severity="HIGH",
        evidence_anchors=["src/foo.py:10", "src/bar.py:20"],
    )
    assert len(f.evidence_anchors) == 2


# ---------------------------------------------------------------------------
# Type contract: Chunk
# ---------------------------------------------------------------------------


def test_chunk_has_required_fields():
    from loa_cheval.chunking import Chunk

    c = Chunk(
        chunk_index=0,
        files=["src/a.py", "src/b.py"],
        content="...",
    )
    assert c.chunk_index == 0
    assert c.files == ["src/a.py", "src/b.py"]
    assert c.content == "..."
    assert c.shared_header == ""
    assert c.estimated_tokens == 0


# ---------------------------------------------------------------------------
# Type contract: ChunkFindings + AggregatedFindings
# ---------------------------------------------------------------------------


def test_chunk_findings_has_required_fields():
    from loa_cheval.chunking import ChunkFindings

    cf = ChunkFindings(chunk_index=2, files=["src/x.py"])
    assert cf.chunk_index == 2
    assert cf.files == ["src/x.py"]
    assert cf.findings == []


def test_aggregated_findings_defaults_are_neutral():
    from loa_cheval.chunking import AggregatedFindings

    af = AggregatedFindings()
    assert af.findings == []
    assert af.cross_chunk_overlaps == []
    assert af.chunks_reviewed == 0
    assert af.chunks_with_findings == 0
    assert af.second_stage_invoked is False


# ---------------------------------------------------------------------------
# SEVERITY_RANK monotonicity (load-bearing for aggregation severity-escalation)
# ---------------------------------------------------------------------------


def test_severity_rank_is_monotonic_blocker_to_info():
    from loa_cheval.chunking import SEVERITY_RANK

    assert (
        SEVERITY_RANK["BLOCKER"]
        > SEVERITY_RANK["HIGH"]
        > SEVERITY_RANK["MED"]
        > SEVERITY_RANK["LOW"]
        > SEVERITY_RANK["INFO"]
    )


def test_severity_rank_aliases_match_canonical_form():
    from loa_cheval.chunking import SEVERITY_RANK

    # Aliases must rank-equivalent to their canonical name
    assert SEVERITY_RANK["BLOCKING"] == SEVERITY_RANK["BLOCKER"]
    assert SEVERITY_RANK["MEDIUM"] == SEVERITY_RANK["MED"]
    assert SEVERITY_RANK["ADVISORY"] == SEVERITY_RANK["LOW"]


def test_severity_rank_praise_is_lowest():
    """PRAISE findings (T2.6 BB enrichment surface) should rank below
    INFO so aggregation never escalates a real concern UP to PRAISE."""
    from loa_cheval.chunking import SEVERITY_RANK

    assert SEVERITY_RANK["PRAISE"] < SEVERITY_RANK["INFO"]


# ---------------------------------------------------------------------------
# Stub signatures: confirm NotImplementedError fires (T4.2-T4.4 RED)
# ---------------------------------------------------------------------------


def test_chunk_pr_for_review_is_stubbed_for_t4_2():
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    with pytest.raises(NotImplementedError) as excinfo:
        chunk_pr_for_review("input", 1000)
    assert "T4.2" in str(excinfo.value)


def test_aggregate_findings_is_stubbed_for_t4_3():
    from loa_cheval.chunking.aggregate import aggregate_findings

    with pytest.raises(NotImplementedError) as excinfo:
        aggregate_findings([])
    assert "T4.3" in str(excinfo.value)


def test_detect_boundary_findings_is_stubbed_for_t4_4():
    from loa_cheval.chunking.aggregate import detect_boundary_findings

    with pytest.raises(NotImplementedError) as excinfo:
        detect_boundary_findings([], [])
    assert "T4.4" in str(excinfo.value)


def test_second_stage_review_is_stubbed_for_t4_4():
    from loa_cheval.chunking.aggregate import second_stage_review

    with pytest.raises(NotImplementedError) as excinfo:
        second_stage_review([])
    assert "T4.4" in str(excinfo.value)


def test_merge_with_second_stage_is_stubbed_for_t4_4():
    from loa_cheval.chunking.aggregate import merge_with_second_stage

    with pytest.raises(NotImplementedError) as excinfo:
        merge_with_second_stage([], [])
    assert "T4.4" in str(excinfo.value)


# ---------------------------------------------------------------------------
# Stub signature shape (positional + keyword args match the SDD spec)
# ---------------------------------------------------------------------------


def test_chunk_pr_for_review_signature_accepts_documented_kwargs():
    """SDD §5.4.1: signature accepts shared_header + chunks_max kwargs.
    Even though impl is stubbed, the signature must be the canonical
    one so callers don't need to migrate when T4.2 lands."""
    import inspect
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    sig = inspect.signature(chunk_pr_for_review)
    params = sig.parameters
    assert "input_text" in params
    assert "effective_input_ceiling" in params
    assert "shared_header" in params
    assert "chunks_max" in params
    # chunks_max default = 16 per SDD §5.4.1
    assert params["chunks_max"].default == 16


def test_aggregate_findings_signature_accepts_per_chunk_list():
    import inspect
    from loa_cheval.chunking.aggregate import aggregate_findings

    sig = inspect.signature(aggregate_findings)
    assert "per_chunk" in sig.parameters
