#!/usr/bin/env bash
# =============================================================================
# seed-corpus-from-record.sh — build a review-recall fixture from a shipped
# sprint's round-1 state and its record-branch feedback (cycle-129 FR-2,
# SDD D-2.2, DEC-0154)
#
# Usage:
#   seed-corpus-from-record.sh <global-sprint> <record-ref> [--out <corpus>/pr-NN]
#                              [--base <rev>] [--head <rev>] [--fix <rev>]
#                              [--feedback a.md,b.md] [--paths 'glob,!glob'] [--allow-no-labels] [--dry-run]
#   seed-corpus-from-record.sh --stamp-exposure pr-NN   # add/refresh the exposure block (cycle-132)
#   seed-corpus-from-record.sh --build-manifest pr-NN   # labels → hidden manifest (after curation)
#   seed-corpus-from-record.sh --approve pr-NN --by "<who> <YYYY-MM-DD>"
#   seed-corpus-from-record.sh --sync-labels pr-NN      # manifest anchors/approved_by → labels rows
#   seed-corpus-from-record.sh --freeze                 # regenerate SHA256SUMS
#   seed-corpus-from-record.sh --check                  # verify SHA256SUMS
#   common: [--repo <git dir>] [--corpus <evals/fixtures/review-prs>]
#
# Without --base/--head/--fix/--feedback/--paths/--out the sprint's row in
# <corpus>/record-pairs.tsv supplies them.
#
# --feedback (cycle-132 FR-1, SDD D-1.1) is a comma list; each entry is a bare
# `<name>.md` (the shorthand: grimoires/loa/a2a/sprint-<N>/<name>.md on the record
# ref), `a2a/<dir>/<name>.md` (under grimoires/loa/) or any `.md` path relative to
# the record ref's root (the cycle-131 sprints keep theirs under a2a/sprint-1 … 3/).
# An absolute path, a `..` or `.` component, a backslash, a NUL or a non-.md name
# is a usage error (exit 2); a path the record ref does not hold is reported as
# dropped. fixture.yaml lists the paths read.
#
# --paths (cycle-132) scopes the fixture to part of base..head when two sprints
# share a base (sprints 261/262): a comma list of fnmatch globs (`*` crosses `/`);
# an entry starting with `!` excludes. A changed path is in scope when it matches
# an include (or there is none) and no exclude. The scope is recorded in
# fixture.yaml as `scope_paths`; a scope that leaves no file is refused (exit 1).
#
# --allow-no-labels (cycle-132) builds the fixture even when no finding became a
# label: the review-derived set is then empty (a manifest with `defects: []`, the
# fix regions kept) because the blind annotation (FR-2), not the review, supplies
# the primary key. Without it such a sprint is a gap row in corpus.tsv, as before.
#
# Provenance (cycle-132 FR-1, SDD §3.2): every seeded fixture.yaml ends with
#   exposure:
#     fable_5_1: post-cutoff|pre-cutoff   # head commit date (UTC) after the knowledge-cutoff month
#     opus_5_5: unverified                # the catalog date is an upper bound, not a cutoff
#     retrieval: public-repository
#   contamination_note: "fix commits on main since <head date>; sandbox has network; egress scanned (grader class 9)"
# computed from the MODEL_AVAILABILITY table below and the head commit's committer
# date. --stamp-exposure pr-NN writes the same block into an existing fixture.yaml
# (pr-11 … pr-18): it removes any earlier `exposure:` block and `contamination_note:`
# line, appends the fresh block, keeps every other line byte for byte and is
# idempotent; it refuses (exit 1, file untouched) a fixture without fixture.yaml,
# without head_commit, or whose head commit --repo does not hold. It does not
# refreeze: run --freeze.
#
# Writes (seed):
#   <corpus>/pr-NN/{fixture.yaml, head.diff, PR.md, REVIEW-INSTRUCTIONS.md,
#                   AUDIT-INSTRUCTIONS.md, base/…, head/…}     (copied into the sandbox)
#   <corpus>/labels/pr-NN.tsv          HIDDEN (never copied into a sandbox): the labels,
#                                      first line `# approved-by: pending`
#   <corpus>/labels/pr-NN.dropped.txt  HIDDEN: every finding that did not become a label, and why
#   <corpus>/manifests/pr-NN.json      HIDDEN: the graded manifest (`approved: false` until --approve)
#   <corpus>/corpus.tsv                one `record` row per fixture (or a `#` gap comment)
#   evals/tasks/{review,audit}-recall/{review,audit}-pr-NN.yaml
#   <corpus>/SHA256SUMS                refreshed
#
# Scope: the fixture is the change base..head without the generated or state
# files (grimoires/, CHANGELOG.md, .claude/checksums.json, REPO-MAP.md, lock
# files, .beads/, .run/, evals/results/) and without binaries.
#
# Findings are read from `- **SEV** …` bullets, `### [SEV-n] …` and (cycle-132)
# `### SEV-n — …` headings, `**SEV-n — title.** …` paragraphs and a Bridgebuilder
# `Fixed` table; sections named previous feedback / refuted / praise / closed are skipped.
#
# Label rule: a feedback finding becomes a label only when the fix commit
# touches the file it cites (`git diff --name-only head..fix`) and that file
# is part of the fixture; label_source is review (engineer-feedback*,
# reviewer*), audit (auditor-sprint-feedback*) or bridgebuilder
# (bridgebuilder*, the "Fixed" table only). The anchor is a head-side line
# the fix changed near the cited line or inside the cited symbol; a finding
# that cites only a file is anchored on that file's fix hunks when there are
# at most four, else dropped. `fix` rows cover every hunk fix_commit changed
# in a fixture file (source fix/<sha>:<start>-<end>); the grader uses them
# only for refuted share.
#
# Label grammar (labels/pr-NN.tsv): the first line `# approved-by: <who>` (the
# approval record; `pending` until --approve), `#` comments, the column header,
# then one row per anchor. A defect's first row is its primary row (anchor_line,
# must_match, severity, category, label_source and source in the manifest); every
# further row of the same defect_id and file adds an anchor. must_match is either
# text that occurs on exactly one line of head/<file> (preferred: it survives
# renumbering) or `@L<n>`, head line n (1-based, 1 <= n <= the file's line count),
# for a line whose text is not unique (bd-y4pqj); `file` must be a relative path
# inside pr-NN/head/ (no absolute path, `..`, backslash or NUL; symlinks may not
# lead out), else the row is refused; `@L0`, a line past the end and a
# non-integer after `@L` are refused with the row named. Only a one-word `@L` value
# (`@L` followed by letters, digits or `-`) is that grammar; longer text that starts
# with `@L` (`@Lazy foo`) is ordinary text.
#
# Labels v2 (cycle-132 D-2.3): the header may instead be the v2 header, the seven columns plus
# `annotators agreement adjudication review_driven`; every row then has eleven columns. label_source
# also takes the annotated values fix-commit, incident and fix-commit+incident, which need the v2
# header and name their annotators (`A,B`), agreement (agreed|adjudicated) and review_driven
# (true|false); an adjudicated row carries the reason in adjudication; other rows may hold `-`. When
# any row is annotated, --build-manifest writes `label_set: "v2"` after `fixture`, adds
# annotators (list), agreement, adjudication (`-` → null) and review_driven (bool) to every defect,
# and records `record.incidents_meta: {main_sha}` from <corpus>/incidents/pr-NN.meta.json when that
# file exists; otherwise the manifest is today's, byte for byte. --sync-labels copies every column of
# the defect's primary row. The frozen cycle-131 set lives in labels/review/pr-NN.tsv and
# manifests/c131/pr-NN.json (moved, byte-identical; rebuild it on a scratch corpus where the review
# file is labels/pr-NN.tsv); manifests/v1/ is unchanged. Schema: evals/harness/schemas/review-manifest.schema.json.
#
# --sync-labels pr-NN (bd-y4pqj) brings the labels to a curated manifest: for every
# anchor of manifests/pr-NN.json (`anchors`, else `anchor_line`) that no row of its
# defect resolves to, it inserts a row after that defect's last row, copying the
# primary row's columns, with must_match the line's stripped text when that text is
# on exactly one line (else `@L<n>`); it rewrites the first line to the manifest's
# approved_by (one line: no control, C1 or U+2028/U+2029 characters) and keeps every
# other line byte for byte; the file is replaced atomically (temp file + rename).
# It prints the rows it added, adds nothing on a second run and never writes the manifest. On every run, a no-op
# included, it rebuilds the manifest in memory from the new labels before writing and
# refuses (exit 1, labels file untouched, the differing fields named) when the rebuild
# fails or is not byte-identical to the manifest. It does not refreeze: run --freeze.
#
# Generated artefacts never become fix regions (cycle-130 bd-8o5rx, PRD AC-10.1):
# a path with a `dist/` component, a name ending `.map`, `.d.ts` or `.checksum`,
# or named `checksums.json`, `REPO-MAP.md` or `.build-manifest.json` is a
# mechanical slice of the fix commit, so a finding there must not lower the
# refuted share. Seeding writes no `fix` row for such a path and --build-manifest
# skips any `fix` row naming one (labels written before the rule keep theirs);
# each excluded path is printed once on stderr as
# `excluded generated path: <path>`. Defect labels are never filtered. Titles are control-stripped, capped at 160 chars,
# and a title matching a secret pattern drops its finding; every written
# file passes evals/graders/no-secrets.sh or the seed fails.
#
# Exit: 0 ok, 1 refused / spec error / secret found / check failed, 2 usage
# Tested by evals/tests/seed-corpus.bats and (the lib/corpus-seed.sh extraction) evals/tests/corpus-seed-lib.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# the shared seeding library (fixture layout, labels grammar, exposure, SHA256SUMS);
# eval.yml trust boundary: a literal in-tree path, no variable on the source line
pushd "$SCRIPT_DIR" >/dev/null
source ./lib/corpus-seed.sh
popd >/dev/null

