"""stats.py — the cycle-132 statistics (stdlib only, deterministic by seed).

sdd.md §1.4 "Analysis module", §5.3; prd.md FR-5, D16, D17; D-5.1, D-7.4, D-7.9.

A *pair* (the analysis unit, PRD FR-5 a) is a dict
    {"pr": str, "trial": int,
     "full":    {"caught": number, "defects": int, "cost": float, ...},
     "matched": {"caught": number, "defects": int, "cost": float, ...}}
— "full" is side A of a contrast and "matched" side B (the primary contrast is
a1_full − a0_bare_matched; the secondary contrasts reuse the same shape). Both
sides of a pair carry the PR's labelled-defect count.

Functions:
  phi_cdf, phi_inv                 Φ via math.erf; Φ⁻¹ via statistics.NormalDist
  cluster_bootstrap(cells, n, seed, level)   PR-cluster bootstrap of the defect-weighted Δ
                                   (+ the PR-weighted Δ beside)
  linear_se(cells)                 the delta-method SE the bootstrap SE approximates
  reml_lmm(cells)                  y = μ + β·[full] + u_pr + ε on cell recall; REML profile
                                   likelihood on λ = σu²/σe², golden-section on log λ ∈ [−12, 12]
  permutation_test(cells, n, seed, unit)    PR-level (D-7.4) or pair-level sign flips
  gs_boundaries(fractions, alpha, constant, one_sided, grid)
                                   Lan–DeMets O'Brien–Fleming spending, Armitage–McPherson–Rowe
                                   recursion with trapezoid integration
  rci, conditional_power           repeated confidence interval; current-trend CP
  shuffle_within_pr, placebo       the D17 placebo distribution
  defects_per_usd, cost_per_extra_defect    D-7.9 cost reads
  kappa(table)                     Cohen's kappa, k × k

Degenerate inputs return {"status": <name>} (no_valid_pairs, zero_se, ...) instead of numbers.
"""
import functools
import math
import random
import statistics

Z975 = 1.959963984540054
_ND = statistics.NormalDist()


# ---------------------------------------------------------------- normal helpers
def phi_cdf(x):
    if x == math.inf:
        return 1.0
    if x == -math.inf:
        return 0.0
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))


def phi_sf(x):
    """1 − Φ(x), accurate in the upper tail."""
    if x == math.inf:
        return 0.0
    if x == -math.inf:
        return 1.0
    return 0.5 * math.erfc(x / math.sqrt(2.0))


def phi_pdf(x):
    return math.exp(-0.5 * x * x) / math.sqrt(2.0 * math.pi)


def phi_inv(p):
    return _ND.inv_cdf(p)


def _betacf(a, b, x):
    """continued fraction of the regularized incomplete beta (Lentz)"""
    tiny = 1e-300
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 400):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        d = 1.0 / (d if abs(d) > tiny else tiny)
        c = 1.0 + aa / c
        c = c if abs(c) > tiny else tiny
        de = d * c
        h *= de
        if abs(de - 1.0) < 1e-15:
            break
    return h


def betainc(a, b, x):
    """regularized incomplete beta I_x(a, b)"""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    lbt = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b) + a * math.log(x) + b * math.log1p(-x)
    if x < (a + 1.0) / (a + b + 2.0):
        return math.exp(lbt) * _betacf(a, b, x) / a
    return 1.0 - math.exp(lbt) * _betacf(b, a, 1.0 - x) / b


def t_cdf(x, df):
    ib = betainc(df / 2.0, 0.5, df / (df + x * x))
    return 1.0 - 0.5 * ib if x >= 0 else 0.5 * ib


def t_inv(p, df):
    """Student-t quantile by bisection on t_cdf"""
    lo, hi = -1e3, 1e3
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if t_cdf(mid, df) < p:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def quantile(sorted_vals, q):
    """type-7 (linear interpolation) quantile of an already sorted list"""
    n = len(sorted_vals)
    if n == 0:
        return None
    if n == 1:
        return sorted_vals[0]
    h = (n - 1) * q
    lo = int(math.floor(h))
    hi = min(lo + 1, n - 1)
    return sorted_vals[lo] + (h - lo) * (sorted_vals[hi] - sorted_vals[lo])


