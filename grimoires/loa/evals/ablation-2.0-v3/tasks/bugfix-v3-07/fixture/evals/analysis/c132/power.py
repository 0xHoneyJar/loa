#!/usr/bin/env python3
"""power.py — the cycle-132 power simulation of the complete pre-registered procedure.

Usage:
  python3 -I evals/analysis/c132/power.py --rows F [--rows F …] --runs-root DIR [--runs-root DIR …]
      --fixtures-dir evals/fixtures/review-prs --suite-root DIR [--suite-root DIR …]
      --candidates F --seed N --out DIR
      [--labels-dir DIR] [--grid 6,8,10,12] [--studies 2000] [--ceiling N] [--envelope 2500]
      [--mde 0.10] [--exclusion 0.05] [--partial-prob 0.10] [--se-method bootstrap|linear]
      [--se-boot 200] [--no-sensitivities] [--interval t|percentile]
      [--validity c132|c131]   (the profiles' validity rules, as reads-c132.py --validity)
      [--quiet]                (no progress lines on stderr; outputs are unaffected)

Model (sdd.md §5.3, D-5.3, D-7.7; prd.md FR-6, D18):
  * Rows → cells (common.py: the decision statistic's missed set, the validity filter). Profiles:
    every task with ≥ 1 valid a0_bare and ≥ 1 valid a1_full cell; per defect the caught count and
    trials per arm.
  * Cost fits: least squares cost = a + b·L per arm (a1_full, a0_bare, a0_bare_fable) over the
    completed rows with a cost, L = the fixture's head.diff changed lines ('+'/'-' lines, file headers
    excluded) or the candidate table's diff_lines; k_p = round(ĉ_full(L)/ĉ_bare(L)), floor 2, cap 30
    (a non-positive ĉ_bare gives the cap); the Fable k from ĉ_bare_fable.
  * Per arm a Beta(α, β) fitted across defects by the method of moments on the caught shares (the
    binomial part of the variance removed), a blind-spot weight π0 = max(0, share never caught −
    the Beta-Binomial chance of never catching); in each simulated study a defect never caught is a
    blind spot (p = 0) with probability π0 / share-never-caught, else its latent p is drawn from the
    posterior Beta(α + c, β + n − c) (shrinkage toward the arm's grand mean).
  * Matched cell: v ~ Binomial(k, 1 − r) valid sessions (invalid below ⌈k/2⌉, D-7.3); a defect is
    caught with probability (1 − ρ)(1 − (1 − p)^v) + ρ·p (ρ = 0: independent sessions; the
    correlated-sessions sensitivity ρ ∈ {0.3, 0.6}: with probability ρ the v sessions behave as one —
    the pairwise session correlation is ρ). Full cell: invalid with probability r; each defect caught
    with its shifted p.
  * Design effect: one shift δ on the logit of every full p solves E[recall_full] − E[recall_matched]
    = Δ_target (0 or the MDE) over the profiles' defects (expectations by a seeded Monte Carlo over
    the latent draws); the expected share of defects that cannot move (a full blind spot, or a
    shifted p outside [0.01, 0.99]) is the clipped share; > 0.10 flags the N as unreliable.
  * A study: N profiles drawn with replacement, 2 trials per arm, pairwise exclusion; groups for N
    (N ≤ 7: one; 8–11: 6 + rest; ≥ 12: 6, ⌊(N−6)/2⌋, rest); with probability --partial-prob the last
    group is cut to a uniform size in [1, |G| − 1] (a cap-driven partial group); at each look the
    defect-weighted Δ̂ and its PR-cluster SE (bootstrap with --se-boot resamples, or the linear SE)
    over the PRs of groups ≤ j; then reads.py's procedure exactly: t_j = SE_plan²/SE_j² (capped at 1,
    non-decreasing, the last look t = 1), YES/NO OBF boundaries × c, conditional powers, the D16
    partition, no decision below 6 valid PRs or 30 labelled defects. SE_plan(N) = the median final-
    look SE of the Δ = MDE studies. Boundaries in the simulation use t rounded to 0.01 and a
    400-point grid (cached; within 0.005 of the 2,000-point recursion — test_stats).
  * --interval t (default, round 1): the look's boundaries move to the cluster-t scale with
    df = valid PRs − 1, exactly as reads.py --interval t; `percentile` keeps the normal scale.
  * Calibration: c from 1.00 in steps of 0.01 until P(YES | Δ = 0) ≤ 0.05; chosen N = the smallest
    evaluated N (≤ the corpus ceiling) with P(YES | Δ = MDE) ≥ 0.80 AND P(NO | Δ = 0) ≥ 0.80 under its
    calibrated c (round 1). When no N satisfies both, nothing is chosen (chosen_n null,
    decision_required true): the figures are reported at the largest evaluated N (reference_n) and
    the lead decides. The per-N table carries P(NO | 0), P(SMALL | 0), P(NEGATIVE | 0 and | MDE)
    (round 3: reads.decide's ordered table; a significantly negative Δ̂ is NEGATIVE, no longer NO), the clipped share and the
    expected matched / full recall beside each Δ row; the arm fits carry the literal π0 diagnostic.
  * Cap (sdd.md §5.3): (N × (2·22 + 2·22 + 2·22 + 2·12 + 24) + |G1| × 2 × 20 + 2·N·3 + 30 + 80 + 60)
    × 1.25, rounded up to USD 50; affordable-N: a cap above --envelope moves N to the largest
    evaluated N whose cap fits, with its power stated (< 0.50 → exploratory).
  * Sensitivities at the chosen N: profile spread × 0.5 / × 1.5 (each defect's logit moved by
    (s − 1)(PR mean − grand mean) per arm), k ± 3, ρ 0.3 / 0.6, r 0 / 0.10 — each with the main
    calibrated c and its own recalibrated c.
  * The candidate table (--candidates TSV with a header: fixture, head_date, labels|defects|
    seeded_labels, exposure_fable_5_1|exposure, diff_lines, contamination_note …): eligible = ≥ 2
    labels and an exposure value; seeded order = post-cutoff fixtures shuffled by the seed, then
    the others, pr-11 last and flagged; the ceiling = min(15, eligible) unless --ceiling.

Outputs DIR/power.json + DIR/power.md: sorted keys, %.4f floats, no timestamps or absolute paths;
deterministic by seed. Exit 0 written; 1 inputs invalid; 2 usage.
"""
import argparse
import hashlib
import json
import math
import os
import random
import re
import sys

