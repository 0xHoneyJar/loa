#!/usr/bin/env bash
# =============================================================================
# judge-sample.sh — the blind judge's stratified sample of grader decisions
# (cycle-132 FR-4, SDD §1.4 "Judge sampler and agreement", §5.2, SKP-007/SKP-023)
#
# Usage:
#   judge-sample.sh --rows F --results-root DIR [--results-root DIR …] --out DIR --seed N
#                   [--per-stratum 10] [--min-total 150] [--suite-root DIR …] [--repo-root DIR]
#                   [--all-cells] [--descriptions FILE]
#
# The universe holds the VALID cells only (common.py's validity filter on the row and its
# grade.json — the cells the reads use, so the Horvitz–Thompson domain is the analysis
# population); --all-cells also enumerates invalid ones (descriptive).
#
# Reads every row's run directory (<root>/<batch>/<arm>/<task>-t<n>, or its highest -r<k>
# sibling) — grading/gates-combined.md (the grader's arm-neutral citation reduction, one
# `path:line[-line]` per line) for the citation regions, and for the finding text the arm's own
# outputs (sandbox/review.md, sandbox/grimoires/loa/a2a/sprint-1/{engineer-feedback,
# auditor-sprint-feedback}.md, eval/adversarial-{review,audit}.json; a matched cell's
# sessions/s<i>/ copies of the same) — plus the task's manifest and PR fixture (task.yaml
# review_catch.{fixture,manifest} under the suite roots; default every root under
# grimoires/loa/evals/; paths relative to --repo-root, default this repository).
#
# Universe, enumerated and recorded first (one unit type per class; d<i> = the manifest's i-th
# defect, the grader's positional id):
#   credited   (region, defect) for every defect the region credits (within ±3 of a site; a
#              region near two defects' sites credits both — the grader's ±3 rule)
#   near-miss  (region, nearest defect in the same file) for a region that credits nothing and
#              whose nearest site is 4–20 lines away
#   stray      a region with no defect site within 20 lines in its file
#   far-miss   a defect with no region of the cell within 20 lines (its packet quotes the
#              cell's closest finding in the same file, when one exists)
# Strata = arm × task × class; per stratum n_s = min(N_s, per-stratum cap), the cap raised
# uniformly until Σ n_s ≥ --min-total (or every unit is drawn); inclusion probability
# π_s = n_s / N_s. Sampling and packet order are seeded (--seed).
#
# Writes OUT/packets/J0001.md … (the finding text, fenced; the cited head lines ±5; the labelled
# defect's description and anchor lines — a stray packet holds only the finding and its lines;
# never the arm, trial, batch, run id or grader decision) and OUT/key.json (outside the
# packets: the universe with every unit's provenance and grader decision, the strata with N_s,
# n_s, π_s, the sampled items, the cells with their defect counts and grader credits, the
# grader-consistency count). Prints the strata table. Deterministic; no timestamps; the key
# names run directories relative to their results root.
#
# The finding text is the first paragraph of the arm's outputs that cites the region's file at its
# start or end line. A paragraph over 1,500 characters is reduced to the bullet(s) that cite the
# region — each from its bullet, numbered-item, heading or finding-id line to the next such start —
# under the note "(the citing bullet(s) of a N-line list; k of m chars shown)"; a long paragraph
# without that structure is shown whole; nothing exceeds 6,000 characters (then cut with " …").
# Until loa-smol judge-v2 addendum 1 the text was cut at 1,500 characters, which hid the citing
# bullet in 616 of 1,283 cycle-132 pair packets (κ 0.00 there against 0.30 / 0.42 where visible).
#
# A cited path resolves to a file the way the grader credits it: exact under head/; else the
# unit's labelled defect file when it ends with "/" + cited; else the unique head/ file ending
# with "/" + cited; else pr/PR.md, PR.md, pr/head.diff → the fixture's PR.md / head.diff. A
# resolved path is printed in the "Cited lines" header ("cited as …"); key.json records each
# item's cited_path_resolution (exact|defect_suffix|unique_suffix|pr_file|unresolved, null with
# no cited region). Resolution never changes the universe, the strata or the draw.
#
# An arm id in a packet is exempt when the task's PR-native text (PR.md, head.diff, the files
# under head/ and base/) also carries it — the PR names the arms, the arm never sees its own name;
# a field line is exempt only when the whole line occurs verbatim there. Batch names, run ids and
# cell keys are never exempt. Exemptions go to key.json provenance_exempt; packets are unchanged.
#
# --descriptions FILE (defect-descriptions.py's output, {fixtures: {<fixture>: {<defect id>: {text}}}})
# gives a pair packet's "Description:" line the annotators' text for (fixture, defect id); otherwise
# the manifest's description, else the defect id. key.json records each item's description_source
# (annotators|manifest|id_fallback; null for a stray) and a counts line is printed. The description
# never changes the universe, the strata or the draw; it is provenance-scanned like the packet.
#
# Exit: 0 written; 1 a packet would carry a provenance field (nothing written), or inputs
# invalid; 2 usage.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANALYSIS_DIR="$REPO_ROOT/evals/analysis"

