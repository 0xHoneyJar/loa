"""Apparatus tests for corpus_loader.py (cycle-100 T1.2)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
_LIB_DIR = _REPO_ROOT / "tests" / "red-team" / "jailbreak" / "lib"
sys.path.insert(0, str(_LIB_DIR))

import corpus_loader  # noqa: E402


@pytest.fixture
def isolated_corpus(tmp_path, monkeypatch):
    corpus_dir = tmp_path / "corpus"
    corpus_dir.mkdir()
    # Test-mode gate (cycle-098 dual-condition pattern). PYTEST_CURRENT_TEST
    # is set by pytest itself.
    monkeypatch.setenv("LOA_JAILBREAK_TEST_MODE", "1")
    monkeypatch.setenv("LOA_JAILBREAK_CORPUS_DIR", str(corpus_dir))
    # Reload module to pick up env override; since CORPUS_DIR is module-level
    # constant, recompute here for tests.
    import importlib
    importlib.reload(corpus_loader)
    return corpus_dir


def _vector(vid="RT-RS-001", **overrides):
    base = {
        "vector_id": vid,
        "category": "role_switch",
        "title": "test vector for unit suite",
        "defense_layer": "L1",
        "payload_construction": "_make_evil_body_x",
        "expected_outcome": "redacted",
        "source_citation": "in-house-cypherpunk test fixture",
        "severity": "LOW",
        "status": "active",
    }
    base.update(overrides)
    return base


def test_validate_all_empty_corpus(isolated_corpus):
    assert corpus_loader.validate_all() == []


def test_validate_all_happy_path(isolated_corpus):
    f = isolated_corpus / "role_switch.jsonl"
    f.write_text(json.dumps(_vector("RT-RS-001")) + "\n")
    assert corpus_loader.validate_all() == []


def test_validate_all_strips_comment_lines(isolated_corpus):
    f = isolated_corpus / "role_switch.jsonl"
    f.write_text(
        "# schema-major: 1\n"
        "# Comment with adversarial-looking text but lint runs separately\n"
        "\n"
        + json.dumps(_vector("RT-RS-001"))
        + "\n"
    )
    assert corpus_loader.validate_all() == []


def test_validate_all_detects_bad_id(isolated_corpus):
    f = isolated_corpus / "role_switch.jsonl"
    f.write_text(json.dumps(_vector(vid="rs-001")) + "\n")
    errs = corpus_loader.validate_all()
    assert len(errs) == 1
    assert "vector_id" in errs[0]


def test_validate_all_detects_duplicate_vector_id(isolated_corpus):
    (isolated_corpus / "a.jsonl").write_text(json.dumps(_vector("RT-RS-001")) + "\n")
    (isolated_corpus / "b.jsonl").write_text(json.dumps(_vector("RT-RS-001")) + "\n")
    errs = corpus_loader.validate_all()
    assert any("duplicate vector_id" in e for e in errs)


def test_validate_all_detects_suppressed_without_reason(isolated_corpus):
    bad = _vector("RT-RS-002", status="suppressed")
    (isolated_corpus / "role_switch.jsonl").write_text(json.dumps(bad) + "\n")
    errs = corpus_loader.validate_all()
    assert errs, "suppressed status without suppression_reason should fail"


def test_validate_all_detects_extra_property(isolated_corpus):
    bad = _vector("RT-RS-003")
    bad["evil_extra"] = "should be rejected"
    (isolated_corpus / "role_switch.jsonl").write_text(json.dumps(bad) + "\n")
    errs = corpus_loader.validate_all()
    assert errs, "additionalProperties:false should reject extra fields"


def test_iter_active_filters_by_status(isolated_corpus):
    suppressed = _vector(
        "RT-RS-098",
        status="suppressed",
        suppression_reason="Legacy carry-over kept as audit anchor for the test run.",
    )
    superseded = _vector("RT-RS-099", status="superseded", superseded_by="RT-RS-001")
    active = _vector("RT-RS-001")
    (isolated_corpus / "role_switch.jsonl").write_text(
        "\n".join(json.dumps(v) for v in (suppressed, superseded, active)) + "\n"
    )
    ids = [v.vector_id for v in corpus_loader.iter_active()]
    assert ids == ["RT-RS-001"]


def test_iter_active_sort_is_lc_c_byte_order(isolated_corpus):
    # Use vector ids that would sort differently under en_US.UTF-8 (case-insensitive)
    # vs LC_ALL=C (byte-order). Numerals and uppercase ASCII fully avoid that
    # ambiguity, so we test sort by writing files in REVERSE order and asserting
    # corpus_iter_active emits them in ascending byte-order regardless of file
    # discovery order.
    a = _vector("RT-RS-005")
    b = _vector("RT-RS-002")
    c = _vector("RT-RS-009")
    d = _vector("RT-RS-001")
    (isolated_corpus / "z.jsonl").write_text(
        "\n".join(json.dumps(v) for v in (a, b)) + "\n"
    )
    (isolated_corpus / "a.jsonl").write_text(
        "\n".join(json.dumps(v) for v in (c, d)) + "\n"
    )
    ids = [v.vector_id for v in corpus_loader.iter_active()]
    assert ids == ["RT-RS-001", "RT-RS-002", "RT-RS-005", "RT-RS-009"]


def test_iter_active_category_filter(isolated_corpus):
    rs = _vector("RT-RS-001", category="role_switch")
    cl = _vector("RT-CL-001", category="credential_leak")
    (isolated_corpus / "mixed.jsonl").write_text(
        "\n".join(json.dumps(v) for v in (rs, cl)) + "\n"
    )
    rs_only = [v.vector_id for v in corpus_loader.iter_active("role_switch")]
    assert rs_only == ["RT-RS-001"]


def test_get_field_known(isolated_corpus):
    v = _vector("RT-RS-001")
    (isolated_corpus / "f.jsonl").write_text(json.dumps(v) + "\n")
    assert corpus_loader.get_field("RT-RS-001", "category") == "role_switch"


def test_get_field_unknown(isolated_corpus):
    v = _vector("RT-RS-001")
    (isolated_corpus / "f.jsonl").write_text(json.dumps(v) + "\n")
    assert corpus_loader.get_field("RT-XX-999", "category") is None


def test_count_by_status(isolated_corpus):
    items = [
        _vector("RT-RS-001"),
        _vector("RT-RS-002"),
        _vector("RT-RS-003", status="superseded", superseded_by="RT-RS-001"),
        _vector(
            "RT-RS-004",
            status="suppressed",
            suppression_reason="Stale legacy fixture; documented in T1.2 unit suite.",
        ),
    ]
    (isolated_corpus / "f.jsonl").write_text(
        "\n".join(json.dumps(v) for v in items) + "\n"
    )
    counts = corpus_loader.count_by_status()
    assert counts == {"active": 2, "superseded": 1, "suppressed": 1}


def test_bash_python_byte_equal_iter_active(isolated_corpus, tmp_path):
    """Cross-runtime parity: bash and python emit byte-equal vector_id lists.

    Per cycle-099 cross-runtime parity traps lesson — both runtimes must use
    LC_ALL=C lexicographic sort. We compare the vector_id sequence (canonical
    field across both runtimes; full-line comparison would require deeper
    JSON-canonicalization that cycle-100 doesn't ship).
    """
    items = [
        _vector("RT-RS-005"),
        _vector("RT-RS-002"),
        _vector("RT-RS-009"),
        _vector("RT-RS-001"),
    ]
    (isolated_corpus / "f.jsonl").write_text(
        "\n".join(json.dumps(v) for v in items) + "\n"
    )

    py_ids = [v.vector_id for v in corpus_loader.iter_active()]

    sh_loader = _REPO_ROOT / "tests" / "red-team" / "jailbreak" / "lib" / "corpus_loader.sh"
    env = os.environ.copy()
    env["LOA_JAILBREAK_CORPUS_DIR"] = str(isolated_corpus)
    env["LC_ALL"] = "C"
    out = subprocess.run(
        ["bash", str(sh_loader), "iter-active"],
        capture_output=True, text=True, check=True, env=env,
    )
    sh_ids = [json.loads(line)["vector_id"] for line in out.stdout.splitlines() if line.strip()]
    assert sh_ids == py_ids, f"bash {sh_ids} != python {py_ids}"
