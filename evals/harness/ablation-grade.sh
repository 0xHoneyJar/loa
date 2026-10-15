#!/usr/bin/env bash
# =============================================================================
# ablation-grade.sh — the cycle-130 ablation grader (SDD §3.6, §5.7, D-4.7, D-4.8;
# PRD FR-6 AC-6.1/6.2/6.4; DEC-0401, DEC-0413, DEC-0414, DEC-0420, DEC-0491, DEC-0493)
#
# Grades ONE run directory written by pipeline-run.sh against its task and writes
# grade.json (the input ablation-row.sh joins into the runs.jsonl row), or
# self-checks a task (--self-check) on a synthetic run built from the task itself.
#
# Usage:
#   ablation-grade.sh <run-dir> <task-id> [--suite-root DIR] [--tasks-dir tasks|smoke]
#                     [--out FILE] [--json] [--executor container|host]
#                     [--image loa-ablation:258] [--docker-bin D]
#                     [--allow-unfrozen] [--allow-partial]
#   ablation-grade.sh --self-check base|reference|noisy --task-yaml F [--suite-root DIR]
#                     [--executor …] [--image …] [--docker-bin D] [--json]
#                     [--allow-unfrozen] [--allow-partial]
#
# Options:
#   --suite-root DIR   suite root (default grimoires/loa/evals/ablation-2.0; with
#                      --self-check, the directory two levels above the task dir)
#   --tasks-dir T      tasks (default) or smoke: the task is <root>/<T>/<task-id>/
#   --out FILE         where grade.json goes (default <run-dir>/grade.json)
#   --json             also print grade.json (self-check: the verdict object) on stdout
#   --executor MODE    container (default; DEC-0491) or host
#   --image IMG        the grading image (default loa-ablation:258)
#   --docker-bin D     docker CLI (default $EVAL_DOCKER_BIN, else docker)
#   --allow-unfrozen   grade although freeze.sh --check fails or the suite has no
#                      MANIFEST.sha256 yet (task authoring only); grade.json records
#                      suite_frozen: false. Without it a drift is exit 2 (DEC-0414).
#   --allow-partial    passed to freeze.sh --check (fewer than four tasks per type)
#   --self-check MODE  base | reference | noisy (noisy: review-catch only), see below
#   --task-yaml F      the task to self-check (<root>/<tasks|smoke>/<id>/task.yaml)
#
# Reads ONLY (DEC-0413): <run-dir>/sandbox/, <run-dir>/snapshots/{index.json,<LABEL>.bundle},
# <run-dir>/transcripts/events-*.jsonl, <run-dir>/eval/adversarial-{review,audit}.json,
# the task's directory under the suite root (task.yaml, hidden/, fixture/), the suite's
# MANIFEST.sha256 (through freeze.sh) and, for review-catch, the key manifest the task
# names (review_catch.manifest) and its PR fixture (self-check only). It never reads
# <run-dir>/meta/, the batch MANIFEST.json, or the sandbox copies of the dissent
# envelopes (tamperable; the harness copies under eval/ are authoritative). It writes
# only <run-dir>/grading/ and the --out file; nothing under sandbox/ is ever written.
#
# Freeze: freeze.sh --check --root <suite-root> runs first (with --smoke when the
# suite manifest lists smoke/ paths, so a manifest frozen with --smoke checks as it
# was frozen); a drift or a missing manifest refuses the grade (exit 2) unless
# --allow-unfrozen.
#
# Grading trees (D-4.8) under <run-dir>/grading/<label>/, recreated on every call:
#   final      sandbox/ as the agent left it, minus the top-level .git .claude CLAUDE.md
#              .loa.config.yaml grimoires .run .beads .eval pr, every __pycache__ and
#              .pytest_cache, anything that is not a regular file, directory or
#              symlink (a FIFO never blocks the copy), and every symlink whose target is
#              absolute or resolves outside the tree (lexically, then through the other
#              links; counted in symlinks_dropped); in-tree relative links are kept
#   implement  the IMPLEMENT snapshot (snapshots/IMPLEMENT.bundle, commit
#              index.json.implement): the tree REVIEW read; graded when REVIEW ran or
#              when AUDIT ran without a fix1 snapshot
#   fix1       the FIX1 snapshot: the tree AUDIT read; graded when AUDIT ran
#   base       the task fixture: the baseline of the regression check (regression_command;
#              refactor: test_command, the fixture suite)
# A snapshot is extracted with `git bundle unbundle` into a scratch bare repository and
# `git archive <commit>` (tarfile.data_filter: a member that would land outside the tree,
# and a symlink member with an absolute or escaping target, is skipped). In
# every tree each grader_protected path is restored from the fixture (a deleted file is
# recreated, a modified one overwritten, a path the fixture lacks is removed; a
# symlinked parent is replaced by a directory), then every hidden/manifest.json entry
# is written at its dest (a same-named file is overwritten, a deleted directory
# recreated). Deleting a grading tree never chmods through a symlink. Churn
# (diff_lines, files_changed) compares the final tree against the
# fixture before any restore: added + removed lines per changed text file (difflib),
# every added, removed or modified file counted once; null for review-catch.
#
# Commands run INSIDE the image (DEC-0491):
#   docker run --rm --network none --read-only --tmpfs /tmp:rw,size=256m --user <uid>:<gid>
#     -v <tree>:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp
#     <image> timeout 120 <cmd…>
# `python3 -m pytest …` (or `pytest …`) becomes `python3 -I -s -m pytest -p no:cacheprovider
# -q --rootdir /workspace -rA …` (one -q: -qq would drop the summary line; -rA lists every
# outcome, from which the ids come); `bats …` becomes `bats --tap …` with BATS_LIB_PATH
# unset (the -e set is the whole container environment). --executor host runs the same
# argv in the tree under `env -i PATH HOME=<scratch> LC_ALL=C TMPDIR=<scratch>
# PYTHONUSERBASE=<the caller's user base>` with pytest as `python3 -P -m pytest …`:
# no -I or -s on the host, because the host's pytest lives in the user site (the Sprint
# 258 smoke found no pytest under `-I -s`); PYTHONUSERBASE is passed for the same reason.
#
# Parsing: the pytest summary line (`N passed, M failed, K error …`) or TAP (`1..N`,
# `ok`/`not ok`). A collection error is expanded to the test functions of its file; the
# hidden total is never below the static case count of the hidden test files (`def test`
# / `@test`). A command without a parseable summary counts total = that static count
# (at least 1), passed = 0 when it exited non-zero (total when it exited 0), with
# parse_error: true. Ids: "t<k>", k = the 1-based position of the case in file order
# (pytest: path, then the line of its def; TAP: the test number); regression ids are
# positions in the base run, newly_failing = failing at final, passing at base. When
# either side of the regression check has no parseable summary, regressions.parse_error is
# true and newly_failing comes from the exit statuses: base unparsed, exit 0, final exit
# non-zero or timed out → every fallback id; base parsed, final unparsed and failed → every
# base-passing case; else none. A run is green (all_pass) only when every case passed, the
# summary parsed, the command exited 0 and did not time out.
#
# Hidden assertion per type: bug-fix and feature-build — test_command is hidden_tests,
# regression_command the regression check; refactor (DEC-0401, AC-5.3) — the structural
# check (structural_check's overlay dest, run with pytest or bats) is hidden_tests, so the
# row's hidden_test_pass_rate is the structural pass rate, and test_command (the fixture
# suite) is the regression check at base and final; structural repeats the structural
# counts with suite_green_base and suite_green_final.
#
# Review-catch (DEC-0420): grading/gates-combined.md is the arm-neutral reduction: every
# `path:line[-line]` citation (parser of recall-vs-defects.sh 1.1.2; the LOA-VERDICT
# trailer removed first) from sandbox/review.md (the A0 contract),
# sandbox/grimoires/loa/a2a/sprint-1/{engineer-feedback.md,auditor-sprint-feedback.md}
# and each finding's anchor (and file:line) in eval/adversarial-{review,audit}.json,
# one normalised `path:line[-line]` line each (pr/head/ → head/, a/ b/ and /workspace/
# prefixes dropped), duplicates dropped. recall-vs-defects.sh <grading-dir> <pr-NN>
# gates-combined.md (EVAL_MANIFEST_DIR = the manifest's directory) gives recall;
# flags = its findings_cited; missed = defect positions ("d2"), never defect ids.
# false_positives = citations within ±3 of no anchor, deduplicated by cited region
# (same file, overlapping ±3 windows count once).
#
# Verdicts: the last `<!-- LOA-VERDICT {…} -->` trailer of engineer-feedback.md (review)
# and auditor-sprint-feedback.md (audit); a gate ran when its feedback file exists.
# verdict = {source_file, value}: the audit's, else the review's, else review.md's
# `Verdict:` line (A0), else null. verdict_accuracy_per_gate {review, audit}: build —
# true when APPROVED and the tree that gate read passes every hidden test, or
# CHANGES_REQUIRED and it fails one; review-catch — true iff (CHANGES_REQUIRED) ==
# (the key holds a high or critical defect); refactor — the tree passes when the
# structural check AND the fixture suite are green on it; a gate without a trailer is false; a gate
# that did not run is null. verdict_accuracy = audit's, else review's, else null.
#
# Contamination (D-4.7, DEC-0493): every tool_use input in transcripts/events-*.jsonl —
# Bash command; Read/Grep/Glob file_path|path|pattern; Write/Edit/MultiEdit/NotebookEdit
# file_path|notebook_path; WebFetch url; WebSearch query — is checked for: `hidden` (any
# case) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
# repo_name; `git log … --all` or `git reflog` (Bash) → git_history; an absolute path
# (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word
# is read as a regex) outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
# /sbin /lib /lib64 /etc /opt /var (container), or outside the sandbox root (the
# sessions' init cwd and <run-dir>/sandbox), /tmp, those system directories and the
# caller's ~/.claude ~/.claude.json ~/.codex ~/.aws (host) → outside_path. The first hit
# in phase order is contaminated: {phase, pattern, excerpt_id: "<phase>:<line>"} (never
# the text); else null. The scan is a LOWER BOUND on leakage: obfuscated access, reads
# by programs the agent wrote, and network access by other means are not seen.
#
# grade.json (ids only in every summary field: no test name, defect title or excerpt):
#   {schema_version: 1, grader_version: "1.1.0", task_id, task_type, suite_frozen,
#    executor_mode, image, snapshots_graded: [labels], hidden_tests {passed, total,
#    failed_names, parse_error, timed_out, rc}, structural (refactor: {passed, total,
#    failed_names, parse_error, suite_green_base, suite_green_final}; else null),
#    regressions ({newly_failing, base {passed, total, rc, timed_out}, final {…},
#    parse_error} or null without a regression check), snapshot_tests {implement?,
#    fix1?: {passed, total}} (refactor: the structural check), recall (review-catch
#    {defects_seeded, defects_caught, recall, flags, missed}; else null),
#    false_positives, verdict, verdicts {review, audit}, verdict_accuracy,
#    verdict_accuracy_per_gate {review, audit}, diff_lines, files_changed,
#    symlinks_dropped, contaminated}
# grader 1.1.0 (Sprint 259 fix round): refactor hidden_tests = the structural check,
# exit-status-aware green, symlink filtering; 1.0.0 grades of refactor tasks differ.
# Round 2: snapshot trees get the same realpath symlink pass as the final copy (counted in
# symlinks_dropped); regressions carries base_green and final_green (all_pass of each run);
# the self-check's suite-green rule requires a parsed summary too.
# No timestamp and no scratch path is written: the same run grades byte-identically.
#
# Self-check (DEC-0401; AC-2.3): a synthetic run under mktemp -d built from the task.
#   base       build: the fixture is the final tree → PASS when at least one hidden test
#              fails (refactor: the structural check) and the regression check's final
#              run (regressions.final) is green — every case, exit 0, no timeout;
#              review-catch: an empty findings file → recall 0.0
#   reference  build: the fixture with hidden/reference.patch (patch -p1) → every hidden
#              test passes with exit 0 (refactor: structural green), suite green;
#              review-catch: a findings file citing every key anchor → recall 1.0
#   noisy      review-catch: every line of every pr/head/ file cited → false_positives
#              greater than the reference findings file's
# Prints `self-check <mode> <task-id>: PASS|FAIL <evidence>`.
#
# Exit codes: 0 graded / self-check PASS; 1 self-check FAIL; 2 error (usage, missing run
# dir, task not found, unfrozen suite without --allow-unfrozen, docker or the image
# missing in container mode, a tool failure).
#
# Tested by evals/tests/ablation-grade.bats (docker = evals/tests/fixtures/docker-stub.sh).
# No .claude/ code is sourced and nothing is sourced or eval'd from a variable (eval.yml
# trust boundary); hashing is Python hashlib.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
case "${1:-}" in -h|--help) sed -n '3,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac

