"""build_packets.py — cycle-131 Task 1.10: blind adjudication packets for the same-scope grader credits (python3 -I, stdlib).

Pool (pre-registered 2026-10-19T06:08:48Z): over the 36 cycle-130 review-catch runs re-graded under grader 1.3.0 with the
current (curated) manifests, (a) every (run, defect) in recall.credits_function_only and (b) every (run, defect) credited by
the anchor expansion alone (in missed_pm3_v1 and not in missed_pm3), deduplicated by (run_id, defect). Sample: 20 from (a)
(fewer eligible -> all) and up to 10 from (b), stratified by arm x PR proportionally, seed 20261015. Packets are blind.
The citation parser is the grader's own (common.py execs the grader's citation section)."""
import json, os, re, sys, random, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "analysis-2026-10", "scripts"))
import common as C

REGRADE = os.path.expanduser("~/.cache/loa/cycle-131/regrade")
KEY_DIR = os.path.expanduser("~/.cache/loa/cycle-131"); os.makedirs(KEY_DIR, exist_ok=True)
SEED = 20261015
REPL_PR = {"review-r17": "pr-17", "review-r18": "pr-18"}

def all_runs():
    runs = list(C.valid_runs())
    for arm in ("a0_bare", "a1_full"):
        for task, pr in REPL_PR.items():
            for t in (1, 2, 3):
                runs.append({"arm": arm, "task": task, "pr": pr, "trial": t,
                             "run_id": f"replication-01-{arm}-{task}-t{t}",
                             "run_dir": os.path.join(C.REPO, "evals/results/ablation-2.0/replication-01", arm, f"{task}-t{t}")})
    return runs

def load_v1(pr):
    with open(os.path.join(C.MANIFESTS, "v1", pr + ".json"), encoding="utf-8") as f:
        return json.load(f)

SOURCES = {"review.md": "sandbox/review.md",
           "engineer-feedback.md": "sandbox/grimoires/loa/a2a/sprint-1/engineer-feedback.md",
           "auditor-sprint-feedback.md": "sandbox/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md"}

def source_lines(run_dir):
    out = {}
    for name, rel in SOURCES.items():
        t = C.read_text(os.path.join(run_dir, rel))
        if t is not None:
            out[name] = t.split("\n")
    return out

def line_cites(srcs):
    """[(source, line_idx, path, a, b)] for every citation, line by line (the grader parses the whole text; a
    citation never spans lines, so per-line parsing finds the same set except bare-:N continuations, handled below)"""
    out = []
    for name, lines in srcs.items():
        last_path = None
        for i, ln in enumerate(lines):
            cs = C.citations(ln)
            if cs:
                for p, a, b in cs:
                    out.append((name, i, p, a, b)); last_path = p
    return out

# ---- enclosing definition (the grader's rule, re-implemented for packet selection only; the grade itself is the grader's)
_H_BASH = [re.compile(r"^(\s*)(?:function\s+)?[A-Za-z_][A-Za-z0-9_.:-]*\s*\(\)\s*\{?"), re.compile(r"^(\s*)function\s+[A-Za-z_][A-Za-z0-9_]*\s*\{")]
_H_PY = [re.compile(r"^(\s*)def\s+[A-Za-z_][A-Za-z0-9_]*\s*\(")]
_H_BATS = [re.compile(r'^(\s*)@test\s+"')]
_H_MD = [re.compile(r"^(\s*)(#{1,6})\s")]
def headers(lines, file):
    ext = file.rsplit(".", 1)[-1].lower() if "." in file else ""
    if ext in ("sh", "bash") or (lines and lines[0].startswith("#!") and ("bash" in lines[0] or "sh" in lines[0]) and ext not in ("py", "md", "bats")):
        pats, kind = _H_BASH, "bash"
    elif ext == "py": pats, kind = _H_PY, "py"
    elif ext == "bats": pats, kind = _H_BATS + _H_BASH, "bats"
    elif ext in ("md", "markdown"): pats, kind = _H_MD, "md"
    else: return None, None
    hs = []
    for i, ln in enumerate(lines, 1):
        for p in pats:
            m = p.match(ln)
            if m:
                lvl = len(m.group(2)) if kind == "md" else len(m.group(1))
                hs.append((i, lvl)); break
    return hs, kind

