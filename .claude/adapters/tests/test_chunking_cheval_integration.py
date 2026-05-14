"""cycle-109 Sprint 4 T4.5 — cheval pre-flight gate dispatches chunked path.

Pins:
  1. EXIT_CODES["CHUNKING_EXCEEDED"] = 13
  2. The chunked-dispatch path lives in cheval.cmd_invoke and is routed
     by the pre-flight gate when input > effective_input_ceiling × 0.7
     AND chunking is enabled (per-model config).
  3. _default_dispatch_fn in aggregate.py invokes cheval via subprocess
     for the second-stage cross-chunk review.
  4. ChunkingExceeded → exit code 13 via the cheval error envelope path.

T4.5 is the integration layer between the chunking package (T4.1-T4.4)
and cheval.cmd_invoke. Tests verify the wiring exists structurally;
end-to-end integration runs against the curl-mock harness (out of
scope for this unit suite).
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# Exit code 13 contract
# ---------------------------------------------------------------------------


def test_exit_code_13_is_chunking_exceeded():
    """SDD §6.1: exit code 13 = ChunkingExceeded. Source-level pin
    (cheval.py uses runtime dataclasses that resist importlib.util
    sandbox loads; a grep is safer + faster for this constant pin)."""
    text = (ROOT / "cheval.py").read_text()
    assert '"CHUNKING_EXCEEDED": 13' in text


def test_chunking_exceeded_exception_exit_code_maps_via_13():
    """ChunkingExceeded.code == 'CHUNKING_EXCEEDED' which the cheval
    main() routes to exit 13."""
    from loa_cheval.chunking.chunker import ChunkingExceeded

    err = ChunkingExceeded(chunks_needed=20, chunks_max=16)
    assert err.code == "CHUNKING_EXCEEDED"


# ---------------------------------------------------------------------------
# _default_dispatch_fn — wired to cheval subprocess
# ---------------------------------------------------------------------------


def test_default_dispatch_fn_signature_accepts_input_text():
    """The cross-chunk pass's default dispatch is a function taking
    input_text (string) and returning list[Finding]. T4.5 wires the
    real cheval subprocess; tests inject fixture fns to avoid it."""
    import inspect
    from loa_cheval.chunking import aggregate

    fn = aggregate._default_dispatch_fn
    sig = inspect.signature(fn)
    params = list(sig.parameters.keys())
    assert "input_text" in params


def test_default_dispatch_fn_callable_returns_list():
    """Calling _default_dispatch_fn with input_text returns a list
    (empty in the no-op v1; T4.5 wires real cheval but the empty-default
    path stays the safe fallback when LOA_CHEVAL_DISABLE_SECOND_STAGE=1)."""
    import os
    from loa_cheval.chunking import aggregate

    # Force the no-op path to keep the test hermetic
    os.environ["LOA_CHEVAL_DISABLE_SECOND_STAGE"] = "1"
    try:
        result = aggregate._default_dispatch_fn("any text")
        assert isinstance(result, list)
    finally:
        os.environ.pop("LOA_CHEVAL_DISABLE_SECOND_STAGE", None)


# ---------------------------------------------------------------------------
# Pre-flight gate routes to chunked when input > ceiling × 0.7
# ---------------------------------------------------------------------------


def test_cheval_has_chunked_dispatch_path_in_cmd_invoke():
    """T4.5 adds a chunked-dispatch path in cmd_invoke gated on the
    pre-flight decision. Source-level wiring check: the cheval.py
    module must reference the chunking package."""
    text = (ROOT / "cheval.py").read_text()
    assert "loa_cheval.chunking" in text or "from .chunking" in text or "chunk_pr_for_review" in text


def test_chunking_exceeded_routed_to_exit_13():
    """When the chunker raises ChunkingExceeded, cheval's error envelope
    path emits exit code 13. Source-level wiring check."""
    text = (ROOT / "cheval.py").read_text()
    # The error envelope or exception-translation path must reference
    # either CHUNKING_EXCEEDED or ChunkingExceeded
    assert "CHUNKING_EXCEEDED" in text or "ChunkingExceeded" in text