if __package__ in (None, ""):
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from c132 import common, stats  # noqa: E402
from c132.common import InputError  # noqa: E402
from c132.reads import dumps, f4, MIN_PRS, MIN_DEFECTS, decide, PARTITION_LEGEND  # noqa: E402

K_FLOOR, K_CAP = 2, 30
UNIT = {"full": 22, "matched_opus": 22, "matched_fable": 22, "review_only": 12, "smoke": 24,
        "open_mount": 20, "blind_per_pr": 3, "judge": 30, "reproduction": 80, "dissents": 60}
CONTINGENCY = 1.25


# ---------------------------------------------------------------- inputs
def diff_lines(path):
    n = 0
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if (line.startswith("+") and not line.startswith("+++ ")) or (line.startswith("-") and not line.startswith("--- ")):
                n += 1
    return n


def task_fixture(suite_roots):
    out = {}
    pat = re.compile(r"review-prs/(pr-[0-9]+)")
    for root in suite_roots or []:
        tdir = os.path.join(root, "tasks")
        if not os.path.isdir(tdir):
            continue
        for t in sorted(os.listdir(tdir)):
            p = os.path.join(tdir, t, "task.yaml")
            if not os.path.isfile(p):
                continue
            with open(p, encoding="utf-8") as f:
                for line in f:
                    if line.startswith("review_catch:"):
                        m = pat.search(line)
                        if m:
                            out[t] = m.group(1)
                        break
    return out


def ols(xs, ys):
    """least squares y = a + b·x; with < 2 distinct x a line through the origin by the mean ratio"""
    n = len(xs)
    if n == 0:
        return None
    if len(set(xs)) < 2:
        mx = sum(xs) / n
        return (0.0, (sum(ys) / n) / mx if mx else 0.0)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    b = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    return (my - b * mx, b)


def k_for(L, fit_full, fit_bare, shift=0):
    cf = fit_full[0] + fit_full[1] * L
    cb = fit_bare[0] + fit_bare[1] * L
    k = K_CAP if cb <= 0 else int(math.floor(cf / cb + 0.5))
    return max(K_FLOOR, min(K_CAP, k + shift))


def beta_mom(counts, weights=None):
    """Beta(α, β) by the method of moments from [(caught, trials)] with the binomial variance
    removed; optional per-defect weights (the non-blind probability)"""
    w = weights or [1.0] * len(counts)
    pts = [(c / float(n), 1.0 / n, wi) for (c, n), wi in zip(counts, w) if n and wi > 0]
    W = sum(wi for _, _, wi in pts)
    if not pts or W <= 0:
        return None
    m = sum(x * wi for x, _, wi in pts) / W
    v = sum(wi * (x - m) ** 2 for x, _, wi in pts) / W
    inv_n = sum(i * wi for _, i, wi in pts) / W
    m = min(max(m, 1e-3), 1 - 1e-3)
    denom = m * (1 - m)
    rho = (v / denom - inv_n) / (1.0 - inv_n) if inv_n < 1 else v / denom
    rho = min(max(rho, 1e-3), 0.999)
    s = 1.0 / rho - 1.0
    return {"alpha": m * s, "beta": (1 - m) * s, "mean": m, "rho": rho}


def bb_zero(n, a, b):
    """Beta-Binomial P(0 of n caught) = B(α, β + n)/B(α, β)"""
    return math.exp(math.lgamma(b + n) + math.lgamma(a + b) - math.lgamma(b) - math.lgamma(a + b + n))


def fit_arm(defects, rounds=200):
    """defects: [(caught, trials)] → {alpha, beta, mean, rho, pi0, share_never, chance_never}.
    The blind-spot mixture by a fixed point: the Beta is fitted to the non-blind part (a never-caught
    defect weighted 1 − π0/never), chance = its mean P(0 caught), and P(never) = π0 + (1 − π0)·chance
    gives π0 = max(0, (never − chance)/(1 − chance))."""
    if not defects:
        return None
    never = sum(1 for c, n in defects if c == 0) / float(len(defects))
    pi0 = 0.0
    f = None
    for _ in range(rounds):
        wz = 1.0 - (pi0 / never if never > 0 else 0.0)
        f = beta_mom(defects, [wz if c == 0 else 1.0 for c, _ in defects])
        if f is None:
            return None
        chance = sum(bb_zero(n, f["alpha"], f["beta"]) for _, n in defects) / float(len(defects))
        new = max(0.0, (never - chance) / (1.0 - chance)) if chance < 1 else 0.0
        new = min(new, never)
        if abs(new - pi0) < 1e-12:
            pi0 = new
            break
        pi0 = new
    f["share_never"] = never
    f["chance_never"] = chance
    f["pi0"] = pi0
    # DIAGNOSTIC (round 1): the literal "never − chance" under the one-pass Beta fitted to every
    # defect (blind spots included), which absorbs blind spots into the chance term
    f0 = beta_mom(defects)
    chance0 = sum(bb_zero(n, f0["alpha"], f0["beta"]) for _, n in defects) / float(len(defects))
    f["pi0_literal"] = max(0.0, never - chance0)
    f["chance_never_literal"] = chance0
    return f


