"""oracle_scan.py — the mounted-framework oracle. In every a1_full sandbox the pinned Loa tree (ba11b860) is mounted
at /workspace/.claude (and tools/, tests/ …) — a LATER version than the PR under review, so it already holds the fix.
(1) static exposure: per PR and defect, does the pinned tree's copy differ from pr/head at the defect's site?
(2) use: per a1 gate, every Bash command that diffs a PR-touched file's pr/ copy against the workspace copy, and
whether the printed diff covers a planted site; plus reads of the workspace copy of PR-touched files.
Writes data/oracle-scan.json and prints a table."""
import json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

PIN = "ba11b860e4b3d2112bf010c8f056d7e7bb521dde"
# a real content diff: the executable is diff/comm/sdiff (not `diff -q`, not the word inside `head.diff`/`--diff-file`),
# with one operand under pr/ and one outside pr/
DIFF_SEG = re.compile(r"(?:^|[;&|]\s*|\n\s*|\$\(\s*)(?:git\s+diff\s+--no-index|diff|sdiff|comm)\s+(?!-q\b)([^\n;|&]*)")
PR_PATH = re.compile(r"pr/(?:head|base)/([A-Za-z0-9_./+-]+\.[A-Za-z0-9]{1,6})")

def pinned_text(path):
    try:
        return subprocess.run(["git", "show", f"{PIN}:{path}"], capture_output=True, text=True, check=True, cwd=C.REPO).stdout.split("\n")
    except subprocess.CalledProcessError:
        return None

