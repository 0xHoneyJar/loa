#!/usr/bin/env bash
# =============================================================================
# record-branch.sh — build one stage of a cycle's record branch
# (cycle-133 Sprint 1 Task 1.4; SDD §1.4 C-4, §5.2, §5.4; PRD FR-4(a)).
#
# The record branch `record/<ledger cycle id>` carries the cycle's merged tree
# plus its gitignored records (a2a sprint directories, audits, Flatline and
# prompt records, NOTES and its archive, the cycle's results batches and the
# record_lite tree). It replaces the per-cycle cache scripts of cycles 125-132.
#
# Usage:
#   record-branch.sh --cycle N --head SHA --prev REF --stage LABEL
#                    [--manifest FILE] [--add PATH]... [--dry-run]
#                    [--accept-scan TREE_SHA] [--scan-max-bytes N]
#
#   --cycle N          ledger cycle number; resolves the ledger cycle whose id
#                      is `cycle-N` or starts with `cycle-N-` (the record ref
#                      is refs/heads/record/<that id>)
#   --head SHA         the cycle's merged commit (second parent; its tree is
#                      the base of the record tree)
#   --prev REF         the previous record commit (first parent): the prior
#                      cycle's record for stage 1, this record for later stages
#   --stage LABEL      one-line stage label ("stage 1"); its slug names the
#                      manifest file inside the record
#   --manifest FILE    JSON {paths: [..], results_roots: [..], lite_tree: str|null}
#                      replacing the ledger-derived default
#   --add PATH         an extra repository path to record (repeatable)
#   --dry-run          print the size table of what would be recorded; no
#                      object, index or ref is written (parent and ref checks
#                      print as warnings)
#   --accept-scan TREE acknowledge the non-credential scan hits of exactly the
#                      staged tree TREE (the sha the refusal names as scan_tree=)
#   --scan-max-bytes N bound of the exported scan directory (default 4 GiB)
#   --help             this text
#
# Default manifest (from the ledger cycle): grimoires/loa/a2a/sprint-<global id>
# for each cycle sprint; the bug micro-sprint directories (bug-*/, sprint-bug-*)
# of ledger bugfix entries created within the cycle's date window;
# a2a/audits/<YYYY-MM-DD> within that window; a2a/flatline; a2a/prompts;
# grimoires/loa/NOTES.md; grimoires/loa/archive/notes; results roots
# evals/results/ablation-2.0/c<N>-* minus every sandbox/, snapshots/ and
# grading/pr/ directory; the lite tree evals/results/ablation-2.0/c<N>-lite.
# The window runs from the cycle's `created` date to its `archived` date
# (today while active), whole days, UTC.
#
# Order (every refusal happens before any ref is written):
#   1. parents --prev and --head must already be on origin (a remote-tracking
#      ref under refs/remotes/origin/ contains them); the record ref must be
#      absent or equal to --prev (compare-and-swap expectation)
#   2. every manifest path must stay inside the repository without passing a
#      symlinked directory; nested git repositories and non-regular files are
#      refused; every symlink of the complete final tree (inherited <head>
#      entries, the additions, the lite tree) must be relative and name a path
#      that is itself in the record; gitlinks are refused
#   3. temporary index (GIT_INDEX_FILE): read-tree <head>, add -f, write-tree
#      → scan_tree; the working tree and the real index are never touched
#   4. secret scan over `git diff-tree -r <head> <scan_tree>` exported to a
#      bounded temporary directory: audit-secret-redaction-scan.sh (class
#      audit-key-password-assignment) plus the credential shapes private-key,
#      anthropic-key, openai-key, github-token, aws-access-key, google-api-key,
#      slack-token, bearer-token. Credential-shaped hits stop the build
#      unconditionally; other hits stop unless --accept-scan names scan_tree.
#      Hits print as path:line:class; the matched text is never printed.
#   5. the manifest grimoires/loa/a2a/record-manifests/<cycle id>/<stage slug>.json
#      {cycle, head, prev, stage, paths, results_roots, lite_tree, scan_tree,
#      accepted_scan} joins the tree; scan_tree and accepted_scan also go into
#      the commit message
#   6. commit-tree -p <prev> -p <head>; update-ref <record ref> <new> <expected
#      old> (compare-and-swap). The push stays the operator's ICE call:
#      .claude/scripts/run-mode-ice.sh push origin record/<cycle id>
#
# Exit codes (SDD §5.4): 0 built (or dry-run printed) · 1 a step failed ·
# 2 refusal before any ref write (usage, precondition, symlink or escape,
# scan hit, compare-and-swap).
# Tests: tests/unit/record-branch.bats
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/audit-secret-redaction-scan.sh"

