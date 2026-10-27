"""reads.py — the cycle-132 pre-registered reads (CLI: reads-c132.py).

Usage:
  reads-c132.py --rows F --results-root DIR [--results-root DIR …] --inputs INPUTS.json
                [--registration REGISTRATION.json] (--look N | --final | --placebo) --out DIR
                [--power power.json] [--sensitivity-grades DIR] [--judge DIR]
                [--arm-a ARM] [--arm-b ARM] [--seed N] [--name STEM] [--placebo-n 200]
                [--interval t|percentile] [--validity c132|c131]
  reads-c132.py --rows F --results-root DIR … --make-inputs --out DIR
                [--pin SHA] [--label-set v2] [--planned FILE] [--suite-root DIR …]

Modes (sdd.md §5.2, §5.3; prd.md FR-5, D16, D17):
  --look N     the group-sequential look after group N of the registration: per look j ≤ N the
               pairs of groups 1 … j, the cluster-bootstrap Δ̂ and SE, the information fraction
               t_j = SE²_planned-final / SE²_j (capped at 1, made non-decreasing; the registration's
               last look uses t = 1), the YES boundary (two-sided α 0.05 OBF) and the NO boundary
               (one-sided α 0.025 OBF on z_no = (MDE − Δ̂)/SE), both × boundary_constant, the
               conditional powers and the decision under the ordered table of PARTITION_LEGEND
               (round 3: NEGATIVE / YES / SMALL / NO / INCONCLUSIVE / FUTILE / CONTINUE). No decision with fewer than 6
               valid PRs or 30 labelled defects (CONTINUE with the reason).
  --final      the pre-registered reads (primary Δ with 95 % / 90 % intervals and the RCI at the
               stopping look, PR-weighted Δ, REML, PR-level permutation, defects per USD, cost per
               extra defect on valid pairs and all spend, review-only contrast, pipeline-independent
               read, matched-Fable contrast, dollar-matching table, the positive control (D-7.10:
               a1_full_openmount − a1_full on G1, saturated PRs exempt; pass / control not exercised /
               void), missingness with the two bounds, the 25 % guard), then the sensitivities in the
               registration's order.
  --placebo    200 seeded within-PR arm-label shuffles through the primary read (1,000 resamples
               each): pass when |mean Δ| < 0.03 (bias) and ≤ 8 % of the 95 % intervals exclude 0
               (calibration); mean |Δ| and the other interval's share are diagnostics (round 1).
               --registration is optional here (the Phase 0 placebo precedes it; the output says
               "unregistered"); --arm-a/--arm-b pick the contrast (default a1_full, a0_bare_matched).
  --interval t (default; round 1) the primary 95 % / 90 % intervals are the cluster-t intervals
               Δ̂ ± t_{P−1, 0.975 | 0.95}·SE_boot and the group-sequential boundaries move to the t
               scale (same upper-tail mass, df = valid PRs − 1) for the crossing rule and the RCI; the
               percentile interval is printed beside as a diagnostic. `percentile` swaps the roles
               (normal-scale boundaries). Conditional power stays on the normal Brownian model.
  --validity c132 (default; sdd.md §5.2) or c131 (no oracle_exposed clause — the Phase 0 placebo
               on the 63 existing rows, whose cycle-130 a1_full runs all ran under the open mount)
  Sensitivity "class9_nonrepo_egress_reincluded" (round 4; PREREGISTRATION §12 addendum, after
               "degraded and contaminated rows excluded"): cells whose only invalidity is contaminated
               {pattern: network_egress, repo_named: false} count as valid (recall as graded); the
               re-included cells are counted per arm and group.
  --sensitivity-grades DIR  re-grades for the label-set sensitivities:
               DIR/<c131|v1>/<batch>/<arm>/<task>-t<n>/grade.json (absent → "not_provided")
  --judge DIR  the judge's result.json (judge_agree.py): judge-corrected figures and the
               judge-confirmed strays (absent → "not_provided")
  --make-inputs  write DIR/INPUTS.json for the current rows and run dirs (rows sha256, every
               grade.json sha256, pin, label set, planned cells, matched-cell session membership,
               task → fixture from the suite roots' task.yaml) — the lead reviews and freezes it.

Inputs are validated before any output (D-7.5): the rows file hash, every grade.json hash, the pin,
the label set, the cells and each matched cell's session membership must equal INPUTS.json, and every
row's registration_sha256 must equal sha256(REGISTRATION.json). Registration keys read: seed,
boundary_constant, groups ([[task…]…]; look j follows group j), mde (default 0.10), planned_final_se
or power_json (a path to power.json holding planned_final_se; relative to the registration's
directory, else the cwd), sensitivities (optional order), arms (unused for routing here).

Outputs (DIR/<stem>.json + DIR/<stem>.md, stem default "reads"): sorted keys, floats as %.4f,
no timestamps, no absolute paths, the input hashes printed — byte-identical across runs.
Degenerate inputs print a named status instead of a number: no_valid_pairs, zero_se, too_few_prs,
reml_boundary.

Exit: 0 written; 1 inputs invalid (nothing written); 2 usage.
"""
import argparse
import json
import math
import os
import re
import sys

from c132 import common, stats
from c132.common import InputError

PRIMARY_A, PRIMARY_B = "a1_full", "a0_bare_matched"
FABLE_B = "a0_bare_fable_matched"
REVIEW_ONLY = "a1_review_only"
MIN_PRS, MIN_DEFECTS = 6, 30
DEFAULT_SEED = 20261021
DEFAULT_SENSITIVITIES = [
    "frozen_c131_labels", "v1_labels", "judge_corrected", "judge_strays_as_defects",
    "exact_dollar_trim", "pair_level_permutation", "ci90", "leave_one_pr_out", "pr11_in_out",
    "degraded_contaminated_excluded", "class9_nonrepo_egress_reincluded", "pr_weighted", "matched_fable_contrast",
]
BOOT = 10000
INTERVAL = "t"          # --interval (round 1: cluster-t primary, percentile beside)
VALIDITY = "c132"       # --validity
PLACEBO_N, PLACEBO_BOOT = 200, 1000
DOLLAR_TOL = 0.25
GUARD = 0.25


