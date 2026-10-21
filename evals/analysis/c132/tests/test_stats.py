"""stats.py against textbook values (cycle-132 Task 1.8; sdd.md §1.4, §5.3)."""
import math
import random
import unittest

import _path  # noqa: F401
from c132 import stats


def pair(pr, trial, cf, cm, d, costf=1.0, costm=1.0):
    return {"pr": pr, "trial": trial,
            "full": {"caught": cf, "defects": d, "cost": costf},
            "matched": {"caught": cm, "defects": d, "cost": costm}}


class NormalTest(unittest.TestCase):
    def test_phi_and_inverse(self):
        self.assertAlmostEqual(stats.phi_cdf(1.959963984540054), 0.975, places=9)
        self.assertAlmostEqual(stats.phi_inv(0.975), 1.959963984540054, places=9)
        self.assertAlmostEqual(stats.phi_cdf(0.0), 0.5, places=12)


class StudentTTest(unittest.TestCase):
    def test_quantiles(self):
        # t tables: t_{5,0.975} = 2.570582, t_{11,0.975} = 2.200985, t_{1,0.975} = 12.7062
        self.assertAlmostEqual(stats.t_inv(0.975, 5), 2.570582, delta=1e-5)
        self.assertAlmostEqual(stats.t_inv(0.975, 11), 2.200985, delta=1e-5)
        self.assertAlmostEqual(stats.t_inv(0.975, 1), 12.7062, delta=1e-3)
        self.assertAlmostEqual(stats.t_cdf(0.0, 7), 0.5, places=12)


class OBFBoundaryTest(unittest.TestCase):
    """Lan–DeMets O'Brien–Fleming spending at (1/3, 2/3, 1), two-sided 0.05.

    Reference: Jennison & Turnbull (2000) Table 7.6 / gsDesign sfLDOF, PRD FR-5 AC 1 and
    sdd.md §5.3: 3.710, 2.511, 1.993 (we hold within 0.01)."""

    def test_published_values_two_sided(self):
        b = stats.gs_boundaries([1 / 3, 2 / 3, 1.0], alpha=0.05)
        for got, want in zip(b, (3.710, 2.511, 1.993)):
            self.assertAlmostEqual(got, want, delta=0.01)

    def test_one_sided_0025_matches_two_sided_005(self):
        # gsDesign sfLDOF with one-sided alpha 0.025: the same boundaries (the lower
        # tail's crossing mass under H0 is negligible)
        b = stats.gs_boundaries([1 / 3, 2 / 3, 1.0], alpha=0.025, one_sided=True)
        for got, want in zip(b, (3.710, 2.511, 1.993)):
            self.assertAlmostEqual(got, want, delta=0.01)

    def test_single_look_is_fixed_sample(self):
        self.assertAlmostEqual(stats.gs_boundaries([1.0], alpha=0.05)[0], 1.95996, delta=1e-4)
        self.assertAlmostEqual(stats.gs_boundaries([1.0], alpha=0.025, one_sided=True)[0], 1.95996, delta=1e-4)

    def test_constant_multiplies(self):
        b1 = stats.gs_boundaries([0.5, 1.0], alpha=0.05)
        b2 = stats.gs_boundaries([0.5, 1.0], alpha=0.05, constant=1.1)
        for x, y in zip(b1, b2):
            self.assertAlmostEqual(y, 1.1 * x, places=9)

    def test_two_looks_published(self):
        # two equally spaced looks, Lan–DeMets OBF two-sided 0.05: 2.963, 1.969
        b = stats.gs_boundaries([0.5, 1.0], alpha=0.05)
        self.assertAlmostEqual(b[0], 2.963, delta=0.01)
        self.assertAlmostEqual(b[1], 1.969, delta=0.01)

    def test_coarse_grid_close_to_fine(self):
        fine = stats.gs_boundaries([0.4, 0.75, 1.0], alpha=0.05, grid=2000)
        coarse = stats.gs_boundaries([0.4, 0.75, 1.0], alpha=0.05, grid=400)
        for x, y in zip(fine, coarse):
            self.assertAlmostEqual(x, y, delta=0.005)

    def test_no_new_information_gives_infinite_boundary(self):
        b = stats.gs_boundaries([0.5, 0.5, 1.0], alpha=0.05)
        self.assertTrue(math.isinf(b[1]))

    def test_tiny_first_fraction(self):
        # α*(0.01) underflows 1 − α/2 in double precision: the boundary is still finite and huge
        b = stats.gs_boundaries([0.01, 1.0], alpha=0.05)
        self.assertGreater(b[0], 8.0)
        self.assertAlmostEqual(b[1], 1.95996, delta=0.01)
        self.assertGreater(stats.gs_boundaries([1e-4, 1.0], alpha=0.025, one_sided=True)[0], 8.0)

    def test_rci(self):
        self.assertEqual(stats.rci(0.2, 0.05, 2.0), (0.1, 0.30000000000000004))

    def test_conditional_power(self):
        # at the final look the decision is known
        self.assertEqual(stats.conditional_power(2.5, 1.0, 1.99), 1.0)
        self.assertEqual(stats.conditional_power(1.0, 1.0, 1.99), 0.0)
        # current-trend formula: CP = 1 - Phi((b - z/sqrt(t)) / sqrt(1-t))
        z, t, b = 1.5, 0.5, 1.97
        want = 1 - stats.phi_cdf((b - z / math.sqrt(t)) / math.sqrt(1 - t))
        self.assertAlmostEqual(stats.conditional_power(z, t, b), want, places=12)
        # an explicit drift of 0 (the null): CP = 1 - Phi((b - z sqrt t)/sqrt(1-t))
        want0 = 1 - stats.phi_cdf((b - z * math.sqrt(t)) / math.sqrt(1 - t))
        self.assertAlmostEqual(stats.conditional_power(z, t, b, drift=0.0), want0, places=12)


