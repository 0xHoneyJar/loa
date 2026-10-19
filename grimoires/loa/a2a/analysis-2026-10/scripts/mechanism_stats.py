"""mechanism_stats.py — deliverable 5 (quantitative side): what each arm did per run — turns, tool calls, test
executions, exec probes, tool-output bytes, head files read — and per defect whether the agent printed the
region (head file) or the hunk (diff) before missing or catching it. Writes data/mechanism-stats.json + .md table."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

def main():
    recs = json.load(open(os.path.join(C.DATA, "runs.json")))
    rows = []
    for r in recs:
        for ph, st in r["transcripts"].items():
            rows.append({"arm": r["arm"], "task": r["task"], "pr": r["pr"], "trial": r["trial"], "phase": ph, "turns": st["num_turns"],
                         "tool_calls": st["n_tool_calls"], "test_runs": st["n_test_runs"], "exec_probes": st["n_exec_probes"],
                         "result_kb": round(st["result_bytes"] / 1024), "truncated": st["truncated_results"], "head_files": len(st["head_files_read"]),
                         "regions_read": len(st["regions_read"]), "diff_seen": len(st["diff_seen"]), "n_defects": len(r["per_defect"])})
    # per defect-trial read/miss matrix
    rm = {}
    for r in recs:
        for k, d in r["per_defect"].items():
            read_any = any(v for v in d["region_read"].values()); diff_any = any(v for v in d["diff_seen"].values())
            key = (r["arm"], r["task"])
            e = rm.setdefault(key, {"caught_read": 0, "caught_unread": 0, "missed_read": 0, "missed_unread": 0, "missed_diff_seen": 0, "missed_total": 0})
            if d["caught"]:
                e["caught_read" if read_any else "caught_unread"] += 1
            else:
                e["missed_read" if read_any else "missed_unread"] += 1; e["missed_total"] += 1; e["missed_diff_seen"] += bool(diff_any)
    json.dump({"phases": rows, "read_miss": {f"{a}|{t}": v for (a, t), v in rm.items()}}, open(os.path.join(C.DATA, "mechanism-stats.json"), "w"), indent=1)
    L = ["## Activity per gate (means over the 3 trials)\n", "| arm | task | phase | turns | tool calls | test runs | exec probes | tool output KB | truncated results | head files read | planted regions printed (head) | planted hunks printed (diff) | defects |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for arm in ("a0_bare", "a1_full"):
        for t in ("review-01", "review-02", "review-03", "review-04"):
            for ph in ("BARE", "REVIEW", "AUDIT"):
                xs = [x for x in rows if x["arm"] == arm and x["task"] == t and x["phase"] == ph]
                if not xs: continue
                m = lambda k: sum((x[k] or 0) for x in xs) / len(xs)
                L.append(f"| {arm} | {t} | {ph} | {m('turns'):.0f} | {m('tool_calls'):.0f} | {m('test_runs'):.1f} | {m('exec_probes'):.1f} | {m('result_kb'):.0f} | {m('truncated'):.1f} | {m('head_files'):.1f} | {m('regions_read'):.1f} | {m('diff_seen'):.1f} | {xs[0]['n_defects']} |")
    L.append("\n## Read-and-missed vs never-read (defect-trials, any phase of the run)\n")
    L.append("| arm | task | caught & region printed | caught, region not printed | missed & region printed | missed, region never printed | missed but hunk printed from the diff |\n|---|---|---|---|---|---|---|")
    for (a, t), e in sorted(rm.items()):
        L.append(f"| {a} | {t} | {e['caught_read']} | {e['caught_unread']} | {e['missed_read']} | {e['missed_unread']} | {e['missed_diff_seen']}/{e['missed_total']} |")
    L.append("\n'Region printed' = a `sed -n`/`awk` range over the head file covering the anchor ±3 (grep -n/-A output and whole-file `cat` are not counted, so this under-counts reading); 'hunk printed' = the diff lines of the defect's hunk were displayed (`cat`/`sed -n` over head.diff, `diff -u base head`).\n")
    open(os.path.join(C.DATA, "mechanism-stats.md"), "w").write("\n".join(L) + "\n")
    print("\n".join(L))

if __name__ == "__main__":
    main()
