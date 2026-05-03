"""
tests/conformance/jcs/test-jcs-python.py

cycle-098 Sprint 1A — IMP-001 (HIGH_CONSENSUS 736). Pytest harness exercising
the Python JCS adapter (.claude/adapters/loa_cheval/jcs.py) against the
conformance corpus.

Run:
    pytest tests/conformance/jcs/test-jcs-python.py -v
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent.parent
ADAPTER_DIR = REPO_ROOT / ".claude" / "adapters"
VECTORS_PATH = SCRIPT_DIR / "test-vectors.json"

sys.path.insert(0, str(ADAPTER_DIR))
from loa_cheval.jcs import canonicalize, available  # noqa: E402


@pytest.fixture(scope="module")
def vectors() -> list[dict]:
    if not VECTORS_PATH.exists():
        pytest.skip(f"missing corpus: {VECTORS_PATH}")
    with VECTORS_PATH.open("r", encoding="utf-8") as f:
        data = json.load(f)
    assert "vectors" in data, "corpus missing 'vectors' key"
    return data["vectors"]


def test_adapter_is_available():
    """rfc8785 must be importable for the conformance gate to run."""
    assert available(), "rfc8785 not installed — pip install rfc8785"


def test_corpus_size_meets_ac(vectors):
    """Sprint 1 AC: corpus contains at least 20 vectors."""
    assert len(vectors) >= 20, f"corpus has {len(vectors)} vectors; AC requires >= 20"


def test_returns_bytes_not_str(vectors):
    """canonicalize() returns bytes (matching the spec; bash + node produce bytes too)."""
    sample = vectors[0]["input"]
    out = canonicalize(sample)
    assert isinstance(out, bytes), f"expected bytes, got {type(out).__name__}"


@pytest.mark.parametrize(
    "vector",
    [pytest.param(v, id=v["id"]) for v in json.loads(VECTORS_PATH.read_text())["vectors"]]
    if VECTORS_PATH.exists()
    else [],
)
def test_vector(vector):
    """Each vector's canonical output must equal the recorded `expected` bytes."""
    actual = canonicalize(vector["input"])
    expected = vector["expected"].encode("utf-8")
    assert actual == expected, (
        f"divergence on {vector['id']}: got {actual!r}, expected {expected!r}"
    )


def test_determinism():
    """Same logical input in different key order must produce identical bytes."""
    a = canonicalize({"x": 1.5, "y": [1, 2, 3]})
    b = canonicalize({"y": [1, 2, 3], "x": 1.5})
    assert a == b