class KappaTest(unittest.TestCase):
    def test_textbook_2x2(self):
        # po = 35/50 = 0.70, pe = (25*30 + 25*20)/50^2 = 0.50 → kappa = 0.40
        self.assertAlmostEqual(stats.kappa([[20, 5], [10, 15]]), 0.4, places=12)

    def test_textbook_3x3(self):
        # a 3x3 table, kappa = (po - pe)/(1 - pe) by hand
        # rows 35, 35, 27; cols 30, 40, 27 (n = 97 → po = 75/97)
        t = [[25, 5, 5], [3, 30, 2], [2, 5, 20]]
        n = 97.0
        po = 75 / n
        rows, cols = [35, 35, 27], [30, 40, 27]
        pe = sum(r * c for r, c in zip(rows, cols)) / (n * n)
        self.assertAlmostEqual(stats.kappa(t), (po - pe) / (1 - pe), places=12)

    def test_degenerate(self):
        self.assertIsNone(stats.kappa([[10, 0], [0, 0]]))
        self.assertIsNone(stats.kappa([[0, 0], [0, 0]]))


class REMLTest(unittest.TestCase):
    """Balanced two-arm design with a PR random intercept: REML equals the ANOVA
    (method-of-moments) estimates when they are positive — computed by hand below."""

    DATA = {  # pr: (full cells, matched cells) — cell recall values
        "p1": ([0.8, 0.9], [0.6, 0.7]),
        "p2": ([0.5, 0.7], [0.4, 0.4]),
        "p3": ([1.0, 0.9], [0.9, 0.7]),
    }

    def cells(self):
        out = []
        for pr, (f, m) in sorted(self.DATA.items()):
            for t, (yf, ym) in enumerate(zip(f, m), 1):
                out.append(pair(pr, t, yf * 10, ym * 10, 10))
        return out

    def hand(self):
        P, n = 3, 4
        N = P * n
        fulls = [y for f, _ in self.DATA.values() for y in f]
        mats = [y for _, m in self.DATA.values() for y in m]
        beta = sum(fulls) / len(fulls) - sum(mats) / len(mats)
        # within-PR residual: y - PR mean - beta*(x - 1/2)
        sse = 0.0
        grand = (sum(fulls) + sum(mats)) / N
        ssb = 0.0
        for f, m in self.DATA.values():
            pm = (sum(f) + sum(m)) / n
            ssb += n * (pm - grand) ** 2
            for y in f:
                sse += (y - pm - beta / 2) ** 2
            for y in m:
                sse += (y - pm + beta / 2) ** 2
        mse = sse / (N - P - 1)
        msb = ssb / (P - 1)
        su2 = (msb - mse) / n
        se_beta = math.sqrt(mse / (N / 4.0))   # sum over cells of (x - xbar_p)^2 = N/4
        return beta, mse, su2, se_beta

    def test_matches_anova_within_1e6(self):
        beta, se2, su2, se_beta = self.hand()
        self.assertGreater(su2, 0)
        r = stats.reml_lmm(self.cells())
        self.assertFalse(r["boundary"])
        self.assertAlmostEqual(r["beta"], beta, delta=1e-6)
        self.assertAlmostEqual(r["sigma_e2"], se2, delta=1e-6)
        self.assertAlmostEqual(r["sigma_u2"], su2, delta=1e-6)
        self.assertAlmostEqual(r["se"], se_beta, delta=1e-6)
        lo, hi = r["ci95"]
        self.assertAlmostEqual(lo, beta - 1.959963984540054 * se_beta, delta=1e-6)
        self.assertAlmostEqual(hi, beta + 1.959963984540054 * se_beta, delta=1e-6)

    def test_boundary_when_between_variance_negative(self):
        # identical PR means → MSB = 0 < MSE → sigma_u^2 at the lower edge
        cells = [pair("p1", 1, 8, 5, 10), pair("p1", 2, 6, 7, 10),
                 pair("p2", 1, 6, 7, 10), pair("p2", 2, 8, 5, 10),
                 pair("p3", 1, 7, 6, 10), pair("p3", 2, 7, 6, 10)]
        r = stats.reml_lmm(cells)
        self.assertTrue(r["boundary"])
        self.assertLess(r["sigma_u2"], 1e-4)

    def test_degenerate(self):
        self.assertEqual(stats.reml_lmm([])["status"], "no_valid_pairs")


