#!/usr/bin/env python3
"""Task 4.8 (bd-ewrc) diagnostic: re-grade every retained Sprint 3 A/B trial with
grader 1.1.0 (the worktree copy) and compare with the blind adjudication.
Per case and arm: graded-1.0 recall, graded-1.1 recall, adjudicated recall;
agreement = |hits(1.1) - hits(adjudicated)| per case/arm (condition (a): <= 1 slot).
Read-only over evals/results; scratch workspaces under a tmp dir."""
import glob, json, os, subprocess, sys, tempfile, shutil
R = os.path.expanduser("~/Documents/thj/code/loa/evals/results")
G = os.path.expanduser("~/.cache/loa/cycle-126-dissent/wt-s4c/evals/graders/recall-vs-defects.sh")
MAN = os.path.expanduser("~/.cache/loa/cycle-126-dissent/wt-s4c/evals/fixtures/review-prs/manifests")
ARM = {"2079e719": "before", "41b783a1": "after", "c9b7bdc0": "ablate"}
ADJ = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "adjudication.json")))
tmp = tempfile.mkdtemp(prefix="regrade.")
cases, disagree = {}, []
for jl in sorted(glob.glob(f"{R}/run-202610*/task-*.jsonl")):
    rd = os.path.dirname(jl)
    for line in open(jl):
        d = json.loads(line)
        arm = ARM.get(str((d.get("executor") or {}).get("prompt_tree_commit", ""))[:8])
        if not arm: continue
        g = next((g for g in d["graders"] if g["name"] == "recall-vs-defects.sh"), None)
        if not g or not g["details"].get("planted"): continue
        art = f'{rd}/artifacts/{d["task_id"]}/trial-{d["trial"]}'
        rf = next((n for n in ("review.md", "audit.md") if os.path.isfile(f"{art}/{n}")), None)
        if not rf: print("NO REVIEW FILE", art, file=sys.stderr); continue
        ws = os.path.join(tmp, "ws"); shutil.rmtree(ws, ignore_errors=True); os.makedirs(ws + "/.eval")
        shutil.copy(f"{art}/{rf}", ws)
        fx = "pr-" + d["task_id"].rsplit("-", 1)[1]
        out = subprocess.run([G, ws, fx, rf], capture_output=True, text=True, env={**os.environ, "EVAL_MANIFEST_DIR": MAN})
        new = json.loads(out.stdout)["details"]
        old = g["details"]
        c = cases.setdefault(d["task_id"], {}).setdefault(arm, {"n": 0, "slots": 0, "old": 0, "new": 0, "adj": 0})
        c["n"] += 1; c["slots"] += old["planted"]; c["old"] += len(old["detected"]); c["new"] += len(new["detected"])
        adj_found = set(old["detected"])
        for m in old["missed"]:
            k = f'{d["run_id"][-8:]}:{d["task_id"]}:t{d["trial"]}:{m}'
            if ADJ.get(k, {}).get("verdict") == "found": adj_found.add(m)
        c["adj"] += len(adj_found)
        for x in set(new["detected"]) ^ adj_found:
            disagree.append(f'{d["run_id"][-8:]}:{d["task_id"]}:t{d["trial"]}:{x} grader1.1={"found" if x in new["detected"] else "missed"} adjudication={"found" if x in adj_found else "missed"}')
print(f'{"case":14} {"arm":7} {"n":>3} {"g1.0":>6} {"g1.1":>6} {"adjud":>6} {"|1.1-adj|":>9}')
worst = 0
for t in sorted(cases):
    for arm in ("before", "after", "ablate"):
        c = cases[t].get(arm)
        if not c: continue
        gap = abs(c["new"] - c["adj"]); worst = max(worst, gap)
        print(f'{t:14} {arm:7} {c["n"]:>3} {c["old"]/c["slots"]:>6.3f} {c["new"]/c["slots"]:>6.3f} {c["adj"]/c["slots"]:>6.3f} {gap:>9}')
print("disagreements:", *disagree, sep="\n  ")
print("max per-case/arm slot gap:", worst)
shutil.rmtree(tmp, ignore_errors=True)