def logit(p):
    p = min(max(p, 1e-9), 1 - 1e-9)
    return math.log(p / (1 - p))


def expit(x):
    if x >= 0:
        return 1.0 / (1.0 + math.exp(-x))
    e = math.exp(x)
    return e / (1.0 + e)


# ---------------------------------------------------------------- model
class Model:
    def __init__(self, profiles, fits, ks, rho=0.0, spread=1.0, k_shift=0):
        self.profiles = profiles      # [{task, defects: [(cb, nb, cf, nf)]}]
        self.fits = fits              # {"bare": fit, "full": fit}
        self.ks = ks                  # {task: k}
        self.rho, self.spread, self.k_shift = rho, spread, k_shift
        # PR mean logits of the posterior means (the spread sensitivity)
        self.pr_shift = {}
        for arm, idx in (("bare", (0, 1)), ("full", (2, 3))):
            f = fits[arm]
            means = {}
            for pf in profiles:
                ls = [logit((d[idx[0]] + f["alpha"]) / (d[idx[1]] + f["alpha"] + f["beta"])) for d in pf["defects"]]
                means[pf["task"]] = sum(ls) / len(ls)
            grand = sum(means.values()) / len(means)
            for t, m in means.items():
                self.pr_shift[(arm, t)] = (spread - 1.0) * (m - grand)

    def k(self, task):
        return max(K_FLOOR, min(K_CAP, self.ks[task] + self.k_shift))

    def latent(self, rng, pf):
        """per defect (p_bare, p_full) for one study (blind spots → 0)"""
        out = []
        for cb, nb, cf, nf in pf["defects"]:
            ps = []
            for arm, c, n in (("bare", cb, nb), ("full", cf, nf)):
                f = self.fits[arm]
                if c == 0 and f["share_never"] > 0 and rng.random() < f["pi0"] / f["share_never"]:
                    ps.append(None)
                    continue
                p = rng.betavariate(f["alpha"] + c, f["beta"] + n - c)
                sh = self.pr_shift[(arm, pf["task"])]
                if sh:
                    p = expit(logit(p) + sh)
                ps.append(p)
            out.append(tuple(ps))
        return out

    def matched_p(self, p, v):
        if p is None or v <= 0:
            return 0.0
        return (1.0 - self.rho) * (1.0 - (1.0 - p) ** v) + self.rho * p

    def solve_delta(self, target, seed, draws=200):
        """δ on the logit of p_full with E[recall_full] − E[recall_matched] = target; the clipped share"""
        rng = random.Random("%s:solve" % seed)
        samples = []
        for pf in self.profiles:
            k = self.k(pf["task"])
            for _ in range(draws):
                for pb, pfu in self.latent(rng, pf):
                    samples.append((self.matched_p(pb, k), pfu))
        n = float(len(samples))
        em = sum(m for m, _ in samples) / n

        def ef(d):
            return sum(expit(logit(p) + d) for _, p in samples if p is not None) / n

        lo, hi = -15.0, 15.0
        reach = (ef(lo) - em, ef(hi) - em)
        if not (reach[0] <= target <= reach[1]):
            d = lo if target < reach[0] else hi
            status = "unreachable"
        else:
            for _ in range(80):
                mid = (lo + hi) / 2.0
                if ef(mid) - em < target:
                    lo = mid
                else:
                    hi = mid
            d = (lo + hi) / 2.0
            status = "ok"
        clipped = sum(1 for _, p in samples if p is None or not (0.01 <= expit(logit(p) + d) <= 0.99)) / n
        return {"delta_logit": d, "clipped_share": clipped, "status": status,
                "expected_recall_matched": em, "expected_recall_full": ef(d)}


def groups_for(n):
    if n <= 7:
        return [n]
    if n <= 11:
        return [6, n - 6]
    a = (n - 6) // 2
    return [6, a, n - 6 - a]


def study(model, rng, n, shift, r, partial_prob, se_method, se_boot):
    """one simulated study → per look [(Δ̂, SE, valid PRs, labelled defects)]"""
    profs = [model.profiles[rng.randrange(len(model.profiles))] for _ in range(n)]
    sizes = groups_for(n)
    if partial_prob and sizes[-1] >= 2 and rng.random() < partial_prob:
        sizes = sizes[:-1] + [rng.randint(1, sizes[-1] - 1)]
    per_pr = []
    for i, pf in enumerate(profs):
        lat = model.latent(rng, pf)
        k = model.k(pf["task"])
        pairs = []
        for _t in (1, 2):
            full_ok = rng.random() >= r
            v = sum(1 for _ in range(k) if rng.random() >= r) if r else k
            m_ok = v >= int(math.ceil(k / 2.0))
            cf = sum(1 for _pb, p in lat if p is not None and rng.random() < expit(logit(p) + shift))
            cm = sum(1 for pb, _p in lat if rng.random() < model.matched_p(pb, v))
            if full_ok and m_ok:
                pairs.append((cf, cm, len(lat)))
        per_pr.append(pairs)
    looks = []
    upto = 0
    for g in sizes:
        upto += g
        cells = []
        for i in range(upto):
            for t, (cf, cm, d) in enumerate(per_pr[i], 1):
                cells.append({"pr": "p%d" % i, "trial": t, "full": {"caught": cf, "defects": d},
                              "matched": {"caught": cm, "defects": d}})
        prs = {c["pr"] for c in cells}
        d_tot = sum(per_pr[int(p[1:])][0][2] for p in prs)
        if not cells:
            looks.append((None, None, 0, 0))
            continue
        aggs = stats._by_pr(cells)
        delta = stats._delta(list(aggs.values()))
        if se_method == "linear":
            se = stats.linear_se(cells)
        else:
            A = list(aggs.values())
            P = len(A)
            ds = []
            for _ in range(se_boot):
                ds.append(stats._delta([A[rng.randrange(P)] for _ in range(P)]))
            mu = sum(ds) / len(ds)
            se = math.sqrt(sum((x - mu) ** 2 for x in ds) / (len(ds) - 1))
        looks.append((delta, se, len(prs), d_tot))
    return looks, len(sizes) == len(groups_for(n))


