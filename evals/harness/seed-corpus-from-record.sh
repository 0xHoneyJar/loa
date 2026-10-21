#!/usr/bin/env bash
# =============================================================================
# seed-corpus-from-record.sh — build a review-recall fixture from a shipped
# sprint's round-1 state and its record-branch feedback (cycle-129 FR-2,
# SDD D-2.2, DEC-0154)
#
# Usage:
#   seed-corpus-from-record.sh <global-sprint> <record-ref> [--out <corpus>/pr-NN]
#                              [--base <rev>] [--head <rev>] [--fix <rev>]
#                              [--feedback a.md,b.md] [--dry-run]
#   seed-corpus-from-record.sh --build-manifest pr-NN   # labels → hidden manifest (after curation)
#   seed-corpus-from-record.sh --approve pr-NN --by "<who> <YYYY-MM-DD>"
#   seed-corpus-from-record.sh --sync-labels pr-NN      # manifest anchors/approved_by → labels rows
#   seed-corpus-from-record.sh --freeze                 # regenerate SHA256SUMS
#   seed-corpus-from-record.sh --check                  # verify SHA256SUMS
#   common: [--repo <git dir>] [--corpus <evals/fixtures/review-prs>]
#
# Without --base/--head/--fix/--feedback/--out the sprint's row in
# <corpus>/record-pairs.tsv supplies them.
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
# for a line whose text is not unique (bd-y4pqj); `@L0`, a line past the end and a
# non-integer after `@L` are refused with the row named.
#
# --sync-labels pr-NN (bd-y4pqj) brings the labels to a curated manifest: for every
# anchor of manifests/pr-NN.json (`anchors`, else `anchor_line`) that no row of its
# defect resolves to, it inserts a row after that defect's last row, copying the
# primary row's columns, with must_match the line's stripped text when that text is
# on exactly one line (else `@L<n>`); it rewrites the first line to the manifest's
# approved_by and keeps every other line byte for byte. It prints the rows it added,
# adds nothing on a second run, never writes the manifest, and refuses (restoring the
# labels) when the synced labels would not rebuild the manifest byte for byte. It
# does not refreeze: run --freeze afterwards.
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
# Tested by evals/tests/seed-corpus.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec python3 -I - "$REPO_ROOT" "$@" <<'PY'
import argparse, csv, hashlib, io, json, os, re, shutil, subprocess, sys, tempfile

HARNESS_ROOT = sys.argv[1]
argv = sys.argv[2:]

ap = argparse.ArgumentParser(prog="seed-corpus-from-record.sh", add_help=True)
ap.add_argument("sprint", nargs="?")
ap.add_argument("record_ref", nargs="?")
ap.add_argument("--out"); ap.add_argument("--base"); ap.add_argument("--head"); ap.add_argument("--fix")
ap.add_argument("--feedback"); ap.add_argument("--dry-run", action="store_true")
ap.add_argument("--build-manifest", metavar="FIXTURE"); ap.add_argument("--approve", metavar="FIXTURE")
ap.add_argument("--sync-labels", metavar="FIXTURE")
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
FX_RX = re.compile(r"^pr-[0-9]{2}$")
HEADER = ["defect_id", "severity", "category", "file", "must_match", "label_source", "source"]

def fail(msg, code=1):
    print(f"seed-corpus: {msg}", file=sys.stderr)
    sys.exit(code)

def git(*a, binary=False, check=True):
    p = subprocess.run(["git", "-C", REPO, *a], capture_output=True, text=not binary)
    if check and p.returncode != 0:
        fail(f"git {' '.join(a[:3])} failed: {(p.stderr if not binary else p.stderr.decode('utf-8', 'replace')).strip()[:300]}")
    return p.stdout

def rev(r):
    p = subprocess.run(["git", "-C", REPO, "rev-parse", "--verify", "--quiet", f"{r}^{{commit}}"], capture_output=True, text=True)
    if p.returncode != 0:
        fail(f"missing commit: {r}")
    return p.stdout.strip()

def show(r, path):
    p = subprocess.run(["git", "-C", REPO, "show", f"{r}:{path}"], capture_output=True)
    return p.stdout if p.returncode == 0 else None

CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f  ]")
def clean(s, cap=160):
    s = CTRL.sub(" ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s if len(s) <= cap else s[: cap - 1].rstrip() + "…"

# audit r1 DISS-C-007: shapes beyond the original nine (PEM blocks, JWTs, GitHub
# fine-grained/app/user tokens, Google and Stripe keys, generic key/token assignments);
# the generic patterns stay on ONE line so a redaction never joins lines.
SECRET_RX = [re.compile(p) for p in (
    r"AKIA[0-9A-Z]{16}", r"sk-[a-zA-Z0-9]{20,}", r"ghp_[a-zA-Z0-9]{36}", r"gho_[a-zA-Z0-9]{36}",
    r"github_pat_[A-Za-z0-9_]{20,}", r"gh[su]_[a-zA-Z0-9]{36}",
    r"glpat-[a-zA-Z0-9\-]{20,}", r"xox[bpors]-[a-zA-Z0-9\-]+", r"sk-ant-[a-zA-Z0-9\-]{20,}",
    r"AIza[0-9A-Za-z\-_]{35}", r"(?:sk|rk)_(?:live|test)_[0-9a-zA-Z]{20,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]*-----END [A-Z ]*PRIVATE KEY-----",
    r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}",
    r"password[ \t]*[:=][ \t]*[\"'][^\"'\n]{8,}", r"secret[ \t]*[:=][ \t]*[\"'][^\"'\n]{8,}",
    r"(?:api[_-]?key|access[_-]?token|auth[_-]?token)[ \t]*[:=][ \t]*[\"'][^\"'\n]{16,}")]
def has_secret(s):
    return any(r.search(s) for r in SECRET_RX)

REDACTED = [0]
def redact(b, count=True):
    """Secret-shaped strings in verbatim copies of tracked files (fake test keys)
    become a fixed marker, identically in base/, head/ and head.diff; line
    numbers never move. Counted in the dropped report."""
    if b is None:
        return None
    t = b.decode("utf-8", "replace") if isinstance(b, bytes) else b
    for r in SECRET_RX:
        t, n = r.subn("REDACTED-TEST-SECRET", t)
        REDACTED[0] += n if count else 0
    return t.encode("utf-8") if isinstance(b, bytes) else t

def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()

def freeze():
    entries = []
    for root, _d, files in os.walk(CORPUS):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), CORPUS)
            if rel != "SHA256SUMS":
                entries.append(rel)
    lines = [f"{sha(os.path.join(CORPUS, rel))}  {rel}" for rel in sorted(entries)]
    open(os.path.join(CORPUS, "SHA256SUMS"), "w").write("\n".join(lines) + "\n")
    return len(lines)

def check():
    bad, n = [], 0
    for line in open(os.path.join(CORPUS, "SHA256SUMS"), encoding="utf-8"):
        if not line.strip():
            continue
        n += 1
        d, rel = line.rstrip("\n").split("  ", 1)
        p = os.path.join(CORPUS, rel)
        if not os.path.isfile(p) or sha(p) != d:
            bad.append(rel)
    listed = {l.rstrip("\n").split("  ", 1)[1] for l in open(os.path.join(CORPUS, "SHA256SUMS"), encoding="utf-8") if l.strip()}
    for root, _d, files in os.walk(CORPUS):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), CORPUS)
            if rel != "SHA256SUMS" and rel not in listed:
                bad.append(rel + " (not listed)")
    if bad:
        fail("SHA256SUMS mismatch: " + ", ".join(bad[:20]))
    print(f"corpus OK: {n} files match SHA256SUMS")

# ---------------------------------------------------------------- labels I/O
def read_labels(fx):
    path = os.path.join(LABELS_DIR, f"{fx}.tsv")
    if not os.path.isfile(path):
        fail(f"labels not found: {path}")
    text = open(path, encoding="utf-8").read().splitlines()
    if not text or not re.match(r"^# approved-by: \S", text[0]):
        fail(f"{path}: the first line must be '# approved-by: <who> <date>' (or 'pending')")
    approved_by = text[0][len("# approved-by: "):].strip()
    body = [l for l in text[1:] if l and not l.startswith("#")]
    if not body or body[0].split("\t") != HEADER:
        fail(f"{path}: header must be: " + "\t".join(HEADER))
    rows = []
    for i, l in enumerate(body[1:], 2):
        cells = l.split("\t")
        if len(cells) != len(HEADER):
            fail(f"{path}: row {i} has {len(cells)} columns, want {len(HEADER)}")
        rows.append(dict(zip(HEADER, cells)))
    return approved_by, rows, text

