#!/usr/bin/env bash
# =============================================================================
# seed-corpus-from-external.sh — build a review-recall fixture from a public
# GitHub pull request and a later fix (cycle-133 Sprint 3 Task 3.3; PRD FR-12;
# SDD C-12, D-3.3 DEC-0851, §5.4)
#
# Usage:
#   seed-corpus-from-external.sh <repo-url> <pr> --fix <sha>|<first>..<last>
#                                [--incident REF] [--licence SPDX] [--commit-trees] [--private-source]
#                                [--paths 'glob,!glob'] [--dry-run] [--out <corpus>/pr-NN]
#                                [--max-files N] [--max-bytes N[K|M|G]] [--max-fix-diff-bytes N[K|M|G]]
#   seed-corpus-from-external.sh --check [<corpus dir>]
#   common: [--corpus <evals/fixtures/review-prs>] [--tasks-dir <evals/tasks>]
#
# What the fixture is (the record seeder's layout, lib/corpus-seed.sh):
#   head/     the PR head — the reviewed, pre-fix tree — restricted to the files the PR changed
#   base/     the same files at the PR's merge base (merge-base of the PR base sha and its head),
#             so head.diff is the PR's own diff
#   the fix   one commit, or the inclusive range <first>..<last> squashed; the fix diff is
#             fix^..fix (<first>^..<last>), never head..fix, so commits that landed between the
#             PR and the fix never become fix regions. The PR head (or, for a squash merge, the
#             PR's merge commit) must be an ancestor of (or equal to) fix^.
#   PR.md     the PR title and body only (never the fix, an issue or the incident text)
#   labels/pr-NN.tsv  `# approved-by: pending`, the header and one `fix` row per fix^..fix hunk,
#             carried to head/ line numbers through the head → fix^ diff of its file (a hunk where
#             that file changed between the PR head and fix^, or in a file the PR did not change,
#             is listed in labels/pr-NN.dropped.txt); the defects come from the blind annotation
#
# Order (every refusal happens before anything is written to the corpus):
#   1. the URL: https://github.com/<owner>/<repo> only (no other scheme or host, no query or
#      fragment); credentials are stripped and only the sanitised form is printed or used
#   2. `gh api` reads the repository (licence, language, private), the PR (base and head sha, title,
#      body, dates, merge commit) and binds the PR to the repository; a private repository refuses
#      unless --private-source is given (and --private-source refuses a public one)
#   3. a blobless clone (--filter=blob:none --no-checkout --no-recurse-submodules, hooks off,
#      no global or system git config; with --private-source the one credential helper
#      `gh auth git-credential`, never a prompt) fetches refs/pull/<pr>/head; the head sha must equal the
#      API's, the base sha and every fix commit must resolve, the fix must follow the head and
#      touch at least one file the PR changed (else the PR is not where the defect came from)
#   4. from tree metadata only (GIT_NO_LAZY_FETCH=1 `git ls-tree -r` and the GitHub git/trees API
#      sizes, which must agree with the clone's entries): a symlink, a submodule or any other
#      non-regular entry in the PR's changed files, or an unsafe path, refuses; the blobs to fetch
#      (base, head, the fix files at fix^ and fix, the root licence files) must fit --max-files
#      (default 5000) and --max-bytes (default 200M) — no blob has been fetched yet.
#      The fix diff's blobs (cycle-134 C-7, D-2.4; bd-kdk3l), in phases: (1) the blobless clone and
#      fetches already hold the commits and trees of fix^ and fix (no blob); (2) changed(fix^, fix)
#      over those trees (diff-tree --no-renames: adds and deletes, NUL-safe); (3) both sides' blob ids
#      of every changed path — regular files and symlinks, every object the diff reads — join the want
#      set, deduplicated against the PR's blobs and charged once against --max-files / --max-bytes;
#      when they do not fit: `fix diff needs N blob(s) outside the fetch bounds: <paths>` (exit 2);
#      (4) the one bounded fetch of step 5; (5) the diffs, after the fetch and still under
#      GIT_NO_LAZY_FETCH=1 — a diff that reads an object outside the fetched set refuses (exit 2),
#      never a partial diff. A failure in (1)–(4) (tree enumeration, the fetch: exit 1 naming the
#      paths) stops the run before (5) and before any write
#   5. the blobs are fetched in one batch (noop negotiation; every other git call runs with
#      GIT_NO_LAZY_FETCH=1, so nothing outside the checked set is fetched implicitly); `git archive`
#      (no hooks, nothing executed) of a tree built in a temporary index from exactly the checked
#      entries materialises base/ and head/ into a temporary tree — a tree-ish that is not a commit
#      gets no export-subst, and every tar member must be a regular file of the expected set whose
#      git blob id matches its entry (nothing altered, nothing hidden); binary and lock files are
#      left out
#   6. the fix diff must fit --max-fix-diff-bytes (default 4M)
#   7. leakage: any added or removed fix-diff line of at least 20 non-whitespace characters
#      (whitespace-normalised; blank, brace-only and import lines excluded) that occurs in the
#      whitespace-normalised PR.md refuses, naming the lines
#   8. the C-4 scanner (.claude/scripts/lib/secret-classes.sh: the eight credential classes and the
#      audit-key-password-assignment class) over the temporary tree: any hit refuses
#   9. licence: the GitHub licence API's SPDX id; a missing or unidentified licence refuses; a
#      root package.json / pyproject.toml / Cargo.toml declaring another licence is a conflict and
#      refuses (compared by licence family: "Apache License 2.0" is Apache-2.0, "GPL-2.0-only" is
#      not MIT); --licence must equal the API's id (it cannot override contrary evidence); an id
#      outside the allowlist (MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC) refuses;
#      --commit-trees needs at least one root LICENSE/LICENCE/COPYING/NOTICE file.
#      --private-source (the operator's own private repository, e.g. a fleet mount; cycle-135
#      instrument repair, Task B): when the licence API identifies no licence, --licence must name the
#      operator's rights assertion as an SPDX LicenseRef (`LicenseRef-<id>`); that id is recorded as the
#      licence, the allowlist, the declared-licence conflict rule and the root licence-file requirement
#      do not apply to it (a root package.json/pyproject/Cargo declaration is logged, not judged), and
#      the attribution row carries `-` for licence_files. An identified licence follows the public rules.
#      fixture.yaml records `visibility: private` and `exposure.retrieval: private-repository` (the head
#      was never retrievable; the record's contamination note is unchanged). The trees are the owner's
#      private code: --check names every private-source fixture so a corpus that is published is
#      published knowingly.
#
# Writes:
#   --commit-trees  <corpus>/pr-NN/{fixture.yaml, head.diff, PR.md, REVIEW-INSTRUCTIONS.md,
#                   AUDIT-INSTRUCTIONS.md, base/…, head/…, upstream/<LICENSE|NOTICE…>},
#                   labels/pr-NN.{tsv,dropped.txt}, manifests/pr-NN.json (no defect until the
#                   annotation), external/pr-NN.json (provenance: every file's blob id and sha256),
#                   THIRD-PARTY.tsv (the attribution row), the two recall tasks, the corpus.tsv
#                   row (kind external), SHA256SUMS
#   default         no third-party bytes: <corpus>/pr-NN/{fixture.yaml, PR.md, the instructions},
#                   external/pr-NN.json (the fetch manifest: source, commits and every file's
#                   blob id and sha256), the corpus.tsv row (kind external-fetch), SHA256SUMS
#   --dry-run       nothing in the corpus: the full --commit-trees layout in a new temporary corpus
#                   (its own SHA256SUMS) plus DRY-RUN-REPORT.txt there; the path is printed
#   --check [DIR]   writes nothing: DIR (default --corpus) matches its SHA256SUMS; every
#                   external/pr-NN.json fixture has its fixture.yaml (kind external, source, pr,
#                   head, exposure), PR.md, no symlink, every recorded file with its sha256 (the
#                   committed ones), and passes the C-4 scanner; the OK line names the private-source
#                   fixtures (fixture.yaml `visibility: private`), when there are any
#
# fixture.yaml provenance: source_url (sanitised), pr, pr_url, pr_created, pr_merged, base_commit
# (the merge base), pr_base_sha, head_commit, merge_commit, fix_commit, fix_first, fix_parent,
# fix_committed, fix_after_cutoff (against the lib's MODEL_AVAILABILITY table), incident, licence,
# visibility (public | private), trees (committed | fetch-at-run-time), then the lib's exposure block
# for the head commit (retrieval public-repository, or private-repository under --private-source).
#
# --incident REF: an https:// URL (credentials, query and fragment stripped) or an identifier
# ([A-Za-z0-9#._:/-], at most 120 characters); recorded, never fetched.
#
# --paths 'glob,!glob' (cycle-135 instrument repair, Task B; the record seeder's grammar): scopes the
# fixture to part of the PR's changed files — a comma list of fnmatch globs (`*` crosses `/`), an entry
# starting with `!` excludes; a changed path is in scope when it matches an include (or there is none)
# and no exclude. A fleet PR carries the mount's state files (grimoires/, .beads/, .run/) beside its
# code; `--paths '!grimoires/*,!.beads/*,!.run/*'` leaves them out of head/, base/, head.diff and the
# fix regions (listed in labels/pr-NN.dropped.txt as outside the scope). The fix must touch an in-scope
# file. fixture.yaml records the scope as `scope_paths`; a scope that leaves no file refuses (exit 2).
#
# Test seam (bats only): with LOA_SEED_EXTERNAL_TEST_MODE=1 and BATS_TEST_FILENAME set,
# LOA_SEED_EXTERNAL_CLONE_FROM names a local repository cloned instead of the URL (the URL is
# still validated); `gh` is whatever is first on PATH.
#
# Exit (SDD §5.4): 0 seeded, dry-run done or check passed · 1 a step failed (git, gh, a check
# difference) · 2 refusal before any write (usage, URL, binding, limits, symlink, submodule,
# non-regular entry, leakage, secret, licence). Refusals print one stderr line naming the repair.
# Tested by evals/tests/seed-corpus-from-external.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# the shared seeding library and the C-4 secret classes;
# eval.yml trust boundary: literal in-tree paths, no variable on the source line
pushd "$SCRIPT_DIR" >/dev/null
source ./lib/corpus-seed.sh
source ../../.claude/scripts/lib/secret-classes.sh
popd >/dev/null
declare -F secret_classes_scan >/dev/null || { echo "seed-corpus-external: FAILED: lib/secret-classes.sh did not load" >&2; exit 1; }

