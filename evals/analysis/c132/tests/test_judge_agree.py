"""judge_agree.py: agreement, kappa, Horvitz–Thompson corrections on a hand-built key."""
import contextlib
import io
import json
import os
import shutil
import tempfile
import unittest

import _path  # noqa: F401
from c132 import judge_agree, stats


def unit(uid, cell, cls, region, defect, credit, sampled):
    arm, task, trial = cell.split("/")[1], cell.split("/")[2], int(cell.split("/")[3])
    return {"unit": uid, "cell": cell, "arm": arm, "task": task, "trial": trial, "class": cls,
            "region": region, "defect": defect, "grader_credit": credit, "sampled": sampled}


C1 = "b/a1_full/t1/1"
C2 = "b/a1_full/t2/1"


def key():
    # cell C1: 4 defects; credited d1 (two regions), d2 (one region); near-miss on d3; d4 far-miss;
    # two strays. cell C2: 2 defects, credited d1, d2 far-miss.
    u = [
        unit("U1", C1, "credited", ["f.sh", 10, 10], "d1", True, True),
        unit("U2", C1, "credited", ["f.sh", 12, 12], "d1", True, False),
        unit("U3", C1, "credited", ["f.sh", 40, 40], "d2", True, True),
        unit("U4", C1, "near-miss", ["f.sh", 70, 70], "d3", False, True),
        unit("U5", C1, "far-miss", None, "d4", False, True),
        unit("U6", C1, "stray", ["g.sh", 5, 5], None, False, True),
        unit("U7", C1, "stray", ["g.sh", 90, 90], None, False, False),
        unit("U8", C2, "credited", ["f.sh", 3, 3], "d1", True, True),
        unit("U9", C2, "far-miss", None, "d2", False, True),
    ]
    strata = {}
    for x in u:
        s = "%s|%s|%s" % (x["arm"], x["task"], x["class"])
        st = strata.setdefault(s, {"N": 0, "n": 0})
        st["N"] += 1
        st["n"] += x["sampled"]
    for st in strata.values():
        st["pi"] = st["n"] / float(st["N"])
    items = {}
    j = 0
    for x in u:
        if x["sampled"]:
            j += 1
            items["J%04d" % j] = {k: x[k] for k in ("unit", "cell", "arm", "task", "trial", "class", "region", "defect", "grader_credit")}
    cells = {C1: {"arm": "a1_full", "task": "t1", "trial": 1, "defects": 4, "credited": ["d1", "d2"], "regions": 6},
             C2: {"arm": "a1_full", "task": "t2", "trial": 1, "defects": 2, "credited": ["d1"], "regions": 1}}
    return {"seed": 5, "strata": strata, "items": items, "cells": cells, "universe": u}


# J0001 U1 credited d1 → does-not-describe; J0002 U3 credited d2 → describes; J0003 U4 near-miss d3 →
# describes; J0004 U5 far-miss d4 → partially; J0005 U6 stray → real; J0006 U8 credited → partially;
# J0007 U9 far-miss → does-not-describe
LABELS = {"J0001": "does-not-describe", "J0002": "describes", "J0003": "describes", "J0004": "partially",
          "J0005": "real", "J0006": "partially", "J0007": "does-not-describe"}

ROWS = [{"batch": "b", "arm": "a1_full", "task_id": t, "trial": 1, "status": "completed", "contaminated": None,
         "oracle_exposed_defects": [], "defects_seeded": n, "defects_missed_pm3": [], "phases": []}
        for t, n in (("t1", 4), ("t2", 2))]


