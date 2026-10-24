"""judge_defects.py (EXPLORATORY defect-level judge read): sampling, leak refusal, aggregation.

The sample tests build a tiny synthetic world (fixture, manifest, task.yaml, run dirs, rows) and
produce its source key with the real evals/harness/judge-sample.sh, so the packets can be compared
with judge-sample.sh's own for the same units. The aggregation tests use a hand-built key.
"""
import contextlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest

import _path  # noqa: F401
from c132 import judge_defects as jd

REPO = os.path.dirname(_path.ANALYSIS_DIR)
JUDGE_SAMPLE = os.path.join(REPO, "harness", "judge-sample.sh")
BATCH = "zb-batch"
TASKS = ("review-x1", "review-x2", "review-x3")
SITES = (10, 30, 50)
# per arm: the gates-combined.md citations (line ranges in head/src/f.py) and the review paragraphs
CITES = {"a1_full": [(10, 10), (11, 12), (30, 30), (58, 58)],
         "a0_bare_matched": [(10, 10), (40, 40)]}


def _w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def build_world(root, leak_text=None):
    """repo root, results root, rows, descriptions under root; returns their paths"""
    repo, res = os.path.join(root, "repo"), os.path.join(root, "results")
    descs = {"schema_version": 1, "fixtures": {}}
    rows = []
    for t in TASKS:
        fx = "pr-%s" % t[-2:]
        fdir = os.path.join(repo, "evals/fixtures/tfx", fx)
        _w(os.path.join(fdir, "head/src/f.py"), "".join("line_%d = %d\n" % (i, i) for i in range(1, 61)))
        _w(os.path.join(fdir, "PR.md"), "# PR %s\n" % fx)
        man = {"fixture": fx, "defects": [{"id": "V%02d" % (i + 1), "file": "src/f.py", "anchor_line": s,
                                           "description": "manifest text %d" % (i + 1)} for i, s in enumerate(SITES)]}
        _w(os.path.join(fdir, "manifest.json"), json.dumps(man))
        _w(os.path.join(repo, "suite/tasks", t, "task.yaml"),
           "id: %s\nreview_catch: {fixture: tfx/%s, manifest: evals/fixtures/tfx/%s/manifest.json}\n" % (t, fx, fx))
        descs["fixtures"][fx] = {"V%02d" % (i + 1): {"text": "annotator text %s %d" % (fx, i + 1)} for i in range(3)}
        for arm, cites in sorted(CITES.items()):
            rd = os.path.join(res, BATCH, arm, "%s-t1" % t)
            _w(os.path.join(rd, "grading/gates-combined.md"), "".join("src/f.py:%d-%d\n" % c for c in cites))
            paras = ["head/src/f.py:%d — finding about lines %d to %d in %s." % (a, a, b, t) for a, b in cites]
            if leak_text and arm == "a1_full" and t == TASKS[0]:
                paras[0] += " " + leak_text
            _w(os.path.join(rd, "sandbox/review.md"), "\n\n".join(paras) + "\n")
            credited = {i for i, s in enumerate(SITES) for a, b in cites if max(0, a - s, s - b) <= 3}
            missed = ["d%d" % (i + 1) for i in range(3) if i not in credited]
            _w(os.path.join(rd, "grade.json"), json.dumps({"recall": {"missed_pm3": missed}, "contaminated": None}))
            rows.append({"batch": BATCH, "arm": arm, "task_id": t, "task_type": "review-catch", "trial": 1,
                         "run_id": "zb-run-%s-%s" % (arm, t), "status": "completed", "contaminated": None,
                         "oracle_exposed_defects": [], "defects_seeded": 3, "defects_missed_pm3": missed})
    rows_path = os.path.join(root, "rows.jsonl")
    _w(rows_path, "".join(json.dumps(r, sort_keys=True) + "\n" for r in rows))
    descs_path = os.path.join(root, "descs.json")
    _w(descs_path, json.dumps(descs))
    return repo, res, rows_path, descs_path


def run_cli(argv):
    err = io.StringIO()
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
        rc = jd.main(argv)
    return rc, err.getvalue()


def tree(d):
    out = {}
    for base, _dns, fns in os.walk(d):
        for n in fns:
            p = os.path.join(base, n)
            with open(p, "rb") as f:
                out[os.path.relpath(p, d)] = f.read()
    return out


