"""cycle-109 Sprint 4 T4.2 — chunk_pr_for_review tests.

Pins the file-level chunk boundary algorithm per SDD §5.4.1:

  - Per-chunk size = effective_input_ceiling × 0.7 (30% prompt headroom)
  - File boundaries preserved (no mid-file splits)
  - Larger-diff-first priority ordering
  - Max 16 chunks per call (chunks_max, configurable)
  - Shared header attached to every chunk (PR description + files list +
    CLAUDE.md excerpts)
  - ChunkingExceeded raised when chunks > chunks_max
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------


def _make_diff(filename: str, line_count: int = 20, content_char: str = "x") -> str:
    """Synthesize a unified-diff block for one file.

    Mirrors `git diff` output: `diff --git a/<path> b/<path>` header
    followed by hunk lines.
    """
    body_line = "+" + (content_char * 50) + "\n"
    return (
        f"diff --git a/{filename} b/{filename}\n"
        f"--- a/{filename}\n"
        f"+++ b/{filename}\n"
        f"@@ -1,1 +1,{line_count} @@\n"
        + (body_line * line_count)
    )


# ---------------------------------------------------------------------------
# Trivial case: single small file fits in one chunk
# ---------------------------------------------------------------------------


def test_single_small_file_returns_one_chunk():
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    diff = _make_diff("src/a.py", line_count=5)
    chunks = chunk_pr_for_review(diff, effective_input_ceiling=10_000)
    assert len(chunks) == 1
    assert chunks[0].chunk_index == 0
    assert chunks[0].files == ["src/a.py"]


def test_empty_input_returns_empty_list():
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    chunks = chunk_pr_for_review("", effective_input_ceiling=10_000)
    assert chunks == []


def test_input_without_diff_markers_returns_one_chunk():
    """Non-diff inputs (e.g., a plain document) treat the whole text as
    one chunk under a synthetic single-file marker."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    chunks = chunk_pr_for_review("plain text body", effective_input_ceiling=10_000)
    assert len(chunks) == 1
    # The synthetic file marker is intentionally generic
    assert len(chunks[0].files) == 1


# ---------------------------------------------------------------------------
# Multi-file partitioning
# ---------------------------------------------------------------------------


def test_two_small_files_fit_in_one_chunk_when_under_ceiling():
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    diff = _make_diff("src/a.py", 5) + _make_diff("src/b.py", 5)
    chunks = chunk_pr_for_review(diff, effective_input_ceiling=10_000)
    assert len(chunks) == 1
    assert set(chunks[0].files) == {"src/a.py", "src/b.py"}


def test_two_files_each_larger_than_threshold_split_into_two_chunks():
    """Two files whose combined size would exceed ceiling × 0.7 but each
    individually fits split into two chunks (file boundaries preserved)."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    # Each file ~30K chars; ceiling 60K → ceiling × 0.7 = 42K budget
    diff = _make_diff("src/a.py", line_count=500) + _make_diff("src/b.py", line_count=500)
    chunks = chunk_pr_for_review(diff, effective_input_ceiling=60_000)
    assert len(chunks) == 2
    # Each chunk holds exactly one file (file-level boundary preserved)
    assert all(len(c.files) == 1 for c in chunks)


def test_files_never_split_mid_file():
    """A single file larger than the per-chunk budget still occupies one
    whole chunk — file boundaries are preserved. The operator-facing
    consequence is documented in the rationale; the chunker does not
    attempt mid-file splitting."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    # One large file; small ceiling
    diff = _make_diff("src/huge.py", line_count=2_000)
    chunks = chunk_pr_for_review(diff, effective_input_ceiling=5_000)
    assert len(chunks) == 1
    assert chunks[0].files == ["src/huge.py"]
    # The chunk is "oversized" relative to ceiling × 0.7, which is the
    # intentional trade-off per §5.4.1.


# ---------------------------------------------------------------------------
# Priority ordering: larger-diff-first
# ---------------------------------------------------------------------------


def test_larger_files_appear_before_smaller_files_in_chunk_order():
    """SDD §5.4.1: 'Chunk priority ordering: larger-diff-first → preserve
    high-signal files when truncated.'

    Smaller files should appear LATER in the chunk sequence so that if a
    truncation event drops trailing chunks, the high-signal larger files
    are retained.
    """
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    diff = (
        _make_diff("src/small.py", 10)
        + _make_diff("src/huge.py", 1000)
        + _make_diff("src/medium.py", 100)
    )
    chunks = chunk_pr_for_review(diff, effective_input_ceiling=20_000)
    # Files should be packed across chunks in descending size order.
    # Flatten the per-chunk files in order and assert huge.py is first.
    file_order = [f for c in chunks for f in c.files]
    assert file_order.index("src/huge.py") < file_order.index("src/medium.py")
    assert file_order.index("src/medium.py") < file_order.index("src/small.py")


# ---------------------------------------------------------------------------
# chunks_max guard
# ---------------------------------------------------------------------------