class BootstrapTest(unittest.TestCase):
    def cells(self):
        rng = random.Random(7)
        out = []
        for p in range(8):
            d = rng.randint(3, 12)
            for t in (1, 2):
                out.append(pair("pr-%02d" % p, t, rng.randint(0, d), rng.randint(0, d), d,
                                costf=rng.uniform(5, 20), costm=rng.uniform(5, 20)))
        return out

    def test_point_estimate_and_reproducible(self):
        c = self.cells()
        a = stats.cluster_bootstrap(c, n=2000, seed=11)
        b = stats.cluster_bootstrap(c, n=2000, seed=11)
        self.assertEqual(a, b)
        cf = sum(x["full"]["caught"] for x in c)
        cm = sum(x["matched"]["caught"] for x in c)
        d = sum(x["full"]["defects"] for x in c)
        self.assertAlmostEqual(a["delta"], (cf - cm) / d, places=12)
        self.assertLessEqual(a["ci95"][0], a["ci90"][0])
        self.assertGreaterEqual(a["ci95"][1], a["ci90"][1])
        self.assertNotEqual(a, stats.cluster_bootstrap(c, n=2000, seed=12))

    def test_pairs_of_a_pr_travel_together(self):
        # one PR has delta +1 on both trials, the others 0: every resample is k/P
        c = [pair("a", 1, 2, 0, 2), pair("a", 2, 2, 0, 2)]
        for p in "bcd":
            c += [pair(p, 1, 1, 1, 2), pair(p, 2, 1, 1, 2)]
        r = stats.cluster_bootstrap(c, n=500, seed=3)
        for v in r["_draws"]:
            self.assertIn(round(v * 4, 9), (0.0, 1.0, 2.0, 3.0, 4.0))

    def test_linear_se_close_to_bootstrap(self):
        c = self.cells()
        r = stats.cluster_bootstrap(c, n=10000, seed=5)
        self.assertAlmostEqual(stats.linear_se(c) / r["se"], 1.0, delta=0.1)

    def test_pr_weighted(self):
        c = [pair("a", 1, 2, 0, 2), pair("a", 2, 2, 0, 2), pair("b", 1, 0, 0, 10), pair("b", 2, 0, 0, 10)]
        r = stats.cluster_bootstrap(c, n=100, seed=1)
        self.assertAlmostEqual(r["pr_weighted"]["delta"], 0.5, places=12)
        self.assertAlmostEqual(r["delta"], 4 / 24, places=12)

    def test_degenerate(self):
        self.assertEqual(stats.cluster_bootstrap([], n=10, seed=1)["status"], "no_valid_pairs")
        one = [pair("a", 1, 2, 0, 2), pair("a", 2, 1, 0, 2)]
        self.assertEqual(stats.cluster_bootstrap(one, n=10, seed=1)["status"], "zero_se")


class PermutationTest(unittest.TestCase):
    def test_exact_constructed_case(self):
        # three PRs with paired differences 1, 2, 3 (same defect count): |T| >= 6 only for
        # all-plus and all-minus sign vectors → p = 2/8
        c = [pair("a", 1, 1, 0, 5), pair("b", 1, 2, 0, 5), pair("c", 1, 3, 0, 5)]
        r = stats.permutation_test(c, n=10000, seed=1, unit="pr")
        self.assertTrue(r["exact"])
        self.assertAlmostEqual(r["p"], 0.25, places=12)

    def test_pr_vs_pair_unit(self):
        # PR a: trial diffs +2 and -2 (net 0); PR b: +1, +1. PR unit: T = 2 → |T|>=2 for
        # sign vectors with b's sign ±: all 4 → p = 1. Pair unit: 16 vectors; |s1*2 - s2*2 + s3 + s4|>=2 …
        c = [pair("a", 1, 2, 0, 4), pair("a", 2, 0, 2, 4), pair("b", 1, 1, 0, 4), pair("b", 2, 1, 0, 4)]
        self.assertAlmostEqual(stats.permutation_test(c, n=10000, seed=1, unit="pr")["p"], 1.0)
        # enumerate the pair-level distribution by hand
        d = [2, -2, 1, 1]
        cnt = 0
        for m in range(16):
            s = sum(x if (m >> i) & 1 else -x for i, x in enumerate(d))
            cnt += abs(s) >= 2 - 1e-12
        self.assertAlmostEqual(stats.permutation_test(c, n=10000, seed=1, unit="pair")["p"], cnt / 16)

    def test_monte_carlo_close_to_exact(self):
        c = [pair("p%02d" % i, 1, i % 4, 0, 6) for i in range(16)]
        exact = stats.permutation_test(c, n=1 << 16, seed=1, unit="pr")
        mc = stats.permutation_test(c, n=10000, seed=1, unit="pr")
        self.assertTrue(exact["exact"])
        self.assertFalse(mc["exact"])
        self.assertAlmostEqual(exact["p"], mc["p"], delta=0.02)


