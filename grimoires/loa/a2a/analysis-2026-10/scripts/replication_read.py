"""replication_read.py — the pre-registered read of batch replication-01 (a0_bare vs a1_full on review-r17 = pr-17 and
review-r18 = pr-18), from the run directories: per-defect detection under the grader's rule (extract.extract), the
defect-level paired bootstrap over the 28 defects, pairwise exclusion, the 25 % guard, the degenerate check; beside it
(deciding nothing): per PR, 2-cluster bootstrap, precision/false positives, cost and wall-clock, dissent status per gate,
the same-function window sensitivity, and the KF-049 oracle scan with the read repeated without exposed cells."""
import json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
import extract as X
import oracle_scan as O

BATCH = os.path.join(C.REPO, "evals/results/ablation-2.0/replication-01")
ROWS = os.path.join(C.REPO, "evals/results/ablation-2.0/runs.jsonl")
TASKS = {"review-r17": "pr-17", "review-r18": "pr-18"}
SEED, B = 20261015, 10000

def rows():
    out = {}
    for line in open(ROWS, encoding="utf-8"):
        try: r = json.loads(line)
        except ValueError: continue
        if r.get("batch") == "replication-01": out[r["run_id"]] = r
    return out

def run_dirs():
    runs = []
    for arm in ("a0_bare", "a1_full"):
        d = os.path.join(BATCH, arm)
        if not os.path.isdir(d): continue
        for name in sorted(os.listdir(d)):
            p = os.path.join(d, name)
            if not os.path.isdir(p) or not os.path.isfile(os.path.join(p, "grade.json")): continue
            task, _, t = name.partition("-t"); trial = int(t.split("-")[0])
            runs.append({"arm": arm, "task": task, "pr": TASKS[task], "trial": trial, "run_id": f"replication-01-{arm}-{task}-t{trial}", "run_dir": p})
    # keep the highest -rK per cell
    best = {}
    for r in runs:
        best[(r["arm"], r["task"], r["trial"])] = r
    return sorted(best.values(), key=lambda r: (r["task"], r["trial"], r["arm"]))

def ci(v, lo=0.05, hi=0.95):
    v = sorted(v); return v[int(lo * len(v))], v[int(hi * len(v)) - 1]