IFS= read -r -d '' SEED_EXTERNAL_PY <<'PY' || true
import argparse, fnmatch, hashlib, io, json, os, re, shutil, subprocess, sys, tarfile, tempfile, urllib.parse

HARNESS_ROOT = sys.argv[1]
argv = sys.argv[2:]
SEED_TAG = "seed-corpus-external"
SECRET_LIB = os.path.join(HARNESS_ROOT, ".claude", "scripts", "lib", "secret-classes.sh")
ALLOWLIST = ("MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC")
LICENCE_FILE_RX = re.compile(r"^(?:LICEN[CS]E|COPYING|NOTICE)(?:[._-][A-Za-z0-9._-]+)?$", re.I)
LOCK_RX = re.compile(r"(^|/)(?:package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|[^/]*\.lock)$")
REGULAR_MODES = ("100644", "100755")

def refuse(msg):
    fail(msg, 2)

def size_arg(s, name):
    m = re.fullmatch(r"([1-9][0-9]*)([KMG]?)", s or "")
    if not m:
        refuse(f"{name} must be a positive integer with an optional K, M or G suffix")
    return int(m.group(1)) * {"": 1, "K": 1 << 10, "M": 1 << 20, "G": 1 << 30}[m.group(2)]

ap = argparse.ArgumentParser(prog="seed-corpus-from-external.sh", add_help=True)
ap.add_argument("repo_url", nargs="?"); ap.add_argument("pr", nargs="?")
ap.add_argument("--fix"); ap.add_argument("--incident"); ap.add_argument("--licence")
ap.add_argument("--commit-trees", action="store_true"); ap.add_argument("--dry-run", action="store_true")
ap.add_argument("--private-source", action="store_true"); ap.add_argument("--paths")
ap.add_argument("--check", nargs="?", const="", default=None, metavar="DIR")
ap.add_argument("--out")
ap.add_argument("--max-files", default="5000"); ap.add_argument("--max-bytes", default="200M")
ap.add_argument("--max-fix-diff-bytes", default="4M")
ap.add_argument("--corpus", default=os.path.join(HARNESS_ROOT, "evals", "fixtures", "review-prs"))
ap.add_argument("--tasks-dir", default=os.path.join(HARNESS_ROOT, "evals", "tasks"))
try:
    args = ap.parse_args(argv)
except SystemExit as e:
    sys.exit(2 if e.code else 0)

CORPUS = os.path.abspath(args.corpus)
REPO = None   # the clone (lib git()/rev()/show() and the exposure block read it)
NO_SECRETS = os.path.join(HARNESS_ROOT, "evals", "graders", "no-secrets.sh")
LABELS_DIR = os.path.join(CORPUS, "labels")
MANIFESTS_DIR = os.path.join(CORPUS, "manifests")

def set_corpus(c):
    global CORPUS, LABELS_DIR, MANIFESTS_DIR
    CORPUS = c
    LABELS_DIR, MANIFESTS_DIR = os.path.join(c, "labels"), os.path.join(c, "manifests")

def log(msg):
    print(f"{SEED_TAG}: {msg}", file=sys.stderr)

def blob_id(data):
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()

def secret_scan(d, paths):
    """the C-4 scanner over the listed paths under d: [path:line:class, …]"""
    with tempfile.TemporaryDirectory() as td:
        lst = os.path.join(td, "list")
        open(lst, "w", encoding="utf-8", errors="surrogateescape").write("".join(p + "\n" for p in paths))
        p = subprocess.run(["bash", SECRET_LIB, "scan", d, lst, os.path.join(td, "cred"), os.path.join(td, "other")],
                           capture_output=True, text=True, env={**os.environ, "SECRET_CLASSES_TAG": SEED_TAG})
        if p.returncode != 0:
            fail(f"the secret scanner failed: {p.stderr.strip()[:300]}")
        return [l for f in ("cred", "other") for l in open(os.path.join(td, f), encoding="utf-8", errors="replace").read().splitlines() if l]

def files_under(d):
    out = []
    for root, dirs, files in os.walk(d):
        for n in dirs + files:
            p = os.path.join(root, n)
            if os.path.islink(p):
                out.append((os.path.relpath(p, d), "symlink"))
            elif n in files:
                out.append((os.path.relpath(p, d), "file"))
    return sorted(out)