# ---------------------------------------------------------------- deterministic output
def _fmt(x):
    if isinstance(x, bool) or x is None:
        return json.dumps(x)
    if isinstance(x, int):
        return str(x)
    if isinstance(x, float):
        if math.isnan(x):
            return "null"
        if math.isinf(x):
            return '"inf"' if x > 0 else '"-inf"'
        s = "%.4f" % x
        return "0.0000" if s == "-0.0000" else s
    if isinstance(x, str):
        return json.dumps(x, ensure_ascii=False)
    if isinstance(x, (list, tuple)):
        return "[" + ", ".join(_fmt(v) for v in x) + "]"
    if isinstance(x, dict):
        return "{" + ", ".join(json.dumps(str(k)) + ": " + _fmt(x[k]) for k in sorted(x, key=str)) + "}"
    raise TypeError("unserialisable %r" % type(x))


def dumps(obj):
    return _fmt(_clean(obj)) + "\n"


def _clean(o):
    if isinstance(o, dict):
        return {k: _clean(v) for k, v in o.items() if not str(k).startswith("_")}
    if isinstance(o, (list, tuple)):
        return [_clean(v) for v in o]
    return o


def f4(x):
    if x is None:
        return "—"
    if isinstance(x, float) and math.isinf(x):
        return "inf"
    if isinstance(x, (int, float)) and not isinstance(x, bool):
        s = "%.4f" % x
        return "0.0000" if s == "-0.0000" else s
    return str(x)


def iv(pair):
    return "—" if not pair or pair[0] is None else "[%s, %s]" % (f4(pair[0]), f4(pair[1]))


# ---------------------------------------------------------------- reads
def primary_read(pairs, seed, n=BOOT, min_prs=MIN_PRS):
    if not pairs:
        return {"status": "no_valid_pairs", "n_prs": 0, "n_pairs": 0}
    b = stats.cluster_bootstrap(pairs, n=n, seed=seed, interval=INTERVAL)
    if b["n_prs"] < min_prs:
        return {"status": "too_few_prs", "n_prs": b["n_prs"], "n_pairs": b["n_pairs"],
                "n_defects": b["n_defects"], "min_prs": min_prs}
    keep = ("status", "delta", "se", "ci95", "ci90", "ci95_t", "ci90_t", "ci95_percentile", "ci90_percentile",
            "interval", "df", "n_prs", "n_pairs", "n_defects",
            "caught_full", "caught_matched", "recall_full", "recall_matched", "resamples", "pr_weighted")
    out = {k: b[k] for k in keep if k in b}
    if b["status"] == "zero_se":
        return {"status": "zero_se", "n_prs": b["n_prs"], "n_pairs": b["n_pairs"], "n_defects": b["n_defects"]}
    return out


def labelled_defects(pairs):
    seen = {}
    for p in pairs:
        seen[p["pr"]] = p["full"]["defects"]
    return sum(seen.values()), len(seen)


OUTCOMES = ("NEGATIVE", "YES", "SMALL", "NO", "INCONCLUSIVE", "FUTILE", "CONTINUE")
PARTITION_LEGEND = (
    "Decision table (ordered, exhaustive; round 3). The YES boundary is two-sided: "
    "\"z_yes crosses\" means |z_yes| ≥ b_yes. "
    "1. z_yes crosses and Δ̂ < 0 → NEGATIVE. "
    "2. z_yes crosses and Δ̂ > 0 and z_no < b_no and RCI upper ≥ MDE → YES. "
    "3. z_yes crosses and Δ̂ ≥ 0 and (z_no ≥ b_no or RCI upper < MDE) → SMALL. "
    "4. z_yes does not cross and z_no ≥ b_no → NO. "
    "5. neither crossed, final look → INCONCLUSIVE. "
    "6. neither crossed, interim look: both conditional powers < 0.20 → FUTILE (non-binding), else CONTINUE.")


def decide(delta, z_yes, b_yes, z_no, b_no, rci_hi, mde, cp_yes, cp_no, final):
    """the ordered decision table of PARTITION_LEGEND (round 3; Flatline SKP-003/SKP-006). `delta`
    is the signed Δ̂; z_yes = Δ̂/SE crosses its two-sided boundary when |z_yes| ≥ b_yes."""
    crossed_yes = abs(z_yes) >= b_yes
    crossed_no = z_no >= b_no
    if crossed_yes and delta < 0:
        return "NEGATIVE"
    if crossed_yes and delta > 0 and not crossed_no and rci_hi >= mde:
        return "YES"
    if crossed_yes:          # Δ̂ ≥ 0 and (z_no crossed or the RCI lies below the MDE)
        return "SMALL"
    if crossed_no:
        return "NO"
    if final:
        return "INCONCLUSIVE"
    if cp_yes < 0.20 and cp_no < 0.20:
        return "FUTILE"
    return "CONTINUE"


