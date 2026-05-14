"""cycle-109 Sprint 4 T4.1 — canonical chunking type definitions.

Mirrors SDD §5.4.2 + §5.4.5 type contract. Used by:
  - chunk_pr_for_review (T4.2)
  - aggregate_findings (T4.3)
  - cross-chunk pass (T4.4)
  - cheval.cmd_invoke chunked-dispatch (T4.5)
  - MODELINV envelope additive fields (T4.7)
  - PR-comment chunked annotation (T4.8)

All types are dataclasses (no behavior) — keeps the contract clean and
serializable. Validation happens at use site, not at construction, so
producer code can build partial states during aggregation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List, Optional, Tuple


# ---------------------------------------------------------------------------
# Severity ordering (mirrors verdict-quality.schema.json + chunking aggregation
# severity-escalation per SDD §5.4.2 IMP-006)
# ---------------------------------------------------------------------------

SEVERITY_RANK = {
    "BLOCKER": 5,
    "BLOCKING": 5,    # alias — different consumers use either spelling
    "HIGH": 4,
    "MED": 3,
    "MEDIUM": 3,      # alias
    "LOW": 2,
    "ADVISORY": 2,    # alias
    "INFO": 1,
    "PRAISE": 0,
}


# ---------------------------------------------------------------------------
# Finding — the unit of model output that flows through aggregation
# ---------------------------------------------------------------------------


@dataclass
class Finding:
    """A single finding emitted by a model. Mirrors the per-finding shape used
    by FL / adversarial-review / BB consumers (id + severity + file:line +
    description). Aggregation-time fields default to neutral values so
    pre-aggregation findings construct cleanly.
    """

    id: str
    """Finding identifier (e.g. ``IMP-001``, ``DISS-001``, ``SKP-002``).
    Unique within the producing voice; aggregation may dedupe across voices."""

    file: str
    """Source file path the finding anchors to (e.g. ``src/auth.ts``).
    Required for the (file, line, finding_class) dedupe key in §5.4.2."""

    line: int
    """Line number within ``file``. ``0`` for file-level findings without a
    specific line anchor."""

    finding_class: str
    """Category / class label (e.g. ``null-safety``, ``shell-injection``,
    ``error-handling``). Used as the third dedupe-key axis."""

    severity: str
    """One of the keys in ``SEVERITY_RANK`` (case-insensitive matching by
    the aggregator). Escalation in §5.4.2 takes the max."""

    description: str = ""
    """Human-readable finding description. Optional for type-construction
    convenience; production callers always populate."""

    evidence_anchors: List[str] = field(default_factory=list)
    """Citations / file:line references that back the finding. Union'd
    across deduped instances per §5.4.2."""

    # Aggregation-time fields (None / default until aggregation visits the finding)

    severity_escalated_from: Optional[str] = None
    """When aggregation escalates severity (multiple chunks reported the
    same anchor at different severities), the LOWEST severity seen in
    the input set. Audit trail for operators."""

    cross_chunk_pass: bool = False
    """True iff this finding originated from the second-stage cross-chunk
    review (§5.4.3). Operator-visible via PR-comment annotation."""

    chunk_indices: List[int] = field(default_factory=list)
    """0-based indices of the chunks that contributed to this finding.
    Single-chunk findings: ``[N]``. Cross-chunk pass output: the set of
    spanning chunks."""


# ---------------------------------------------------------------------------
# Chunk — the unit of input passed to the model
# ---------------------------------------------------------------------------


@dataclass
class Chunk:
    """A single review chunk produced by ``chunk_pr_for_review``.

    File-level chunking per SDD §5.4.1: a chunk holds one or more whole
    files (file boundaries preserve coherent review units). Size budgeted
    to ``effective_input_ceiling × 0.7`` (30% headroom for prompt overhead).
    """

    chunk_index: int
    """0-based position in the chunk sequence. Used in
    ``Finding.chunk_indices`` to link findings back to their source."""

    files: List[str]
    """Files included in this chunk (paths relative to repo root)."""

    content: str
    """The chunk body that gets fed to the model (file contents +
    optional structural markers)."""

    shared_header: str = ""
    """PR description + affected-files-list + relevant CLAUDE.md excerpts.
    Same header attaches to every chunk so the reviewer has cross-file
    context per FR-4.1."""

    estimated_tokens: int = 0
    """Estimated token count for this chunk. Producer-side estimation
    used to verify the ``effective_input_ceiling × 0.7`` budget."""


# ---------------------------------------------------------------------------
# ChunkFindings — per-chunk model output, the input to aggregation
# ---------------------------------------------------------------------------


@dataclass
class ChunkFindings:
    """The model's output for a single chunk: a list of findings plus the
    chunk metadata that anchors them. ``aggregate_findings`` consumes a
    list of these and produces an ``AggregatedFindings``.
    """

    chunk_index: int
    """0-based chunk index this finding-set belongs to (matches
    ``Chunk.chunk_index``)."""

    files: List[str]
    """Files this chunk covered (for the cross-chunk pass to know which
    boundaries to inspect)."""

    findings: List[Finding] = field(default_factory=list)
    """Findings the model emitted for this chunk. Empty list = chunk
    reviewed-clean."""


# ---------------------------------------------------------------------------
# AggregatedFindings — output of aggregate_findings
# ---------------------------------------------------------------------------


@dataclass
class AggregatedFindings:
    """Post-aggregation finding set + observability fields per SDD §5.4.2.

    Mirrors the MODELINV envelope ``chunked_review`` shape (T4.7):
      chunks_reviewed, chunks_with_findings, second_stage_invoked.
    """

    findings: List[Finding] = field(default_factory=list)
    """Deduped + severity-escalated finding set after IMP-006
    conflict-resolution applies."""

    cross_chunk_overlaps: List[Tuple[Finding, Finding]] = field(
        default_factory=list
    )
    """Pairs of findings that share ``(file, line)`` but differ on
    ``finding_class``. Annotated as informational overlap; both findings
    are kept in ``findings``."""

    chunks_reviewed: int = 0
    """Total chunks that flowed into aggregation (= ``len(per_chunk)``)."""

    chunks_with_findings: int = 0
    """Subset of chunks whose ``ChunkFindings.findings`` was non-empty."""

    second_stage_invoked: bool = False
    """True iff the cross-chunk pass (§5.4.3) ran for boundary-spanning
    findings. ``cross_chunk_pass=True`` on individual findings indicates
    those that came from the second stage."""