# bd-8o5rx: generated artefacts are never fix regions (see the header for the list)
GENERATED_NAMES = {"checksums.json", "REPO-MAP.md", ".build-manifest.json"}
GENERATED_SUFFIXES = (".map", ".d.ts", ".checksum")
def generated_path(p):
    parts = p.split("/")
    return "dist" in parts[:-1] or parts[-1] in GENERATED_NAMES or parts[-1].endswith(GENERATED_SUFFIXES)

EXCLUDED_SEEN = set()
def note_excluded(p):
    if p not in EXCLUDED_SEEN:
        EXCLUDED_SEEN.add(p)
        print(f"excluded generated path: {p}", file=sys.stderr)

def unique_line(lines, needle):
    hits = [i for i, l in enumerate(lines, 1) if needle in l]
    return hits[0] if len(hits) == 1 else None

# bd-y4pqj: `@L<n>` names head line n (1-based) for a curated anchor whose text is not unique
AT_LINE_RX = re.compile(r"^@L([1-9][0-9]*)$")
def resolve_anchor(lines, must_match, fname):
    """(line, None) when the must_match resolves, else (None, why)."""
    if must_match.startswith("@L"):
        m = AT_LINE_RX.match(must_match)
        if not m:
            return None, "is not @L<n> with n a positive integer"
        if int(m.group(1)) > len(lines):
            return None, f"is past the end of head/{fname} ({len(lines)} lines)"
        return int(m.group(1)), None
    at = unique_line(lines, must_match)
    return (at, None) if at is not None else (None, f"is not on exactly one line of head/{fname}")

def build_manifest(fx, write=True):
    approved_by, rows, _ = read_labels(fx)
    fyaml = os.path.join(CORPUS, fx, "fixture.yaml")
    meta = {}
    for l in open(fyaml, encoding="utf-8"):
        m = re.match(r"^(sprint|head_commit|fix_commit|record_ref):\s*\"?([^\"\n]*)\"?$", l)
        if m:
            meta[m.group(1)] = m.group(2)
    defects, regions, errors, order = {}, [], [], []
    for r in rows:
        if r["label_source"] not in ("review", "audit", "bridgebuilder", "fix"):
            errors.append(f"{r['defect_id']}: label_source {r['label_source']!r}"); continue
        hp = os.path.join(CORPUS, fx, "head", r["file"])
        if not os.path.isfile(hp):
            errors.append(f"{r['defect_id']}: head/{r['file']} missing"); continue
        lines = open(hp, encoding="utf-8", errors="replace").read().splitlines()
        if r["label_source"] == "fix" and generated_path(r["file"]):
            note_excluded(r["file"]); continue
        if r["label_source"] == "fix":
            m = re.match(r"^fix/[0-9a-f]+:(\d+)-(\d+)$", r["source"])
            if not m:
                errors.append(f"{r['defect_id']}: fix source must be fix/<sha>:<start>-<end>"); continue
            regions.append({"id": r["defect_id"], "file": r["file"], "start": int(m.group(1)), "end": int(m.group(2)),
                            "source": r["source"]})
            continue
        at, why = resolve_anchor(lines, r["must_match"], r["file"])
        if at is None:
            errors.append(f"{r['defect_id']}: must_match {r['must_match']!r} {why}"); continue
        d = defects.get(r["defect_id"])
        if d is None:
            order.append(r["defect_id"])
            defects[r["defect_id"]] = {"id": r["defect_id"], "file": r["file"], "anchor_line": at, "anchors": [at],
                                       "must_match": r["must_match"], "severity": r["severity"], "category": r["category"],
                                       "label_source": r["label_source"], "source": r["source"],
                                       "source_commit": meta.get("head_commit", "")[:8], "synthetic": False}
        else:
            if d["file"] != r["file"]:
                errors.append(f"{r['defect_id']}: extra anchor rows must name the same file"); continue
            d["anchors"].append(at)
    if errors:
        fail(f"{fx}: " + "; ".join(errors))
    out = []
    for k in order:
        d = defects[k]
        d["anchors"] = sorted(set(d["anchors"]))
        if len(d["anchors"]) == 1:
            del d["anchors"]
        out.append(d)
    man = {"fixture": fx, "approved": approved_by != "pending", "approved_by": approved_by,
           "record": {"sprint": meta.get("sprint"), "record_ref": meta.get("record_ref"),
                      "head_commit": meta.get("head_commit"), "fix_commit": meta.get("fix_commit")},
           "defects": out, "fix_regions": regions}
    if write:
        os.makedirs(MANIFESTS_DIR, exist_ok=True)
        json.dump(man, open(os.path.join(MANIFESTS_DIR, f"{fx}.json"), "w"), indent=2)
    return man

