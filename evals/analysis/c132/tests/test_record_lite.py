"""record_lite.py — the sandbox-lite record (DEC-0811): build, manifest, reconstruct, refusals, reproduce --dry-run."""
import hashlib
import json
import os
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(os.path.dirname(HERE), "record_lite.py")
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
from c132 import record_lite  # noqa: E402


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def write(p, text):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)


@pytest.fixture
def world(tmp_path):
    """one fixture pr-91 (head/base), a suite root with task review-r91 and a v2 key naming one defect file,
    a batch c132-g1-a1 with one pipeline cell whose sandbox holds pr/head+base (head identical to the fixture,
    one base file changed), review.md, grimoires/… outputs, a defect-file copy, .git/ and .eval/ noise."""
    root = tmp_path
    fx = root / "evals" / "fixtures" / "review-prs"
    write(str(fx / "pr-91" / "head" / "src" / "a.py"), "def a():\n    return 1\n")
    write(str(fx / "pr-91" / "head" / "README.md"), "head readme\n")
    write(str(fx / "pr-91" / "base" / "src" / "a.py"), "def a():\n    return 0\n")
    write(str(fx / "pr-91" / "base" / "README.md"), "base readme\n")
    write(str(fx / "pr-91" / "head.diff"), "--- a\n+++ b\n")
    write(str(fx / "pr-91" / "PR.md"), "# PR 91\n")
    man = fx / "manifests" / "pr-91.json"
    write(str(man), json.dumps({"fixture": "pr-91", "defects": [{"file": "src/a.py", "anchors": [2]}]}))
    suite = root / "grimoires" / "loa" / "evals" / "ablation-2.0-c132"
    write(str(suite / "tasks" / "review-r91" / "task.yaml"),
          "id: review-r91\ntype: review-catch\nreview_catch: {fixture: review-prs/pr-91, manifest: evals/fixtures/review-prs/manifests/pr-91.json}\n")
    results = root / "evals" / "results" / "ablation-2.0"
    batch = results / "c132-g1-a1"
    write(str(batch / "MANIFEST.json"), json.dumps({"tasks_dir": "tasks", "allow_partial": True, "arm_map": {"r1": "a1_full"}}))
    cell = batch / "a1_full" / "review-r91-t1"
    sb = cell / "sandbox"
    write(str(sb / "pr" / "head" / "src" / "a.py"), "def a():\n    return 1\n")
    write(str(sb / "pr" / "head" / "README.md"), "head readme\n")
    write(str(sb / "pr" / "base" / "src" / "a.py"), "def a():\n    return 0\n")
    write(str(sb / "pr" / "base" / "README.md"), "base readme CHANGED\n")   # differs from the fixture → kept
    write(str(sb / "pr" / "head.diff"), "--- a\n+++ b\n")
    write(str(sb / "pr" / "PR.md"), "# PR 91\n")
    write(str(sb / "review.md"), "## Finding\nhead/src/a.py:2 returns the wrong value\n")
    write(str(sb / "grimoires" / "loa" / "a2a" / "sprint-1" / "engineer-feedback.md"), "- head/src/a.py:2\n")
    write(str(sb / "src" / "a.py"), "def a():\n    return 1  # mounted copy\n")   # the defect-file copy the oracle check reads
    write(str(sb / ".git" / "HEAD"), "ref: refs/heads/main\n")
    write(str(sb / ".eval" / "cost-ledger.jsonl"), "{}\n")
    write(str(cell / "meta" / "pipeline.json"), json.dumps({"arm": "a1_full", "run_id": "r1"}))
    write(str(cell / "transcripts" / "events-REVIEW.jsonl"), "{}\n")
    write(str(cell / "eval" / "cost-ledger.jsonl"), "{}\n")
    write(str(cell / "grading" / "gates-combined.md"), "# gates\n")
    write(str(cell / "grade.json"), json.dumps({"recall": {"recall_pm3": 1.0}}))
    return {"root": root, "results": results, "fx": fx, "suite": suite, "cell": cell, "batch": batch}


