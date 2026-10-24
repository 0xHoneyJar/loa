"""reads.py --judge-defects (cycle-133 Sprint 274 Task 3.2; sdd.md C-11, C-12): the judged defect read of grader 1.5.0's
--judge-verdicts grades, registered under the registration schema v2 chain."""
import contextlib
import hashlib
import io
import json
import os
import shutil
import tempfile
import unittest

import _path  # noqa: F401
import synth
from c132 import reads


def slurp(path, mode="r"):
    with open(path, mode) as f:
        return f.read()


def run(argv):
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        rc = reads.main(argv)
    return rc, err.getvalue()


def judged(blind_false=(), does_not=(), unjudged_task=None):
    """a synth mutate hook: a grader-1.5.0 grade whose every caught defect is one credited pair with a verdict"""
    def mutate(row, grade):
        caught = [d for d in ["d%d" % i for i in range(1, row["defects_seeded"] + 1)] if d not in row["defects_missed_pm3"]]
        pairs = []
        for d in caught:
            v = "does_not_describe" if (row["arm"], d) in does_not else "describes"
            pairs.append({"finding_id": "F-%s" % hashlib.sha256(d.encode()).hexdigest()[:6], "finding_sha256": "0" * 64,
                          "defect_key": d, "verdict": v, "blind": (row["arm"], d) not in blind_false})
        unj = 0
        if unjudged_task and row["task_id"] == unjudged_task and pairs:
            pairs[0].update(verdict=None, blind=None)
            unj = 1
        grade.update(grader_version="1.5.0", credited_pairs=pairs, unjudged_pairs=unj,
                     judged_pairs=sum(1 for p in pairs if p["blind"] is True),
                     judged_pairs_unblind=sum(1 for p in pairs if p["blind"] is False),
                     judge={"judge_models": ["judge-x"], "judge_prompt_sha256": ["ab" * 32], "verdicts_sha256": "cd" * 32})
    return mutate


class JudgeDefectsRead(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-judge-read-")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def batch(self, mutate, v2=True):
        root = os.path.join(self.tmp, "b")
        s = synth.build(root, mutate=mutate)
        if v2:   # the v2 addendum: supersedes the v1 registration the rows were written under
            v1 = json.loads(slurp(s["registration"]))
            doc = dict(v1, schema_version=2, supersedes=s["reg_sha"], looks_seen=[])
            s["registration"] = os.path.join(root, "REGISTRATION-2.json")
            with open(s["registration"], "w") as f:
                f.write(json.dumps(doc, sort_keys=True, separators=(",", ":")))
        inp = os.path.join(root, "in")
        rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--make-inputs", "--out", inp,
                       "--pin", "a" * 40, "--label-set", "v2"])
        self.assertEqual(rc, 0, err)
        s["inputs"] = os.path.join(inp, "INPUTS.json")
        return s

    def read(self, s, out="o", extra=()):
        o = os.path.join(self.tmp, out)
        rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--inputs", s["inputs"],
                       "--registration", s["registration"], "--judge-defects", "--out", o] + list(extra))
        return rc, err, o

    def test_judged_read_counts_blind_describes_and_is_byte_identical(self):
        s = self.batch(judged(does_not={("a1_full", "d1")}, blind_false={("a1_full", "d2")}))
        rc, err, o = self.read(s)
        self.assertEqual(rc, 0, err)
        doc = json.loads(slurp(os.path.join(o, "reads.json")))
        self.assertEqual(doc["mode"], "judge_defects")
        j = doc["judge_defects"]
        self.assertEqual(j["primary"]["status"], "ok")
        self.assertEqual(j["pairs_unjudged"], [])
        a, b = j["per_arm"]["a1_full"], j["per_arm"]["a0_bare_matched"]
        # a1_full: d1 judged does_not_describe and d2 judged unblind wherever caught → never counted; a0: every caught one
        self.assertLess(a["caught_judged"], a["caught_grader"])
        self.assertEqual(b["caught_judged"], b["caught_grader"])
        self.assertGreater(a["judged_pairs_unblind"], 0)
        self.assertEqual(j["judge_models"], ["judge-x"])
        self.assertIn("Judged defect read", slurp(os.path.join(o, "reads.md")))
        _rc, _e, o2 = self.read(s, out="o2")
        for n in ("reads.json", "reads.md"):
            self.assertEqual(slurp(os.path.join(o, n), "rb"), slurp(os.path.join(o2, n), "rb"))

    def test_a_pair_with_an_unjudged_cell_is_listed_never_read(self):
        s = self.batch(judged(unjudged_task="review-s03"))
        rc, err, o = self.read(s)
        self.assertEqual(rc, 0, err)
        j = json.loads(slurp(os.path.join(o, "reads.json")))["judge_defects"]
        self.assertTrue(j["pairs_unjudged"])
        self.assertTrue(all(x["pr"] == "review-s03" for x in j["pairs_unjudged"]))
        self.assertTrue(all("unjudged_pairs" in (x["a"], x["b"]) for x in j["pairs_unjudged"]))

    def test_a_v1_registration_refuses_the_read(self):
        s = self.batch(judged(), v2=False)
        rc, err, o = self.read(s)
        self.assertEqual(rc, 1)
        self.assertIn("registration schema v2", err)
        self.assertFalse(os.path.exists(os.path.join(o, "reads.json")))

    def test_grades_without_judge_fields_are_not_judged(self):
        s = self.batch(None)
        rc, err, o = self.read(s)
        self.assertEqual(rc, 0, err)
        j = json.loads(slurp(os.path.join(o, "reads.json")))["judge_defects"]
        self.assertEqual(j["pairs_used"], 0)
        self.assertEqual(j["primary"]["status"], "no_valid_pairs")
        self.assertTrue(all(x["a"] == "not_judged_grade" for x in j["pairs_unjudged"]))

    def test_the_registration_is_required(self):
        s = self.batch(judged())
        rc, _err = run(["--rows", s["rows"], "--results-root", s["results"], "--inputs", s["inputs"], "--judge-defects",
                        "--out", os.path.join(self.tmp, "x")])
        self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
