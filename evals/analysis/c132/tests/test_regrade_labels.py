"""regrade_labels.py (addendum 16): layout, cells without a key, idempotence, the label_set refusal,
--check and the refusals before writes, on synthetic run directories with a stub grader (no docker,
no model). The stub lives at <repo>/evals/harness/ablation-grade.sh beside a stub freeze.sh, so the
default repository root (three levels above the grader) is exercised."""
import contextlib
import hashlib
import io
import json
import os
import shutil
import tempfile
import unittest

import _path  # noqa: F401
from c132 import common, reads, regrade_labels

STUB_GRADER = r'''#!/usr/bin/env bash
# stub ablation-grade.sh: label_set from the key's directory, recall_pm3 = cited defects / key defects
[[ -n "${STUB_LOG:-}" ]] && echo "$*" >> "$STUB_LOG"
exec python3 -I - "$0" "$@" <<'PY'
import json, os, sys
me, argv = sys.argv[1], sys.argv[2:]
repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(me))))
def opt(n):
    return argv[argv.index(n) + 1] if n in argv else None
root, out = opt("--suite-root"), opt("--out")
if not os.path.isfile(os.path.join(root, "MANIFEST.sha256")):
    sys.exit("suite not frozen")
def key(task):
    line = [l for l in open(os.path.join(root, "tasks", task, "task.yaml")) if l.startswith("review_catch:")][0]
    rel = line.split("manifest:")[1].split(",")[0].strip().rstrip("}")
    d = os.path.basename(os.path.dirname(rel))
    ls = d if d in ("c131", "v1", "review") else "v2"
    return json.load(open(os.path.join(repo, rel))), os.environ.get("STUB_LABEL_SET") or ls
def write(path, g):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(json.dumps(g, indent=2) + "\n")
if "--union" in argv:
    cell, task = opt("--union"), opt("--task-id")
    k, ls = key(task)
    cj = json.load(open(os.path.join(cell, "meta", "cell.json")))
    os.makedirs(os.path.join(cell, "grading"), exist_ok=True)
    got, per, first = set(), [], None
    for s in cj["sessions"]:
        if s["valid"]:
            sg = json.load(open(os.path.join(cell, s["run_dir"], "grade.json")))
            got |= set(sg["recall"]["detected_pm3"])
            first = first or sg
        per.append({"session": s["id"], "valid": s["valid"]})
    open(os.path.join(cell, "grading", "gates-combined.md"), "w").write(" ".join(sorted(got)) + "\n")
    n = len(k["defects"])
    g = {"grader_version": "9.9.9", "union": True, "sessions_valid": sum(1 for s in cj["sessions"] if s["valid"]),
         "per_session": per, "recall": {"defects_seeded": n, "recall_pm3": len(got) / n,
         "missed_pm3": sorted(set(d["id"] for d in k["defects"]) - got)}}
    if first:
        g["label_set"] = first["label_set"]
    write(out, g)
    sys.exit(0)
rd, task = argv[0], argv[1]
if not os.path.isdir(os.path.join(rd, "sandbox")):
    sys.exit("no sandbox/ under %s" % rd)
k, ls = key(task)
cited = open(os.path.join(rd, "sandbox", "review.md")).read().split()
ids = [d["id"] for d in k["defects"]]
det = [d for d in ids if d in cited]
os.makedirs(os.path.join(rd, "grading"), exist_ok=True)
open(os.path.join(rd, "grading", "gates-combined.md"), "w").write(" ".join(cited) + "\n")
write(out, {"grader_version": "9.9.9", "label_set": ls, "contaminated": None,
            "recall": {"defects_seeded": len(ids), "recall_pm3": len(det) / len(ids), "detected_pm3": det,
                       "missed_pm3": [d for d in ids if d not in det]}})
PY
'''

STUB_FREEZE = r'''#!/usr/bin/env bash
exec python3 -I - "$@" <<'PY'
import hashlib, os, sys
root = sys.argv[sys.argv.index("--root") + 1]
lines = []
for dp, ds, fs in os.walk(os.path.join(root, "tasks")):
    for f in fs:
        p = os.path.join(dp, f)
        lines.append("%s  %s" % (hashlib.sha256(open(p, "rb").read()).hexdigest(), os.path.relpath(p, root)))
open(os.path.join(root, "MANIFEST.sha256"), "w").write("\n".join(sorted(lines)) + "\n")
PY
'''

