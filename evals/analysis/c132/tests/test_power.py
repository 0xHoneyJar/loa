"""power.py: the model pieces, the procedure evaluation, calibration and a seeded tiny run on
the frozen mini fixture (sdd.md §5.3; prd.md FR-6 AC 1, 3)."""
import contextlib
import io
import json
import os
import random
import shutil
import tempfile
import unittest

import _path
import synth
from c132 import power

# the frozen mini inputs (rows, suite, candidates) are committed; the head.diff fixtures are generated per run by
# synth.power_mini_diffs (bd-qxwrm; seed recorded, byte-identity with the removed blobs pinned in
# test_synth_power_mini.py) into a temporary copy of the mini tree
_MINI_SRC = os.path.join(_path.FIXTURES, "power-mini")
MINI = None


def setUpModule():
    global MINI
    MINI = os.path.join(tempfile.mkdtemp(prefix="c132-power-mini-"), "power-mini")
    shutil.copytree(_MINI_SRC, MINI)
    synth.power_mini_diffs(os.path.join(MINI, "fixtures"), seed=synth.POWER_MINI_SEED)


def tearDownModule():
    shutil.rmtree(os.path.dirname(MINI), ignore_errors=True)


def mini_args(out, *extra, seed="20261021"):
    return ["--rows", os.path.join(MINI, "rows.jsonl"), "--fixtures-dir", os.path.join(MINI, "fixtures"),
            "--suite-root", os.path.join(MINI, "suite"), "--candidates", os.path.join(MINI, "candidates.tsv"),
            "--seed", seed, "--out", out] + list(extra)


def run(argv):
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        rc = power.main(argv)
    return rc, err.getvalue()


def slurp(p):
    with open(p, "rb") as f:
        return f.read()


class PiecesTest(unittest.TestCase):
    def test_diff_lines(self):
        self.assertEqual(power.diff_lines(os.path.join(MINI, "fixtures", "pr-91", "head.diff")), 60)

    def test_ols_and_k(self):
        a, b = power.ols([0, 10, 20], [1, 3, 5])
        self.assertAlmostEqual(a, 1.0)
        self.assertAlmostEqual(b, 0.2)
        self.assertEqual(power.ols([5, 5], [1, 3]), (0.0, 0.4))
        # k = round(ĉ_full/ĉ_bare), floor 2, cap 30, non-positive bare → cap
        self.assertEqual(power.k_for(100, (10, 0), (1, 0)), 10)
        self.assertEqual(power.k_for(100, (100, 0), (1, 0)), 30)
        self.assertEqual(power.k_for(100, (1, 0), (1, 0)), 2)
        self.assertEqual(power.k_for(100, (10, 0), (-5, 0)), 30)
        self.assertEqual(power.k_for(100, (10, 0), (1, 0), shift=3), 13)
        self.assertEqual(power.k_for(100, (10.5, 0), (1, 0)), 11)    # half rounds up

    def test_beta_mom_recovers_parameters(self):
        rng = random.Random(3)
        counts = []
        for _ in range(4000):
            p = rng.betavariate(2.0, 3.0)
            counts.append((sum(rng.random() < p for _ in range(6)), 6))
        f = power.beta_mom(counts)
        self.assertAlmostEqual(f["mean"], 0.4, delta=0.02)
        self.assertAlmostEqual(f["rho"], 1 / 6.0, delta=0.03)       # 1/(α+β+1)

    def test_blind_spot_weight(self):
        rng = random.Random(4)
        counts = []
        for i in range(2000):
            if i % 5 == 0:
                counts.append((0, 3))                                 # 20 % blind spots
            else:
                p = rng.betavariate(6.0, 2.0)
                counts.append((sum(rng.random() < p for _ in range(3)), 3))
        f = power.fit_arm(counts)
        self.assertAlmostEqual(f["pi0"], 0.20, delta=0.03)          # the fixed point recovers the truth
        self.assertLess(f["pi0_literal"], 0.08)                      # the literal form absorbs blind spots
        self.assertLessEqual(f["pi0"], f["share_never"])
        clean = power.fit_arm([(2, 3), (1, 3), (3, 3), (2, 3)])
        self.assertEqual(clean["pi0"], 0.0)

    def test_bb_zero(self):
        # Beta(1,1) → P(0 of n) = 1/(n+1)
        self.assertAlmostEqual(power.bb_zero(3, 1.0, 1.0), 0.25, places=12)

    def test_groups_and_cap(self):
        self.assertEqual(power.groups_for(6), [6])
        self.assertEqual(power.groups_for(8), [6, 2])
        self.assertEqual(power.groups_for(10), [6, 4])
        self.assertEqual(power.groups_for(12), [6, 3, 3])
        # (N·180 + 6·40 + 6N + 170) × 1.25 rounded up to 50
        self.assertEqual(power.cap_usd(6)[0], 1950)
        self.assertEqual(power.cap_usd(8)[0], 2400)
        self.assertEqual(power.cap_usd(10)[0], 2850)
        self.assertEqual(power.cap_usd(12)[0], 3350)

    def test_candidate_order(self):
        cands = power.read_candidates(os.path.join(MINI, "candidates.tsv"))
        ordered = power.order_candidates(cands, 20261021)
        names = [c["fixture"] for c in ordered]
        self.assertEqual(names[-1], "pr-11")
        self.assertTrue(ordered[-1]["flagged"])
        self.assertNotIn("pr-21", names)     # one label: ineligible
        self.assertNotIn("pr-23", names)     # no exposure: ineligible
        post = [c["fixture"] for c in ordered if c["exposure"] == "post-cutoff"]
        self.assertEqual(names[:len(post)], post)
        self.assertEqual(names, [c["fixture"] for c in power.order_candidates(power.read_candidates(os.path.join(MINI, "candidates.tsv")), 20261021)])


