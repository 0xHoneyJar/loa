"""common.py — shared loaders for the cycle-130 deep analysis (python3 -I, stdlib only).

The citation parser and the matching rule are NOT re-implemented: the exact source text of
ablation-grade.sh's citation section (recall-vs-defects 1.1.2 parser + false_positives) is
sliced out of the grader file and exec'd, so this analysis credits exactly what the grader
credits. If the grader's section markers move, this module fails loudly.
"""
import json, os, re, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", ".."))
BATCHES = os.path.join(REPO, "grimoires/loa/reports/ablation-2.0/batches")
FIXTURES = os.path.join(REPO, "evals/fixtures/review-prs")
MANIFESTS = os.path.join(FIXTURES, "manifests")
RUNS_JSONL = os.path.join(REPO, "grimoires/loa/reports/ablation-2.0/runs.jsonl")
GRADER = os.path.join(REPO, "evals/harness/ablation-grade.sh")
OUT = os.path.join(REPO, "grimoires/loa/a2a/analysis-2026-10")
DATA = os.path.join(OUT, "data")

TASK_PR = {"review-01": "pr-05", "review-02": "pr-08", "review-03": "pr-12", "review-04": "pr-13"}
# the valid cells (reads-v2.md: a1 review-01..03 from priority-v2-p1b, the -r2 dirs for trial 1; review-04 from priority-v2-p1)
def valid_runs():
    runs = []
    for task in ("review-01", "review-02", "review-03", "review-04"):
        for t in (1, 2, 3):
            runs.append({"arm": "a0_bare", "task": task, "pr": TASK_PR[task], "trial": t,
                         "run_id": f"priority-v2-p1-a0_bare-{task}-t{t}",
                         "run_dir": os.path.join(BATCHES, "priority-v2-p1", "a0_bare", f"{task}-t{t}")})
            if task == "review-04":
                runs.append({"arm": "a1_full", "task": task, "pr": TASK_PR[task], "trial": t,
                             "run_id": f"priority-v2-p1-a1_full-{task}-t{t}",
                             "run_dir": os.path.join(BATCHES, "priority-v2-p1", "a1_full", f"{task}-t{t}")})
            else:
                d = f"{task}-t{t}-r2" if t == 1 else f"{task}-t{t}"
                runs.append({"arm": "a1_full", "task": task, "pr": TASK_PR[task], "trial": t,
                             "run_id": f"priority-v2-p1b-a1_full-{task}-t{t}",
                             "run_dir": os.path.join(BATCHES, "priority-v2-p1b", "a1_full", d)})
    for r in runs:
        assert os.path.isfile(os.path.join(r["run_dir"], "grade.json")), r["run_dir"]
    return runs

def load_manifest(pr):
    with open(os.path.join(MANIFESTS, pr + ".json"), encoding="utf-8") as f:
        return json.load(f)

def defect_positions(man):
    """grade.json names defects by position d1..dN (never by id)"""
    return {f"d{i}": d for i, d in enumerate(man.get("defects") or [], 1)}

# ---------------------------------------------------------------- the grader's own parser, exec'd verbatim
def _grader_namespace():
    src = open(GRADER, encoding="utf-8").read()
    a = src.index("# ------------------------------------------------------------------ citations (recall-vs-defects 1.1.2 parser)")
    b = src.index("def envelope_texts(")
    c = src.index("def false_positives(cites, defects):")
    d = src.index("def grade_recall(")
    code = src[a:b] + "\n" + src[c:d]
    ns = {"re": re, "json": json, "os": os}
    exec(compile(code, GRADER + "#citations", "exec"), ns)
    for name in ("citations", "norm_path", "strip_side", "path_matches", "false_positives", "CITE", "TRAILER"):
        assert name in ns, name
    return ns

G = _grader_namespace()
citations = G["citations"]
path_matches = G["path_matches"]
strip_side = G["strip_side"]
grader_false_positives = G["false_positives"]

def envelope_texts(env):
    """same extraction as the grader's envelope_texts, on a parsed envelope"""
    out = []
    for f in (env.get("findings") or []) if isinstance(env, dict) else []:
        if not isinstance(f, dict):
            continue
        if isinstance(f.get("anchor"), str):
            out.append(f["anchor"])
        fp = f.get("file") or f.get("path")
        ln = f.get("line") or f.get("line_start") or f.get("start_line")
        if isinstance(fp, str) and isinstance(ln, int):
            out.append(f"{fp}:{ln}")
    return out

def defect_sites(d):
    return [s for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int)]

def cite_hits_defect(cite, d):
    p, a, b = cite
    return path_matches(p, d["file"]) and any(not (b < s - 3 or a > s + 3) for s in defect_sites(d))

def detected(cites, defects):
    """the grader's rule: defect detected when any citation hits any of its sites (±3)"""
    return [d["id"] for d in defects if any(cite_hits_defect(c, d) for c in cites)]