def evaluate(results, se_plan, c, mde, n_looks_planned, interval="t"):
    """reads.py's look procedure over stored studies → outcome shares"""
    counts = {"NEGATIVE": 0, "YES": 0, "NO": 0, "SMALL": 0, "FUTILE": 0, "INCONCLUSIVE": 0}
    stop_looks = 0
    for looks, _complete in results:
        ts, outcome = [], "INCONCLUSIVE"
        last = len(looks)
        for j, (delta, se, nprs, ndef) in enumerate(looks, 1):
            final = j == last
            if delta is None or not se:
                ts.append(ts[-1] if ts else 0.0)
                continue
            t = 1.0 if final else min(1.0, se_plan ** 2 / se ** 2)
            t = round(t, 2)
            if ts and t < ts[-1]:
                t = ts[-1]
            ts.append(t)
            if nprs < MIN_PRS or ndef < MIN_DEFECTS:
                continue
            fr = ts[:]
            b_yes = stats.gs_boundaries(fr, alpha=0.05, constant=c, grid=400)[-1]
            b_no = stats.gs_boundaries(fr, alpha=0.025, constant=c, one_sided=True, grid=400)[-1]
            if interval == "t":     # reads.py --interval t: the cluster-t scale, df = valid PRs − 1
                df = max(nprs - 1, 1)
                b_yes, b_no = stats.t_boundary(round(b_yes, 6), df), stats.t_boundary(round(b_no, 6), df)
            z_yes = delta / se
            z_no = (mde - delta) / se
            cp_y = cp_n = 1.0
            if not final:
                frf = fr if fr[-1] >= 1.0 else fr + [1.0]
                cp_y = stats.conditional_power(z_yes, t, stats.gs_boundaries(frf, alpha=0.05, constant=c, grid=400)[-1])
                cp_n = stats.conditional_power(z_no, t, stats.gs_boundaries(frf, alpha=0.025, constant=c, one_sided=True, grid=400)[-1])
            hi = delta + b_yes * se if not math.isinf(b_yes) else math.inf
            dcs = decide(delta, z_yes, b_yes, z_no, b_no, hi, mde, cp_y, cp_n, final)
            if dcs != "CONTINUE":
                outcome = dcs
                stop_looks += j
                break
        counts[outcome] += 1
    n = float(len(results))
    out = {k.lower(): v / n for k, v in counts.items()}
    out["void"] = 0.0
    return out


def calibrate(null_results, se_plan, mde, n_looks, interval="t"):
    c = 1.0
    while c < 3.0:
        if evaluate(null_results, se_plan, c, mde, n_looks, interval)["yes"] <= 0.05:
            progress("calibrated constant %.2f" % c)
            return round(c, 2)
        c = round(c + 0.01, 2)
    return 3.0


def progress(msg):
    """a progress line on stderr (round 2; never in the outputs)"""
    if not QUIET:
        sys.stderr.write("power: %s\n" % msg)
        sys.stderr.flush()


QUIET = False


def simulate_n(model, n, mde, studies, seed, r, partial_prob, se_method, se_boot, tag):
    out = {}
    for name, target in (("null", 0.0), ("mde", mde)):
        sol = model.solve_delta(target, "%s:%s:%s" % (seed, tag, name))
        rng = random.Random("%s:%s:%d:%s" % (seed, tag, n, name))
        res = [study(model, rng, n, sol["delta_logit"], r, partial_prob, se_method, se_boot) for _ in range(studies)]
        progress("simulated %s N=%d Δ=%s (%d studies)" % (tag, n, name, studies))
        out[name] = {"solve": sol, "results": res}
    finals = sorted(x[0][-1][1] for x in out["mde"]["results"] if x[0][-1][1])
    se_plan = stats.quantile(finals, 0.5) if finals else None
    return out, se_plan


def summarise(sim, se_plan, c, mde, n, interval="t"):
    nl = len(groups_for(n))
    row = {"n": n, "groups": groups_for(n), "se_plan": se_plan, "constant": c}
    for name in ("null", "mde"):
        ev = evaluate(sim[name]["results"], se_plan, c, mde, nl, interval)
        row[name] = ev
        row["clipped_share_" + name] = sim[name]["solve"]["clipped_share"]
        row["solve_status_" + name] = sim[name]["solve"]["status"]
        row["expected_recall_matched_" + name] = sim[name]["solve"]["expected_recall_matched"]
        row["expected_recall_full_" + name] = sim[name]["solve"]["expected_recall_full"]
    row["power_at_mde"] = row["mde"]["yes"]
    row["type1"] = row["null"]["yes"]
    row["power_no_at_null"] = row["null"]["no"]      # round 1: the power to conclude "no actionable lift"
    row["small_at_null"] = row["null"]["small"]
    row["negative_at_null"] = row["null"]["negative"]     # round 3: the NEGATIVE outcome
    row["negative_at_mde"] = row["mde"]["negative"]
    row["meets_both"] = row["power_at_mde"] >= 0.80 and row["power_no_at_null"] >= 0.80
    row["mc_se_power"] = math.sqrt(max(row["power_at_mde"] * (1 - row["power_at_mde"]), 0.0) / len(sim["mde"]["results"]))
    row["unreliable"] = max(row["clipped_share_null"], row["clipped_share_mde"]) > 0.10
    return row


