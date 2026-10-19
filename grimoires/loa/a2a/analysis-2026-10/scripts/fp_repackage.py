"""fp_repackage.py — keep the drawn sample (same packet ids and regions) but recompute each packet's finding
excerpt so that it is the text that actually cites the region: for one-finding-per-line files (review.md) the
citing line itself; for the feedback files the enclosing paragraph. Prints the packets whose first packaging
did not contain a citation of the region (those are re-labelled)."""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C
import fp_sample as F

def excerpt_hits(excerpt, region):
    """the excerpt cites one of the region's own cited lines (exact, not the ±3 window: a neighbouring credited
    citation must not be mistaken for this stray one)"""
    return any(C.strip_side(p) == region["file"] and not (b < region["lo"] or a > region["hi"]) for p, a, b in C.citations(excerpt))

def citing_blocks_v2(run_dir, sources, region, cap=1600):
    paths = {"review.md": os.path.join(run_dir, "sandbox", "review.md"),
             "engineer-feedback.md": os.path.join(run_dir, "sandbox/grimoires/loa/a2a/sprint-1/engineer-feedback.md"),
             "auditor-sprint-feedback.md": os.path.join(run_dir, "sandbox/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md")}
    out = []
    for src in sources:
        p = paths.get(src)
        if not p: continue
        text = C.read_text(p) or ""
        lines = text.split("\n")
        # pass 1: a line whose own citations hit the region
        hit = None
        for i, ln in enumerate(lines):
            if ":" in ln and excerpt_hits(ln, region):
                hit = i; break
        # pass 2: a bare `:N` continuation — find the line whose number tokens fall in the window and whose
        # nearest preceding path token is the region's file
        if hit is None:
            base = region["file"].rsplit("/", 1)[-1]
            for i, ln in enumerate(lines):
                if base not in ln: continue
                for n in range(region["lo"], region["hi"] + 1):
                    if re.search(r"(?<![0-9])" + str(n) + r"(?![0-9])", ln):
                        hit = i; break
                if hit is not None: break
        if hit is None:
            continue
        if src == "review.md":
            # one finding per line; include wrapped continuation lines that carry no new citation
            j = hit
            while j + 1 < len(lines) and lines[j + 1].strip() and not C.citations(lines[j + 1]) and not lines[j + 1].startswith("Verdict"):
                j += 1
            blk = "\n".join(lines[hit:j + 1])
        else:
            blk = F.block_around(text, hit, cap=100000)
            if len(blk) > cap:
                # centre the window on the citing line inside a long block
                pos = blk.find(lines[hit])
                s = max(0, pos - cap // 2); blk = ("…" if s else "") + blk[s:s + cap] + ("…" if s + cap < len(blk) else "")
        out.append({"source": src, "excerpt": blk if len(blk) <= cap + 2 else blk[:cap] + " …[truncated]"})
    return out

def main():
    lead = json.load(open(os.path.join(C.DATA, "fp-sample.json")))
    recs = {r["run_id"]: r for r in json.load(open(os.path.join(C.DATA, "runs.json")))}
    changed = []
    for p in lead:
        r = recs[p["run_id"]]
        region = next(rg for rg in r["stray_regions"] if rg["file"] == p["file"] and rg["lo"] == p["lines"][0] and rg["hi"] == p["lines"][1])
        old_ok = any(excerpt_hits(x, region) for x in p["findings"])
        blocks = citing_blocks_v2(r["run_dir"], p["sources"], region)
        new = [b["excerpt"] for b in blocks]
        new_ok = any(excerpt_hits(x, region) for x in new)
        if not old_ok:
            changed.append((p["packet_id"], p["arm"], new_ok))
        p["findings"] = new if new else p["findings"]
        p["finding_sources"] = [b["source"] for b in blocks]
        p["excerpt_cites_region"] = new_ok
    json.dump(lead, open(os.path.join(C.DATA, "fp-sample.json"), "w"), indent=1)
    blind = [{k: p[k] for k in ("packet_id", "pr", "file", "lines", "region_in_diff", "nearest_hunk_distance", "enclosing_symbol", "findings", "head_context", "diff_hunk")} for p in lead]
    json.dump(blind, open(os.path.join(C.DATA, "fp-packets-blind.json"), "w"), indent=1)
    with open(os.path.join(C.DATA, "fp-packets-blind.md"), "w") as f:
        for p in blind:
            if p["region_in_diff"]: where = "inside the PR's diff"
            elif p["nearest_hunk_distance"] is None: where = "OUTSIDE the PR's diff (file not changed by the PR)"
            else: where = f"OUTSIDE the PR's diff (nearest changed line {p['nearest_hunk_distance']} lines away)"
            f.write(f"\n\n## {p['packet_id']} — {p['pr']} · `{p['file']}` lines {p['lines'][0]}–{p['lines'][1]} · region {where} · enclosing symbol: {p['enclosing_symbol'] or '—'}\n\n")
            f.write("### The reviewer's finding(s) citing this region\n\n")
            for x in p["findings"] or ["(no isolated excerpt)"]:
                f.write("```text\n" + x + "\n```\n\n")
            f.write("### Head file context (line| text)\n\n```text\n" + (p["head_context"] or "(file not present in head/)") + "\n```\n")
            if p["diff_hunk"]:
                f.write("\n### The PR's diff hunk covering these lines\n\n```diff\n" + p["diff_hunk"] + "\n```\n")
    print(f"repackaged {len(lead)} packets; previously mis-packaged (excerpt did not cite the region): {len(changed)}")
    print("  ", ", ".join(f"{pid}({arm[:2]}{'' if ok else ',still-none'})" for pid, arm, ok in changed))
    print("now citing the region:", sum(1 for p in lead if p["excerpt_cites_region"]), "of", len(lead))
    with open(os.path.join(C.DATA, "fp-relabel-ids.txt"), "w") as f:
        f.write("\n".join(pid for pid, _, _ in changed) + "\n")

if __name__ == "__main__":
    main()
