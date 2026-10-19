"""contingency.py — deliverable 1: per-defect paired contingency (bare vs full, 19 defects × 3 trials), exact
McNemar on the paired defect-trials, the pre-registered defect-level paired bootstrap, a cluster bootstrap by PR,
and the diff-size covariate. Writes contingency.json + contingency.md."""
import json, math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

SEED, B, LEVEL = 20261015, 10000, 0.90
DIFF_LINES = {"pr-05": 127, "pr-08": 138, "pr-12": 1077, "pr-13": 5880}
DIFF_FILES = {"pr-05": 3, "pr-08": 3, "pr-12": 15, "pr-13": 54}

def load():
    recs = json.load(open(os.path.join(C.DATA, "runs.json")))
    cells = {}  # (task, trial) -> {arm: set(caught positions)}
    for r in recs:
        caught = {k for k, d in r["per_defect"].items() if d["caught"]}
        cells.setdefault((r["task"], r["trial"]), {})[r["arm"]] = caught
    return recs, cells

def mcnemar_exact(b, c):
    """two-sided exact binomial on the discordant pairs (b = bare only, c = full only)"""
    n = b + c
    if n == 0: return 1.0
    k = min(b, c)
    p = sum(math.comb(n, i) for i in range(0, k + 1)) / 2 ** n
    return min(1.0, 2 * p)

def ci(vals, level=LEVEL):
    vals = sorted(vals); lo = (1 - level) / 2
    return vals[int(lo * len(vals))], vals[min(len(vals) - 1, int((1 - lo) * len(vals)))]