IFS= read -r -d '' SEED_RECORD_PY <<'PY' || true
import argparse, csv, fnmatch, hashlib, io, json, os, re, shutil, subprocess, sys, tempfile

HARNESS_ROOT = sys.argv[1]
argv = sys.argv[2:]

ap = argparse.ArgumentParser(prog="seed-corpus-from-record.sh", add_help=True)
ap.add_argument("sprint", nargs="?")
ap.add_argument("record_ref", nargs="?")
ap.add_argument("--out"); ap.add_argument("--base"); ap.add_argument("--head"); ap.add_argument("--fix")
ap.add_argument("--feedback"); ap.add_argument("--dry-run", action="store_true")
ap.add_argument("--build-manifest", metavar="FIXTURE"); ap.add_argument("--approve", metavar="FIXTURE")
ap.add_argument("--sync-labels", metavar="FIXTURE")
ap.add_argument("--stamp-exposure", metavar="FIXTURE"); ap.add_argument("--paths")
ap.add_argument("--allow-no-labels", action="store_true")
ap.add_argument("--by"); ap.add_argument("--freeze", action="store_true"); ap.add_argument("--check", action="store_true")
ap.add_argument("--repo", default=HARNESS_ROOT)
ap.add_argument("--corpus", default=os.path.join(HARNESS_ROOT, "evals", "fixtures", "review-prs"))
ap.add_argument("--tasks-dir", default=os.path.join(HARNESS_ROOT, "evals", "tasks"))
try:
    args = ap.parse_args(argv)