exec python3 -I - "$SCRIPT_DIR" "$REPO_ROOT" "${EVAL_DOCKER_BIN:-docker}" "$@" <<'PY'
import argparse, difflib, json, os, re, shutil, site, stat, subprocess, sys, tarfile, tempfile

GRADER_VERSION = "1.1.0"
SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
SPRINT = "sprint-1"
TEST_TIMEOUT_S = 120
EXCLUDE_TOP = {".git", ".claude", "CLAUDE.md", ".loa.config.yaml", "grimoires", ".run", ".beads", ".eval", "pr"}
EXCLUDE_ANY = {"__pycache__", ".pytest_cache"}
PHASE_ORDER = ["PLAN", "BARE", "IMPLEMENT", "REVIEW", "FIX1", "AUDIT", "FIX2"]


class GradeError(Exception):
    pass


def die(msg):
    print(f"ablation-grade: {msg}", file=sys.stderr)
    sys.exit(2)


ap = argparse.ArgumentParser(prog="ablation-grade.sh", add_help=False)
ap.add_argument("run_dir", nargs="?")
ap.add_argument("task_id", nargs="?")
ap.add_argument("--suite-root")
ap.add_argument("--tasks-dir", choices=["tasks", "smoke"])
ap.add_argument("--out")
ap.add_argument("--json", action="store_true")
ap.add_argument("--executor", choices=["container", "host"], default="container")
ap.add_argument("--image", default="loa-ablation:258")
ap.add_argument("--docker-bin", default=DOCKER_DEFAULT)
ap.add_argument("--allow-unfrozen", action="store_true")
ap.add_argument("--allow-partial", action="store_true")
ap.add_argument("--self-check", choices=["base", "reference", "noisy"])
ap.add_argument("--task-yaml")
try:
    A = ap.parse_args(sys.argv[4:])
except SystemExit:
    sys.exit(2)


# ------------------------------------------------------------------ small helpers
def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def load_yaml(path):
    p = run(["yq", "-o=json", ".", path])
    if p.returncode != 0:
        raise GradeError(f"task yaml does not parse: {path}")
    try:
        return json.loads(p.stdout)
    except ValueError:
        raise GradeError(f"task yaml does not parse: {path}")


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def is_within(path, root):
    path, root = os.path.realpath(path), os.path.realpath(root)
    return path == root or path.startswith(root + os.sep)


def remove_path(p):
    """delete p; a directory is made writable first, but never through a symlink: a tree
    the agent shaped may hold `x -> /somewhere`, and os.chmod follows links (DISS-001)"""
    if os.path.islink(p) or os.path.isfile(p):
        os.unlink(p)
    elif os.path.isdir(p):
        for r, ds, _fs in os.walk(p, followlinks=False):
            for d in ds:
                q = os.path.join(r, d)
                try:
                    if stat.S_ISDIR(os.lstat(q).st_mode):
                        os.chmod(q, 0o700)
                except OSError:
                    pass
        shutil.rmtree(p)
    elif os.path.lexists(p):
        os.unlink(p)