# ------------------------------------------------------------------- --check
def check_external(corpus):
    set_corpus(os.path.abspath(corpus))
    if not os.path.isfile(os.path.join(CORPUS, "SHA256SUMS")):
        fail(f"{CORPUS}: no SHA256SUMS (not a corpus directory)")
    check()   # the lib's SHA256SUMS check (exit 1 on a difference)
    ext = os.path.join(CORPUS, "external")
    names = sorted(n for n in os.listdir(ext) if re.fullmatch(r"pr-[0-9]{2}\.json", n)) if os.path.isdir(ext) else []
    bad, private = [], []
    for n in names:
        fx = n[:-5]
        try:
            prov = json.load(open(os.path.join(ext, n), encoding="utf-8"))
        except ValueError as e:
            bad.append(f"{fx}: external/{n} does not parse ({e})"); continue
        fdir = os.path.join(CORPUS, fx)
        fy = os.path.join(fdir, "fixture.yaml")
        if not os.path.isfile(fy):
            bad.append(f"{fx}: no fixture.yaml"); continue
        y = open(fy, encoding="utf-8").read()
        for key in ("kind: external", "source_url: ", "pr: ", "head_commit: ", "exposure:", "trees: "):
            if ("\n" + key) not in ("\n" + y):
                bad.append(f"{fx}: fixture.yaml lacks `{key.strip()}`")
        if not os.path.isfile(os.path.join(fdir, "PR.md")):
            bad.append(f"{fx}: no PR.md")
        listing = files_under(fdir)
        bad += [f"{fx}: symlink {p}" for p, k in listing if k == "symlink"]
        committed = prov.get("trees") == "committed"
        for side in ("base", "head"):
            for e in prov.get("files", {}).get(side, []):
                p = os.path.join(fdir, side, e["path"])
                if committed and not os.path.isfile(p):
                    bad.append(f"{fx}: {side}/{e['path']} missing")
                elif committed and sha(p) != e["sha256"]:
                    bad.append(f"{fx}: {side}/{e['path']} sha256 differs from external/{n}")
                elif not committed and os.path.exists(p):
                    bad.append(f"{fx}: {side}/{e['path']} is present in a fetch-at-run-time fixture")
        hits = secret_scan(fdir, [p for p, k in listing if k == "file"])
        bad += [f"{fx}: secret scan hit {h}" for h in hits]
        if "\nvisibility: private\n" in "\n" + y:
            private.append(fx)
    if bad:
        fail("check failed: " + "; ".join(bad[:20]))
    print(f"external OK: {len(names)} external fixture(s) in {CORPUS}"
          + (f"; {len(private)} private-source ({', '.join(private)}): their trees are the owner's private code, "
             "publish the corpus only knowingly" if private else ""))

if args.check is not None:
    if args.repo_url or args.pr or args.fix or args.dry_run or args.commit_trees or args.private_source:
        refuse("--check takes only an optional corpus directory (see --help)")
    check_external(args.check or CORPUS)
    sys.exit(0)

# ------------------------------------------------------------------- inputs
if not args.repo_url or not args.pr:
    refuse("usage: seed-corpus-from-external.sh <repo-url> <pr> --fix <sha>|<first>..<last> [...] (see --help)")

def sanitise_url(u):
    """(https://github.com/<owner>/<repo>, owner, repo, had_credentials) or a refusal"""
    if any(c in u for c in "\x00\r\n\t "):
        refuse("the repository URL holds whitespace or a control character")
    p = urllib.parse.urlsplit(u)
    had = bool(p.username or p.password)
    if p.scheme != "https":
        refuse("only https:// repository URLs are accepted (got scheme %r)" % (p.scheme or "none"))
    if (p.hostname or "").lower() != "github.com" or p.port not in (None, 443):
        refuse("only https://github.com/<owner>/<repo> is accepted (the GitHub API is the metadata source)")
    if p.query or p.fragment:
        refuse("the repository URL must not carry a query or a fragment")
    path = p.path.strip("/")
    path = path[:-4] if path.endswith(".git") else path
    m = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9_.-]{0,99})/([A-Za-z0-9_.][A-Za-z0-9_.-]{0,99})", path)
    if not m or m.group(2) in (".", ".."):
        refuse("the repository URL must be https://github.com/<owner>/<repo>")
    return f"https://github.com/{m.group(1)}/{m.group(2)}", m.group(1), m.group(2), had

SOURCE, OWNER, NAME, HAD_CREDS = sanitise_url(args.repo_url)
log(f"source {SOURCE}" + (" (credentials stripped from the given URL)" if HAD_CREDS else ""))
if not re.fullmatch(r"[1-9][0-9]{0,6}", args.pr):
    refuse("<pr> must be a pull request number")
PR = int(args.pr)
fm = re.fullmatch(r"([0-9a-f]{7,40})(?:\.\.([0-9a-f]{7,40}))?", args.fix or "")
if not fm:
    refuse("--fix needs a commit sha or an inclusive range <first>..<last> (7-40 lowercase hex)")
FIX_FIRST_R, FIX_LAST_R = fm.group(1), fm.group(2) or fm.group(1)
if not re.fullmatch(r"[1-9][0-9]*", args.max_files):
    refuse("--max-files must be a positive integer")
MAX_FILES = int(args.max_files)
MAX_BYTES = size_arg(args.max_bytes, "--max-bytes")
MAX_FIX_DIFF = size_arg(args.max_fix_diff_bytes, "--max-fix-diff-bytes")
def sanitise_incident(r):
    if r is None:
        return None
    if r.startswith("https://"):
        p = urllib.parse.urlsplit(r)
        if not p.hostname or any(c in r for c in "\x00\r\n\t "):
            refuse("--incident must be an https:// URL or an identifier")
        return urllib.parse.urlunsplit(("https", p.hostname + (f":{p.port}" if p.port else ""), p.path, "", ""))
    if not re.fullmatch(r"[A-Za-z0-9#._:/-]{1,120}", r):
        refuse("--incident must be an https:// URL or an identifier ([A-Za-z0-9#._:/-], at most 120 characters)")
    return r
INCIDENT = sanitise_incident(args.incident)
scope_raw = (args.paths or "").strip()
if "\n" in scope_raw or '"' in scope_raw or "\\" in scope_raw:
    refuse("--paths: a comma list of globs (no quote, backslash or newline)")
scope_inc = [g for g in scope_raw.split(",") if g and not g.startswith("!")]
scope_exc = [g[1:] for g in scope_raw.split(",") if g.startswith("!") and len(g) > 1]
def in_scope(p):
    return ((not scope_inc or any(fnmatch.fnmatchcase(p, g) for g in scope_inc))
            and not any(fnmatch.fnmatchcase(p, g) for g in scope_exc))
if args.licence is not None and not re.fullmatch(r"[A-Za-z0-9.+-]{1,64}", args.licence):
    refuse("--licence must be an SPDX identifier")
fx = os.path.basename(args.out.rstrip("/")) if args.out else ("pr-99" if args.dry_run else None)
if not fx:
    refuse("--out <corpus>/pr-NN is required (except with --dry-run)")
if not FX_RX.match(fx):
    refuse(f"fixture id must be pr-NN, got {fx}")
if args.out and not args.dry_run and os.path.abspath(os.path.dirname(args.out.rstrip("/"))) != CORPUS:
    refuse(f"--out must be a directory directly under {CORPUS}")
fy_existing = os.path.join(CORPUS, fx, "fixture.yaml")
if not args.dry_run and os.path.isfile(fy_existing) and "\nkind: external" not in "\n" + open(fy_existing, encoding="utf-8").read():
    refuse(f"{fx} exists and is not an external fixture; choose another --out")