def main(partial=False):
    rs = rows(); runs = run_dirs(); head_cache = {}
    recs = [X.extract(r, head_cache) for r in runs]
    for rec in recs:
        row = rs.get(rec["run_id"]); rec["row_status"] = row.get("status") if row else "no-row"; rec["row_degraded"] = row.get("degraded") if row else None
    cells = {(r["task"], r["trial"]): {} for r in recs}
    for r in recs: cells[(r["task"], r["trial"])][r["arm"]] = r
    valid = {k: v for k, v in cells.items() if len(v) == 2 and all(x["row_status"] == "completed" and not x["row_degraded"] for x in v.values())}
    excl = {a: sum(1 for k, v in cells.items() if a in v and (v[a]["row_status"] != "completed" or v[a]["row_degraded"])) for a in ("a0_bare", "a1_full")}
    def read(cellset, label):
        per_def = []; per_task = {}
        for task, pr in TASKS.items():
            man = C.load_manifest(pr); n = len(man["defects"]); tb = tf = tn = 0
            for i in range(1, n + 1):
                k = f"d{i}"; diffs = []
                for tr in (1, 2, 3):
                    v = cellset.get((task, tr))
                    if not v: continue
                    b = v["a0_bare"]["per_defect"][k]["caught"]; f = v["a1_full"]["per_defect"][k]["caught"]
                    diffs.append(f - b); tb += b; tf += f; tn += 1
                if diffs: per_def.append(sum(diffs) / len(diffs))
            per_task[task] = {"bare": tb, "full": tf, "n": tn, "defects": n}
        if not per_def: return {"label": label, "n_defects": 0}
        rnd = random.Random(SEED); boots = []
        for _ in range(B):
            s = [per_def[rnd.randrange(len(per_def))] for _ in per_def]; boots.append(sum(s) / len(s))
        lo, hi = ci(boots)
        degenerate = (max(per_def) - min(per_def)) < 1e-12
        # 2-cluster (PR) bootstrap, pooled statistic
        rnd2 = random.Random(SEED + 1); by = {}
        for task, pr in TASKS.items():
            man = C.load_manifest(pr); by[task] = []
            for i in range(1, len(man["defects"]) + 1):
                k = f"d{i}"; d_ = [cellset[(task, tr)]["a1_full"]["per_defect"][k]["caught"] - cellset[(task, tr)]["a0_bare"]["per_defect"][k]["caught"] for tr in (1, 2, 3) if (task, tr) in cellset]
                if d_: by[task].append(sum(d_) / len(d_))
        cb = []
        for _ in range(B):
            pick = [list(TASKS)[rnd2.randrange(2)] for _ in range(2)]; vals = [v for t in pick for v in by[t]]
            cb.append(sum(vals) / len(vals) if vals else 0.0)
        clo, chi = ci(cb)
        return {"label": label, "n_defects": len(per_def), "point": sum(per_def) / len(per_def), "ci90": [lo, hi], "degenerate": degenerate,
                "cluster2_ci90": [clo, chi], "per_task": per_task,
                "established": (lo > 0) and not degenerate}
    plain = read(valid, "pre-registered (valid cells)")
    # labelled sensitivity (decides nothing): contaminated rows whose contamination is the grader's repo_name scan firing on
    # the PR's own quoted content (KF-046, hand-read 2026-10-19) treated as valid
    def hand_read_ok(x):
        g = C.read_json(os.path.join(x["run_dir"], "grade.json")) or {}
        c = g.get("contaminated")
        return x["row_status"] == "contaminated" and isinstance(c, dict) and c.get("pattern") == "repo_name"
    sens_cells = {k: v for k, v in cells.items() if len(v) == 2 and all((x["row_status"] == "completed" and not x["row_degraded"]) or hand_read_ok(x) for x in v.values())}
    sens = read(sens_cells, "sensitivity: repo_name-contaminated rows hand-read as scan false positives and included")
    # oracle scan over a1 run dirs
    exposed_cells = set(); oracle = []
    for r in runs:
        if r["arm"] != "a1_full" or (r["task"], r["trial"]) not in sens_cells: continue
        hunks = C.diff_hunks(r["pr"]); man = C.load_manifest(r["pr"])
        for ph in ("REVIEW", "AUDIT"):
            if not os.path.isfile(os.path.join(r["run_dir"], "transcripts", f"events-{ph}.jsonl")): continue
            diffs, reads, exp = O.scan_gate(r, ph, hunks, man["defects"])
            rec = next(x for x in recs if x["run_id"] == r["run_id"])
            pos = {d["id"]: f"d{i}" for i, d in enumerate(man["defects"], 1)}
            after = []
            for did, ev_i in exp.items():
                pd = next(v for v in rec["per_defect"].values() if v["id"] == did); fc = pd["first_citation"]
                cited_after = bool(fc) and ((fc["phase"] == ph and fc["event"] > ev_i) or (ph == "REVIEW" and fc["phase"] == "AUDIT"))
                after.append({"defect": pos[did], "exposed_at": ev_i, "caught": pd["caught"], "first_citation": fc, "cited_after_exposure": cited_after,
                              "bare_caught_same_trial": cells[(r["task"], r["trial"])].get("a0_bare", {}).get("per_defect", {}).get(pos[did], {}).get("caught")})
            oracle.append({"run_id": r["run_id"], "gate": ph, "n_diff_cmds": len(diffs), "n_ws_reads": len(reads), "exposed": sorted(exp),
                           "exposed_detail": after, "n_exposed_cited_after": sum(1 for a in after if a["cited_after_exposure"]),
                           "n_exposed_cited_after_bare_missed": sum(1 for a in after if a["cited_after_exposure"] and not a["bare_caught_same_trial"]),
                           "diffs": [{"event": d["event"], "cmd": d["cmd"][:160], "planted": d["planted_in_diff"]} for d in diffs]})
            if exp: exposed_cells.add((r["task"], r["trial"]))
    clean = read({k: v for k, v in sens_cells.items() if k not in exposed_cells}, "oracle-exposed cells excluded (from the sensitivity cell set)")
    # zeroed variant: only the defect-trials whose site was exposed AND cited after exposure are set to not-caught
    import copy
    zeroed = copy.deepcopy(sens_cells)
    for o in oracle:
        key = next((k for k, v in sens_cells.items() if v.get("a1_full", {}).get("run_id") == o["run_id"]), None)
        if key is None: continue
        for a in o["exposed_detail"]:
            if a["cited_after_exposure"]:
                zeroed[key]["a1_full"]["per_defect"][a["defect"]]["caught"] = False
    zero_read = read(zeroed, "oracle-exposed-and-cited-after defect-trials set to not caught")
    # same-function window sensitivity
    import window_sensitivity as W
    def caught_fn(rec):
        man = C.load_manifest(rec["pr"]); cites = []; seen = set()
        sb = os.path.join(rec["run_dir"], "sandbox"); a2a = os.path.join(sb, "grimoires/loa/a2a/sprint-1")
        for p in (os.path.join(sb, "review.md"), os.path.join(a2a, "engineer-feedback.md"), os.path.join(a2a, "auditor-sprint-feedback.md")):
            t = C.read_text(p)
            if t is None: continue
            for c in C.citations(t):
                if c not in seen: seen.add(c); cites.append(c)
        return sum(W.detected_w(cites, d, 3, C.head_lines(rec["pr"], d["file"]), True) for d in man["defects"])
    fn = {a: 0 for a in ("a0_bare", "a1_full")}; n_dt = 0
    for k, v in sens_cells.items():
        for a in fn: fn[a] += caught_fn(v[a])
        n_dt += len(v["a0_bare"]["per_defect"])
    # dissent status, costs, precision
    gates = {}; cost = {}; wall = {}; prec = {}
    for r in recs:
        cost.setdefault(r["arm"], []).append(r["cost_usd"] or 0); wall.setdefault(r["arm"], []).append(r["wall_ms"] or 0)
        p = prec.setdefault(r["arm"], {"caught": 0, "flags": 0, "fp": 0}); p["caught"] += r["grade"]["caught"]; p["flags"] += r["grade"]["flags"]; p["fp"] += r["grade"]["false_positives"]
        if r["arm"] == "a1_full":
            gates[r["run_id"]] = {g: (e["status"], e["voices_succeeded"]) for g, e in r["envelopes"].items()}
    out = {"batch": "replication-01", "runs": [{k: r[k] for k in ("run_id", "arm", "task", "pr", "trial", "row_status", "row_degraded", "cost_usd", "wall_ms")} | {"caught": r["grade"]["caught"], "seeded": r["grade"]["seeded"], "missed": r["grade"]["missed"], "flags": r["grade"]["flags"], "false_positives": r["grade"]["false_positives"], "verdicts": r["grade"]["verdicts"], "crosscheck_ok": all(r["crosscheck"].values())} for r in recs],
           "valid_cells": sorted(f"{k[0]}-t{k[1]}" for k in valid), "excluded_cells_per_arm": excl, "excluded_share": {a: excl[a] / 6 for a in excl},
           "read": plain, "read_sensitivity_contaminated_included": sens, "sensitivity_cells": sorted(f"{k[0]}-t{k[1]}" for k in sens_cells), "oracle": oracle, "oracle_exposed_cells": sorted(f"{k[0]}-t{k[1]}" for k in exposed_cells), "read_oracle_clean": clean, "read_oracle_zeroed": zero_read,
           "same_function_window": {"bare": fn["a0_bare"], "full": fn["a1_full"], "n": n_dt, "gap": (fn["a1_full"] - fn["a0_bare"]) / n_dt if n_dt else None},
           "dissent_gates": gates, "cost_per_run": {a: sum(v) / len(v) for a, v in cost.items()}, "wall_min_per_run": {a: sum(v) / len(v) / 60000 for a, v in wall.items()},
           "precision": {a: {"caught": p["caught"], "flags": p["flags"], "fp": p["fp"], "precision": (p["caught"] / p["flags"] if p["flags"] else None)} for a, p in prec.items()}}
    json.dump(out, open(os.path.join(C.DATA, "replication-read.json"), "w"), indent=1, default=str)
    json.dump(recs, open(os.path.join(C.DATA, "replication-runs.json"), "w"), indent=1, default=str)
    print(json.dumps({k: out[k] for k in ("valid_cells", "excluded_share", "read", "read_sensitivity_contaminated_included", "sensitivity_cells", "oracle_exposed_cells", "read_oracle_clean", "read_oracle_zeroed", "same_function_window", "dissent_gates", "cost_per_run", "wall_min_per_run", "precision")}, indent=1, default=str))
    for r in out["runs"]: print(r["run_id"], r["row_status"], f"caught {r['caught']}/{r['seeded']}", "fp", r["false_positives"], "USD", round(r["cost_usd"] or 0, 2), "crosscheck", r["crosscheck_ok"])

if __name__ == "__main__":
    main()