def look_table(cells, reg, upto, seed, planned_se, arm_a=PRIMARY_A, arm_b=PRIMARY_B, n=BOOT):
    groups = reg.get("groups") or []
    if upto < 1 or upto > len(groups):
        raise InputError("--look %d outside the registration's %d group(s)" % (upto, len(groups)))
    c = float(reg.get("boundary_constant", 1.0))
    mde = float(reg.get("mde", 0.10))
    K = len(groups)
    rows, ts = [], []
    for j in range(1, upto + 1):
        tasks = set(t for g in groups[:j] for t in g)
        pairs, _ = common.make_pairs(cells, arm_a, arm_b, tasks=tasks)
        d_total, n_prs = labelled_defects(pairs)
        rec = {"look": j, "n_prs": n_prs, "n_pairs": len(pairs), "n_defects": d_total,
               "final_look": j == K}
        if not pairs:
            rec.update(status="no_valid_pairs", decision="CONTINUE", reason="no valid pairs")
            rows.append(rec)
            ts.append(ts[-1] if ts else 0.0)
            continue
        b = stats.cluster_bootstrap(pairs, n=n, seed=seed, interval=INTERVAL)
        rec.update(delta=b["delta"], se=b["se"])
        if b["se"] <= 0:
            rec.update(status="zero_se", decision="CONTINUE", reason="zero SE")
            rows.append(rec)
            ts.append(ts[-1] if ts else 0.0)
            continue
        t_obs = (planned_se ** 2) / (b["se"] ** 2)
        t = 1.0 if j == K else min(1.0, t_obs)
        if ts and t < ts[-1]:
            t = ts[-1]
        ts.append(t)
        rec["t_observed"] = t_obs
        rec["t"] = t
        rows.append(rec)
    # boundaries for the realised fractions (a look without data reuses the previous fraction)
    for j, rec in enumerate(rows, 1):
        if "t" not in rec:
            continue
        fr = ts[:j]
        b_yes_z = stats.gs_boundaries(fr, alpha=0.05, constant=c)[-1]
        b_no_z = stats.gs_boundaries(fr, alpha=0.025, constant=c, one_sided=True)[-1]
        # --interval t: the boundaries move to the cluster-t scale with df = valid PRs − 1 (the
        # same upper-tail mass), so the crossing rule and the RCI match the primary interval
        df = max(rec["n_prs"] - 1, 1)
        b_yes = stats.t_boundary(b_yes_z, df) if INTERVAL == "t" else b_yes_z
        b_no = stats.t_boundary(b_no_z, df) if INTERVAL == "t" else b_no_z
        fr_final = fr if fr[-1] >= 1.0 else fr + [1.0]
        b_yes_f = stats.gs_boundaries(fr_final, alpha=0.05, constant=c)[-1]
        b_no_f = stats.gs_boundaries(fr_final, alpha=0.025, constant=c, one_sided=True)[-1]
        z_yes = rec["delta"] / rec["se"]
        z_no = (mde - rec["delta"]) / rec["se"]
        cp_yes = stats.conditional_power(z_yes, rec["t"], b_yes_f)
        cp_no = stats.conditional_power(z_no, rec["t"], b_no_f)
        lo, hi = stats.rci(rec["delta"], rec["se"], b_yes) if not math.isinf(b_yes) else (None, None)
        rec.update(z_yes=z_yes, b_yes=b_yes, z_no=z_no, b_no=b_no, cp_yes=cp_yes, cp_no=cp_no,
                   b_yes_normal=b_yes_z, b_no_normal=b_no_z, df=df, interval=INTERVAL,
                   rci=[lo, hi], b_yes_final=b_yes_f, b_no_final=b_no_f, status="ok")
        if rec["n_prs"] < MIN_PRS or rec["n_defects"] < MIN_DEFECTS:
            rec["decision"] = "CONTINUE"
            rec["reason"] = "minimum information not reached (%d valid PRs < %d or %d labelled defects < %d)" % (
                rec["n_prs"], MIN_PRS, rec["n_defects"], MIN_DEFECTS)
        else:
            rec["decision"] = decide(rec["delta"], z_yes, b_yes, z_no, b_no, hi if hi is not None else math.inf, mde,
                                     cp_yes, cp_no, rec["final_look"])
            rec["reason"] = None
    return rows


OPEN_MOUNT = "a1_full_openmount"
PC_EXPECTED = 0.067     # cycle-131 R1 on pr-17 (D-7.10)
PC_SATURATED = 0.9


def positive_control(cells, reg, seed):
    """D-7.10: a1_full_openmount − a1_full on G1's pairs, PRs whose closed-mount recall exceeds 0.9
    exempt (no headroom); pass when Δ̂ > 0 and the oracle detector shows exposure in ≥ 1 open run;
    no exposure in any open run → "control not exercised"; Δ̂ < 0 with exposure → "void" (every
    other read is then reported void); the 90 % interval and the expected effect beside."""
    opens = [c for c in cells if c["arm"] == OPEN_MOUNT]
    if not opens:
        return {"status": "not_run"}
    groups = reg.get("groups") or []
    g1 = set(groups[0]) if groups else {c["task"] for c in opens}
    closed = {}
    for c in cells:
        if c["arm"] == PRIMARY_A and c["valid"] and c["task"] in g1:
            a = closed.setdefault(c["task"], [0, 0])
            a[0] += c["caught"]
            a[1] += c["defects"]
    saturated = sorted(t for t, (cg, d) in closed.items() if d and cg / float(d) > PC_SATURATED)
    tasks = g1 - set(saturated)
    pairs, _ = common.make_pairs(cells, OPEN_MOUNT, PRIMARY_A, tasks=tasks)
    exposed = sorted(c["key"] for c in opens if c["task"] in g1 and
                     (c["row"].get("oracle_exposed_defects") or (c["grade"] or {}).get("oracle_exposed_defects")))
    out = {"saturated_exempt": saturated, "exposed_open_runs": exposed, "expected_effect": PC_EXPECTED,
           "n_pairs": len(pairs)}
    if not pairs:
        out.update(status="no_valid_pairs", outcome="control not exercised" if not exposed else "inconclusive")
        return out
    b = stats.cluster_bootstrap(pairs, n=BOOT, seed=seed, interval=INTERVAL)
    out.update(status="ok", delta=b["delta"], ci90=b["ci90"], se=b["se"], n_prs=b["n_prs"])
    if not exposed:
        out["outcome"] = "control not exercised"
    elif b["delta"] > 0:
        out["outcome"] = "pass"
    elif b["delta"] < 0:
        out["outcome"] = "void"
    else:
        out["outcome"] = "inconclusive"
    return out


def guard(cells, inputs, arms):
    """the 25 % guard: an arm whose excluded share (1 − valid / planned) exceeds 0.25 marks the
    read inconclusive by degradation (reported; the figures are still printed)"""
    planned = inputs.get("planned_cells") or [c["key"] for c in cells]
    out = {}
    for arm in arms:
        p = [k for k in planned if k.split("/")[1] == arm]
        v = [c for c in cells if c["arm"] == arm and c["valid"]]
        if not p:
            continue
        share = 1.0 - len(v) / float(len(p))
        out[arm] = {"planned": len(p), "valid": len(v), "excluded_share": share, "tripped": share > GUARD}
    return {"arms": out, "inconclusive_by_degradation": any(x["tripped"] for x in out.values())}


def missingness(cells, inputs, arms, pairs_fn, seed):
    planned = inputs.get("planned_cells") or [c["key"] for c in cells]
    rowed = {c["key"] for c in cells}
    by_arm = {}
    for arm in arms:
        rec = {"planned": 0, "rowed": 0, "valid": 0, "not_rowed": 0, "excluded": {}}
        for k in planned:
            if k.split("/")[1] != arm:
                continue
            rec["planned"] += 1
            if k not in rowed:
                rec["not_rowed"] += 1
        for c in cells:
            if c["arm"] != arm:
                continue
            rec["rowed"] += 1
            if c["valid"]:
                rec["valid"] += 1
            for r in c["reasons"]:
                rec["excluded"][r] = rec["excluded"].get(r, 0) + 1
        by_arm[arm] = rec
    sessions = {}
    for c in cells:
        if not c["matched"]:
            continue
        key = "%s/k=%s" % (c["arm"], c["k"])
        s = sessions.setdefault(key, {"cells": 0, "sessions_planned": 0, "sessions_valid": 0, "sessions_excluded": 0})
        s["cells"] += 1
        s["sessions_planned"] += c["k"]
        sv = c["sessions_valid"] if isinstance(c["sessions_valid"], int) else 0
        s["sessions_valid"] += sv
        s["sessions_excluded"] += c["k"] - sv
    bounds = {}
    for name, mode in (("excluded_sessions_missed_everything", "missed"),
                       ("excluded_sessions_caught_everything", "caught")):
        pairs = pairs_fn(mode)
        r = primary_read(pairs, seed)
        bounds[name] = r
    return {"cells_by_arm": by_arm, "sessions_by_arm_k": sessions, "bounds": bounds}