@unittest.skipUnless(shutil.which("bash") and shutil.which("jq"), "judge-sample.sh needs bash and jq")
class SampleTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.repo, self.res, self.rows, self.descs = build_world(self.tmp)
        self.src = os.path.join(self.tmp, "src")
        p = subprocess.run(["bash", JUDGE_SAMPLE, "--rows", self.rows, "--results-root", self.res, "--out", self.src,
                            "--seed", "7", "--per-stratum", "50", "--suite-root", os.path.join(self.repo, "suite"),
                            "--repo-root", self.repo, "--descriptions", self.descs],
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def sample(self, out, per_arm=40, seed=20261021, rows=None):
        return run_cli(["sample", "--key", os.path.join(self.src, "key.json"), "--rows", rows or self.rows,
                        "--results-root", self.res, "--descriptions", self.descs, "--out", out,
                        "--seed", str(seed), "--per-arm", str(per_arm),
                        "--suite-root", os.path.join(self.repo, "suite"), "--repo-root", self.repo])

    def test_all_pairs_and_every_citation(self):
        out = os.path.join(self.tmp, "o1")
        self.assertEqual(self.sample(out)[0], 0)
        key = json.load(open(os.path.join(out, "key.json")))
        # a1_full credits d1 (two regions) and d2 per PR; a0_bare_matched d1 (one region)
        self.assertEqual(key["universe"]["a1_full"]["credited_pairs"], 6)
        self.assertEqual(key["universe"]["a1_full"]["credited_units"], 9)
        self.assertEqual(key["universe"]["a0_bare_matched"]["credited_pairs"], 3)
        self.assertEqual(key["universe"]["a1_full"]["sampled_pairs"], 6)
        self.assertEqual(len(key["items"]), 12)
        self.assertEqual(sorted(os.listdir(os.path.join(out, "packets"))), ["D%04d.md" % i for i in range(1, 13)])
        for p in key["pairs"].values():
            n = 2 if (p["arm"], p["defect"]) == ("a1_full", "d1") else 1
            self.assertEqual(len(p["items"]), n)
        self.assertNotIn(self.tmp, json.dumps(key))

    def test_per_arm_cap_and_inclusion(self):
        out = os.path.join(self.tmp, "o2")
        self.assertEqual(self.sample(out, per_arm=2)[0], 0)
        key = json.load(open(os.path.join(out, "key.json")))
        for arm, n_pairs in (("a1_full", 6), ("a0_bare_matched", 3)):
            u = key["universe"][arm]
            self.assertEqual(u["sampled_pairs"], 2)
            self.assertAlmostEqual(u["pi"], 2.0 / n_pairs)
            self.assertEqual(sum(1 for p in key["pairs"].values() if p["arm"] == arm), 2)
        self.assertEqual(len(key["items"]), sum(len(p["items"]) for p in key["pairs"].values()))

    def test_deterministic_and_seeded(self):
        a, b, c = (os.path.join(self.tmp, n) for n in ("a", "b", "c"))
        for d in (a, b):
            self.assertEqual(self.sample(d, per_arm=2)[0], 0)
        self.assertEqual(tree(a), tree(b))
        self.assertEqual(self.sample(c, per_arm=2, seed=99)[0], 0)
        ka, kc = (json.load(open(os.path.join(d, "key.json"))) for d in (a, c))
        self.assertNotEqual([p["units"] for p in ka["pairs"].values()], [p["units"] for p in kc["pairs"].values()])

    def test_packets_match_judge_sample(self):
        out = os.path.join(self.tmp, "o3")
        self.assertEqual(self.sample(out)[0], 0)
        key = json.load(open(os.path.join(out, "key.json")))
        src = json.load(open(os.path.join(self.src, "key.json")))
        by_unit = {it["unit"]: j for j, it in src["items"].items()}
        for d, it in key["items"].items():
            j = by_unit[it["unit"]]
            a = open(os.path.join(out, "packets", d + ".md")).read().replace(d, "X", 1)
            # the one difference from judge-sample.sh's layout: the sample id line (cycle-133 bd-xr3uq)
            a = a.replace("Sample: `%s`\n\n" % key["sample_id"], "", 1)
            b = open(os.path.join(self.src, "packets", j + ".md")).read().replace(j, "X", 1)
            self.assertEqual(a, b)
            self.assertIn("annotator text", a)
            for tok in (BATCH, "zb-run", "a1_full", "a0_bare", "credited"):
                self.assertNotIn(tok, a)

    def test_leak_refuses_whole_run(self):
        shutil.rmtree(self.tmp)
        os.makedirs(self.tmp)
        self.repo, self.res, self.rows, self.descs = build_world(self.tmp, leak_text="(see %s)" % BATCH)
        # the source key from a clean world: the leak sits only in the run dir the packets read
        clean = tempfile.mkdtemp()
        try:
            crepo, cres, crows, cdescs = build_world(clean)
            p = subprocess.run(["bash", JUDGE_SAMPLE, "--rows", crows, "--results-root", cres, "--out", self.src,
                                "--seed", "7", "--per-stratum", "50", "--suite-root", os.path.join(crepo, "suite"),
                                "--repo-root", crepo], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)
        finally:
            shutil.rmtree(clean)
        out = os.path.join(self.tmp, "leak")
        rc, err = self.sample(out)
        self.assertEqual(rc, 1)
        self.assertIn("provenance field (%s)" % BATCH, err)
        self.assertFalse(os.path.exists(out))

    def test_arm_field_line_refused(self):
        shutil.rmtree(self.tmp)
        os.makedirs(self.tmp)
        self.repo, self.res, self.rows, self.descs = build_world(self.tmp, leak_text="\narm: something")
        clean = tempfile.mkdtemp()
        try:
            crepo, cres, crows, _ = build_world(clean)
            p = subprocess.run(["bash", JUDGE_SAMPLE, "--rows", crows, "--results-root", cres, "--out", self.src,
                                "--seed", "7", "--suite-root", os.path.join(crepo, "suite"), "--repo-root", crepo],
                               capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)
        finally:
            shutil.rmtree(clean)
        rc, err = self.sample(os.path.join(self.tmp, "leak2"))
        self.assertEqual(rc, 1)
        self.assertIn("provenance field (arm:", err)

    def test_refuses_nonempty_out_and_invalid_cells_drop(self):
        out = os.path.join(self.tmp, "o4")
        self.assertEqual(self.sample(out)[0], 0)
        self.assertEqual(self.sample(out)[0], 1)
        rows = [json.loads(x) for x in open(self.rows)]
        rows[0]["status"] = "failed"
        rp = os.path.join(self.tmp, "rows2.jsonl")
        _w(rp, "".join(json.dumps(r) + "\n" for r in rows))
        out2 = os.path.join(self.tmp, "o5")
        self.assertEqual(self.sample(out2, rows=rp)[0], 0)
        key = json.load(open(os.path.join(out2, "key.json")))
        self.assertEqual(len(key["invalid_cells_skipped"]), 1)
        self.assertNotIn(key["invalid_cells_skipped"][0], key["cells"])

    # ---------------------------------------------- cycle-133 bd-xr3uq: labels bound to the sample
    def test_sample_id_in_the_key_and_every_packet_header(self):
        out = os.path.join(self.tmp, "sid")
        self.assertEqual(self.sample(out)[0], 0)
        key = json.load(open(os.path.join(out, "key.json")))
        sid = key["sample_id"]
        self.assertRegex(sid, r"^[0-9a-f]{12}$")
        self.assertEqual(jd.sample_id_of(key), sid)
        body = dict(key)
        del body["sample_id"]
        import hashlib
        self.assertEqual(hashlib.sha256((json.dumps(body, sort_keys=True, indent=1) + "\n").encode()).hexdigest()[:12], sid)
        for n in os.listdir(os.path.join(out, "packets")):
            text = open(os.path.join(out, "packets", n)).read()
            self.assertEqual(text.splitlines()[2], "Sample: `%s`" % sid, n)

    def test_an_existing_key_needs_force_and_force_replaces_the_sample(self):
        out = os.path.join(self.tmp, "force")
        self.assertEqual(self.sample(out)[0], 0)
        first = json.load(open(os.path.join(out, "key.json")))["sample_id"]
        shutil.rmtree(os.path.join(out, "packets"))           # the packets cleared: the old guard alone let this through
        rc, err = self.sample(out, seed=99, per_arm=2)
        self.assertEqual(rc, 1)
        self.assertIn("--force", err)
        self.assertEqual(json.load(open(os.path.join(out, "key.json")))["sample_id"], first, "key.json untouched")
        rc, err = run_cli(["sample", "--key", os.path.join(self.src, "key.json"), "--rows", self.rows,
                           "--results-root", self.res, "--descriptions", self.descs, "--out", out, "--seed", "99",
                           "--per-arm", "2", "--suite-root", os.path.join(self.repo, "suite"), "--repo-root", self.repo,
                           "--force"])
        self.assertEqual(rc, 0, err)
        key = json.load(open(os.path.join(out, "key.json")))
        self.assertNotEqual(key["sample_id"], first)
        self.assertEqual(sorted(os.listdir(os.path.join(out, "packets"))), sorted(i + ".md" for i in key["items"]))

    def test_stale_labels_against_a_new_key_are_rejected(self):
        a, b = os.path.join(self.tmp, "ka"), os.path.join(self.tmp, "kb")
        self.assertEqual(self.sample(a, per_arm=2)[0], 0)
        self.assertEqual(self.sample(b, per_arm=2, seed=5)[0], 0)
        ka, kb = (json.load(open(os.path.join(d, "key.json"))) for d in (a, b))
        self.assertNotEqual(ka["sample_id"], kb["sample_id"])
        lab = {i: {"verdict": "describes", "note": ""} for i in ka["items"]}
        lab["sample_id"] = ka["sample_id"]
        lp = os.path.join(self.tmp, "labels-a.json")
        _w(lp, json.dumps(lab))
        base = ["aggregate", "--labels", lp, "--rows", self.rows, "--results-root", self.res, "--boot", "50"]
        rc, err = run_cli(base + ["--key", os.path.join(a, "key.json"), "--out", os.path.join(self.tmp, "ra")])
        self.assertEqual(rc, 0, err)
        rc, err = run_cli(base + ["--key", os.path.join(b, "key.json"), "--out", os.path.join(self.tmp, "rb")])
        self.assertEqual(rc, 1)
        self.assertIn("sample_id", err)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "rb")))

    def test_aggregate_loads_the_grades_for_its_validity_filter(self):
        out = os.path.join(self.tmp, "gv")
        self.assertEqual(self.sample(out, per_arm=2)[0], 0)
        key = json.load(open(os.path.join(out, "key.json")))
        lab = {i: {"verdict": "describes", "note": ""} for i in key["items"]}
        lab["sample_id"] = key["sample_id"]
        lp = os.path.join(self.tmp, "labels-gv.json")
        _w(lp, json.dumps(lab))
        ck = sorted(key["cells"])[0]
        b, arm, task, trial = ck.split("/")
        gp = os.path.join(self.res, b, arm, "%s-t%s" % (task, trial), "grade.json")
        g = json.load(open(gp))
        g["contaminated"] = {"pattern": "outside_path"}          # the row says clean, the grade says contaminated
        _w(gp, json.dumps(g))
        rc, err = run_cli(["aggregate", "--key", os.path.join(out, "key.json"), "--labels", lp, "--rows", self.rows,
                           "--results-root", self.res, "--out", os.path.join(self.tmp, "rg"), "--boot", "50"])
        self.assertEqual(rc, 1)
        self.assertIn(ck, err)

    def test_usage(self):
        self.assertEqual(run_cli([])[0], 2)
        self.assertEqual(run_cli(["aggregate", "--key", "k", "--labels", "l", "--rows", "r", "--out", "o"])[0], 2,
                         "aggregate needs --results-root")
        self.assertEqual(run_cli(["sample", "--key", "x"])[0], 2)


