"""window_sensitivity.py — how much of the bare-vs-full gap is the grader's ±3-line window? Re-applies the
grader's citation rule with wider windows (±3 as shipped, ±6, ±10, ±20, same enclosing function) per arm, using the
exact citations already extracted. Decides nothing; a sensitivity on the measurement rule."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

def detected_w(cites, d, w, lines=None, same_fn=False):
    sites = C.defect_sites(d)
    syms = {C.enclosing_symbol(lines, s) for s in sites} - {None} if (same_fn and lines) else set()
    for p, a, b in cites:
        if not C.path_matches(p, d["file"]): continue
        if any(not (b < s - w or a > s + w) for s in sites): return True
        if syms and lines:
            # any cited line inside the same function (cited range start..end)
            for L in range(a, min(b, a + 400) + 1):
                if C.enclosing_symbol(lines, L) in syms: return True
    return False

def main():
    runs = C.valid_runs()
    recs = {r["run_id"]: r for r in json.load(open(os.path.join(C.DATA, "runs.json")))}
    out = {}
    for w, same_fn in ((3, False), (6, False), (10, False), (20, False), (3, True)):
        key = f"±{w}" + (" or same function" if same_fn else "")
        tot = {"a0_bare": 0, "a1_full": 0}; per_task = {}
        for run in runs:
            r = recs[run["run_id"]]
            man = C.load_manifest(run["pr"])
            # rebuild the run's union citations from the source files exactly as extract.py did
            cites = []
            seen = set()
            sb = os.path.join(run["run_dir"], "sandbox"); a2a = os.path.join(sb, "grimoires/loa/a2a/sprint-1")
            for p in (os.path.join(sb, "review.md"), os.path.join(a2a, "engineer-feedback.md"), os.path.join(a2a, "auditor-sprint-feedback.md")):
                t = C.read_text(p)
                if t is None: continue
                for c in C.citations(t):
                    if c not in seen: seen.add(c); cites.append(c)
            n = 0
            for d in man["defects"]:
                lines = C.head_lines(run["pr"], d["file"]) if same_fn else None
                n += detected_w(cites, d, w, lines, same_fn)
            tot[run["arm"]] += n
            per_task.setdefault(run["task"], {"a0_bare": 0, "a1_full": 0, "n": 3 * len(man["defects"])})[run["arm"]] += n
        out[key] = {"pooled": {a: tot[a] / 57 for a in tot}, "pooled_caught": tot, "per_task": per_task,
                    "task_mean": {a: sum(per_task[t][a] / per_task[t]["n"] for t in per_task) / 4 for a in tot}}
    json.dump(out, open(os.path.join(C.DATA, "window-sensitivity.json"), "w"), indent=1)
    print("| window | bare caught /57 | full caught /57 | pooled gap | task-mean bare | task-mean full | task-mean gap |")
    print("|---|---|---|---|---|---|---|")
    for k, v in out.items():
        print(f"| {k} | {v['pooled_caught']['a0_bare']} | {v['pooled_caught']['a1_full']} | {v['pooled']['a1_full']-v['pooled']['a0_bare']:+.3f} | {v['task_mean']['a0_bare']:.3f} | {v['task_mean']['a1_full']:.3f} | {v['task_mean']['a1_full']-v['task_mean']['a0_bare']:+.3f} |")
    print("\nper task (bare/full caught):")
    for k, v in out.items():
        print(k, {t: f"{e['a0_bare']}/{e['a1_full']} of {e['n']}" for t, e in v["per_task"].items()})

if __name__ == "__main__":
    main()