def bound_pairs(cells, arm_a, arm_b, mode):
    """pairs for the SKP-012 bounds: a valid arm_a cell paired with every rowed arm_b matched cell
    whose only defect is session-level (valid with sessions_valid < k, or invalid only by
    sessions_valid < ⌈k/2⌉); its excluded sessions caught nothing ("missed") or everything ("caught")"""
    a = {(c["task"], c["pair_trial"]): c for c in cells if c["arm"] == arm_a}
    b = {(c["task"], c["pair_trial"]): c for c in cells if c["arm"] == arm_b}
    out = []
    for key in sorted(set(a) & set(b), key=lambda k: (str(k[0]), k[1])):
        ca, cb = a[key], b[key]
        if not ca["valid"]:
            continue
        # a matched cell below ⌈k/2⌉ valid sessions is rowed `degraded` by the runner (D-7.3)
        session_only = cb["matched"] and "sessions_valid<ceil(k/2)" in cb["reasons"] and \
            set(cb["reasons"]) <= {"sessions_valid<ceil(k/2)", "status:degraded"}
        if not (cb["valid"] or session_only):
            continue
        if cb["defects"] is None or cb["defects"] != ca["defects"]:
            continue
        caught = cb["caught"] if cb["caught"] is not None else 0
        short = cb["matched"] and isinstance(cb["k"], int) and (cb["sessions_valid"] or 0) < cb["k"]
        if mode == "caught" and short:
            caught = cb["defects"]
        out.append({"pr": key[0], "trial": key[1], "full": common.side(ca),
                    "matched": {"caught": caught, "defects": cb["defects"], "cost": cb["cost"]}})
    return out


def dollar_table(pairs):
    rows, within = [], 0
    for p in pairs:
        cf, cm = p["full"]["cost"], p["matched"]["cost"]
        ok = cf is not None and cm is not None and abs(cm - cf) <= DOLLAR_TOL * cf
        within += ok
        rows.append({"pr": p["pr"], "trial": p["trial"], "cost_full": cf, "cost_matched": cm,
                     "ratio": (cm / cf) if cf else None, "within_25pct": ok})
    return {"pairs": rows, "within": within, "n": len(rows),
            "share_within": within / float(len(rows)) if rows else None, "tolerance": DOLLAR_TOL}


def all_spend(cells, arm_a, arm_b, tasks):
    tot = {"full": 0.0, "matched": 0.0}
    for c in cells:
        if c["task"] not in tasks:
            continue
        if c["arm"] == arm_a:
            tot["full"] += c["all_spend"] or 0.0
        elif c["arm"] == arm_b:
            tot["matched"] += c["all_spend"] or 0.0
    return tot


def contrast(cells, arm_a, arm_b, seed, restrict_fn=None):
    pairs, lost = common.make_pairs(cells, arm_a, arm_b, restrict_fn=restrict_fn)
    r = primary_read(pairs, seed)
    r["arm_a"], r["arm_b"], r["pairs_lost"] = arm_a, arm_b, len(lost)
    return r, pairs


def regrade_cells(cells, grades_dir, label):
    """cells re-graded under another label set: DIR/<label>/<batch>/<arm>/<task>-t<trial>/grade.json
    (the grade's own missed_pm3 and defects_seeded); None when the directory is absent"""
    base = os.path.join(grades_dir, label)
    if not os.path.isdir(base):
        return None
    out = []
    for c in cells:
        p = os.path.join(base, str(c["batch"]), str(c["arm"]), "%s-t%s" % (c["task"], c["trial"]), "grade.json")
        g = None
        if os.path.isfile(p) and not os.path.islink(p):
            g = common.load_json(p, "sensitivity grade")
        row = {k: v for k, v in c["row"].items()
               if k not in ("defects_seeded", "defects_missed", "defects_missed_pm3", "defects_caught")}
        nc = common.build_cell(row, g, c["run_dir"], p if g else None, VALIDITY)
        nc["pair_trial"] = c["pair_trial"]
        out.append(nc)
    return out


def exact_dollar_pairs(pairs, cells_by_key):
    """the exact-dollar trim: the largest m ≤ k valid sessions (in session order) whose summed cost
    ≤ the paired full cell's cost; the matched side caught = the union of those sessions"""
    out, missing = [], 0
    for p in pairs:
        cb = cells_by_key[p["matched"]["key"]]
        ps = cb.get("per_session")
        if not isinstance(ps, list) or not ps:
            missing += 1
            continue
        budget = p["full"]["cost"] or 0.0
        spent, got, m = 0.0, set(), 0
        for s in ps:
            if not isinstance(s, dict) or s.get("status") not in (None, "completed", "valid"):
                continue
            cost = s.get("cost_usd")
            if not isinstance(cost, (int, float)) or spent + cost > budget:
                break
            spent += cost
            m += 1
            got |= set(common.session_detected(s) or [])
        got &= set(cb["defect_ids"])
        out.append({"pr": p["pr"], "trial": p["trial"], "full": p["full"],
                    "matched": {"caught": len(got), "defects": p["matched"]["defects"], "cost": spent, "m": m}})
    return out, missing


def strays_pairs(pairs, strays):
    """judge-confirmed real strays count as defects for every arm (PRD D14): per PR the n_s real
    strays join the denominator of both sides; a side's caught gains the strays its cell cited"""
    by_pr = {}
    for s in strays or []:
        by_pr.setdefault(s.get("pr"), []).append(set(s.get("cells") or []))
    out = []
    for p in pairs:
        ss = by_pr.get(p["pr"], [])
        extra = len(ss)
        cf = sum(1 for s in ss if p["full"]["key"] in s)
        cm = sum(1 for s in ss if p["matched"]["key"] in s)
        out.append({"pr": p["pr"], "trial": p["trial"],
                    "full": dict(p["full"], caught=p["full"]["caught"] + cf, defects=p["full"]["defects"] + extra),
                    "matched": dict(p["matched"], caught=p["matched"]["caught"] + cm,
                                    defects=p["matched"]["defects"] + extra)})
    return out