def safe_rel(rel):
    if not isinstance(rel, str) or not rel or rel.startswith("/") or "\\" in rel:
        return None
    parts = [x for x in rel.split("/") if x not in ("", ".")]
    if not parts or ".." in parts:
        return None
    return parts


def ensure_parent(tree, parts):
    """make every parent component of tree/parts a real directory inside tree"""
    cur = tree
    for comp in parts[:-1]:
        cur = os.path.join(cur, comp)
        if os.path.islink(cur) or (os.path.lexists(cur) and not os.path.isdir(cur)):
            os.unlink(cur)
        if not os.path.isdir(cur):
            os.mkdir(cur)
    return os.path.join(cur, parts[-1])


def link_escapes(target, rel_dir):
    """a symlink at <tree>/<rel_dir>/<name> pointing at target: absolute, or resolving
    (lexically) above the tree root"""
    if not target or os.path.isabs(target):
        return True
    n = os.path.normpath(os.path.join(rel_dir, target))
    return n == ".." or n.startswith("../") or os.path.isabs(n)


def drop_escaping_links(tree):
    """second pass over the copy: any symlink whose full resolution (through the other
    links) leaves the tree is removed; repeated until stable → number removed"""
    n, root = 0, os.path.realpath(tree)
    while True:
        gone = 0
        for r, ds, fs in os.walk(tree, followlinks=False):
            for name in ds + fs:
                q = os.path.join(r, name)
                if os.path.islink(q) and not is_within(q, root):
                    os.unlink(q)
                    gone += 1
        if not gone:
            return n
        n += gone


def copy_tree(src, dst, top_exclude=frozenset()):
    """regular files, directories and in-tree relative symlinks only; caches dropped. A
    symlink whose target is absolute or resolves outside dst is not recreated (DISS-001).
    → the number of symlinks dropped"""
    os.makedirs(dst, exist_ok=True)
    dropped = 0
    for root, dirs, files in os.walk(src, followlinks=False):
        rel = os.path.relpath(root, src)
        keep = []
        for d in sorted(dirs):
            if (rel == "." and d in top_exclude) or d in EXCLUDE_ANY:
                continue
            sp = os.path.join(root, d)
            dp = os.path.join(dst, rel, d)
            if os.path.islink(sp):
                target = os.readlink(sp)
                if link_escapes(target, rel):
                    dropped += 1
                else:
                    os.symlink(target, dp)
                continue
            os.makedirs(dp, exist_ok=True)
            keep.append(d)
        dirs[:] = keep
        for f in sorted(files):
            if rel == "." and f in top_exclude:
                continue
            sp, dp = os.path.join(root, f), os.path.join(dst, rel, f)
            st = os.lstat(sp)
            if stat.S_ISLNK(st.st_mode):
                target = os.readlink(sp)
                if link_escapes(target, rel):
                    dropped += 1
                else:
                    os.symlink(target, dp)
            elif stat.S_ISREG(st.st_mode):
                shutil.copyfile(sp, dp)
                os.chmod(dp, (st.st_mode & 0o777) | 0o600)
    return dropped + drop_escaping_links(dst)


def put_file(tree, rel, src):
    parts = safe_rel(rel)
    if parts is None:
        raise GradeError(f"unsafe path: {rel!r}")
    dst = ensure_parent(tree, parts)
    if os.path.lexists(dst):
        remove_path(dst)
    if os.path.isdir(src) and not os.path.islink(src):
        copy_tree(src, dst)
    else:
        shutil.copyfile(src, dst)
        os.chmod(dst, (os.stat(src).st_mode & 0o777) | 0o600)


# ------------------------------------------------------------------ task loading
class Task:
    pass


def load_task(task_yaml, suite_root):
    t = Task()
    t.yaml = os.path.abspath(task_yaml)
    t.dir = os.path.dirname(t.yaml)
    t.suite_root = os.path.abspath(suite_root)
    t.spec = load_yaml(t.yaml)
    if not isinstance(t.spec, dict):
        raise GradeError(f"task yaml is not a mapping: {task_yaml}")
    t.id = t.spec.get("id") or ""
    t.type = t.spec.get("type") or ""
    if t.type not in ("bug-fix", "feature-build", "refactor", "review-catch"):
        raise GradeError(f"unknown task type: {t.type!r}")
    t.build = t.type != "review-catch"
    t.fixture = None
    if t.build:
        rel = t.spec.get("fixture")
        if not isinstance(rel, str) or not rel:
            raise GradeError("build task has no fixture")
        for cand in (os.path.join(t.suite_root, rel), os.path.join(t.dir, rel)):
            if os.path.isdir(cand):
                t.fixture = os.path.realpath(cand)
                break
        if t.fixture is None:
            raise GradeError(f"fixture not found: {rel}")
        if not is_within(t.fixture, t.dir):
            raise GradeError(f"fixture must be inside the task directory: {rel}")
    t.hidden = os.path.join(t.dir, "hidden")
    man = read_json(os.path.join(t.hidden, "manifest.json")) if t.build else None
    t.overlay = []
    if t.build:
        if not isinstance(man, dict) or not isinstance(man.get("files"), list):
            raise GradeError("hidden/manifest.json missing or malformed")
        for e in man["files"]:
            src, dest = (e or {}).get("src"), (e or {}).get("dest")
            sp = safe_rel(src)
            if sp is None or safe_rel(dest) is None:
                raise GradeError(f"hidden/manifest.json: unsafe entry {e!r}")
            full = os.path.join(t.hidden, *sp)
            if not os.path.exists(full):
                raise GradeError(f"hidden/manifest.json: src not found: {src}")
            t.overlay.append(("/".join(sp), "/".join(safe_rel(dest)), full))
    t.protected = []
    for p in t.spec.get("grader_protected") or []:
        parts = safe_rel(p)
        if parts is None:
            raise GradeError(f"grader_protected: unsafe path {p!r}")
        t.protected.append("/".join(parts))
    t.test_command = t.spec.get("test_command")
    t.regression_command = t.spec.get("regression_command")
    for k in ("test_command", "regression_command"):
        v = getattr(t, k)
        if v is not None and (not isinstance(v, list) or not v or not all(isinstance(x, str) for x in v)):
            raise GradeError(f"{k} must be a non-empty array of strings or null")
    if t.build and not t.test_command:
        raise GradeError("build task has no test_command")
    t.structural = None
    sc = t.spec.get("structural_check")
    if sc:
        sp = safe_rel(sc)
        if sp is None or sp[0] != "hidden":
            raise GradeError(f"structural_check must be under hidden/: {sc}")
        src = "/".join(sp[1:])
        dest = next((d for s, d, _f in t.overlay if s == src), None)
        if dest is None:
            raise GradeError(f"structural_check {sc} is not overlaid by hidden/manifest.json")
        t.structural = dest
    if t.type == "refactor" and not t.structural:
        raise GradeError("refactor task has no structural_check")
    t.structural_full = next((f for _s, d, f in t.overlay if d == t.structural), None) if t.structural else None
    t.reference_patch = None
    rp = t.spec.get("reference_patch")
    if rp:
        parts = safe_rel(rp)
        if parts is None:
            raise GradeError(f"reference_patch: unsafe path {rp!r}")
        t.reference_patch = os.path.join(t.dir, *parts)
    # the hidden test files' static case count (structural check excluded)
    t.static_cases = 0
    for s, d, full in t.overlay:
        if d == t.structural or not os.path.isfile(full):
            continue
        t.static_cases += count_cases(full)
    t.structural_cases = count_cases(t.structural_full) if t.structural_full else 0
    t.rc = None
    if t.type == "review-catch":
        rc = t.spec.get("review_catch")
        if not isinstance(rc, dict) or not rc.get("manifest"):
            raise GradeError("review-catch task has no review_catch.manifest")
        t.rc = rc
        mp = None
        for cand in (os.path.join(REPO_ROOT, rc["manifest"]), os.path.join(t.suite_root, rc["manifest"]),
                     os.path.join(t.dir, rc["manifest"])):
            if os.path.isfile(cand):
                mp = os.path.abspath(cand)
                break
        if mp is None:
            raise GradeError(f"review-catch manifest not found: {rc['manifest']}")
        t.key_path = mp
        t.key = read_json(mp)
        if not isinstance(t.key, dict) or not isinstance(t.key.get("defects"), list):
            raise GradeError(f"review-catch manifest malformed: {rc['manifest']}")
        t.key_id = os.path.basename(mp)[:-5] if mp.endswith(".json") else os.path.basename(mp)
    return t