# ---------------------------------------------------------------- GitHub API
def gh_json(path):
    try:
        p = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    except OSError:
        fail("gh is not installed (the GitHub API is the metadata source)")
    if p.returncode != 0:
        if "404" in (p.stderr + p.stdout) or "Not Found" in (p.stderr + p.stdout):
            return None
        fail(f"gh api {path} failed: {p.stderr.strip()[:300]}")
    try:
        return json.loads(p.stdout)
    except ValueError:
        fail(f"gh api {path} returned no JSON")

REPO_META = gh_json(f"repos/{OWNER}/{NAME}")
if not isinstance(REPO_META, dict):
    refuse(f"{SOURCE} is not a repository the GitHub API knows")
PRIVATE = REPO_META.get("private") is True
if PRIVATE and not args.private_source:
    refuse(f"{SOURCE} is private; only public repositories are seeded (--private-source for a private repository the operator controls)")
if args.private_source and not PRIVATE:
    refuse(f"{SOURCE} is public; --private-source is only for a private repository (drop the flag)")
if PRIVATE:
    log("private source: the operator's repository; the clone authenticates through `gh auth git-credential`")
PR_META = gh_json(f"repos/{OWNER}/{NAME}/pulls/{PR}")
if not isinstance(PR_META, dict):
    refuse(f"{SOURCE} has no pull request #{PR}")
def sha_of(d, *keys):
    for k in keys:
        d = d.get(k) if isinstance(d, dict) else None
    return d if isinstance(d, str) and re.fullmatch(r"[0-9a-f]{40}", d) else None
API_BASE, API_HEAD = sha_of(PR_META, "base", "sha"), sha_of(PR_META, "head", "sha")
MERGE_COMMIT = sha_of(PR_META, "merge_commit_sha") if PR_META.get("merged_at") else None
bound = ((PR_META.get("base") or {}).get("repo") or {}).get("full_name", "")
if not (API_BASE and API_HEAD):
    refuse(f"pull request #{PR}: the API gave no base/head sha")
if bound.lower() != f"{OWNER}/{NAME}".lower():
    refuse(f"pull request #{PR} belongs to {bound or 'an unknown repository'}, not {OWNER}/{NAME}")
def day(ts):
    return ts[:10] if isinstance(ts, str) and re.match(r"^\d{4}-\d{2}-\d{2}", ts) else None
PR_CREATED, PR_MERGED = day(PR_META.get("created_at")), day(PR_META.get("merged_at"))

# ------------------------------------------------------------- blobless clone
WORK = tempfile.mkdtemp(prefix="seed-external.")
def cleanup():
    shutil.rmtree(WORK, ignore_errors=True)
import atexit
atexit.register(cleanup)
CLONE = os.path.join(WORK, "src")
GIT_ENV = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
           "GIT_NO_LAZY_FETCH": "1", "GIT_ASKPASS": "/bin/false"}
GIT_SAFE = ["-c", "core.hooksPath=" + os.devnull, "-c", "core.fsmonitor=false", "-c", "transfer.fsckObjects=true",
            "-c", "protocol.allow=never", "-c", "protocol.https.allow=always", "-c", "credential.helper="]
if PRIVATE:
    # the empty helper above clears any configured helper; the gh helper is then the only one (no prompt: GIT_ASKPASS
    # is /bin/false and GIT_TERMINAL_PROMPT=0), so a missing gh login fails the clone instead of asking
    GIT_SAFE += ["-c", "credential.helper=!gh auth git-credential"]
clone_from = SOURCE
if os.environ.get("LOA_SEED_EXTERNAL_TEST_MODE") == "1" and os.environ.get("BATS_TEST_FILENAME") and os.environ.get("LOA_SEED_EXTERNAL_CLONE_FROM"):
    clone_from = "file://" + os.path.abspath(os.environ["LOA_SEED_EXTERNAL_CLONE_FROM"])
    GIT_SAFE += ["-c", "protocol.file.allow=always"]

def g(*a, env=None, check=True, data=None, binary=False):
    p = subprocess.run(["git", *GIT_SAFE, "-C", CLONE, *a], capture_output=True, input=data,
                       text=not binary, env=env or GIT_ENV)
    if check and p.returncode != 0:
        err = p.stderr if not binary else p.stderr.decode("utf-8", "replace")
        fail(f"git {' '.join(a[:2])} failed: {err.strip()[:300]}")
    return p

log("blobless clone (no checkout, no submodules, hooks off)")
p = subprocess.run(["git", *GIT_SAFE, "clone", "--quiet", "--filter=blob:none", "--no-checkout", "--no-recurse-submodules",
                    "--", clone_from, CLONE], capture_output=True, text=True, env=GIT_ENV)
if p.returncode != 0:
    fail(f"git clone {SOURCE} failed: {p.stderr.strip()[:300]}")
REPO = CLONE
g("fetch", "--quiet", "--no-tags", "origin", f"+refs/pull/{PR}/head:refs/remotes/origin/pr-{PR}")
pr_head = g("rev-parse", "--verify", "--quiet", f"refs/remotes/origin/pr-{PR}^{{commit}}", check=False).stdout.strip()
if pr_head != API_HEAD:
    refuse(f"refs/pull/{PR}/head in the clone is {pr_head[:12] or 'absent'}, the API says {API_HEAD[:12]}; the PR moved — retry")

def have(c):
    return g("cat-file", "-e", f"{c}^{{commit}}", check=False).returncode == 0
def resolve(c, what):
    if not have(c):
        g("fetch", "--quiet", "--no-tags", "origin", c, check=False)
    r = g("rev-parse", "--verify", "--quiet", f"{c}^{{commit}}", check=False).stdout.strip()
    if not r:
        refuse(f"{what} {c} is not a commit of {SOURCE}")
    return r
def is_anc(a, b):
    return g("merge-base", "--is-ancestor", a, b, check=False).returncode == 0

HEAD = API_HEAD
PR_BASE = resolve(API_BASE, "the PR base")
MB = g("merge-base", PR_BASE, HEAD, check=False).stdout.strip()
if not MB:
    refuse(f"pull request #{PR}: its base {PR_BASE[:12]} and head {HEAD[:12]} share no history")
FIX_FIRST, FIX_LAST = resolve(FIX_FIRST_R, "--fix"), resolve(FIX_LAST_R, "--fix")
if FIX_FIRST != FIX_LAST and not is_anc(FIX_FIRST, FIX_LAST):
    refuse(f"--fix {args.fix}: {FIX_FIRST[:12]} is not an ancestor of {FIX_LAST[:12]}")
FIX_PARENT = g("rev-parse", "--verify", "--quiet", f"{FIX_FIRST}^1", check=False).stdout.strip()
if not FIX_PARENT:
    refuse(f"--fix {FIX_FIRST[:12]} has no parent")
if MERGE_COMMIT and not have(MERGE_COMMIT):
    MERGE_COMMIT = resolve(MERGE_COMMIT, "the PR merge commit")
if not (is_anc(HEAD, FIX_PARENT) or (MERGE_COMMIT and is_anc(MERGE_COMMIT, FIX_PARENT))):
    refuse(f"the fix does not follow the PR: neither the head {HEAD[:12]} nor the merge commit "
           f"{(MERGE_COMMIT or '-')[:12]} is an ancestor of fix^ {FIX_PARENT[:12]}")