def definition_of(lines, hs, kind, line):
    """header line number of the innermost definition holding `line`, else None (top-level); > 400 lines -> None"""
    if not hs: return None
    best = None
    for idx, (h, lvl) in enumerate(hs):
        if h > line: break
        # end: next header at same-or-lower indentation (md: same-or-higher level = smaller/equal number), else EOF
        end = len(lines)
        for h2, l2 in hs[idx + 1:]:
            if (kind == "md" and l2 <= lvl) or (kind != "md" and l2 <= lvl):
                end = h2 - 1; break
        if kind in ("bash", "bats"):
            ind = lvl
            for j in range(h, min(end, len(lines)) + 1):
                s = lines[j - 1]
                if j > h and s.strip() == "}" and (len(s) - len(s.lstrip())) == ind:
                    end = j; break
                if j == h and s.rstrip().endswith("}") and "{" in s:
                    end = j; break
        elif kind == "py":
            ind = lvl
            for j in range(h + 1, min(end, len(lines)) + 1):
                s = lines[j - 1]
                if s.strip() and not s.lstrip().startswith("#") and (len(s) - len(s.lstrip())) <= ind:
                    end = j - 1; break
        if h <= line <= end:
            best = (h, end)  # innermost = latest header holding the line
    if best is None: return None
    if best[1] - best[0] + 1 > 400: return None
    return best[0]