def sync_labels(fx):
    """bd-y4pqj: add a labels row for every manifest anchor no row resolves to; copy approved_by (see the header)."""
    mpath = os.path.join(MANIFESTS_DIR, f"{fx}.json")
    lpath = os.path.join(LABELS_DIR, f"{fx}.tsv")
    if not os.path.isfile(mpath):
        fail(f"manifest not found: {mpath}")
    mraw = open(mpath, encoding="utf-8").read()
    man = json.loads(mraw)
    approved_by = man.get("approved_by")
    if (not isinstance(approved_by, str) or not approved_by or approved_by != approved_by.strip()
            or re.search(r"[\x00-\x1f\x7f]", approved_by)):
        fail(f"{mpath}: approved_by must be a one-line non-empty string without surrounding space")
    if man.get("approved") is not (approved_by != "pending"):
        fail(f"{mpath}: approved {man.get('approved')!r} disagrees with approved_by {approved_by!r}")
    read_labels(fx)  # validates the header and every row's shape
    raw = open(lpath, encoding="utf-8", newline="").read()
    tl = raw.splitlines(keepends=True)
    heads, have, last, primary = {}, {}, {}, {}
    def head(f):
        if f not in heads:
            hp = os.path.join(CORPUS, fx, "head", f)
            if not os.path.isfile(hp):
                fail(f"{fx}: head/{f} missing")
            heads[f] = open(hp, encoding="utf-8", errors="replace").read().splitlines()
        return heads[f]
    seen_header = False
    for i, l in enumerate(tl[1:], 1):
        l = l.rstrip("\r\n")
        if not l or l.startswith("#"):
            continue
        if not seen_header:
            seen_header = True; continue
        r = dict(zip(HEADER, l.split("\t")))
        if r["label_source"] == "fix":
            continue
        at, why = resolve_anchor(head(r["file"]), r["must_match"], r["file"])
        if at is None:
            fail(f"{fx}: {r['defect_id']}: must_match {r['must_match']!r} {why}")
        primary.setdefault(r["defect_id"], r)
        have.setdefault(r["defect_id"], set()).add(at)
        last[r["defect_id"]] = i
    ids = [d.get("id") for d in man.get("defects", [])]
    for k in primary:
        if k not in ids:
            fail(f"{fx}: label {k} is not a defect of manifests/{fx}.json")
    adds, n_text, n_at = {}, 0, 0
    for d in man.get("defects", []):
        p = primary.get(d.get("id"))
        if p is None:
            fail(f"{fx}: manifest defect {d.get('id')!r} has no labels row")
        if d.get("file") != p["file"]:
            fail(f"{fx}: manifest defect {d['id']} names {d.get('file')!r}, its labels rows {p['file']!r}")
        want = d.get("anchors", [d.get("anchor_line")])
        lines = head(p["file"])
        for n in sorted(set(want)):
            if not isinstance(n, int) or isinstance(n, bool) or not 1 <= n <= len(lines):
                fail(f"{fx}: manifest defect {d['id']} anchor {n!r} is not a line of head/{p['file']}")
            if n in have[d["id"]]:
                continue
            t = lines[n - 1].strip()
            textual = (t and "\t" not in t and not t.startswith("@L") and len(t.splitlines()) == 1
                       and not has_secret(t) and unique_line(lines, t) == n)
            mm = t if textual else f"@L{n}"
            n_text, n_at = n_text + bool(textual), n_at + (not textual)
            adds.setdefault(last[d["id"]], []).append(
                (d["id"], mm, "\t".join([d["id"], p["severity"], p["category"], p["file"], mm, p["label_source"], p["source"]])))
            have[d["id"]].add(n)
    out = [f"# approved-by: {approved_by}\n"]
    for i, l in enumerate(tl[1:], 1):
        if i in adds and not l.endswith("\n"):
            l += "\n"
        out.append(l)
        out.extend(row + "\n" for _k, _m, row in adds.get(i, []))
    new = "".join(out)
    header_changed = tl[0].rstrip("\r\n") != out[0].rstrip("\n")
    if new != raw:
        open(lpath, "w", encoding="utf-8", newline="").write(new)
        rebuilt = json.dumps(build_manifest(fx, write=False), indent=2)
        if rebuilt != mraw:
            open(lpath, "w", encoding="utf-8", newline="").write(raw)
            fail(f"{fx}: the synced labels would not rebuild manifests/{fx}.json byte for byte; labels left unchanged")
    print(f"{fx}: added {n_text + n_at} row(s) ({n_text} text, {n_at} @L<n>); approved-by "
          + (f"set to {approved_by!r}" if header_changed else "unchanged")
          + ("; run --freeze to refresh SHA256SUMS" if new != raw else ""))
    for i in sorted(adds):
        for k, mm, _row in adds[i]:
            print(f"  + {k}\t{mm}")

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
for f in feedback:
    if "/" in f or f.startswith(".") or not f.endswith(".md"):
        fail(f"feedback file must be a bare .md name: {f}", 2)
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
    for p in (old, new):
        if p.startswith("/") or ".." in p.split("/"):
            fail(f"unsafe path in the change: {p}")
    changes.append((st, old, new))
