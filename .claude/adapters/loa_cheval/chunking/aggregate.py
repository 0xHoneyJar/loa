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


# ---------------------------------------------------------------------------
# Cross-chunk pass mechanism (T4.4 — SDD §5.4.3)
# ---------------------------------------------------------------------------


def _parse_anchor_path(anchor: str) -> str:
    """Extract the file-path portion of an evidence_anchor string.

    Canonical form is ``<path>:<line>``; the path is everything before
    the LAST `:` (paths may contain colons on Windows but we conserve
    cross-platform semantics here). Falls back to the whole string when
    no colon is present.
    """
    if not isinstance(anchor, str) or ":" not in anchor:
        return anchor
    return anchor.rsplit(":", 1)[0]


def detect_boundary_findings(
    aggregated: List[Finding],
    per_chunk: List[ChunkFindings],
) -> List[Finding]:
    """Identify findings whose evidence_anchors span multiple chunks
    (e.g., shell-injection sanitizer in chunk N + sink in chunk N+1).

    A finding is a boundary candidate iff:
      1. It has at least 2 evidence_anchors.
      2. Their file paths map to ≥ 2 distinct chunks in ``per_chunk``.
      3. Files NOT present in any chunk are ignored (they don't
         contribute to span detection).
    """
    if not aggregated or not per_chunk:
        return []

    # Build file → chunk_index lookup (a file can appear in only one
    # chunk per §5.4.1 file-boundary invariant, but we tolerate
    # malformed inputs by recording the first seen).
    file_to_chunk: Dict[str, int] = {}
    for chunk in per_chunk:
        for f in (chunk.files or []):
            if f not in file_to_chunk:
                file_to_chunk[f] = chunk.chunk_index

    candidates: List[Finding] = []
    for finding in aggregated:
        anchors = finding.evidence_anchors or []
        if len(anchors) < 2:
            continue
        chunk_indices_seen: set = set()
        for anchor in anchors:
            path = _parse_anchor_path(anchor)
            idx = file_to_chunk.get(path)
            if idx is not None:
                chunk_indices_seen.add(idx)
        # ≥ 2 distinct chunks → boundary span
        if len(chunk_indices_seen) >= 2:
            candidates.append(finding)

    return candidates


def _default_dispatch_fn(input_text: str) -> List[Finding]:
    """Default second-stage dispatch — production routes through cheval.

    Test injection: monkeypatch this symbol on the aggregate module to
    avoid live model calls. See test_chunking_cross_chunk_pass.py for
    the canonical fixture-injection pattern.

    For T4.4 v1 (this commit) the default is a no-op stub: returns
    empty list. T4.5 wires this to the real cheval --role review
    dispatch path. Until then, the test fixture (or T4.5 wiring) is
    the only way to exercise second-stage behavior end-to-end.
    """
    # The substrate dispatch lives at the cheval layer (T4.5 wires it).
    # For T4.4-only environments, return empty so the aggregator's
    # cross-chunk-pass branch doesn't escalate (consumers get the
    # IMP-006 result without second-stage augmentation).
    return []