def changed_head_lines(head_lines, pin_lines):
    """head-side line numbers that differ between pr/head and the pinned copy (difflib opcodes)"""
    import difflib
    out = set()
    sm = difflib.SequenceMatcher(None, head_lines, pin_lines, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag != "equal":
            for L in range(i1 + 1, max(i2, i1 + 1) + 1):
                out.add(L)
    return out

def static_exposure(pr):
    man = C.load_manifest(pr); hunks = C.diff_hunks(pr)
    files = set(hunks) | {d["file"] for d in man["defects"]}
    changed = {}
    for f in files:
        hl = C.head_lines(pr, f); pl = pinned_text(f)
        changed[f] = None if (hl is None or pl is None) else changed_head_lines(hl, pl)
    out = []
    for i, d in enumerate(man["defects"], 1):
        ch = changed.get(d["file"])
        exposed = None if ch is None else any(any(abs(s - L) <= 3 for L in ch) for s in C.defect_sites(d))
        out.append({"pos": f"d{i}", "id": d["id"], "file": d["file"], "sites": C.defect_sites(d), "pinned_copy_exists": ch is not None, "site_changed_in_pinned_copy": exposed})
    return out, {f: (None if v is None else len(v)) for f, v in changed.items()}

def scan_gate(run, phase, hunks, defects):
    ev = C.read_events(os.path.join(run["run_dir"], "transcripts", f"events-{phase}.jsonl"))
    touched = {f.rsplit("/", 1)[-1]: f for f in hunks}
    pending = {}  # tool_use id -> (event, files)
    diffs, reads, exposed = [], [], {}
    for e in ev:
        if e.get("type") == "assistant":
            for blk in (e.get("message") or {}).get("content") or []:
                if not (isinstance(blk, dict) and blk.get("type") == "tool_use"): continue
                cmd = (blk.get("input") or {}).get("command") or ""
                if not cmd: continue
                pr_files = set(PR_PATH.findall(cmd))
                ws_files = set()
                for base, full in touched.items():
                    for m in re.finditer(r"(?<![\w/])((?:\./)?(?:\.claude|tools|tests|docs|lib|\.loa\.config\.yaml\.example|CHANGELOG\.md|README\.md)[A-Za-z0-9_./+-]*)", cmd):
                        tok = m.group(1).lstrip("./")
                        if tok.endswith(base) and not cmd[max(0, m.start() - 8):m.start()].endswith("pr/head/") and not cmd[max(0, m.start() - 8):m.start()].endswith("pr/base/"):
                            ws_files.add(full)
                    if "$H/" in cmd or "$F/" in cmd or "$W/" in cmd:
                        pass
                real_diff = False
                for m in DIFF_SEG.finditer(cmd):
                    args = m.group(1)
                    if "-q" in args.split() or "--brief" in args: continue
                    has_pr = bool(re.search(r"(?:pr/(?:head|base)|\$H/|\$B/)", args))
                    has_ws = bool(re.search(r"(?<![\w/])(?:\./)?(?:\.claude|tools|tests|docs|lib)/", args)) or bool(re.search(r"\s\.loa\.config\.yaml", args))
                    if has_pr and has_ws: real_diff = True
                if real_diff:
                    pending[blk.get("id")] = (e["_i"], sorted(ws_files) or ["(operands)"], cmd[:300])
                elif ws_files and re.search(r"\b(sed -n|cat|grep|awk|head|tail|less|rg)\b", cmd) and "pr/head" not in cmd:
                    reads.append({"event": e["_i"], "files": sorted(ws_files), "cmd": cmd[:160]})
        elif e.get("type") == "user":
            for blk in (e.get("message") or {}).get("content") or []:
                if isinstance(blk, dict) and blk.get("type") == "tool_result" and blk.get("tool_use_id") in pending:
                    i0, files, cmd = pending.pop(blk["tool_use_id"])
                    res = blk.get("content") if isinstance(blk.get("content"), str) else "\n".join(x.get("text", "") for x in (blk.get("content") or []) if isinstance(x, dict))
                    # hunk headers of a unified diff give the pr/head-side ranges when pr/head is the first operand; a plain
                    # `diff` gives `NaM,b` / `Nc` ranges. Collect every line-range mentioned and test the planted sites.
                    ranges = []
                    for m in re.finditer(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", res, re.M):
                        a, n = int(m.group(1)), int(m.group(2) or 1); ranges.append((a, a + max(n, 1) - 1))
                        c, k = int(m.group(3)), int(m.group(4) or 1); ranges.append((c, c + max(k, 1) - 1))
                    for m in re.finditer(r"^(\d+)(?:,(\d+))?[acd](\d+)(?:,(\d+))?$", res, re.M):
                        a = int(m.group(1)); b = int(m.group(2) or a); ranges.append((a, b))
                        c = int(m.group(3)); d_ = int(m.group(4) or c); ranges.append((c, d_))
                    hit = []
                    for d in defects:
                        if d["file"] in files or any(d["file"].endswith("/" + f) for f in files) or any(f.endswith(d["file"]) for f in files):
                            if any(any(not (hi < s - 3 or lo > s + 3) for lo, hi in ranges) for s in C.defect_sites(d)) or (d.get("must_match") and d["must_match"].strip()[:50] in res):
                                hit.append(d["id"])
                                exposed.setdefault(d["id"], e["_i"]) if d["id"] not in exposed else None
                    diffs.append({"event": i0, "result_event": e["_i"], "files": files, "cmd": cmd, "result_chars": len(res), "truncated": "<persisted-output>" in res, "ranges": len(ranges), "planted_in_diff": hit})
    return diffs, reads, exposed

def main():
    recs = {r["run_id"]: r for r in json.load(open(os.path.join(C.DATA, "runs.json")))}
    out = {"pin": PIN, "static": {}, "runs": []}
    print("== static exposure (does the pinned framework copy differ from pr/head at the planted site?)")
    for pr in ("pr-05", "pr-08", "pr-12", "pr-13", "pr-16", "pr-17", "pr-18"):
        se, files = static_exposure(pr)
        out["static"][pr] = {"defects": se, "changed_lines_per_file": files}
        n = sum(1 for d in se if d["site_changed_in_pinned_copy"]); m = sum(1 for d in se if d["pinned_copy_exists"])
        print(f"{pr}: {n}/{len(se)} defects exposed (pinned copy exists for {m}/{len(se)}); per defect: " + " ".join(f"{d['pos']}={'E' if d['site_changed_in_pinned_copy'] else ('-' if d['site_changed_in_pinned_copy'] is False else '?')}" for d in se))
    print("\n== use by the full arm (per gate): diff commands pr/ vs workspace copy, planted sites inside a printed diff, first citation after exposure?")
    for run in C.valid_runs():
        if run["arm"] != "a1_full": continue
        r = recs[run["run_id"]]; hunks = C.diff_hunks(run["pr"]); man = C.load_manifest(run["pr"])
        rec = {"run_id": run["run_id"], "task": run["task"], "trial": run["trial"], "gates": {}}
        for ph in ("REVIEW", "AUDIT"):
            diffs, reads, exposed = scan_gate(run, ph, hunks, man["defects"])
            pos = {d["id"]: f"d{i}" for i, d in enumerate(man["defects"], 1)}
            after = []
            for did, ev_i in exposed.items():
                pd = next(v for v in r["per_defect"].values() if v["id"] == did)
                fc = pd["first_citation"]
                after.append({"defect": pos[did], "exposed_at": ev_i, "caught": pd["caught"], "first_citation": fc, "cited_after_exposure": bool(fc and fc["phase"] == ph and fc["event"] > ev_i) or bool(fc and ph == "REVIEW" and fc["phase"] == "AUDIT")})
            rec["gates"][ph] = {"n_diff_cmds": len(diffs), "n_ws_reads": len(reads), "diffs": diffs, "exposed_defects": after}
            flag = " ".join(f"{a['defect']}@{a['exposed_at']}{'→cited-after' if a['cited_after_exposure'] else ('→cited-before' if a['caught'] else '→not-caught')}" for a in after)
            print(f"{run['task']} t{run['trial']} {ph:6s} diff-cmds={len(diffs):3d} ws-reads={len(reads):3d} exposed-planted={len(after)} {flag}")
        out["runs"].append(rec)
    json.dump(out, open(os.path.join(C.DATA, "oracle-scan.json"), "w"), indent=1, default=str)

if __name__ == "__main__":
    main()