def test_build_writes_the_lite_set_and_a_complete_manifest(world, tmp_path):
    out = tmp_path / "lite"
    record_lite.build(str(world["results"]), ["c132-g1-a1"], str(world["fx"]), str(world["suite"]), str(out),
                      repo_root=str(world["root"]), log=lambda *a: None)
    rel = "c132-g1-a1/a1_full/review-r91-t1"
    lite = out / rel / "sandbox-lite"
    assert (lite / "review.md").is_file()
    assert (lite / "grimoires" / "loa" / "a2a" / "sprint-1" / "engineer-feedback.md").is_file()
    assert (lite / "src" / "a.py").is_file(), "the sandbox copy of the key defect file is kept"
    assert (lite / "pr" / "base" / "README.md").is_file(), "a pr/ file that differs from the fixture is kept"
    assert not (lite / "pr" / "head" / "src" / "a.py").exists(), "pr/ files identical to the fixture are rebuilt, not kept"
    assert not (lite / ".git" / "HEAD").exists() and not (lite / ".eval" / "cost-ledger.jsonl").exists()
    m = json.load(open(out / rel / "sandbox-manifest.json"))
    paths = {f["path"] for f in m["files"]}
    assert {"review.md", ".git/HEAD", ".eval/cost-ledger.jsonl", "pr/head/src/a.py", "src/a.py"} <= paths, "every sandbox entry is listed"
    assert m["pr_head_equals_fixture"] is True and m["pr_base_equals_fixture"] is False
    assert "pr/base/README.md" in m["pr_diffs"] and "src/a.py" in m["defect_files"]
    assert m["lite_sha256"]["review.md"] == sha(world["cell"] / "sandbox" / "review.md")
    idx = json.load(open(out / "INDEX.json"))
    assert any(rel in json.dumps(e) for e in (idx if isinstance(idx, list) else idx.values()) if True) or rel in json.dumps(idx)


def test_build_is_deterministic(world, tmp_path):
    a, b = tmp_path / "a", tmp_path / "b"
    for out in (a, b):
        record_lite.build(str(world["results"]), ["c132-g1-a1"], str(world["fx"]), str(world["suite"]), str(out),
                          repo_root=str(world["root"]), log=lambda *a: None)
    rel = "c132-g1-a1/a1_full/review-r91-t1/sandbox-manifest.json"
    assert sha(a / rel) == sha(b / rel) and sha(a / "INDEX.json") == sha(b / "INDEX.json")


def test_reconstruct_rebuilds_the_sandbox_byte_for_byte_except_the_dropped_set(world, tmp_path):
    out = tmp_path / "lite"
    record_lite.build(str(world["results"]), ["c132-g1-a1"], str(world["fx"]), str(world["suite"]), str(out),
                      repo_root=str(world["root"]), log=lambda *a: None)
    rel = "c132-g1-a1/a1_full/review-r91-t1"
    dest = tmp_path / "dest"
    record_lite.reconstruct_run_dir(str(world["results"]), str(out), str(world["fx"]), rel, str(dest))
    sb = dest / rel / "sandbox"
    orig = world["cell"] / "sandbox"
    for p in ("review.md", "grimoires/loa/a2a/sprint-1/engineer-feedback.md", "src/a.py",
              "pr/head/src/a.py", "pr/head/README.md", "pr/base/src/a.py", "pr/base/README.md", "pr/head.diff", "pr/PR.md"):
        assert sha(sb / p) == sha(orig / p), p
    assert not (sb / ".git").exists(), "the dropped set stays dropped"
    for sub in ("meta/pipeline.json", "transcripts/events-REVIEW.jsonl", "eval/cost-ledger.jsonl"):
        assert (dest / rel / sub).is_file(), "the recorded subdirectories come along"
    assert not (dest / rel / "grade.json").exists(), "the recorded grade is never copied into the reconstruction"


