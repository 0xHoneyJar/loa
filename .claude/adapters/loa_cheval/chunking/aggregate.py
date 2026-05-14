"""cycle-109 Sprint 4 T4.3 — aggregate_findings + IMP-006 conflict-resolution.

Per SDD §5.4.2:

  1. Same (file, line, finding_class) → dedupe; keep highest severity;
     union evidence_anchors.
  2. Same (file, line) different class → keep both; annotate
     cross_chunk_overlaps.
  3. Same class different line → keep both.
  4. Conflicting severity for same logical finding → escalate to max;
     annotate severity_escalated_from with the min.
  5. Finding spans chunk boundary → cross-chunk pass (T4.4 second-stage).

The aggregator is pure (no I/O, no global state) and deterministic.
Output finding order is canonical (sorted by (file, line, class)) so
downstream consumers can compare snapshots.

T4.4 cross-chunk pass: aggregate_findings invokes detect_boundary_findings
+ second_stage_review + merge_with_second_stage at the tail. While T4.4
is still stubbed (raises NotImplementedError), the wiring tolerates the
exception so the IMP-006 path lands cleanly. T4.4 replaces the stubs
with real impl and the second_stage_invoked flag flips.
"""

from __future__ import annotations

import copy
from collections import defaultdict
from typing import Any, Dict, List, Tuple

from .types import AggregatedFindings, ChunkFindings, Finding, SEVERITY_RANK


# ---------------------------------------------------------------------------
# Severity helpers
# ---------------------------------------------------------------------------


def _severity_rank(severity: str) -> int:
    """Rank a severity string. Unknown severities rank at 0 (treated as
    lowest); the SEVERITY_RANK table handles aliases."""
    if not isinstance(severity, str):
        return 0
    return SEVERITY_RANK.get(severity.upper(), 0)


def _canonical_severity(rank: int) -> str:
    """Return the canonical name for a rank (used to normalize aliases
    on output — e.g., BLOCKING → BLOCKER, MEDIUM → MED, ADVISORY → LOW)."""
    canonical = {
        5: "BLOCKER",
        4: "HIGH",
        3: "MED",
        2: "LOW",
        1: "INFO",
        0: "PRAISE",
    }
    return canonical.get(rank, "INFO")


# ---------------------------------------------------------------------------
# Public API: aggregate_findings
# ---------------------------------------------------------------------------