def cap_usd(n):
    g1 = groups_for(n)[0]
    per_pr = (2 * UNIT["full"] + 2 * UNIT["matched_opus"] + 2 * UNIT["matched_fable"]
              + 2 * UNIT["review_only"] + UNIT["smoke"])
    raw = (n * per_pr + g1 * 2 * UNIT["open_mount"] + 2 * n * UNIT["blind_per_pr"]
           + UNIT["judge"] + UNIT["reproduction"] + UNIT["dissents"])
    total = raw * CONTINGENCY
    return int(math.ceil(total / 50.0 - 1e-9) * 50), raw


# ---------------------------------------------------------------- candidates
ALIASES = {"labels": ("labels", "defects", "seeded_labels", "seeded_label_count", "label_count"),
           "exposure": ("exposure_fable_5_1", "exposure", "fable_5_1"),
           "diff_lines": ("diff_lines", "diff lines", "lines"),
           "head_date": ("head_date", "head date", "date")}


def read_candidates(path):
    with open(path, encoding="utf-8") as f:
        lines = [l.rstrip("\n") for l in f if l.strip() and not l.startswith("#")]
    if not lines:
        raise InputError("candidates file is empty: %s" % path)
    head = [h.strip().lower() for h in lines[0].split("\t")]
    if "fixture" not in head:
        raise InputError("candidates header lacks a fixture column")
    out = []
    for l in lines[1:]:
        cols = l.split("\t")
        rec = {h: (cols[i].strip() if i < len(cols) else "") for i, h in enumerate(head)}
        c = {"fixture": rec["fixture"]}
        for k, names in ALIASES.items():
            c[k] = next((rec[nm] for nm in names if nm in rec and rec[nm] != ""), None)
        c["contamination_note"] = rec.get("contamination_note") or None
        c["sprint"] = rec.get("sprint") or None
        for k in ("labels", "diff_lines"):
            if c[k] is not None:
                try:
                    c[k] = int(c[k])
                except ValueError:
                    raise InputError("candidates: %s %s is not an integer (%s)" % (c["fixture"], k, c[k]))
        out.append(c)
    return out


def order_candidates(cands, seed):
    elig = [c for c in cands if (c["labels"] or 0) >= 2 and c["exposure"]]
    rng = random.Random("%s:candidates" % seed)
    post = sorted([c for c in elig if c["exposure"] == "post-cutoff" and c["fixture"] != "pr-11"], key=lambda c: c["fixture"])
    rest = sorted([c for c in elig if c["exposure"] != "post-cutoff" and c["fixture"] != "pr-11"], key=lambda c: c["fixture"])
    rng.shuffle(post)
    rng.shuffle(rest)
    tail = [c for c in elig if c["fixture"] == "pr-11"]
    ordered = post + rest + tail
    for i, c in enumerate(ordered, 1):
        c["order"] = i
        c["flagged"] = c["fixture"] == "pr-11"
        c["eligible"] = True
    for c in cands:
        if c not in ordered:
            c.update(order=None, flagged=c["fixture"] == "pr-11", eligible=False)
    return ordered


# ---------------------------------------------------------------- main
def build_profiles(cells):
    by = {}
    for c in cells:
        if not c["valid"] or c["arm"] not in ("a0_bare", "a1_full"):
            continue
        by.setdefault(c["task"], {}).setdefault(c["arm"], []).append(c)
    profiles = []
    for task in sorted(by):
        arms = by[task]
        if "a0_bare" not in arms or "a1_full" not in arms:
            continue
        ids = arms["a1_full"][0]["defect_ids"]
        ds = []
        for d in ids:
            cb = sum(1 for c in arms["a0_bare"] if d in c["caught_ids"])
            cf = sum(1 for c in arms["a1_full"] if d in c["caught_ids"])
            ds.append((cb, len(arms["a0_bare"]), cf, len(arms["a1_full"])))
        profiles.append({"task": task, "defects": ds, "n_bare": len(arms["a0_bare"]), "n_full": len(arms["a1_full"])})
    return profiles