def test_a_symlink_in_the_lite_set_is_refused_before_any_write(world, tmp_path):
    os.symlink("/etc/hostname", str(world["cell"] / "sandbox" / "grimoires" / "loa" / "leak.md"))
    out = tmp_path / "lite"
    with pytest.raises(Exception):
        record_lite.build(str(world["results"]), ["c132-g1-a1"], str(world["fx"]), str(world["suite"]), str(out),
                          repo_root=str(world["root"]), log=lambda *a: None)
    assert not (out / "INDEX.json").exists()


def test_reproduce_dry_run_counts_cells_and_writes_nothing(world, tmp_path):
    scratch = tmp_path / "scratch"
    rc = subprocess.run([sys.executable, "-I", MOD, "reproduce", "--record-root", str(world["root"]), "--scratch", str(scratch),
                         "--batches", "c132-g1-a1", "--dry-run"], capture_output=True, text=True)
    assert rc.returncode == 0, rc.stdout + rc.stderr
    assert "1 batches, 1 cells" in rc.stdout
    assert not list((scratch / "results").rglob("*")) if (scratch / "results").exists() else True


def test_a_unit_without_a_recorded_grade_is_skipped_not_counted_as_a_difference(tmp_path):
    res = {"sessions": [{"run_dir": "b/a/t-t1/sessions/s1", "recorded": None, "reproduced": None, "recorded_graded": False,
                         "grade_equal": False, "combined_equal": False, "arm": "a0_bare_matched", "rc": None}],
           "cells": [{"run_dir": "b/a/t-t2", "recorded": "x", "reproduced": "x", "recorded_graded": True, "grade_equal": True,
                      "combined_equal": True, "arm": "a1_full", "rc": 0}],
           "unions": [], "reconstruct_errors": [], "rows": [], "reads": [], "inputs_cells": []}
    table = dict((label, (n, k)) for label, n, k in record_lite.classes(res))
    assert table["session grade.json"] == (0, 0), "an ungraded recorded unit is not tallied as graded"
    assert table["pipeline-cell grade.json"] == (1, 1)
    assert table["not graded in the record (skipped, listed below)"] == (1, 1)
    out = tmp_path / "r.md"
    ok = record_lite.write_report(res, str(out))
    text = out.read_text()
    assert ok is True, "the ungraded unit does not fail the reproduction"
    assert "## Not graded in the record" in text and "b/a/t-t1/sessions/s1" in text
    assert "## Differences\n\nNone." in text


# ---------------------------------------------------------------- cycle-133 bd-ombvn (Sprint 271 audit SEC-003/SEC-005/CQ-001)
REL = "c132-g1-a1/a1_full/review-r91-t1"


def _build(world, out):
    record_lite.build(str(world["results"]), ["c132-g1-a1"], str(world["fx"]), str(world["suite"]), str(out),
                      repo_root=str(world["root"]), log=lambda *a: None)


def _rewrite_same_size_same_mtime(p, text):
    """an in-place rewrite that keeps the inode, the size and the mtime (cp -p / rsync -t onto the same inode)"""
    st = os.stat(p)
    assert len(text.encode()) == st.st_size
    with open(p, "r+", encoding="utf-8") as f:
        f.write(text)
    os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))
    st2 = os.stat(p)
    assert (st2.st_ino, st2.st_size, st2.st_mtime_ns) == (st.st_ino, st.st_size, st.st_mtime_ns)


def test_sha256_file_verify_bypasses_the_cache(tmp_path):
    p = tmp_path / "f.txt"
    p.write_text("aaaa\n")
    first = record_lite.sha256_file(str(p))
    _rewrite_same_size_same_mtime(str(p), "bbbb\n")
    assert record_lite.sha256_file(str(p), verify=True) == sha(p) != first


def test_the_cache_key_follows_a_symlink_to_its_target(tmp_path):
    """the old key was an lstat of the path: a symlink and its target hashed through open() but keyed on the link"""
    a, b = tmp_path / "a.txt", tmp_path / "b.txt"
    a.write_text("one\n")
    b.write_text("two\n")
    link = tmp_path / "link"
    os.symlink(str(a), str(link))
    assert record_lite.sha256_file(str(link)) == sha(a)
    os.unlink(str(link))
    os.symlink(str(b), str(link))
    assert record_lite.sha256_file(str(link)) == sha(b)