def pipeline_independent_fn(ca, cb):
    meta = dict(ca["labels_meta"])
    meta.update(cb["labels_meta"])
    keep = set()
    for d, m in meta.items():
        src = str(m.get("label_source") or "")
        if m.get("review_driven") is False or "incident" in src:
            keep.add(d)
    return keep


def final_reads(cells, inputs, reg, seed, planned_se, sens_dir=None, judge_dir=None):
    out = {}
    pairs, lost = common.make_pairs(cells, PRIMARY_A, PRIMARY_B)
    tasks = {p["pr"] for p in pairs}
    prim = primary_read(pairs, seed)
    groups = reg.get("groups") or []
    ran = [j for j, g in enumerate(groups, 1) if any(c["task"] in g for c in cells)]
    if groups and ran and planned_se:
        lt = look_table(cells, reg, max(ran), seed, planned_se)
        stop = lt[-1]
        prim["rci_at_stopping_look"] = {"look": stop["look"], "b_yes": stop.get("b_yes"), "rci": stop.get("rci"),
                                        "decision": stop.get("decision")}
        out["looks"] = lt
    prim["pairs_lost"] = len(lost)
    out["primary"] = prim
    lmm = stats.reml_lmm(pairs)
    out["lmm"] = lmm if lmm.get("status") == "ok" else {"status": lmm.get("status", "reml_boundary"),
                                                        "n_obs": lmm.get("n_obs"), "n_groups": lmm.get("n_groups")}
    out["permutation"] = stats.permutation_test(pairs, n=BOOT, seed=seed, unit="pr")
    sec = {}
    sec["defects_per_usd"] = stats.defects_per_usd(pairs, n=BOOT, seed=seed)
    alls = all_spend(cells, PRIMARY_A, PRIMARY_B, tasks)
    sec["cost_per_extra_defect"] = {
        "matched_valid": stats.cost_per_extra_defect(pairs, "matched", "valid"),
        "matched_all_spend": stats.cost_per_extra_defect(pairs, "matched", "all", alls),
        "session1_valid": stats.cost_per_extra_defect(pairs, "session1", "valid"),
        "session1_all_spend": _session1_all(cells, pairs, tasks),
    }
    sec["review_only_vs_full"], _ = contrast(cells, REVIEW_ONLY, PRIMARY_A, seed)
    sec["pipeline_independent"], pi_pairs = contrast(cells, PRIMARY_A, PRIMARY_B, seed, restrict_fn=pipeline_independent_fn)
    if pi_pairs and all(p["full"]["defects"] == 0 for p in pi_pairs):
        sec["pipeline_independent"] = {"status": "no_labels_meta"}
    sec["matched_fable"], _ = contrast(cells, PRIMARY_A, FABLE_B, seed)
    sec["dollar_matching"] = dollar_table(pairs)
    sec["positive_control"] = positive_control(cells, reg, seed)
    out["secondary"] = sec
    out["void"] = sec["positive_control"].get("outcome") == "void"
    out["guard"] = guard(cells, inputs, [PRIMARY_A, PRIMARY_B])
    out["missingness"] = missingness(cells, inputs, [PRIMARY_A, PRIMARY_B, FABLE_B, REVIEW_ONLY],
                                     lambda mode: bound_pairs(cells, PRIMARY_A, PRIMARY_B, mode), seed)
    out["sensitivities"] = sensitivities(cells, inputs, reg, seed, pairs, sens_dir, judge_dir, prim)
    return out


def _session1_all(cells, pairs, tasks):
    """cost per extra defect vs BARE-1 on all spend: the full arm's every attempt against the
    matched cells' first-session cost (every rowed matched cell on the paired PRs)"""
    full = sum(c["all_spend"] or 0.0 for c in cells if c["arm"] == PRIMARY_A and c["task"] in tasks)
    s1 = 0.0
    for c in cells:
        if c["arm"] == PRIMARY_B and c["task"] in tasks and c.get("session1") and c["session1"].get("cost") is not None:
            s1 += c["session1"]["cost"]
    return stats.cost_per_extra_defect(pairs, "session1", "all", {"full": full, "matched": s1}) \
        if all(p["matched"].get("session1") for p in pairs) and pairs else {"status": "no_session1"}


