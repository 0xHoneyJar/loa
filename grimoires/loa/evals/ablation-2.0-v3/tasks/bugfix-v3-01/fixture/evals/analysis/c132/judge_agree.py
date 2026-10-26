#!/usr/bin/env python3
"""judge_agree.py — grader vs blind judge agreement and the Horvitz–Thompson corrected figures.

Usage:
  python3 -I evals/analysis/c132/judge_agree.py --key key.json --labels labels.json --rows F --out DIR
      [--seed N] [--boot 2000]

Inputs: key.json from evals/harness/judge-sample.sh (the universe, strata with N_s, the sampled
items, the cells), the judge's labels.json {J0001: {verdict, note}} — pair items (credited,
near-miss, far-miss) take describes | partially | does-not-describe, stray items real | style |
wrong | not-a-finding — and the rows (the validity filter of common.py on the row fields; only
valid cells enter the per-arm figures).

Reads (sdd.md §1.4 "Judge sampler and agreement", prd.md FR-4):
  * per stratum and pooled agreement between grader credit and judge `describes` — strict
    (`partially` counts as disagreement) and lenient (`partially` counts as agreement) — unweighted
    and inverse-probability weighted (weight N_s / n'_s, n'_s = the judged items of the stratum;
    an unjudged item is reported and leaves the stratum's effective sample);
  * Cohen's kappa (grader credit vs judge describes; lenient: describes or partially) with a
    seeded item-bootstrap 95 % percentile interval; the confusion table per stratum;
  * judge-corrected recall and precision per arm as Horvitz–Thompson estimates: every judged unit
    updates its defect's credit with weight 1/π'_s — a rejected credited unit removes 1/m of the
    defect's credit (m = the defect's credited units in the cell), an accepted near-miss or
    far-miss unit adds 1/q (q = the defect's uncredited units in the cell; only for a defect the
    grader did not credit); precision: a rejected credited region removes 1/m_r (m_r = the region's
    credited units), an accepted near-miss region adds 1, a stray rated `real` adds 1, over the
    cell's distinct regions; unsampled units keep the grader's decision; PR-cluster bootstrap
    intervals; strict (accept = describes) and lenient (describes or partially);
  * real_strays: the strays rated `real`, merged by (task, file, lines), with the cells that cited
    them — reads-c132.py's "judge-confirmed strays as defects" sensitivity.

Outputs DIR/result.json + DIR/result.md (sorted keys, %.4f, no timestamps). Exit 0 written;
1 inputs invalid (an unknown item or verdict); 2 usage.
"""
import argparse
import os
import random
import sys

if __package__ in (None, ""):
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from c132 import common, stats  # noqa: E402
from c132.common import InputError  # noqa: E402
from c132.reads import dumps, f4, iv  # noqa: E402

PAIR_VERDICTS = ("describes", "partially", "does-not-describe")
STRAY_VERDICTS = ("real", "style", "wrong", "not-a-finding")


def stratum_of(u):
    return "%s|%s|%s" % (u["arm"], u["task"], u["class"])


def validate(key, labels):
    items = key.get("items") or {}
    errs = []
    for jid in sorted(labels):
        if jid not in items:
            errs.append("label for an unknown item %s" % jid)
            continue
        v = (labels[jid] or {}).get("verdict")
        ok = STRAY_VERDICTS if items[jid]["class"] == "stray" else PAIR_VERDICTS
        if v not in ok:
            errs.append("%s: verdict %r not in %s" % (jid, v, "|".join(ok)))
    if errs:
        raise InputError("; ".join(errs))


def agree(grader_credit, v, lenient):
    if v == "partially":
        return lenient
    return grader_credit == (v == "describes")


def accept(v, lenient):
    return v == "describes" or (lenient and v == "partially")


def kappa_table(pairs, lenient):
    t = [[0, 0], [0, 0]]
    for g, v in pairs:
        j = accept(v, lenient)
        t[0 if g else 1][0 if j else 1] += 1
    return t