usage() { sed -n '/^# Usage:/,/^# Tests:/p' "$0" | sed 's/^# \{0,1\}//'; }
refuse() { echo "record-branch: REFUSED: $*" >&2; exit 2; }
fail() { echo "record-branch: FAILED: $*" >&2; exit 1; }
warn() { echo "record-branch: WARN: $*" >&2; }

CYCLE="" HEAD_REF="" PREV_REF="" STAGE="" MANIFEST_IN="" DRY=0 ACCEPT="" SCAN_MAX=4294967296
ADDS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cycle)          [[ $# -ge 2 ]] || refuse "--cycle needs a number (see --help)"; CYCLE="$2"; shift 2 ;;
    --head)           [[ $# -ge 2 ]] || refuse "--head needs a commit (see --help)"; HEAD_REF="$2"; shift 2 ;;
    --prev)           [[ $# -ge 2 ]] || refuse "--prev needs a commit (see --help)"; PREV_REF="$2"; shift 2 ;;
    --stage)          [[ $# -ge 2 ]] || refuse "--stage needs a label (see --help)"; STAGE="$2"; shift 2 ;;
    --manifest)       [[ $# -ge 2 ]] || refuse "--manifest needs a file (see --help)"; MANIFEST_IN="$2"; shift 2 ;;
    --add)            [[ $# -ge 2 && -n "$2" ]] || refuse "--add needs a path (see --help)"; ADDS+=("$2"); shift 2 ;;
    --dry-run)        DRY=1; shift ;;
    --accept-scan)    [[ $# -ge 2 ]] || refuse "--accept-scan needs the scan_tree sha the refusal printed"; ACCEPT="$2"; shift 2 ;;
    --scan-max-bytes) [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || refuse "--scan-max-bytes needs a positive integer"; SCAN_MAX="$2"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *)                refuse "unknown argument '$1' (see --help)" ;;
  esac
done
[[ "$CYCLE" =~ ^[0-9]+$ ]] || refuse "--cycle N is required (the ledger cycle number, e.g. --cycle 133)"
[[ -n "$HEAD_REF" ]] || refuse "--head SHA is required (the cycle's merged commit)"
[[ -n "$PREV_REF" ]] || refuse "--prev REF is required (the previous record commit)"
[[ -n "$STAGE" ]] || refuse "--stage LABEL is required (e.g. --stage \"stage 1\")"
[[ "$STAGE" != *$'\n'* && ${#STAGE} -le 80 ]] || refuse "--stage must be one line of at most 80 characters"
if [[ -n "$ACCEPT" && ! "$ACCEPT" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
  refuse "--accept-scan must be a full tree sha (the scan_tree= value of the refusal)"
fi
STAGE_SLUG="$(printf '%s' "$STAGE" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[[ -n "$STAGE_SLUG" ]] || refuse "--stage '$STAGE' has no letters or digits to name the manifest"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not inside a git work tree; run from the repository root"
cd "$ROOT"
LEDGER="grimoires/loa/ledger.json"
[[ -f "$LEDGER" ]] || refuse "no $LEDGER in $ROOT"
command -v jq >/dev/null 2>&1 || refuse "jq is required"
command -v python3 >/dev/null 2>&1 || refuse "python3 is required"
[[ -f "$SCANNER" ]] || refuse "the scanner $SCANNER is missing"

ids="$(jq -r --arg n "$CYCLE" '[.cycles[]? | .id | select(type == "string") | select(test("^cycle-0*" + $n + "(-|$)"))] | .[]' "$LEDGER")" \
  || refuse "$LEDGER does not parse; repair the ledger first"
[[ -n "$ids" ]] || refuse "no ledger cycle matching cycle-$CYCLE in $LEDGER"
[[ "$ids" != *$'\n'* ]] || refuse "more than one ledger cycle matches cycle-$CYCLE: $(printf '%s' "$ids" | paste -sd' ' -)"
CYCLE_ID="$ids"
[[ "$CYCLE_ID" =~ ^[A-Za-z0-9._-]+$ ]] || refuse "ledger cycle id '$CYCLE_ID' is not a valid ref component"
BRANCH="record/$CYCLE_ID"
REF="refs/heads/$BRANCH"
MANIFEST_PATH="grimoires/loa/a2a/record-manifests/$CYCLE_ID/$STAGE_SLUG.json"

HEAD_SHA="$(git rev-parse --verify --quiet "$HEAD_REF^{commit}")" || refuse "--head '$HEAD_REF' is not a commit"
PREV_SHA="$(git rev-parse --verify --quiet "$PREV_REF^{commit}")" || refuse "--prev '$PREV_REF' is not a commit"

# --- 1. parents public, compare-and-swap expectation -------------------------
precondition() { if (( DRY )); then warn "$*"; else refuse "$*"; fi; }
on_origin() { [[ -n "$(git for-each-ref --contains "$1" --format='%(refname)' refs/remotes/origin/)" ]]; }
git remote get-url origin >/dev/null 2>&1 || precondition "no remote 'origin'; the parents must be public refs"
on_origin "$HEAD_SHA" || precondition "--head $HEAD_SHA is not on origin (no refs/remotes/origin/* contains it); push or fetch it first"
on_origin "$PREV_SHA" || precondition "--prev $PREV_SHA is not on origin (no refs/remotes/origin/* contains it); push the previous record first"
CUR="$(git rev-parse --verify --quiet "$REF" || true)"
if [[ -n "$CUR" && "$CUR" != "$PREV_SHA" ]]; then
  precondition "$BRANCH is at $CUR, not --prev $PREV_SHA; compare-and-swap refused (check who moved it, then pass --prev $CUR to build on it)"
fi
if [[ "$(git rev-parse --show-object-format 2>/dev/null || echo sha1)" == "sha256" ]]; then
  ZERO="$(printf '%064d' 0)"
else
  ZERO="$(printf '%040d' 0)"
fi
EXPECTED="${CUR:-$ZERO}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/record-branch.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT

# --- the Python helper (stdlib only; reads untrusted directories → -I) -------
read -r -d '' PY <<'PYEOF' || true
import datetime, json, os, posixpath, re, stat, subprocess, sys

def die(code, msg):
    print("record-branch: REFUSED: " + msg if code == 2 else "record-branch: FAILED: " + msg, file=sys.stderr)
    sys.exit(code)

def git(*args, data=None):
    p = subprocess.run(["git", *args], input=data, capture_output=True)
    if p.returncode != 0:
        die(1, "git %s: %s" % (" ".join(args[:2]), p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout

def tree_entries(tree):
    """[(mode, type, sha, size_or_None, path)] of the whole tree."""
    out = []
    for rec in git("ls-tree", "-r", "-z", "-l", "--full-tree", tree).split(b"\0"):
        if not rec:
            continue
        meta, path = rec.split(b"\t", 1)
        mode, typ, sha, size = meta.split()
        out.append((mode.decode(), typ.decode(), sha.decode(), None if size == b"-" else int(size), path.decode("utf-8", "surrogateescape")))
    return out

class Batch:
    """One `git cat-file --batch` process, one object at a time (streams; no deadlock, bounded memory)."""
    def __init__(self):
        self.p = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    def stream(self, sha, sink):
        self.p.stdin.write((sha + "\n").encode()); self.p.stdin.flush()
        hdr = self.p.stdout.readline().split()
        if len(hdr) < 3 or hdr[1] == b"missing":
            die(1, "object %s missing" % sha)
        left = int(hdr[2])
        while left:
            chunk = self.p.stdout.read(min(left, 1 << 20))
            if not chunk:
                die(1, "git cat-file --batch ended early on %s" % sha)
            sink(chunk); left -= len(chunk)
        self.p.stdout.read(1)
    def read(self, sha):
        parts = []
        self.stream(sha, parts.append)
        return b"".join(parts)
    def close(self):
        self.p.stdin.close(); self.p.wait()

def read_blobs(shas):
    b = Batch()
    try:
        return {s: b.read(s) for s in shas}
    finally:
        b.close()

def check_links(links, files):
    """links: [(path, target)]; files: set of every final path. Refuse escapes."""
    dirs = set()
    for f in files:
        d = posixpath.dirname(f)
        while d and d not in dirs:
            dirs.add(d)
            d = posixpath.dirname(d)
    for path, target in sorted(links):
        if target.startswith("/"):
            die(2, "%s is a symlink to the absolute path %s; replace it with a regular file or drop it from the record" % (path, target))
        resolved = posixpath.normpath(posixpath.join(posixpath.dirname(path), target))
        if resolved == ".." or resolved.startswith("../"):
            die(2, "%s is a symlink leaving the repository (%s); replace it with a regular file or drop it from the record" % (path, target))
        if resolved not in files and resolved not in dirs:
            die(2, "%s is a symlink to %s, which is not in the record; record the target or drop the symlink" % (path, resolved))

def head_links(head):
    ents = tree_entries(head)
    for mode, typ, sha, size, path in ents:
        if mode == "160000":
            die(2, "%s is a gitlink (submodule) in %s; a record cannot carry submodules" % (path, head))
    lk = [(p, s) for m, t, s, z, p in ents if m == "120000"]
    blobs = read_blobs(sorted({s for p, s in lk}))
    return {p for m, t, s, z, p in ents}, [(p, blobs[s].decode("utf-8", "surrogateescape")) for p, s in lk]

EXCLUDED = ("sandbox", "snapshots")

def excluded(rel_parts):
    for i, part in enumerate(rel_parts):
        if part in EXCLUDED:
            return True
        if part == "grading" and i + 1 < len(rel_parts) and rel_parts[i + 1] == "pr":
            return True
    return False

def cmd_collect(root, head, ledger_path, cycle_id, cycle_num, manifest_in, adds_file):
    root_real = os.path.realpath(root)
    with open(ledger_path, encoding="utf-8") as fh:
        ledger = json.load(fh)
    adds = [a for a in open(adds_file, encoding="utf-8", errors="surrogateescape").read().split("\0") if a]
    explicit = set()
    if manifest_in:
        try:
            with open(manifest_in, encoding="utf-8") as fh:
                m = json.load(fh)
        except (OSError, ValueError) as e:
            die(2, "--manifest %s does not parse as JSON: %s" % (manifest_in, e))
        if not isinstance(m, dict):
            die(2, "--manifest must be a JSON object {paths, results_roots, lite_tree}")
        paths, roots, lite = m.get("paths", []), m.get("results_roots", []), m.get("lite_tree")
        if not (isinstance(paths, list) and all(isinstance(p, str) and p for p in paths)
                and isinstance(roots, list) and all(isinstance(p, str) and p for p in roots)
                and (lite is None or (isinstance(lite, str) and lite))):
            die(2, "--manifest fields: paths and results_roots are lists of non-empty strings, lite_tree a string or null")
        explicit.update(paths); explicit.update(roots)
        if lite:
            explicit.add(lite)
    else:
        cyc = [c for c in ledger.get("cycles", []) if isinstance(c, dict) and c.get("id") == cycle_id][0]
        start = str(cyc.get("created") or "")[:10]
        end = str(cyc.get("archived") or "")[:10] or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
        a2a = "grimoires/loa/a2a"
        isdir = lambda p: os.path.isdir(os.path.join(root, p)) and not os.path.islink(os.path.join(root, p))
        paths = []
        for s in cyc.get("sprints", []) or []:
            if isinstance(s, dict) and isinstance(s.get("global_id"), int):
                paths.append("%s/sprint-%d" % (a2a, s["global_id"]))
        bugs = []
        for key in ("bugfix_cycles", "bugfixes"):
            v = ledger.get(key)
            if isinstance(v, list):
                bugs.extend(b for b in v if isinstance(b, dict))
        for b in bugs:
            day = str(b.get("created_at") or b.get("created") or "")[:10]
            if not (start and day and start <= day <= end):
                continue
            tri = b.get("triage")
            if isinstance(tri, str) and tri.startswith(a2a + "/"):
                paths.append(posixpath.dirname(tri))
            for sp in b.get("sprints", []) or []:
                if isinstance(sp, str) and re.fullmatch(r"sprint-bug-[A-Za-z0-9-]+", sp):
                    paths.append("%s/%s" % (a2a, sp))
        aud = os.path.join(root, a2a, "audits")
        if os.path.isdir(aud):
            for d in sorted(os.listdir(aud)):
                if re.fullmatch(r"\d{4}-\d{2}-\d{2}", d) and start <= d <= end:
                    paths.append("%s/audits/%s" % (a2a, d))
        paths += ["%s/flatline" % a2a, "%s/prompts" % a2a, "grimoires/loa/NOTES.md", "grimoires/loa/archive/notes"]
        paths = [p for p in paths if os.path.lexists(os.path.join(root, p))]
        res = "evals/results/ablation-2.0"
        lite_name = "c%s-lite" % cycle_num
        roots, lite = [], None
        if os.path.isdir(os.path.join(root, res)):
            for d in sorted(os.listdir(os.path.join(root, res))):
                if not d.startswith("c%s-" % cycle_num) or not isdir("%s/%s" % (res, d)):
                    continue
                if d == lite_name:
                    lite = "%s/%s" % (res, d)
                else:
                    roots.append("%s/%s" % (res, d))
    def norm(p):
        if "\n" in p:
            die(2, "path %r contains a newline; rename it before recording" % p)
        if os.path.isabs(p):
            rp = os.path.normpath(p)
            for base in (root_real, root):
                if rp == base or rp.startswith(base + os.sep):
                    p = os.path.relpath(rp, base)
                    break
            else:
                die(2, "%s is outside the repository %s" % (p, root))
        q = posixpath.normpath(p)
        if q == "." or q == ".." or q.startswith("../"):
            die(2, "%s is outside the repository %s" % (p, root))
        parent = posixpath.dirname(q)
        if parent and os.path.realpath(os.path.join(root, parent)) != os.path.join(root_real, parent):
            real = os.path.realpath(os.path.join(root, parent))
            where = "outside the repository" if not (real == root_real or real.startswith(root_real + os.sep)) else "through a symlinked directory"
            die(2, "%s resolves %s (%s → %s); record the real path instead" % (p, where, parent, real))
        if q == ".git" or q.startswith(".git/"):
            die(2, "%s is inside .git" % p)
        return q
    paths = list(dict.fromkeys([norm(p) for p in paths] + [norm(a) for a in adds]))
    roots = list(dict.fromkeys(norm(p) for p in roots))
    lite = norm(lite) if lite else None
    explicit.update(adds)
    explicit = {norm(p) for p in explicit}
    files, links = {}, []
    def visit(top, is_root):
        full = os.path.join(root, top)
        if not os.path.lexists(full):
            if top in explicit:
                die(2, "%s does not exist; drop it from the manifest or create it" % top)
            return
        st = os.lstat(full)
        if stat.S_ISLNK(st.st_mode):
            files[top] = st; links.append((top, os.readlink(full))); return
        if stat.S_ISREG(st.st_mode):
            files[top] = st; return
        if not stat.S_ISDIR(st.st_mode):
            die(2, "%s is not a regular file, directory or symlink" % top)
        for dp, dns, fns in os.walk(full, followlinks=False):
            rel = os.path.relpath(dp, root)
            if ".git" in dns or ".git" in fns:
                die(2, "%s contains a nested git repository (%s/.git); drop it from the record" % (top, rel))
            keep = []
            for d in sorted(dns):
                r = posixpath.join(rel, d)
                if is_root and excluded(posixpath.relpath(r, top).split("/")):
                    continue
                if os.path.islink(os.path.join(dp, d)):
                    files[r] = os.lstat(os.path.join(dp, d)); links.append((r, os.readlink(os.path.join(dp, d))))
                else:
                    keep.append(d)
            dns[:] = keep
            for f in sorted(fns):
                r = posixpath.join(rel, f)
                if "\n" in r:
                    die(2, "path %r contains a newline; rename it before recording" % r)
                if is_root and excluded(posixpath.relpath(r, top).split("/")):
                    continue
                st = os.lstat(os.path.join(dp, f))
                if stat.S_ISLNK(st.st_mode):
                    files[r] = st; links.append((r, os.readlink(os.path.join(dp, f))))
                elif stat.S_ISREG(st.st_mode):
                    files[r] = st
                else:
                    die(2, "%s is not a regular file or symlink" % r)
    for p in paths:
        visit(p, False)
    for p in roots:
        visit(p, True)
    if lite:
        visit(lite, False)
    head_paths, hlinks = head_links(head)
    final = head_paths | set(files)
    check_links(hlinks + links, final)
    sizes = {p: st.st_size for p, st in files.items()}
    json.dump({"paths": paths, "results_roots": roots, "lite_tree": lite,
               "files": sorted(files), "sizes": sizes}, sys.stdout, sort_keys=True)

def cmd_table(collect_json):
    c = json.load(open(collect_json, encoding="utf-8"))
    groups = {}
    for p in c["files"]:
        parts = p.split("/")
        g = "/".join(parts[:min(4, len(parts) - 1)]) or p
        n, b = groups.get(g, (0, 0))
        groups[g] = (n + 1, b + c["sizes"][p])
    print("%8s  %14s  %s" % ("files", "bytes", "group"))
    tn = tb = 0
    for g in sorted(groups):
        n, b = groups[g]
        tn += n; tb += b
        print("%8d  %14d  %s" % (n, b, g))
    print("%8d  %14d  %s" % (tn, tb, "total"))

def cmd_checktree(tree):
    paths, links = head_links(tree)
    check_links(links, paths)

def cmd_export(tree, diff_nul, outdir, maxbytes):
    want = {p.decode("utf-8", "surrogateescape") for p in open(diff_nul, "rb").read().split(b"\0") if p}
    ents = [e for e in tree_entries(tree) if e[4] in want]
    total = sum(e[3] or 0 for e in ents)
    if total > int(maxbytes):
        die(2, "the scan export is %d bytes (bound %s); split the record with --manifest or raise --scan-max-bytes" % (total, maxbytes))
    batch = Batch()
    out_real = os.path.realpath(outdir)
    listed = []
    for mode, typ, sha, size, path in sorted(ents, key=lambda e: e[4]):
        if typ != "blob":
            continue
        dest = os.path.realpath(os.path.join(outdir, path))
        if not dest.startswith(out_real + os.sep):
            die(2, "tree path %s escapes the scan directory" % path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as fh:
            batch.stream(sha, fh.write)
        listed.append(path)
    batch.close()
    sys.stdout.write("".join(p + "\n" for p in listed))

CRED = [
    ("private-key", re.compile(rb"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"), False),
    ("anthropic-key", re.compile(rb"sk-ant-([A-Za-z0-9_-]{20,})"), False),
    ("openai-key", re.compile(rb"(?<![A-Za-z0-9_-])sk-(?!ant-)([A-Za-z0-9_-]{20,})"), True),
    ("github-token", re.compile(rb"(?<![A-Za-z0-9_])(?:gh[pousr]_([A-Za-z0-9]{36,})|github_pat_([A-Za-z0-9_]{22,}))"), False),
    ("aws-access-key", re.compile(rb"(?<![A-Z0-9])(?:AKIA|ASIA)([A-Z0-9]{16})(?![A-Z0-9])"), False),
    ("google-api-key", re.compile(rb"AIza([0-9A-Za-z_-]{35})"), False),
    ("slack-token", re.compile(rb"xox[abporsu]-([A-Za-z0-9-]{10,})"), True),
    ("bearer-token", re.compile(rb"[Bb]earer\s+([A-Za-z0-9._~+/-]{20,})"), True),
]

def secretish(m, generic):
    groups = [g for g in m.groups() if g]
    if not groups:
        return True
    body = groups[0]
    if len(set(body)) < 6:
        return False          # placeholder shapes: xxxx…, 0000…, REDACTED
    if generic and not (re.search(rb"[0-9]", body) and re.search(rb"[A-Za-z]", body)):
        return False          # prose ("Bearer authentication-is-required") is not a token
    return True

def cmd_credscan(outdir, list_file):
    hits = []
    for path in [l for l in open(list_file, encoding="utf-8", errors="surrogateescape").read().split("\n") if l]:
        with open(os.path.join(outdir, path), "rb") as fh:
            for n, line in enumerate(fh, 1):
                for cls, rx, generic in CRED:
                    if any(secretish(m, generic) for m in rx.finditer(line)):
                        hits.append("%s:%d:%s" % (path, n, cls))
    sys.stdout.write("".join(h + "\n" for h in hits))

def cmd_parsepw(list_file, pw_out):
    known = sorted([l for l in open(list_file, encoding="utf-8", errors="surrogateescape").read().split("\n") if l], key=len, reverse=True)
    hits = []
    for line in open(pw_out, encoding="utf-8", errors="surrogateescape").read().split("\n"):
        for p in known:
            m = re.match(re.escape(p) + r":(\d+):", line)
            if m:
                hits.append("%s:%s:audit-key-password-assignment" % (p, m.group(1)))
                break
        else:
            if line.strip():
                die(1, "unparsed scanner output line (path not in the export): %d bytes" % len(line))
    sys.stdout.write("".join(h + "\n" for h in hits))

def cmd_manifest(collect_json, cycle, head, prev, stage, scan_tree, accepted_file):
    c = json.load(open(collect_json, encoding="utf-8"))
    acc = []
    for l in open(accepted_file, encoding="utf-8", errors="surrogateescape").read().split("\n"):
        if l:
            p, n, cls = l.rsplit(":", 2)
            acc.append({"path": p, "line": int(n), "class": cls})
    doc = {"cycle": cycle, "head": head, "prev": prev, "stage": stage, "paths": c["paths"],
           "results_roots": c["results_roots"], "lite_tree": c["lite_tree"],
           "scan_tree": scan_tree, "accepted_scan": acc}
    sys.stdout.write(json.dumps(doc, sort_keys=True, indent=2, ensure_ascii=False) + "\n")

{"collect": cmd_collect, "table": cmd_table, "checktree": cmd_checktree, "export": cmd_export,
 "credscan": cmd_credscan, "parsepw": cmd_parsepw, "manifest": cmd_manifest}[sys.argv[1]](*sys.argv[2:])
PYEOF
py() { python3 -I -c "$PY" "$@"; }

# --- 2. manifest, escape and symlink refusal (before staging) ---------------
: > "$WORK/adds.nul"
for a in ${ADDS[@]+"${ADDS[@]}"}; do printf '%s\0' "$a" >> "$WORK/adds.nul"; done
py collect "$ROOT" "$HEAD_SHA" "$LEDGER" "$CYCLE_ID" "$CYCLE" "$MANIFEST_IN" "$WORK/adds.nul" > "$WORK/collect.json"
NFILES="$(jq -r '.files | length' "$WORK/collect.json")" || fail "collect output does not parse"

if (( DRY )); then
  echo "record-branch: dry run — $BRANCH stage '$STAGE' over $HEAD_SHA (prev $PREV_SHA): $NFILES files to add"
  py table "$WORK/collect.json"
  exit 0
fi

# --- 3. temporary index → scan_tree ------------------------------------------
export GIT_INDEX_FILE="$WORK/index"
git read-tree "$HEAD_SHA"
jq -j '.files[] | . + "\u0000"' "$WORK/collect.json" > "$WORK/files.nul" || fail "cannot list the files to add"
if [[ -s "$WORK/files.nul" ]]; then
  git --literal-pathspecs add -f --pathspec-from-file="$WORK/files.nul" --pathspec-file-nul \
    || fail "git add -f into the temporary index failed"
fi
SCAN_TREE="$(git write-tree)"

# --- 4. secret scan over the paths that differ from <head> -------------------
git diff-tree -r -z --name-only --no-renames "$HEAD_SHA" "$SCAN_TREE" > "$WORK/diff.nul"
mkdir -p "$WORK/scan"
py export "$SCAN_TREE" "$WORK/diff.nul" "$WORK/scan" "$SCAN_MAX" > "$WORK/scan.list"
pw_rc=0
(cd "$WORK/scan" && cat -- "$WORK/scan.list" | bash "$SCANNER") > "$WORK/pw.out" 2> "$WORK/pw.err" || pw_rc=$?
case "$pw_rc" in
  0) : > "$WORK/pw.out" ;;
  1) : ;;
  *) fail "audit-secret-redaction-scan.sh exited $pw_rc: $(head -c 300 "$WORK/pw.err")" ;;
esac
py parsepw "$WORK/scan.list" "$WORK/pw.out" > "$WORK/other.hits"
py credscan "$WORK/scan" "$WORK/scan.list" > "$WORK/cred.hits"
NSCANNED="$(grep -c '' "$WORK/scan.list" || true)"

if [[ -s "$WORK/cred.hits" ]]; then
  sed 's/^/record-branch: credential-shaped hit: /' "$WORK/cred.hits" >&2
  refuse "$(grep -c '' "$WORK/cred.hits") credential-shaped hit(s) in scan_tree=$SCAN_TREE are not bypassable (--accept-scan does not apply); remove or redact them in the working tree and rebuild"
fi
if [[ -n "$ACCEPT" && "$ACCEPT" != "$SCAN_TREE" ]]; then
  refuse "--accept-scan names tree $ACCEPT but this build's staged tree is scan_tree=$SCAN_TREE; review the hits of this tree and accept it by that sha"
fi
: > "$WORK/accepted"
if [[ -s "$WORK/other.hits" ]]; then
  if [[ -z "$ACCEPT" ]]; then
    sed 's/^/record-branch: scan hit: /' "$WORK/other.hits" >&2
    refuse "$(grep -c '' "$WORK/other.hits") non-credential scan hit(s) in scan_tree=$SCAN_TREE; review them, then re-run with --accept-scan $SCAN_TREE"
  fi
  cp "$WORK/other.hits" "$WORK/accepted"
fi

# --- 5. manifest into the tree, final-tree check -----------------------------
py manifest "$WORK/collect.json" "$CYCLE_ID" "$HEAD_SHA" "$PREV_SHA" "$STAGE" "$SCAN_TREE" "$WORK/accepted" > "$WORK/manifest.json"
MBLOB="$(git hash-object -w -- "$WORK/manifest.json")"
git update-index --add --cacheinfo "100644,$MBLOB,$MANIFEST_PATH"
FINAL_TREE="$(git write-tree)"
py checktree "$FINAL_TREE"

# --- 6. commit-tree and compare-and-swap -------------------------------------
{
  printf 'record(%s): %s — the cycle tree at %s plus %s recorded files\n\n' "$CYCLE_ID" "$STAGE" "${HEAD_SHA:0:12}" "$NFILES"
  printf 'Built by .claude/scripts/record-branch.sh (temporary index; parents: prev %s, head %s).\n\n' "$PREV_SHA" "$HEAD_SHA"
  jq -r '"paths:", (.paths[] | "- " + .), "results_roots:", (.results_roots[] | "- " + .), "lite_tree: " + (.lite_tree // "none")' "$WORK/collect.json"
  printf 'manifest: %s\n' "$MANIFEST_PATH"
  printf 'scan_tree: %s (%s differing paths scanned)\n' "$SCAN_TREE" "$NSCANNED"
  if [[ -s "$WORK/accepted" ]]; then
    sed -E 's/^(.*):([0-9]+):([a-z-]+)$/accepted_scan: \1:\2 \3/' "$WORK/accepted"
  else
    printf 'accepted_scan: none\n'
  fi
} > "$WORK/message"
NEW="$(git commit-tree "$FINAL_TREE" -p "$PREV_SHA" -p "$HEAD_SHA" -F "$WORK/message")" || fail "commit-tree failed"
unset GIT_INDEX_FILE
git update-ref -m "record-branch: $STAGE" "$REF" "$NEW" "$EXPECTED" 2> "$WORK/cas.err" \
  || refuse "$BRANCH moved during the build (expected ${CUR:-absent}); compare-and-swap refused, nothing written: $(head -c 200 "$WORK/cas.err")"

echo "record-branch: $BRANCH = $NEW ($NFILES files added over $HEAD_SHA; scan_tree $SCAN_TREE, $(grep -c '' "$WORK/accepted" || true) accepted hit(s))"
echo "record-branch: push with: .claude/scripts/run-mode-ice.sh push origin $BRANCH"