# ---------------------------------------------------------------- pair aggregation
def _by_pr(cells):
    """{pr: [Σcaught_full, Σcaught_matched, Σdefects, Σ per-pair Δ, n_pairs]} (sorted PR keys)"""
    out = {}
    for c in cells:
        d = c["full"]["defects"]
        if not d:
            continue
        agg = out.setdefault(c["pr"], [0.0, 0.0, 0, 0.0, 0])
        cf, cm = c["full"]["caught"], c["matched"]["caught"]
        agg[0] += cf
        agg[1] += cm
        agg[2] += d
        agg[3] += (cf - cm) / d
        agg[4] += 1
    return {k: out[k] for k in sorted(out)}


def _delta(aggs):
    sf = sm = sd = 0.0
    for a in aggs:
        sf += a[0]
        sm += a[1]
        sd += a[2]
    return (sf - sm) / sd if sd else None


def _pr_weighted(aggs):
    vals = [a[3] / a[4] for a in aggs if a[4]]
    return sum(vals) / len(vals) if vals else None


def linear_se(cells):
    """delta-method SE of the defect-weighted Δ under PR resampling: sqrt(Σ e_p²)/ΣD,
    e_p = (cf_p − cm_p) − Δ·D_p — the quantity the cluster bootstrap SE estimates."""
    aggs = list(_by_pr(cells).values())
    d = _delta(aggs)
    if d is None:
        return None
    sd = sum(a[2] for a in aggs)
    return math.sqrt(sum(((a[0] - a[1]) - d * a[2]) ** 2 for a in aggs)) / sd


def cluster_bootstrap(cells, n=10000, seed=0, level=0.95, keep_draws=False):
    """PR-cluster bootstrap (all of a PR's pairs travel together) of the defect-weighted
    Δ = Σcaught_full/Σdefects − Σcaught_matched/Σdefects. Percentile intervals at `level`
    and at 0.90; SE = the bootstrap SD; the PR-weighted Δ (mean over PRs of the PR's mean
    per-pair Δ) beside with its own percentile interval."""
    by = _by_pr(cells)
    aggs = list(by.values())
    n_pairs = sum(a[4] for a in aggs)
    if not aggs:
        return {"status": "no_valid_pairs", "n_prs": 0, "n_pairs": 0}
    point = _delta(aggs)
    prw = _pr_weighted(aggs)
    rng = random.Random(seed)
    P = len(aggs)
    draws, wdraws = [], []
    for _ in range(n):
        sample = [aggs[rng.randrange(P)] for _ in range(P)]
        draws.append(_delta(sample))
        wdraws.append(_pr_weighted(sample))
    mean = sum(draws) / n
    se = math.sqrt(sum((x - mean) ** 2 for x in draws) / (n - 1)) if n > 1 else 0.0
    wmean = sum(wdraws) / n
    wse = math.sqrt(sum((x - wmean) ** 2 for x in wdraws) / (n - 1)) if n > 1 else 0.0
    sd_sorted, wd_sorted = sorted(draws), sorted(wdraws)
    a = (1.0 - level) / 2.0
    out = {
        "status": "ok",
        "delta": point,
        "se": se,
        "ci95": [quantile(sd_sorted, 0.025), quantile(sd_sorted, 0.975)],
        "ci_level": [quantile(sd_sorted, a), quantile(sd_sorted, 1 - a)],
        "level": level,
        "ci90": [quantile(sd_sorted, 0.05), quantile(sd_sorted, 0.95)],
        "n_prs": P,
        "n_pairs": n_pairs,
        "n_defects": sum(x[2] for x in aggs),
        "caught_full": sum(x[0] for x in aggs),
        "caught_matched": sum(x[1] for x in aggs),
        "recall_full": sum(x[0] for x in aggs) / sum(x[2] for x in aggs),
        "recall_matched": sum(x[1] for x in aggs) / sum(x[2] for x in aggs),
        "resamples": n,
        "pr_weighted": {"delta": prw, "se": wse,
                        "ci95": [quantile(wd_sorted, 0.025), quantile(wd_sorted, 0.975)],
                        "ci90": [quantile(wd_sorted, 0.05), quantile(wd_sorted, 0.95)]},
    }
    # DIAGNOSTIC, not the pre-registered interval: Δ̂ ± t_{P−1, 0.975}·SE·√(P/(P−1)) — the
    # percentile interval undercovers at 6–12 PRs (placebo on synthetic nulls; report s1-d)
    if P >= 2:
        tq = t_inv(0.975, P - 1)
        half = tq * se * math.sqrt(P / (P - 1.0))
        out["ci95_t"] = [point - half, point + half]
    else:
        out["ci95_t"] = None
    if keep_draws or n <= 1000:
        out["_draws"] = draws
    if se == 0.0:
        out["status"] = "zero_se"
    return out


