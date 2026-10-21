#!/usr/bin/env bash
# =============================================================================
# annotation-packets.sh — the blind annotators' packet for one review-catch
# record fixture (cycle-132 FR-2, SDD §1.4 "Annotation packets and merge",
# §5.2, D-7.6)
#
# Usage:
#   annotation-packets.sh <fixture> [--incidents F | --no-incidents] [--out DIR]
#                         [--context 12] [--deny-dir DIR]… [--repo <git dir>]
#                         [--corpus <evals/fixtures/review-prs>]
#
#   <fixture>       pr-NN (under --corpus) or a fixture directory (fixture.yaml,
#                   head/, head.diff)
#   --incidents F   the incident-scan.sh TSV (default <corpus>/incidents/pr-NN.tsv;
#                   evidence read from <dir of F>/pr-NN/evidence/); missing → exit 1
#   --no-incidents  write incidents.md with no entry (a fixture never scanned)
#   --out DIR       default grimoires/loa/a2a/sprint-1/annotation/packets
#   --context N     head lines shown before and after each hunk (default 12, 0…100)
#   --deny-dir DIR  a run directory (evals/results/…) whose text lines must not
#                   appear in the packet; repeatable
#
# Writes (replacing an earlier packet of the fixture):
#   <out>/pr-NN/codebook.md   evals/harness/annotation/codebook.md, verbatim
#   <out>/pr-NN/hunks.md      every hunk of `git diff -U0 --inter-hunk-context=3
#                             <head> <fix> -- <fixture head files>`: id H01 …, the
#                             path, the head-side range, N lines of head context
#                             from the fixture's head/ copy (changed head lines
#                             marked `>`), the hunk text; sorted by path, then line
#   <out>/pr-NN/incidents.md  every incident row (I01 … as in the TSV) with its
#                             evidence file, quoted in fences, capped at 200 lines
#   <out>/pr-NN.hunks.meta.json   OUTSIDE the packet directory (never shown to an
#                             annotator): per hunk {file, head_start, head_end,
#                             insertion, review_driven, cited_by[]}
#
# review_driven (D-7.6): true when the sprint's record-branch feedback — every
# engineer-feedback*, auditor-sprint-feedback*, bridgebuilder*, bb-triage* and
# adversarial-review*/adversarial-audit* file in the directories of the fixture's
# feedback_files — cites the hunk's file at a head-side line within ±3 of the hunk
# (`path:N`, `path:N-M`, `path#LN`, or a dissent finding's anchor/anchor_line), or
# quotes a backticked snippet (≥ 8 characters) that occurs in the hunk's lines
# when the file's basename is named within 1,500 characters of the quote. A
# citation's path resolves to a fixture file by exact path, by `/`-suffix or by a
# basename unique among the fixture's files.
#
# Leak check (fails closed): before anything is written, every packet line is
# compared (whitespace-normalised, ≥ 20 characters; the `> NNN | ` and diff
# prefixes removed as a second form) with every line of the fixture's labels
# (labels/pr-NN.tsv, labels/pr-NN.dropped.txt, labels/review/pr-NN.tsv), its
# manifests (manifests/pr-NN.json, manifests/c131/, manifests/v1/), the feedback
# files above and every text file under each --deny-dir. A match exits 1, prints
# the packet line and its source, and writes nothing. Lines of the fixture's own
# code (head/, base/ and the diffs shown) are exempt: a feedback file may quote code.
# Every written file must also pass evals/graders/no-secrets.sh.
#
# Deterministic: sorted paths, fixed formats, no timestamps, no absolute paths.
# Exit: 0 written, 1 refused (fixture/commit/incidents missing, leak, secret), 2 usage
# Tested by evals/tests/annotation-packets.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec python3 -I - "$REPO_ROOT" "$@" <<'PY'
import argparse, bisect, json, os, re, shutil, subprocess, sys, tempfile

