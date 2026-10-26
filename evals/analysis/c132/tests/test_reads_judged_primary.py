"""reads.py --final under the judged primary rule (loa-smol instrument repair; grader 1.5.0 --judge-verdicts; judge-pairs.sh):
when every valid cell of both primary arms carries grade.json recall_judged the primary Δ is read on the blind
`describes` credits and the pm3 Δ is the first sensitivity; otherwise the read is unchanged."""
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


def judged(does_not=(), skip=()):
    """a synth mutate hook: grader-1.5.0 judge fields on every cell — one credited pair per caught defect, blind
    `describes` unless (arm, defect) is in does_not; cells of (arm, task) in skip stay without the fields"""
    def mutate(row, grade):
        if (row["arm"], row["task_id"]) in skip:
            return
        caught = [d for d in ["d%d" % i for i in range(1, row["defects_seeded"] + 1)] if d not in row["defects_missed_pm3"]]
        pairs = [{"finding_id": "F-%s" % hashlib.sha256(d.encode()).hexdigest()[:6], "finding_sha256": "0" * 64, "defect_key": d,
                  "verdict": "does_not_describe" if (row["arm"], d) in does_not else "describes", "blind": True} for d in caught]
        yes = {p["defect_key"] for p in pairs if p["verdict"] == "describes"}
        grade.update(grader_version="1.5.0", credited_pairs=pairs, judged_pairs=len(pairs), judged_pairs_unblind=0, unjudged_pairs=0,
                     recall_judged=round(len(yes) / row["defects_seeded"], 4),
                     judge={"judge_models": ["majority:a+b"], "judge_prompt_sha256": ["ab" * 32], "verdicts_sha256": "cd" * 32})
    return mutate


class JudgedPrimaryRule(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-judged-primary-")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def batch(self, name, mutate):
        root = os.path.join(self.tmp, name)
        s = synth.build(root, mutate=mutate)
        inp = os.path.join(root, "in")
        rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--make-inputs", "--out", inp,
                       "--pin", "a" * 40, "--label-set", "v2"])
        self.assertEqual(rc, 0, err)
        s["inputs"] = os.path.join(inp, "INPUTS.json")
        return s

    def final(self, s, out):
        o = os.path.join(self.tmp, out)
        rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--inputs", s["inputs"],
                       "--registration", s["registration"], "--final", "--out", o])
        self.assertEqual(rc, 0, err)
        return json.loads(slurp(os.path.join(o, "reads.json"))), slurp(os.path.join(o, "reads.md")), o

    def test_every_cell_judged_switches_the_primary_and_prints_pm3_first(self):
        pm3 = self.batch("pm3", None)
        jd = self.batch("judged", judged(does_not={("a1_full", "d1")}))
        doc_pm3, _md_pm3, _ = self.final(pm3, "o-pm3")
        doc, md, o = self.final(jd, "o-judged")
        self.assertEqual(doc["primary"]["rule"], "judged")
        self.assertNotIn("rule", doc_pm3["primary"])
        order = doc["sensitivities"]["order"]
        self.assertEqual(order[0], reads.PM3_SENSITIVITY)
        self.assertEqual(order[1:], reads.DEFAULT_SENSITIVITIES)
        pm3_read = doc["sensitivities"]["reads"][reads.PM3_SENSITIVITY]
        self.assertEqual(pm3_read["rule"], "pm3")
        # the pm3 sensitivity is the read the unjudged batch calls primary (same rows, same pairs, same seed)
        for k in ("delta", "se", "ci95", "n_prs", "n_pairs", "n_defects"):
            self.assertEqual(pm3_read[k], doc_pm3["primary"][k], k)
        # a1_full loses every d1 credit under the judged rule while the matched arm keeps its credits: Δ falls
        self.assertLess(doc["primary"]["delta"], pm3_read["delta"])
        self.assertEqual(doc["primary"]["n_defects"], pm3_read["n_defects"])
        self.assertIn("rule judged", md)
        self.assertIn("| pm3_grader_credit |", md)
        # the pm3 line comes first under the sensitivities heading
        sens = md[md.index("## Sensitivities"):]
        self.assertLess(sens.index("| pm3_grader_credit |"), sens.index("| exact_dollar_trim |"))
        # deterministic
        doc2, md2, o2 = self.final(jd, "o-judged-2")
        self.assertEqual(slurp(os.path.join(o, "reads.json"), "rb"), slurp(os.path.join(o2, "reads.json"), "rb"))
        self.assertEqual(md, md2)

    def test_a_valid_primary_cell_without_recall_judged_keeps_the_pm3_rule_unchanged(self):
        pm3 = self.batch("pm3", None)
        part = self.batch("partial", judged(does_not={("a1_full", "d1")}, skip={("a1_full", "review-s02")}))
        doc_pm3, md_pm3, _ = self.final(pm3, "o-pm3")
        doc, md, _ = self.final(part, "o-partial")
        self.assertNotIn("rule", doc["primary"])
        self.assertEqual(doc["sensitivities"]["order"], reads.DEFAULT_SENSITIVITIES)
        self.assertNotIn(reads.PM3_SENSITIVITY, doc["sensitivities"]["reads"])
        self.assertEqual(doc["primary"], doc_pm3["primary"])
        self.assertEqual(doc["sensitivities"], doc_pm3["sensitivities"])
        self.assertNotIn("rule judged", md)
        # the only differences from the unjudged batch are the grade hashes in the inputs block
        self.assertEqual(md.split("\n", 3)[3], md_pm3.split("\n", 3)[3])

    def test_only_the_matched_arm_judged_is_not_enough(self):
        tasks = ["review-s%02d" % i for i in range(1, 9)]
        half = self.batch("half", judged(skip={("a1_full", t) for t in tasks}))
        doc, _md, _ = self.final(half, "o-half")
        self.assertNotIn("rule", doc["primary"])
        self.assertEqual(doc["sensitivities"]["order"], reads.DEFAULT_SENSITIVITIES)

    def test_look_mode_is_unchanged(self):
        pm3 = self.batch("pm3", None)
        jd = self.batch("judged", judged(does_not={("a1_full", "d1")}))
        looks = []
        for s, out in ((pm3, "l-pm3"), (jd, "l-judged")):
            o = os.path.join(self.tmp, out)
            rc, err = run(["--rows", s["rows"], "--results-root", s["results"], "--inputs", s["inputs"],
                           "--registration", s["registration"], "--look", "1", "--out", o])
            self.assertEqual(rc, 0, err)
            looks.append(json.loads(slurp(os.path.join(o, "reads.json")))["looks"])
        self.assertEqual(looks[0], looks[1])


if __name__ == "__main__":
    unittest.main()