# ---------------------------------------------------------------- REML LMM
def _reml_obs(cells):
    groups = {}
    for c in cells:
        d = c["full"]["defects"]
        if not d:
            continue
        g = groups.setdefault(c["pr"], [])
        g.append((1.0, c["full"]["caught"] / d))
        g.append((0.0, c["matched"]["caught"] / d))
    return {k: groups[k] for k in sorted(groups)}


def _reml_parts(groups, lam):
    """X'H⁻¹X (2×2 with X = [1, x]), X'H⁻¹y, y'H⁻¹y and Σ log(1 + n_p λ), H = I + λZZ'."""
    a11 = a12 = a22 = b1 = b2 = yy = logdet = 0.0
    for obs in groups.values():
        n = len(obs)
        sx = sum(x for x, _ in obs)
        sy = sum(y for _, y in obs)
        sxx = sum(x * x for x, _ in obs)
        sxy = sum(x * y for x, y in obs)
        syy = sum(y * y for _, y in obs)
        w = lam / (1.0 + n * lam)
        a11 += n - w * n * n
        a12 += sx - w * n * sx
        a22 += sxx - w * sx * sx
        b1 += sy - w * n * sy
        b2 += sxy - w * sx * sy
        yy += syy - w * sy * sy
        logdet += math.log1p(n * lam)
    return a11, a12, a22, b1, b2, yy, logdet


def _reml_fit(groups, lam, N):
    a11, a12, a22, b1, b2, yy, logdet = _reml_parts(groups, lam)
    det = a11 * a22 - a12 * a12
    if det <= 0:
        return None
    i11, i12, i22 = a22 / det, -a12 / det, a11 / det
    mu = i11 * b1 + i12 * b2
    beta = i12 * b1 + i22 * b2
    rss = yy - (mu * b1 + beta * b2)
    rss = max(rss, 1e-300)
    ll = -0.5 * ((N - 2) * math.log(rss) + logdet + math.log(det))
    sigma_e2 = rss / (N - 2)
    return {"ll": ll, "mu": mu, "beta": beta, "sigma_e2": sigma_e2, "var_beta": sigma_e2 * i22}


