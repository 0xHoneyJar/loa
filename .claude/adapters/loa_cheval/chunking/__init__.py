"""cycle-109 Sprint 4 — hierarchical / chunked review for large inputs (FR-4).

Closes KF-002 layer-1 structurally: when input exceeds a model's
``effective_input_ceiling``, cheval chunks the review, aggregates findings
with conflict resolution, and runs a cross-chunk pass for boundary-
spanning findings — instead of empty-contenting empirically and
producing KF-002-class incidents.

Public API (full impl across T4.2-T4.4):

  chunk_pr_for_review(input, ceiling)            -> list[Chunk]
  aggregate_findings(per_chunk: list[ChunkFindings]) -> AggregatedFindings
  detect_boundary_findings(aggregated, per_chunk) -> list[Finding]
  second_stage_review(boundary_candidates)        -> list[Finding]
  merge_with_second_stage(aggregated, second_stage) -> list[Finding]

T4.1 scaffolding: type definitions + stub functions that raise
NotImplementedError until the matching subsequent tasks fill them in.
"""

from .types import (
    Chunk,
    ChunkFindings,
    AggregatedFindings,
    Finding,
    SEVERITY_RANK,
)
from .chunker import chunk_pr_for_review, ChunkingExceeded
from .aggregate import (
    aggregate_findings,
    detect_boundary_findings,
    second_stage_review,
    merge_with_second_stage,
)


__all__ = [
    "Chunk",
    "ChunkFindings",
    "AggregatedFindings",
    "Finding",
    "SEVERITY_RANK",
    "chunk_pr_for_review",
    "ChunkingExceeded",
    "aggregate_findings",
    "detect_boundary_findings",
    "second_stage_review",
    "merge_with_second_stage",
]