def sensitivities(cells, inputs, reg, seed, pairs, sens_dir, judge_dir, prim):
    order = reg.get("sensitivities") or DEFAULT_SENSITIVITIES
    res = {}
    judge = None
    if judge_dir:
        jp = os.path.join(judge_dir, "result.json")
        if os.path.isfile(jp):
            judge = common.load_json(jp, "judge result")
    by_key = {c["key"]: c for c in cells}
    for name in order:
        if name in ("frozen_c131_labels", "v1_labels"):
            label = "c131" if name == "frozen_c131_labels" else "v1"
            rc = regrade_cells(cells, sens_dir, label) if sens_dir else None
            if rc is None:
                res[name] = {"status": "not_provided"}
            else:
                res[name], _ = contrast(rc, PRIMARY_A, PRIMARY_B, seed)
        elif name == "judge_corrected":
            if not judge or not judge.get("corrected"):
                res[name] = {"status": "not_provided"}
            else:
                cor = judge["corrected"]
                a, b = cor.get(PRIMARY_A) or {}, cor.get(PRIMARY_B) or {}
                d = (a.get("recall") - b.get("recall")) if a.get("recall") is not None and b.get("recall") is not None else None
                res[name] = {"status": "ok" if d is not None else "not_provided", "delta": d,
                             "recall_full": a.get("recall"), "recall_matched": b.get("recall"),
                             "precision_full": a.get("precision"), "precision_matched": b.get("precision")}
        elif name == "judge_strays_as_defects":
            if not judge or "real_strays" not in judge:
                res[name] = {"status": "not_provided"}
            else:
                res[name] = primary_read(strays_pairs(pairs, judge["real_strays"]), seed)
        elif name == "exact_dollar_trim":
            ep, missing = exact_dollar_pairs(pairs, by_key)
            r = primary_read(ep, seed)
            r["pairs_without_sessions"] = missing
            res[name] = r
        elif name == "pair_level_permutation":
            res[name] = stats.permutation_test(pairs, n=BOOT, seed=seed, unit="pair")
        elif name == "ci90":
            res[name] = {"status": prim.get("status"), "ci90": prim.get("ci90")}
        elif name == "leave_one_pr_out":
            lo = {}
            for pr in sorted({p["pr"] for p in pairs}):
                lo[pr] = primary_read([p for p in pairs if p["pr"] != pr], seed, min_prs=1)
            res[name] = lo
        elif name == "pr11_in_out":
            tf = inputs.get("task_fixture") or {}
            out_tasks = {t for t, f in tf.items() if f == "pr-11"}
            if not out_tasks or not any(p["pr"] in out_tasks for p in pairs):
                res[name] = {"status": "not_applicable"}
            else:
                res[name] = {"pr11_out": primary_read([p for p in pairs if p["pr"] not in out_tasks], seed, min_prs=1),
                             "tasks": sorted(out_tasks)}
        elif name == "degraded_contaminated_excluded":
            strict = [dict(c, valid=c["valid"] and not c["row"].get("degraded")) for c in cells]
            res[name], _ = contrast(strict, PRIMARY_A, PRIMARY_B, seed)
        elif name == "class9_nonrepo_egress_reincluded":
            # round 4 (PREREGISTRATION §12 addendum): a cell whose ONLY invalidity is a class-9
            # network egress naming no repository (repo_named false: a tool download, not
            # answer-key retrieval) counts as valid with its recall as graded; the main filter
            # stays unchanged
            groups = reg.get("groups") or []

            def group_of(task):
                return next(("G%d" % j for j, g in enumerate(groups, 1) if task in g), "ungrouped")

            back = [dict(c, valid=True) if common.only_nonrepo_egress(c) else c for c in cells]
            r, sens_pairs = contrast(back, PRIMARY_A, PRIMARY_B, seed)
            counts = {}
            for c in cells:
                if common.only_nonrepo_egress(c):
                    a = counts.setdefault(c["arm"], {})
                    g = group_of(c["task"])
                    a[g] = a.get(g, 0) + 1
            r["reincluded_cells"] = counts
            r["reincluded_keys"] = sorted(c["key"] for c in cells if common.only_nonrepo_egress(c))
            res[name] = r
        elif name == "pr_weighted":
            res[name] = prim.get("pr_weighted") or {"status": prim.get("status")}
        elif name == "matched_fable_contrast":
            res[name], _ = contrast(cells, PRIMARY_A, FABLE_B, seed)
        else:
            res[name] = {"status": "unknown_sensitivity"}
    return {"order": list(order), "reads": res}


# ---------------------------------------------------------------- markdown
def md_primary(title, r):
    if r.get("status") not in ("ok",):
        return "| %s | status `%s` | PRs %s |\n" % (title, r.get("status"), r.get("n_prs", "—"))
    alt = "percentile" if r.get("interval", "t") == "t" else "t"
    return "| %s | Δ %s | 95 %% %s | 90 %% %s | SE %s | PRs %d, pairs %d, defects %d | diag 95 %% %s %s |\n" % (
        title, f4(r["delta"]), iv(r["ci95"]), iv(r["ci90"]), f4(r["se"]), r["n_prs"], r["n_pairs"], r["n_defects"],
        alt, iv(r.get("ci95_" + alt)))