def reml_lmm(cells, lo=-12.0, hi=12.0):
    """REML fit of y_{p,t,a} = μ + β·[a = full] + u_p + ε on cell recall. The profile REML
    log-likelihood in θ = log λ is scanned on a 0.2 grid over [lo, hi] and refined by
    golden-section search in the best grid bracket; GLS β with a Wald 95 % interval;
    boundary true when θ̂ sits at an edge of [lo, hi]."""
    groups = _reml_obs(cells)
    N = sum(len(g) for g in groups.values())
    if not groups:
        return {"status": "no_valid_pairs"}
    if len(groups) < 2 or N <= 3:
        return {"status": "too_few_prs", "n_groups": len(groups), "n_obs": N}

    def f(theta):
        r = _reml_fit(groups, math.exp(theta), N)
        return -math.inf if r is None else r["ll"]

    steps = int(round((hi - lo) / 0.2))
    grid = [lo + i * (hi - lo) / steps for i in range(steps + 1)]
    vals = [f(t) for t in grid]
    best = max(range(len(grid)), key=lambda i: (vals[i], -i))
    a = grid[max(best - 1, 0)]
    b = grid[min(best + 1, len(grid) - 1)]
    g = (math.sqrt(5.0) - 1.0) / 2.0
    c, d = b - g * (b - a), a + g * (b - a)
    fc, fd = f(c), f(d)
    for _ in range(300):
        if b - a < 1e-12:
            break
        if fc >= fd:
            b, d, fd = d, c, fc
            c = b - g * (b - a)
            fc = f(c)
        else:
            a, c, fc = c, d, fd
            d = a + g * (b - a)
            fd = f(d)
    theta = (a + b) / 2.0
    # an edge optimum: compare against the edge itself
    for edge in (lo, hi):
        if f(edge) >= f(theta):
            theta = edge
    boundary = abs(theta - lo) < 1e-3 or abs(theta - hi) < 1e-3
    lam = math.exp(theta)
    r = _reml_fit(groups, lam, N)
    se = math.sqrt(r["var_beta"]) if r["var_beta"] > 0 else 0.0
    out = {
        "status": "reml_boundary" if boundary else "ok",
        "beta": r["beta"],
        "mu": r["mu"],
        "se": se,
        "ci95": [r["beta"] - Z975 * se, r["beta"] + Z975 * se],
        "lambda": lam,
        "log_lambda": theta,
        "sigma_e2": r["sigma_e2"],
        "sigma_u2": lam * r["sigma_e2"],
        "sigma_e": math.sqrt(r["sigma_e2"]),
        "sigma_u": math.sqrt(lam * r["sigma_e2"]),
        "boundary": boundary,
        "n_obs": N,
        "n_groups": len(groups),
        "reml_loglik": r["ll"],
    }
    return out


# ---------------------------------------------------------------- permutation
def permutation_test(cells, n=10000, seed=0, unit="pr"):
    """Two-sided sign-flip permutation p on |Δ|. unit "pr": every cell of a PR swaps arm
    labels together (D-7.4); "pair": each PR × trial pair swaps on its own (sensitivity).
    Exact enumeration when 2^units ≤ n, else n Monte-Carlo flips with p = (b + 1)/(n + 1)."""
    if unit not in ("pr", "pair"):
        raise ValueError("unit must be pr or pair")
    units = {}
    total_d = 0
    for c in cells:
        d = c["full"]["defects"]
        if not d:
            continue
        key = c["pr"] if unit == "pr" else (c["pr"], c["trial"])
        units[key] = units.get(key, 0.0) + (c["full"]["caught"] - c["matched"]["caught"])
        total_d += d
    if not units:
        return {"status": "no_valid_pairs"}
    diffs = [units[k] for k in sorted(units, key=str)]
    obs = abs(sum(diffs)) / total_d
    U = len(diffs)
    tol = 1e-12
    if (1 << U) <= n:
        cnt = 0
        for m in range(1 << U):
            s = 0.0
            for i, x in enumerate(diffs):
                s += x if (m >> i) & 1 else -x
            cnt += abs(s) / total_d >= obs - tol
        return {"status": "ok", "p": cnt / float(1 << U), "n": 1 << U, "exact": True,
                "unit": unit, "n_units": U, "delta": sum(diffs) / total_d}
    rng = random.Random(seed)
    cnt = 0
    for _ in range(n):
        s = 0.0
        for x in diffs:
            s += x if rng.random() < 0.5 else -x
        cnt += abs(s) / total_d >= obs - tol
    return {"status": "ok", "p": (cnt + 1) / float(n + 1), "n": n, "exact": False,
            "unit": unit, "n_units": U, "delta": sum(diffs) / total_d}