def kappa_boot(pairs, lenient, n, seed):
    rng = random.Random(seed)
    ks = []
    m = len(pairs)
    for _ in range(n):
        k = stats.kappa(kappa_table([pairs[rng.randrange(m)] for _ in range(m)], lenient))
        if k is not None:
            ks.append(k)
    ks.sort()
    return [stats.quantile(ks, 0.025), stats.quantile(ks, 0.975)] if ks else None


def corrections(key, labels, lenient):
    """per cell: (Δ caught, Δ positive regions) from the judged units, each weighted 1/π'_s"""
    uni = key["universe"]
    items = key["items"]
    judged_by_stratum = {}
    for jid, it in items.items():
        if jid in labels:
            judged_by_stratum[stratum_of(it)] = judged_by_stratum.get(stratum_of(it), 0) + 1
    m_def, q_def, m_reg = {}, {}, {}
    for u in uni:
        if u["class"] == "credited":
            m_def[(u["cell"], u["defect"])] = m_def.get((u["cell"], u["defect"]), 0) + 1
            rk = (u["cell"], tuple(u["region"]))
            m_reg[rk] = m_reg.get(rk, 0) + 1
        elif u["class"] in ("near-miss", "far-miss"):
            q_def[(u["cell"], u["defect"])] = q_def.get((u["cell"], u["defect"]), 0) + 1
    credited = {(c, d) for c, cell in key["cells"].items() for d in cell["credited"]}
    near_regions_counted = set()
    out = {}
    for jid, it in sorted(items.items()):
        if jid not in labels:
            continue
        v = labels[jid]["verdict"]
        st = key["strata"][stratum_of(it)]
        n_eff = judged_by_stratum.get(stratum_of(it), 0)
        w = st["N"] / float(n_eff) if n_eff else 0.0
        dc = dp = 0.0
        cls = it["class"]
        if cls == "credited":
            if not accept(v, lenient):
                dc = -1.0 / m_def[(it["cell"], it["defect"])]
                dp = -1.0 / m_reg[(it["cell"], tuple(it["region"]))]
        elif cls in ("near-miss", "far-miss"):
            if accept(v, lenient) and (it["cell"], it["defect"]) not in credited:
                dc = 1.0 / q_def[(it["cell"], it["defect"])]
            if cls == "near-miss" and accept(v, lenient):
                rk = (it["cell"], tuple(it["region"]))
                if rk not in near_regions_counted:
                    near_regions_counted.add(rk)
                    dp = 1.0
        elif cls == "stray" and v == "real":
            dp = 1.0
        a = out.setdefault(it["cell"], [0.0, 0.0])
        a[0] += w * dc
        a[1] += w * dp
    return out


def per_arm(key, valid_cells, corr, seed, n):
    """{arm: {recall, precision, grader figures, PR-cluster intervals}}"""
    by_arm = {}
    for ck, cell in sorted(key["cells"].items()):
        if ck not in valid_cells:
            continue
        uni_regions = {tuple(u["region"]) for u in key["universe"] if u["cell"] == ck and u["class"] != "far-miss"}
        cred_regions = {tuple(u["region"]) for u in key["universe"] if u["cell"] == ck and u["class"] == "credited"}
        dc, dp = corr.get(ck, [0.0, 0.0])
        rec = (cell["task"], len(cell["credited"]) + dc, cell["defects"], len(cred_regions) + dp, len(uni_regions),
               len(cell["credited"]), len(cred_regions))
        by_arm.setdefault(cell["arm"], []).append(rec)
    out = {}
    for arm, recs in sorted(by_arm.items()):
        def figs(rs):
            d = sum(r[2] for r in rs)
            g = sum(r[4] for r in rs)
            return (sum(r[1] for r in rs) / d if d else None, sum(r[3] for r in rs) / g if g else None)
        rcl, prc = figs(recs)
        d = sum(r[2] for r in recs)
        g = sum(r[4] for r in recs)
        tasks = sorted({r[0] for r in recs})
        rng = random.Random("%s:%s" % (seed, arm))
        rb, pb = [], []
        for _ in range(n):
            pick = [tasks[rng.randrange(len(tasks))] for _ in tasks]
            rs = [r for t in pick for r in recs if r[0] == t]
            a, b = figs(rs)
            if a is not None:
                rb.append(a)
            if b is not None:
                pb.append(b)
        rb.sort()
        pb.sort()
        out[arm] = {"recall": rcl, "precision": prc, "cells": len(recs), "prs": len(tasks),
                    "recall_grader": sum(r[5] for r in recs) / d if d else None,
                    "precision_grader": sum(r[6] for r in recs) / g if g else None,
                    "recall_ci95": [stats.quantile(rb, 0.025), stats.quantile(rb, 0.975)] if rb else None,
                    "precision_ci95": [stats.quantile(pb, 0.025), stats.quantile(pb, 0.975)] if pb else None}
    return out