HARNESS_ROOT = sys.argv[1]
ap = argparse.ArgumentParser(prog="annotation-packets.sh")
ap.add_argument("fixture")
ap.add_argument("--incidents"); ap.add_argument("--no-incidents", action="store_true")
ap.add_argument("--out", default=os.path.join(HARNESS_ROOT, "grimoires", "loa", "a2a", "sprint-1", "annotation", "packets"))
ap.add_argument("--context", type=int, default=12)
ap.add_argument("--deny-dir", action="append", default=[])
ap.add_argument("--repo", default=HARNESS_ROOT)
ap.add_argument("--corpus", default=os.path.join(HARNESS_ROOT, "evals", "fixtures", "review-prs"))
try:
    args = ap.parse_args(sys.argv[2:])
except SystemExit as e:
    sys.exit(2 if e.code else 0)

def fail(msg, code=1):
    print(f"annotation-packets: {msg}", file=sys.stderr)
    sys.exit(code)

if not 0 <= args.context <= 100:
    fail("--context must be 0 … 100", 2)
if args.incidents and args.no_incidents:
    fail("--incidents and --no-incidents exclude each other", 2)
REPO, CORPUS = os.path.abspath(args.repo), os.path.abspath(args.corpus)
CODEBOOK = os.path.join(HARNESS_ROOT, "evals", "harness", "annotation", "codebook.md")
NO_SECRETS = os.path.join(HARNESS_ROOT, "evals", "graders", "no-secrets.sh")
MIN_LEAK = 20
CAP_LINES = 200

def git(*a, check=True):
    p = subprocess.run(["git", "-C", REPO, *a], capture_output=True, text=True, errors="replace")
    if check and p.returncode != 0:
        fail(f"git {' '.join(a[:3])} failed: {p.stderr.strip()[:300]}")
    return p.stdout

