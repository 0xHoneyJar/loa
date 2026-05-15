"""cycle-109 Sprint 4 T4.2 — file-level chunk-boundary algorithm.

Per SDD §5.4.1:

  Per-chunk size       = effective_input_ceiling × 0.7 (30% prompt headroom)
  Chunk boundary       = file-level (preserve coherent review units)
  Priority ordering    = larger-diff-first (truncation preserves high-signal)
  Max chunks per call  = 16 (configurable; chunks_max breach → ChunkingExceeded)
  Shared header        = PR description + affected-files-list + CLAUDE.md
                          excerpts; attached to every chunk

Token estimation: simple character-count / 3 heuristic, matching
``loa_cheval.providers.base.estimate_tokens`` for cross-module
consistency. The number is "approximate" rather than tokenizer-exact;
the 30% headroom absorbs the slop.

The chunker is pure (no I/O, no provider calls, no env reads) and
deterministic — same input + same params → byte-equal chunk sequence.
File-ordering ties resolve by alphabetic filename so the order is
reproducible across runs.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from loa_cheval.types import ChevalError

from .types import Chunk


# ---------------------------------------------------------------------------
# Exception class — chunks_max breach
# ---------------------------------------------------------------------------


class ChunkingExceeded(ChevalError):
    """Raised when the chunked-review input requires more chunks than
    ``chunks_max`` and truncation is forbidden.

    SDD §6.1 maps this to exit code 13 (T4.5). The exception carries
    ``chunks_needed`` + ``chunks_max`` in context so the caller can
    surface an actionable operator-facing error.
    """

    def __init__(self, chunks_needed: int, chunks_max: int):
        super().__init__(
            "CHUNKING_EXCEEDED",
            f"chunked review requires {chunks_needed} chunks; "
            f"chunks_max={chunks_max} and truncation forbidden",
            retryable=False,
            context={
                "chunks_needed": chunks_needed,
                "chunks_max": chunks_max,
            },
        )


# ---------------------------------------------------------------------------
# Token estimation (character-based heuristic)
# ---------------------------------------------------------------------------


def _estimate_tokens(text: str) -> int:
    """Estimate token count via character-count / 3.

    Matches the conservative heuristic used elsewhere in cheval (bytes/3
    for code-shaped content). 30% headroom in the chunk budget absorbs
    the heuristic slop.
    """
    if not text:
        return 0
    return max(1, len(text) // 3)


# ---------------------------------------------------------------------------
# File-level diff parsing
# ---------------------------------------------------------------------------


# Match `diff --git a/<path> b/<path>` headers; capture the path.
# (We use a/<path> since that's the canonical "before" path; the
# scanner is permissive on quoting + trailing whitespace.)
_DIFF_HEADER_RE = re.compile(
    r"^diff --git a/(?P<path>\S+) b/\S+\s*$",
    re.MULTILINE,
)


def _parse_diff_into_files(input_text: str) -> List[Dict[str, Any]]:
    """Split a unified-diff into per-file blocks.

    Each block carries:
      - ``path``: file path from the `diff --git` header
      - ``content``: the full diff text for that file (header through
        last hunk line, up to but not including the next header)

    Returns a list in DIFF ORDER (preserves the producer's intent). Use
    ``_sort_files_by_priority`` to apply larger-first ordering.

    Inputs without any `diff --git` markers return a single synthetic
    block keyed on path ``<unstructured-input>``.
    """
    matches = list(_DIFF_HEADER_RE.finditer(input_text))
    if not matches:
        # Non-diff input: single synthetic block.
        return [{"path": "<unstructured-input>", "content": input_text}]

    blocks: List[Dict[str, Any]] = []
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(input_text)
        blocks.append(
            {
                "path": m.group("path"),
                "content": input_text[start:end],
            }
        )
    return blocks


def _sort_files_by_priority(files: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Sort files by descending content length (larger-diff-first per
    SDD §5.4.1). Ties resolve by ascending path for determinism.

    Producer-supplied order is INTENTIONALLY discarded — priority
    ordering is the chunker's responsibility.
    """
    return sorted(
        files,
        key=lambda f: (-len(f["content"]), f["path"]),
    )


# ---------------------------------------------------------------------------
# Greedy bin-packing
# ---------------------------------------------------------------------------


def _pack_files_into_chunks(
    files: List[Dict[str, Any]],
    budget_tokens: int,
) -> List[Chunk]:
    """Pack files into chunks bounded by ``budget_tokens``.

    Algorithm:
      - Files arrive in priority order (largest first).
      - For each file: if it fits in the current chunk, add it. Else
        close the current chunk and start a new one with this file as
        its first entry.
      - A file larger than ``budget_tokens`` still occupies one whole
        chunk (file boundaries are preserved per §5.4.1; the "oversize"
        consequence is documented in operator-facing rationale).

    Returns a list of ``Chunk`` objects with ``chunk_index`` set in
    order. ``shared_header`` and ``content`` are populated; the caller
    overlays the shared header.
    """
    if not files:
        return []

    chunks: List[Chunk] = []
    current_files: List[str] = []
    current_content_parts: List[str] = []
    current_tokens = 0

    def _flush() -> None:
        if not current_files:
            return
        chunks.append(
            Chunk(
                chunk_index=len(chunks),
                files=list(current_files),
                content="".join(current_content_parts),
                shared_header="",  # caller overlays
                estimated_tokens=current_tokens,
            )
        )

    for f in files:
        file_tokens = _estimate_tokens(f["content"])
        # If the current chunk is non-empty AND adding this file would
        # blow the budget → flush the current chunk first.
        if current_files and (current_tokens + file_tokens) > budget_tokens:
            _flush()
            current_files = []
            current_content_parts = []
            current_tokens = 0
        current_files.append(f["path"])
        current_content_parts.append(f["content"])
        current_tokens += file_tokens

    # Final flush
    if current_files:
        _flush()

    return chunks


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def chunk_pr_for_review(
    input_text: str,
    effective_input_ceiling: int,
    *,
    shared_header: str = "",
    chunks_max: int = 16,
) -> List[Chunk]:
    """Partition ``input_text`` into chunks bounded by
    ``effective_input_ceiling × 0.7`` tokens each.

    Args:
      input_text: the full PR / document content to review. Unified
        diff format is parsed by-file boundary; non-diff inputs are
        treated as one synthetic chunk.
      effective_input_ceiling: per-model input-token ceiling from
        model-config.yaml. Chunks sized to ``ceiling × 0.7`` to leave
        30% headroom for prompt overhead.
      shared_header: PR description + affected-files-list + relevant
        CLAUDE.md excerpts. Attached to every chunk. Defaults to empty.
      chunks_max: hard upper bound on chunk count (default 16,
        configurable per-model via ``model-config.yaml::models.<id>.chunks_max``).
        Exceeding raises ``ChunkingExceeded`` (T4.5 wires exit code 13).

    Returns:
      Ordered list of ``Chunk`` objects. Empty list for empty input.

    Raises:
      ChunkingExceeded: when chunks > chunks_max.
    """
    # Empty input → empty result. Pre-T4.5 callers handle this case
    # by skipping the chunked-dispatch path entirely.
    if not input_text:
        return []

    # Parse + sort by priority
    files = _parse_diff_into_files(input_text)
    files = _sort_files_by_priority(files)

    # Compute per-chunk budget (30% headroom)
    budget_tokens = max(1, int(effective_input_ceiling * 0.7))

    # Pack
    chunks = _pack_files_into_chunks(files, budget_tokens)

    # Chunks_max guard
    if len(chunks) > chunks_max:
        raise ChunkingExceeded(
            chunks_needed=len(chunks), chunks_max=chunks_max,
        )

    # Overlay shared header on every chunk
    if shared_header:
        for c in chunks:
            c.shared_header = shared_header

    return chunks