# ------------------------------------------------- tree metadata (no blob fetched)
def ls_tree(commit):
    """{path: (mode, type, oid)} of the whole tree, from tree objects only"""
    out = {}
    for rec in g("ls-tree", "-r", "-z", "--full-tree", commit, binary=True).stdout.split(b"\0"):
        if rec:
            meta, path = rec.split(b"\t", 1)
            mode, typ, oid = meta.decode().split()
            out[path.decode("utf-8", "surrogateescape")] = (mode, typ, oid)
    return out

def changed(a, b):
    """[(status, path)] between two commits, no rename detection (trees only)"""
    raw = g("diff-tree", "-r", "-z", "--no-renames", "--name-status", a, b, binary=True).stdout.split(b"\0")
    out = []
    for i in range(0, len(raw) - 1, 2):
        out.append((raw[i].decode()[:1], raw[i + 1].decode("utf-8", "surrogateescape")))
    return out

TREE_SIZES = {}
def api_sizes(commit):
    """{path: (mode, type, oid, size)} from the GitHub git/trees API for commit's tree; bound to the clone"""
    tree = g("rev-parse", f"{commit}^{{tree}}").stdout.strip()
    if tree in TREE_SIZES:
        return TREE_SIZES[tree]
    d = gh_json(f"repos/{OWNER}/{NAME}/git/trees/{tree}?recursive=1")
    if not isinstance(d, dict) or not isinstance(d.get("tree"), list):
        fail(f"gh api git/trees/{tree[:12]} gave no tree listing")
    if d.get("truncated"):
        refuse(f"the GitHub tree listing of {commit[:12]} is truncated (the repository exceeds the API's 100000-entry bound); "
               "it is outside the harness size bounds")
    out = {e.get("path"): (e.get("mode"), e.get("type"), e.get("sha"), e.get("size")) for e in d["tree"] if isinstance(e, dict)}
    TREE_SIZES[tree] = out
    return out

def unsafe_path(p):
    return (not p or p.startswith("/") or "\\" in p or "\x00" in p or any(x in ("", ".", "..") for x in p.split("/"))
            or re.search(r"[\x00-\x1f\x7f]", p) is not None or p.split("/")[0] == ".git" or "/.git/" in "/" + p + "/")

PR_CHANGES_ALL = changed(MB, HEAD)
if not PR_CHANGES_ALL:
    refuse(f"pull request #{PR} changes no file between {MB[:12]} and {HEAD[:12]}")
skipped = []
out_of_scope = sorted(p for _s, p in PR_CHANGES_ALL if not in_scope(p))
skipped += [f"{p}: outside the --paths scope" for p in out_of_scope]
PR_CHANGES = [(st, p) for st, p in PR_CHANGES_ALL if in_scope(p)]
if not PR_CHANGES:
    refuse(f"pull request #{PR}: no file of its {len(PR_CHANGES_ALL)} changed file(s) is inside --paths {scope_raw!r}")
trees = {"base": ls_tree(MB), "head": ls_tree(HEAD)}
want = {"base": [], "head": []}   # [(path, oid)]
for st, path in PR_CHANGES:
    if unsafe_path(path):
        refuse(f"unsafe path in the PR: {path!r}")
    if LOCK_RX.search(path):
        skipped.append(f"{path}: lock file left out"); continue
    for side in ("base", "head"):
        e = trees[side].get(path)
        if e is None:
            continue
        mode, typ, oid = e
        if mode == "120000":
            refuse(f"{side} {path} is a symlink; symlinks are refused before extraction")
        if mode == "160000" or typ == "commit":
            refuse(f"{side} {path} is a submodule; submodules are refused before extraction")
        if mode not in REGULAR_MODES or typ != "blob":
            refuse(f"{side} {path} is not a regular file (mode {mode}); refused before extraction")
        want[side].append((path, oid))
if not want["head"] and not want["base"]:
    refuse(f"pull request #{PR}: no regular, non-lock file changed")
FIX_CHANGES = changed(FIX_PARENT, FIX_LAST)
if not FIX_CHANGES:
    refuse(f"--fix {args.fix} changes no file")
if not {p for _s, p in FIX_CHANGES} & {p for _s, p in PR_CHANGES if trees["head"].get(p)}:
    refuse(f"--fix {args.fix} touches no file the PR changed" + (f" inside --paths {scope_raw!r}" if scope_raw else "")
           + "; the PR is not where the fixed defect was introduced")
fix_trees = {"parent": ls_tree(FIX_PARENT), "fix": ls_tree(FIX_LAST)}
fix_want = []
for st, path in FIX_CHANGES:
    if unsafe_path(path):
        refuse(f"unsafe path in the fix: {path!r}")
    for side in ("parent", "fix"):
        e = fix_trees[side].get(path)
        # every blob the fix diff reads (C-7): regular files and symlinks (a symlink's blob is its target text; it is
        # diffed, never materialised); a submodule entry is a commit id the diff prints without reading an object
        if e and e[1] == "blob":
            fix_want.append((side, path, e[2]))
lic_want = [(p, e[2]) for p, e in trees["head"].items() if "/" not in p and LICENCE_FILE_RX.match(p) and e[0] in REGULAR_MODES]
manifest_want = [(p, trees["head"][p][2]) for p in ("package.json", "pyproject.toml", "Cargo.toml")
                 if p in trees["head"] and trees["head"][p][0] in REGULAR_MODES]

# sizes from the API, which must agree with the clone's own entries
sizes = {}
for commit, side_entries in ((MB, want["base"]), (HEAD, want["head"] + lic_want + manifest_want)):
    meta = api_sizes(commit)
    for path, oid in side_entries:
        m = meta.get(path)
        if not m or m[2] != oid or not isinstance(m[3], int):
            fail(f"the GitHub tree listing of {commit[:12]} disagrees with the clone at {path!r}")
        sizes[oid] = m[3]
oid_paths = {}   # oid → the paths it stands for (refusal and fetch-failure messages)
for side_entries in (want["base"], want["head"], lic_want, manifest_want):
    for path, oid in side_entries:
        oid_paths.setdefault(oid, set()).add(path)
n_blobs, n_bytes = len(sizes), sum(sizes.values())
if n_blobs > MAX_FILES:
    refuse(f"{n_blobs} files to fetch exceed --max-files {MAX_FILES} (checked from tree metadata; nothing fetched)")
if n_bytes > MAX_BYTES:
    refuse(f"{n_bytes} bytes to fetch exceed --max-bytes {MAX_BYTES} (checked from tree metadata; nothing fetched)")
# the fix diff's blobs (both sides of changed(FIX_PARENT, FIX_LAST)) join the same set, deduplicated against the PR's
# blobs and charged once against the same bounds; outside the bounds the run refuses naming them (C-7, D-2.4)
fix_extra = {}
for side, path, oid in fix_want:
    meta = api_sizes(FIX_PARENT if side == "parent" else FIX_LAST)
    m = meta.get(path)
    if not m or m[2] != oid or not isinstance(m[3], int):
        fail(f"the GitHub tree listing of the fix disagrees with the clone at {path!r}")
    oid_paths.setdefault(oid, set()).add(path)
    if oid not in sizes:
        fix_extra[oid] = m[3]
if n_blobs + len(fix_extra) > MAX_FILES or n_bytes + sum(fix_extra.values()) > MAX_BYTES:
    named = sorted({p for o in fix_extra for p in oid_paths[o]})
    refuse(f"fix diff needs {len(fix_extra)} blob(s) outside the fetch bounds: {', '.join(named[:20])}"
           f"{f' (+{len(named) - 20} more)' if len(named) > 20 else ''} (the PR's set is {n_blobs} file(s), {n_bytes} byte(s); "
           f"--max-files {MAX_FILES}, --max-bytes {MAX_BYTES}; checked from tree metadata; nothing fetched)")
