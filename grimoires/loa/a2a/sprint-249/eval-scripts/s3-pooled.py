#!/usr/bin/env python3
"""Sprint 3 replay A/B, pooled per case over every trial of each arm.

Arm = executor.prompt_tree_commit (2079e719 before, 41b783a1 after,
c9b7bdc0 ablate). Two recall columns per arm:
  graded      — recall-vs-defects.sh as run (the pre-registered metric)
  adjudicated — graded, plus every graded miss that adjudication.json marks
                "found" (the review names the defect's mechanism in the
                defect's file; evidence quoted per slot). Unadjudicated misses
                stay missed and are listed.
Exit 1 if any case's pooled after-arm graded recall < before-arm.
"""
import glob, json, os, sys
R = os.path.expanduser("~/Documents/thj/code/loa/evals/results")
ARM = {"2079e719": "before", "41b783a1": "after", "c9b7bdc0": "ablate"}
ADJ = json.load(open(os.path.join(os.path.dirname(__file__), "adjudication.json")))
cases = {}
unadj = []
for jl in glob.glob(f"{R}/run-202610*/task-*.jsonl"):
    for line in open(jl):
        d = json.loads(line)
        arm = ARM.get(str((d.get("executor") or {}).get("prompt_tree_commit", ""))[:8])
        if not arm:
            continue
        g = next((g for g in d["graders"] if g["name"] == "recall-vs-defects.sh"), None)
        if not g or not g["details"].get("planted"):
            continue
        det = g["details"]
        c = cases.setdefault(d["task_id"], {}).setdefault(arm, {"n": 0, "slots": 0, "hit": 0, "adj": 0})
        c["n"] += 1
        c["slots"] += det["planted"]
        c["hit"] += len(det["detected"])
        c["adj"] += len(det["detected"])
        for m in det["missed"]:
            k = f'{d["run_id"][-8:]}:{d["task_id"]}:t{d["trial"]}:{m}'
            v = ADJ.get(k, {}).get("verdict")
            if v == "found":
                c["adj"] += 1
            elif v is None:
                unadj.append(k)
lost = 0
print(f'{"case":14} {"arm":7} {"n":>3} {"graded":>8} {"adjud.":>8}')
for t in sorted(cases):
    for arm in ("before", "after", "ablate"):
        c = cases[t].get(arm)
        if c:
            print(f'{t:14} {arm:7} {c["n"]:>3} {c["hit"]/c["slots"]:>8.3f} {c["adj"]/c["slots"]:>8.3f}')
    b, a = cases[t].get("before"), cases[t].get("after")
    if b and a and a["hit"] / a["slots"] < b["hit"] / b["slots"]:
        lost += 1
        print(f'{"":14} ^ graded recall lost')
if unadj:
    print("unadjudicated misses:", *unadj, sep="\n  ")
sys.exit(1 if lost else 0)
