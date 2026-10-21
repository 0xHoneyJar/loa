#!/usr/bin/env python3
"""compare-ab.py — arm-A vs arm-B gate for the cycle-124 prompt A/B (PRD FR-9, AC-9.2).

Invoked by compare.sh --ab. Reads two results.jsonl files produced by
run-eval.sh for the same suite and applies the gates the PRD names:

  recall      mean recall over defect tasks: B >= A - 0.1   ("≥ baseline" per the
              PRD's tolerance); false positives on clean tasks: B <= A
  audit       the recall gates + tokens_ratio: mean tokens per call B/A <= 0.5
  discipline  mean composite pass rate over tasks: B >= A (strict, as written)

Validity (exit 2 — the run is not a comparison at all):
  * every completed trial in both arms reports the same executor model id
  * neither arm ran on a dirty prompt tree
  * the two arms ran on different prompt trees

Exit 0 when valid and every gate passes, 1 when valid and a gate fails.
Trials with status != completed are excluded from the means and reported
under error_trials (a session cap is not a recall drop).
"""
import json
import sys
from collections import defaultdict

TOL = 0.1
TOKENS_RATIO_MAX = 0.5


def load(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def recall_details(row):
    for g in row.get("graders") or []:
        if g.get("name") == "recall-vs-defects.sh" and isinstance(g.get("details"), dict):
            return g["details"]
    return None


def mean(xs):
    xs = [x for x in xs if x is not None]
    return round(sum(xs) / len(xs), 4) if xs else None


def summarize(rows):
    # loa:shortcut: one pass over the rows builds every per-task/per-defect aggregate the
    # gates read; splitting it would thread five dicts through helpers for no reader gain.
    completed = [r for r in rows if r.get("status") == "completed"]
    errors = [r for r in rows if r.get("status") != "completed"]
    models = set()
    trees = set()
    dirty = False
    per_task = defaultdict(lambda: {"recall": [], "fp": [], "tokens": [], "pass": [], "planted": 0})
    per_defect = defaultdict(lambda: [0, 0])  # id -> [detected, seen]
    for r in completed:
        ex = r.get("executor") or {}
        models.add(ex.get("model_id") or r.get("model_version"))
        if ex.get("prompt_tree_sha"):
            trees.add(ex["prompt_tree_sha"])
        dirty = dirty or bool(ex.get("prompt_tree_dirty"))
        t = per_task[r["task_id"]]
        t["pass"].append(1.0 if (r.get("composite") or {}).get("pass") else 0.0)
        u = ex.get("usage") or {}
        if u:
            # all four usage fields: cached prompt reads dominate a real call
            t["tokens"].append(sum(int(u.get(k, 0) or 0) for k in
                                   ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")))
        d = recall_details(r)
        if d is not None:
            t["planted"] = int(d.get("planted") or 0)
            if d.get("recall") is not None:
                t["recall"].append(float(d["recall"]))
            if d.get("false_positives") is not None:
                t["fp"].append(float(d["false_positives"]))
            for did in d.get("detected") or []:
                per_defect[did][0] += 1
                per_defect[did][1] += 1
            for did in d.get("missed") or []:
                per_defect[did][1] += 1
    tasks = {}
    for tid, t in per_task.items():
        tasks[tid] = {
            "planted": t["planted"],
            "recall": mean(t["recall"]),
            "false_positives": mean(t["fp"]),
            "tokens_mean": mean(t["tokens"]),
            "pass_rate": mean(t["pass"]),
            "trials": len(t["pass"]),
        }
    defect_tasks = [v for v in tasks.values() if v["planted"] > 0]
    clean_tasks = [v for v in tasks.values() if v["planted"] == 0 and v["false_positives"] is not None]
    return {
        "trials_completed": len(completed),
        "error_trials": len(errors),
        "models": sorted(m for m in models if m),
        "prompt_trees": sorted(trees),
        "dirty": dirty,
        "recall": mean([v["recall"] for v in defect_tasks]),
        "false_positives": mean([v["false_positives"] for v in clean_tasks]),
        "tokens_mean": mean([v["tokens_mean"] for v in tasks.values()]),
        "pass_rate": mean([v["pass_rate"] for v in tasks.values()]),
        "tasks": tasks,
        "per_defect": {k: round(v[0] / v[1], 4) if v[1] else None for k, v in per_defect.items()},
    }


def main():
    # loa:shortcut: argument handling, validity reasons and the three gate blocks stay in one
    # function so the exit-code contract (0 pass / 1 fail / 2 invalid) is visible top to bottom.
    a_path, b_path, metric, json_out = sys.argv[1:5]
    A = summarize(load(a_path))
    B = summarize(load(b_path))
    reasons = []
    if not A["trials_completed"] or not B["trials_completed"]:
        reasons.append("an arm has no completed trials")
    if len(set(A["models"]) | set(B["models"])) != 1:
        reasons.append(f"executor model id skew: A={A['models']} B={B['models']}")
    if A["dirty"] or B["dirty"]:
        reasons.append("an arm ran on a prompt tree with uncommitted .claude/ changes")
    if A["prompt_trees"] and B["prompt_trees"] and set(A["prompt_trees"]) & set(B["prompt_trees"]):
        reasons.append("both arms ran on the same prompt tree (nothing was varied)")
    if len(A["prompt_trees"]) > 1 or len(B["prompt_trees"]) > 1:
        reasons.append("an arm mixes prompt trees across trials")
    valid = not reasons

    gates = []

    def gate(name, a, b, ok, rule):
        gates.append({"name": name, "a": a, "b": b, "pass": bool(ok), "rule": rule})

    if metric in ("recall", "audit"):
        a, b = A["recall"], B["recall"]
        gate("recall", a, b, a is not None and b is not None and b >= a - TOL, f"mean recall over defect tasks: B >= A - {TOL}")
        a, b = A["false_positives"], B["false_positives"]
        gate("false_positives", a, b, a is not None and b is not None and b <= a, "mean critical+high findings on clean tasks: B <= A")
    if metric == "audit":
        a, b = A["tokens_mean"], B["tokens_mean"]
        ratio = round(b / a, 4) if (a and b is not None) else None
        gate("tokens_ratio", a, b, ratio is not None and ratio <= TOKENS_RATIO_MAX, f"mean tokens per call B/A <= {TOKENS_RATIO_MAX} (ratio={ratio})")
    if metric == "discipline":
        a, b = A["pass_rate"], B["pass_rate"]
        gate("pass_rate", a, b, a is not None and b is not None and b >= a, "mean task pass rate: B >= A")

    per_defect = []
    for did in sorted(set(A["per_defect"]) | set(B["per_defect"])):
        pa, pb = A["per_defect"].get(did), B["per_defect"].get(did)
        per_defect.append({"id": did, "a": pa, "b": pb, "regressed": (pa is not None and pb is not None and pb < pa)})

    out = {
        "valid": valid,
        "reasons": reasons,
        "metric": metric,
        "arms": {
            "a": {k: A[k] for k in ("trials_completed", "error_trials", "models", "prompt_trees", "recall", "false_positives", "tokens_mean", "pass_rate")},
            "b": {k: B[k] for k in ("trials_completed", "error_trials", "models", "prompt_trees", "recall", "false_positives", "tokens_mean", "pass_rate")},
        },
        "gates": gates,
        "per_defect": per_defect,
        "per_task": {tid: {"a": A["tasks"].get(tid), "b": B["tasks"].get(tid)} for tid in sorted(set(A["tasks"]) | set(B["tasks"]))},
    }
    if json_out == "true":
        print(json.dumps(out, indent=2))
    else:
        print(f"A/B ({metric}): valid={valid}" + (f" — {'; '.join(reasons)}" if reasons else ""))
        for g in gates:
            print(f"  {'PASS' if g['pass'] else 'FAIL'} {g['name']}: A={g['a']} B={g['b']}  [{g['rule']}]")
        regressed = [d["id"] for d in per_defect if d["regressed"]]
        if regressed:
            print(f"  per-defect regressions (advisory): {', '.join(regressed)}")
        if A["error_trials"] or B["error_trials"]:
            print(f"  error trials excluded: A={A['error_trials']} B={B['error_trials']}")
    if not valid:
        sys.exit(2)
    sys.exit(0 if all(g["pass"] for g in gates) else 1)


if __name__ == "__main__":
    main()