def render_md(doc):
    L = ["# cycle-132 reads — mode `%s`\n" % doc["mode"], "\n"]
    inp = doc["inputs"]
    L.append("Inputs: rows sha256 `%s`; grades sha256 `%s`; INPUTS.json sha256 `%s`; registration `%s`; seed %d; "
             "interval %s; validity rules %s.\n\n"
             % (inp["rows_sha256"], inp["grades_sha256"], inp["inputs_sha256"], inp.get("registration_sha256") or "unregistered",
                doc["seed"], doc["interval"], doc["validity"]))
    if doc["mode"] == "placebo":
        p = doc["placebo"]
        L.append("Contrast `%s` − `%s`; %s.\n\n" % (doc["arm_a"], doc["arm_b"], "PASS" if p.get("pass") else "FAIL"))
        L.append("Pass rule: |mean Δ| < 0.03 (bias) and ≤ 0.08 of the 95 %% %s intervals exclude 0 (calibration).\n\n" % doc["interval"])
        L.append("| shuffles | resamples | share excluding 0 | mean Δ | Δ q05 / q50 / q95 | diag: mean abs Δ | diag: share (t) | diag: share (percentile) |\n|---|---|---|---|---|---|---|---|\n")
        if p.get("status") == "ok":
            L.append("| %d | %d | %s | %s | %s / %s / %s | %s | %s | %s |\n\n" % (
                p["n"], p["boot"], f4(p["share_excluding_zero"]), f4(p["mean_delta"]), f4(p["delta_q05"]), f4(p["delta_q50"]),
                f4(p["delta_q95"]), f4(p["diagnostic_mean_abs_delta"]), f4(p["diagnostic_share_excluding_zero_t"]),
                f4(p["diagnostic_share_excluding_zero_percentile"])))
        else:
            L.append("| status `%s` |\n\n" % p.get("status"))
        L.append("Primary read on the unshuffled pairs (descriptive):\n\n")
        L.append(md_primary("unshuffled", doc["unshuffled"]))
        return "".join(L)
    if doc.get("looks"):
        L.append("## Looks\n\n| look | PRs | defects | Δ | SE | t | z_yes | b_yes | z_no | b_no | CP yes | CP no | RCI | decision |\n"
                 "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n")
        for r in doc["looks"]:
            L.append("| %d | %d | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s%s |\n" % (
                r["look"], r["n_prs"], r["n_defects"], f4(r.get("delta")), f4(r.get("se")), f4(r.get("t")),
                f4(r.get("z_yes")), f4(r.get("b_yes")), f4(r.get("z_no")), f4(r.get("b_no")), f4(r.get("cp_yes")),
                f4(r.get("cp_no")), iv(r.get("rci")), r.get("decision"),
                (" (%s)" % r["reason"]) if r.get("reason") else ""))
        L.append("\n" + PARTITION_LEGEND + "\n")
        L.append("\nBoundary constant %s; MDE %s; planned final SE %s.\n\n" % (
            f4(doc["boundary_constant"]), f4(doc["mde"]), f4(doc["planned_final_se"])))
    if doc["mode"] == "final":
        L.append("## Pre-registered reads\n\n")
        L.append(md_primary("primary %s − %s" % (PRIMARY_A, PRIMARY_B), doc["primary"]))
        pw = doc["primary"].get("pr_weighted")
        if pw:
            L.append("| PR-weighted | Δ %s | 95 %% %s | 90 %% %s | | |\n" % (f4(pw["delta"]), iv(pw["ci95"]), iv(pw["ci90"])))
        st = doc["primary"].get("rci_at_stopping_look")
        if st:
            L.append("\nRepeated confidence interval at the stopping look %d: %s (b = %s); decision %s.\n" % (
                st["look"], iv(st["rci"]), f4(st["b_yes"]), st["decision"]))
        lmm = doc["lmm"]
        L.append("\nREML LMM: %s.\n" % ("β %s, 95 %% %s, σu %s, σe %s" % (f4(lmm["beta"]), iv(lmm["ci95"]), f4(lmm["sigma_u"]), f4(lmm["sigma_e"]))
                                         if lmm.get("status") == "ok" else "status `%s`" % lmm.get("status")))
        pm = doc["permutation"]
        L.append("PR-level permutation: %s.\n\n" % ("p %s (%s, %d)" % (f4(pm["p"]), "exact" if pm["exact"] else "Monte Carlo", pm["n"])
                                                   if pm.get("status") == "ok" else "status `%s`" % pm.get("status")))
        sec = doc["secondary"]
        dpu = sec["defects_per_usd"]
        if dpu.get("status") == "ok":
            L.append("Defects per USD: full %s %s; matched %s %s.\n\n" % (
                f4(dpu["full"].get("value")), iv(dpu["full"].get("ci95")), f4(dpu["matched"].get("value")), iv(dpu["matched"].get("ci95"))))
        L.append("| cost per extra defect | value | extra defects | status |\n|---|---|---|---|\n")
        for k in sorted(sec["cost_per_extra_defect"]):
            v = sec["cost_per_extra_defect"][k]
            L.append("| %s | %s | %s | %s |\n" % (k, f4(v.get("value")), f4(v.get("extra_defects")), v.get("status")))
        L.append("\n| contrast | read |\n|---|---|\n")
        for k in ("review_only_vs_full", "pipeline_independent", "matched_fable"):
            v = sec[k]
            L.append("| %s | %s |\n" % (k, "Δ %s, 95 %% %s, PRs %s" % (f4(v["delta"]), iv(v["ci95"]), v["n_prs"])
                                        if v.get("status") == "ok" else "status `%s`" % v.get("status")))
        pc = sec["positive_control"]
        L.append("\nPositive control (%s − %s, G1, saturated PRs exempt %s): %s%s.\n" % (
            OPEN_MOUNT, PRIMARY_A, ", ".join(pc.get("saturated_exempt") or []) or "none", pc.get("outcome", pc.get("status")),
            "; Δ %s, 90 %% %s, expected %s, exposed open runs %d" % (f4(pc["delta"]), iv(pc["ci90"]), f4(pc["expected_effect"]),
                                                                  len(pc["exposed_open_runs"])) if pc.get("status") == "ok" else ""))
        if doc.get("void"):
            L.append("\n**VOID: the positive control read negative with verified exposure; every other read is reported void.**\n")
        dm = sec["dollar_matching"]
        L.append("\nDollar matching: %d of %d pairs within ±25 %% of the full cell's cost.\n\n" % (dm["within"], dm["n"]))
        L.append("| PR | trial | cost full | cost matched | ratio | within |\n|---|---|---|---|---|---|\n")
        for r in dm["pairs"]:
            L.append("| %s | %d | %s | %s | %s | %s |\n" % (r["pr"], r["trial"], f4(r["cost_full"]), f4(r["cost_matched"]),
                                                          f4(r["ratio"]), "yes" if r["within_25pct"] else "no"))
        g = doc["guard"]
        L.append("\n25 %% guard: %s.\n\n" % ("INCONCLUSIVE BY DEGRADATION" if g["inconclusive_by_degradation"] else "not tripped"))
        ms = doc["missingness"]
        L.append("## Missingness\n\n| arm | planned | rowed | valid | not rowed | excluded by reason |\n|---|---|---|---|---|---|\n")
        for arm in sorted(ms["cells_by_arm"]):
            r = ms["cells_by_arm"][arm]
            L.append("| %s | %d | %d | %d | %d | %s |\n" % (arm, r["planned"], r["rowed"], r["valid"], r["not_rowed"],
                                                          ", ".join("%s %d" % (k, r["excluded"][k]) for k in sorted(r["excluded"])) or "—"))
        if ms["sessions_by_arm_k"]:
            L.append("\n| arm / k | cells | sessions planned | valid | excluded |\n|---|---|---|---|---|\n")
            for k in sorted(ms["sessions_by_arm_k"]):
                s = ms["sessions_by_arm_k"][k]
                L.append("| %s | %d | %d | %d | %d |\n" % (k, s["cells"], s["sessions_planned"], s["sessions_valid"], s["sessions_excluded"]))
        L.append("\n")
        for k in sorted(ms["bounds"]):
            L.append(md_primary("bound: %s" % k, ms["bounds"][k]))
        L.append("\n## Sensitivities (registered order; decide nothing)\n\n")
        for name in doc["sensitivities"]["order"]:
            v = doc["sensitivities"]["reads"][name]
            if name == "leave_one_pr_out":
                for pr in sorted(v):
                    L.append(md_primary("leave out %s" % pr, v[pr]))
            elif name == "class9_nonrepo_egress_reincluded":
                L.append(md_primary(name, v))
                cnt = v.get("reincluded_cells") or {}
                L.append("| re-included cells (arm: group n) | %s |\n" % (
                    "; ".join("%s: %s" % (arm, ", ".join("%s %d" % (g, cnt[arm][g]) for g in sorted(cnt[arm])))
                              for arm in sorted(cnt)) or "none"))
                if v.get("status") == "ok":
                    L.append("| recall per arm | %s %s, %s %s |\n" % (PRIMARY_A, f4(v.get("recall_full")),
                                                                    PRIMARY_B, f4(v.get("recall_matched"))))
            elif name == "pr11_in_out" and "pr11_out" in v:
                L.append(md_primary("pr-11 out", v["pr11_out"]))
            elif name in ("pair_level_permutation",):
                L.append("| %s | %s |\n" % (name, "p %s" % f4(v.get("p")) if v.get("status") == "ok" else "status `%s`" % v.get("status")))
            elif name == "ci90":
                L.append("| ci90 | %s |\n" % iv(v.get("ci90")))
            elif name == "pr_weighted":
                L.append("| pr_weighted | Δ %s %s |\n" % (f4(v.get("delta")), iv(v.get("ci95"))))
            elif name == "judge_corrected":
                L.append("| judge_corrected | %s |\n" % ("Δ %s" % f4(v["delta"]) if v.get("status") == "ok" else "status `%s`" % v.get("status")))
            else:
                L.append(md_primary(name, v))
    return "".join(L)