def run(key, labels, rows, seed, n):
    validate(key, labels)
    valid = set()
    for r in rows:
        c = common.build_cell(r, None)
        if c["valid"]:
            valid.add(c["key"])
    items = key["items"]
    strata = {}
    pairs_all = []
    unjudged = sorted(j for j in items if j not in labels)
    for jid, it in sorted(items.items()):
        s = stratum_of(it)
        st = strata.setdefault(s, {"N": key["strata"][s]["N"], "n": key["strata"][s]["n"], "judged": 0,
                                   "agree_strict": 0, "agree_lenient": 0, "confusion": {}})
        if jid not in labels:
            continue
        v = labels[jid]["verdict"]
        st["judged"] += 1
        g = bool(it["grader_credit"])
        cell = st["confusion"].setdefault("grader_credit" if g else "grader_no_credit", {})
        cell[v] = cell.get(v, 0) + 1
        if it["class"] != "stray":
            st["agree_strict"] += agree(g, v, False)
            st["agree_lenient"] += agree(g, v, True)
            pairs_all.append((g, v))
    pooled = {}
    for mode in ("strict", "lenient"):
        num = den = wnum = wden = 0.0
        for s, st in strata.items():
            if s.endswith("|stray") or not st["judged"]:
                continue
            a = st["agree_" + mode]
            num += a
            den += st["judged"]
            w = st["N"] / float(st["judged"])
            wnum += w * a
            wden += w * st["judged"]
        pooled[mode] = {"unweighted": num / den if den else None, "weighted": wnum / wden if wden else None}
    for s, st in strata.items():
        if st["judged"] and not s.endswith("|stray"):
            st["agreement_strict"] = st["agree_strict"] / float(st["judged"])
            st["agreement_lenient"] = st["agree_lenient"] / float(st["judged"])
    kap = {}
    for mode, len_ in (("strict", False), ("lenient", True)):
        t = kappa_table(pairs_all, len_)
        kap[mode] = {"kappa": stats.kappa(t), "ci95": kappa_boot(pairs_all, len_, n, seed) if pairs_all else None,
                     "table": {"grader_credit": {"judge_yes": t[0][0], "judge_no": t[0][1]},
                               "grader_no_credit": {"judge_yes": t[1][0], "judge_no": t[1][1]}}}
    corrected = {}
    for mode, len_ in (("strict", False), ("lenient", True)):
        corrected[mode] = per_arm(key, valid, corrections(key, labels, len_), seed, n)
    real = {}
    for jid, it in sorted(items.items()):
        if it["class"] == "stray" and labels.get(jid, {}).get("verdict") == "real":
            reg = it["region"]
            k = (it["task"], reg[0].split("head/", 1)[-1], reg[1], reg[2])
            real.setdefault(k, set()).add(it["cell"])
    real_strays = [{"pr": k[0], "region": [k[1], k[2], k[3]], "cells": sorted(v)} for k, v in sorted(real.items())]
    return {"schema_version": 1, "seed": seed, "boot": n, "items": len(items), "judged": len(items) - len(unjudged),
            "unjudged": unjudged, "strata": strata, "pooled_agreement": pooled, "kappa": kap,
            "corrected": corrected["strict"], "corrected_lenient": corrected["lenient"], "real_strays": real_strays}