except SystemExit as e:
    sys.exit(2 if e.code else 0)

REPO, CORPUS = os.path.abspath(args.repo), os.path.abspath(args.corpus)
NO_SECRETS = os.path.join(HARNESS_ROOT, "evals", "graders", "no-secrets.sh")
LABELS_DIR = os.path.join(CORPUS, "labels")
MANIFESTS_DIR = os.path.join(CORPUS, "manifests")
# ------------------------------------------------------------ simple modes
if args.check:
    check(); sys.exit(0)
if args.freeze:
    print(f"froze {freeze()} files in SHA256SUMS"); sys.exit(0)
if args.build_manifest:
    if not FX_RX.match(args.build_manifest):
        fail("fixture id must be pr-NN", 2)
    m = build_manifest(args.build_manifest)
    n = freeze()
    print(f"{args.build_manifest}: {len(m['defects'])} label(s), {len(m['fix_regions'])} fix region(s); approved={m['approved']}; SHA256SUMS {n} files")
    sys.exit(0)
if args.stamp_exposure:
    if not FX_RX.match(args.stamp_exposure):
        fail("fixture id must be pr-NN", 2)
    stamp_exposure(args.stamp_exposure)
    sys.exit(0)
if args.sync_labels:
    if not FX_RX.match(args.sync_labels):
        fail("fixture id must be pr-NN", 2)
    sync_labels(args.sync_labels)
    sys.exit(0)
if args.approve:
    fx = args.approve
    if not FX_RX.match(fx) or not args.by or not re.match(r"^[A-Za-z0-9 ._@-]{3,80}$", args.by):
        fail("--approve pr-NN needs --by '<who> <YYYY-MM-DD>' (letters, digits, space . _ @ -)", 2)
    path = os.path.join(LABELS_DIR, f"{fx}.tsv")
    _, _, text = read_labels(fx)
    text[0] = f"# approved-by: {args.by}"
    open(path, "w", encoding="utf-8").write("\n".join(text) + "\n")
    m = build_manifest(fx)
    freeze()
    print(f"{fx}: approved by {args.by}; {len(m['defects'])} label(s)")
    sys.exit(0)

# ------------------------------------------------------------------- seed
if not args.sprint or not re.match(r"^[0-9]{1,5}$", args.sprint or ""):
    fail("usage: seed-corpus-from-record.sh <global-sprint> <record-ref> [...] (see --help)", 2)
if not args.record_ref or not re.match(r"^[A-Za-z0-9._/-]+$", args.record_ref):
    fail("a record ref is required (e.g. origin/record/cycle-128-a2a)", 2)
sprint = args.sprint
pair = {}
pairs_path = os.path.join(CORPUS, "record-pairs.tsv")
if os.path.isfile(pairs_path):
    lines = [l for l in open(pairs_path, encoding="utf-8").read().splitlines() if l and not l.startswith("#")]
    for r in csv.DictReader(io.StringIO("\n".join(lines)), delimiter="\t", quoting=csv.QUOTE_NONE):
        if r["sprint"] == sprint:
            pair = r
base_r = args.base or pair.get("base")
head_r = args.head or pair.get("head")
fix_r = args.fix or pair.get("fix")
feedback = (args.feedback or pair.get("feedback") or "").split(",")
feedback = [f for f in feedback if f]
fx = os.path.basename(args.out.rstrip("/")) if args.out else pair.get("fixture")
if not (base_r and head_r and fix_r and feedback and fx):
    fail(f"sprint {sprint}: no record-pairs.tsv row; pass --base --head --fix --feedback --out", 2)
if not FX_RX.match(fx):
    fail(f"fixture id must be pr-NN, got {fx}", 2)
if args.out and os.path.abspath(os.path.dirname(args.out.rstrip("/"))) != CORPUS:
    fail(f"--out must be a directory directly under {CORPUS}", 2)
fdir = os.path.join(CORPUS, fx)
fy = os.path.join(fdir, "fixture.yaml")
if os.path.isfile(fy) and "\nsprint:" not in "\n" + open(fy, encoding="utf-8").read():
    fail(f"{fx} exists and is not a record fixture; refusing to overwrite it")
def feedback_path(f):
    """cycle-132 D-1.1: a bare name is the a2a/sprint-<N>/ shorthand; a2a/… sits under grimoires/loa/;
    anything else is a path from the record ref's root. Unsafe or non-.md entries are usage errors."""
    parts = f.split("/")
    if (not f.endswith(".md") or f.startswith("/") or "\\" in f or "\x00" in f
            or any(x in ("", ".", "..") for x in parts) or parts[-1].startswith(".")):
        fail(f"feedback must be a .md name or a relative .md path without . or .. components: {f!r}", 2)
    if len(parts) == 1:
        return f"grimoires/loa/a2a/sprint-{sprint}/{f}"
    if parts[0] == "a2a":
        return "grimoires/loa/" + f
    return f
feedback = [(f.rsplit("/", 1)[-1], feedback_path(f)) for f in feedback]
scope_raw = args.paths if args.paths is not None else (pair.get("paths") or "-")
scope_raw = "" if scope_raw.strip() == "-" else scope_raw.strip()
if "\n" in scope_raw or '"' in scope_raw or "\\" in scope_raw:
    fail("--paths: a comma list of globs (no quote, backslash or newline)", 2)
scope_inc = [g for g in scope_raw.split(",") if g and not g.startswith("!")]
scope_exc = [g[1:] for g in scope_raw.split(",") if g.startswith("!") and len(g) > 1]
def in_scope(p):
    return ((not scope_inc or any(fnmatch.fnmatchcase(p, g) for g in scope_inc))
            and not any(fnmatch.fnmatchcase(p, g) for g in scope_exc))