sizes.update(fix_extra)
n_blobs, n_bytes = len(sizes), sum(sizes.values())
log(f"limits ok from tree metadata: {n_blobs} file(s), {n_bytes} byte(s); fetching blobs")

# ------------------------------------------------------- fetch and materialise
missing = [o for o in sorted(sizes) if g("cat-file", "-e", o, check=False).returncode != 0]
if missing:
    # one batch for the checked set, the way git's own promisor fetch asks (noop negotiation: the connectivity
    # check of a have-negotiated fetch rejects bare blob wants); GIT_NO_LAZY_FETCH=1 stays set
    fp = g("-c", "fetch.negotiationAlgorithm=noop", "fetch", "--quiet", "--no-tags", "--no-write-fetch-head", "--recurse-submodules=no",
           "--filter=blob:none", "--stdin", "origin", data="".join(o + "\n" for o in missing), check=False)
    if fp.returncode != 0:
        names = sorted({p for o in missing for p in oid_paths.get(o, {o})})
        fail(f"the bounded fetch of {len(missing)} blob(s) from {SOURCE} failed ({', '.join(names[:20])}"
             f"{' …' if len(names) > 20 else ''}): {fp.stderr.strip()[:300]}; nothing written")
still = [o for o in missing if g("cat-file", "-e", o, check=False).returncode != 0]
if still:
    names = sorted({p for o in still for p in oid_paths.get(o, {o})})
    fail(f"{len(still)} blob(s) did not arrive from {SOURCE}: {', '.join(names[:20])}{' …' if len(names) > 20 else ''}; nothing written")

def archive(commit, entries):
    """{path: bytes} through `git archive` (tar) of a tree holding exactly `entries` (built in a temporary
    index, so archive reads no other blob and, the tree-ish not being a commit, applies no export-subst);
    each member must be a regular file of the set whose git blob id matches its tree entry"""
    exp = dict(entries)
    if not exp:
        return {}
    idx = os.path.join(WORK, "archive.index")
    if os.path.exists(idx):
        os.remove(idx)
    ienv = {**GIT_ENV, "GIT_INDEX_FILE": idx}
    modes = {p: trees["head" if commit == HEAD else "base"].get(p, ("100644",))[0] for p in exp}
    g("update-index", "-z", "--add", "--index-info", env=ienv,
      data="".join(f"{modes.get(p, '100644')} blob {o}\t{p}\0" for p, o in sorted(exp.items())))
    tree = g("write-tree", env=ienv).stdout.strip()
    tar = g("archive", "--format=tar", tree, binary=True).stdout
    got = {}
    with tarfile.open(fileobj=io.BytesIO(tar), mode="r:") as tf:
        for m in tf.getmembers():
            if m.type in (tarfile.XGLTYPE, tarfile.XHDTYPE) or m.isdir():
                continue
            if not m.isreg():
                refuse(f"git archive of {commit[:12]} holds a non-regular member {m.name!r}; refused before extraction")
            if m.name not in exp:
                refuse(f"git archive of {commit[:12]} holds an unexpected member {m.name!r}")
            data = tf.extractfile(m).read()
            if blob_id(data) != exp[m.name]:
                refuse(f"{m.name} from git archive does not match its blob {exp[m.name][:12]} (an export attribute?)")
            got[m.name] = data
    lost = sorted(set(exp) - set(got))
    if lost:
        refuse(f"git archive of {commit[:12]} omitted {', '.join(lost[:5])} (export-ignore?)")
    return got

base_bytes, head_bytes = archive(MB, want["base"]), archive(HEAD, want["head"])
lic_bytes = archive(HEAD, lic_want)
man_bytes = archive(HEAD, manifest_want)
def is_binary(b):
    return b"\0" in b[:8000]
binary = sorted({p for p, b in list(base_bytes.items()) + list(head_bytes.items()) if is_binary(b)})
skipped += [f"{p}: binary file left out" for p in binary]
base_files = sorted((p, b) for p, b in base_bytes.items() if p not in binary)
head_files = sorted((p, b) for p, b in head_bytes.items() if p not in binary)
paths = sorted({p for p, _ in base_files} | {p for p, _ in head_files})
if not head_files and not base_files:
    refuse(f"pull request #{PR}: only binary or lock files changed")
DIFF_OPTS = ["--no-color", "--no-ext-diff", "--no-textconv", "--no-renames"]
diff_text = g("diff", *DIFF_OPTS, MB, HEAD, "--", *[":(literal)" + p for p in paths]).stdout
# after the fetch, still under GIT_NO_LAZY_FETCH=1: a diff that needs an object outside the fetched set is a refusal,
# never a partial diff (C-7)
fp = g("diff", *DIFF_OPTS, "-U0", FIX_PARENT, FIX_LAST, check=False)
if fp.returncode != 0:
    refuse(f"the fix diff {FIX_PARENT[:12]}..{FIX_LAST[:12]} reads an object outside the fetched set "
           f"({fp.stderr.strip().splitlines()[-1][:200] if fp.stderr.strip() else 'git diff exit ' + str(fp.returncode)}); "
           "nothing written — report the fix range")
fix_diff = fp.stdout
if len(fix_diff.encode("utf-8")) > MAX_FIX_DIFF:
    refuse(f"the fix diff is {len(fix_diff.encode('utf-8'))} bytes, over --max-fix-diff-bytes {MAX_FIX_DIFF}")

# ------------------------------------------------------------------- PR.md + leakage
PR_TEXT_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f  ]")
title = clean(str(PR_META.get("title") or f"pull request #{PR}"), 200)
body = PR_TEXT_CTRL.sub("", str(PR_META.get("body") or "").replace("\r\n", "\n").replace("\r", "\n")).strip()
if len(body) > 20000:
    body = body[:19999].rstrip() + "…"
pr_md = f"# {title}\n\n" + (body + "\n" if body else "(no description)\n")
STOP_RX = re.compile(r"^[\s{}()\[\];,.:<>/\\|*#'\"`=+-]*$")
IMPORT_RX = re.compile(r"^\s*(?:import\s|from\s+\S+\s+import\s|#\s*include\b|using\s|use\s|require\s*\(|(?:const|let|var)\s+[\w{}\s,]+=\s*require\s*\(|export\s+\*\s+from\s)")
def substantive(line):
    t = " ".join(line.split())
    return t if len(re.sub(r"\s", "", t)) >= 20 and not STOP_RX.match(t) and not IMPORT_RX.match(t) else None
pr_norm = " ".join(pr_md.split())
leaks, cur = [], None
for l in fix_diff.splitlines():
    if l.startswith("+++ ") or l.startswith("--- "):
        cur = l[6:] if l[4:6] in ("a/", "b/") else cur
        continue
    if l.startswith("diff --git ") or l.startswith("@@") or not l[:1] in ("+", "-"):
        continue
    t = substantive(l[1:])
    if t and t in pr_norm:
        leaks.append(f"{cur}: {l[:1]}{clean(t, 120)}")
if leaks:
    for x in leaks[:20]:
        print(f"{SEED_TAG}: leakage: {x}", file=sys.stderr)
    refuse(f"PR.md carries {len(leaks)} line(s) of the fix diff (listed above); the PR title and body reveal the fix — choose another PR")