# ---------------------------------------------------------------- group-sequential boundaries
def obf_spending(t, alpha):
    """Lan–DeMets O'Brien–Fleming-type spending α*(t) = 2 − 2Φ(z_{α/2}/√t) for a one-sided
    level α (gsDesign sfLDOF). The two-sided symmetric design spends 2·α*(t) with the
    per-tail level α/2 (see _gs_cached)."""
    if t <= 0:
        return 0.0
    t = min(t, 1.0)
    return 2.0 * phi_sf(phi_inv(1.0 - alpha / 2.0) / math.sqrt(t))


def _grid(lo, hi, m):
    h = (hi - lo) / (m - 1)
    pts = [lo + i * h for i in range(m)]
    w = [h] * m
    w[0] = w[-1] = h / 2.0
    return pts, w


@functools.lru_cache(maxsize=4096)
def _gs_cached(fractions, alpha, one_sided, grid):
    K = len(fractions)
    bounds = []
    prev_t = 0.0
    prev_spent = 0.0
    dens = None          # (points, weights·density) on the S = Z√t scale at the previous look
    for k, t in enumerate(fractions):
        t = min(max(t, 0.0), 1.0)
        # two-sided symmetric: α/2 per tail, each tail on the OBF function of level α/2
        # (Jennison & Turnbull 2000 §7.2; gsDesign test.type 2) — this reproduces the
        # published 3.710 / 2.511 / 1.993 at (1/3, 2/3, 1) for α = 0.05
        spent = obf_spending(t, alpha) if one_sided else 2.0 * obf_spending(t, alpha / 2.0)
        inc = spent - prev_spent
        dt = t - prev_t
        if dt <= 1e-12 or inc <= 0.0:
            bounds.append(math.inf)
            # no new information: the continuation density is unchanged
            continue
        sdt = math.sqrt(dt)
        if dens is None:
            # first look: the fixed-sample quantile
            # the upper-tail quantile from the tail mass itself (1 − inc rounds to 1 at small t)
            tail = inc if one_sided else inc / 2.0
            b = -phi_inv(tail) if tail > 0.0 else math.inf
            if math.isinf(b):
                bounds.append(math.inf)
                continue
        else:
            pts, wd = dens

            def cross(c):
                tot = 0.0
                for u, w in zip(pts, wd):
                    p = phi_sf((c - u) / sdt)
                    if not one_sided:
                        p += phi_cdf((-c - u) / sdt)
                    tot += w * p
                return tot

            lo_c, hi_c = 0.0, 40.0 * math.sqrt(t)
            for _ in range(80):
                mid = (lo_c + hi_c) / 2.0
                if cross(mid) > inc:
                    lo_c = mid
                else:
                    hi_c = mid
            b = ((lo_c + hi_c) / 2.0) / math.sqrt(t)
        bounds.append(b)
        if k < K - 1:
            c = b * math.sqrt(t)
            lower = -c if not one_sided else -8.0 * math.sqrt(t) - 1.0
            pts_new, w_new = _grid(lower, c, grid)
            if dens is None:
                st = math.sqrt(t)
                vals = [phi_pdf(s / st) / st for s in pts_new]
            else:
                pts, wd = dens
                inv = 1.0 / sdt
                vals = []
                for s in pts_new:
                    acc = 0.0
                    for u, w in zip(pts, wd):
                        z = (s - u) * inv
                        acc += w * math.exp(-0.5 * z * z)
                    vals.append(acc * inv / math.sqrt(2.0 * math.pi))
            dens = (pts_new, [w * v for w, v in zip(w_new, vals)])
        prev_t, prev_spent = t, spent
    return tuple(bounds)