def grader_title(rows):
    """the grader version(s) on the rows, sorted and comma-joined; "" when no row carries one"""
    vs = sorted({str(r["grader_version"]) for r in rows or () if isinstance(r, dict) and r.get("grader_version")})
    return ", ".join(vs)


def render_md(doc, rows=None):
    gv = grader_title(rows)
    L = ["# Grader %svs the blind judge\n\n" % (gv + " " if gv else ""),
         "%d items sampled, %d judged; seed %d; %d bootstrap resamples. The grader stays the primary; the corrected figures are sensitivities.\n\n"
         % (doc["items"], doc["judged"], doc["seed"], doc["boot"])]
    for mode in ("strict", "lenient"):
        k = doc["kappa"][mode]
        p = doc["pooled_agreement"][mode]
        L.append("- %s: agreement %s unweighted, %s weighted; kappa %s %s\n" % (
            mode, f4(p["unweighted"]), f4(p["weighted"]), f4(k["kappa"]), iv(k["ci95"])))
    L.append("\n## Per stratum\n\n| stratum | N | n | judged | agreement strict | lenient | confusion |\n|---|---|---|---|---|---|---|\n")
    for s in sorted(doc["strata"]):
        st = doc["strata"][s]
        conf = "; ".join("%s: %s" % (g, ", ".join("%s %d" % (v, st["confusion"][g][v]) for v in sorted(st["confusion"][g])))
                         for g in sorted(st["confusion"]))
        L.append("| %s | %d | %d | %d | %s | %s | %s |\n" % (s, st["N"], st["n"], st["judged"], f4(st.get("agreement_strict")),
                                                           f4(st.get("agreement_lenient")), conf or "—"))
    for title, key in (("strict", "corrected"), ("lenient", "corrected_lenient")):
        L.append("\n## Judge-corrected recall and precision per arm (%s, Horvitz–Thompson)\n\n"
                 "| arm | cells | PRs | recall (grader) | recall corrected | 95 %% | precision (grader) | precision corrected | 95 %% |\n"
                 "|---|---|---|---|---|---|---|---|---|\n" % title)
        for arm in sorted(doc[key]):
            a = doc[key][arm]
            L.append("| %s | %d | %d | %s | %s | %s | %s | %s | %s |\n" % (
                arm, a["cells"], a["prs"], f4(a["recall_grader"]), f4(a["recall"]), iv(a["recall_ci95"]),
                f4(a["precision_grader"]), f4(a["precision"]), iv(a["precision_ci95"])))
    L.append("\nStrays rated real: %d.\n" % len(doc["real_strays"]))
    return "".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="judge_agree.py")
    ap.add_argument("--key", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--rows", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--boot", type=int, default=2000)
    try:
        a = ap.parse_args(sys.argv[1:] if argv is None else argv)
    except SystemExit as e:
        return 2 if e.code else 0
    try:
        key = common.load_json(a.key, "key.json")
        labels = common.load_json(a.labels, "labels.json")
        rows = common.load_rows(a.rows)
        doc = run(key, labels, rows, a.seed if a.seed is not None else int(key.get("seed", 0)), a.boot)
    except InputError as e:
        sys.stderr.write("judge_agree: inputs invalid: %s\n" % e)
        return 1
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "result.json"), "w", encoding="utf-8") as f:
        f.write(dumps(doc))
    with open(os.path.join(a.out, "result.md"), "w", encoding="utf-8") as f:
        f.write(render_md(doc, rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