# fixture → {label dir: defect ids}; pr-03 has no key in any set
KEYS = {"pr-01": {"": ["d1", "d2", "d3"], "c131": ["d1", "d2"], "v1": ["d1"]},
        "pr-02": {"": ["d1", "d2"], "review": ["d1", "d2", "d3", "d4"]},
        "pr-03": {"": ["d1"]}}
TASKS = {"review-a": "pr-01", "review-b": "pr-02", "review-c": "pr-03"}


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def tree_state(root):
    out = {}
    for dp, ds, fs in os.walk(root):
        for n in ds + fs:
            p = os.path.join(dp, n)
            st = os.lstat(p)
            h = hashlib.sha256(open(p, "rb").read()).hexdigest() if os.path.isfile(p) and not os.path.islink(p) else None
            out[os.path.relpath(p, root)] = (st.st_mode, st.st_size, st.st_mtime_ns, h)
    return out


class RegradeLabelsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-regrade-")
        t = self.tmp
        self.repo = os.path.join(t, "repo")
        h = os.path.join(self.repo, "evals", "harness")
        write(os.path.join(h, "ablation-grade.sh"), STUB_GRADER)
        write(os.path.join(h, "freeze.sh"), STUB_FREEZE)
        self.grader = os.path.join(h, "ablation-grade.sh")
        man = os.path.join(self.repo, "evals", "fixtures", "review-prs", "manifests")
        for pr, sets in KEYS.items():
            for d, ids in sets.items():
                write(os.path.join(man, d, pr + ".json"), json.dumps({"defects": [{"id": i} for i in ids]}))
        self.suite = os.path.join(t, "suite")
        for task, pr in TASKS.items():
            write(os.path.join(self.suite, "tasks", task, "task.yaml"),
                  "id: %s\ntype: review-catch\nreview_catch: {fixture: review-prs/%s, manifest: "
                  "evals/fixtures/review-prs/manifests/%s.json, bare_sessions_matched: 2}\n" % (task, pr, pr))
        write(os.path.join(self.suite, "MANIFEST.sha256"), "original\n")
        self.results = os.path.join(t, "results")
        rows = []
        for task in TASKS:
            # a single run: cites d1 d2 d4
            d = os.path.join(self.results, "c132-g1-a1", "a1_full", "%s-t1" % task)
            write(os.path.join(d, "sandbox", "review.md"), "d1 d2 d4\n")
            write(os.path.join(d, "transcripts", "events-REVIEW.jsonl"), "{}\n")
            write(os.path.join(d, "grade.json"), '{"recorded": true}\n')
            write(os.path.join(d, "grading", "gates-combined.md"), "recorded\n")
            rows.append({"batch": "c132-g1-a1", "arm": "a1_full", "task_id": task, "trial": 1, "status": "completed"})
            # a matched cell: s1 cites d1, s2 cites d3, s3 invalid without a sandbox (fails to grade)
            c = os.path.join(self.results, "c132-g1-a2", "a0_bare_matched", "%s-t1" % task)
            for sid, cites in (("s1", "d1"), ("s2", "d3")):
                write(os.path.join(c, "sessions", sid, "sandbox", "review.md"), cites + "\n")
                write(os.path.join(c, "sessions", sid, "grade.json"), '{"recorded": true}\n')
                write(os.path.join(c, "sessions", sid, "grading", "gates-combined.md"), "recorded\n")
            os.makedirs(os.path.join(c, "sessions", "s3", "transcripts"))
            write(os.path.join(c, "sessions", "s1.log"), "log\n")
            write(os.path.join(c, "meta", "cell.json"), json.dumps({"k": 3, "sessions": [
                {"id": "s1", "run_dir": "sessions/s1", "valid": True},
                {"id": "s2", "run_dir": "sessions/s2", "valid": True},
                {"id": "s3", "run_dir": "sessions/s3", "valid": False}]}))
            write(os.path.join(c, "grade.json"), '{"recorded": true}\n')
            write(os.path.join(c, "grading", "gates-combined.md"), "recorded\n")
            rows.append({"batch": "c132-g1-a2", "arm": "a0_bare_matched", "task_id": task, "trial": 1,
                         "status": "completed", "bare_sessions": 3, "sessions_valid": 2})
        self.rows = os.path.join(t, "rows.jsonl")
        write(self.rows, "".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
        self.out, self.work, self.roots = (os.path.join(t, n) for n in ("out", "work", "roots"))
        self.log = os.path.join(t, "grader.log")
        os.environ["STUB_LOG"] = self.log
        os.environ.pop("STUB_LABEL_SET", None)

    def tearDown(self):
        os.environ.pop("STUB_LOG", None)
        os.environ.pop("STUB_LABEL_SET", None)
        regrade_labels.safe_rmtree(self.work, self.tmp) if os.path.isdir(self.work) else None
        shutil.rmtree(self.tmp)

    def run_tool(self, *extra, out=None, labels="c131,v1,review"):
        argv = ["--rows", self.rows, "--results-root", self.results, "--suite-root", self.suite, "--labels", labels,
                "--out", out or self.out, "--work", self.work, "--roots", self.roots, "--grader", self.grader,
                "--jobs", "2"] + list(extra)
        so, se = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(so), contextlib.redirect_stderr(se):
            rc = regrade_labels.main(argv)
        return rc, so.getvalue(), se.getvalue()

    def calls(self):
        return len(open(self.log).read().splitlines()) if os.path.isfile(self.log) else 0

    def jl(self, *p):
        with open(os.path.join(*p)) as f:
            return json.load(f)

    def test_layout_keys_and_record_untouched(self):
        before, suite_before = tree_state(self.results), tree_state(self.suite)
        rc, so, se = self.run_tool()
        self.assertEqual(rc, 0, se)
        self.assertEqual(tree_state(self.results), before)
        self.assertEqual(tree_state(self.suite), suite_before)
        # c131: only pr-01 has a key; the single run cites d1 d2 of {d1, d2}
        g = self.jl(self.out, "c131", "c132-g1-a1", "a1_full", "review-a-t1", "grade.json")
        self.assertEqual((g["label_set"], g["recall"]["recall_pm3"]), ("c131", 1.0))
        u = self.jl(self.out, "c131", "c132-g1-a2", "a0_bare_matched", "review-a-t1", "grade.json")
        self.assertEqual((u["label_set"], u["recall"]["missed_pm3"]), ("c131", ["d2"]))
        s1 = os.path.join(self.out, "c131", "c132-g1-a2", "a0_bare_matched", "review-a-t1", "sessions")
        self.assertTrue(os.path.isfile(os.path.join(s1, "s1", "grade.json")))
        self.assertFalse(os.path.exists(os.path.join(s1, "s3")))
        idx = self.jl(self.out, "c131", "INDEX.json")
        self.assertEqual(idx["n_cells"], 2)
        self.assertEqual(idx["n_sessions"], 2)
        self.assertEqual(idx["label_sets_observed"], {"c131": 4})
        self.assertEqual(sorted(c["key"] for c in idx["cells_without_key"]), [
            "c132-g1-a1/a1_full/review-b/1", "c132-g1-a1/a1_full/review-c/1",
            "c132-g1-a2/a0_bare_matched/review-b/1", "c132-g1-a2/a0_bare_matched/review-c/1"])
        self.assertEqual(idx["suite_root"]["repointed"], {"review-a": {
            "from": "evals/fixtures/review-prs/manifests/pr-01.json", "to": "evals/fixtures/review-prs/manifests/c131/pr-01.json"}})
        self.assertTrue(idx["suite_root"]["frozen"])
        root_manifest = os.path.join(self.roots, "c131", "MANIFEST.sha256")
        self.assertEqual(idx["suite_root"]["manifest_sha256"], common.sha256_file(root_manifest))
        self.assertEqual(open(os.path.join(self.out, "c131", "MANIFEST.sha256")).read(), open(root_manifest).read())
        matched = [c for c in idx["cells"] if c["matched"]][0]
        s3 = [s for s in matched["sessions"] if s["id"] == "s3"][0]
        self.assertIsNone(s3["grade"])
        self.assertIn("no sandbox", s3["error"])
        for c in idx["cells"]:
            self.assertEqual(c["grade_sha256"], common.sha256_file(os.path.join(self.out, "c131", c["grade"])))
        self.assertNotIn(self.tmp, open(os.path.join(self.out, "c131", "INDEX.json")).read())
        # review: review/ for pr-02, the c131/ fallback for pr-01; pr-03 without a key
        rv = self.jl(self.out, "review", "INDEX.json")
        self.assertEqual({t: k["label_set"] for t, k in rv["keys"].items()}, {"review-a": "c131", "review-b": "review"})
        self.assertEqual(rv["label_sets_observed"], {"c131": 4, "review": 4})
        gb = self.jl(self.out, "review", "c132-g1-a1", "a1_full", "review-b-t1", "grade.json")
        self.assertEqual((gb["label_set"], gb["recall"]["recall_pm3"]), ("review", 0.75))
        self.assertEqual(self.jl(self.out, "v1", "INDEX.json")["keys"]["review-a"]["label_set"], "v1")
        # the work copy's files are hard links to the record; the record's grading/ and grade.json are not copied
        w = os.path.join(self.work, "c131", "c132-g1-a1", "a1_full", "review-a-t1")
        rec = os.path.join(self.results, "c132-g1-a1", "a1_full", "review-a-t1")
        self.assertTrue(os.path.samefile(os.path.join(w, "sandbox", "review.md"), os.path.join(rec, "sandbox", "review.md")))
        self.assertEqual(open(os.path.join(w, "grading", "gates-combined.md")).read(), "d1 d2 d4\n")
        # reads.py builds the cells without a key with grade None
        cells = common.load_cells(common.load_rows(self.rows), [self.results])
        common.assign_pair_trials(cells)
        rc_cells = reads.regrade_cells(cells, self.out, "c131")
        by = {c["key"]: c for c in rc_cells}
        self.assertEqual(by["c132-g1-a1/a1_full/review-a/1"]["caught"], 2)
        self.assertIsNone(by["c132-g1-a1/a1_full/review-b/1"]["grade"])
        self.assertIn("no_defect_record", by["c132-g1-a1/a1_full/review-b/1"]["reasons"])

    def test_idempotent_and_force(self):
        rc, _so, se = self.run_tool()
        self.assertEqual(rc, 0, se)
        n, first = self.calls(), tree_state(self.out)
        rc, _so, se = self.run_tool()
        self.assertEqual(rc, 0, se)
        self.assertEqual(self.calls(), n)                   # every copy holds its grade: nothing re-graded
        self.assertEqual({k: v[3] for k, v in tree_state(self.out).items()}, {k: v[3] for k, v in first.items()})
        rc, _so, se = self.run_tool("--force")
        self.assertEqual(rc, 0, se)
        self.assertEqual(self.calls(), 2 * n)
        self.assertEqual({k: v[3] for k, v in tree_state(self.out).items()}, {k: v[3] for k, v in first.items()})
        # a second output tree from scratch is byte-identical (determinism)
        other = os.path.join(self.tmp, "out2")
        regrade_labels.safe_rmtree(self.work, self.tmp)
        rc, _so, se = self.run_tool(out=other)
        self.assertEqual(rc, 0, se)
        self.assertEqual({k: v[3] for k, v in tree_state(other).items()}, {k: v[3] for k, v in first.items()})

    def test_resume_after_partial_copy(self):
        part = os.path.join(self.work, "c131", "c132-g1-a1", "a1_full", "review-a-t1")
        os.makedirs(os.path.join(part, "sandbox"))
        rc, _so, se = self.run_tool(labels="c131")
        self.assertEqual(rc, 0, se)
        self.assertTrue(os.path.isfile(os.path.join(part, "sandbox", "review.md")))

    def test_label_set_mismatch_refused(self):
        os.environ["STUB_LABEL_SET"] = "v2"
        rc, _so, se = self.run_tool(labels="c131")
        self.assertEqual(rc, 1)
        self.assertIn("label_set 'v2', the key directory is 'c131'", se)
        self.assertFalse(os.path.exists(os.path.join(self.out, "c131", "INDEX.json")))
        self.assertEqual([f for _d, _s, fs in os.walk(self.out) for f in fs if f == "grade.json"], [])

    def test_suite_root_change_refused_without_force(self):
        rc, _so, se = self.run_tool(labels="c131")
        self.assertEqual(rc, 0, se)
        with open(os.path.join(self.suite, "tasks", "review-a", "TASK.md"), "w") as f:
            f.write("changed\n")
        rc, _so, se = self.run_tool(labels="c131")
        self.assertEqual(rc, 1)
        self.assertIn("differs from the one the work tree was graded under", se)
        rc, _so, se = self.run_tool("--force", labels="c131")
        self.assertEqual(rc, 0, se)

    def test_check(self):
        rc, _so, se = self.run_tool()
        self.assertEqual(rc, 0, se)
        rc, so, se = self.run_tool("--check")
        self.assertEqual(rc, 0, se)
        doc = json.loads(so)
        self.assertTrue(doc["pass"])
        self.assertEqual(len(doc["sample"]), 3)
        self.assertGreaterEqual(doc["files_compared"], 6)
        self.assertEqual(self.jl(self.out, "CHECK.json"), doc)
        self.assertEqual(sorted(os.listdir(self.work)), ["c131", "review", "v1"])     # the temp dir is gone
        # a tampered output is caught
        for s in doc["sample"]:
            lab, key = s["label"], s["key"]
            b, a, t, tr = key.split("/")
            p = os.path.join(self.out, lab, b, a, "%s-t%s" % (t, tr), "grade.json")
            with open(p, "a") as f:
                f.write(" ")
        rc, so, _se = self.run_tool("--check")
        self.assertEqual(rc, 1)
        self.assertFalse(json.loads(so)["pass"])

    def test_dry_run_and_refusals_write_nothing(self):
        rc, so, se = self.run_tool("--dry-run")
        self.assertEqual(rc, 0, se)
        plan = json.loads(so)
        self.assertEqual(plan["labels"]["review"]["cells_without_key"],
                         ["c132-g1-a1/a1_full/review-c/1", "c132-g1-a2/a0_bare_matched/review-c/1"])
        self.assertEqual(plan["sessions"], 9)
        for p in (self.out, self.work, self.roots):
            self.assertFalse(os.path.exists(p))
        before = tree_state(self.results)
        rc, _so, se = self.run_tool(out=os.path.join(self.results, "sens"))
        self.assertEqual(rc, 1)
        self.assertIn("inside the results root", se)
        rc, _so, se = self.run_tool("--only", "review-z")
        self.assertEqual(rc, 1)
        os.rename(os.path.join(self.results, "c132-g1-a1", "a1_full", "review-b-t1", "sandbox"),
                  os.path.join(self.results, "c132-g1-a1", "a1_full", "review-b-t1", "sandbox.x"))
        rc, _so, se = self.run_tool()
        self.assertEqual(rc, 1)
        self.assertIn("no sandbox/", se)
        os.rename(os.path.join(self.results, "c132-g1-a1", "a1_full", "review-b-t1", "sandbox.x"),
                  os.path.join(self.results, "c132-g1-a1", "a1_full", "review-b-t1", "sandbox"))
        # the renames above move one directory's mtime: compare paths and contents
        self.assertEqual({k: v[3] for k, v in tree_state(self.results).items()}, {k: v[3] for k, v in before.items()})
        for p in (self.out, self.work, self.roots):
            self.assertFalse(os.path.exists(p))
        self.assertEqual(self.run_tool(labels="c131,v2")[0], 2)
        self.assertEqual(self.run_tool(labels="c131,c131")[0], 2)

    def test_only(self):
        rc, _so, se = self.run_tool("--only", "review-b", labels="review")
        self.assertEqual(rc, 0, se)
        idx = self.jl(self.out, "review", "INDEX.json")
        self.assertEqual(idx["only"], ["review-b"])
        self.assertEqual(sorted(c["task"] for c in idx["cells"]), ["review-b", "review-b"])


if __name__ == "__main__":
    unittest.main()