def test_reconstruct_detects_a_same_size_same_mtime_rewrite_of_a_lite_file(world, tmp_path):
    out = tmp_path / "lite"
    _build(world, out)
    lite_review = out / REL / "sandbox-lite" / "review.md"
    record_lite.sha256_file(str(lite_review))          # the digest is now cached for this inode/size/mtime
    old = lite_review.read_text()
    _rewrite_same_size_same_mtime(str(lite_review), old.replace("wrong", "WRONG"))
    with pytest.raises(record_lite.Mismatch, match="lite file sha differs: review.md"):
        record_lite.reconstruct_run_dir(str(world["results"]), str(out), str(world["fx"]), REL, str(tmp_path / "d"))


def test_reconstruct_detects_a_same_size_same_mtime_rewrite_of_a_fixture_file(world, tmp_path):
    out = tmp_path / "lite"
    _build(world, out)                                  # fixture_map() hashed and cached every fixture file
    fx_readme = world["fx"] / "pr-91" / "head" / "README.md"
    _rewrite_same_size_same_mtime(str(fx_readme), "HEAD readme\n")
    with pytest.raises(record_lite.Mismatch, match="pr file not reconstructable from the fixture: pr/head/README.md"):
        record_lite.reconstruct_run_dir(str(world["results"]), str(out), str(world["fx"]), REL, str(tmp_path / "d"))


def test_compare_unit_hashes_fresh(tmp_path):
    rec, new = tmp_path / "rec", tmp_path / "new"
    for root in (rec, new):
        write(str(root / "u" / "grade.json"), '{"a": 1}\n')
        write(str(root / "u" / "grading" / "gates-combined.md"), "# g\n")
    assert record_lite.compare_unit(str(rec), str(new), "u")["grade_equal"] is True
    _rewrite_same_size_same_mtime(str(new / "u" / "grade.json"), '{"a": 2}\n')
    assert record_lite.compare_unit(str(rec), str(new), "u")["grade_equal"] is False


@pytest.mark.parametrize("target", ["/etc/passwd", "../../../../outside", "head/../../x", ""])
def test_an_unsafe_pr_symlink_target_is_refused(world, tmp_path, target):
    out = tmp_path / "lite"
    _build(world, out)
    mp = out / REL / "sandbox-manifest.json"
    m = json.load(open(mp))
    m["files"].append({"path": "pr/head/evil", "target": target, "type": "symlink"})
    m["files"].sort(key=lambda e: e["path"])
    mp.write_text(record_lite.dump_json(m))
    dest = tmp_path / "d"
    with pytest.raises(record_lite.Mismatch, match="unsafe symlink target"):
        record_lite.reconstruct_run_dir(str(world["results"]), str(out), str(world["fx"]), REL, str(dest))
    assert not os.path.lexists(str(dest / REL / "sandbox" / "pr" / "head" / "evil"))


def test_a_safe_pr_symlink_target_is_recreated(world, tmp_path):
    os.symlink("README.md", str(world["cell"] / "sandbox" / "pr" / "head" / "readme-link"))
    out = tmp_path / "lite"
    _build(world, out)
    dest = tmp_path / "d"
    record_lite.reconstruct_run_dir(str(world["results"]), str(out), str(world["fx"]), REL, str(dest))
    assert os.readlink(str(dest / REL / "sandbox" / "pr" / "head" / "readme-link")) == "README.md"


def test_build_only_writes_index_only_and_reproduce_md_names_both_index_files(world, tmp_path):
    out = tmp_path / "lite"
    record_lite.build(str(world["results"]), ["c132-g1-a1"], str(world["fx"]), str(world["suite"]), str(out),
                      only=["review-r91"], repo_root=str(world["root"]), log=lambda *a: None)
    assert (out / "INDEX-only.json").is_file() and not (out / "INDEX.json").exists()
    repro = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE)))),
                         "grimoires", "loa", "reports", "review-catch-c132", "REPRODUCE.md")
    text = open(repro, encoding="utf-8").read()
    assert "INDEX-only.json" in text and "INDEX.json" in text
