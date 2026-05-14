"""cycle-109 Sprint 4 T4.1 scaffold — ``chunk_pr_for_review`` stub.

T4.2 fills this in with the file-level chunk boundary algorithm per SDD
§5.4.1: chunk size = ``effective_input_ceiling × 0.7``, shared header
attached to every chunk, file boundaries preserved (no mid-file splits).
"""

from __future__ import annotations

from typing import List

from .types import Chunk


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
      input_text: the full PR / document content to review.
      effective_input_ceiling: per-model input-token ceiling from
        model-config.yaml. Chunks are sized to ``ceiling × 0.7`` to
        leave 30% headroom for prompt overhead.
      shared_header: PR description + affected-files-list + relevant
        CLAUDE.md excerpts. Attached to every chunk.
      chunks_max: hard upper bound on chunk count (default 16, configurable
        per-model via ``model-config.yaml::models.<id>.chunks_max``).
        Exceeding raises ``ChunkingExceeded`` (T4.5 wires exit code 13).

    Returns:
      Ordered list of ``Chunk`` objects.

    Raises:
      NotImplementedError: T4.1 scaffold; T4.2 fills in.
    """
    raise NotImplementedError(
        "chunk_pr_for_review is T4.2 work; T4.1 ships only the scaffold "
        "+ type signatures. See SDD §5.4.1 for the file-level boundary "
        "algorithm spec."
    )