base, head, fixc = rev(base_r), rev(head_r), rev(fix_r)
record_ref = args.record_ref
if subprocess.run(["git", "-C", REPO, "rev-parse", "--verify", "--quiet", record_ref], capture_output=True).returncode != 0:
    fail(f"record ref not found: {record_ref} (git fetch origin 'refs/heads/record/*:refs/remotes/origin/record/*')")
record_name = record_ref.split("origin/", 1)[-1]

# --- scope -------------------------------------------------------------------
# audit r1 DISS-C-003 (defensive): a root CLAUDE.md copy inside a fixture would be an
# instruction file Claude Code may load for the agent under test; the sandbox's own
# CLAUDE.md points at the pinned prompt tree and is the only one allowed.
EXCL = re.compile(r"^(grimoires/|\.beads/|\.run/|evals/results/|CLAUDE\.md$|CHANGELOG\.md$|\.claude/checksums\.json$|(.*/)?REPO-MAP\.md$|.*\.lock$|(.*/)?package-lock\.json$)")
binary = set()
for l in git("diff", "--numstat", "-M", base, head).splitlines():
    a, d, p = l.split("\t", 2)
    if a == "-" and d == "-":
        binary.add(p.split(" => ")[-1].strip("{}"))
changes = []  # (status, old, new)
for l in git("diff", "--name-status", "-M", base, head).splitlines():
    parts = l.split("\t")
    st = parts[0][0]
    if st in "RC":
        old, new = parts[1], parts[2]
    else:
        old = new = parts[1]
    if EXCL.match(new) or EXCL.match(old) or new in binary or old in binary:
        continue
    if not (in_scope(new) or in_scope(old)):
        continue
    for p in (old, new):
        if p.startswith("/") or ".." in p.split("/"):
            fail(f"unsafe path in the change: {p}")
    changes.append((st, old, new))
if not changes:
    fail(f"sprint {sprint}: no in-scope file changed between {base[:8]} and {head[:8]}"
         + (f" (scope {scope_raw})" if scope_raw else ""))
head_files = sorted({n for st, o, n in changes if st != "D"})
paths = sorted({p for st, o, n in changes for p in (o, n)})
diff_text = redact(git("diff", "-M", "--no-color", "--no-ext-diff", base, head, "--", *paths))
fix_touched = set(git("diff", "--name-only", head, fixc).splitlines())
head_text = {}
for p in head_files:
    b = show(head, p)
    head_text[p] = (redact(b, count=False) or b"").decode("utf-8", "replace").splitlines()

