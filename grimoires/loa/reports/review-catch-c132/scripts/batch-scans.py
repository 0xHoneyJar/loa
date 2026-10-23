#!/usr/bin/env python3
"""batch-scans.py — enumerate every contaminated Phase 1 unit (trial cells and matched-cell sessions) of the c132-g* batches with its
excerpt, for the Sprint 270 hand-read table (a2a/sprint-270/batch-scans.md). Read-only. Usage: batch-scans.py <results-root> <out.tsv>"""
import json, os, re, sys, glob
root, out = sys.argv[1], sys.argv[2]
rows = []
for b in sorted(glob.glob(os.path.join(root, "c132-g[1-9]-*"))):
    batch = os.path.basename(b)
    if not re.match(r"^c132-g[1-9]-(a1|a2|a3|b)$", batch):
        continue
    for g in sorted(glob.glob(os.path.join(b, "*", "*", "grade.json")) + glob.glob(os.path.join(b, "*", "*", "sessions", "*", "grade.json"))):
        rel = os.path.relpath(g, b).split(os.sep)
        arm, unit = rel[0], rel[1]
        sess = rel[3] if len(rel) > 3 and rel[2] == "sessions" else ""
        if not sess and os.path.isdir(os.path.join(b, arm, unit, "sessions")):
            continue   # the union grade of a matched cell: its sessions carry the contamination
        try:
            gd = json.load(open(g))
        except Exception:
            continue
        c = gd.get("contaminated")
        if not c:
            continue
        rd = os.path.dirname(g)
        ph, _, ln = (c.get("excerpt_id") or "::").partition(":")
        cmd = ""
        tp = os.path.join(rd, "transcripts", "events-%s.jsonl" % ph)
        if ln.isdigit() and os.path.isfile(tp):
            with open(tp, encoding="utf-8", errors="replace") as fh:
                for i, line in enumerate(fh, 1):
                    if i == int(ln):
                        try:
                            ev = json.loads(line)
                            for blk in (ev.get("message") or {}).get("content") or []:
                                if isinstance(blk, dict) and blk.get("type") == "tool_use":
                                    inp = blk.get("input") or {}
                                    cmd = inp.get("command") or inp.get("file_path") or inp.get("url") or json.dumps(inp)
                        except Exception:
                            pass
                        break
        rows.append([batch, arm, unit, sess, c.get("pattern", ""), c.get("excerpt_id", ""), str(c.get("repo_named", "")),
                     c.get("host", "") or "", re.sub(r"\s+", " ", cmd)[:400]])
with open(out, "w") as fh:
    fh.write("batch\tarm\tunit\tsession\tpattern\texcerpt\trepo_named\thost\tcommand\n")
    for r in rows:
        fh.write("\t".join(x.replace("\t", " ") for x in r) + "\n")
print(len(rows), "contaminated units ->", out)