def count_cases(path):
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return 0
    if path.endswith(".bats"):
        return len(re.findall(r"(?m)^\s*@test\s", text))
    if path.endswith(".py"):
        return len(re.findall(r"(?m)^\s*(?:async\s+)?def\s+test\w*\s*\(", text))
    return 0


def resolve_pr_fixture(t):
    rel = (t.rc or {}).get("fixture") or ""
    for cand in (os.path.join(t.dir, rel), os.path.join(t.suite_root, rel), os.path.join(REPO_ROOT, rel),
                 os.path.join(REPO_ROOT, "evals", "fixtures", rel)):
        if rel and os.path.isdir(cand):
            return os.path.abspath(cand)
    raise GradeError(f"review-catch fixture not found: {rel}")


# ------------------------------------------------------------------ freeze
def freeze_check(suite_root):
    manifest = os.path.join(suite_root, "MANIFEST.sha256")
    if not os.path.isfile(manifest):
        if A.allow_unfrozen:
            print("ablation-grade: WARNING suite has no MANIFEST.sha256; grading unfrozen (--allow-unfrozen)", file=sys.stderr)
            return False
        raise GradeError(f"suite is not frozen: no MANIFEST.sha256 in {suite_root} (--allow-unfrozen while authoring)")
    smoke = any(l.split("  ", 1)[-1].startswith("smoke/") for l in open(manifest, encoding="utf-8") if l.strip())
    cmd = ["bash", os.path.join(SCRIPT_DIR, "freeze.sh"), "--root", suite_root, "--check"]
    if smoke:
        cmd.append("--smoke")
    if A.allow_partial:
        cmd.append("--allow-partial")
    p = run(cmd)
    if p.returncode == 0:
        return True
    detail = (p.stdout + p.stderr).strip().splitlines()
    if A.allow_unfrozen:
        print("ablation-grade: WARNING freeze.sh --check failed; grading unfrozen (--allow-unfrozen)", file=sys.stderr)
        return False
    raise GradeError("freeze.sh --check failed (exit %d); refusing to grade: %s" % (p.returncode, " | ".join(detail[:6])))


# ------------------------------------------------------------------ command execution
SCRATCH = tempfile.mkdtemp(prefix="ablation-grade.")


def docker_ready():
    if A.executor != "container":
        return
    d = A.docker_bin
    if not (shutil.which(d) or (os.path.isfile(d) and os.access(d, os.X_OK))):
        raise GradeError(f"docker CLI not found: {d} (container mode)")
    p = run([d, "image", "inspect", "--format", "{{.Id}}", A.image])
    if p.returncode != 0:
        raise GradeError(f"image not found: {A.image}")


def shape_command(cmd, root):
    """the argv that runs inside the tree; root = /workspace (container) or the tree (host)"""
    host = A.executor == "host"
    rest = None
    if cmd[:3] == ["python3", "-m", "pytest"]:
        rest = cmd[3:]
    elif cmd[0] == "pytest":
        rest = cmd[1:]
    if rest is not None:
        rest = [x for x in rest if x not in ("-q", "--quiet")]
        pre = ["python3", "-P"] if host else ["python3", "-I", "-s"]
        return pre + ["-m", "pytest", "-p", "no:cacheprovider", "-q", "--rootdir", root, "-rA"] + rest, "pytest"
    if cmd[0] == "bats":
        rest = cmd[1:]
        if "--tap" in rest or any(x.startswith("--formatter") or x == "-F" for x in rest):
            return list(cmd), "tap"
        return ["bats", "--tap"] + rest, "tap"
    return list(cmd), "auto"


def exec_in_tree(tree, cmd):
    """→ (rc, output, timed_out, kind)"""
    if A.executor == "container":
        argv, kind = shape_command(cmd, "/workspace")
        full = [A.docker_bin, "run", "--rm", "--network", "none", "--read-only", "--tmpfs", "/tmp:rw,size=256m",
                "--user", f"{os.getuid()}:{os.getgid()}", "-v", f"{tree}:/workspace:rw", "-w", "/workspace",
                "-e", "HOME=/tmp", "-e", "LC_ALL=C", "-e", "TMPDIR=/tmp", A.image, "timeout", str(TEST_TIMEOUT_S)] + argv
        cwd = None
    else:
        argv, kind = shape_command(cmd, tree)
        home = tempfile.mkdtemp(prefix="home.", dir=SCRATCH)
        full = ["env", "-i", "PATH=" + os.environ.get("PATH", "/usr/bin:/bin"), "HOME=" + home, "LC_ALL=C",
                "TMPDIR=" + home, "PYTHONUSERBASE=" + site.getuserbase(), "timeout", str(TEST_TIMEOUT_S)] + argv
        cwd = tree
    try:
        p = subprocess.run(full, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                           timeout=TEST_TIMEOUT_S + 60)
        out, rc = p.stdout.decode("utf-8", "replace"), p.returncode
    except subprocess.TimeoutExpired as e:
        out, rc = (e.stdout or b"").decode("utf-8", "replace"), 124
    except OSError as e:
        raise GradeError(f"cannot run {full[0]}: {e}")
    return rc, out, rc == 124, kind


# ------------------------------------------------------------------ result parsing
SUMMARY_RX = re.compile(r"^=*\s*((?:\d+ [a-z]+(?:, )?)+) in [0-9.]+s(?: \([^)]*\))?\s*=*\s*$")
COUNT_RX = re.compile(r"(\d+) ([a-z]+)")
OUTCOME_RX = re.compile(r"^(PASSED|FAILED|ERROR|XFAIL|XPASS) (\S+)")