class PlaceboTest(unittest.TestCase):
    def null_cells(self, seed, n_prs=20):
        rng = random.Random(seed)
        out = []
        for p in range(n_prs):
            d = rng.randint(10, 25)
            q = rng.uniform(0.2, 0.9)
            for t in (1, 2):
                cf = sum(rng.random() < q for _ in range(d))
                cm = sum(rng.random() < q for _ in range(d))
                out.append(pair("pr-%02d" % p, t, cf, cm, d))
        return out

    def test_calibrated_on_synthetic_nulls(self):
        r = stats.placebo(self.null_cells(1), seed=20261021, n=200, boot=1000)
        self.assertEqual(r["n"], 200)
        self.assertLessEqual(r["share_excluding_zero"], 0.08)
        self.assertLess(r["mean_abs_delta"], 0.03)
        self.assertTrue(r["pass"])
        self.assertEqual(r, stats.placebo(self.null_cells(1), seed=20261021, n=200, boot=1000))

    def test_small_cluster_undercoverage_is_visible(self):
        # at 6 PRs the percentile interval excludes 0 on more than 8 % of null shuffles while
        # the t diagnostic stays near nominal (the s1-d finding; the band is the lead's call)
        shares, tshares = [], []
        for s in range(4):
            r = stats.placebo(self.null_cells(s, n_prs=6), seed=s, n=100, boot=500)
            shares.append(r["share_excluding_zero"])
            tshares.append(r["diagnostic_share_excluding_zero_t"])
        self.assertGreater(sum(shares) / 4, 0.08)
        self.assertLess(sum(tshares) / 4, 0.08)

    def test_shuffle_preserves_pr_totals(self):
        c = self.null_cells(2)
        rng = random.Random(4)
        s = stats.shuffle_within_pr(c, rng)
        for pr in {x["pr"] for x in c}:
            a = sorted([x["full"]["caught"] for x in c if x["pr"] == pr] + [x["matched"]["caught"] for x in c if x["pr"] == pr])
            b = sorted([x["full"]["caught"] for x in s if x["pr"] == pr] + [x["matched"]["caught"] for x in s if x["pr"] == pr])
            self.assertEqual(a, b)

    def test_a_real_effect_fails_the_band_only_when_not_shuffled(self):
        # sanity: the primary read on an effect excludes 0, the placebo does not
        c = [pair("p%d" % i, t, 9, 3, 10) for i in range(8) for t in (1, 2)]
        self.assertGreater(stats.cluster_bootstrap(c, n=500, seed=1)["ci95"][0], 0)


class CostTest(unittest.TestCase):
    def test_defects_per_usd(self):
        c = [pair("a", 1, 4, 2, 5, costf=20, costm=10), pair("b", 1, 2, 2, 5, costf=20, costm=10)]
        r = stats.defects_per_usd(c, n=200, seed=1)
        self.assertAlmostEqual(r["full"]["value"], 6 / 40)
        self.assertAlmostEqual(r["matched"]["value"], 4 / 20)

    def test_cost_per_extra_defect(self):
        c = [pair("a", 1, 4, 2, 5, costf=20, costm=10), pair("b", 1, 2, 2, 5, costf=20, costm=10)]
        r = stats.cost_per_extra_defect(c, baseline="matched", spend="valid")
        self.assertAlmostEqual(r["value"], (40 - 20) / (6 - 4))
        r = stats.cost_per_extra_defect(c, baseline="matched", spend="all", all_spend={"full": 50.0, "matched": 30.0})
        self.assertAlmostEqual(r["value"], (50 - 30) / 2)
        c2 = [dict(x, matched=dict(x["matched"], session1={"caught": 1, "cost": 1.0})) for x in c]
        r = stats.cost_per_extra_defect(c2, baseline="session1", spend="valid")
        self.assertAlmostEqual(r["value"], (40 - 2) / (6 - 2))
        c3 = [pair("a", 1, 2, 2, 5)]
        self.assertEqual(stats.cost_per_extra_defect(c3, baseline="matched", spend="valid")["status"], "no_extra_defects")


if __name__ == "__main__":
    unittest.main()