def aggregate_findings(per_chunk: List[ChunkFindings]) -> AggregatedFindings:
    """Conflict-resolution aggregation per SDD §5.4.2 IMP-006.

    Args:
      per_chunk: list of ``ChunkFindings``, one per chunk fed through
        the model. Empty findings within a chunk are valid.

    Returns:
      ``AggregatedFindings`` with deduped + escalated finding set,
      cross-chunk overlap annotations, and observability counts.

    Deterministic: same input → byte-equal output.
    Pure: does not mutate ``per_chunk``.
    """
    # Defensive deep-copy so we never mutate caller data
    safe_per_chunk = [copy.deepcopy(c) for c in per_chunk]

    # Index findings by (file, line) location
    by_anchor: Dict[Tuple[str, int], List[Finding]] = defaultdict(list)
    for chunk in safe_per_chunk:
        for f in chunk.findings:
            by_anchor[(f.file, f.line)].append(f)

    aggregated: List[Finding] = []
    overlap_pairs: List[Tuple[Finding, Finding]] = []

    # Iterate anchors in deterministic order (file path, then line)
    for (file_path, line), findings in sorted(by_anchor.items()):
        # Group by finding_class within this anchor
        by_class: Dict[str, List[Finding]] = defaultdict(list)
        for f in findings:
            by_class[f.finding_class].append(f)

        anchor_kept: List[Finding] = []
        for finding_class in sorted(by_class.keys()):
            instances = by_class[finding_class]
            # Dedupe same (file, line, class):
            # Keep ONE finding; max severity; union evidence_anchors.
            ranks = [_severity_rank(f.severity) for f in instances]
            max_rank = max(ranks)
            min_rank = min(ranks)

            # Pick the instance with max severity as the canonical;
            # if ties, take the first (deterministic given input order
            # which was preserved via safe_per_chunk iteration).
            kept_idx = ranks.index(max_rank)
            kept = copy.deepcopy(instances[kept_idx])

            # Union evidence_anchors across all instances (sorted for
            # determinism)
            union: List[str] = []
            seen = set()
            for f in instances:
                for anchor in (f.evidence_anchors or []):
                    if anchor not in seen:
                        seen.add(anchor)
                        union.append(anchor)
            kept.evidence_anchors = sorted(union)

            # Severity escalation: if there was a spread, normalize to
            # canonical max + record min.
            if max_rank != min_rank:
                kept.severity = _canonical_severity(max_rank)
                kept.severity_escalated_from = _canonical_severity(min_rank)
            # Else leave severity as-is (no escalation marker)

            anchor_kept.append(kept)

        # Cross-class same-anchor: keep ALL classes; annotate the
        # pairs (combinations of size 2) in cross_chunk_overlaps.
        if len(anchor_kept) > 1:
            for i in range(len(anchor_kept)):
                for j in range(i + 1, len(anchor_kept)):
                    overlap_pairs.append((anchor_kept[i], anchor_kept[j]))

        aggregated.extend(anchor_kept)

    # Canonical output ordering: by (file, line, finding_class) for
    # snapshot-comparison determinism downstream.
    aggregated.sort(key=lambda f: (f.file, f.line, f.finding_class))

    # T4.4 cross-chunk pass — wired but tolerant of stub NotImplementedError
    second_stage_invoked = False
    try:
        boundary_candidates = detect_boundary_findings(aggregated, safe_per_chunk)
        if boundary_candidates:
            second_stage = second_stage_review(boundary_candidates)
            aggregated = merge_with_second_stage(aggregated, second_stage)
            second_stage_invoked = True
    except NotImplementedError:
        # T4.4 not yet landed; aggregate cleanly without cross-chunk pass.
        pass

    return AggregatedFindings(
        findings=aggregated,
        cross_chunk_overlaps=overlap_pairs,
        chunks_reviewed=len(safe_per_chunk),
        chunks_with_findings=sum(1 for c in safe_per_chunk if c.findings),
        second_stage_invoked=second_stage_invoked,
    )


# ---------------------------------------------------------------------------
# Cross-chunk pass — T4.4 stubs
# ---------------------------------------------------------------------------


def detect_boundary_findings(
    aggregated: List[Finding],
    per_chunk: List[ChunkFindings],
) -> List[Finding]:
    """Identify findings whose evidence may span a chunk boundary.

    Args:
      aggregated: post-IMP-006 aggregated findings.
      per_chunk: original per-chunk finding sets.

    Returns:
      Subset of ``aggregated`` whose anchors sit at or near a chunk
      boundary.

    Raises:
      NotImplementedError: T4.3 scaffold-tolerant stub; T4.4 fills in.
    """
    raise NotImplementedError(
        "detect_boundary_findings is T4.4 work; T4.3 wires the call site "
        "but tolerates this NotImplementedError until T4.4 lands. See "
        "SDD §5.4.3 for the cross-chunk pass mechanism spec."
    )


def second_stage_review(
    boundary_candidates: List[Finding],
) -> List[Finding]:
    """Re-dispatch boundary-spanning candidates as a synthetic combined
    chunk (size bounded to ``effective_input_ceiling × 0.4``).

    Raises:
      NotImplementedError: T4.3 scaffold-tolerant stub; T4.4 fills in.
    """
    raise NotImplementedError(
        "second_stage_review is T4.4 work; T4.3 wires the call site but "
        "tolerates this NotImplementedError until T4.4 lands. See SDD "
        "§5.4.3 for the synthetic-combined-chunk mechanism."
    )


def merge_with_second_stage(
    aggregated: List[Finding],
    second_stage: List[Finding],
) -> List[Finding]:
    """Fold ``second_stage`` findings into ``aggregated``, annotating
    the merged set's provenance.

    Raises:
      NotImplementedError: T4.3 scaffold-tolerant stub; T4.4 fills in.
    """
    raise NotImplementedError(
        "merge_with_second_stage is T4.4 work; T4.3 wires the call site "
        "but tolerates this NotImplementedError until T4.4 lands."
    )