# ------------------------------------------------------------- licence
lic_api = gh_json(f"repos/{OWNER}/{NAME}/license")
spdx = (((lic_api or {}).get("license") or {}).get("spdx_id")) if isinstance(lic_api, dict) else None
LICENSE_REF = False   # --private-source with no identified licence: the operator's LicenseRef assertion
if not spdx or spdx in ("NOASSERTION", "OTHER"):
    if not PRIVATE:
        refuse(f"{SOURCE}: the GitHub licence API identifies no licence ({spdx or 'none'}); unlicensed code is not seeded")
    if not (args.licence or "").startswith("LicenseRef-") or len(args.licence) < len("LicenseRef-") + 1:
        refuse(f"{SOURCE}: the GitHub licence API identifies no licence ({spdx or 'none'}); a private source needs "
               "--licence LicenseRef-<id>, the operator's rights assertion, recorded as the licence")
    spdx, LICENSE_REF = args.licence, True
    log(f"licence: none identified; recording the operator's assertion {spdx}")
elif args.licence is not None and args.licence != spdx:
    refuse(f"--licence {args.licence} contradicts the GitHub licence API ({spdx}); the flag cannot override that evidence")
declared = []
for p, b in sorted(man_bytes.items()):
    t = b.decode("utf-8", "replace")
    if p == "package.json":
        try:
            v = json.loads(t).get("license")
        except (ValueError, AttributeError):
            v = None
        if isinstance(v, str):
            declared.append((p, v))
    else:
        m = re.search(r'^\s*license\s*=\s*(?:\{\s*text\s*=\s*)?"([^"]{1,120})"', t, re.M)
        if m:
            declared.append((p, m.group(1)))
FAMILIES = ("agpl", "lgpl", "gpl", "mpl", "epl", "apache", "mit", "bsd", "isc", "unlicense", "cc-by", "cc0", "proprietary")
def families(text):
    """the licence families a declaration names ("Apache License 2.0" → apache; "MIT OR Apache-2.0" → mit, apache)"""
    t, out = text.lower(), set()
    for f in FAMILIES:
        if re.search(r"(?<![a-z])" + re.escape(f) + r"(?![a-z])", t):
            out.add(f)
    return out
api_family = families(spdx)
for p, v in declared:
    named = families(v)
    if LICENSE_REF:
        log(f"licence: {p} declares {clean(v, 60)!r} (logged; the operator's assertion {spdx} stands)")
    elif named and not (named & api_family):
        refuse(f"{p} declares licence {clean(v, 60)!r} but the GitHub licence API says {spdx}; a conflicting declaration refuses")
if spdx not in ALLOWLIST and not LICENSE_REF:
    refuse(f"licence {spdx} is outside the allowlist ({', '.join(ALLOWLIST)}); third-party trees under it are not seeded")
if args.commit_trees and not lic_bytes and not LICENSE_REF:
    refuse(f"{SOURCE} has no root LICENSE/NOTICE file to commit with the trees (--commit-trees needs one)")

# ------------------------------------------------------------- temporary tree + scan
committed = bool(args.commit_trees or args.dry_run)
DRY_ROOT = None
if args.dry_run:
    DRY_ROOT = tempfile.mkdtemp(prefix="seed-external-dry-run.")
    DRY_DONE = []
    atexit.register(lambda: DRY_DONE or shutil.rmtree(DRY_ROOT, ignore_errors=True))   # a refused dry run leaves nothing
    set_corpus(os.path.join(DRY_ROOT, "corpus"))
    os.makedirs(os.path.join(CORPUS, "pr-01"))
    real = os.path.abspath(args.corpus)
    for name in INSTRUCTION_FILES:
        src = os.path.join(real, "pr-01", name)
        if os.path.isfile(src):
            shutil.copyfile(src, os.path.join(CORPUS, "pr-01", name))
        else:
            open(os.path.join(CORPUS, "pr-01", name), "w", encoding="utf-8").write(f"# {name[:-3].title()}\n")
    open(os.path.join(CORPUS, "corpus.tsv"), "w", encoding="utf-8").write(
        "fixture\tkind\tcommit\tfile\tdefect_id\tseverity\tcategory\tmust_match\n")
    tasks_dir = os.path.join(CORPUS, "tasks")
else:
    tasks_dir = args.tasks_dir
if not all(os.path.isfile(os.path.join(CORPUS, "pr-01", n)) for n in INSTRUCTION_FILES):
    fail(f"{CORPUS}/pr-01 lacks the instruction templates ({', '.join(INSTRUCTION_FILES)})")
stage = os.path.join(WORK, "stage")
write_layout(os.path.join(stage, fx), base_files, head_files, diff_text, pr_md)
for name, b in sorted(lic_bytes.items()):
    d = os.path.join(stage, fx, "upstream"); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, name), "wb").write(b)
scan_list = [p for p, k in files_under(os.path.join(stage, fx)) if k == "file"]
hits = secret_scan(os.path.join(stage, fx), scan_list)
if hits:
    for h in hits[:20]:
        print(f"{SEED_TAG}: secret scan hit: {h}", file=sys.stderr)
    refuse(f"{len(hits)} secret scan hit(s) in the materialised trees (listed above, text never printed); the fixture is not seeded")

# ------------------------------------------------------------- fixture records
def git_day(c):
    p = g("log", "-1", "--date=format-local:%Y-%m-%d", "--format=%cd", c, env={**GIT_ENV, "TZ": "UTC"})
    return p.stdout.strip()
FIX_DAY = git_day(FIX_LAST)
cut = MODEL_AVAILABILITY["fable_5_1"]["knowledge_cutoff"]
fix_after = FIX_DAY[:7] > cut
def q(v):
    return "null" if v is None else json.dumps(v)
def file_rows(files):
    return [{"path": p, "blob": blob_id(b), "sha256": hashlib.sha256(b).hexdigest(), "size": len(b)} for p, b in files]
prov = {"schema_version": 1, "fixture": fx, "source_url": SOURCE, "pr": PR, "pr_url": f"{SOURCE}/pull/{PR}",
        "pr_base_sha": PR_BASE, "base_commit": MB, "head_commit": HEAD, "merge_commit": MERGE_COMMIT,
        "fix_first": FIX_FIRST, "fix_commit": FIX_LAST, "fix_parent": FIX_PARENT, "licence": spdx,
        "visibility": "private" if PRIVATE else "public", "trees": "committed" if committed else "fetch-at-run-time",
        "scope_paths": scope_raw or None,
        "files": {"base": file_rows(base_files), "head": file_rows(head_files)},
        "licence_files": file_rows(sorted(lic_bytes.items())), "skipped": skipped}
fixture_yaml = (
    f'name: {fx}\nversion: "1.0.0"\nlanguage: {json.dumps(str(REPO_META.get("language") or "mixed").lower())}\n'
    f'runtime: none\ndependency_strategy: none\n'
    f'description: "external fixture: {OWNER}/{NAME} pull request #{PR} reviewed at its head (pre-fix); labels live in the hidden labels/ and manifests/ dirs"\n'
    f'difficulty: advanced\ndomain: external\ndeprecated: false\nkind: external\n'
    f'source_url: "{SOURCE}"\npr: {PR}\npr_url: "{SOURCE}/pull/{PR}"\npr_created: {q(PR_CREATED)}\npr_merged: {q(PR_MERGED)}\n'
    f'base_commit: "{MB}"\npr_base_sha: "{PR_BASE}"\nhead_commit: "{HEAD}"\nmerge_commit: {q(MERGE_COMMIT)}\n'
    f'fix_commit: "{FIX_LAST}"\nfix_first: "{FIX_FIRST}"\nfix_parent: "{FIX_PARENT}"\nfix_committed: "{FIX_DAY}"\n'
    f'fix_after_cutoff:\n  fable_5_1: {"true" if fix_after else "false"}      # knowledge cutoff {cut}\n'
    f'incident: {q(INCIDENT)}\nlicence: "{spdx}"\nvisibility: {prov["visibility"]}\ntrees: {prov["trees"]}\n'
    + (f'scope_paths: "{scope_raw}"\n' if scope_raw else "") + exposure_block(HEAD, RETRIEVAL_PRIVATE if PRIVATE else RETRIEVAL))