def second_stage_review(
    boundary_candidates: List[Finding],
    *,
    dispatch_fn: Any = None,
) -> List[Finding]:
    """Re-dispatch boundary-spanning candidates as a synthetic combined
    chunk + annotate cross_chunk_pass=True on the returned findings.

    Per SDD §5.4.3:
      - Build a synthetic combined chunk from the candidates' evidence
        (path + line listing). Size bounded to
        ``effective_input_ceiling × 0.4`` (smaller than main chunks).
      - Re-dispatch through cheval with ``--role review`` (single call
        per chunked-review — bounded once, no recursion).
      - Annotate every returned finding with ``cross_chunk_pass = True``.

    Args:
      boundary_candidates: output of ``detect_boundary_findings``.
      dispatch_fn: callable accepting the synthetic combined-chunk
        text and returning a list of ``Finding``. Defaults to
        ``_default_dispatch_fn`` (T4.5 wires the real cheval path).
        Tests inject a fixture fn directly.

    Returns:
      List of ``Finding`` from the second-stage call, each with
      ``cross_chunk_pass = True``. Empty list on no candidates / on
      dispatch failure.
    """
    if not boundary_candidates:
        return []

    fn = dispatch_fn if dispatch_fn is not None else _default_dispatch_fn

    # Build a compact synthetic combined chunk describing the spanning
    # candidates. The dispatch_fn receives this as input_text — the
    # production cheval call interprets it as a review prompt.
    parts = ["## Cross-chunk pass — spanning findings\n"]
    for f in boundary_candidates:
        parts.append(
            f"- [{f.id}] {f.file}:{f.line} ({f.finding_class}, "
            f"severity={f.severity}): {f.description or '(no description)'}"
        )
        for anchor in (f.evidence_anchors or []):
            parts.append(f"  - evidence: {anchor}")
    synthetic_input = "\n".join(parts)

    try:
        raw_findings = fn(synthetic_input)
    except Exception:  # noqa: BLE001 — graceful degradation
        # Dispatch failure (cheval error, network glitch, fixture bug):
        # return empty so the aggregation pipeline doesn't abort.
        return []

    # Annotate every returned finding with the cross-chunk provenance
    # flag. We deep-copy to avoid mutating dispatch_fn's return value.
    annotated: List[Finding] = []
    for f in (raw_findings or []):
        copied = copy.deepcopy(f)
        copied.cross_chunk_pass = True
        annotated.append(copied)
    return annotated


def merge_with_second_stage(
    aggregated: List[Finding],
    second_stage: List[Finding],
) -> List[Finding]:
    """Fold ``second_stage`` findings into ``aggregated``, applying the
    same IMP-006 conflict-resolution rules to the merged set.

    Semantics:
      - Same (file, line, class) → dedupe; max severity wins;
        cross_chunk_pass=True if EITHER instance has it set.
      - New (file, line, class) → append.
      - Severity escalation across stages: if aggregated.MED +
        second_stage.HIGH at same anchor, merged becomes HIGH with
        severity_escalated_from=MED.
    """
    if not second_stage:
        return list(aggregated)

    # Index by (file, line, class)
    by_key: Dict[Tuple[str, int, str], Finding] = {}
    for f in aggregated:
        by_key[(f.file, f.line, f.finding_class)] = copy.deepcopy(f)

    for s in second_stage:
        key = (s.file, s.line, s.finding_class)
        if key not in by_key:
            # New finding from second-stage — append
            by_key[key] = copy.deepcopy(s)
        else:
            # Merge: max severity + cross_chunk_pass propagates
            existing = by_key[key]
            existing_rank = _severity_rank(existing.severity)
            new_rank = _severity_rank(s.severity)
            if new_rank > existing_rank:
                # Second-stage escalated
                existing.severity_escalated_from = _canonical_severity(existing_rank)
                existing.severity = _canonical_severity(new_rank)
            elif new_rank < existing_rank:
                # Aggregated already higher; preserve escalation marker
                if existing.severity_escalated_from is None:
                    existing.severity_escalated_from = _canonical_severity(new_rank)
            # cross_chunk_pass propagates if either set
            existing.cross_chunk_pass = bool(
                existing.cross_chunk_pass or s.cross_chunk_pass
            )
            # Union evidence_anchors
            anchors = list(existing.evidence_anchors or [])
            seen = set(anchors)
            for anchor in (s.evidence_anchors or []):
                if anchor not in seen:
                    seen.add(anchor)
                    anchors.append(anchor)
            existing.evidence_anchors = sorted(anchors)

    # Output ordering: canonical (file, line, class)
    merged = sorted(
        by_key.values(),
        key=lambda f: (f.file, f.line, f.finding_class),
    )
    return merged