def hand_key():
    """two arms over PRs p1, p2; pairs with their items"""
    cells = {"b/a1_full/p1/1": {"arm": "a1_full", "task": "p1", "trial": 1, "defects": 4, "credited": ["d1", "d2"]},
             "b/a1_full/p2/1": {"arm": "a1_full", "task": "p2", "trial": 1, "defects": 4, "credited": ["d1", "d3"]},
             "b/a0_bare_matched/p1/1": {"arm": "a0_bare_matched", "task": "p1", "trial": 1, "defects": 4,
                                        "credited": ["d1"]},
             "b/a0_bare_matched/p2/1": {"arm": "a0_bare_matched", "task": "p2", "trial": 1, "defects": 4,
                                        "credited": ["d3"]}}
    spec = [("P001", "b/a1_full/p1/1", "d1", 2), ("P002", "b/a1_full/p1/1", "d2", 1), ("P003", "b/a1_full/p2/1", "d1", 3),
            ("P004", "b/a1_full/p2/1", "d3", 1), ("P005", "b/a0_bare_matched/p1/1", "d1", 1),
            ("P006", "b/a0_bare_matched/p2/1", "d3", 2)]
    pairs, items, n = {}, {}, 0
    for pid, ck, did, m in spec:
        c = cells[ck]
        ids = []
        for _ in range(m):
            n += 1
            iid = "D%04d" % n
            ids.append(iid)
            items[iid] = {"unit": "U%05d" % n, "cell": ck, "arm": c["arm"], "task": c["task"], "trial": 1,
                          "class": "credited", "region": ["f.py", n, n], "defect": did, "grader_credit": True,
                          "pair": pid, "cited_path_resolution": "exact", "description_source": "annotators"}
        pairs[pid] = {"cell": ck, "arm": c["arm"], "pr": c["task"], "trial": 1, "defect": did, "items": ids,
                      "units": [items[i]["unit"] for i in ids], "inclusion_probability": 1.0}
    universe = {a: {"cells": 2, "prs": 2, "defects": 8, "credited_pairs": k, "credited_units": 0,
                    "sampled_pairs": k, "sampled_units": 0, "pi": 1.0} for a, k in (("a1_full", 4), ("a0_bare_matched", 2))}
    return jd.with_sample_id({"schema_version": 1, "seed": 20261021, "per_arm": 40, "universe": universe, "pairs": pairs,
                              "items": items, "cells": cells})