def run(a):
    rows, seen = [], set()
    for p in a.rows:
        for r in common.load_rows(p):
            k = common.cell_key(r)
            if k in seen:
                raise InputError("duplicate cell key across --rows files: %s" % k)
            seen.add(k)
            rows.append(r)
    cells = common.load_cells(rows, a.runs_root, a.validity)
    tf = task_fixture(a.suite_root)
    L = {}
    for t in sorted({c["task"] for c in cells}):
        fx = tf.get(t)
        p = os.path.join(a.fixtures_dir, fx, "head.diff") if fx else None
        if not p or not os.path.isfile(p):
            raise InputError("no fixture head.diff for task %s (fixture %s)" % (t, fx))
        L[t] = diff_lines(p)
    fits = {}
    for arm in ("a1_full", "a0_bare", "a0_bare_fable"):
        xs, ys = [], []
        for c in cells:
            if c["arm"] == arm and c["row"].get("status") == "completed" and c["cost"]:
                xs.append(float(L[c["task"]]))
                ys.append(c["cost"])
        fits[arm] = {"fit": ols(xs, ys), "n": len(xs)}
    if not fits["a1_full"]["fit"] or not fits["a0_bare"]["fit"]:
        raise InputError("cost fits need completed a1_full and a0_bare rows")
    profiles = build_profiles(cells)
    if len(profiles) < 2:
        raise InputError("fewer than two PR profiles with valid a0_bare and a1_full cells")
    arm_fit = {"bare": fit_arm([(d[0], d[1]) for p in profiles for d in p["defects"]]),
               "full": fit_arm([(d[2], d[3]) for p in profiles for d in p["defects"]])}
    ks = {p["task"]: k_for(L[p["task"]], fits["a1_full"]["fit"], fits["a0_bare"]["fit"]) for p in profiles}
    cands = read_candidates(a.candidates)
    ordered = order_candidates(cands, a.seed)
    fxdir = a.fixtures_dir
    for c in cands:
        if c["diff_lines"] is None:
            p = os.path.join(fxdir, c["fixture"], "head.diff")
            c["diff_lines"] = diff_lines(p) if os.path.isfile(p) else None
        if c["diff_lines"] is not None:
            c["k_opus"] = k_for(c["diff_lines"], fits["a1_full"]["fit"], fits["a0_bare"]["fit"])
            ff = fits["a0_bare_fable"]["fit"]
            c["k_fable"] = k_for(c["diff_lines"], fits["a1_full"]["fit"], ff) if ff else None
        else:
            c["k_opus"] = c["k_fable"] = None
    ceiling = a.ceiling if a.ceiling is not None else min(15, len(ordered))
    grid = sorted(set(a.grid))
    evaluated = [n for n in grid if n <= ceiling]
    if ceiling < max(grid) and ceiling not in evaluated and ceiling >= MIN_PRS:
        evaluated.append(ceiling)
    evaluated = sorted(evaluated)
    if not evaluated:
        raise InputError("no grid N at or below the corpus ceiling %d" % ceiling)

    base = Model(profiles, arm_fit, ks)
    per_n, sims = [], {}
    for n in evaluated:
        sim, se_plan = simulate_n(base, n, a.mde, a.studies, a.seed, a.exclusion, a.partial_prob, a.se_method, a.se_boot, "main")
        c = calibrate(sim["null"]["results"], se_plan, a.mde, len(groups_for(n)), a.interval)
        row = summarise(sim, se_plan, c, a.mde, n, a.interval)
        row["cap_usd"], row["cap_raw_usd"] = cap_usd(n)
        per_n.append(row)
        sims[n] = (sim, se_plan, c)
    # round 1: N must give both P(YES | MDE) ≥ 0.80 and P(NO | Δ = 0) ≥ 0.80 under its calibrated c;
    # when none does, nothing is picked: both powers are reported at the ceiling and the lead decides
    powered = [r for r in per_n if r["meets_both"]]
    decision_required = not powered
    chosen = powered[0] if powered else per_n[-1]
    reason = ("smallest N with P(YES | MDE) >= 0.80 and P(NO | 0) >= 0.80" if powered else
              "NO N satisfies P(YES | MDE) >= 0.80 and P(NO | 0) >= 0.80: nothing is chosen; the figures below are "
              "at the largest evaluated N (the ceiling) and the lead decides")
    if chosen["cap_usd"] > a.envelope and not decision_required:
        fits_env = [r for r in per_n if r["cap_usd"] <= a.envelope]
        if fits_env:
            affordable = fits_env[-1]
            reason += "; its cap USD %d exceeds the envelope USD %d → the largest N whose cap fits" % (chosen["cap_usd"], a.envelope)
            chosen = affordable
        else:
            reason += "; no evaluated N fits the envelope"
    exploratory = chosen["power_at_mde"] < 0.50 or chosen["power_no_at_null"] < 0.50
    sens = {}
    if not a.no_sensitivities:
        n = chosen["n"]
        _, se_plan_main, c_main = sims[n]
        variants = [("spread_x0.5", dict(spread=0.5)), ("spread_x1.5", dict(spread=1.5)),
                    ("k_minus_3", dict(k_shift=-3)), ("k_plus_3", dict(k_shift=3)),
                    ("rho_0.3", dict(rho=0.3)), ("rho_0.6", dict(rho=0.6)),
                    ("r_0", dict(r=0.0)), ("r_0.10", dict(r=0.10))]
        for name, kw in variants:
            r = kw.pop("r", a.exclusion)
            m = Model(profiles, arm_fit, ks, **kw)
            sim, se_plan = simulate_n(m, n, a.mde, a.studies, a.seed, r, a.partial_prob, a.se_method, a.se_boot, name)
            at_main = summarise(sim, se_plan_main, c_main, a.mde, n, a.interval)
            c_own = calibrate(sim["null"]["results"], se_plan, a.mde, len(groups_for(n)), a.interval)
            own = summarise(sim, se_plan, c_own, a.mde, n, a.interval)
            sens[name] = {"main_constant": {"power_at_mde": at_main["power_at_mde"], "type1": at_main["type1"],
                                            "power_no_at_null": at_main["power_no_at_null"],
                                            "clipped_share_mde": at_main["clipped_share_mde"]},
                          "recalibrated": {"constant": c_own, "power_at_mde": own["power_at_mde"], "type1": own["type1"],
                                           "power_no_at_null": own["power_no_at_null"]}}
    inputs_sha = hashlib.sha256()
    for p in a.rows:
        inputs_sha.update(common.sha256_file(p).encode())
    for c in sorted(cells, key=lambda c: c["key"]):
        inputs_sha.update((c["key"] + ":" + (common.sha256_file(c["grade_path"]) if c["grade_path"] else "-")).encode())
    inputs_sha.update(common.sha256_file(a.candidates).encode())
    doc = {
        "seed": a.seed, "inputs_sha256": inputs_sha.hexdigest(), "studies": a.studies, "mde": a.mde,
        "exclusion_rate": a.exclusion, "partial_prob": a.partial_prob, "se_method": a.se_method,
        "se_boot": a.se_boot if a.se_method == "bootstrap" else None,
        "grid": grid, "evaluated": evaluated, "corpus_ceiling": ceiling, "envelope_usd": a.envelope,
        "interval": a.interval, "validity": a.validity, "per_n": per_n, "chosen_n": None if decision_required else chosen["n"],
        "reference_n": chosen["n"], "decision_required": decision_required, "chosen_reason": reason,
        "power_no_at_reference": chosen["power_no_at_null"], "groups": groups_for(chosen["n"]),
        "looks": [sum(groups_for(chosen["n"])[:j + 1]) for j in range(len(groups_for(chosen["n"])))],
        "boundary_constant": chosen["constant"], "planned_final_se": chosen["se_plan"],
        "power_at_chosen": chosen["power_at_mde"], "exploratory": exploratory,
        "cap_usd": chosen["cap_usd"], "cap_raw_usd": chosen["cap_raw_usd"], "cap_units_usd": UNIT,
        "cap_contingency": CONTINGENCY, "sensitivities": sens,
        "cost_fits": {arm: {"intercept": v["fit"][0] if v["fit"] else None, "slope": v["fit"][1] if v["fit"] else None,
                            "n": v["n"]} for arm, v in fits.items()},
        "arm_fits": arm_fit, "profiles": [{"task": p["task"], "defects": len(p["defects"]), "n_bare": p["n_bare"],
                                           "n_full": p["n_full"], "diff_lines": L[p["task"]], "k": ks[p["task"]]}
                                          for p in profiles],
        "candidates": [{"fixture": c["fixture"], "sprint": c["sprint"], "head_date": c["head_date"], "defects": c["labels"],
                        "post_cutoff": c["exposure"] == "post-cutoff", "exposure_fable_5_1": c["exposure"],
                        "contamination_note": c["contamination_note"], "diff_lines": c["diff_lines"],
                        "k_opus": c["k_opus"], "k_fable": c["k_fable"], "order": c["order"], "flagged": c["flagged"],
                        "eligible": c["eligible"]}
                       for c in sorted(cands, key=lambda c: (c["order"] is None, c["order"] or 0, c["fixture"]))],
        "selected": [c["fixture"] for c in ordered[:chosen["n"]]],
    }
    return doc