# ---------------------------------------------------------------- CLI
def _task_fixture(suite_roots):
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


def _grades_sha(cells):
    h = {c["key"]: (common.sha256_file(c["grade_path"]) if c["grade_path"] else None) for c in cells}
    import hashlib
    return hashlib.sha256(json.dumps(h, sort_keys=True).encode()).hexdigest()


def _planned_se(reg, reg_path, power_path):
    if power_path:
        pj = common.load_json(power_path, "power.json")
        return float(pj["planned_final_se"])
    if reg.get("planned_final_se") is not None:
        return float(reg["planned_final_se"])
    pp = reg.get("power_json")
    if pp:
        for base in (os.path.dirname(os.path.abspath(reg_path)) if reg_path else None, os.getcwd()):
            if base and os.path.isfile(os.path.join(base, pp)):
                return float(common.load_json(os.path.join(base, pp), "power.json")["planned_final_se"])
    return None


def parse(argv):
    ap = argparse.ArgumentParser(prog="reads-c132.py", description="cycle-132 pre-registered reads")
    ap.add_argument("--rows", required=True)
    ap.add_argument("--results-root", action="append", default=[])
    ap.add_argument("--registration")
    ap.add_argument("--inputs")
    m = ap.add_mutually_exclusive_group(required=True)
    m.add_argument("--look", type=int)
    m.add_argument("--final", action="store_true")
    m.add_argument("--placebo", action="store_true")
    m.add_argument("--make-inputs", action="store_true")
    ap.add_argument("--out", required=True)
    ap.add_argument("--power")
    ap.add_argument("--sensitivity-grades")
    ap.add_argument("--judge")
    ap.add_argument("--arm-a", default=PRIMARY_A)
    ap.add_argument("--arm-b", default=PRIMARY_B)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--name", default="reads")
    ap.add_argument("--pin")
    ap.add_argument("--label-set")
    ap.add_argument("--planned")
    ap.add_argument("--suite-root", action="append", default=[])
    ap.add_argument("--placebo-n", type=int, default=PLACEBO_N)
    ap.add_argument("--interval", choices=("t", "percentile"), default="t")
    ap.add_argument("--validity", choices=common.VALIDITY_RULES, default="c132")
    a = ap.parse_args(argv)
    if not re.match(r"^[A-Za-z0-9._-]+$", a.name):
        ap.error("--name must be a bare file stem")
    if not a.make_inputs and not a.inputs:
        ap.error("--inputs INPUTS.json is required (D-7.5)")
    if (a.look is not None or a.final) and not a.registration:
        ap.error("--registration is required for --look and --final")
    return a


def main(argv=None):
    try:
        a = parse(sys.argv[1:] if argv is None else argv)
    except SystemExit as e:
        return 2 if e.code else 0
    global INTERVAL, VALIDITY
    INTERVAL, VALIDITY = a.interval, a.validity
    try:
        rows = common.load_rows(a.rows)
        cells = common.load_cells(rows, a.results_root, VALIDITY)
        if a.make_inputs:
            planned = None
            if a.planned:
                with open(a.planned, encoding="utf-8") as f:
                    txt = f.read()
                planned = json.loads(txt) if txt.lstrip().startswith("[") else [x.strip() for x in txt.splitlines() if x.strip()]
            doc = common.make_inputs(a.rows, rows, cells, pin=a.pin, label_set=a.label_set, planned=planned,
                                     task_fixture=_task_fixture(a.suite_root))
            os.makedirs(a.out, exist_ok=True)
            with open(os.path.join(a.out, "INPUTS.json"), "w", encoding="utf-8") as f:
                f.write(json.dumps(doc, sort_keys=True, indent=2) + "\n")
            return 0
        inputs = common.load_json(a.inputs, "INPUTS.json")
        common.validate_inputs(inputs, a.rows, rows, cells)
        reg, reg_sha = {}, None
        if a.registration:
            reg = common.load_json(a.registration, "REGISTRATION.json")
            reg_sha = common.validate_registration(a.registration, rows)
        seed = a.seed if a.seed is not None else int(reg.get("seed", DEFAULT_SEED))
        doc = {"inputs": {"rows_sha256": common.sha256_file(a.rows), "grades_sha256": _grades_sha(cells),
                          "inputs_sha256": common.sha256_file(a.inputs), "registration_sha256": reg_sha,
                          "n_rows": len(rows)},
               "seed": seed, "interval": INTERVAL, "validity": VALIDITY}
        if a.placebo:
            pairs, lost = common.make_pairs(cells, a.arm_a, a.arm_b)
            doc.update(mode="placebo", arm_a=a.arm_a, arm_b=a.arm_b, pairs_lost=len(lost),
                       placebo=stats.placebo(pairs, seed=seed, n=a.placebo_n, boot=PLACEBO_BOOT, interval=INTERVAL),
                       unshuffled=primary_read(pairs, seed))
        else:
            planned_se = _planned_se(reg, a.registration, a.power)
            if planned_se is None:
                raise InputError("no planned final SE: the registration names neither planned_final_se nor power_json (or pass --power)")
            doc.update(boundary_constant=float(reg.get("boundary_constant", 1.0)), mde=float(reg.get("mde", 0.10)),
                       planned_final_se=planned_se)
            if a.look is not None:
                doc.update(mode="look", look=a.look, looks=look_table(cells, reg, a.look, seed, planned_se),
                           guard=guard(cells, inputs, [PRIMARY_A, PRIMARY_B]),
                           positive_control=positive_control(cells, reg, seed))
                doc["decision"] = doc["looks"][-1].get("decision")
            else:
                doc["mode"] = "final"
                doc.update(final_reads(cells, inputs, reg, seed, planned_se, a.sensitivity_grades, a.judge))
        body_json, body_md = dumps(doc), render_md(doc)
    except InputError as e:
        sys.stderr.write("reads-c132: inputs invalid: %s\n" % e)
        return 1
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, a.name + ".json"), "w", encoding="utf-8") as f:
        f.write(body_json)
    with open(os.path.join(a.out, a.name + ".md"), "w", encoding="utf-8") as f:
        f.write(body_md)
    return 0