def hand_rows():
    return [{"batch": "b", "arm": c.split("/")[1], "task_id": c.split("/")[2], "trial": 1, "status": "completed",
             "contaminated": None, "oracle_exposed_defects": [], "defects_seeded": 4, "defects_missed_pm3": []}
            for c in hand_key()["cells"]]


# items D0001-D0002 P001, D0003 P002, D0004-D0006 P003, D0007 P004, D0008 P005, D0009-D0010 P006
LABELS = {"D0001": "does-not-describe", "D0002": "describes",          # P001 strict hit
          "D0003": "partially",                                        # P002 lenient only
          "D0004": "does-not-describe", "D0005": "does-not-describe", "D0006": "does-not-describe",  # P003 miss
          "D0007": "describes",                                        # P004 strict hit
          "D0008": "partially",                                        # P005 lenient only
          "D0009": "does-not-describe", "D0010": "does-not-describe"}  # P006 miss


def labels(over=None, sample_id=None):
    d = dict(LABELS, **(over or {}))
    out = {k: {"verdict": v, "note": "n"} for k, v in d.items() if v is not None}
    out["sample_id"] = sample_id or hand_key()["sample_id"]
    return out


GRADES = {}   # hand_rows carry everything the validity filter needs; no cell's grade adds a reason


def hand_results(root):
    """a results root holding one grade.json per hand row (what aggregate --results-root reads)"""
    for r in hand_rows():
        _w(os.path.join(root, r["batch"], r["arm"], "%s-t%d" % (r["task_id"], r["trial"]), "grade.json"),
           json.dumps({"recall": {"missed_pm3": []}, "contaminated": None}))
    return root