def main():
    recs, cells = load()
    tasks = ["review-01", "review-02", "review-03", "review-04"]
    mans = {t: C.load_manifest(C.TASK_PR[t]) for t in tasks}
    # per defect: over trials, bare caught count, full caught count, paired cells
    rows = []
    paired = []  # (task, defect, trial, bare, full)
    for t in tasks:
        pos = C.defect_positions(mans[t])
        for k, d in pos.items():
            bb = ff = both = neither = bonly = fonly = 0
            for tr in (1, 2, 3):
                b = k in cells[(t, tr)]["a0_bare"]; f = k in cells[(t, tr)]["a1_full"]
                paired.append((t, k, tr, b, f))
                bb += b; ff += f; both += b and f; neither += (not b) and (not f); bonly += b and not f; fonly += f and not b
            rows.append({"task": t, "pr": C.TASK_PR[t], "defect": k, "id": d["id"], "severity": d.get("severity"), "category": d.get("category"),
                         "file": d["file"], "bare": bb, "full": ff, "both": both, "neither": neither, "bare_only": bonly, "full_only": fonly})
    tot = {x: sum(r[x] for r in rows) for x in ("bare", "full", "both", "neither", "bare_only", "full_only")}
    n_pairs = len(paired)
    p_mcnemar = mcnemar_exact(tot["bare_only"], tot["full_only"])
    # per-PR McNemar
    per_pr = {}
    for t in tasks:
        rs = [r for r in rows if r["task"] == t]
        b = sum(r["bare_only"] for r in rs); c = sum(r["full_only"] for r in rs)
        per_pr[t] = {"pr": C.TASK_PR[t], "defects": len(rs), "bare": sum(r["bare"] for r in rs), "full": sum(r["full"] for r in rs),
                     "bare_only": b, "full_only": c, "both": sum(r["both"] for r in rs), "neither": sum(r["neither"] for r in rs),
                     "p_mcnemar_exact": mcnemar_exact(b, c), "diff_lines": DIFF_LINES[C.TASK_PR[t]], "files": DIFF_FILES[C.TASK_PR[t]]}
    # pre-registered: defect-level paired bootstrap on per-defect rates (mean over 3 trials), 19 units
    rnd = random.Random(SEED)
    per_def = [((r["full"] - r["bare"]) / 3.0) for r in rows]
    point = sum(per_def) / len(per_def)
    boot = []
    for _ in range(B):
        s = [per_def[rnd.randrange(len(per_def))] for _ in per_def]
        boot.append(sum(s) / len(s))
    def_ci = ci(boot)
    bs = sorted(boot); def_ci_alt = (bs[int(0.05 * B)], bs[int(0.95 * B) - 1])
    # cluster bootstrap by PR: resample the 4 PRs with replacement; statistic = defect-pooled difference (and task-mean)
    rnd = random.Random(SEED + 1)
    by_task = {t: [((r["full"] - r["bare"]) / 3.0) for r in rows if r["task"] == t] for t in tasks}
    cb_pooled, cb_taskmean = [], []
    for _ in range(B):
        pick = [tasks[rnd.randrange(4)] for _ in range(4)]
        vals = [v for t in pick for v in by_task[t]]
        cb_pooled.append(sum(vals) / len(vals))
        cb_taskmean.append(sum(sum(by_task[t]) / len(by_task[t]) for t in pick) / 4)
    cl_ci = ci(cb_pooled); cl_tm_ci = ci(cb_taskmean)
    task_means = {t: sum(by_task[t]) / len(by_task[t]) for t in tasks}
    # exact enumeration of the 4^4 = 256 PR-cluster resamples (with the pooled statistic), for honesty about the support
    import itertools
    enum = sorted(set(round(sum(v for t in pick for v in by_task[t]) / sum(len(by_task[t]) for t in pick), 6) for pick in itertools.product(tasks, repeat=4)))
    # leave-one-PR-out
    loo = {}
    for t in tasks:
        vals = [v for u in tasks if u != t for v in by_task[u]]
        loo[t] = sum(vals) / len(vals)
    # diff-size covariate: per PR, catch rate per arm vs lines
    cov = []
    for t in tasks:
        rs = [r for r in rows if r["task"] == t]
        cov.append({"task": t, "pr": C.TASK_PR[t], "diff_lines": DIFF_LINES[C.TASK_PR[t]], "files": DIFF_FILES[C.TASK_PR[t]],
                    "defects": len(rs), "bare_rate": sum(r["bare"] for r in rs) / (3 * len(rs)), "full_rate": sum(r["full"] for r in rs) / (3 * len(rs)),
                    "lift": (sum(r["full"] for r in rs) - sum(r["bare"] for r in rs)) / (3 * len(rs))})
    # by severity / category
    def grp(key):
        g = {}
        for r in rows:
            e = g.setdefault(r[key] or "?", {"defects": 0, "bare": 0, "full": 0})
            e["defects"] += 1; e["bare"] += r["bare"]; e["full"] += r["full"]
        return g
    out = {"n_defects": len(rows), "n_defect_trials": n_pairs, "totals": tot, "mcnemar_exact_p_two_sided": p_mcnemar,
           "per_pr": per_pr, "per_defect": rows,
           "preregistered_defect_bootstrap": {"point": point, "ci90": def_ci, "resamples": B, "seed": SEED, "units": "19 defects (per-defect mean over 3 trials)"},
           "cluster_bootstrap_by_pr": {"pooled_point": point, "pooled_ci90": cl_ci, "task_mean_point": sum(task_means.values()) / 4, "task_mean_ci90": cl_tm_ci,
                                       "distinct_resample_values_pooled": len(enum), "support_min": enum[0], "support_max": enum[-1], "resamples": B, "seed": SEED + 1},
           "leave_one_pr_out_pooled": loo, "task_means": task_means, "covariate": cov, "by_severity": grp("severity"), "by_category": grp("category")}
    json.dump(out, open(os.path.join(C.OUT, "contingency.json"), "w"), indent=1)
    # markdown
    L = []
    L.append("# Deliverable 1 — per-defect contingency, bare vs full (suite v2, valid cells)\n")
    L.append(f"Source: the 24 valid run directories (12 a0_bare, 12 a1_full) re-graded with the grader's own citation rule (`scripts/extract.py`; cross-check against every grade.json: identical). 19 planted defects × 3 paired trials = {n_pairs} defect-trials. Script: `scripts/contingency.py` (seed {SEED}, {B} resamples, 90 % intervals).\n")
    L.append("## Pooled paired table (defect-trials)\n")
    L.append("| | full caught | full missed | total |\n|---|---|---|---|")
    L.append(f"| **bare caught** | {tot['both']} | {tot['bare_only']} | {tot['bare']} |")
    L.append(f"| **bare missed** | {tot['full_only']} | {tot['neither']} | {n_pairs - tot['bare']} |")
    L.append(f"| **total** | {tot['full']} | {n_pairs - tot['full']} | {n_pairs} |\n")
    L.append(f"- bare catch rate {tot['bare']}/{n_pairs} = {tot['bare']/n_pairs:.3f}; full {tot['full']}/{n_pairs} = {tot['full']/n_pairs:.3f}; difference (pooled) {(tot['full']-tot['bare'])/n_pairs:+.3f}")
    L.append(f"- discordant pairs: full-only {tot['full_only']}, bare-only {tot['bare_only']}; **exact McNemar (two-sided binomial on the discordant pairs) p = {p_mcnemar:.4f}**")
    L.append("- caveat: the 57 defect-trials are not independent (three trials of one defect share the defect; defects share a PR); the McNemar p treats them as independent pairs and is therefore optimistic. The intervals below are the honest view.\n")
    L.append("## Per PR\n")
    L.append("| task | PR | diff lines | files | defects | bare caught /9 or /24 or /15 | full | both | full-only | bare-only | neither | exact McNemar p |\n|---|---|---|---|---|---|---|---|---|---|---|---|")
    for t in tasks:
        e = per_pr[t]; n = 3 * e["defects"]
        L.append(f"| {t} | {e['pr']} | {e['diff_lines']} | {e['files']} | {e['defects']} | {e['bare']}/{n} | {e['full']}/{n} | {e['both']} | {e['full_only']} | {e['bare_only']} | {e['neither']} | {e['p_mcnemar_exact']:.3f} |")
    L.append("\n## Per defect (over 3 trials)\n")
    L.append("| task | defect | id | sev | category | bare | full | both | full-only | bare-only | neither |\n|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        L.append(f"| {r['task']} | {r['defect']} | `{r['id'][:34]}` | {r['severity']} | {r['category']} | {r['bare']} | {r['full']} | {r['both']} | {r['full_only']} | {r['bare_only']} | {r['neither']} |")
    L.append("\n## Intervals\n")
    L.append(f"- **Pre-registered read (reproduced):** defect-level paired bootstrap over the 19 defects (each defect's mean over its 3 trials), 90 %: **{point:+.3f} [{def_ci[0]:+.3f}, {def_ci[1]:+.3f}]** (the shipped report: +0.263 [+0.158, +0.386]; same statistic, independent implementation; the bootstrap distribution over 19 units is discrete and the 5 % point sits on a jump between 8/57 = +0.140 and 9/57 = +0.158 — one defect-trial — so the two lower bounds are the same number read on either side of the jump; upper bound identical).")
    L.append(f"- **Cluster bootstrap by PR (4 clusters, resampled with replacement, defect-pooled statistic):** {point:+.3f} [{cl_ci[0]:+.3f}, {cl_ci[1]:+.3f}]; task-mean statistic {sum(task_means.values())/4:+.3f} [{cl_tm_ci[0]:+.3f}, {cl_tm_ci[1]:+.3f}]. With four clusters the resampling distribution has only {len(enum)} distinct values (support {enum[0]:+.3f} … {enum[-1]:+.3f}); the interval's lower end is where resamples drop pr-12 — **this is the honest uncertainty with four PRs: the effect is positive in every resample that keeps pr-12 and ≈ 0 in those that do not.**")
    L.append(f"- Leave-one-PR-out (pooled): " + ", ".join(f"without {t} ({C.TASK_PR[t]}) {v:+.3f}" for t, v in loo.items()) + ".")
    L.append(f"- Task means: " + ", ".join(f"{t} {v:+.3f}" for t, v in task_means.items()) + ".\n")
    L.append("## Diff-size covariate\n")
    L.append("| task | PR | diff lines | files | defects | bare rate | full rate | lift |\n|---|---|---|---|---|---|---|---|")
    for c in cov:
        L.append(f"| {c['task']} | {c['pr']} | {c['diff_lines']} | {c['files']} | {c['defects']} | {c['bare_rate']:.3f} | {c['full_rate']:.3f} | {c['lift']:+.3f} |")
    L.append("\nReading: the lift is not monotone in diff size — zero on the two ~130-line PRs where bare is already at or near 1.0 (ceiling), largest on the 1,077-line PR, and small on the 5,880-line PR where both arms are low and the dissent never ran (budget gate). Bare's catch rate falls with diff size (1.00, 0.89, 0.25, 0.53); full's falls less (1.00, 1.00, 0.75, 0.67). Four points cannot separate 'size' from 'this PR'.\n")
    L.append("## By severity and category (defect-trials caught)\n")
    L.append("| severity | defects | bare | full |\n|---|---|---|---|")
    for k, e in sorted(out["by_severity"].items()):
        L.append(f"| {k} | {e['defects']} | {e['bare']}/{3*e['defects']} | {e['full']}/{3*e['defects']} |")
    L.append("\n| category | defects | bare | full |\n|---|---|---|---|")
    for k, e in sorted(out["by_category"].items()):
        L.append(f"| {k} | {e['defects']} | {e['bare']}/{3*e['defects']} | {e['full']}/{3*e['defects']} |")
    open(os.path.join(C.OUT, "contingency.md"), "w").write("\n".join(L) + "\n")
    print(json.dumps({k: out[k] for k in ("totals", "mcnemar_exact_p_two_sided", "preregistered_defect_bootstrap", "cluster_bootstrap_by_pr", "leave_one_pr_out_pooled", "task_means")}, indent=1))

if __name__ == "__main__":
    main()