class ClippingTest(unittest.TestCase):
    def model(self, p_full_counts, p_bare_counts, k=10):
        prof = [{"task": "t%d" % i, "defects": [(b, 3, f, 3) for b, f in zip(p_bare_counts, p_full_counts)]} for i in range(3)]
        fits = {"bare": power.fit_arm([(b, 3) for b in p_bare_counts * 3]),
                "full": power.fit_arm([(f, 3) for f in p_full_counts * 3])}
        return power.Model(prof, fits, {"t0": k, "t1": k, "t2": k})

    def test_saturated_design_is_flagged(self):
        m = self.model([3, 3, 3, 3, 3, 2], [2, 2, 3, 2, 3, 1], k=20)
        sol = m.solve_delta(0.0, "x")
        self.assertGreater(sol["clipped_share"], 0.10)

    def test_mid_range_design_is_not(self):
        m = self.model([2, 1, 2, 1, 2, 1], [1, 0, 1, 1, 0, 1], k=2)
        sol = m.solve_delta(0.10, "x")
        self.assertEqual(sol["status"], "ok")
        self.assertLess(sol["clipped_share"], 0.10)
        self.assertAlmostEqual(sol["expected_recall_full"] - sol["expected_recall_matched"], 0.10, delta=1e-6)


class ProcedureTest(unittest.TestCase):
    def looks(self, delta, se, nprs=6, ndef=40):
        return ([(delta, se, nprs, ndef)], True)

    def test_evaluate_partition_single_look(self):
        res = [self.looks(0.3, 0.05), self.looks(0.0, 0.05), self.looks(0.05, 0.01), self.looks(0.1, 0.2),
               self.looks(0.3, 0.05, nprs=5)]
        ev = power.evaluate(res, 0.05, 1.0, 0.10, 1, "percentile")
        # YES, NO (z_no = 2 ≥ 1.96), SMALL (both cross), inconclusive, inconclusive (minimum information)
        self.assertAlmostEqual(ev["yes"], 0.2)
        self.assertAlmostEqual(ev["no"], 0.2)
        self.assertAlmostEqual(ev["small"], 0.2)
        self.assertAlmostEqual(ev["inconclusive"], 0.4)
        self.assertAlmostEqual(ev["negative"], 0.0)

    def test_negative_outcome_is_tallied(self):
        # round 3: a significantly negative Δ̂ (z_yes −4) is NEGATIVE, no longer NO
        res = [self.looks(-0.2, 0.05), self.looks(-0.2, 0.05), self.looks(0.3, 0.05), self.looks(-0.03, 0.05)]
        for iv_ in ("percentile", "t"):
            ev = power.evaluate(res, 0.05, 1.0, 0.10, 1, iv_)
            self.assertAlmostEqual(ev["negative"], 0.5)
            self.assertAlmostEqual(ev["yes"], 0.25)
            self.assertAlmostEqual(sum(v for k, v in ev.items() if k != "void"), 1.0)

    def test_calibration_inflates_until_type1(self):
        rng = random.Random(9)
        # null studies with an anti-conservative SE: z ~ N(0, 1.3²)
        res = [self.looks(rng.gauss(0, 1.3) * 0.05, 0.05) for _ in range(2000)]
        for iv_ in ("percentile", "t"):
            c = power.calibrate(res, 0.05, 0.10, 1, iv_)
            self.assertLessEqual(power.evaluate(res, 0.05, c, 0.10, 1, iv_)["yes"], 0.05)
            if c > 1.0:
                self.assertGreater(power.evaluate(res, 0.05, round(c - 0.01, 2), 0.10, 1, iv_)["yes"], 0.05)
        self.assertGreater(power.calibrate(res, 0.05, 0.10, 1, "percentile"), 1.0)
        # the t scale (df 5) is wider: it needs no more inflation than the normal scale
        self.assertLessEqual(power.calibrate(res, 0.05, 0.10, 1, "t"), power.calibrate(res, 0.05, 0.10, 1, "percentile"))

    def test_t_scale_is_stricter(self):
        # z = 2.3 crosses 1.96 (normal) but not t_{5}(1.96) = 2.57 at a single look with 6 PRs
        res = [self.looks(0.115, 0.05)]
        self.assertEqual(power.evaluate(res, 0.05, 1.0, 0.10, 1, "percentile")["yes"], 1.0)
        self.assertEqual(power.evaluate(res, 0.05, 1.0, 0.10, 1, "t")["yes"], 0.0)


class TinyRunTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="c132-power-")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_seeded_reproducible_and_frozen_chosen_n(self):
        outs = []
        for i in (1, 2):
            o = os.path.join(self.tmp, "o%d" % i)
            rc, err = run(mini_args(o, "--grid", "6", "--studies", "50", "--se-method", "linear", "--no-sensitivities"))
            self.assertEqual(rc, 0, err)
            outs.append((slurp(os.path.join(o, "power.json")), slurp(os.path.join(o, "power.md"))))
        self.assertEqual(outs[0], outs[1])
        doc = json.loads(outs[0][0])
        self.assertEqual(doc["reference_n"], 6)
        row = doc["per_n"][0]
        for k in ("power_no_at_null", "small_at_null", "negative_at_null", "negative_at_mde", "expected_recall_matched_null", "expected_recall_matched_mde",
                  "clipped_share_null", "clipped_share_mde", "meets_both"):
            self.assertIn(k, row)
        # round 1: N is chosen only when both powers reach 0.80; otherwise nothing is picked
        if row["meets_both"]:
            self.assertEqual(doc["chosen_n"], 6)
            self.assertFalse(doc["decision_required"])
        else:
            self.assertIsNone(doc["chosen_n"])
            self.assertTrue(doc["decision_required"])
            self.assertIn("DECISION REQUIRED", outs[0][1].decode())
        self.assertIn("pi0_literal", doc["arm_fits"]["bare"])
        self.assertEqual(doc["validity"], "c132")
        self.assertIn("negative", row["null"])
        self.assertIn("| NEGATIVE |", outs[0][1].decode())
        self.assertEqual(doc["evaluated"], [6])
        self.assertEqual(len(doc["per_n"]), 1)
        self.assertIn("planned_final_se", doc)
        self.assertEqual(doc["candidates"][0]["order"], 1)
        self.assertEqual(len(doc["selected"]), 6)
        self.assertNotIn(self.tmp, outs[0][0].decode() + outs[0][1].decode())
        o3 = os.path.join(self.tmp, "o3")
        rc, _ = run(mini_args(o3, "--grid", "6", "--studies", "50", "--se-method", "linear", "--no-sensitivities", seed="7"))
        self.assertEqual(rc, 0)
        self.assertNotEqual(slurp(os.path.join(o3, "power.json")), outs[0][0])

    def test_sensitivities_and_bootstrap_se(self):
        o = os.path.join(self.tmp, "s")
        rc, err = run(mini_args(o, "--grid", "6,8", "--studies", "20", "--se-boot", "20", "--ceiling", "7"))
        self.assertEqual(rc, 0, err)
        doc = json.loads(slurp(os.path.join(o, "power.json")))
        self.assertEqual(doc["evaluated"], [6, 7])       # the ceiling is evaluated when below the grid top
        self.assertEqual(sorted(doc["sensitivities"]), sorted(
            ["spread_x0.5", "spread_x1.5", "k_minus_3", "k_plus_3", "rho_0.3", "rho_0.6", "r_0", "r_0.10"]))

    def test_usage_and_invalid(self):
        self.assertEqual(run(["--rows", "x"])[0], 2)
        rc, err = run(["--rows", os.path.join(MINI, "rows.jsonl"), "--fixtures-dir", self.tmp,
                       "--suite-root", os.path.join(MINI, "suite"), "--candidates", os.path.join(MINI, "candidates.tsv"),
                       "--seed", "1", "--out", os.path.join(self.tmp, "x")])
        self.assertEqual(rc, 1)
        self.assertIn("head.diff", err)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "x")))


if __name__ == "__main__":
    unittest.main()