class AggregateTest(unittest.TestCase):
    def test_shares_and_corrected_recall(self):
        doc = jd.run(hand_key(), labels(), hand_rows(), 20261021, 400, GRADES)
        a1, a0 = doc["per_arm"]["a1_full"], doc["per_arm"]["a0_bare_matched"]
        self.assertEqual((a1["pairs_judged"], a1["items"]), (4, 7))
        self.assertAlmostEqual(a1["share_strict"], 0.5)
        self.assertAlmostEqual(a1["share_lenient"], 0.75)
        self.assertAlmostEqual(a1["recall_grader"], 0.5)
        self.assertAlmostEqual(a1["recall_corrected_strict"], 0.25)
        self.assertAlmostEqual(a1["recall_corrected_lenient"], 0.375)
        self.assertAlmostEqual(a0["share_strict"], 0.0)
        self.assertAlmostEqual(a0["share_lenient"], 0.5)
        self.assertAlmostEqual(a0["recall_corrected_lenient"], 0.125)
        for k in ("share_strict_ci95", "share_lenient_ci95", "recall_corrected_strict_ci95"):
            lo, hi = a1[k]
            self.assertLessEqual(lo, a1[k[:-5]])
            self.assertGreaterEqual(hi, a1[k[:-5]])
        d = doc["difference"]
        self.assertAlmostEqual(d["share_strict"], 0.5)
        self.assertAlmostEqual(d["recall_corrected_strict"], 0.25)
        self.assertEqual(len(d["share_strict_ci95"]), 2)
        self.assertEqual(doc["per_pr"]["a1_full"]["p2"], {"pairs": 2, "items": 4, "judged_pairs": 2, "strict": 1,
                                                          "lenient": 1})

    def test_incomplete_pair_left_out(self):
        doc = jd.run(hand_key(), labels({"D0005": None}), hand_rows(), 1, 50, GRADES)
        self.assertEqual(doc["incomplete_pairs"], ["P003"])
        self.assertEqual(doc["per_arm"]["a1_full"]["pairs_judged"], 3)
        self.assertAlmostEqual(doc["per_arm"]["a1_full"]["share_strict"], 2.0 / 3)

    def test_cli_outputs_deterministic_and_labelled(self):
        tmp = tempfile.mkdtemp()
        try:
            kp, rp = os.path.join(tmp, "key.json"), os.path.join(tmp, "rows.jsonl")
            _w(kp, json.dumps(hand_key()))
            _w(rp, "".join(json.dumps(r) + "\n" for r in hand_rows()))
            lab = labels()
            sid = lab.pop("sample_id")
            res = hand_results(os.path.join(tmp, "results"))
            ks = sorted(lab)
            _w(os.path.join(tmp, "sessions/c01/labels.json"), json.dumps(dict({k: lab[k] for k in ks[:5]}, sample_id=sid)))
            _w(os.path.join(tmp, "sessions/c02/labels.json"), json.dumps(dict({k: lab[k] for k in ks[5:]}, sample_id=sid)))
            _w(os.path.join(tmp, "sessions/c02.failed-120000/labels.json"), json.dumps({"D0001": lab["D0001"]}))
            outs = []
            for n in ("r1", "r2"):
                o = os.path.join(tmp, n)
                self.assertEqual(run_cli(["aggregate", "--key", kp, "--labels", os.path.join(tmp, "sessions"),
                                          "--rows", rp, "--results-root", res, "--out", o, "--boot", "200"])[0], 0)
                outs.append(tree(o))
            self.assertEqual(outs[0], outs[1])
            md = outs[0]["result.md"].decode()
            self.assertIn("EXPLORATORY / post hoc", md)
            self.assertIn("a1_full − a0_bare_matched", md)
            self.assertNotIn(tmp, md + outs[0]["result.json"].decode())
            merged = os.path.join(tmp, "merged.json")
            _w(merged, json.dumps(dict(lab, sample_id=sid)))
            o3 = os.path.join(tmp, "r3")
            self.assertEqual(run_cli(["aggregate", "--key", kp, "--labels", merged, "--rows", rp, "--results-root", res,
                                      "--out", o3, "--boot", "200"])[0], 0)
            self.assertEqual(tree(o3), outs[0])
            # an item labelled in two sessions, an unknown item, a stray verdict: refused
            _w(os.path.join(tmp, "sessions/c03/labels.json"), json.dumps({"D0001": lab["D0001"], "sample_id": sid}))
            self.assertEqual(run_cli(["aggregate", "--key", kp, "--labels", os.path.join(tmp, "sessions"),
                                      "--rows", rp, "--results-root", res, "--out", os.path.join(tmp, "r4")])[0], 1)
            os.remove(os.path.join(tmp, "sessions/c03/labels.json"))
            # a session without the sample id, a key edited after sampling: refused
            _w(os.path.join(tmp, "sessions/c01/labels.json"), json.dumps({k: lab[k] for k in ks[:5]}))
            rc, err = run_cli(["aggregate", "--key", kp, "--labels", os.path.join(tmp, "sessions"), "--rows", rp,
                               "--results-root", res, "--out", os.path.join(tmp, "r6")])
            self.assertEqual(rc, 1)
            self.assertIn("c01", err)
            edited = dict(hand_key(), seed=7)
            _w(os.path.join(tmp, "edited.json"), json.dumps(edited))
            _w(merged, json.dumps(dict(lab, sample_id=sid)))
            rc, err = run_cli(["aggregate", "--key", os.path.join(tmp, "edited.json"), "--labels", merged, "--rows", rp,
                               "--results-root", res, "--out", os.path.join(tmp, "r7")])
            self.assertEqual(rc, 1)
            self.assertIn("does not match its content", err)
            for bad in ({"J0001": {"verdict": "describes"}, "sample_id": sid}, {"D0001": {"verdict": "real"}, "sample_id": sid}):
                _w(merged, json.dumps(bad))
                rc, err = run_cli(["aggregate", "--key", kp, "--labels", merged, "--rows", rp, "--results-root", res,
                                   "--out", os.path.join(tmp, "r5")])
                self.assertEqual(rc, 1, err)
                self.assertFalse(os.path.exists(os.path.join(tmp, "r5")))
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