if not changes:
    fail(f"sprint {sprint}: no in-scope file changed between {base[:8]} and {head[:8]}")
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
        if RX_H.match(l) and not RX_B.match(l):
            section = l
            in_fixed_table = bool(re.match(r"^#{2,4}\s+Fixed\b", l))
            i += 1; continue
        if SKIP_SECTION.search(section):
            i += 1; continue
        m_a, m_b = RX_A.match(l), RX_B.match(l)
        if m_a or m_b:
            sev = SEV[(m_a or m_b).group(1)]
            rest = m_a.group(3) if m_a else m_b.group(2)
            body = []
            j = i + 1
            while j < len(lines):
                n = lines[j]
                if RX_A.match(n) or RX_B.match(n) or RX_H.match(n) or (m_a and RX_BULLET.match(n)):
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
for name in feedback:
    path = f"grimoires/loa/a2a/sprint-{sprint}/{name}"
    blob = show(record_ref, path)
    if blob is None:
        dropped.append(f"{name}: not on {record_ref}")
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

if not labels:
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
    gap = f"# {fx} sprint-{sprint}: no record fixture — no finding met the fix-touches-file rule with a unique anchor ({len(dropped)} finding(s) dropped)"
    spec = os.path.join(CORPUS, "corpus.tsv")
    keep = [l for l in open(spec, encoding="utf-8").read().splitlines() if not (l.startswith(fx + "\t") or l.startswith(f"# {fx} "))]
    open(spec, "w", encoding="utf-8").write("\n".join(keep + [gap]) + "\n")
    freeze()
    print(summary + " — NOT BUILT (gap recorded in corpus.tsv)")
    sys.exit(0)

shutil.rmtree(fdir, ignore_errors=True)
os.makedirs(fdir)
for st, old, new in changes:
    if st != "A":
        b = show(base, old)
        if b is not None:
            bp = os.path.join(fdir, "base", old); os.makedirs(os.path.dirname(bp), exist_ok=True); open(bp, "wb").write(redact(b))
    if st != "D":
        h = show(head, new)
        if h is not None:
            hp = os.path.join(fdir, "head", new); os.makedirs(os.path.dirname(hp), exist_ok=True); open(hp, "wb").write(redact(h))
open(os.path.join(fdir, "head.diff"), "w", encoding="utf-8").write(diff_text)
open(os.path.join(fdir, "PR.md"), "w", encoding="utf-8").write(pr_md)
tmpl = os.path.join(CORPUS, "pr-01")
for name in ("REVIEW-INSTRUCTIONS.md", "AUDIT-INSTRUCTIONS.md"):
    shutil.copyfile(os.path.join(tmpl, name), os.path.join(fdir, name))