class JudgeAgreeTest(unittest.TestCase):
    def doc(self):
        labels = {k: {"verdict": v, "note": ""} for k, v in LABELS.items()}
        return judge_agree.run(key(), labels, ROWS, 5, 200)

    def test_agreement_and_kappa(self):
        d = self.doc()
        # pair items: U1 (g1, dnd: disagree), U3 (g1, desc: agree), U4 (g0, desc: disagree),
        # U5 (g0, partially: strict disagree / lenient agree), U8 (g1, partially: strict dis / lenient agree),
        # U9 (g0, dnd: agree) → strict 2/6, lenient 4/6
        self.assertAlmostEqual(d["pooled_agreement"]["strict"]["unweighted"], 2 / 6.0)
        self.assertAlmostEqual(d["pooled_agreement"]["lenient"]["unweighted"], 4 / 6.0)
        # strict kappa table (judge yes = describes): g1: yes U3; no U1, U8 → [1, 2]; g0: yes U4; no U5, U9 → [1, 2]
        self.assertEqual(d["kappa"]["strict"]["table"], {"grader_credit": {"judge_yes": 1, "judge_no": 2},
                                                          "grader_no_credit": {"judge_yes": 1, "judge_no": 2}})
        self.assertAlmostEqual(d["kappa"]["strict"]["kappa"], stats.kappa([[1, 2], [1, 2]]))

    def test_horvitz_thompson_recall(self):
        d = self.doc()
        c = d["corrected"]["a1_full"]
        # strata weights N/n': credited t1 (N 3, judged 2 → 1.5); near-miss t1 1; far-miss t1 1; stray t1 (N 2, n 1 → 2);
        # credited t2 1; far-miss t2 1.
        # C1 caught: 2 + 1.5·(−1/2) [U1 rejects one of d1's two credits] + 1·(+1) [U4 accepts d3] = 2.25
        # (U5 partially is not an accept under strict); C2: 1 + 1·(−1) [U8 partially rejects under strict] = 0
        self.assertAlmostEqual(c["recall"], (2.25 + 0.0) / 6.0)
        self.assertAlmostEqual(c["recall_grader"], 3 / 6.0)
        # lenient: C1 2 − 0.75 + 1 + 1 (U5 partially accepts d4) = 3.25; C2 1 + 0 = 1 → 4.25/6
        self.assertAlmostEqual(d["corrected_lenient"]["a1_full"]["recall"], 4.25 / 6.0)

    def test_horvitz_thompson_precision(self):
        d = self.doc()
        c = d["corrected"]["a1_full"]
        # regions C1: f10, f12, f40 credited (3 positive), f70 near-miss, g5, g90 strays → 6 regions; C2: f3 → 1
        # grader precision (3 + 1)/7; corrected C1: 3 − 1.5·1 (U1 region rejected) + 1 (U4 accepted) + 2·1 (U6 real)
        # = 4.5; C2: 1 − 1 = 0 → 4.5/7
        self.assertAlmostEqual(c["precision_grader"], 4 / 7.0)
        self.assertAlmostEqual(c["precision"], 4.5 / 7.0)

    def test_real_strays(self):
        d = self.doc()
        self.assertEqual(d["real_strays"], [{"pr": "t1", "region": ["g.sh", 5, 5], "cells": [C1]}])

    def test_unjudged_item_leaves_the_effective_sample(self):
        labels = {k: {"verdict": v} for k, v in LABELS.items() if k != "J0002"}
        d = judge_agree.run(key(), labels, ROWS, 5, 50)
        self.assertEqual(d["unjudged"], ["J0002"])
        # credited t1 now N 3 / judged 1 → weight 3: C1 = 2 + 3·(−1/2) + 1 = 1.5
        self.assertAlmostEqual(d["corrected"]["a1_full"]["recall"], (1.5 + 0.0) / 6.0)

    def test_cli_and_invalid_verdict(self):
        tmp = tempfile.mkdtemp()
        try:
            kp, lp, rp = (os.path.join(tmp, n) for n in ("key.json", "labels.json", "rows.jsonl"))
            with open(kp, "w") as f:
                json.dump(key(), f)
            with open(rp, "w") as f:
                f.write("".join(json.dumps(r) + "\n" for r in ROWS))
            with open(lp, "w") as f:
                json.dump({k: {"verdict": v} for k, v in LABELS.items()}, f)
            outs = []
            for i in (1, 2):
                o = os.path.join(tmp, "o%d" % i)
                self.assertEqual(judge_agree.main(["--key", kp, "--labels", lp, "--rows", rp, "--out", o, "--boot", "100"]), 0)
                with open(os.path.join(o, "result.json"), "rb") as f:
                    outs.append(f.read())
            self.assertEqual(outs[0], outs[1])
            with open(lp, "w") as f:
                json.dump({"J0001": {"verdict": "real"}}, f)          # a stray verdict on a pair item
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                rc = judge_agree.main(["--key", kp, "--labels", lp, "--rows", rp, "--out", os.path.join(tmp, "bad")])
            self.assertEqual(rc, 1)
            self.assertFalse(os.path.exists(os.path.join(tmp, "bad")))
        finally:
            shutil.rmtree(tmp)

    def test_title_takes_the_grader_version_from_the_rows(self):
        d = self.doc()
        rows = [dict(r, grader_version="1.3.8") for r in ROWS]
        self.assertTrue(judge_agree.render_md(d, rows).startswith("# Grader 1.3.8 vs the blind judge\n\n"))
        rows[1]["grader_version"] = "1.3.10"
        self.assertTrue(judge_agree.render_md(d, rows).startswith("# Grader 1.3.10, 1.3.8 vs the blind judge\n\n"))
        self.assertTrue(judge_agree.render_md(d, ROWS).startswith("# Grader vs the blind judge\n\n"))
        # everything after the title is unchanged
        self.assertEqual(judge_agree.render_md(d, rows).split("\n", 1)[1], judge_agree.render_md(d).split("\n", 1)[1])


if __name__ == "__main__":
    unittest.main()
