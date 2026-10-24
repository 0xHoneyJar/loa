"""reads.py — the cycle-132 pre-registered reads (CLI: reads-c132.py).

Usage:
  reads-c132.py --rows F --results-root DIR [--results-root DIR …] --inputs INPUTS.json
                [--registration REGISTRATION.json] (--look N | --final | --placebo | --judge-defects) --out DIR
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
               read, matched-Fable contrast, dollar-matching table, the positive control (§8, addendum 10:
               a1_full_openmount − a1_full on every group, saturated PRs exempt; not exercised / void /
               pass / not demonstrated, the pre-addendum-10 label beside), missingness with the two bounds, the 25 % guard), then the sensitivities in the
               registration's order.
               Since addendum 16 (iv) the final also carries the §5 co-reads (`co_reads`, the look over
               every group: pipeline-independent Δ, recall by label_source / review_driven, the
               cost-matched Δ with its dollar-matching table), rendered before Missingness.
  --placebo    200 seeded within-PR arm-label shuffles through the primary read (1,000 resamples
               each): pass when |mean Δ| < 0.03 (bias) and ≤ 8 % of the 95 % intervals exclude 0
               (calibration); mean |Δ| and the other interval's share are diagnostics (round 1).
               --registration is optional here (the Phase 0 placebo precedes it; the output says
               "unregistered"); --arm-a/--arm-b pick the contrast (default a1_full, a0_bare_matched).
  --judge-defects  (cycle-133 C-11, a registered read under the registration schema v2 chain — sdd.md C-12; --registration
               required and schema_version 2, else inputs invalid) the defect-level judged recall of grader 1.5.0's
               --judge-verdicts grades: per cell, the defects with a blind `describes` verdict on a credited pair
               (grade.json credited_pairs; blind: false verdicts are reported beside, never counted); the --arm-a − --arm-b
               primary read (cluster bootstrap over PRs, the pairing and validity of the primary read) on the pairs whose
               two cells were graded by 1.5.0 with every credited pair judged (unjudged_pairs 0) — the others are listed as
               pairs_unjudged with the reason; per arm the cells, pairs judged / unjudged, grader recall and judged recall
               over the fully judged valid cells; the judge models, prompt hashes and verdicts-file hashes seen.
  --interval t (default; round 1) the primary 95 % / 90 % intervals are the cluster-t intervals
               Δ̂ ± t_{P−1, 0.975 | 0.95}·SE_boot and the group-sequential boundaries move to the t
               scale (same upper-tail mass, df = valid PRs − 1) for the crossing rule and the RCI; the
               percentile interval is printed beside as a diagnostic. `percentile` swaps the roles
               (normal-scale boundaries). Conditional power stays on the normal Brownian model.
  --validity c132 (default; sdd.md §5.2) or c131 (no oracle_exposed clause — the Phase 0 placebo
               on the 63 existing rows, whose cycle-130 a1_full runs all ran under the open mount)
  Sensitivity "contaminated_reincluded_per_class" (round 5, replacing round 4's single item; after
               "degraded and contaminated rows excluded"): for every contamination class observed in the
               rows (the grade's pattern; class 9 split by repo_named into network_egress:repo / :nonrepo /
               :unstated), the primary read with the cells whose ONLY invalidity is a contamination of that
               class counted valid (recall as graded), plus one read re-including every class; the cells
               are counted per arm, group and class. The round-4 name "class9_nonrepo_egress_reincluded"
               is still accepted in a registration's order and runs the network_egress:nonrepo member.
               Round 6 (addendum 9) adds the member "oracle_exposed": cells whose ONLY invalidity is
               oracle exposure, re-included by form — `read_only`, `diff` (with or without read) and
               `all` — with counts per arm, group, PR and form (grade.json oracle_exposed_by_form).
  --sensitivity-grades DIR  re-grades for the label-set sensitivities (regrade_labels.py writes them):
               DIR/<c131|v1|review>/<batch>/<arm>/<task>-t<n>/grade.json (a label directory absent →
               "not_provided"; a cell without a re-grade, e.g. a fixture the set has no key for, is built
               with grade None and so reads no_defect_record). The sensitivities frozen_c131_labels,
               v1_labels and review_derived_labels (addendum 16: §10 item 2, the seeded review-derived key —
               manifests/review/ for pr-19 … pr-28 and the moved cycle-131 set manifests/c131/ for the four
               older fixtures) read DIR/c131, DIR/v1 and DIR/review.
  Cost per extra defect (addendum 16, §5): `ok` (value = cost increment ÷ extra defects) only when both
               increments are positive; extra defects > 0 with a cost increment ≤ 0 → `dominated`, extra
               defects ≤ 0 with a cost increment > 0 → `dominated_by_cost` (value null, both increments printed).
  --judge DIR  the judge's result.json (judge_agree.py): judge-corrected figures and the
               judge-confirmed strays (absent → "not_provided")
  --make-inputs  write DIR/INPUTS.json for the current rows and run dirs (rows sha256, every
               grade.json sha256, pin, label set, planned cells, matched-cell session membership,
               task → fixture from the suite roots' task.yaml) — the lead reviews and freezes it.

Inputs are validated before any output (D-7.5): the rows file hash, every grade.json hash, the pin,
the label set, the cells and each matched cell's session membership must equal INPUTS.json, and every
row's registration_sha256 must equal sha256(REGISTRATION.json) or a predecessor on its `supersedes`
chain (REGISTRATION*.json beside it; PREREGISTRATION.md §12). Registration keys read: seed,
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
    "frozen_c131_labels", "v1_labels", "review_derived_labels", "judge_corrected", "judge_strays_as_defects",
    "exact_dollar_trim", "pair_level_permutation", "ci90", "leave_one_pr_out", "pr11_in_out",
    "degraded_contaminated_excluded", "contaminated_reincluded_per_class", "pr_weighted", "matched_fable_contrast",
]
LABEL_SENSITIVITIES = {"frozen_c131_labels": "c131", "v1_labels": "v1", "review_derived_labels": "review"}
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


PC_MIN_PAIRS = 3
PC_RULE = "§8 (addendum 10)"
PC_CONSEQUENCE = {"pass": "", "void": "every other read void",
                  "not demonstrated": "every other read unconfirmed by the positive control",
                  "not exercised": "every other read unconfirmed by the positive control"}


def pc_outcome(n_exposed, n_pairs, delta, ci90_t):
    """PREREGISTRATION §8 (addendum 10), ordered and exhaustive: not exercised (no exposure in any
    open run, or fewer than 3 eligible pairs) → void (the 90 % cluster-t interval entirely below 0)
    → pass (exposure in ≥ 2 open runs and Δ̂ > 0) → not demonstrated (otherwise, with exposure)"""
    if n_exposed == 0 or n_pairs < PC_MIN_PAIRS or delta is None:
        return "not exercised"
    if ci90_t and ci90_t[1] is not None and ci90_t[1] < 0:
        return "void"
    if n_exposed >= 2 and delta > 0:
        return "pass"
    return "not demonstrated"


def pc_outcome_pre_addendum_10(n_exposed, n_pairs, delta):
    """the label the pre-addendum-10 code gave (D-7.10, on G1's pairs): pass on Δ̂ > 0 with ≥ 1
    exposure; void on Δ̂ < 0; inconclusive on Δ̂ == 0 or on no pairs with exposure"""
    if not n_pairs:
        return "control not exercised" if not n_exposed else "inconclusive"
    if not n_exposed:
        return "control not exercised"
    if delta > 0:
        return "pass"
    if delta < 0:
        return "void"
    return "inconclusive"


def _pc_scope(cells, opens, scope, seed):
    """(saturated, pairs, exposed, bootstrap or None) for the open-vs-closed contrast on `scope`"""
    closed = {}
    for c in cells:
        if c["arm"] == PRIMARY_A and c["valid"] and c["task"] in scope:
            a = closed.setdefault(c["task"], [0, 0])
            a[0] += c["caught"]
            a[1] += c["defects"]
    saturated = sorted(t for t, (cg, d) in closed.items() if d and cg / float(d) > PC_SATURATED)
    pairs, _ = common.make_pairs(cells, OPEN_MOUNT, PRIMARY_A, tasks=scope - set(saturated))
    exposed = sorted(c["key"] for c in opens if c["task"] in scope and
                     (c["row"].get("oracle_exposed_defects") or (c["grade"] or {}).get("oracle_exposed_defects")))
    b = stats.cluster_bootstrap(pairs, n=BOOT, seed=seed, interval=INTERVAL) if pairs else None
    return saturated, pairs, exposed, b


def positive_control(cells, reg, seed):
    """PREREGISTRATION §8 (addendum 10): a1_full_openmount − a1_full on EVERY registered group's
    pairs, PRs whose closed-mount recall exceeds 0.9 exempt (no headroom); exposure = the oracle
    detector's per-run verdict over every open run of the registered groups; outcome by pc_outcome
    (90 % cluster-t interval, expected effect beside). `outcome_pre_addendum_10` is the label the
    pre-addendum code gave (G1-only pairs; pc_outcome_pre_addendum_10) — both reads are reported."""
    opens = [c for c in cells if c["arm"] == OPEN_MOUNT]
    if not opens:
        return {"status": "not_run"}
    groups = reg.get("groups") or []
    scope = set(t for g in groups for t in g) if groups else {c["task"] for c in opens}
    saturated, pairs, exposed, b = _pc_scope(cells, opens, scope, seed)
    g1 = set(groups[0]) if groups else scope
    old = (saturated, pairs, exposed, b) if g1 == scope else _pc_scope(cells, opens, g1, seed)
    out = {"rule": PC_RULE, "saturated_exempt": saturated, "exposed_open_runs": exposed,
           "n_exposed_open_runs": len(exposed), "expected_effect": PC_EXPECTED,
           "n_pairs": len(pairs), "eligible_pairs": len(pairs),
           "outcome_pre_addendum_10": pc_outcome_pre_addendum_10(
               len(old[2]), len(old[1]), old[3]["delta"] if old[3] else None)}
    if b is None:
        out.update(status="no_valid_pairs", n_prs=0)
    else:
        out.update(status="ok", delta=b["delta"], ci90=b["ci90"], ci90_t=b["ci90_t"], se=b["se"], n_prs=b["n_prs"])
    out["outcome"] = pc_outcome(len(exposed), len(pairs), out.get("delta"), out.get("ci90_t"))
    out["consequence"] = PC_CONSEQUENCE[out["outcome"]]
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


def contrast(cells, arm_a, arm_b, seed, restrict_fn=None, min_prs=MIN_PRS):
    pairs, lost = common.make_pairs(cells, arm_a, arm_b, restrict_fn=restrict_fn)
    r = primary_read(pairs, seed, min_prs=min_prs)
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


def label_descriptive(pairs):
    """per-arm caught / defects / defect-weighted recall on a label set's valid pairs, printed whatever the
    read's status (the frozen keys cover 4 PRs, below the 6-PR minimum: too_few_prs)"""
    out = {"n_prs": len({p["pr"] for p in pairs}), "n_pairs": len(pairs)}
    for side_name, arm in (("full", PRIMARY_A), ("matched", PRIMARY_B)):
        caught = sum(p[side_name]["caught"] for p in pairs)
        den = sum(p[side_name]["defects"] for p in pairs)
        out[arm] = {"caught": caught, "defects": den, "recall": (float(caught) / den) if den else None}
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


def _group_of(reg, task):
    return next(("G%d" % j for j, g in enumerate(reg.get("groups") or [], 1) if task in g), "ungrouped")


def reinclude(cells, reg, seed, cls, pred=None):
    """the primary read with the cells whose only invalidity is a contamination of class `cls`
    (None: any class) — or that satisfy `pred` when given — counted valid; their count per arm and
    group, and their keys"""
    sel = [c for c in cells if (pred(c) if pred else common.only_contamination(c, cls))]
    keys = {c["key"] for c in sel}
    back = [dict(c, valid=True) if c["key"] in keys else c for c in cells]
    r, _ = contrast(back, PRIMARY_A, PRIMARY_B, seed)
    counts = {}
    for c in sel:
        a = counts.setdefault(c["arm"], {})
        g = _group_of(reg, c["task"])
        a[g] = a.get(g, 0) + 1
    r["reincluded_cells"] = counts
    r["reincluded_keys"] = sorted(keys)
    return r


def reincluded_family(cells, reg, seed):
    """{observed, counts: {arm: {group: {class: n}}}, classes: {class: read}, all_classes: read};
    classes are those observed on any contaminated cell, in sorted order"""
    observed = sorted({c["contamination"] for c in cells if c.get("contamination")})
    counts = {}
    for c in cells:
        if common.only_contamination(c):
            g = counts.setdefault(c["arm"], {}).setdefault(_group_of(reg, c["task"]), {})
            g[c["contamination"]] = g.get(c["contamination"], 0) + 1
    return {"status": "ok" if observed else "no_contaminated_cells", "observed": observed, "counts": counts,
            "classes": {cls: reinclude(cells, reg, seed, cls) for cls in observed},
            "all_classes": reinclude(cells, reg, seed, None) if observed else {"status": "no_contaminated_cells"},
            "oracle_exposed": oracle_family(cells, reg, seed)}


def oracle_family(cells, reg, seed):
    """round 6 (addendum 9): oracle-exposed cells re-included — cells whose ONLY invalidity is oracle
    exposure of form `read` only, of form `diff` (with or without read), and every oracle-exposed
    cell (any form, incl. an unrecorded one); recall as graded (the detector does not change the
    grade); counts per arm, group, PR and form"""
    exposed = [c for c in cells if common.only_oracle(c)]
    counts = {}
    for c in exposed:
        g = counts.setdefault(c["arm"], {}).setdefault(_group_of(reg, c["task"]), {}).setdefault(c["task"], {})
        g[c["oracle_form"]] = g.get(c["oracle_form"], 0) + 1
    if not any(c.get("oracle_form") for c in cells):
        return {"status": "no_oracle_exposed_cells", "counts": {}}
    return {"status": "ok", "counts": counts,
            "read_only": reinclude(cells, reg, seed, None, lambda c: common.only_oracle(c, "read")),
            "diff": reinclude(cells, reg, seed, None, lambda c: common.only_oracle(c, "diff")),
            "all": reinclude(cells, reg, seed, None, common.only_oracle)}


def pipeline_independent_fn(ca, cb):
    meta = dict(ca["labels_meta"])
    meta.update(cb["labels_meta"])
    keep = set()
    for d, m in meta.items():
        src = str(m.get("label_source") or "")
        if m.get("review_driven") is False or "incident" in src:
            keep.add(d)
    return keep


def stratified_recall(pairs, cells_by_key):
    """co-read (b): caught / defects / recall per arm by label_source and by review_driven over the
    valid pairs (labels_meta of the pair's cells; a defect without metadata counts as "unlabelled")"""
    out = {"label_source": {}, "review_driven": {}}
    for p in pairs:
        meta = dict(cells_by_key[p["full"]["key"]]["labels_meta"])
        meta.update(cells_by_key[p["matched"]["key"]]["labels_meta"])
        for side, arm in (("full", PRIMARY_A), ("matched", PRIMARY_B)):
            got = set(p[side]["caught_ids"])
            for d in p[side]["defect_ids"]:
                m = meta.get(d) or {}
                rd = m.get("review_driven")
                for dim, k in (("label_source", str(m.get("label_source") or "unlabelled")),
                               ("review_driven", "true" if rd is True else "false" if rd is False else "unlabelled")):
                    st = out[dim].setdefault(k, {PRIMARY_A: {"caught": 0, "defects": 0}, PRIMARY_B: {"caught": 0, "defects": 0}})
                    st[arm]["defects"] += 1
                    st[arm]["caught"] += d in got
    for dim in out.values():
        for st in dim.values():
            for r in st.values():
                r["recall"] = r["caught"] / float(r["defects"]) if r["defects"] else None
    return out


def co_reads(cells, reg, upto, seed):
    """PREREGISTRATION §5 co-reads at look `upto` (groups 1 … upto; descriptive, never in decide /
    look_table): (a) the pipeline-independent Δ, (b) recall per arm by label_source and review_driven,
    (c) the cost-matched Δ — the exact-dollar trim on the pairs within the 25 % dollar tolerance —
    with the dollar-matching table of every pair. min_prs = 1: a co-read prints its figure below the
    6-PR decision minimum (the look's own decision rule is untouched)."""
    groups = reg.get("groups") or []
    tasks = set(t for g in groups[:upto] for t in g)
    lc = [c for c in cells if c["task"] in tasks]
    by_key = {c["key"]: c for c in lc}
    pi, pi_pairs = contrast(lc, PRIMARY_A, PRIMARY_B, seed, restrict_fn=pipeline_independent_fn, min_prs=1)
    if pi_pairs and all(p["full"]["defects"] == 0 for p in pi_pairs):
        pi = {"status": "no_labels_meta"}
    pairs, _ = common.make_pairs(lc, PRIMARY_A, PRIMARY_B)
    dm = dollar_table(pairs)
    ok = {(r["pr"], r["trial"]) for r in dm["pairs"] if r["within_25pct"]}
    ep, missing = exact_dollar_pairs([p for p in pairs if (p["pr"], p["trial"]) in ok], by_key)
    cm = primary_read(ep, seed, min_prs=1)
    return {"look": upto, "pipeline_independent": pi, "stratified": stratified_recall(pairs, by_key),
            "cost_matched": {"read": cm, "n_pairs_within_tolerance": len(ok), "pairs_without_sessions": missing,
                             "dollar_matching": dm}}


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
    # addendum 16 (iv): §5 reports the co-reads "beside the primary at every look and at the final" —
    # the final look covers every group
    out["co_reads"] = co_reads(cells, reg, len(groups), seed)
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
        if name in LABEL_SENSITIVITIES:
            label = LABEL_SENSITIVITIES[name]
            rc = regrade_cells(cells, sens_dir, label) if sens_dir else None
            if rc is None:
                res[name] = {"status": "not_provided"}
            else:
                res[name], lp = contrast(rc, PRIMARY_A, PRIMARY_B, seed)
                res[name]["label_dir"] = label
                res[name]["cells_regraded"] = sum(1 for c in rc if c["grade_path"])
                res[name]["cells_without_regrade"] = sum(1 for c in rc if not c["grade_path"])
                res[name]["descriptive"] = label_descriptive(lp)
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
        elif name in ("contaminated_reincluded_per_class", "class9_nonrepo_egress_reincluded"):
            # rounds 4–5 (PREREGISTRATION §12 addenda): per contamination class observed in the rows, the
            # primary read with the cells whose ONLY invalidity is a contamination of that class counted
            # valid (recall as graded), plus every class at once; the main filter stays unchanged.
            # The round-4 name runs only its class-9 non-repository member (same semantics), computed
            # once without the rest of the family (round 9, review DISS-C-002).
            res[name] = reinclude(cells, reg, seed, "network_egress:nonrepo") \
                if name == "class9_nonrepo_egress_reincluded" else reincluded_family(cells, reg, seed)
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


def md_positive_control(pc):
    if pc.get("status") == "not_run":
        return "\nPositive control: status `not_run`.\n"
    return "\nPositive control (%s; %s − %s, every group, saturated PRs exempt %s): %s%s; eligible pairs %d, " \
        "exposed open runs %d%s. Pre-addendum-10 label (G1 only): %s.\n" % (
            pc["rule"], OPEN_MOUNT, PRIMARY_A, ", ".join(pc.get("saturated_exempt") or []) or "none", pc["outcome"],
            "; Δ %s, 90 %% %s, expected %s" % (f4(pc["delta"]), iv(pc["ci90_t"]), f4(pc["expected_effect"]))
            if pc.get("status") == "ok" else " (status `%s`)" % pc.get("status"),
            pc["eligible_pairs"], pc["n_exposed_open_runs"],
            " — %s" % pc["consequence"] if pc.get("consequence") else "", pc["outcome_pre_addendum_10"])


def md_co_reads(co):
    L = ["## Co-reads (§5, reported at every look)\n\n",
         "Descriptive: they qualify the primary and never enter the decision.\n\n"]
    pi = co["pipeline_independent"]
    L.append(md_primary("(a) pipeline-independent %s − %s" % (PRIMARY_A, PRIMARY_B), pi) if pi.get("status") == "ok"
             else "| (a) pipeline-independent | status `%s` |\n" % pi.get("status"))
    cm = co["cost_matched"]
    L.append(md_primary("(c) cost-matched (exact-dollar trim, pairs within ±25 %)", cm["read"]))
    L.append("\n(b) Recall per arm by stratum (valid pairs):\n\n| stratum | %s caught / defects | recall | %s caught / defects | recall |\n"
             "|---|---|---|---|---|\n" % (PRIMARY_A, PRIMARY_B))
    for dim in ("label_source", "review_driven"):
        for k in sorted(co["stratified"][dim]):
            r = co["stratified"][dim][k]
            a, b = r[PRIMARY_A], r[PRIMARY_B]
            L.append("| %s = %s | %d / %d | %s | %d / %d | %s |\n" % (
                dim, k, a["caught"], a["defects"], f4(a["recall"]), b["caught"], b["defects"], f4(b["recall"])))
    dm = cm["dollar_matching"]
    L.append("\n(c) Dollar matching: %d of %d pairs within ±25 %% of the full cell's cost (pairs outside stay in the primary); "
             "trimmed pairs without per-session data %d.\n\n" % (dm["within"], dm["n"], cm["pairs_without_sessions"]))
    L.append("| PR | trial | cost full | cost matched | ratio | within |\n|---|---|---|---|---|---|\n")
    for r in dm["pairs"]:
        L.append("| %s | %d | %s | %s | %s | %s |\n" % (r["pr"], r["trial"], f4(r["cost_full"]), f4(r["cost_matched"]),
                                                      f4(r["ratio"]), "yes" if r["within_25pct"] else "no"))
    return "".join(L) + "\n"


COST_LEGEND = ("Cost per extra defect = cost increment ÷ extra defects, defined only when both are positive (§5); "
               "`dominated`: the full arm caught more defects for no more cost; `dominated_by_cost`: it cost more "
               "and caught no more; the value is then not reported and both increments are printed.")


# ---------------------------------------------------------------- the judged defect read (cycle-133 C-11, registration v2)
JUDGE_GRADER = "1.5.0"


def judge_view(c):
    """(judged caught ids | None, reason): a cell's defects with a blind `describes` verdict, or why it has none"""
    g = c.get("grade") or {}
    if g.get("grader_version") != JUDGE_GRADER or not isinstance(g.get("credited_pairs"), list):
        return None, "not_judged_grade"
    if g.get("unjudged_pairs") != 0:
        return None, "unjudged_pairs"
    caught = sorted({p.get("defect_key") for p in g["credited_pairs"]
                     if isinstance(p, dict) and p.get("verdict") == "describes" and p.get("blind") is True
                     and p.get("defect_key") in c["defect_ids"]}, key=lambda d: int(d[1:]))
    return caught, None


def judge_defects_read(cells, reg, seed, arm_a=PRIMARY_A, arm_b=PRIMARY_B):
    if reg.get("schema_version") != 2:
        raise InputError("--judge-defects is registered under the registration schema v2 chain (sdd.md C-11/C-12); the "
                         "registration is schema_version %r — register the read with registration.py v2" % reg.get("schema_version"))
    pairs, lost = common.make_pairs(cells, arm_a, arm_b)
    by_key = {c["key"]: c for c in cells}
    used, unjudged = [], []
    for p in pairs:
        va, ra = judge_view(by_key[p["full"]["key"]])
        vb, rb = judge_view(by_key[p["matched"]["key"]])
        if va is None or vb is None:
            unjudged.append({"pr": p["pr"], "trial": p["trial"], "a": ra, "b": rb})
            continue
        q = {"pr": p["pr"], "trial": p["trial"], "full": dict(p["full"], caught=len(va), caught_ids=va),
             "matched": dict(p["matched"], caught=len(vb), caught_ids=vb)}
        q["full"].pop("session1", None)
        q["matched"].pop("session1", None)
        used.append(q)
    per_arm, models, prompts, vfiles = {}, set(), set(), set()
    for arm in (arm_a, arm_b):
        cs = [c for c in cells if c["arm"] == arm and c["valid"]]
        e = {"cells_valid": len(cs), "cells_judged": 0, "credited_pairs": 0, "judged_pairs": 0, "judged_pairs_unblind": 0,
             "unjudged_pairs": 0, "defects": 0, "caught_grader": 0, "caught_judged": 0}
        for c in cs:
            g = c.get("grade") or {}
            if g.get("grader_version") != JUDGE_GRADER or not isinstance(g.get("credited_pairs"), list):
                continue
            j = g.get("judge") or {}
            models.update(x for x in j.get("judge_models") or [] if isinstance(x, str))
            prompts.update(x for x in j.get("judge_prompt_sha256") or [] if isinstance(x, str))
            if isinstance(j.get("verdicts_sha256"), str):
                vfiles.add(j["verdicts_sha256"])
            e["credited_pairs"] += len(g["credited_pairs"])
            for k in ("judged_pairs", "judged_pairs_unblind", "unjudged_pairs"):
                e[k] += g.get(k) if isinstance(g.get(k), int) and not isinstance(g.get(k), bool) else 0
            caught, why = judge_view(c)
            if caught is None:
                continue
            e["cells_judged"] += 1
            e["defects"] += c["defects"] or 0
            e["caught_grader"] += c["caught"] or 0
            e["caught_judged"] += len(caught)
        e["recall_grader"] = e["caught_grader"] / e["defects"] if e["defects"] else None
        e["recall_judged"] = e["caught_judged"] / e["defects"] if e["defects"] else None
        per_arm[arm] = e
    return {"label": "registered read (cycle-133 C-11; registration schema v2)", "grader_version": JUDGE_GRADER,
            "arm_a": arm_a, "arm_b": arm_b, "primary": primary_read(used, seed), "pairs_used": len(used),
            "pairs_lost": len(lost), "pairs_unjudged": sorted(unjudged, key=lambda x: (str(x["pr"]), x["trial"])),
            "per_arm": per_arm, "judge_models": sorted(models), "judge_prompt_sha256": sorted(prompts),
            "verdicts_sha256": sorted(vfiles)}


def md_judge_defects(j):
    L = ["## Judged defect read (%s)\n\n" % j["label"],
         "Contrast `%s` − `%s` on %d pair(s) with every credited pair judged (grader %s); %d valid pair(s) not fully "
         "judged; %d pair(s) lost to validity.\n\n" % (j["arm_a"], j["arm_b"], j["pairs_used"], j["grader_version"],
                                                       len(j["pairs_unjudged"]), j["pairs_lost"]),
         "| read | Δ | 95 % | 90 % | SE | PRs, pairs, defects | diag |\n|---|---|---|---|---|---|---|\n",
         md_primary("judged recall", j["primary"]), "\n",
         "| arm | cells valid | cells judged | credited pairs | judged (blind) | judged (unblind) | unjudged | grader recall | judged recall |\n"
         "|---|---|---|---|---|---|---|---|---|\n"]
    for arm in (j["arm_a"], j["arm_b"]):
        e = j["per_arm"][arm]
        L.append("| `%s` | %d | %d | %d | %d | %d | %d | %s | %s |\n" % (
            arm, e["cells_valid"], e["cells_judged"], e["credited_pairs"], e["judged_pairs"], e["judged_pairs_unblind"],
            e["unjudged_pairs"], f4(e["recall_grader"]), f4(e["recall_judged"])))
    L.append("\nJudge models: %s; prompt sha256: %s; verdicts files: %d.\n" % (
        ", ".join("`%s`" % m for m in j["judge_models"]) or "none",
        ", ".join("`%s`" % h[:12] for h in j["judge_prompt_sha256"]) or "none", len(j["verdicts_sha256"])))
    return "".join(L)


def render_md(doc):
    L = ["# cycle-132 reads — mode `%s`\n" % doc["mode"], "\n"]
    inp = doc["inputs"]
    L.append("Inputs: rows sha256 `%s`; grades sha256 `%s`; INPUTS.json sha256 `%s`; registration `%s`; seed %d; "
             "interval %s; validity rules %s.\n\n"
             % (inp["rows_sha256"], inp["grades_sha256"], inp["inputs_sha256"], inp.get("registration_sha256") or "unregistered",
                doc["seed"], doc["interval"], doc["validity"]))
    rp = inp.get("registrations")
    if rp:
        L.append("Rows by registration: %s.\n\n" % ", ".join("%s: %d" % (k[:12], n) for k, n in sorted(rp["rows_by_registration"].items())))
        L.append("Registration chain (current first): %s%s.\n\n" % (
            " → ".join("`%s`" % k[:12] for k in rp["chain"]),
            "; unresolved predecessor %s" % ", ".join("`%s`" % k[:12] for k in rp["unresolved_predecessor"])
            if rp["unresolved_predecessor"] else ""))
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
    if doc["mode"] == "judge_defects":
        L.append(md_judge_defects(doc["judge_defects"]))
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
    if doc.get("co_reads") and doc["mode"] != "final":
        L.append(md_co_reads(doc["co_reads"]))
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
        L.append("| cost per extra defect | value | extra defects | cost increment | status |\n|---|---|---|---|---|\n")
        for k in sorted(sec["cost_per_extra_defect"]):
            v = sec["cost_per_extra_defect"][k]
            dc = v["cost_full"] - v["cost_baseline"] if isinstance(v.get("cost_full"), (int, float)) and \
                isinstance(v.get("cost_baseline"), (int, float)) else None
            L.append("| %s | %s | %s | %s | %s |\n" % (k, f4(v.get("value")), f4(v.get("extra_defects")), f4(dc), v.get("status")))
        L.append("\n%s\n\n" % COST_LEGEND)
        L.append("\n| contrast | read |\n|---|---|\n")
        for k in ("review_only_vs_full", "pipeline_independent", "matched_fable"):
            v = sec[k]
            L.append("| %s | %s |\n" % (k, "Δ %s, 95 %% %s, PRs %s" % (f4(v["delta"]), iv(v["ci95"]), v["n_prs"])
                                        if v.get("status") == "ok" else "status `%s`" % v.get("status")))
        L.append(md_positive_control(sec["positive_control"]))
        if doc.get("void"):
            L.append("\n**VOID: the positive control's 90 % cluster-t interval lies entirely below 0 with verified exposure; "
                     "every other read is reported void.**\n")
        dm = sec["dollar_matching"]
        L.append("\nDollar matching: %d of %d pairs within ±25 %% of the full cell's cost.\n\n" % (dm["within"], dm["n"]))
        L.append("| PR | trial | cost full | cost matched | ratio | within |\n|---|---|---|---|---|---|\n")
        for r in dm["pairs"]:
            L.append("| %s | %d | %s | %s | %s | %s |\n" % (r["pr"], r["trial"], f4(r["cost_full"]), f4(r["cost_matched"]),
                                                          f4(r["ratio"]), "yes" if r["within_25pct"] else "no"))
        g = doc["guard"]
        L.append("\n25 %% guard: %s.\n\n" % ("INCONCLUSIVE BY DEGRADATION" if g["inconclusive_by_degradation"] else "not tripped"))
        if doc.get("co_reads"):
            L.append(md_co_reads(doc["co_reads"]))
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
            elif name == "contaminated_reincluded_per_class":
                ox = v.get("oracle_exposed") or {}
                if ox.get("status") == "ok":
                    for k, lab in (("read_only", "oracle-exposed, read form only"), ("diff", "oracle-exposed, diff form"),
                                   ("all", "oracle-exposed, every form")):
                        L.append(md_primary("re-included: %s" % lab, ox[k]))
                        if ox[k].get("status") == "ok":
                            L.append("| recall per arm (%s) | %s %s, %s %s |\n" % (
                                lab, PRIMARY_A, f4(ox[k].get("recall_full")), PRIMARY_B, f4(ox[k].get("recall_matched"))))
                    L.append("| oracle-exposed cells (arm / group / PR: form n) | %s |\n" % ("; ".join(
                        "%s / %s / %s: %s" % (arm, g, pr, ", ".join("%s %d" % (f, ox["counts"][arm][g][pr][f]) for f in sorted(ox["counts"][arm][g][pr])))
                        for arm in sorted(ox["counts"]) for g in sorted(ox["counts"][arm]) for pr in sorted(ox["counts"][arm][g])) or "none"))
                else:
                    L.append("| oracle-exposed re-inclusion | status `%s` |\n" % ox.get("status", "not_computed"))
                if v.get("status") != "ok":
                    L.append("| %s | status `%s` |\n" % (name, v.get("status")))
                else:
                    for cls in v["observed"]:
                        L.append(md_primary("re-included: %s" % cls, v["classes"][cls]))
                    L.append(md_primary("re-included: every class", v["all_classes"]))
                    for cls in v["observed"] + [None]:
                        r = v["classes"][cls] if cls else v["all_classes"]
                        if r.get("status") == "ok":
                            L.append("| recall per arm (%s) | %s %s, %s %s |\n" % (
                                cls or "every class", PRIMARY_A, f4(r.get("recall_full")), PRIMARY_B, f4(r.get("recall_matched"))))
                    L.append("| re-included cells (arm / group: class n) | %s |\n" % ("; ".join(
                        "%s / %s: %s" % (arm, g, ", ".join("%s %d" % (k, v["counts"][arm][g][k]) for k in sorted(v["counts"][arm][g])))
                        for arm in sorted(v["counts"]) for g in sorted(v["counts"][arm])) or "none"))
            elif name == "class9_nonrepo_egress_reincluded":
                L.append(md_primary(name, v))
            elif name == "pr11_in_out" and "pr11_out" in v:
                L.append(md_primary("pr-11 out", v["pr11_out"]))
            elif name in ("pair_level_permutation",):
                L.append("| %s | %s |\n" % (name, "p %s" % f4(v.get("p")) if v.get("status") == "ok" else "status `%s`" % v.get("status")))
            elif name == "ci90":
                L.append("| ci90 | %s |\n" % iv(v.get("ci90")))
            elif name == "pr_weighted":
                L.append("| pr_weighted | Δ %s %s |\n" % (f4(v.get("delta")), iv(v.get("ci95"))))
            elif name in LABEL_SENSITIVITIES:
                L.append(md_primary("%s (key dir `%s`)" % (name, LABEL_SENSITIVITIES[name]), v))
                ds = v.get("descriptive")
                if ds:
                    L.append("| %s: descriptive, valid pairs | %s %s / %s = %s; %s %s / %s = %s; PRs %d, pairs %d; "
                             "cells re-graded %d, without a re-grade %d |\n" % (
                                 name, PRIMARY_A, ds[PRIMARY_A]["caught"], ds[PRIMARY_A]["defects"], f4(ds[PRIMARY_A]["recall"]),
                                 PRIMARY_B, ds[PRIMARY_B]["caught"], ds[PRIMARY_B]["defects"], f4(ds[PRIMARY_B]["recall"]),
                                 ds["n_prs"], ds["n_pairs"], v["cells_regraded"], v["cells_without_regrade"]))
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
    m.add_argument("--judge-defects", action="store_true")
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
    if (a.look is not None or a.final or a.judge_defects) and not a.registration:
        ap.error("--registration is required for --look, --final and --judge-defects")
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
            if a.registration:
                doc["registrations"] = common.registration_provenance(a.registration, rows)
            os.makedirs(a.out, exist_ok=True)
            with open(os.path.join(a.out, "INPUTS.json"), "w", encoding="utf-8") as f:
                f.write(json.dumps(doc, sort_keys=True, indent=2) + "\n")
            return 0
        inputs = common.load_json(a.inputs, "INPUTS.json")
        common.validate_inputs(inputs, a.rows, rows, cells)
        reg, reg_sha, reg_prov = {}, None, None
        if a.registration:
            reg = common.load_json(a.registration, "REGISTRATION.json")
            reg_sha = common.validate_registration(a.registration, rows)
            reg_prov = common.registration_provenance(a.registration, rows)
        seed = a.seed if a.seed is not None else int(reg.get("seed", DEFAULT_SEED))
        doc = {"inputs": {"rows_sha256": common.sha256_file(a.rows), "grades_sha256": _grades_sha(cells),
                          "inputs_sha256": common.sha256_file(a.inputs), "registration_sha256": reg_sha,
                          "n_rows": len(rows), "registrations": reg_prov},
               "seed": seed, "interval": INTERVAL, "validity": VALIDITY}
        if a.judge_defects:
            doc.update(mode="judge_defects", judge_defects=judge_defects_read(cells, reg, seed, a.arm_a, a.arm_b))
        elif a.placebo:
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
                doc["co_reads"] = co_reads(cells, reg, a.look, seed)
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