def render_md(doc):
    L = ["# cycle-132 power simulation\n\n",
         "Seed %d; inputs sha256 `%s`; %d studies per N and Δ; MDE %s; exclusion rate %s; partial-group probability %s; SE %s%s.\n\n"
         % (doc["seed"], doc["inputs_sha256"], doc["studies"], f4(doc["mde"]), f4(doc["exclusion_rate"]), f4(doc["partial_prob"]),
            doc["se_method"], (" (%d resamples)" % doc["se_boot"]) if doc["se_boot"] else ""),
         "Interval %s. Selection: the smallest N with P(YES | MDE) ≥ 0.80 and P(NO | 0) ≥ 0.80 under its calibrated constant.\n\n" % doc["interval"],
         "## Per N\n\n| N | groups | constant | SE plan | Δ | YES | NO | SMALL | NEGATIVE | FUTILE | inconclusive | void | clipped | E recall matched | E recall full | cap USD |\n"
         "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"]
    for r in doc["per_n"]:
        for name, lab in (("null", "0"), ("mde", "MDE")):
            e = r[name]
            L.append("| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s%s | %s | %s | %d |\n" % (
                r["n"], "+".join(str(g) for g in r["groups"]), f4(r["constant"]), f4(r["se_plan"]), lab,
                f4(e["yes"]), f4(e["no"]), f4(e["small"]), f4(e["negative"]), f4(e["futile"]), f4(e["inconclusive"]), f4(e["void"]),
                f4(r["clipped_share_" + name]), " (unreliable)" if r["unreliable"] else "",
                f4(r["expected_recall_matched_" + name]), f4(r["expected_recall_full_" + name]), r["cap_usd"]))
    L.append("\n| N | P(YES · MDE) | P(NO · 0) | P(SMALL · 0) | P(NEGATIVE · 0) | P(NEGATIVE · MDE) | type I | both ≥ 0.80 |\n|---|---|---|---|---|---|---|---|\n")
    for r in doc["per_n"]:
        L.append("| %d | %s | %s | %s | %s | %s | %s | %s |\n" % (r["n"], f4(r["power_at_mde"]), f4(r["power_no_at_null"]),
                                                               f4(r["small_at_null"]), f4(r["negative_at_null"]),
                                                               f4(r["negative_at_mde"]), f4(r["type1"]),
                                                               "yes" if r["meets_both"] else "no"))
    L.append("\n" + PARTITION_LEGEND + "\n")
    if doc["decision_required"]:
        L.append("\n**No N chosen — DECISION REQUIRED** (%s). At the reference N = %d: P(YES | MDE) %s, P(NO | 0) %s; groups %s, "
                 "looks %s; calibrated constant %s; planned final SE %s; cap USD %d (envelope USD %d); corpus ceiling %d.\n\n" % (
                     doc["chosen_reason"], doc["reference_n"], f4(doc["power_at_chosen"]), f4(doc["power_no_at_reference"]),
                     doc["groups"], doc["looks"], f4(doc["boundary_constant"]), f4(doc["planned_final_se"]), doc["cap_usd"],
                     doc["envelope_usd"], doc["corpus_ceiling"]))
    else:
        L.append("\n**Chosen N = %d** (%s); groups %s, looks %s; calibrated boundary constant %s; planned final SE %s; "
                 "P(YES | MDE) %s, P(NO | 0) %s; cap USD %d (envelope USD %d)%s; corpus ceiling %d.\n\n" % (
                     doc["chosen_n"], doc["chosen_reason"], doc["groups"], doc["looks"], f4(doc["boundary_constant"]),
                     f4(doc["planned_final_se"]), f4(doc["power_at_chosen"]), f4(doc["power_no_at_reference"]), doc["cap_usd"],
                     doc["envelope_usd"], "; EXPLORATORY (a power < 0.50)" if doc["exploratory"] else "", doc["corpus_ceiling"]))
    if doc["sensitivities"]:
        L.append("## Sensitivities at N = %d\n\n| variant | P(YES · MDE) main c | P(NO · 0) main c | type I main c | recalibrated c | P(YES · MDE) | P(NO · 0) | type I |\n|---|---|---|---|---|---|---|---|\n" % doc["reference_n"])
        for k in sorted(doc["sensitivities"]):
            s = doc["sensitivities"][k]
            m, o = s["main_constant"], s["recalibrated"]
            L.append("| %s | %s | %s | %s | %s | %s | %s | %s |\n" % (k, f4(m["power_at_mde"]), f4(m["power_no_at_null"]), f4(m["type1"]),
                                                                  f4(o["constant"]), f4(o["power_at_mde"]), f4(o["power_no_at_null"]), f4(o["type1"])))
        L.append("\n")
    L.append("## Model inputs\n\n| profile | defects | bare runs | full runs | diff lines | k |\n|---|---|---|---|---|---|\n")
    for p in doc["profiles"]:
        L.append("| %s | %d | %d | %d | %d | %d |\n" % (p["task"], p["defects"], p["n_bare"], p["n_full"], p["diff_lines"], p["k"]))
    L.append("\n| arm | α | β | mean | ρ | never caught | chance | π0 (fixed point) | diag: chance (one pass) | diag: π0 literal |\n|---|---|---|---|---|---|---|---|---|---|\n")
    for arm in ("bare", "full"):
        f = doc["arm_fits"][arm]
        L.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % (arm, f4(f["alpha"]), f4(f["beta"]), f4(f["mean"]), f4(f["rho"]),
                                                                       f4(f["share_never"]), f4(f["chance_never"]), f4(f["pi0"]),
                                                                       f4(f["chance_never_literal"]), f4(f["pi0_literal"])))
    L.append("\n| cost fit | intercept | slope per line | rows |\n|---|---|---|---|\n")
    for arm in sorted(doc["cost_fits"]):
        v = doc["cost_fits"][arm]
        L.append("| %s | %s | %s | %d |\n" % (arm, f4(v["intercept"]), "%.6f" % v["slope"] if v["slope"] is not None else "—", v["n"]))
    L.append("\n## Candidates (seeded order: post-cutoff first, pr-11 last and flagged)\n\n"
             "| order | fixture | sprint | head date | defects | exposure (Fable 5.1) | diff lines | k Opus | k Fable | contamination note |\n"
             "|---|---|---|---|---|---|---|---|---|---|\n")
    for c in doc["candidates"]:
        L.append("| %s | %s%s | %s | %s | %s | %s | %s | %s | %s | %s |\n" % (
            c["order"] if c["order"] else "ineligible", c["fixture"], " (flagged)" if c["flagged"] else "", c["sprint"] or "—",
            c["head_date"] or "—", c["defects"] if c["defects"] is not None else "—", c["exposure_fable_5_1"] or "—",
            c["diff_lines"] if c["diff_lines"] is not None else "—", c["k_opus"] or "—", c["k_fable"] or "—",
            c["contamination_note"] or "—"))
    L.append("\nSelected (first N in order%s): %s.\n" % (", reference N — not chosen" if doc["decision_required"] else "",
                                                      ", ".join(doc["selected"])))
    return "".join(L)