def def_line(tree, path, func, cache):
    if path not in cache:
        try:
            cache[path] = open(os.path.join(tree, path), encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            cache[path] = []
    rx = re.compile(r"^\s*(?:async\s+)?def\s+" + re.escape(func) + r"\s*\(")
    for i, l in enumerate(cache[path], 1):
        if rx.match(l):
            return i
    return 10 ** 9


def parse_pytest(out, tree):
    lines = out.splitlines()
    summary = None
    for l in reversed(lines):
        m = SUMMARY_RX.match(l.strip())
        if m:
            summary = {k: int(n) for n, k in COUNT_RX.findall(m.group(1))}
            break
    if summary is None:
        return None
    norm = {}
    for k, v in summary.items():
        k = {"error": "errors", "warning": "warnings"}.get(k, k)
        norm[k] = norm.get(k, 0) + v
    outcomes, coll_err = {}, []
    for l in lines:
        m = OUTCOME_RX.match(l)
        if not m:
            continue
        kind, node = m.group(1), m.group(2)
        if kind == "ERROR" and "::" not in node:
            coll_err.append(node)
            continue
        prev = outcomes.get(node)
        bad = kind in ("FAILED", "ERROR")
        outcomes[node] = "bad" if (bad or prev == "bad") else "ok"
    cache = {}
    expanded = 0
    for f in coll_err:
        try:
            text = open(os.path.join(tree, f), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for fn in re.findall(r"(?m)^\s*(?:async\s+)?def\s+(test\w*)\s*\(", text):
            outcomes.setdefault(f"{f}::{fn}", "bad")
            expanded += 1

    def key(node):
        path, _, rest = node.partition("::")
        func = rest.split("::")[-1].split("[")[0]
        return (path, def_line(tree, path, func, cache), node)
    order = sorted(outcomes, key=key)
    total = sum(norm.get(k, 0) for k in ("passed", "failed", "errors", "skipped", "xfailed", "xpassed"))
    total = total - len(coll_err) + expanded
    passed = norm.get("passed", 0)
    if total <= 0 and passed == 0:
        return None
    return {"passed": passed, "total": max(total, len(order)), "order": order,
            "bad": {n for n, v in outcomes.items() if v == "bad"}}


TAP_RX = re.compile(r"^(not )?ok (\d+)\b ?(?:- )?(.*)$")


def parse_tap(out):
    plan, seen = None, {}
    for l in out.splitlines():
        m = re.match(r"^1\.\.(\d+)", l)
        if m and plan is None:
            plan = int(m.group(1))
            continue
        m = TAP_RX.match(l)
        if m:
            n = int(m.group(2))
            desc = re.sub(r"\s+#\s*(?:skip|SKIP|todo|TODO).*$", "", m.group(3)).strip()
            seen[n] = (m.group(1) is None, desc or f"#{n}")
    if plan is None and not seen:
        return None
    total = plan if plan is not None else len(seen)
    if total == 0:
        return None
    nums = sorted(set(range(1, total + 1)) | set(seen))
    names = {n: (seen[n][1] if n in seen else f"#{n}") for n in nums}
    order = [names[n] for n in nums]
    bad = {names[n] for n in nums if n not in seen or not seen[n][0]}
    return {"passed": sum(1 for n in seen if seen[n][0]), "total": total, "order": order, "bad": bad}


def run_suite(tree, cmd, static=0):
    rc, out, timed_out, kind = exec_in_tree(tree, cmd)
    parsed = None
    if kind in ("pytest", "auto"):
        parsed = parse_pytest(out, tree)
    if parsed is None and kind in ("tap", "auto"):
        parsed = parse_tap(out)
    if parsed is None:
        total = max(static, 1)
        passed = total if rc == 0 else 0
        order = [f"#{i}" for i in range(1, total + 1)]
        return {"passed": passed, "total": total, "order": order, "bad": set(order) if rc != 0 else set(),
                "parse_error": True, "timed_out": timed_out, "rc": rc}
    parsed["total"] = max(parsed["total"], static)
    parsed.update(parse_error=False, timed_out=timed_out, rc=rc)
    return parsed


def ids_of(res, keys):
    pos = {k: i for i, k in enumerate(res["order"], 1)}
    return sorted((f"t{pos[k]}" for k in keys if k in pos), key=lambda s: int(s[1:]))


def summary(res):
    return {"passed": res["passed"], "total": res["total"], "failed_names": ids_of(res, res["bad"]),
            "parse_error": res["parse_error"], "timed_out": res["timed_out"], "rc": res["rc"]}


def all_pass(res):
    """every case passed, the summary parsed, and the command exited 0 within its time
    (a passing TAP block followed by exit 1, or a timeout, is not green: DISS-002)"""
    if res is None:
        return False
    return (res["passed"] >= res["total"] and not res["bad"] and not res["parse_error"]
            and res["rc"] == 0 and not res["timed_out"])


def run_counts(res):
    return {"passed": res["passed"], "total": res["total"], "rc": res["rc"], "timed_out": res["timed_out"]}


def regressions(rb, rf):
    """base run rb vs final run rf of the regression command. Parsed on both sides:
    newly_failing = base-passing cases failing (or absent) at final. Either side
    unparseable (DISS-003): base unparsed → every fallback id when the base exited 0 and
    the final run failed (non-zero exit or timeout); base parsed, final unparsed → every
    base-passing case when the final run failed; else none. parse_error records it."""
    final_red = rf["rc"] != 0 or rf["timed_out"]
    base_ok = [k for k in rb["order"] if k not in rb["bad"]]
    pe = bool(rb["parse_error"] or rf["parse_error"])
    if not pe:
        newly = [k for k in base_ok if k in rf["bad"] or k not in rf["order"]]
    elif rb["parse_error"]:
        newly = list(rb["order"]) if (rb["rc"] == 0 and not rb["timed_out"] and final_red) else []
    else:
        newly = base_ok if final_red else []
    return {"newly_failing": ids_of(rb, newly), "base": run_counts(rb), "final": run_counts(rf), "parse_error": pe,
            "base_green": all_pass(rb), "final_green": all_pass(rf)}


# ------------------------------------------------------------------ grading trees
def prepare(t, tree):
    for rel in t.protected:
        src = os.path.join(t.fixture, *rel.split("/"))
        if os.path.lexists(src) and not os.path.islink(src):
            put_file(tree, rel, src)
        else:
            parts = rel.split("/")
            cur = tree
            ok = True
            for comp in parts[:-1]:
                cur = os.path.join(cur, comp)
                if os.path.islink(cur) or not os.path.isdir(cur):
                    ok = False
                    break
            if ok and os.path.lexists(os.path.join(tree, *parts)):
                remove_path(os.path.join(tree, *parts))
    for _s, dest, full in t.overlay:
        put_file(tree, dest, full)


def git_env(home):
    return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "LC_ALL": "C",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}


SNAPSHOT_LINKS_DROPPED = [0]   # escaping links removed from snapshot trees in this grade


def extract_snapshot(run_dir, label, commit, tree):
    snaps = os.path.join(run_dir, "snapshots")
    bundle = None
    for name in (label.upper() + ".bundle", label + ".bundle"):
        p = os.path.join(snaps, name)
        if os.path.isfile(p) and not os.path.islink(p):
            bundle = p
            break
    if bundle is None or not re.match(r"^[0-9a-f]{7,64}$", commit or ""):
        return False
    g = tempfile.mkdtemp(prefix="git.", dir=SCRATCH)
    env = git_env(g)
    if run(["git", "init", "-q", "--bare", g], env=env).returncode != 0:
        return False
    if run(["git", "-C", g, "bundle", "unbundle", bundle], env=env).returncode != 0:
        return False
    tarp = os.path.join(g, "snap.tar")
    with open(tarp, "wb") as f:
        if subprocess.run(["git", "-C", g, "archive", "--format=tar", commit], stdout=f, stderr=subprocess.DEVNULL,
                          env=env).returncode != 0:
            return False
    os.makedirs(tree, exist_ok=True)

    def keep(member, path):
        parts = safe_rel(member.name)
        if parts is None or parts[0] in EXCLUDE_TOP or any(x in EXCLUDE_ANY for x in parts):
            return None
        try:
            return tarfile.data_filter(member, path)
        except tarfile.FilterError:
            return None
    with tarfile.open(tarp) as tf:
        tf.extractall(tree, filter=keep)
    # round 2 DISS-C-001: data_filter judges members in archive order, so a link that escapes
    # only through a later link slips past it; the same realpath pass as the final copy runs here
    SNAPSHOT_LINKS_DROPPED[0] += drop_escaping_links(tree)
    return True


# ------------------------------------------------------------------ churn
def churn(a, b):
    def listing(root):
        out = {}
        for r, ds, fs in os.walk(root, followlinks=False):
            ds[:] = [d for d in ds if d not in EXCLUDE_ANY and not os.path.islink(os.path.join(r, d))]
            for name in fs + [d for d in os.listdir(r) if os.path.islink(os.path.join(r, d)) and os.path.isdir(os.path.join(r, d))]:
                p = os.path.join(r, name)
                out[os.path.relpath(p, root)] = p
        return out
    def content(p):
        if os.path.islink(p):
            return ("link:" + os.readlink(p)).encode()
        try:
            return open(p, "rb").read()
        except OSError:
            return b""
    def lines(bs):
        try:
            return bs.decode("utf-8").splitlines()
        except UnicodeDecodeError:
            return None
    la, lb = listing(a), listing(b)
    files = diff = 0
    for rel in sorted(set(la) | set(lb)):
        ca = content(la[rel]) if rel in la else None
        cb = content(lb[rel]) if rel in lb else None
        if ca == cb:
            continue
        files += 1
        xa = lines(ca) if ca is not None else []
        xb = lines(cb) if cb is not None else []
        if xa is None or xb is None:
            continue
        for l in difflib.unified_diff(xa, xb, lineterm="", n=0):
            if l.startswith(("+++", "---", "@@")):
                continue
            if l.startswith(("+", "-")):
                diff += 1
    return diff, files


# ------------------------------------------------------------------ verdicts
TRAILER_LINE = re.compile(r"<!-- LOA-VERDICT (\{.*\}) -->\s*$")


def gate_verdict(path):
    """→ None (no file) | APPROVED | CHANGES_REQUIRED | none"""
    if not os.path.isfile(path):
        return None
    last = None
    for l in open(path, encoding="utf-8", errors="replace"):
        m = TRAILER_LINE.search(l.rstrip("\n"))
        if m:
            last = m.group(1)
    if last is None:
        return "none"
    try:
        v = json.loads(last).get("verdict")
    except (ValueError, AttributeError):
        return "none"
    return v if v in ("APPROVED", "CHANGES_REQUIRED") else "none"


def review_md_verdict(path):
    if not os.path.isfile(path):
        return None
    v = None
    for l in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"^\s*\**Verdict:?\**:?\s*\**\s*(APPROVED|CHANGES_REQUIRED)\b", l)
        if m:
            v = m.group(1)
    return v