_SRC_CACHE = {}
def label_block(d):
    """the human finding's text: a record fixture's `source` (record/<ref>:<path>#L<n>) read from the local record branch,
    from line n to the line before the next heading (at most 14 lines); a synthetic fixture's description fields otherwise"""
    src = d.get("source")
    if isinstance(src, str) and ":" in src and "#L" in src:
        ref_path, _, frag = src.rpartition("#L")
        ref, _, path = ref_path.partition(":")
        n = int(re.match(r"\d+", frag).group(0))
        key = (ref, path)
        if key not in _SRC_CACHE:
            try:
                out = subprocess.run(["git", "-C", C.REPO, "show", f"origin/{ref}:{path}"], check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode("utf-8", "replace")
                _SRC_CACHE[key] = out.split("\n")
            except Exception:
                _SRC_CACHE[key] = None
        lines = _SRC_CACHE[key]
        if lines and 1 <= n <= len(lines):
            end = n
            while end < len(lines) and end - n < 13 and not lines[end].startswith("#"):
                end += 1
            return "\n".join(lines[n - 1:end]).strip()
    for k in ("description", "title", "summary", "finding", "label", "note"):
        if isinstance(d.get(k), str) and d[k].strip():
            return d[k].strip()
    # synthetic record fixtures (pr-01 … pr-10) carry no human finding text: the label is the planted defect's own id,
    # category and planted line (the fix that was reverted to plant it)
    slug = re.sub(r"^[A-Z]\d+-", "", d.get("id", "")).replace("-", " ")
    return f"Planted defect {d.get('id')}: {slug} (category {d.get('category')}, severity {d.get('severity')}). Planted line: `{d.get('must_match')}`"

def within3(a, b, sites):
    return any(not (b < s - 3 or a > s + 3) for s in sites)

def ctx(lines, lo, hi, pad=10):
    lo2, hi2 = max(1, lo - pad), min(len(lines), hi + pad)
    return "\n".join(f"{n:5d}| {lines[n-1]}" for n in range(lo2, hi2 + 1))

def finding_text(srcs, name, idx):
    lines = srcs[name]
    if name == "review.md":
        j = idx
        while j + 1 < len(lines) and lines[j + 1].strip() and not C.citations(lines[j + 1]) and not lines[j + 1].startswith("Verdict"):
            j += 1
        return "\n".join(lines[idx:j + 1])
    lo = idx
    while lo > 0 and lines[lo - 1].strip(): lo -= 1
    hi = idx
    while hi + 1 < len(lines) and lines[hi + 1].strip(): hi += 1
    blk = "\n".join(lines[lo:hi + 1])
    if len(blk) > 1800:
        pos = blk.find(lines[idx]); s = max(0, pos - 900); blk = ("…" if s else "") + blk[s:s + 1800] + "…"
    return blk

def main():
    pool = []
    for r in all_runs():
        g = json.load(open(os.path.join(REGRADE, r["run_id"] + ".grade.json")))["recall"]
        man = C.load_manifest(r["pr"]); v1 = load_v1(r["pr"])
        dcur = C.defect_positions(man); dv1 = C.defect_positions(v1)
        assert [d["id"] for d in man["defects"]] == [d["id"] for d in v1["defects"]], r["pr"]
        srcs = source_lines(r["run_dir"]); cites = line_cites(srcs)
        a_ids = list(g.get("credits_function_only") or [])
        b_ids = [d for d in (g.get("missed_pm3_v1") or []) if d not in set(g.get("missed_pm3") or [])]
        for grp, ids in (("a", a_ids), ("b", b_ids)):
            for did in ids:
                d = dcur[did]; dv = dv1[did]
                s_cur, s_v1 = C.defect_sites(d), C.defect_sites(dv)
                hl = C.head_lines(r["pr"], d["file"]) or []
                hs, kind = headers(hl, d["file"]) if hl else (None, None)
                site_defs = {definition_of(hl, hs, kind, s) for s in s_cur} if hl else set()
                cands, approx = [], False
                for (name, idx, p, a, b) in cites:
                    if not C.path_matches(p, d["file"]): continue
                    if grp == "a":
                        if within3(a, b, s_cur): continue
                        lo, hi = (a, b) if b - a + 1 <= 25 else (a, a)
                        if hl and any(definition_of(hl, hs, kind, ln) in site_defs and definition_of(hl, hs, kind, ln) is not None for ln in range(lo, hi + 1)):
                            cands.append((name, idx, p, a, b))
                    else:
                        if within3(a, b, s_v1): continue
                        if within3(a, b, [s for s in s_cur if s not in s_v1]):
                            cands.append((name, idx, p, a, b))
                if grp == "a" and not cands:
                    approx = True
                    cands = [(n, i, p, a, b) for (n, i, p, a, b) in cites if C.path_matches(p, d["file"]) and not within3(a, b, s_cur)]
                seen, fts, cited, cctx = set(), [], [], []
                for (name, idx, p, a, b) in cands:
                    k = (name, idx)
                    if k not in seen:
                        seen.add(k); fts.append({"source": name, "text": finding_text(srcs, name, idx)})
                    cited.append(f"{p}:{a}" + (f"-{b}" if b != a else ""))
                    if hl: cctx.append(ctx(hl, a, min(b, a + 25)))
                planted = ctx(hl, min(s_cur), max(s_cur)) if hl and s_cur and max(s_cur) - min(s_cur) <= 60 else ("\n…\n".join(ctx(hl, s, s) for s in s_cur) if hl else "")
                pool.append({"run_id": r["run_id"], "arm": r["arm"], "pr": r["pr"], "defect": did, "group": grp, "approx": approx,
                             "n_candidates": len(cands), "label_text": label_block(d), "label_gate": d.get("label_source"), "must_match": d.get("must_match"),
                             "defect_file": d["file"], "sites_cur": s_cur, "sites_v1": s_v1,
                             "finding_texts": fts, "cited": sorted(set(cited)), "head_context_cited": "\n---\n".join(dict.fromkeys(cctx)),
                             "head_context_planted": planted})
    rnd = random.Random(SEED)
    A = [p for p in pool if p["group"] == "a"]; B = [p for p in pool if p["group"] == "b"]
    def stratified(items, n):
        if len(items) <= n: return list(items)
        strata = {}
        for it in items: strata.setdefault((it["arm"], it["pr"]), []).append(it)
        tot = len(items); quotas = {k: n * len(v) / tot for k, v in strata.items()}
        base = {k: int(q) for k, q in quotas.items()}; rem = n - sum(base.values())
        for k in sorted(quotas, key=lambda k: -(quotas[k] - base[k]))[:rem]: base[k] += 1
        out = []
        for k in sorted(strata):
            out += rnd.sample(sorted(strata[k], key=lambda x: (x["run_id"], x["defect"])), min(base[k], len(strata[k])))
        return out
    sa, sb = stratified(sorted(A, key=lambda x: (x["run_id"], x["defect"])), 20), stratified(sorted(B, key=lambda x: (x["run_id"], x["defect"])), 10)
    sample = sa + sb; rnd.shuffle(sample)
    key, blind = [], []
    for i, p in enumerate(sample, 1):
        pid = f"P{i:02d}"
        key.append({"packet_id": pid, **{k: p[k] for k in ("run_id", "arm", "pr", "defect", "group", "approx", "n_candidates", "sites_cur", "sites_v1")}})
        blind.append({"packet_id": pid, "group": p["group"], "defect_file": p["defect_file"], "label_text": p["label_text"], "label_gate": p["label_gate"], "must_match": p["must_match"],
                      "finding_texts": p["finding_texts"], "cited": p["cited"], "head_context_cited": p["head_context_cited"], "head_context_planted": p["head_context_planted"]})
    with open(os.path.join(HERE, "packets.jsonl"), "w", encoding="utf-8") as f:
        for b in blind: f.write(json.dumps(b, ensure_ascii=False) + "\n")
    json.dump({"seed": SEED, "pool_a": len(A), "pool_b": len(B), "sampled_a": len(sa), "sampled_b": len(sb),
               "strata_a": sorted({(p["arm"], p["pr"]) for p in A}), "strata_b": {f"{k[0]}|{k[1]}": v for k, v in sorted({(x["arm"], x["pr"]): sum(1 for y in B if (y["arm"], y["pr"]) == (x["arm"], x["pr"])) for x in B}.items())},
               "key": key, "pool": [{k: p[k] for k in ("run_id", "arm", "pr", "defect", "group", "approx", "n_candidates")} for p in pool]},
              open(os.path.join(KEY_DIR, "adjudication-key.json"), "w"), indent=1)
    print(f"pool a={len(A)} b={len(B)}; sampled a={len(sa)} b={len(sb)}; packets -> {os.path.join(HERE, 'packets.jsonl')}; key -> {KEY_DIR}/adjudication-key.json")
    for k in key: print(k["packet_id"], k["group"], k["arm"], k["pr"], k["defect"], "approx" if k["approx"] else "", "cands", k["n_candidates"])

if __name__ == "__main__":
    main()
