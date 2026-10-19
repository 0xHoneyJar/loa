"""fp_sample.py — a stratified (arm × PR) seeded sample of ~60 flagged regions that matched no planted
label, packaged blind (no arm, no run id) for two independent labelers. Writes data/fp-sample.json (lead
copy, with provenance) and data/fp-packets-blind.json + .md (what the labelers see)."""
import json, os, random, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as C

SEED = 20261015
ALLOC = {("a0_bare", "pr-05"): 5, ("a0_bare", "pr-08"): 6, ("a0_bare", "pr-12"): 8, ("a0_bare", "pr-13"): 8,
         ("a1_full", "pr-05"): 8, ("a1_full", "pr-08"): 8, ("a1_full", "pr-12"): 9, ("a1_full", "pr-13"): 9}

def block_around(text, line_idx, cap=1600):
    lines = text.split("\n")
    lo = line_idx
    while lo > 0 and lines[lo - 1].strip(): lo -= 1
    hi = line_idx
    while hi + 1 < len(lines) and lines[hi + 1].strip(): hi += 1
    blk = "\n".join(lines[lo:hi + 1])
    return blk if len(blk) <= cap else blk[:cap] + " …[truncated]"

def citing_blocks(run_dir, sources, region):
    """the finding text that cites the region, per source file (the paragraph/table block holding the citation);
    falls back to a basename+line-number scan when the citation is a bare `:N` continuation inside a table"""
    out = []
    paths = {"review.md": os.path.join(run_dir, "sandbox", "review.md"),
             "engineer-feedback.md": os.path.join(run_dir, "sandbox/grimoires/loa/a2a/sprint-1/engineer-feedback.md"),
             "auditor-sprint-feedback.md": os.path.join(run_dir, "sandbox/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md")}
    base = region["file"].rsplit("/", 1)[-1]
    nums = {str(n) for n in range(region["lo_w"], region["hi_w"] + 1)}
    for src in sources:
        p = paths.get(src)
        if not p: continue
        text = C.read_text(p) or ""
        lines = text.split("\n")
        hit = None
        for i, ln in enumerate(lines):
            if ":" not in ln: continue
            for cp, a, b in C.citations(ln):
                if C.strip_side(cp) == region["file"] and not (b < region["lo_w"] or a > region["hi_w"]):
                    hit = i; break
            if hit is not None: break
        if hit is None:
            last_path_line = -99
            for i, ln in enumerate(lines):
                if base in ln: last_path_line = i
                if i - last_path_line <= 3 and any(re.search(r"(?<![0-9])" + n + r"(?![0-9])", ln) for n in nums) and ":" in ln:
                    hit = i; break
        if hit is not None:
            out.append({"source": src, "excerpt": block_around(text, hit)})
    return out

def hunk_text(pr, file, lo, hi, cap_lines=70):
    """the head.diff hunk(s) covering head lines lo..hi of file"""
    lines = (C.read_text(os.path.join(C.FIXTURES, pr, "head.diff")) or "").split("\n")
    out, cur, hl, keep = [], None, None, False
    buf = []
    for ln in lines:
        if ln.startswith("diff --git "):
            m = re.match(r"diff --git a/(\S+) b/(\S+)", ln); cur = m.group(2) if m else None; hl = None
        elif ln.startswith("@@") and cur:
            if keep and buf: out.extend(buf)
            buf, keep = [], False
            m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", ln)
            hl = int(m.group(1)) if m else None
            if cur == file and hl is not None:
                n = int(m.group(2)) if m.group(2) is not None else 1
                keep = not (hi < hl - 3 or lo > hl + n - 1 + 3)
                buf = [ln]
        elif hl is not None and cur == file and keep:
            buf.append(ln)
    if keep and buf: out.extend(buf)
    return "\n".join(out[:cap_lines]) + ("\n…[hunk truncated]" if len(out) > cap_lines else "")

def context(pr, file, lo, hi, pad=10):
    lines = C.head_lines(pr, file)
    if lines is None:
        return None
    a, b = max(1, lo - pad), min(len(lines), hi + pad)
    return "\n".join(f"{n:5d}| {lines[n-1]}" for n in range(a, b + 1))