def stray_regions(cites, defects):
    """the grader's false-positive regions, but returned (not only counted): per file the merged
    ±3 windows of the citations that hit no anchor; each region lists its own citations."""
    anchors = [(d.get("file", ""), s) for d in defects for s in defect_sites(d)]
    stray = {}
    for p, a, b in cites:
        if any(path_matches(p, f) and not (b < s - 3 or a > s + 3) for f, s in anchors):
            continue
        stray.setdefault(strip_side(p), []).append((a - 3, b + 3, a, b, p))
    regions = []
    for f, wins in stray.items():
        cur = None
        for lo, hi, a, b, p in sorted(wins):
            if cur is None or lo > cur["hi_w"]:
                if cur is not None:
                    regions.append(cur)
                cur = {"file": f, "lo_w": lo, "hi_w": hi, "lo": a, "hi": b, "cites": [[p, a, b]]}
            else:
                cur["hi_w"] = max(cur["hi_w"], hi); cur["lo"] = min(cur["lo"], a); cur["hi"] = max(cur["hi"], b)
                cur["cites"].append([p, a, b])
        if cur is not None:
            regions.append(cur)
    return regions

# ---------------------------------------------------------------- the PR diff
def diff_hunks(pr):
    """head-side changed ranges per file from head.diff: {file: [(start, end), ...]}"""
    hunks = {}
    cur = None
    with open(os.path.join(FIXTURES, pr, "head.diff"), encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("diff --git "):
                m = re.match(r"diff --git a/(\S+) b/(\S+)", line)
                cur = m.group(2) if m else None
                if cur:
                    hunks.setdefault(cur, [])
            elif line.startswith("@@") and cur:
                m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
                if m:
                    s = int(m.group(1)); n = int(m.group(2)) if m.group(2) is not None else 1
                    hunks[cur].append((s, max(s, s + n - 1)))
    return hunks

def diff_line_map(pr):
    """{(file, head_line): line number in head.diff} for every '+' and context line"""
    out = {}
    cur = None; hl = None
    with open(os.path.join(FIXTURES, pr, "head.diff"), encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f, 1):
            if line.startswith("diff --git "):
                m = re.match(r"diff --git a/(\S+) b/(\S+)", line); cur = m.group(2) if m else None; hl = None
            elif line.startswith("@@") and cur:
                m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)", line); hl = int(m.group(1)) if m else None
            elif hl is not None and cur:
                if line.startswith("+") and not line.startswith("+++"):
                    out[(cur, hl)] = n; hl += 1
                elif line.startswith(" "):
                    out[(cur, hl)] = n; hl += 1
                elif line.startswith("-") and not line.startswith("---"):
                    pass
                elif line.startswith("\\"):
                    pass
    return out

def in_diff(hunks, file, lo, hi, slack=3):
    for s, e in hunks.get(file, []):
        if not (hi < s - slack or lo > e + slack):
            return True
    return False

def nearest_hunk_distance(hunks, file, line):
    best = None
    for s, e in hunks.get(file, []):
        d = 0 if s <= line <= e else min(abs(line - s), abs(line - e))
        best = d if best is None else min(best, d)
    return best

def head_lines(pr, file):
    p = os.path.join(FIXTURES, pr, "head", file)
    if not os.path.isfile(p):
        return None
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read().split("\n")

_FN = re.compile(r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_.:-]*)\s*\(\)\s*\{?\s*(#.*)?$")
_FN2 = re.compile(r"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{")
_PYFN = re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
_BATS = re.compile(r'^@test\s+"([^"]*)"')
def enclosing_symbol(lines, line):
    """the function (bash/python) or @test (bats) enclosing head line `line` (1-based), else None"""
    if not lines or line < 1:
        return None
    for i in range(min(line, len(lines)) - 1, -1, -1):
        s = lines[i]
        m = _FN.match(s) or _FN2.match(s) or _PYFN.match(s) or _BATS.match(s)
        if m:
            return m.group(1)
    return None

# ---------------------------------------------------------------- transcripts
def read_events(path):
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            ev["_i"] = i
            out.append(ev)
    return out

def assistant_authored(ev):
    """(kind, text) pairs the assistant produced in this event: text blocks, tool inputs"""
    if ev.get("type") != "assistant":
        return []
    out = []
    for blk in (ev.get("message") or {}).get("content") or []:
        if not isinstance(blk, dict):
            continue
        if blk.get("type") == "text" and isinstance(blk.get("text"), str):
            out.append(("text", blk["text"]))
        elif blk.get("type") == "tool_use":
            inp = blk.get("input") or {}
            name = blk.get("name") or "?"
            if isinstance(inp, dict):
                if "command" in inp and isinstance(inp["command"], str):
                    out.append((f"tool:{name}", inp["command"]))
                elif "content" in inp and isinstance(inp["content"], str):
                    out.append((f"tool:{name}", (inp.get("file_path") or "") + "\n" + inp["content"]))
                else:
                    out.append((f"tool:{name}", json.dumps(inp)))
    return out

def tool_results(ev):
    """tool_result content strings of a user event"""
    if ev.get("type") != "user":
        return []
    out = []
    for blk in (ev.get("message") or {}).get("content") or []:
        if isinstance(blk, dict) and blk.get("type") == "tool_result":
            c = blk.get("content")
            if isinstance(c, str):
                out.append(c)
            elif isinstance(c, list):
                out.append("\n".join(x.get("text", "") for x in c if isinstance(x, dict)))
    return out

def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None

def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None
