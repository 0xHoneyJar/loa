"""cycle-109 Sprint 4 T4.1 scaffold — aggregation API stubs.

T4.3 fills in ``aggregate_findings`` with the IMP-006 conflict-resolution
algorithm per SDD §5.4.2. T4.4 fills in ``detect_boundary_findings`` +
``second_stage_review`` + ``merge_with_second_stage`` per SDD §5.4.3.
"""

from __future__ import annotations

from typing import List

from .types import AggregatedFindings, ChunkFindings, Finding


def aggregate_findings(per_chunk: List[ChunkFindings]) -> AggregatedFindings:
    """Conflict-resolution aggregation per SDD §5.4.2 IMP-006.

    Algorithm (T4.3 will fill in):

      1. Index findings by ``(file, line)`` location.
      2. For each location, group by ``finding_class``:
         a. Same (file, line, class): dedupe; keep highest severity;
            union evidence_anchors.
         b. Severity-escalation: max(severities); annotate
            ``severity_escalated_from`` with the min.
      3. Cross-class same-anchor: keep both findings; annotate the pair
         in ``cross_chunk_overlaps``.
      4. Cross-chunk pass (T4.4): detect boundary-spanning candidates;
         if any, invoke ``second_stage_review`` and merge.

    Args:
      per_chunk: list of ``ChunkFindings``, one per chunk fed through
        the model. Empty findings within a chunk are valid (chunk
        reviewed-clean).

    Returns:
      ``AggregatedFindings`` with deduped + escalated finding set,
      cross-chunk overlap annotations, and observability counts
      (``chunks_reviewed`` / ``chunks_with_findings`` /
      ``second_stage_invoked``).

    Raises:
      NotImplementedError: T4.1 scaffold; T4.3 fills in.
    """
    raise NotImplementedError(
        "aggregate_findings is T4.3 work; T4.1 ships only the scaffold "
        "+ type signatures. See SDD §5.4.2 for the IMP-006 conflict-"
        "resolution algorithm spec."
    )


def detect_boundary_findings(
    aggregated: List[Finding],
    per_chunk: List[ChunkFindings],
) -> List[Finding]:
    """Identify findings whose evidence may span a chunk boundary.

    Args:
      aggregated: post-IMP-006 aggregated findings.
      per_chunk: original per-chunk finding sets (file-set metadata
        used to detect boundary-spanning anchors).

    Returns:
      Subset of ``aggregated`` whose ``(file, line)`` anchors sit at or
      near a chunk boundary, suggesting evidence may span the cut.
      Empty list when no boundary candidates exist.

    Raises:
      NotImplementedError: T4.1 scaffold; T4.4 fills in.
    """
    raise NotImplementedError(
        "detect_boundary_findings is T4.4 work; T4.1 ships only the "
        "scaffold + type signatures. See SDD §5.4.3 for the cross-chunk "
        "pass mechanism spec."
    )


def second_stage_review(
    boundary_candidates: List[Finding],
) -> List[Finding]:
    """Re-dispatch the boundary-spanning candidates as a synthetic
    combined chunk (size bounded to ``effective_input_ceiling × 0.4``).

    Per SDD §5.4.3 boundedness: at most ONCE per chunked call (no
    recursive cross-chunk-of-cross-chunk).

    Args:
      boundary_candidates: output of ``detect_boundary_findings``.

    Returns:
      Findings emitted by the second-stage cheval call, all with
      ``cross_chunk_pass = True``.

    Raises:
      NotImplementedError: T4.1 scaffold; T4.4 fills in.
    """
    raise NotImplementedError(
        "second_stage_review is T4.4 work; T4.1 ships only the scaffold "
        "+ type signatures. See SDD §5.4.3 for the synthetic-combined-"
        "chunk mechanism."
    )


def merge_with_second_stage(
    aggregated: List[Finding],
    second_stage: List[Finding],
) -> List[Finding]:
    """Fold ``second_stage`` findings into ``aggregated``, annotating
    the merged set's provenance.

    Same conflict-resolution rules as ``aggregate_findings`` apply to
    the merged set; second-stage findings with ``cross_chunk_pass=True``
    keep that flag through the merge.

    Args:
      aggregated: pre-merge aggregated findings.
      second_stage: cross-chunk pass output.

    Returns:
      Merged finding set with overlap pairs / severity escalations as
      ``aggregate_findings`` would have produced if the second-stage
      findings had been part of the original ``per_chunk`` input.

    Raises:
      NotImplementedError: T4.1 scaffold; T4.4 fills in.
    """
    raise NotImplementedError(
        "merge_with_second_stage is T4.4 work; T4.1 ships only the "
        "scaffold + type signatures."
    )