def gs_boundaries(fractions, alpha=0.05, constant=1.0, one_sided=False, grid=2000):
    """Boundaries b_k on the Z scale at information fractions t_1 < … ≤ 1 under Lan–DeMets
    OBF spending; two-sided symmetric (|Z| ≥ b) unless one_sided (Z ≥ b). Each boundary is
    multiplied by `constant` (the simulation-calibrated inflation, PRD D16). A look that adds
    no information (t_k ≤ t_{k−1}) spends nothing: its boundary is inf."""
    key = tuple(round(float(t), 12) for t in fractions)
    raw = _gs_cached(key, float(alpha), bool(one_sided), int(grid))
    return [b * constant if not math.isinf(b) else math.inf for b in raw]


def rci(delta, se, boundary):
    """repeated confidence interval Δ̂ ± b_k·SE"""
    return (delta - boundary * se, delta + boundary * se)


def conditional_power(z_k, t_k, b_final, drift=None):
    """P(Z(1) ≥ b_final | Z(t_k) = z_k) for Brownian motion with drift θ per unit information
    (B(t) = Z(t)√t); θ defaults to the current trend z_k/√t_k."""
    if t_k >= 1.0:
        return 1.0 if z_k >= b_final else 0.0
    if math.isinf(b_final):
        return 0.0
    theta = z_k / math.sqrt(t_k) if drift is None else drift
    bt = z_k * math.sqrt(t_k)
    return phi_sf((b_final - bt - theta * (1.0 - t_k)) / math.sqrt(1.0 - t_k))


# ---------------------------------------------------------------- placebo (D17)
def shuffle_within_pr(cells, rng):
    """Permute the arm labels within each PR: the PR's 2·n_pairs cell results are shuffled
    over its full and matched slots (trial order kept); PR totals are preserved."""
    by = {}
    for c in cells:
        by.setdefault(c["pr"], []).append(c)
    out = []
    for pr in sorted(by):
        pcs = sorted(by[pr], key=lambda c: c["trial"])
        pool = [c["full"] for c in pcs] + [c["matched"] for c in pcs]
        rng.shuffle(pool)
        m = len(pcs)
        for i, c in enumerate(pcs):
            out.append({"pr": pr, "trial": c["trial"], "full": pool[i], "matched": pool[m + i]})
    return out


def placebo(cells, seed=0, n=200, boot=1000, statistic=None):
    """n within-PR arm-label shuffles, each through the primary read (`statistic`, default
    cluster_bootstrap with `boot` resamples — 1,000 pre-registered for speed). Pass when
    ≤ 8 % of the 95 % intervals exclude 0 and the mean |Δ| < 0.03 (PRD D17)."""
    if statistic is None:
        def statistic(cs, s):
            return cluster_bootstrap(cs, n=boot, seed=s)
    rng = random.Random(seed)
    deltas, excl, excl_t, statuses = [], 0, 0, {}
    for _ in range(n):
        shuffled = shuffle_within_pr(cells, rng)
        r = statistic(shuffled, rng.randrange(1 << 31))
        if r.get("status") not in ("ok", "zero_se"):
            statuses[r.get("status")] = statuses.get(r.get("status"), 0) + 1
            continue
        deltas.append(r["delta"])
        lo, hi = r["ci95"]
        if lo > 0 or hi < 0:
            excl += 1
        ct = r.get("ci95_t")
        if ct and (ct[0] > 0 or ct[1] < 0):
            excl_t += 1
    if not deltas:
        return {"status": "no_valid_pairs", "n": n, "boot": boot}
    share = excl / float(len(deltas))
    mabs = sum(abs(d) for d in deltas) / len(deltas)
    ds = sorted(deltas)
    return {
        "status": "ok", "n": n, "boot": boot, "seed": seed, "n_valid": len(deltas),
        "share_excluding_zero": share, "mean_abs_delta": mabs, "mean_delta": sum(deltas) / len(deltas),
        "delta_q05": quantile(ds, 0.05), "delta_q50": quantile(ds, 0.5), "delta_q95": quantile(ds, 0.95),
        "band": {"max_share_excluding_zero": 0.08, "max_mean_abs_delta": 0.03},
        "pass": share <= 0.08 and mabs < 0.03, "degenerate": statuses,
        "diagnostic_share_excluding_zero_t": excl_t / float(len(deltas)),
    }