def main():
    recs = json.load(open(os.path.join(C.DATA, "runs.json")))
    strata = {}
    for r in recs:
        for i, rg in enumerate(r["stray_regions"]):
            strata.setdefault((r["arm"], r["pr"]), []).append((r, i, rg))
    rnd = random.Random(SEED)
    sample = []
    for key, n in ALLOC.items():
        pool = strata[key]
        pick = pool if len(pool) <= n else rnd.sample(pool, n)
        for r, i, rg in pick:
            sample.append((r, i, rg))
    # replacement draws (same stratum) for regions whose finding text cannot be isolated
    def excerpts_ok(r, rg):
        return bool(citing_blocks(r["run_dir"], rg["sources"], rg))
    final = []
    used = {(r["run_id"], i) for r, i, rg in sample}
    for r, i, rg in sample:
        if excerpts_ok(r, rg):
            final.append((r, i, rg)); continue
        pool = [(r2, j, rg2) for r2, j, rg2 in strata[(r["arm"], r["pr"])] if (r2["run_id"], j) not in used]
        rnd.shuffle(pool)
        rep = next(((r2, j, rg2) for r2, j, rg2 in pool if excerpts_ok(r2, rg2)), None)
        if rep:
            used.add((rep[0]["run_id"], rep[1])); final.append(rep)
        else:
            final.append((r, i, rg))
    sample = final
    rnd.shuffle(sample)
    hunks_cache = {}
    lead, blind = [], []
    for k, (r, i, rg) in enumerate(sample, 1):
        pid = f"P{k:02d}"
        man = C.load_manifest(r["pr"])
        near = []
        lines = C.head_lines(r["pr"], rg["file"])
        sym = C.enclosing_symbol(lines, rg["lo"]) if lines else None
        for d in man["defects"]:
            if C.path_matches(rg["file"], d["file"]):
                for s_ in C.defect_sites(d):
                    dsym = C.enclosing_symbol(lines, s_) if lines else None
                    if abs(s_ - rg["lo"]) <= 40 or (sym and dsym == sym):
                        near.append({"defect": d["id"], "site": s_, "distance": abs(s_ - rg["lo"]), "same_symbol": bool(sym and dsym == sym)})
        blocks = citing_blocks(r["run_dir"], rg["sources"], rg)
        pkt = {"packet_id": pid, "pr": r["pr"], "file": rg["file"], "lines": [rg["lo"], rg["hi"]],
               "region_in_diff": rg["in_diff"], "nearest_hunk_distance": rg["hunk_distance"],
               "enclosing_symbol": sym, "findings": [b["excerpt"] for b in blocks],
               "head_context": context(r["pr"], rg["file"], rg["lo"], rg["hi"]),
               "diff_hunk": hunk_text(r["pr"], rg["file"], rg["lo"], rg["hi"]) if rg["in_diff"] else None}
        blind.append(pkt)
        lead.append(dict(pkt, arm=r["arm"], run_id=r["run_id"], trial=r["trial"], sources=rg["sources"],
                         cites=rg["cites"], near_planted=near, finding_sources=[b["source"] for b in blocks]))
    json.dump(lead, open(os.path.join(C.DATA, "fp-sample.json"), "w"), indent=1)
    json.dump(blind, open(os.path.join(C.DATA, "fp-packets-blind.json"), "w"), indent=1)
    with open(os.path.join(C.DATA, "fp-packets-blind.md"), "w") as f:
        for p in blind:
            if p["region_in_diff"]:
                where = "inside the PR's diff"
            elif p["nearest_hunk_distance"] is None:
                where = "OUTSIDE the PR's diff (file not changed by the PR)"
            else:
                where = f"OUTSIDE the PR's diff (nearest changed line {p['nearest_hunk_distance']} lines away)"
            f.write(f"\n\n## {p['packet_id']} — {p['pr']} · `{p['file']}` lines {p['lines'][0]}–{p['lines'][1]} · region {where} · enclosing symbol: {p['enclosing_symbol'] or '—'}\n\n")
            f.write("### The reviewer's finding(s) citing this region\n\n")
            for x in p["findings"] or ["(the citation sits in a table or list whose text could not be isolated; judge from the context)"]:
                f.write("```text\n" + x + "\n```\n\n")
            f.write("### Head file context (line| text)\n\n```text\n" + (p["head_context"] or "(file not present in head/)") + "\n```\n")
            if p["diff_hunk"]:
                f.write("\n### The PR's diff hunk covering these lines\n\n```diff\n" + p["diff_hunk"] + "\n```\n")
    n_empty = sum(1 for p in blind if not p["findings"])
    print(f"{len(blind)} packets; strata:", {f"{a}/{p}": sum(1 for x in lead if x['arm']==a and x['pr']==p) for (a,p) in ALLOC})
    print(f"packets without an isolated finding excerpt: {n_empty}; in_diff: {sum(1 for p in blind if p['region_in_diff'])}; near a planted site: {sum(1 for x in lead if x['near_planted'])}")
    print("universe:", {f"{a}/{p}": len(v) for (a,p), v in sorted(strata.items())})

if __name__ == "__main__":
    main()