usage() { sed -n '4,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

ROWS="" OUT="" SEED="" PER=10 MINTOT=150 REPO="$REPO_ROOT" ALL=0 DESCS=""
ROOTS=() SUITES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rows) ROWS="${2:-}"; shift 2 ;;
    --results-root) ROOTS+=("${2:-}"); shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --seed) SEED="${2:-}"; shift 2 ;;
    --per-stratum) PER="${2:-}"; shift 2 ;;
    --min-total) MINTOT="${2:-}"; shift 2 ;;
    --suite-root) SUITES+=("${2:-}"); shift 2 ;;
    --repo-root) REPO="${2:-}"; shift 2 ;;
    --all-cells) ALL=1; shift ;;
    --descriptions) DESCS="${2:-}"; [[ -n "$DESCS" ]] || usage; shift 2 ;;
    -h|--help) usage ;;
    *) printf 'judge-sample: unknown argument %s\n' "$1" >&2; usage ;;
  esac
done
[[ -n "$ROWS" && -n "$OUT" && -n "$SEED" && ${#ROOTS[@]} -gt 0 ]] || usage
[[ "$SEED" =~ ^[0-9]+$ && "$PER" =~ ^[1-9][0-9]*$ && "$MINTOT" =~ ^[0-9]+$ ]] || usage
[[ -f "$ROWS" ]] || { printf 'judge-sample: rows file not found: %s\n' "$ROWS" >&2; exit 1; }
[[ -z "$DESCS" || -f "$DESCS" ]] || { printf 'judge-sample: descriptions file not found: %s\n' "$DESCS" >&2; exit 1; }
[[ -d "$REPO" ]] || { printf 'judge-sample: repo root not found: %s\n' "$REPO" >&2; exit 1; }
if [[ ${#SUITES[@]} -eq 0 ]]; then
  for d in "$REPO"/grimoires/loa/evals/*/; do [[ -d "$d/tasks" ]] && SUITES+=("${d%/}"); done
fi

roots_json="$(printf '%s\n' "${ROOTS[@]}" | jq -R . | jq -s -c .)"
suites_json="$(printf '%s\n' ${SUITES[@]+"${SUITES[@]}"} | jq -R 'select(length > 0)' | jq -s -c .)"

python3 -I - "$ANALYSIS_DIR" "$ROWS" "$roots_json" "$suites_json" "$REPO" "$OUT" "$SEED" "$PER" "$MINTOT" "$ALL" "$DESCS" <<'PY'
import json, os, random, re, sys

analysis_dir, rows_path, roots_json, suites_json, repo, out, seed, per, mintot, all_cells, descs_path = sys.argv[1:12]
all_cells = all_cells == "1"
sys.path.insert(0, analysis_dir)
from c132 import common  # noqa: E402

roots, suites = json.loads(roots_json), json.loads(suites_json)
seed, per, mintot = int(seed), int(per), int(mintot)
WIN, NEAR, CTX = 3, 20, 5


def die(msg, code=1):
    sys.stderr.write("judge-sample: %s\n" % msg)
    sys.exit(code)


def task_meta():
    out = {}
    fx = re.compile(r"fixture:\s*([A-Za-z0-9_./-]+)")
    mf = re.compile(r"manifest:\s*([A-Za-z0-9_./-]+)")
    for root in suites:
        tdir = os.path.join(root, "tasks")
        if not os.path.isdir(tdir):
            continue
        for t in sorted(os.listdir(tdir)):
            p = os.path.join(tdir, t, "task.yaml")
            if t in out or not os.path.isfile(p):
                continue
            with open(p, encoding="utf-8") as f:
                for line in f:
                    if line.startswith("review_catch:"):
                        a, b = fx.search(line), mf.search(line)
                        if a and b:
                            out[t] = {"fixture": a.group(1).rstrip(",}"), "manifest": b.group(1).rstrip(",}")}
                        break
    return out


def inside(base, rel):
    p = os.path.realpath(os.path.join(base, rel))
    return p if p == os.path.realpath(base) or p.startswith(os.path.realpath(base) + os.sep) else None


def path_matches(cited, defect_file):
    for pre in ("head/", "base/"):
        if cited.startswith(pre):
            cited = cited[len(pre):]
    if cited == defect_file or defect_file.endswith("/" + cited):
        return True
    return cited == defect_file.rsplit("/", 1)[-1]


def strip_side(p):
    for pre in ("head/", "base/"):
        if p.startswith(pre):
            return p[len(pre):]
    return p


LINE = re.compile(r"^(?P<p>\S+?):(?P<a>\d{1,6})(?:-(?P<b>\d{1,6}))?$")


def regions(run_dir):
    p = os.path.join(run_dir, "grading", "gates-combined.md")
    out = []
    if not os.path.isfile(p) or os.path.islink(p):
        return None
    with open(p, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.match(line.strip())
            if m:
                a = int(m.group("a")); b = int(m.group("b") or a)
                out.append((m.group("p"), min(a, b), max(a, b)))
    return sorted(set(out))


TRAILER = re.compile(r"<!--\s*LOA-VERDICT.*?-->", re.S)


def sources(run_dir):
    """the arm's own texts (paragraph lists) for the finding text"""
    texts = []
    dirs = [run_dir]
    sd = os.path.join(run_dir, "sessions")
    if os.path.isdir(sd):
        dirs += [os.path.join(sd, s) for s in sorted(os.listdir(sd))]
    for d in dirs:
        for rel in ("sandbox/review.md", "sandbox/grimoires/loa/a2a/sprint-1/engineer-feedback.md",
                    "sandbox/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md"):
            p = os.path.join(d, rel)
            if os.path.isfile(p) and not os.path.islink(p):
                with open(p, encoding="utf-8", errors="replace") as f:
                    texts.append(TRAILER.sub("", f.read()))
        for g in ("review", "audit"):
            p = os.path.join(d, "eval", "adversarial-%s.json" % g)
            if os.path.isfile(p) and not os.path.islink(p):
                try:
                    with open(p, encoding="utf-8") as f:
                        env = json.load(f)
                except ValueError:
                    continue
                for fd in env.get("findings") or []:
                    if isinstance(fd, dict):
                        bits = [str(fd.get(k)) for k in ("title", "description", "file", "anchor_line", "evidence")
                                if fd.get(k) not in (None, "")]
                        if fd.get("file") and isinstance(fd.get("anchor_line"), int):
                            bits.append("%s:%d" % (fd["file"], fd["anchor_line"]))
                        texts.append(" — ".join(bits))
    paras = []
    for t in texts:
        paras += [p.strip() for p in re.split(r"\n\s*\n", t) if p.strip()]
    return paras


CUT, CAP = 1500, 6000     # a citing paragraph over CUT chars is reduced to its citing bullet(s); nothing exceeds CAP
BULLET = re.compile(r"\s*(?:[-*+]|\d+[.)]|#{1,6}\s|\[?[A-Z]{2,}-\d+)")   # a bullet, numbered item, heading or finding id


def finding_text(paras, region):
    """the first paragraph citing the region's file at its start or end line. Over CUT characters the paragraph is
    reduced to the line block(s) that cite the region — each from its bullet, numbered-item, heading or finding-id
    line to the next such start — under a note naming the list's line count and the characters shown (loa-smol
    judge-v2 addendum 1: the cycle-132 rule p[:1500] + " …" hid the citing bullet in 616 of 1,283 pair packets). A
    long paragraph without that structure is shown whole. Never more than CAP characters (then cut with " …")."""
    path, a, b = region
    base = re.escape(strip_side(path).rsplit("/", 1)[-1])
    pat = re.compile(base + r"[`*)\]]{0,3}:(%d|%d)(?!\d)" % (a, b))
    for p in paras:
        if not pat.search(p):
            continue
        if len(p) <= CUT:
            return p
        lines = p.split("\n")
        starts = [i for i, ln in enumerate(lines) if BULLET.match(ln)] or [0]
        keep = set()
        for h in (i for i, ln in enumerate(lines) if pat.search(ln)):
            s = max([x for x in starts if x <= h], default=0)
            e = min([x for x in starts if x > h], default=len(lines))
            keep.update(range(s, e))
        out = p
        if len(keep) < len(lines):
            shown = "\n".join(lines[i] for i in sorted(keep))
            out = "(the citing bullet(s) of a %d-line list; %d of %d chars shown)\n%s" % (len(lines), len(shown), len(p), shown)
        return out if len(out) <= CAP else out[:CAP] + " …"
    return None


def gap(region, site):
    _, a, b = region
    return max(0, a - site, site - b)


WALK_CAP = 200000              # files listed per head tree for the suffix lookup
PR_FILES = {"pr/PR.md": "PR.md", "PR.md": "PR.md", "pr/head.diff": "head.diff"}
_head_files = {}


def head_files(fixture_dir):
    """relative paths of the regular files under head/ (bounded walk, symlinks skipped; cached)"""
    if fixture_dir not in _head_files:
        top, found = os.path.join(fixture_dir, "head"), []
        if os.path.isdir(top) and not os.path.islink(top):
            for d, dns, fns in os.walk(top, followlinks=False):
                dns[:] = sorted(n for n in dns if not os.path.islink(os.path.join(d, n)))
                for n in sorted(fns):
                    q = os.path.join(d, n)
                    if os.path.isfile(q) and not os.path.islink(q):
                        found.append(os.path.relpath(q, top).replace(os.sep, "/"))
                if len(found) >= WALK_CAP:
                    break
        _head_files[fixture_dir] = found[:WALK_CAP]
    return _head_files[fixture_dir]


def resolve_cited(fixture_dir, rel, defect_file):
    """(absolute path or None, display path, resolution) for a cited region path, in the grader's
    order: exact under head/; the unit's labelled defect file when it ends with "/" + cited (the
    grader's credit rule); the unique head/ file ending with "/" + cited; pr/PR.md, PR.md and
    pr/head.diff → the fixture's PR.md / head.diff. Zero or several suffix matches → unresolved."""
    cited = strip_side(rel)
    if not fixture_dir:
        return None, "head/" + cited, "unresolved"
    head = os.path.join(fixture_dir, "head")
    p = inside(head, cited)
    if p and os.path.isfile(p):
        return p, "head/" + cited, "exact"
    if defect_file and defect_file.endswith("/" + cited):
        p = inside(head, defect_file)
        if p and os.path.isfile(p):
            return p, "head/" + defect_file, "defect_suffix"
    hits = [f for f in head_files(fixture_dir) if f.endswith("/" + cited)]
    if len(hits) == 1:
        p = inside(head, hits[0])
        if p and os.path.isfile(p):
            return p, "head/" + hits[0], "unique_suffix"
    if cited in PR_FILES:
        q = os.path.join(fixture_dir, PR_FILES[cited])
        if os.path.isfile(q) and not os.path.islink(q):
            return q, PR_FILES[cited], "pr_file"
    return None, "head/" + cited, "unresolved"


def head_lines(p, a, b):
    if not p:
        return None
    with open(p, encoding="utf-8", errors="replace") as f:
        lines = f.read().split("\n")
    lo, hi = max(1, a - CTX), min(len(lines), b + CTX)
    return "\n".join("%6d  %s" % (i, lines[i - 1]) for i in range(lo, hi + 1))


def fence(text):
    n = 3
    for m in re.finditer(r"`{3,}", text or ""):
        n = max(n, len(m.group(0)) + 1)
    return "`" * n


def load_descriptions(path):
    """{fixture: {defect id: text}} from defect-descriptions.py's output ({} without --descriptions)"""
    if not path:
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except (OSError, ValueError) as e:
        die("descriptions file unreadable: %s" % e)
    fx = doc.get("fixtures") if isinstance(doc, dict) and doc.get("schema_version") == 1 else None
    if not isinstance(fx, dict):
        die("descriptions file is not schema_version 1 with a fixtures object: %s" % path)
    out = {}
    for name, ds in fx.items():
        if not isinstance(ds, dict):
            die("descriptions file: fixture %s is not an object" % name)
        for did, e in ds.items():
            t = e.get("text") if isinstance(e, dict) else None
            if isinstance(t, str) and t.strip():
                out.setdefault(name, {})[did] = " ".join(t.split())
    return out


descriptions = load_descriptions(descs_path)
meta = task_meta()
try:
    rows = common.load_rows(rows_path)
except common.InputError as e:
    die(str(e))
units, cells = [], {}
mismatch = skipped_invalid = 0
for r in sorted(rows, key=common.cell_key):
    if r.get("task_type") not in (None, "review-catch"):
        continue
    key = common.cell_key(r)
    task = r.get("task_id")
    tm = meta.get(task)
    if not tm:
        die("no task.yaml with review_catch for task %s under the suite roots" % task)
    mpath = inside(repo, tm["manifest"])
    if not mpath or not os.path.isfile(mpath):
        die("manifest not found for %s: %s" % (task, tm["manifest"]))
    fixture_rel = tm["fixture"] if tm["fixture"].startswith("evals/") else os.path.join("evals/fixtures", tm["fixture"])
    fixture_dir = inside(repo, fixture_rel)
    with open(mpath, encoding="utf-8") as f:
        man = json.load(f)
    fixture_name = str(man.get("fixture") or os.path.basename(tm["fixture"].rstrip("/")))
    defects = man.get("defects") or []
    rd = common.run_dir_for(r, roots)
    if not rd:
        continue
    if not all_cells:
        g, _gp = common.load_grade(rd)
        if not common.build_cell(r, g)["valid"]:
            skipped_invalid += 1
            continue
    regs = regions(rd)
    if regs is None:
        continue
    root_of = next(rt for rt in roots if os.path.realpath(rd).startswith(os.path.realpath(rt) + os.sep))
    paras = sources(rd)
    credited = set()
    for reg in regs:
        best, hits = None, []
        for i, d in enumerate(defects):
            if not path_matches(reg[0], d.get("file", "")):
                continue
            g = min([gap(reg, s) for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int)] or [None]) \
                if any(isinstance(s, int) for s in (d.get("anchors") or [d.get("anchor_line")])) else None
            if g is None:
                continue
            if g <= WIN:
                hits.append(i)
            if best is None or (g, i) < best:
                best = (g, i)
        base_u = {"cell": key, "arm": r.get("arm"), "task": task, "trial": r.get("trial"), "region": list(reg),
                  "_text": finding_text(paras, reg), "_fixture": fixture_dir, "_man": defects,
                  "_fxname": fixture_name}
        if hits:
            # one credited unit per crediting relation: a region within ±3 of two defects credits both
            for i in hits:
                credited.add("d%d" % (i + 1))
                units.append(dict(base_u, **{"class": "credited", "defect": "d%d" % (i + 1), "grader_credit": True}))
        elif best is not None and best[0] <= NEAR:
            units.append(dict(base_u, **{"class": "near-miss", "defect": "d%d" % (best[1] + 1), "grader_credit": False}))
        else:
            units.append(dict(base_u, **{"class": "stray", "defect": None, "grader_credit": False}))
    for i, d in enumerate(defects):
        did = "d%d" % (i + 1)
        sites = [s for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int)]
        near = [(min(gap(reg, s) for s in sites), reg) for reg in regs if path_matches(reg[0], d.get("file", "")) and sites]
        if near and min(near)[0] <= NEAR:
            continue
        closest = min(near)[1] if near else None
        units.append({"cell": key, "arm": r.get("arm"), "task": task, "trial": r.get("trial"), "class": "far-miss",
                      "region": list(closest) if closest else None, "defect": did, "grader_credit": False,
                      "_text": finding_text(paras, closest) if closest else None, "_fixture": fixture_dir, "_man": defects,
                      "_fxname": fixture_name})
    missed = r.get("defects_missed_pm3")
    if isinstance(missed, list):
        grader = {"d%d" % (i + 1) for i in range(len(defects))} - set(missed)
        if grader != credited:
            mismatch += 1
    cells[key] = {"arm": r.get("arm"), "task": task, "trial": r.get("trial"), "defects": len(defects),
                  "credited": sorted(credited, key=lambda x: int(x[1:])), "regions": len(regs),
                  "run_dir": os.path.relpath(rd, root_of)}

for i, u in enumerate(units, 1):
    u["unit"] = "U%05d" % i
strata = {}
for u in units:
    strata.setdefault("%s|%s|%s" % (u["arm"], u["task"], u["class"]), []).append(u)
cap = per
biggest = max([len(v) for v in strata.values()] or [0])
while sum(min(len(v), cap) for v in strata.values()) < mintot and cap < biggest:
    cap += 1
rng = random.Random(seed)
sampled = []
stab = {}
for s in sorted(strata):
    us = strata[s]
    n = min(len(us), cap)
    pick = rng.sample(us, n) if n < len(us) else list(us)
    for u in pick:
        u["sampled"] = True
    sampled += pick
    stab[s] = {"N": len(us), "n": n, "pi": n / float(len(us))}
for u in units:
    u.setdefault("sampled", False)
prng = random.Random("%d:packets" % seed)
sampled.sort(key=lambda u: u["unit"])
prng.shuffle(sampled)

forbidden, arm_ids = set(), set()
for r in rows:
    for k in ("arm", "batch", "run_id"):
        if r.get(k):
            forbidden.add(str(r[k]))
    if r.get("arm"):
        arm_ids.add(str(r["arm"]))
    forbidden.add(common.cell_key(r))
strict = forbidden - arm_ids    # batch names, run ids, cell keys: never PR content, never exempt
arm_ids -= strict
FIELD = re.compile(r"^\s*(arm|trial|batch|run_id|stratum|grader[_ ]decision)\s*[:=]", re.I | re.M)
NATIVE_CAP = 8 << 20            # bytes read per PR file
_native = {}


def pr_native(fixture_dir):
    """the task's PR-native text: PR.md, head.diff, every regular file under head/ and base/
    (bounded reads, symlinks skipped); an arm id quoted from it does not reveal the arm"""
    if not fixture_dir:
        return ""
    if fixture_dir not in _native:
        paths = [os.path.join(fixture_dir, n) for n in ("PR.md", "head.diff")]
        for side in ("head", "base"):
            top = os.path.join(fixture_dir, side)
            if os.path.isdir(top) and not os.path.islink(top):
                for d, dns, fns in os.walk(top, followlinks=False):
                    dns.sort()
                    paths += [os.path.join(d, n) for n in sorted(fns)]
        parts = []
        for p in paths:
            if os.path.isfile(p) and not os.path.islink(p):
                with open(p, "rb") as f:
                    parts.append(f.read(NATIVE_CAP).decode("utf-8", "replace"))
        _native[fixture_dir] = "\n".join(parts)
    return _native[fixture_dir]


packets, items, provenance_exempt = {}, {}, []
for j, u in enumerate(sampled, 1):
    jid = "J%04d" % j
    L = ["# Judge item %s\n\n" % jid]
    quoted = []    # head-tree text (the PR's own code may name arms): outside the provenance scan
    if u["class"] == "stray":
        L.append("Rate the finding: `real` (a real defect at head), `style`, `wrong`, or `not-a-finding`.\n\n")
    else:
        L.append("Does the finding describe the labelled defect? `describes`, `partially`, or `does-not-describe`.\n\n")
    L.append("## Finding\n\n")
    resolution = None    # no cited region: nothing to resolve
    dsource = None       # a stray carries no labelled defect
    if u["region"] is None:
        L.append("No finding cites this file.\n\n")
    else:
        txt = u["_text"] or "(the finding's prose could not be located; the citation only)"
        fz = fence(txt)
        L.append("%s text\n%s\n%s\n\n" % (fz, txt, fz))
        dfile = u["_man"][int(u["defect"][1:]) - 1].get("file") if u["defect"] else None
        rp, shown, resolution = resolve_cited(u["_fixture"], u["region"][0], dfile)
        hl = head_lines(rp, u["region"][1], u["region"][2])
        note = "" if resolution in ("exact", "unresolved") else "; cited as %s" % strip_side(u["region"][0])
        L.append("## Cited lines: %s:%d-%d (±%d%s)\n\n" % (shown, u["region"][1], u["region"][2], CTX, note))
        if hl is None:
            L.append("(the file is not in the PR's head tree)\n\n")
        else:
            fz = fence(hl)
            L.append("%s text\n%s\n%s\n\n" % (fz, hl, fz))
            quoted.append(hl)
    if u["class"] != "stray":
        d = u["_man"][int(u["defect"][1:]) - 1]
        sites = [s for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int)]
        desc = descriptions.get(u["_fxname"], {}).get(str(d.get("id", "")))
        dsource = "annotators"
        if not desc:
            desc, dsource = d.get("description"), "manifest"
        if not desc:
            desc = re.sub(r"^[A-Za-z]?\d+-", "", str(d.get("id", ""))).replace("-", " ")
            dsource = "id_fallback"
        L.append("## Labelled defect\n\nFile: `%s`; anchor lines: %s.\n\nDescription: %s\n" % (
            d.get("file"), ", ".join(str(s) for s in sites), desc))
        if d.get("must_match") and not str(d["must_match"]).startswith("@L"):
            fz = fence(str(d["must_match"]))
            L.append("\nHead line:\n\n%s text\n%s\n%s\n" % (fz, d["must_match"], fz))
            quoted.append(str(d["must_match"]))
    body = "".join(L)
    scan = body
    for q in quoted:
        scan = scan.replace(q, "")
    native, exempt = None, []
    for m in FIELD.finditer(scan):
        end = scan.find("\n", m.start())
        whole = scan[m.start():end if end >= 0 else len(scan)].strip()
        native = pr_native(u["_fixture"]) if native is None else native
        if not whole or whole not in native:
            die("packet %s would carry a provenance field (%s)" % (jid, m.group(0).strip()))
        exempt.append(whole)
    for tok in sorted(forbidden):
        if tok in scan:
            native = pr_native(u["_fixture"]) if native is None else native
            if tok in strict or tok not in native:
                die("packet %s would carry a provenance field (%s)" % (jid, tok))
            exempt.append(tok)
    for tok in sorted(set(exempt)):
        provenance_exempt.append({"item": jid, "token": tok, "reason": "pr_native"})
    packets[jid] = body
    items[jid] = {k: u[k] for k in ("unit", "cell", "arm", "task", "trial", "class", "region", "defect", "grader_credit")}
    items[jid]["cited_path_resolution"] = resolution
    items[jid]["description_source"] = dsource

key = {"schema_version": 1, "seed": seed, "per_stratum": per, "per_stratum_used": cap, "min_total": mintot,
       "window": WIN, "near": NEAR, "strata": stab, "items": items, "cells": cells,
       "grader_mismatch_cells": mismatch,
       "provenance_exempt": sorted(provenance_exempt, key=lambda e: (e["item"], e["token"])), "invalid_cells_skipped": skipped_invalid, "all_cells": all_cells,
       "universe": [{k: u[k] for k in ("unit", "cell", "arm", "task", "trial", "class", "region", "defect",
                                       "grader_credit", "sampled")} for u in units]}
os.makedirs(os.path.join(out, "packets"), exist_ok=True)
for jid, body in sorted(packets.items()):
    with open(os.path.join(out, "packets", jid + ".md"), "w", encoding="utf-8") as f:
        f.write(body)
with open(os.path.join(out, "key.json"), "w", encoding="utf-8") as f:
    f.write(json.dumps(key, sort_keys=True, indent=1) + "\n")
print("stratum\tN\tn\tpi")
for s in sorted(stab):
    print("%s\t%d\t%d\t%.4f" % (s, stab[s]["N"], stab[s]["n"], stab[s]["pi"]))
print("total\t%d\t%d" % (len(units), len(sampled)))
print("provenance exemptions: %d (pr_native)" % len(provenance_exempt))
RES = ("exact", "defect_suffix", "unique_suffix", "pr_file", "unresolved")
print("cited paths: " + " ".join("%s=%d" % (k, sum(1 for it in items.values() if it["cited_path_resolution"] == k))
                                 for k in RES) + " no_region=%d" % sum(1 for it in items.values() if it["cited_path_resolution"] is None))
if descs_path:
    print("descriptions: " + " ".join("%s=%d" % (k, sum(1 for it in items.values() if it["description_source"] == k))
                                      for k in ("annotators", "manifest", "id_fallback"))
          + " stray=%d" % sum(1 for it in items.values() if it["description_source"] is None))
if mismatch:
    print("grader-consistency: %d cell(s) whose ±3 credits differ from the row's defects_missed_pm3" % mismatch)
PY