# ---------------------------------------------------------------- cost reads (D-7.9)
def defects_per_usd(cells, n=10000, seed=0):
    """Σcaught/Σcost per side over the pairs, with PR-cluster bootstrap percentile intervals."""
    by = {}
    for c in cells:
        a = by.setdefault(c["pr"], [0.0, 0.0, 0.0, 0.0])
        a[0] += c["full"]["caught"]
        a[1] += c["full"].get("cost") or 0.0
        a[2] += c["matched"]["caught"]
        a[3] += c["matched"].get("cost") or 0.0
    if not by:
        return {"status": "no_valid_pairs"}
    aggs = [by[k] for k in sorted(by)]

    def ratio(sample, i):
        cost = sum(x[i + 1] for x in sample)
        return sum(x[i] for x in sample) / cost if cost > 0 else None

    out = {"status": "ok"}
    for name, i in (("full", 0), ("matched", 2)):
        v = ratio(aggs, i)
        if v is None:
            out[name] = {"status": "zero_cost"}
            continue
        rng = random.Random(seed + i)
        P = len(aggs)
        draws = []
        for _ in range(n):
            r = ratio([aggs[rng.randrange(P)] for _ in range(P)], i)
            if r is not None:
                draws.append(r)
        draws.sort()
        out[name] = {"value": v, "ci95": [quantile(draws, 0.025), quantile(draws, 0.975)],
                     "caught": sum(x[i] for x in aggs), "cost_usd": sum(x[i + 1] for x in aggs)}
    return out


def cost_per_extra_defect(cells, baseline="matched", spend="valid", all_spend=None):
    """(cost_full − cost_baseline) / (caught_full − caught_baseline) over the pairs.
    baseline "matched" (the matched cell) or "session1" (the matched cell's BARE-1 session:
    pair["matched"]["session1"] = {caught, cost}); spend "valid" (the pairs' own costs) or
    "all" (all_spend = {"full": USD, "matched": USD}: every dollar of every attempt per arm,
    failed and excluded runs included — the headline, PRD FR-5 h)."""
    cf = cb = cost_f = cost_b = 0.0
    for c in cells:
        cf += c["full"]["caught"]
        cost_f += c["full"].get("cost") or 0.0
        if baseline == "session1":
            s1 = c["matched"].get("session1")
            if not s1 or s1.get("caught") is None:
                return {"status": "no_session1"}
            cb += s1["caught"]
            cost_b += s1.get("cost") or 0.0
        else:
            cb += c["matched"]["caught"]
            cost_b += c["matched"].get("cost") or 0.0
    if not cells:
        return {"status": "no_valid_pairs"}
    if spend == "all":
        if not all_spend:
            return {"status": "no_all_spend"}
        cost_f, cost_b = all_spend["full"], all_spend["matched"]
    extra = cf - cb
    if extra <= 0:
        return {"status": "no_extra_defects", "extra_defects": extra,
                "cost_full": cost_f, "cost_baseline": cost_b}
    return {"status": "ok", "value": (cost_f - cost_b) / extra, "extra_defects": extra,
            "cost_full": cost_f, "cost_baseline": cost_b, "baseline": baseline, "spend": spend}


# ---------------------------------------------------------------- agreement
def kappa(table):
    """Cohen's kappa of a k × k confusion table (rows rater 1, columns rater 2); None when
    undefined (no items, or chance agreement 1)."""
    n = float(sum(sum(r) for r in table))
    if n == 0:
        return None
    k = len(table)
    po = sum(table[i][i] for i in range(k)) / n
    rows = [sum(r) for r in table]
    cols = [sum(table[i][j] for i in range(k)) for j in range(k)]
    pe = sum(rows[i] * cols[i] for i in range(k)) / (n * n)
    if abs(1.0 - pe) < 1e-15:
        return None
    return (po - pe) / (1.0 - pe)