# --- fix hunks (head-side line ranges) ------------------------------------------
def fix_hunks(path):
    out = []
    for l in git("diff", "-U0", "--no-color", head, fixc, "--", path).splitlines():
        m = re.match(r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@", l)
        if m:
            a = int(m.group(1)); n = int(m.group(2)) if m.group(2) is not None else 1
            s, e = (max(a, 1), max(a, 1)) if n == 0 else (a, a + n - 1)
            if out and s - out[-1][1] <= 3:
                out[-1] = (out[-1][0], max(out[-1][1], e))
            else:
                out.append((s, e))
    return out
hunks = {p: fix_hunks(p) for p in head_files if p in fix_touched}

def pr_changed(path, line, slack=10):
    """Is head line `line` within `slack` lines of something base..head changed?"""
    st = next((s for s, o, n in changes if n == path), "M")
    if st in "AC":
        return True
    old = next((o for s, o, n in changes if n == path), path)
    for l in git("diff", "-U0", "--no-color", base, head, "--", old, path).splitlines():
        m = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", l)
        if m:
            a = int(m.group(1)); n = int(m.group(2)) if m.group(2) is not None else 1
            if a - slack <= line <= a + max(n, 1) - 1 + slack:
                return True
    return False

TRIVIAL = re.compile(r"^[\s{}()\[\];,:]*(fi|done|esac|else|then|do|return( 0| 1)?|pass|break|continue|end)?[\s{}()\[\];,:]*$")
def anchor_text(lines, lo, hi):
    """First line in [lo, hi] (widened by 3) whose stripped text is unique and non-trivial."""
    cands = list(range(lo, hi + 1)) + [x for d in range(1, 4) for x in (lo - d, hi + d)]
    for i in cands:
        if 1 <= i <= len(lines):
            t = lines[i - 1].strip()
            if "\t" in t:
                t = max(t.split("\t"), key=len).strip()
            if len(t) < 10 or TRIVIAL.match(t) or has_secret(t):
                continue
            if sum(1 for l in lines if t in l) == 1:
                return i, t
    return None, None

DEF_RX = lambda s: re.compile(
    r"^\s*(?:function\s+)?" + re.escape(s) + r"\s*\(\s*\)|^\s*(?:async\s+)?def\s+" + re.escape(s) + r"\b"
    r"|^\s*class\s+" + re.escape(s) + r"\b|\bfunction\s+" + re.escape(s) + r"\b"
    r"|^\s*(?:export\s+)?(?:const|let|var)\s+" + re.escape(s) + r"\s*=|^\s*(?:async\s+)?" + re.escape(s) + r"\s*\([^)]*\)\s*\{")
ANY_DEF = re.compile(r"^(?:function\s+)?[A-Za-z_][\w:.-]*\s*\(\s*\)\s*\{?\s*$|^(?:async\s+)?def\s|^class\s|^\s{0,4}(?:async\s+)?def\s")

def symbol_extent(lines, sym):
    rx = DEF_RX(sym)
    for i, l in enumerate(lines, 1):
        if rx.search(l):
            j = i + 1
            while j <= len(lines) and not ANY_DEF.match(lines[j - 1]):
                j += 1
            return i, j - 1
    return None

# --- findings ---------------------------------------------------------------------
SEV = {"CRITICAL": "critical", "HIGH": "high", "MEDIUM": "medium", "MED": "medium", "LOW": "low"}
RX_A = re.compile(r"^\s*(?:[-*]|\d+\.)\s+\*\*(CRITICAL|HIGH|MEDIUM|LOW)\*\*\s*(?:\(([^)]*)\))?\s*(.*)$")
RX_B = re.compile(r"^#{3,4}\s+\[(CRITICAL|HIGH|MEDIUM|MED|LOW)(?:-\d+)?\]\s*(.*)$")
# cycle-132: the cycle-129/130 feedback writes findings as `### HIGH-1 — title` / `### MEDIUM-A1 (…) — title`
# headings (RX_C) and as `**LOW-2 — title.** body` paragraphs (RX_D); both carry their locus in the body
SEV_ID = r"(CRITICAL|HIGH|MEDIUM|MED|LOW)-[A-Z]?\d+\b\s*(?:\([^)]*\))?\s*[—–:-]\s*"
RX_C = re.compile(r"^#{3,4}\s+" + SEV_ID + r"(.*)$")
RX_D = re.compile(r"^\*\*" + SEV_ID + r"(.*?)\*\*\s*(.*)$")
RX_H = re.compile(r"^#{1,4}\s")
RX_BULLET = re.compile(r"^\s*(?:[-*]|\d+\.)\s+")
SKIP_SECTION = re.compile(r"previous feedback|refuted|praise|status of prior|closed", re.I)
LATER_ROUND = re.compile(r"^#{2,4}\s+(?:\d+\.\s+)?.*\brun, on the round-", re.I)
PRE_EXISTING = re.compile(r"\bpre-?existing\b|not this sprint'?s", re.I)
TICK = re.compile(r"`([^`\n]{2,200})`")
PATHLIKE = re.compile(r"^(?:head/|base/)?[\w./+-]*[\w-]\.[A-Za-z0-9]{1,6}(?:$|[:\s])")
BARE = re.compile(r"(?<![\w/.`-])((?:\.claude|\.github|tools|tests|evals|lib|src)/[\w./+-]+\.[A-Za-z0-9]{1,6})(?::(\d+(?:-\d+)?(?:,\s*\d+)*|[A-Za-z_][\w.]*))?")

def source_kind(name):
    if name.startswith("auditor"):
        return "audit"
    if name.startswith("bridgebuilder"):
        return "bridgebuilder"
    return "review"

def parse_findings(name, text):
    lines = text.splitlines()
    out, section = [], ""
    i = 0
    in_fixed_table = False
    while i < len(lines):
        l = lines[i]
        if LATER_ROUND.match(l):
            break   # a round-1 file that appends later rounds: those read a tree after head
        if RX_H.match(l) and not RX_B.match(l) and not RX_C.match(l):
            section = l
            in_fixed_table = bool(re.match(r"^#{2,4}\s+Fixed\b", l))
            i += 1; continue
        if SKIP_SECTION.search(section):
            i += 1; continue
        m_a, m_b = RX_A.match(l), RX_B.match(l) or RX_C.match(l)
        m_d = None if (m_a or m_b) else RX_D.match(l)
        if m_d:
            sev, rest = SEV[m_d.group(1)], m_d.group(2).rstrip(" .") + (". " + m_d.group(3) if m_d.group(3) else "")
        if m_a or m_b or m_d:
            if not m_d:
                sev = SEV[(m_a or m_b).group(1)]
                rest = m_a.group(3) if m_a else m_b.group(m_b.lastindex)
            body = []
            j = i + 1
            while j < len(lines):
                n = lines[j]
                if RX_A.match(n) or RX_B.match(n) or RX_C.match(n) or RX_D.match(n) or RX_H.match(n) or (m_a and RX_BULLET.match(n)):
                    break
                body.append(n); j += 1
            title = re.sub(r"^(?:`[^`]*`[\s,]*(?:and\s+|\([^)]*\)\s*)?)+", "", rest).lstrip("—–-: ")
            title = re.split(r"(?<=[.;])\s", title, maxsplit=1)[0] if title else rest
            # a bullet finding names its code locus first (`path:ref` — …); one
            # that opens with prose (`process — …`) is an observation, not a defect
            locus = (not m_a) or rest.lstrip().startswith("`")
            out.append({"line": i + 1, "severity": sev, "title": clean(title or rest), "locus": locus,
                        "text": rest + "\n" + "\n".join(body)})
            i = j; continue
        if in_fixed_table and l.startswith("|") and not re.match(r"^\|\s*(Finding|-{3})", l):
            cells = [c.strip() for c in l.strip().strip("|").split("|")]
            if len(cells) >= 3 and not cells[2].lower().startswith("refuted"):
                ms = re.search(r"\b(CRITICAL|HIGH|MEDIUM|LOW)\b", cells[1])
                if ms:
                    out.append({"line": i + 1, "severity": SEV[ms.group(1)], "title": clean(cells[0] + ": " + cells[2]),
                                "locus": True, "text": cells[2]})
        i += 1
    return out

def resolve_path(tok):
    t = tok.strip().strip("()[]")
    if t.startswith("head/") or t.startswith("base/"):
        t = t[5:]
    ref = None
    m = re.match(r"^([^\s:]+?\.[A-Za-z0-9]{1,6})(?::(.+))?$", t)
    if not m:
        m2 = re.match(r"^(\S+?\.[A-Za-z0-9]{1,6})\s+(\S+)$", t)   # `file.sh func_name`
        if not m2:
            return None, None
        p, ref = m2.group(1), m2.group(2)
    else:
        p, ref = m.group(1), m.group(2)
    if p in head_text:
        return p, ref
    cand = [h for h in head_files if h.endswith("/" + p) or h == p]
    if len(cand) == 1:
        return cand[0], ref
    if "/" not in p:
        cand = [h for h in head_files if h.rsplit("/", 1)[-1] == p]
        if len(cand) == 1:
            return cand[0], ref
    return None, None

def hs_overlap(picked, hs):
    return any(not (b < lo or a > hi) for a, b in picked for lo, hi in hs)

def parse_ref(ref):
    if not ref:
        return None, None
    m = re.match(r"^(\d{1,6})(?:[-–](\d{1,6}))?", ref)
    if m:
        a = int(m.group(1)); b = int(m.group(2)) if m.group(2) else a
        return (min(a, b), max(a, b)), None
    m = re.match(r"^([A-Za-z_][\w]*)", ref)
    return (None, m.group(1)) if m else (None, None)

CATS = [("security", r"inject|secret|credential|token|exec|untrusted|fence|sanitis|saniti|permission|symlink|traversal|auth|escape|exfil|privilege|O_NOFOLLOW|world-|group-writable"),
        ("concurrency", r"race|lock|concurren|flock|parallel"),
        ("error-handling", r"fail[- ]open|fail[- ]closed|error|exit|crash|unguarded|swallow|missing|absent|empty"),
        ("test", r"\btest|bats|assert|fixture"),
        ("docs", r"CHANGELOG|SDD|docs?\b|README|comment|header")]
def category(title):
    for c, rx in CATS:
        if re.search(rx, title, re.I):
            return c
    return "logic"

def slug(title):
    s = re.sub(r"[^a-z0-9]+", "-", re.sub(r"`[^`]*`", "", title).lower()).strip("-")
    return (s[:40].rstrip("-") or "finding")

labels, dropped, fb_paths = [], [], []
for name, path in feedback:
    blob = show(record_ref, path)
    if blob is None:
        dropped.append(f"{name if path == f'grimoires/loa/a2a/sprint-{sprint}/{name}' else path}: not on {record_ref}")
        continue
    fb_paths.append(path)
    for f in parse_findings(name, blob.decode("utf-8", "replace")):
        src = f"{record_name}:{path}#L{f['line']}"
        if has_secret(f["text"]) or has_secret(f["title"]):
            dropped.append(f"{src} [{f['severity']}] secret pattern in the finding text: dropped without its title")
            continue
        if not f["locus"]:
            dropped.append(f"{src} [{f['severity']}] no code locus (the finding opens with prose, not `path:ref`): {f['title']}")
            continue
        if PRE_EXISTING.search(f["text"]):
            dropped.append(f"{src} [{f['severity']}] the finding calls itself pre-existing (not this change): {f['title']}")
            continue
        cites, snippets = [], []   # (text position, token)
        for m in TICK.finditer(f["text"]):
            for piece in re.split(r",\s+(?=[\w./-]+\.[A-Za-z0-9]{1,6})", m.group(1)):
                (cites if PATHLIKE.match(piece.strip()) else snippets).append((m.start(), piece))
        for m in BARE.finditer(f["text"]):
            cites.append((m.start(), m.group(1) + (":" + m.group(2) if m.group(2) else "")))
        cites = [c for _pos, c in sorted(cites)]
        # the file a finding cites is its FIRST path cite; a later mention of
        # another file (an example, a doc pointer) never becomes the locus
        if not cites:
            dropped.append(f"{src} [{f['severity']}] cites no file: {f['title']}")
            continue
        p, ref = resolve_path(cites[0])
        if p is None:
            dropped.append(f"{src} [{f['severity']}] first cited file is not part of this fixture "
                           f"({clean(cites[0], 80)}): {f['title']}")
            continue
        if p not in fix_touched:
            dropped.append(f"{src} [{f['severity']}] fix commit does not touch {p}: {f['title']}")
            continue
        lines = head_text[p]
        hs = hunks.get(p, [])
        rng, sym = parse_ref(ref)
        # a later `path:N` / `path:sym` for the same file refines a bare first cite
        if rng is None and sym is None:
            for c in cites[1:]:
                p2, ref2 = resolve_path(c)
                if p2 == p and ref2:
                    rng, sym = parse_ref(ref2)
                    if rng or sym:
                        break
        # still no locator: the first backticked identifier in the finding that
        # the cited file defines (`red-test-check.sh` `run_bounded`, `lookup()`)
        if rng is None and sym is None:
            for m in TICK.finditer(f["text"]):
                ident = m.group(1).strip()
                ident = ident[:-2] if ident.endswith("()") else ident
                if re.match(r"^[A-Za-z_][\w]{2,}$", ident) and symbol_extent(lines, ident):
                    sym = ident
                    break
        ext = symbol_extent(lines, sym) if sym else None
        # a code snippet the finding quotes (`result=$(_fold_companion …)`) that
        # sits on exactly one head line — inside the cited symbol or near the
        # cited line when several lines carry it — is the strongest locus
        snip_anchors = []
        for _pos, s in snippets:
            s = re.split(r"\s*(?:…|\.\.\.)", s.strip(), maxsplit=1)[0].strip()
            if len(s) < 8 or "\n" in s:
                continue
            hits = [i for i, l in enumerate(lines, 1) if s in l]
            if not p.endswith(".md"):
                # in code, a hit on a comment-only line is documentation, not the site
                hits = [i for i in hits if not re.match(r"^\s*(#|//|/?\*|--)", lines[i - 1])]
            if len(hits) > 1 and ext:
                hits = [i for i in hits if ext[0] <= i <= ext[1]]
            if len(hits) > 1 and rng:
                hits = [i for i in hits if rng[0] - 40 <= i <= rng[1] + 40]
            if len(hits) == 1 and sum(1 for l in lines if s in l) == 1 and not has_secret(s) and "\t" not in s:
                if hits[0] not in [a for a, _ in snip_anchors]:
                    snip_anchors.append((hits[0], s))
            if len(snip_anchors) == 2:
                break
        picked, how = [], ""
        if rng:
            near = [h for h in hs if not (h[1] < rng[0] - 15 or h[0] > rng[1] + 15)]
            if not near and hs:
                best = min(hs, key=lambda h: min(abs(h[0] - rng[0]), abs(h[1] - rng[0])))
                if min(abs(best[0] - rng[0]), abs(best[1] - rng[0])) <= 60:
                    near = [best]
            picked, how = near[:3], f"fix hunk near cited line {rng[0]}"
            if not picked and rng[0] <= len(lines):
                picked, how = [(rng[0], rng[1])], f"cited line {rng[0]} (no fix hunk within 60 lines)"
        elif ext:
            inside = [h for h in hs if ext[0] <= h[0] <= ext[1]]
            picked, how = (inside[:2], f"fix hunk inside {sym}()") if inside else ([(ext[0], ext[0])], f"definition of {sym}")
        if snip_anchors:
            how = "quoted snippet" + (f" + {how}" if how else "")
        elif picked and not hs_overlap(picked, hs) and not pr_changed(p, picked[0][0]):
            dropped.append(f"{src} [{f['severity']}] pre-existing site: neither the change nor the fix touched "
                           f"{p}:{picked[0][0]}: {f['title']}")
            continue
        if not picked and not snip_anchors:
            if 0 < len(hs) <= 4:
                picked, how = hs, "the file's fix hunks (file-level finding)"
            else:
                dropped.append(f"{src} [{f['severity']}] no locator ({len(hs)} fix hunks in {p}): {f['title']}")
                continue
        anchors = list(snip_anchors)
        for lo, hi in picked[: (2 if snip_anchors else 3)]:
            at, t = anchor_text(lines, lo, hi)
            if at and t not in [x[1] for x in anchors] and at not in [x[0] for x in anchors]:
                anchors.append((at, t))
        # a short cited function: its definition line is a site too
        if ext and ext[1] - ext[0] <= 40 and ext[0] not in [a for a, _ in anchors]:
            at, t = anchor_text(lines, ext[0], ext[0])
            if at == ext[0]:
                anchors.append((at, t))
        anchors = anchors[:4]
        if not anchors:
            dropped.append(f"{src} [{f['severity']}] no unique anchor line in head/{p}: {f['title']}")
            continue
        labels.append({"severity": f["severity"], "category": category(f["title"]), "file": p, "anchors": anchors,
                       "label_source": source_kind(name), "source": src, "title": f["title"], "how": how})

# dedupe: one label per (file, first anchor); the first source wins, sources noted
seen, uniq = {}, []
for lb in labels:
    k = (lb["file"], lb["anchors"][0][0])
    if k in seen:
        dropped.append(f"{lb['source']} [{lb['severity']}] duplicate of {seen[k]['id']} (same anchor): {lb['title']}")
        continue
    lb["id"] = f"L{len(uniq) + 1:02d}-{slug(lb['title'])}"
    seen[k] = lb; uniq.append(lb)
labels = uniq

# hand curation (labels/curation.tsv): re-applied on every seed
cur_path = os.path.join(LABELS_DIR, "curation.tsv")
if os.path.isfile(cur_path):
    cur_lines = [l for l in open(cur_path, encoding="utf-8").read().splitlines() if l and not l.startswith("#")]
    for c in csv.DictReader(io.StringIO("\n".join(cur_lines)), delimiter="\t", quoting=csv.QUOTE_NONE):
        if c["fixture"] != fx:
            continue
        hit = [lb for lb in labels if lb["id"].startswith(c["label"] + "-")]
        if len(hit) != 1:
            fail(f"curation.tsv: {fx} {c['label']} matches {len(hit)} seeded labels (re-check the row)")
        lb = hit[0]
        if c["action"] == "drop":
            labels.remove(lb)
            dropped.append(f"{lb['source']} [{lb['severity']}] curated out ({c['reason']}): {lb['title']}")
        elif c["action"] == "anchors":
            new = []
            for needle in [s.strip() for s in c["value"].split(" ||| ") if s.strip()]:
                at = unique_line(head_text[lb["file"]], needle)
                if at is None:
                    fail(f"curation.tsv: {fx} {c['label']} anchor {needle!r} is not on exactly one line of head/{lb['file']}")
                new.append((at, needle))
            lb["anchors"], lb["how"] = new, f"curated: {c['reason']}"
        else:
            fail(f"curation.tsv: unknown action {c['action']!r}")

fix_rows = []
for p in head_files:
    if generated_path(p):
        if hunks.get(p):
            note_excluded(p)
        continue
    for lo, hi in hunks.get(p, []):
        at, t = anchor_text(head_text[p], lo, hi)
        fix_rows.append({"id": f"F{len(fix_rows) + 1:03d}", "file": p, "must_match": t or "-",
                         "source": f"fix/{fixc[:12]}:{lo}-{hi}"})

# --- outputs ------------------------------------------------------------------------
subjects = [s for s in git("log", "--reverse", "--format=%s", f"{base}..{head}").splitlines() if s]
title = clean(subjects[0] if subjects else f"sprint-{sprint}", 200)
pr_md = f"# {title}\n\n" + (f"Sprint {sprint} (global), {len(head_files)} file(s) in scope.\n"
                             + ("\nCommits in this change:\n\n" + "\n".join(f"- {clean(s, 200)}" for s in subjects) + "\n" if len(subjects) > 1 else ""))
tsv = [f"# approved-by: pending",
       f"# fixture {fx} | sprint-{sprint} | record {record_ref} | base {base[:12]} | head {head[:12]} | fix {fixc[:12]}",
       "# seeded by evals/harness/seed-corpus-from-record.sh; curate must_match (one row per anchor: text on exactly one head line, or @L<n> for head line n), then --approve",
       *[f"# {lb['id'][:3]} {lb['severity']} {lb['label_source']}: {lb['title']} [{lb['how']}]" for lb in labels],
       "\t".join(HEADER)]
for lb in labels:
    for at, t in lb["anchors"]:
        tsv.append("\t".join([lb["id"], lb["severity"], lb["category"], lb["file"], t, lb["label_source"], lb["source"]]))
for fr in fix_rows:
    tsv.append("\t".join([fr["id"], "-", "fix", fr["file"], fr["must_match"], "fix", fr["source"]]))
for row in tsv:
    if "\t" in row and len(row.split("\t")) != len(HEADER):
        fail(f"internal: malformed label row {row[:80]!r}")

summary = (f"{fx} sprint-{sprint}: {len(head_files)} file(s), diff {len(diff_text)} B, "
           f"{len(labels)} label(s) ({sum(len(l['anchors']) for l in labels)} anchor row(s)), "
           f"{len(fix_rows)} fix row(s), {len(dropped)} dropped")
if args.dry_run:
    print(summary)
    for lb in labels:
        print(f"  KEEP {lb['id']} [{lb['severity']}/{lb['label_source']}] {lb['file']}:{lb['anchors'][0][0]} ({lb['how']}) — {lb['title']}")
    for d in dropped:
        print(f"  DROP {d}")
    sys.exit(0)

if not labels and not args.allow_no_labels:
    # the gap goes into corpus.tsv and the reasons into labels/<fx>.dropped.txt;
    # a previous build of this record fixture is removed (never left stale)
    shutil.rmtree(fdir, ignore_errors=True)
    for stale in (os.path.join(LABELS_DIR, f"{fx}.tsv"), os.path.join(MANIFESTS_DIR, f"{fx}.json"),
                  os.path.join(args.tasks_dir, "review-recall", f"review-{fx}.yaml"),
                  os.path.join(args.tasks_dir, "audit-recall", f"audit-{fx}.yaml")):
        if os.path.isfile(stale):
            os.remove(stale)
    os.makedirs(LABELS_DIR, exist_ok=True)
    open(os.path.join(LABELS_DIR, f"{fx}.dropped.txt"), "w", encoding="utf-8").write(
        f"# {fx} sprint-{sprint}: NOT BUILT — no finding became a label\n" + "\n".join(dropped) + ("\n" if dropped else ""))
    corpus_set(fx, f"# {fx} sprint-{sprint}: no record fixture — no finding met the fix-touches-file rule with a unique anchor ({len(dropped)} finding(s) dropped)")
    freeze()
    print(summary + " — NOT BUILT (gap recorded in corpus.tsv)")
    sys.exit(0)

base_files, head_files = [], []
for st, old, new in changes:
    if st != "A":
        b = show(base, old)
        if b is not None:
            base_files.append((old, redact(b)))
    if st != "D":
        h = show(head, new)
        if h is not None:
            head_files.append((new, redact(h)))
write_layout(fdir, base_files, head_files, diff_text, pr_md)
open(fy, "w", encoding="utf-8").write(
    f'name: {fx}\nversion: "1.0.0"\nlanguage: mixed\nruntime: none\ndependency_strategy: none\n'
    f'description: "record fixture: sprint-{sprint} round-1 state (cycle-129 FR-2); labels live in the hidden labels/ and manifests/ dirs"\n'
    f'difficulty: advanced\ndomain: framework\ndeprecated: false\n'
    f'sprint: {sprint}\nbase_commit: "{base}"\nhead_commit: "{head}"\nfix_commit: "{fixc}"\n'
    f'record_ref: "{record_ref}"\nfeedback_files:\n' + "".join(f'  - "{p}"\n' for p in fb_paths)
    + (f'scope_paths: "{scope_raw}"\n' if scope_raw else "") + exposure_block(head))
os.makedirs(LABELS_DIR, exist_ok=True)
open(os.path.join(LABELS_DIR, f"{fx}.tsv"), "w", encoding="utf-8").write("\n".join(tsv) + "\n")
open(os.path.join(LABELS_DIR, f"{fx}.dropped.txt"), "w", encoding="utf-8").write(
    f"# {fx} sprint-{sprint}: findings that did not become labels\n"
    + (f"# {REDACTED[0]} secret-shaped test string(s) redacted as REDACTED-TEST-SECRET in base/, head/ and head.diff "
       "(verbatim copies of tracked test fixtures; line numbers unchanged)\n" if REDACTED[0] else "")
    + "\n".join(dropped) + ("\n" if dropped else ""))

# no-secrets over everything written (the fixture dir, then the hidden label files)
ok, msg = no_secrets_scan(fdir)
with tempfile.TemporaryDirectory() as td:
    for n in (f"{fx}.tsv", f"{fx}.dropped.txt"):
        shutil.copyfile(os.path.join(LABELS_DIR, n), os.path.join(td, n))
    ok2, msg2 = no_secrets_scan(td)
if not (ok and ok2):
    shutil.rmtree(fdir, ignore_errors=True)
    for n in (f"{fx}.tsv", f"{fx}.dropped.txt"):
        try: os.remove(os.path.join(LABELS_DIR, n))
        except FileNotFoundError: pass
    fail(f"{fx}: no-secrets.sh failed; nothing kept: {msg if not ok else msg2}")

man = build_manifest(fx)

# tasks (one per suite), mirroring the pr-01 tasks
planted = len(man["defects"])
write_tasks(fx, f"record fixture {fx} (sprint-{sprint} round 1; {planted} label(s); hidden manifest)",
            ("cycle-129", "fr-2", None, "record"), args.tasks_dir)
corpus_row(fx, "record", head)
n = freeze()
print(summary + f"; SHA256SUMS {n} files")
PY
{ corpus_seed_python; printf '%s\n' "$SEED_RECORD_PY"; } | python3 -I - "$REPO_ROOT" "$@"