# ------------------------------------------------------------------ citations (recall-vs-defects 1.1.2 parser)
RNG = r'(\d{1,6})(?:[-–](\d{1,6}))?(?![A-Za-z0-9]|[-–]\d)'
CITE = re.compile(
    r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6})[`*)]{0,3}:(?P<first>' + RNG
    + r'(?:[ \t]*,[ \t]*' + RNG + r')*)'
    r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:"\'{}\[\]*])(?<![A-Za-z0-9_"\'}\]]`)):(?P<bare>' + RNG + r')')
ONE = re.compile(RNG)
TRAILER = re.compile(r'<!--\s*LOA-VERDICT\s*(\{(?:(?!<!--|-->).)*\})\s*-->', re.S)
URL = re.compile(r'[A-Za-z][A-Za-z0-9+.-]*://|^//')


def norm_path(p):
    p = p.lstrip("(")
    for pre in ("/workspace/", "./"):
        if p.startswith(pre):
            p = p[len(pre):]
    if p.startswith("pr/head/"):
        p = "head/" + p[len("pr/head/"):]
    elif p.startswith("pr/base/"):
        p = "base/" + p[len("pr/base/"):]
    elif p.startswith(("a/", "b/")):
        p = p[2:]
    return p


def citations(text):
    body = TRAILER.sub("", text)
    out, last = [], None
    for m in CITE.finditer(body):
        if m.group("path") is not None:
            tok = re.split(r"\s", body[max(0, m.start() - 4096):m.start()])[-1] + m.group("path")
            if "//" in m.group("path") or URL.search(tok):
                continue
            last, spans = norm_path(m.group("path")), m.group("first")
        elif last is not None:
            spans = m.group("bare")
        else:
            continue
        for r in ONE.finditer(spans):
            a = int(r.group(1))
            b = int(r.group(2)) if r.group(2) else a
            if b < a:
                a, b = b, a
            out.append((last, a, b))
    return out


def strip_side(p):
    for pre in ("head/", "base/"):
        if p.startswith(pre):
            return p[len(pre):]
    return p


def path_matches(cited, defect_file):
    cited = strip_side(cited)
    if cited == defect_file or defect_file.endswith("/" + cited):
        return True
    return cited == defect_file.rsplit("/", 1)[-1]


def envelope_texts(path):
    env = read_json(path)
    if not isinstance(env, dict):
        return []
    out = []
    for f in env.get("findings") or []:
        if not isinstance(f, dict):
            continue
        if isinstance(f.get("anchor"), str):
            out.append(f["anchor"])
        fp = f.get("file") or f.get("path")
        ln = f.get("line") or f.get("line_start") or f.get("start_line")
        if isinstance(fp, str) and isinstance(ln, int):
            out.append(f"{fp}:{ln}")
    return out


def combined_findings(run_dir):
    sb = os.path.join(run_dir, "sandbox")
    a2a = os.path.join(sb, "grimoires", "loa", "a2a", SPRINT)
    texts = []
    for p in (os.path.join(sb, "review.md"), os.path.join(a2a, "engineer-feedback.md"),
              os.path.join(a2a, "auditor-sprint-feedback.md")):
        if os.path.isfile(p) and not os.path.islink(p):
            texts.append(open(p, encoding="utf-8", errors="replace").read())
    for gate in ("review", "audit"):
        p = os.path.join(run_dir, "eval", f"adversarial-{gate}.json")
        if os.path.isfile(p) and not os.path.islink(p):
            texts.extend(envelope_texts(p))
    seen, cites = set(), []
    for tx in texts:
        for c in citations(tx):
            if c not in seen:
                seen.add(c)
                cites.append(c)
    return cites


def false_positives(cites, defects):
    anchors = []
    for d in defects:
        for s in (d.get("anchors") or [d.get("anchor_line")]):
            if isinstance(s, int):
                anchors.append((d.get("file", ""), s))
    stray = {}
    for p, a, b in cites:
        if any(path_matches(p, f) and not (b < s - 3 or a > s + 3) for f, s in anchors):
            continue
        stray.setdefault(strip_side(p), []).append((a - 3, b + 3))
    n = 0
    for _p, wins in stray.items():
        end = None
        for lo, hi in sorted(wins):
            if end is None or lo > end:
                n += 1
                end = hi
            else:
                end = max(end, hi)
    return n


def grade_recall(t, run_dir, grading):
    cites = combined_findings(run_dir)
    combined = os.path.join(grading, "gates-combined.md")
    with open(combined, "w", encoding="utf-8") as f:
        f.write("".join(f"{p}:{a}\n" if a == b else f"{p}:{a}-{b}\n" for p, a, b in cites))
    env = dict(os.environ, EVAL_MANIFEST_DIR=os.path.dirname(t.key_path), LC_ALL="C")
    p = run(["bash", os.path.join(REPO_ROOT, "evals", "graders", "recall-vs-defects.sh"), grading, t.key_id,
             "gates-combined.md"], env=env)
    try:
        det = json.loads(p.stdout)["details"]
    except (ValueError, KeyError, TypeError):
        raise GradeError(f"recall-vs-defects.sh failed (exit {p.returncode})")
    if p.returncode == 2 or "error" in det:
        raise GradeError(f"recall-vs-defects.sh error: {det.get('error')}")
    defects = t.key.get("defects") or []
    pos = {d.get("id"): i for i, d in enumerate(defects, 1)}
    recall = {"defects_seeded": det.get("planted", len(defects)), "defects_caught": len(det.get("detected") or []),
              "recall": det.get("recall"), "flags": det.get("findings_cited"),
              "missed": [f"d{pos[x]}" for x in det.get("missed") or [] if x in pos]}
    return recall, false_positives(cites, defects)