def rev(r):
    p = subprocess.run(["git", "-C", REPO, "rev-parse", "--verify", "--quiet", f"{r}^{{commit}}"], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None

# --- fixture --------------------------------------------------------------------------------
if re.match(r"^pr-[0-9]{2}$", args.fixture):
    fdir, fx = os.path.join(CORPUS, args.fixture), args.fixture
else:
    fdir = os.path.abspath(args.fixture); fx = os.path.basename(fdir.rstrip("/"))
    if not re.match(r"^pr-[0-9]{2}$", fx):
        fail(f"fixture directory must be named pr-NN: {args.fixture}", 2)
fy = os.path.join(fdir, "fixture.yaml")
if not (os.path.isfile(fy) and os.path.isdir(os.path.join(fdir, "head"))):
    fail(f"{fx}: fixture.yaml or head/ missing under {fdir}")
meta_y, feedback_files, in_fb = {}, [], False
for l in open(fy, encoding="utf-8"):
    l = l.rstrip("\n")
    m = re.match(r'^(head_commit|fix_commit|record_ref):\s*"?([^"#\s]+)"?\s*(#.*)?$', l)
    if m:
        meta_y[m.group(1)] = m.group(2)
    if re.match(r"^feedback_files:\s*$", l):
        in_fb = True; continue
    if in_fb:
        m = re.match(r'^\s+-\s+"?([^"]+)"?\s*$', l)
        if m:
            feedback_files.append(m.group(1)); continue
        in_fb = False
for k in ("head_commit", "fix_commit"):
    if k not in meta_y:
        fail(f"{fx}: fixture.yaml has no {k}")
head, fixc = rev(meta_y["head_commit"]), rev(meta_y["fix_commit"])
if head is None or fixc is None:
    fail(f"{fx}: head or fix commit not in {REPO}")
record_ref = meta_y.get("record_ref")

HEAD_DIR = os.path.join(fdir, "head")
files = []
for root, dirs, names in os.walk(HEAD_DIR):
    dirs.sort()
    for n in names:
        p = os.path.join(root, n)
        if os.path.isfile(p) and not os.path.islink(p):
            files.append(os.path.relpath(p, HEAD_DIR).replace(os.sep, "/"))
files.sort()
if not files:
    fail(f"{fx}: head/ holds no file")
def head_lines(f):
    return open(os.path.join(HEAD_DIR, f), encoding="utf-8", errors="replace").read().splitlines()

SECRET_RX = [re.compile(p) for p in (
    r"AKIA[0-9A-Z]{16}", r"sk-[a-zA-Z0-9]{20,}", r"ghp_[a-zA-Z0-9]{36}", r"gho_[a-zA-Z0-9]{36}",
    r"github_pat_[A-Za-z0-9_]{20,}", r"gh[su]_[a-zA-Z0-9]{36}",
    r"glpat-[a-zA-Z0-9\-]{20,}", r"xox[bpors]-[a-zA-Z0-9\-]+", r"sk-ant-[a-zA-Z0-9\-]{20,}",
    r"AIza[0-9A-Za-z\-_]{35}", r"(?:sk|rk)_(?:live|test)_[0-9a-zA-Z]{20,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]*-----END [A-Z ]*PRIVATE KEY-----",
    r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")]
def redact(t):
    # the seeder's marker: the fixture's head/ copy carries the same replacement
    for r in SECRET_RX:
        t = r.sub("REDACTED-TEST-SECRET", t)
    return t
CTRL = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f  ]")
def safe(t):
    return CTRL.sub(" ", redact(t))

def fence(text_lines, info):
    n = max([3] + [len(m) for l in text_lines for m in re.findall(r"~{3,}", l)]) + 1
    return ["~" * n + info, *text_lines, "~" * n]

# --- hunks ----------------------------------------------------------------------------------
HUNK_RX = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
hunks = []
for f in files:
    out = git("diff", "-U0", "--inter-hunk-context=3", "--no-color", "--no-ext-diff", "--no-renames", head, fixc, "--", f)
    cur = None
    for l in out.splitlines():
        m = HUNK_RX.match(l)
        if m:
            a, n = int(m.group(1)), (int(m.group(2)) if m.group(2) is not None else 1)
            cur = {"file": f, "a": a, "n": n, "header": l.split(" @@", 1)[0] + " @@", "lines": []}
            hunks.append(cur); continue
        if cur is not None and (l[:1] in ("+", "-", " ") or l.startswith("\\ ")):
            if l.startswith("+++ ") or l.startswith("--- "):
                continue
            cur["lines"].append(l)
for i, h in enumerate(hunks, 1):
    h["id"] = f"H{i:02d}"
    if h["n"] == 0:
        h["start"], h["end"], h["insertion"] = max(h["a"], 1), max(h["a"], 1), True
    else:
        h["start"], h["end"], h["insertion"] = h["a"], h["a"] + h["n"] - 1, False

hl_cache = {}
md = [f"# Hunks — {fx}", "",
      f"The later fix changed {len(hunks)} region(s) in {len({h['file'] for h in hunks})} of the change's "
      f"{len(files)} file(s). Line numbers are head-side (the code under review). "
      f"Each entry shows up to {args.context} head lines before and after the region; `>` marks a head line the fix changed.", ""]
code_lines = []   # the fixture's own code shown in the packet (leak-check exempt)
for h in hunks:
    f = h["file"]
    lines = hl_cache.setdefault(f, head_lines(f))
    if h["insertion"]:
        rng = f"insertion after head line {h['a']}" if h["a"] > 0 else "insertion at the top of the file"
        lo, hi = max(1, h["a"] - args.context + 1), min(len(lines), h["a"] + args.context)
    else:
        rng = f"head lines {h['start']}–{h['end']}" if h["end"] > h["start"] else f"head line {h['start']}"
        lo, hi = max(1, h["start"] - args.context), min(len(lines), h["end"] + args.context)
    md += [f"## {h['id']} — {f} — {rng}", "", f"Head context (head/{f}, lines {lo}–{hi}):" if hi >= lo else "Head context: (none)", ""]
    ctx = []
    for n in range(lo, hi + 1):
        mark = ">" if (not h["insertion"] and h["start"] <= n <= h["end"]) else " "
        ctx.append(f"{mark}{n:>5} | {safe(lines[n - 1])}")
    if ctx:
        md += fence(ctx, "text") + [""]
    md += ["The change from head to the fix:", ""]
    body = [h["header"]] + [safe(l) for l in h["lines"]]
    md += fence(body, "diff") + [""]
    code_lines += h["lines"]

# --- incidents ------------------------------------------------------------------------------
inc_rows, inc_src = [], None
if not args.no_incidents:
    tsv = os.path.abspath(args.incidents) if args.incidents else os.path.join(CORPUS, "incidents", f"{fx}.tsv")
    if not os.path.isfile(tsv):
        fail(f"{fx}: incidents file not found: {tsv} (run incident-scan.sh first, or pass --no-incidents)")
    raw = open(tsv, encoding="utf-8").read().splitlines()
    if not raw or raw[0].split("\t") != ["id", "kind", "ref", "date", "files", "excerpt"]:
        fail(f"{tsv}: header must be: id kind ref date files excerpt")
    ev_dir = os.path.join(os.path.dirname(tsv), fx, "evidence")
    for l in raw[1:]:
        c = l.split("\t")
        if len(c) != 6 or not re.match(r"^I[0-9]{2,}$", c[0]):
            fail(f"{tsv}: malformed row {l[:80]!r}")
        r = dict(zip(["id", "kind", "ref", "date", "files", "excerpt"], c))
        r["evidence"] = None
        for ext in (".md", ".diff"):
            p = os.path.join(ev_dir, r["id"] + ext)
            if os.path.isfile(p):
                r["evidence"] = (ext, open(p, encoding="utf-8", errors="replace").read().splitlines())
        inc_rows.append(r)
    inc_src = os.path.relpath(tsv, CORPUS) if tsv.startswith(CORPUS + os.sep) else os.path.basename(tsv)
im = [f"# Incidents — {fx}", "",
      "Things that happened after the change merged and cite one of its files: later fix commits on the main "
      "branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.", ""]
if not inc_rows:
    im += ["No incident was recorded for this change." if not args.no_incidents else "No incident scan was supplied for this change.", ""]
for r in inc_rows:
    # free text sits on its own line so the leak check compares it whole
    im += [f"## {r['id']} — {r['kind']} — {r['date'][:10]}", "",
           f"- reference: {safe(r['ref'])}", f"- files: {safe(r['files'])}", "", "Summary:", "", safe(r["excerpt"]), ""]
    if r["evidence"]:
        ext, ev = r["evidence"]
        shown = [safe(l) for l in ev[:CAP_LINES]]
        if ext == ".diff":
            code_lines += [l for l in ev if l[:1] in ("+", "-", " ")]
        im += ["Evidence" + (f" (first {CAP_LINES} of {len(ev)} lines)" if len(ev) > CAP_LINES else "") + ":", ""]
        im += fence(shown, "diff" if ext == ".diff" else "text") + [""]

packet = {"codebook.md": open(CODEBOOK, encoding="utf-8").read().splitlines(), "hunks.md": md, "incidents.md": im}

# --- feedback (record branch) ---------------------------------------------------------------
FB_NAME = re.compile(r"^(engineer-feedback|auditor-sprint-feedback|bridgebuilder|bb-triage|adversarial-review|adversarial-audit)[^/]*\.(md|json)$")
fb_texts = {}   # record path -> text
if record_ref and feedback_files:
    if rev(record_ref) is None:
        fail(f"{fx}: record ref not found: {record_ref}")
    for d in sorted({p.rsplit("/", 1)[0] for p in feedback_files if "/" in p}):
        for p in git("ls-tree", "--name-only", f"{record_ref}:{d}", check=False).splitlines():
            if FB_NAME.match(p):
                full = f"{d}/{p}"
                t = subprocess.run(["git", "-C", REPO, "show", f"{record_ref}:{full}"], capture_output=True, text=True, errors="replace")
                if t.returncode == 0:
                    fb_texts[full] = t.stdout

# --- review_driven (D-7.6) ------------------------------------------------------------------
by_base = {}
for f in files:
    by_base.setdefault(f.rsplit("/", 1)[-1], []).append(f)
def resolve(tok):
    t = tok.strip().strip("()[]<>`'\"")
    for pre in ("head/", "base/", "pr/head/", "pr/base/", "./"):
        if t.startswith(pre):
            t = t[len(pre):]
    if t in files:
        return t
    suf = [f for f in files if f.endswith("/" + t)]
    if len(suf) == 1:
        return suf[0]
    if "/" not in t and len(by_base.get(t, [])) == 1:
        return by_base[t][0]
    return None
CITE_RX = re.compile(r"((?:[\w.+-]+/)*[\w.+-]+\.[A-Za-z0-9]{1,6})(?::|#L)(\d{1,6})(?:\s*[-–]\s*L?(\d{1,6}))?")
TICK = re.compile(r"`([^`\n]*)`")   # every span, so a short span never shifts the pairing
cites = []     # (file, lo, hi, source)
snips = []     # (snippet, text window, source)
def scan_text(text, src_of):
    for m in CITE_RX.finditer(text):
        f = resolve(m.group(1))
        if f:
            lo = int(m.group(2)); hi = int(m.group(3)) if m.group(3) else lo
            cites.append((f, min(lo, hi), max(lo, hi), src_of(m.start())))
    for m in TICK.finditer(text):
        s = m.group(1).strip()
        if not 8 <= len(s) <= 200 or CITE_RX.fullmatch(s) or re.fullmatch(r"(?:[\w.+-]+/)*[\w.+-]+\.[A-Za-z0-9]{1,6}", s):
            continue
        snips.append((s, text[max(0, m.start() - 1500): m.end() + 1500], src_of(m.start())))
def walk_json(o, path, out):
    if isinstance(o, dict):
        anchor, line, end = o.get("anchor") or o.get("file") or o.get("path"), o.get("anchor_line", o.get("line")), o.get("anchor_line_end", o.get("line_end"))
        if isinstance(anchor, str) and isinstance(line, int) and not isinstance(line, bool):
            f = resolve(anchor.split(":", 1)[0])
            if f:
                e = end if isinstance(end, int) and not isinstance(end, bool) else line
                cites.append((f, min(line, e), max(line, e), f"{path}:{o.get('id', '?')}"))
        strs = [v for v in o.values() if isinstance(v, str)]
        if strs:
            out.append(("\n".join(strs), f"{path}:{o.get('id', '?')}"))
        for v in o.values():
            walk_json(v, path, out)
    elif isinstance(o, list):
        for v in o:
            walk_json(v, path, out)
for p in sorted(fb_texts):
    text = fb_texts[p]
    if p.endswith(".json"):
        try:
            obj = json.loads(text)
        except ValueError:
            obj = None
        if obj is not None:
            blocks = []
            walk_json(obj, p, blocks)
            for t, src in blocks:
                scan_text(t, lambda _pos, src=src: src)
            continue
    starts = [0] + [m.end() for m in re.finditer(r"\n", text)]
    def src_of(pos, p=p, starts=starts):
        return f"{p}#L{bisect.bisect_right(starts, pos)}"
    scan_text(text, src_of)
for h in hunks:
    lo, hi = h["start"], (h["end"] + 1 if h["insertion"] else h["end"])
    by = sorted({src for f, a, b, src in cites if f == h["file"] and a <= hi + 3 and b >= lo - 3})
    body = "\n".join(l[1:] for l in h["lines"])
    base = h["file"].rsplit("/", 1)[-1]
    by += sorted({src for s, win, src in snips if s in body and base in win} - set(by))
    h["review_driven"], h["cited_by"] = bool(by), by

# --- leak check -----------------------------------------------------------------------------
def norm(s):
    return re.sub(r"\s+", " ", s).strip()
PREFIX = re.compile(r"^(?:[> ]\s*\d+ \| |[+\- ])")
code = set()
for root in (HEAD_DIR, os.path.join(fdir, "base")):
    for r, _d, names in os.walk(root):
        for n in names:
            try:
                for l in open(os.path.join(r, n), encoding="utf-8", errors="replace"):
                    code.add(norm(redact(l)))
            except OSError:
                pass
code |= {norm(redact(l[1:])) for l in code_lines}
sources = {}
def add_source(name, text):
    for l in text.splitlines():
        k = norm(l)
        if len(k) >= MIN_LEAK and k not in code:
            sources.setdefault(k, name)
for rel in (f"labels/{fx}.tsv", f"labels/{fx}.dropped.txt", f"labels/review/{fx}.tsv",
            f"manifests/{fx}.json", f"manifests/c131/{fx}.json", f"manifests/v1/{fx}.json"):
    p = os.path.join(CORPUS, rel)
    if os.path.isfile(p):
        add_source(rel, open(p, encoding="utf-8", errors="replace").read())
for p in sorted(fb_texts):
    add_source(f"{record_ref}:{p}", fb_texts[p])
for d in args.deny_dir:
    if not os.path.isdir(d):
        fail(f"--deny-dir not a directory: {d}", 2)
    for r, dirs, names in os.walk(d):
        dirs.sort()
        for n in sorted(names):
            p = os.path.join(r, n)
            try:
                if os.path.getsize(p) > 64 * 1024 * 1024:
                    continue
                add_source(os.path.relpath(p, os.path.dirname(os.path.abspath(d))), open(p, encoding="utf-8", errors="replace").read())
            except OSError:
                pass
leaks = []
for name in sorted(packet):
    for i, l in enumerate(packet[name], 1):
        for k in (norm(l), norm(PREFIX.sub("", l, count=1))):
            if k in sources and k not in code:
                leaks.append(f"{name}:{i}: {l[:200]}  (matches {sources[k]})"); break
if leaks:
    for x in leaks[:50]:
        print("leak: " + x, file=sys.stderr)
    fail(f"{fx}: {len(leaks)} packet line(s) match label, manifest, feedback or run-directory lines; nothing written")

# --- write ----------------------------------------------------------------------------------
out = os.path.abspath(args.out)
os.makedirs(out, exist_ok=True)
stage = tempfile.mkdtemp(dir=out, prefix=f".{fx}.")
try:
    os.makedirs(os.path.join(stage, fx))
    for name in sorted(packet):
        open(os.path.join(stage, fx, name), "w", encoding="utf-8").write("\n".join(packet[name]).rstrip("\n") + "\n")
    meta = {"fixture": fx, "context": args.context, "record_ref": record_ref,
            "feedback_files": sorted(fb_texts), "incidents": inc_src if not args.no_incidents else None,
            "incident_ids": [r["id"] for r in inc_rows],
            "hunks": {h["id"]: {"file": h["file"], "head_start": h["start"], "head_end": h["end"], "insertion": h["insertion"],
                                "review_driven": h["review_driven"], "cited_by": h["cited_by"]} for h in hunks},
            "review_driven_count": sum(1 for h in hunks if h["review_driven"]), "hunk_count": len(hunks)}
    open(os.path.join(stage, f"{fx}.hunks.meta.json"), "w", encoding="utf-8").write(json.dumps(meta, indent=2, sort_keys=True) + "\n")
    p = subprocess.run(["bash", NO_SECRETS, stage], capture_output=True, text=True)
    if p.returncode != 0:
        fail(f"{fx}: no-secrets.sh failed on the packet; nothing written: {p.stdout.strip()[:300]}")
    shutil.rmtree(os.path.join(out, fx), ignore_errors=True)
    os.replace(os.path.join(stage, fx), os.path.join(out, fx))
    os.replace(os.path.join(stage, f"{fx}.hunks.meta.json"), os.path.join(out, f"{fx}.hunks.meta.json"))
finally:
    shutil.rmtree(stage, ignore_errors=True)
print(f"{fx}: {len(hunks)} hunk(s) ({meta['review_driven_count']} review-driven), {len(inc_rows)} incident(s); "
      f"{len(sources)} leak-check source line(s) clean")
PY