def parse(argv):
    ap = argparse.ArgumentParser(prog="power.py", description="cycle-132 power simulation")
    ap.add_argument("--rows", action="append", required=True)
    ap.add_argument("--runs-root", action="append", default=[])
    ap.add_argument("--labels-dir", help="accepted for the contract; the defect sets come from the rows / grades")
    ap.add_argument("--fixtures-dir", required=True)
    ap.add_argument("--suite-root", action="append", default=[])
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--grid", default="6,8,10,12")
    ap.add_argument("--studies", type=int, default=2000)
    ap.add_argument("--ceiling", type=int)
    ap.add_argument("--envelope", type=int, default=2500)
    ap.add_argument("--mde", type=float, default=0.10)
    ap.add_argument("--exclusion", type=float, default=0.05)
    ap.add_argument("--partial-prob", type=float, default=0.10)
    ap.add_argument("--se-method", choices=("bootstrap", "linear"), default="bootstrap")
    ap.add_argument("--se-boot", type=int, default=200)
    ap.add_argument("--no-sensitivities", action="store_true")
    ap.add_argument("--interval", choices=("t", "percentile"), default="t")
    ap.add_argument("--validity", choices=common.VALIDITY_RULES, default="c132")
    ap.add_argument("--quiet", action="store_true", help="no progress lines on stderr")
    a = ap.parse_args(argv)
    try:
        a.grid = [int(x) for x in a.grid.split(",") if x.strip()]
    except ValueError:
        ap.error("--grid takes comma-separated integers")
    if not a.grid or min(a.grid) < 1 or a.studies < 1:
        ap.error("--grid and --studies must be positive")
    return a


def main(argv=None):
    try:
        a = parse(sys.argv[1:] if argv is None else argv)
    except SystemExit as e:
        return 2 if e.code else 0
    global QUIET
    QUIET = a.quiet
    try:
        doc = run(a)
    except InputError as e:
        sys.stderr.write("power: inputs invalid: %s\n" % e)
        return 1
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "power.json"), "w", encoding="utf-8") as f:
        f.write(dumps(doc))
    with open(os.path.join(a.out, "power.md"), "w", encoding="utf-8") as f:
        f.write(render_md(doc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