# ------------------------------------------------------------------ contamination
SYS_DIRS = ["/dev", "/proc", "/sys", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/opt", "/var"]
GIT_HIST = re.compile(r"\bgit\b[^;&|\n]*\blog\b[^;&|\n]*--all\b|\bgit\b[^;&|\n]*\breflog\b")
ABS_WORD = re.compile(r"(?:(?<=^)|(?<=[\s=:'\"`(<>|;&,]))(/[A-Za-z0-9._@+%=,:~-][A-Za-z0-9._@+%=,:~/-]*)")
FIELDS = {"Bash": ["command"], "Read": ["file_path", "path"], "Grep": ["path", "pattern"], "Glob": ["path", "pattern"],
          "Write": ["file_path"], "Edit": ["file_path"], "MultiEdit": ["file_path"], "NotebookEdit": ["notebook_path"],
          "WebFetch": ["url"], "WebSearch": ["query"]}
PATH_FIELDS = {"file_path", "path", "notebook_path"}


def allowed_roots(run_dir, init_cwds):
    if A.executor == "container":
        return ["/workspace", "/tmp", "/home/evaluser"] + SYS_DIRS
    home = os.path.expanduser("~")
    sb = os.path.join(run_dir, "sandbox")
    roots = {sb, os.path.realpath(sb), "/tmp"} | set(init_cwds)
    roots |= {os.path.join(home, x) for x in (".claude", ".claude.json", ".codex", ".aws")}
    return sorted(roots) + SYS_DIRS


def outside(p, roots):
    p = os.path.normpath(p)
    return not any(p == r or p.startswith(r.rstrip("/") + "/") for r in roots)


def check_value(tool, field, val, roots):
    low = val.lower()
    if "hidden" in low:
        return "hidden"
    if "grimoires/loa/evals/ablation-2.0" in val:
        return "suite_path"
    if "0xhoneyjar/loa" in low:
        return "repo_name"
    if tool == "Bash" and GIT_HIST.search(val):
        return "git_history"
    cands = []
    if field in PATH_FIELDS or (tool == "Glob" and field == "pattern"):
        if val.startswith("/") and not val.startswith("//"):
            cands.append(val)
    elif tool == "Bash":
        for w in ABS_WORD.findall(val):
            if w.startswith("//") or re.match(r"^/[^/]+/$", w):
                continue
            cands.append(w)
    for c in cands:
        if outside(c, roots):
            return "outside_path"
    return None


def transcripts(run_dir):
    d = os.path.join(run_dir, "transcripts")
    if not os.path.isdir(d):
        return []
    files = []
    for n in os.listdir(d):
        m = re.match(r"^events-(.+)\.jsonl$", n)
        p = os.path.join(d, n)
        if m and os.path.isfile(p) and not os.path.islink(p):
            files.append((m.group(1), p))
    rank = lambda lbl: (PHASE_ORDER.index(lbl) if lbl in PHASE_ORDER else len(PHASE_ORDER), lbl)
    return sorted(files, key=lambda x: rank(x[0]))


def tool_uses(ev):
    if not isinstance(ev, dict) or ev.get("type") != "assistant":
        return
    content = (ev.get("message") or {}).get("content") if isinstance(ev.get("message"), dict) else None
    for blk in content or []:
        if isinstance(blk, dict) and blk.get("type") == "tool_use" and isinstance(blk.get("input"), dict):
            yield blk.get("name") or "", blk["input"]


def contamination(run_dir):
    files = transcripts(run_dir)
    events, cwds = [], set()
    for label, p in files:
        rows = []
        for i, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if isinstance(ev, dict) and ev.get("type") == "system" and isinstance(ev.get("cwd"), str):
                if ev["cwd"].startswith("/"):
                    cwds.add(ev["cwd"])
            rows.append((i, ev))
        events.append((label, rows))
    roots = allowed_roots(run_dir, cwds)
    for label, rows in events:
        for i, ev in rows:
            for tool, inp in tool_uses(ev):
                for field in FIELDS.get(tool, []):
                    val = inp.get(field)
                    if isinstance(val, str) and val:
                        hit = check_value(tool, field, val, roots)
                        if hit:
                            return {"phase": label, "pattern": hit, "excerpt_id": f"{label}:{i}"}
    return None


# ------------------------------------------------------------------ the grade
def fresh_dir(p):
    if os.path.lexists(p):
        remove_path(p)
    os.makedirs(p)


def grade(t, run_dir, frozen):
    run_dir = os.path.abspath(run_dir)
    sb = os.path.join(run_dir, "sandbox")
    if not os.path.isdir(sb) or os.path.islink(sb):
        raise GradeError(f"no sandbox/ under {run_dir}")
    if ":" in run_dir or "," in run_dir:
        raise GradeError("the run directory path must not contain ':' or ','")
    grading = os.path.join(run_dir, "grading")
    fresh_dir(grading)
    a2a = os.path.join(sb, "grimoires", "loa", "a2a", SPRINT)
    v_review = gate_verdict(os.path.join(a2a, "engineer-feedback.md"))
    v_audit = gate_verdict(os.path.join(a2a, "auditor-sprint-feedback.md"))
    if v_audit is not None:
        verdict = {"source_file": "auditor-sprint-feedback.md", "value": v_audit}
    elif v_review is not None:
        verdict = {"source_file": "engineer-feedback.md", "value": v_review}
    else:
        rv = review_md_verdict(os.path.join(sb, "review.md"))
        verdict = {"source_file": "review.md", "value": rv} if rv else None
    g = {"schema_version": 1, "grader_version": GRADER_VERSION, "task_id": t.id, "task_type": t.type,
         "suite_frozen": frozen, "executor_mode": A.executor,
         "image": A.image if A.executor == "container" else None, "snapshots_graded": [],
         "hidden_tests": None, "structural": None, "regressions": None, "snapshot_tests": None,
         "recall": None, "false_positives": None, "verdict": verdict,
         "verdicts": {"review": v_review, "audit": v_audit},
         "verdict_accuracy": None, "verdict_accuracy_per_gate": {"review": None, "audit": None},
         "diff_lines": None, "files_changed": None, "symlinks_dropped": 0, "contaminated": None}
    acc = {"review": None, "audit": None}
    SNAPSHOT_LINKS_DROPPED[0] = 0
    if t.build:
        docker_ready()
        final = os.path.join(grading, "final")
        g["symlinks_dropped"] = copy_tree(sb, final, EXCLUDE_TOP)
        g["diff_lines"], g["files_changed"] = churn(t.fixture, final)
        prepare(t, final)
        g["snapshots_graded"].append("final")
        # refactor (DEC-0401, AC-5.3; Sprint 259 MEDIUM-1): the structural check is the
        # hidden assertion and the fixture suite (test_command) the regression check
        refactor = t.type == "refactor"
        if refactor:
            hcmd, hstatic, rcmd = structural_command(t), t.structural_cases, t.test_command
        else:
            hcmd, hstatic, rcmd = t.test_command, t.static_cases, t.regression_command
        res = run_suite(final, hcmd, hstatic)
        g["hidden_tests"] = summary(res)
        rb = rf = None
        if rcmd is not None:
            base_tree = os.path.join(grading, "base")
            copy_tree(t.fixture, base_tree)
            prepare(t, base_tree)
            rb = run_suite(base_tree, rcmd)
            rf = run_suite(final, rcmd)
            g["regressions"] = regressions(rb, rf)
        if refactor:
            st = summary(res)
            st.pop("timed_out")
            st.pop("rc")
            st.update(suite_green_base=all_pass(rb), suite_green_final=all_pass(rf))
            g["structural"] = st
        idx = read_json(os.path.join(run_dir, "snapshots", "index.json"))
        idx = idx if isinstance(idx, dict) else {}
        gates = {}
        if v_review is not None:
            gates["review"] = "implement"
        if v_audit is not None:
            gates["audit"] = "fix1" if idx.get("fix1") else "implement"
        snap_res = {}
        for label in ("implement", "fix1"):
            if label not in gates.values():
                continue
            tree = os.path.join(grading, label)
            if not extract_snapshot(run_dir, label, idx.get(label), tree):
                continue
            prepare(t, tree)
            sr = run_suite(tree, hcmd, hstatic)
            ok = all_pass(sr)
            if refactor:   # the gate read a tree that must keep the suite green too
                ok = ok and all_pass(run_suite(tree, t.test_command))
            snap_res[label] = (sr, ok)
            g["snapshots_graded"].append(label)
        g["symlinks_dropped"] += SNAPSHOT_LINKS_DROPPED[0]
        if snap_res:
            g["snapshot_tests"] = {k: {"passed": v["passed"], "total": v["total"]} for k, (v, _ok) in snap_res.items()}
        for gate, v in (("review", v_review), ("audit", v_audit)):
            if v is None or gates.get(gate) not in snap_res:
                continue
            ok = snap_res[gates[gate]][1]
            acc[gate] = (v == "APPROVED" and ok) or (v == "CHANGES_REQUIRED" and not ok)
    else:
        if os.path.isdir(os.path.join(sb, "pr")) and not os.path.islink(os.path.join(sb, "pr")):
            g["symlinks_dropped"] = copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
        g["recall"], g["false_positives"] = grade_recall(t, run_dir, grading)
        key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
        for gate, v in (("review", v_review), ("audit", v_audit)):
            if v is not None:
                acc[gate] = (v == "CHANGES_REQUIRED") == key_cr and v in ("APPROVED", "CHANGES_REQUIRED")
    g["verdict_accuracy_per_gate"] = acc
    g["verdict_accuracy"] = acc["audit"] if acc["audit"] is not None else acc["review"]
    g["contaminated"] = contamination(run_dir)
    return g


def structural_command(t):
    dest = t.structural
    if dest.endswith(".bats"):
        return ["bats", dest]
    if dest.endswith(".py"):
        return ["python3", "-m", "pytest", "-q", dest]
    return [t.test_command[0], dest]


def write_grade(g, out):
    text = json.dumps(g, indent=2) + "\n"
    d = os.path.dirname(os.path.abspath(out))
    os.makedirs(d, exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, out)
    return text


# ------------------------------------------------------------------ self-check
def synth_run(t, mode, root):
    rd = os.path.join(root, f"run-{mode}")
    sb = os.path.join(rd, "sandbox")
    os.makedirs(sb)
    if t.build:
        copy_tree(t.fixture, sb)
        if mode == "reference":
            if not t.reference_patch or not os.path.isfile(t.reference_patch):
                raise GradeError("self-check reference needs hidden/reference.patch (task.yaml reference_patch)")
            p = subprocess.run(["patch", "-p1", "--batch", "--forward", "--no-backup-if-mismatch", "-s", "-i",
                                t.reference_patch], cwd=sb, capture_output=True, text=True)
            if p.returncode != 0:
                raise GradeError("reference.patch does not apply to the fixture: " + (p.stdout + p.stderr).strip()[:300])
        return rd
    pr = resolve_pr_fixture(t)
    copy_tree(pr, os.path.join(sb, "pr"))
    lines = []
    if mode == "reference":
        for d in t.key.get("defects") or []:
            for s in (d.get("anchors") or [d.get("anchor_line")]):
                lines.append(f"- head/{d['file']}:{s}")
    elif mode == "noisy":
        head = os.path.join(sb, "pr", "head")
        for r, ds, fs in os.walk(head):
            ds.sort()
            for f in sorted(fs):
                p = os.path.join(r, f)
                if os.path.islink(p):
                    continue
                n = len(open(p, "rb").read().splitlines())
                rel = os.path.relpath(p, head)
                lines.extend(f"- head/{rel}:{i}" for i in range(1, n + 1))
    with open(os.path.join(sb, "review.md"), "w", encoding="utf-8") as f:
        f.write("# Findings\n\n" + "".join(l + "\n" for l in lines))
    return rd


def self_check(t, mode, frozen):
    if mode == "noisy" and t.build:
        raise GradeError("--self-check noisy applies to review-catch tasks only")
    root = tempfile.mkdtemp(prefix="selfcheck.", dir=SCRATCH)
    g = grade(t, synth_run(t, mode, root), frozen)
    ok, ev = False, ""
    if t.build:
        # hidden_tests is the structural check for refactor (MEDIUM-1); green = all_pass's
        # rule on the summary (every case, parsed, exit 0, no timeout: MEDIUM-3)
        h, r = g["hidden_tests"], g["regressions"]
        h_green = (h["passed"] >= h["total"] and not h["failed_names"] and not h["parse_error"]
                   and h["rc"] == 0 and not h["timed_out"])
        f = None if r is None else r["final"]
        suite_green = f is None or (f["passed"] >= f["total"] and f["rc"] == 0 and not f["timed_out"] and not r["parse_error"])
        if t.type == "refactor":
            ev = f"structural {h['passed']}/{h['total']}, suite {'green' if suite_green else 'red'}"
        else:
            ev = f"hidden {h['passed']}/{h['total']}" + ("" if f is None else f", fixture suite {f['passed']}/{f['total']}")
        if mode == "base":
            ok = h["passed"] < h["total"] and suite_green
        else:
            ok = h_green and suite_green
    else:
        rc = g["recall"]
        ev = f"recall {rc['recall']} ({rc['defects_caught']}/{rc['defects_seeded']}), false_positives {g['false_positives']}"
        if mode == "base":
            ok = rc["defects_caught"] == 0 and (rc["recall"] in (0, 0.0, None))
        elif mode == "reference":
            ok = rc["defects_seeded"] > 0 and rc["recall"] == 1.0
        else:
            gr = grade(t, synth_run(t, "reference", root), frozen)
            ev += f" vs reference {gr['false_positives']}"
            ok = g["false_positives"] > gr["false_positives"]
    return ok, ev, g


# ------------------------------------------------------------------ main
def main():
    if A.self_check:
        if not A.task_yaml or not os.path.isfile(A.task_yaml):
            raise GradeError("--self-check needs --task-yaml <task.yaml>")
        tdir = os.path.dirname(os.path.abspath(A.task_yaml))
        suite_root = os.path.abspath(A.suite_root) if A.suite_root else os.path.dirname(os.path.dirname(tdir))
        t = load_task(A.task_yaml, suite_root)
        if t.id != os.path.basename(tdir):
            raise GradeError(f"task id {t.id!r} is not its directory name")
        frozen = freeze_check(suite_root)
        ok, ev, g = self_check(t, A.self_check, frozen)
        line = f"self-check {A.self_check} {t.id}: {'PASS' if ok else 'FAIL'} {ev}"
        print(line)
        if A.json:
            print(json.dumps({"mode": A.self_check, "task_id": t.id, "result": "PASS" if ok else "FAIL",
                              "evidence": ev, "grade": g}, indent=2))
        return 0 if ok else 1
    if not A.run_dir or not A.task_id:
        raise GradeError("usage: ablation-grade.sh <run-dir> <task-id> [options] (see --help)")
    if not re.match(r"^[a-z0-9][a-z0-9-]{0,63}$", A.task_id):
        raise GradeError(f"invalid task id: {A.task_id}")
    if not os.path.isdir(A.run_dir):
        raise GradeError(f"run directory not found: {A.run_dir}")
    suite_root = os.path.abspath(A.suite_root or os.path.join(REPO_ROOT, "grimoires", "loa", "evals", "ablation-2.0"))
    ty = os.path.join(suite_root, A.tasks_dir or "tasks", A.task_id, "task.yaml")
    if not os.path.isfile(ty):
        raise GradeError(f"task not found: {ty}")
    t = load_task(ty, suite_root)
    if t.id != A.task_id:
        raise GradeError(f"task.yaml id {t.id!r} differs from {A.task_id!r}")
    frozen = freeze_check(suite_root)
    g = grade(t, A.run_dir, frozen)
    out = A.out or os.path.join(os.path.abspath(A.run_dir), "grade.json")
    text = write_grade(g, out)
    if A.json:
        sys.stdout.write(text)
    else:
        h = g["hidden_tests"]
        part = (f"hidden {h['passed']}/{h['total']}" if h else
                f"recall {g['recall']['recall']} false_positives {g['false_positives']}")
        print(f"graded {t.id}: {part}; verdict_accuracy {g['verdict_accuracy']}; "
              f"contaminated {g['contaminated']['pattern'] if g['contaminated'] else 'no'} → {out}")
    return 0


try:
    rc = main()
except GradeError as e:
    print(f"ablation-grade: {e}", file=sys.stderr)
    rc = 2
except Exception as e:  # an unexpected shape is an error (2), never a self-check FAIL (1)
    print(f"ablation-grade: internal error: {type(e).__name__}: {e}", file=sys.stderr)
    rc = 2
finally:
    try:
        remove_path(SCRATCH)
    except OSError:
        pass
sys.exit(rc)
PY