open(fy, "w", encoding="utf-8").write(
    f'name: {fx}\nversion: "1.0.0"\nlanguage: mixed\nruntime: none\ndependency_strategy: none\n'
    f'description: "record fixture: sprint-{sprint} round-1 state (cycle-129 FR-2); labels live in the hidden labels/ and manifests/ dirs"\n'
    f'difficulty: advanced\ndomain: framework\ndeprecated: false\n'
    f'sprint: {sprint}\nbase_commit: "{base}"\nhead_commit: "{head}"\nfix_commit: "{fixc}"\n'
    f'record_ref: "{record_ref}"\nfeedback_files:\n' + "".join(f'  - "{p}"\n' for p in fb_paths))
os.makedirs(LABELS_DIR, exist_ok=True)
open(os.path.join(LABELS_DIR, f"{fx}.tsv"), "w", encoding="utf-8").write("\n".join(tsv) + "\n")
open(os.path.join(LABELS_DIR, f"{fx}.dropped.txt"), "w", encoding="utf-8").write(
    f"# {fx} sprint-{sprint}: findings that did not become labels\n"
    + (f"# {REDACTED[0]} secret-shaped test string(s) redacted as REDACTED-TEST-SECRET in base/, head/ and head.diff "
       "(verbatim copies of tracked test fixtures; line numbers unchanged)\n" if REDACTED[0] else "")
    + "\n".join(dropped) + ("\n" if dropped else ""))

# no-secrets over everything written (the fixture dir, then the hidden label files)
def scan(d):
    p = subprocess.run(["bash", NO_SECRETS, d], capture_output=True, text=True)
    return p.returncode == 0, p.stdout.strip()
ok, msg = scan(fdir)
with tempfile.TemporaryDirectory() as td:
    for n in (f"{fx}.tsv", f"{fx}.dropped.txt"):
        shutil.copyfile(os.path.join(LABELS_DIR, n), os.path.join(td, n))
    ok2, msg2 = scan(td)
if not (ok and ok2):
    shutil.rmtree(fdir, ignore_errors=True)
    for n in (f"{fx}.tsv", f"{fx}.dropped.txt"):
        try: os.remove(os.path.join(LABELS_DIR, n))
        except FileNotFoundError: pass
    fail(f"{fx}: no-secrets.sh failed; nothing kept: {msg if not ok else msg2}")

man = build_manifest(fx)

# tasks (one per suite), mirroring the pr-01 tasks
planted = len(man["defects"])
for suite, kind, skill, art, verb in (("review-recall", "review", "reviewing-code", "review.md", "review recall on"),
                                      ("audit-recall", "audit", "auditing-security", "audit.md", "audit planted-defect detection on")):
    instr = "REVIEW-INSTRUCTIONS.md" if kind == "review" else "AUDIT-INSTRUCTIONS.md"
    tdir = os.path.join(args.tasks_dir, suite); os.makedirs(tdir, exist_ok=True)
    open(os.path.join(tdir, f"{kind}-{fx}.yaml"), "w", encoding="utf-8").write(
        f'id: {kind}-{fx}\nschema_version: 1\nskill: {skill}\ncategory: skill-quality\nfixture: review-prs/{fx}\n'
        f'description: "{verb} record fixture {fx} (sprint-{sprint} round 1; {planted} label(s); hidden manifest)"\n'
        f'prompt: "Read {instr} in this directory and carry it out."\nagent:\n  skill: {skill}\n  artifacts: [{art}]\n'
        # record PRs carry 66-383 KB diffs (pr-01 … pr-08: ~7 KB): an hour, not 25 min
        f'trials: 3\ntimeout:\n  per_trial: 3600\n  per_grader: 60\ngraders:\n  - type: code\n    script: recall-vs-defects.sh\n'
        f'    args: ["{fx}", "{art}"]\n    weight: 1.0\n  - type: code\n    script: verdict-consistency.sh\n'
        f'    args: ["{art}", "{kind}"]\n    weight: 0.5\ndifficulty: advanced\ntags: ["cycle-129", "fr-2", "{suite}", "record"]\n')

spec = os.path.join(CORPUS, "corpus.tsv")
keep = [l for l in open(spec, encoding="utf-8").read().splitlines() if not (l.startswith(fx + "\t") or l.startswith(f"# {fx} "))]
keep.append("\t".join([fx, "record", head[:8], f"labels/{fx}.tsv", "-", "-", "-", "-"]))
open(spec, "w", encoding="utf-8").write("\n".join(keep) + "\n")
n = freeze()
print(summary + f"; SHA256SUMS {n} files")
PY
