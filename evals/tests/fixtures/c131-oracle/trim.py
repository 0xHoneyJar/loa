#!/usr/bin/env python3
"""trim.py — one-off provenance script for the c131-oracle fixtures (cycle-131 Sprint 263 Task 1.3).

Usage: python3 -I trim.py <main checkout> <grade.json dir of a full grade> <out dir>

Copies, from four cycle-130 run directories of the main checkout (read only), the transcript events the
grader's oracle detector reads: the system init line, and every tool_use named by the full grade's
oracle_exposed_events together with its tool_result; every other line becomes an empty line, so the
line numbers (the events' `event` field) are the originals. For the bare run every Bash/Read/Grep
tool_use and its tool_result are kept, results cut at 4,096 characters (a bare sandbox mounts no
framework copy, so no result can expose one). The later sandbox copy of each path an event names is
copied to <name>/dotclaude/<path below .claude/>.fx (the suffix keeps linters off it). Not run by the tests; the fixtures are committed."""
import json, os, shutil, sys

MAIN, GRADES, OUT = sys.argv[1:4]
B = "grimoires/loa/reports/ablation-2.0/batches"
R = "evals/results/ablation-2.0/replication-01"
RUNS = {
    "p1-a1-review-04-t2": (f"{B}/priority-v2-p1/a1_full/review-04-t2", "review-04", "ablation-2.0"),
    "rep-a1-review-r17-t1": (f"{R}/a1_full/review-r17-t1", "review-r17", "ablation-2.0-replication"),
    "rep-a1-review-r18-t1": (f"{R}/a1_full/review-r18-t1", "review-r18", "ablation-2.0-replication"),
    "rep-a0-review-r17-t1": (f"{R}/a0_bare/review-r17-t1", "review-r17", "ablation-2.0-replication"),
}


def text_of(blk):
    c = blk.get("content")
    return c if isinstance(c, str) else "\n".join(x.get("text", "") for x in c or [] if isinstance(x, dict))


for name, (rel, task, root) in RUNS.items():
    rd = os.path.join(MAIN, rel)
    g = json.load(open(os.path.join(GRADES, rel.replace("/", "__") + ".grade.json")))
    keep = {}
    for e in g.get("oracle_exposed_events") or []:
        keep.setdefault(e["phase"], set()).add(e["event"])
    d = os.path.join(OUT, name)
    os.makedirs(os.path.join(d, "transcripts"), exist_ok=True)
    with open(os.path.join(d, "task"), "w") as f:
        f.write(f"{task} {root}\n")
    bare = "/a0_bare/" in rel
    for ph in (["BARE"] if bare else ["REVIEW", "AUDIT"]):
        src = os.path.join(rd, "transcripts", f"events-{ph}.jsonl")
        lines = open(src, encoding="utf-8").read().split("\n")
        out, ids = [""] * len(lines), set()
        for i, l in enumerate(lines, 1):
            try:
                ev = json.loads(l)
            except ValueError:
                continue
            if ev.get("type") == "system" and ev.get("subtype") == "init":
                out[i - 1] = json.dumps({"type": "system", "subtype": "init", "cwd": ev.get("cwd")})
                continue
            msg = ev.get("message")
            content = msg.get("content") if isinstance(msg, dict) else None
            if not isinstance(content, list):
                continue
            if ev.get("type") == "assistant":
                blks = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_use"
                        and (i in keep.get(ph, ()) or (bare and b.get("name") in ("Bash", "Read", "Grep")))]
                if blks:
                    ids |= {b["id"] for b in blks}
                    out[i - 1] = json.dumps({"type": "assistant", "message": {"content": [
                        {"type": "tool_use", "id": b["id"], "name": b["name"], "input": b["input"]} for b in blks]}})
            elif ev.get("type") == "user":
                blks = [b for b in content if isinstance(b, dict) and b.get("type") == "tool_result"
                        and b.get("tool_use_id") in ids]
                if blks:
                    out[i - 1] = json.dumps({"type": "user", "message": {"content": [
                        {"type": "tool_result", "tool_use_id": b["tool_use_id"],
                         "content": text_of(b)[:4096] if bare else text_of(b),
                         **({"is_error": True} if b.get("is_error") is True else {})} for b in blks]}})
        while out and out[-1] == "":
            out.pop()
        if bare or keep.get(ph):
            with open(os.path.join(d, "transcripts", f"events-{ph}.jsonl"), "w", encoding="utf-8") as f:
                f.write("\n".join(out) + "\n")
    for e in g.get("oracle_exposed_events") or []:
        p = e["path"]
        dst = os.path.join(d, "dotclaude", p[len(".claude/"):] + ".fx")   # .fx: never a script to a linter
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(rd, "sandbox", p), dst)