# fix rows: the hunks of fix^..fix, carried to head/ line numbers through the head → fix^ diff of the same file;
# a hunk that falls where the file changed between the PR head and fix^ has no head-side place and is dropped
HUNK_RX = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
def hunks(a, b, path):
    out = []
    for l in g("diff", *DIFF_OPTS, "-U0", a, b, "--", ":(literal)" + path).stdout.splitlines():
        m = HUNK_RX.match(l)
        if m:
            out.append((int(m.group(1)), 1 if m.group(2) is None else int(m.group(2)),
                        int(m.group(3)), 1 if m.group(4) is None else int(m.group(4))))
    return out
def to_head(path):
    """fix^ line → head line (None where head → fix^ changed the line)"""
    hs = hunks(HEAD, FIX_PARENT, path)
    def f(n):
        off = 0
        for a, an, b, bn in hs:
            if bn and b <= n <= b + bn - 1:
                return None
            if (b + bn - 1 if bn else b) < n:
                off += an - bn
        return n + off
    return f
head_map = dict(head_files)
fix_rows, dropped = [], list(skipped)
for st, path in FIX_CHANGES:
    if path not in head_map:
        dropped.append(f"{path}: the fix touches it but " + ("it is outside the --paths scope" if path in out_of_scope
                       else "the PR did not change it") + "; no fix region")
        continue
    lines = head_map[path].decode("utf-8", "replace").splitlines()
    m = to_head(path)
    for a, an, _b, _bn in hunks(FIX_PARENT, FIX_LAST, path):
        lo, hi = (max(a, 1), max(a, 1)) if an == 0 else (a, a + an - 1)
        hlo, hhi = m(lo), m(hi)
        if hlo is None or hhi is None or hhi - hlo != hi - lo or not 1 <= hlo <= max(len(lines), 1):
            dropped.append(f"{path}: fix hunk at fix^ line {lo}-{hi} lies where the file changed between the PR head and fix^; no fix region")
            continue
        hhi = min(hhi, len(lines))
        t = next((lines[i - 1].strip() for i in range(hlo, hhi + 1)
                  if len(lines[i - 1].strip()) >= 10 and "\t" not in lines[i - 1] and unique_line(lines, lines[i - 1].strip()) == i
                  and not has_secret(lines[i - 1])), "-")
        fix_rows.append("\t".join([f"F{len(fix_rows) + 1:03d}", "-", "fix", path, t, "fix", f"fix/{FIX_LAST[:12]}:{hlo}-{hhi}"]))
tsv = ["# approved-by: pending",
       f"# fixture {fx} | external {SOURCE} pull request #{PR} | base {MB[:12]} | head {HEAD[:12]} | fix {FIX_FIRST[:12]}..{FIX_LAST[:12]}",
       "# seeded by evals/harness/seed-corpus-from-external.sh; the defects come from the blind annotation (labels v2), then --approve",
       "\t".join(HEADER), *fix_rows]

# ------------------------------------------------------------- write
fdir = os.path.join(CORPUS, fx)
shutil.rmtree(fdir, ignore_errors=True)
if committed:
    shutil.copytree(os.path.join(stage, fx), fdir, symlinks=True)
else:
    os.makedirs(fdir)
    for name in ("PR.md",) + INSTRUCTION_FILES:
        shutil.copyfile(os.path.join(stage, fx, name), os.path.join(fdir, name))
open(os.path.join(fdir, "fixture.yaml"), "w", encoding="utf-8").write(fixture_yaml)
os.makedirs(os.path.join(CORPUS, "external"), exist_ok=True)
open(os.path.join(CORPUS, "external", f"{fx}.json"), "w", encoding="utf-8").write(json.dumps(prov, indent=2, sort_keys=True) + "\n")
if committed:
    os.makedirs(LABELS_DIR, exist_ok=True)
    open(os.path.join(LABELS_DIR, f"{fx}.tsv"), "w", encoding="utf-8").write("\n".join(tsv) + "\n")
    open(os.path.join(LABELS_DIR, f"{fx}.dropped.txt"), "w", encoding="utf-8").write(
        f"# {fx} external {SOURCE} #{PR}: files and hunks that did not become fix regions\n" + "".join(d + "\n" for d in dropped))
    man = build_manifest(fx)
    write_tasks(fx, f"external fixture {fx} ({OWNER}/{NAME} #{PR}; hidden manifest)", ("cycle-133", "fr-12", None, "external"), tasks_dir)
    attr = os.path.join(CORPUS, "THIRD-PARTY.tsv")
    rows = [l for l in (open(attr, encoding="utf-8").read().splitlines() if os.path.isfile(attr) else []) if l and not l.startswith(fx + "\t")]
    if not rows or not rows[0].startswith("fixture\t"):
        rows.insert(0, "fixture\tsource\tpr\thead\tlicence\tlicence_files")
    rows.append("\t".join([fx, SOURCE, str(PR), HEAD, spdx, ",".join("upstream/" + n for n in sorted(lic_bytes)) or "-"]))
    open(attr, "w", encoding="utf-8").write("\n".join([rows[0]] + sorted(rows[1:])) + "\n")
    corpus_row(fx, "external", HEAD)
else:
    corpus_set(fx, "\t".join([fx, "external-fetch", HEAD[:8], f"external/{fx}.json", "-", "-", "-", "-"]))
n = freeze()
summary = (f"{fx} {OWNER}/{NAME}#{PR}: {len(head_files)} head file(s), {len(base_files)} base file(s), diff {len(diff_text)} B, "
           f"{len(fix_rows)} fix row(s), licence {spdx}{' (private source)' if PRIVATE else ''}, fix {FIX_DAY} "
           f"({'after' if fix_after else 'before'} the {cut} cutoff), "
           f"trees {prov['trees']}, {len(skipped)} skipped; SHA256SUMS {n} files")
if args.dry_run:
    rep = os.path.join(DRY_ROOT, "DRY-RUN-REPORT.txt")
    open(rep, "w", encoding="utf-8").write(
        summary + "\n" + f"source {SOURCE} pr {PR} base {MB} head {HEAD} fix {FIX_FIRST}..{FIX_LAST} parent {FIX_PARENT}\n"
        + f"limits: {n_blobs} file(s), {n_bytes} byte(s) fetched (bounds {MAX_FILES} / {MAX_BYTES}); fix diff {len(fix_diff)} B\n"
        + "".join(f"skipped: {s}\n" for s in skipped) + "".join(f"dropped: {d}\n" for d in dropped))
    DRY_DONE.append(True)
    print(summary)
    print(f"dry run: temporary corpus {CORPUS}, report {rep}; check with: seed-corpus-from-external.sh --check {CORPUS}")
else:
    print(summary)
PY
{ corpus_seed_python; printf '%s\n' "$SEED_EXTERNAL_PY"; } | python3 -I - "$REPO_ROOT" "$@"