def test_default_chunks_max_is_16():
    """SDD §5.4.1: default chunks_max = 16."""
    import inspect
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    sig = inspect.signature(chunk_pr_for_review)
    assert sig.parameters["chunks_max"].default == 16


def test_chunks_max_breach_raises_chunking_exceeded():
    """When the input requires more chunks than chunks_max, the chunker
    raises ChunkingExceeded. T4.5 maps this to exit code 13."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review, ChunkingExceeded

    # 5 files, each large enough to require its own chunk; chunks_max=3
    diff = "".join(_make_diff(f"src/f{i}.py", line_count=300) for i in range(5))
    with pytest.raises(ChunkingExceeded) as excinfo:
        chunk_pr_for_review(diff, effective_input_ceiling=20_000, chunks_max=3)
    # Exception carries the would-have-been-chunks count
    assert "5" in str(excinfo.value) or hasattr(excinfo.value, "chunks_needed")


def test_chunks_max_default_16_accepts_15_chunks():
    """Just under the default limit completes without raising."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    diff = "".join(_make_diff(f"src/f{i}.py", line_count=300) for i in range(15))
    chunks = chunk_pr_for_review(diff, effective_input_ceiling=20_000)
    assert len(chunks) <= 16


# ---------------------------------------------------------------------------
# Shared header attachment
# ---------------------------------------------------------------------------


def test_shared_header_is_attached_to_every_chunk():
    """SDD §5.4.1: shared header attaches to every chunk so reviewers
    have cross-file context per file's review."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    header = "## PR description\n\nFix auth bug.\n\n## Affected files\n- src/a.py\n- src/b.py\n"
    diff = _make_diff("src/a.py", 200) + _make_diff("src/b.py", 200)
    chunks = chunk_pr_for_review(
        diff, effective_input_ceiling=10_000, shared_header=header,
    )
    assert len(chunks) >= 2
    for c in chunks:
        assert c.shared_header == header


def test_empty_shared_header_defaults_to_empty_string():
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    chunks = chunk_pr_for_review(_make_diff("a.py", 5), effective_input_ceiling=10_000)
    assert chunks[0].shared_header == ""


# ---------------------------------------------------------------------------
# Chunk content carries the file's diff body
# ---------------------------------------------------------------------------


def test_chunk_content_includes_file_diff_body():
    """Each chunk's content must include the diff body for its files;
    the model needs the actual change to review it."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    diff = _make_diff("src/auth.py", line_count=10, content_char="A")
    chunks = chunk_pr_for_review(diff, effective_input_ceiling=10_000)
    assert "src/auth.py" in chunks[0].content
    # The +AAA... body lines from _make_diff must appear in content
    assert "AAA" in chunks[0].content


def test_chunk_estimated_tokens_is_set():
    """Producer-side token estimation must be populated so T4.5's
    pre-flight gate can verify per-chunk budgets."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    chunks = chunk_pr_for_review(
        _make_diff("a.py", 100), effective_input_ceiling=10_000,
    )
    assert chunks[0].estimated_tokens > 0


# ---------------------------------------------------------------------------
# Chunk index sequencing
# ---------------------------------------------------------------------------


def test_chunk_indices_are_sequential_zero_based():
    """chunk_index MUST be 0-based and sequential — Findings reference
    these indices in chunk_indices."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    diff = "".join(_make_diff(f"src/f{i}.py", line_count=300) for i in range(4))
    chunks = chunk_pr_for_review(diff, effective_input_ceiling=20_000)
    indices = [c.chunk_index for c in chunks]
    assert indices == list(range(len(chunks)))


# ---------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------


def test_chunker_is_deterministic_under_same_inputs():
    """Same input + same params MUST produce the same chunk sequence —
    file-ordering ties must resolve deterministically."""
    from loa_cheval.chunking.chunker import chunk_pr_for_review

    # Two files of the EXACT same size: deterministic tie-break needed
    diff = _make_diff("src/a.py", 100) + _make_diff("src/b.py", 100)
    first = chunk_pr_for_review(diff, effective_input_ceiling=10_000)
    for _ in range(3):
        again = chunk_pr_for_review(diff, effective_input_ceiling=10_000)
        assert [c.files for c in first] == [c.files for c in again]


# ---------------------------------------------------------------------------
# ChunkingExceeded shape
# ---------------------------------------------------------------------------


def test_chunking_exceeded_is_a_cheval_error():
    """ChunkingExceeded subclasses ChevalError so the typed exit-code
    mapping in cheval.py (T4.5) can dispatch on .code."""
    from loa_cheval.chunking.chunker import ChunkingExceeded
    from loa_cheval.types import ChevalError

    assert issubclass(ChunkingExceeded, ChevalError)


def test_chunking_exceeded_code_is_canonical():
    """The error code surfaces in MODELINV + operator-facing errors;
    canonical form per SDD §6.1."""
    from loa_cheval.chunking.chunker import ChunkingExceeded

    err = ChunkingExceeded(chunks_needed=20, chunks_max=16)
    assert err.code == "CHUNKING_EXCEEDED"
    assert err.context.get("chunks_needed") == 20
    assert err.context.get("chunks_max") == 16
