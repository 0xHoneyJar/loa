"""seed_tasks.py — the engine behind seed-bugfix-tasks.sh and seed-refactor-tasks.sh.

cycle-130 Sprint 259 Tasks 2.2 / 2.3 (SDD §5.14). Run only through the two
wrappers (they pass --repo-default and --no-secrets); the usage, options, output
lines and exit codes are documented in the wrappers' header blocks.

Stdlib only; run as `python3 -I`. Every git call is an argument vector (no
shell), every path read from history is checked before it touches the disk, and
a task is built in a private temporary directory and moved into place only after
its proof passed and the no-secrets scan came back clean.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import site
import subprocess
import sys
import tempfile

MOUNT_OWNED = (".claude", "CLAUDE.md", ".loa.config.yaml", "grimoires", ".run")
DEFAULT_PATHS = "tools,evals/harness,evals/graders,tests/unit,evals/tests"
SUBJECT = {"bugfix": re.compile(r"^(fix|bug)"), "refactor": re.compile(r"^(refactor|chore|style|perf)")}
TYPE = {"bugfix": "bug-fix", "refactor": "refactor"}
ID_PREFIX = {"bugfix": "bugfix", "refactor": "refactor"}
INFRA_ROOT_FILES = ("pytest.ini", "pyproject.toml", "setup.cfg", "tox.ini")
CUTOFF = "2026-08-01"
RUN_TIMEOUT = 120
MAX_COVERING_TESTS = 20


class Usage(Exception):
    pass


def out(line):
    print(line, flush=True)


# ---------------------------------------------------------------- git helpers
def git(repo, *args, binary=False):
    cmd = ["git", "-C", repo, "-c", "core.quotepath=off", "-c", "diff.noprefix=false", *args]
    p = subprocess.run(cmd, capture_output=True, env=_git_env())
    if p.returncode != 0:
        raise RuntimeError(f"git {' '.join(args[:2])} failed: {p.stderr.decode('utf-8', 'replace').strip()}")
    return p.stdout if binary else p.stdout.decode("utf-8", "replace")


def _git_env():
    env = {k: v for k, v in os.environ.items() if k in ("PATH", "HOME", "LANG", "TMPDIR")}
    env.update({"LC_ALL": "C", "GIT_CONFIG_NOSYSTEM": "1", "GIT_PAGER": "cat", "GIT_EXTERNAL_DIFF": ""})
    return env


def safe_path(p):
    """A history path we are willing to write: relative, no `..`, printable, no backslash."""
    return bool(p) and not p.startswith("/") and ".." not in p.split("/") and "\\" not in p \
        and all(c.isprintable() for c in p)


def mount_owned(p):
    return any(part in MOUNT_OWNED for part in p.split("/"))


def is_test(p):
    parts = p.split("/")
    base = parts[-1]
    return "tests" in parts[:-1] or re.fullmatch(r"test_.*\.py|.*_test\.py", base) is not None or base.endswith(".bats")


def runner_of(p):
    if p.endswith(".bats"):
        return "bats"
    if p.endswith(".py") and re.fullmatch(r"test_.*\.py|.*_test\.py", p.rsplit("/", 1)[-1]):
        return "pytest"
    return None


def under_roots(p, roots):
    return any(p == r or p.startswith(r + "/") for r in roots)


def commits_since(repo, since):
    raw = git(repo, "log", f"--since={since}", "--no-merges", "--format=%H%x1f%P%x1f%cs%x1f%s%x1e")
    for rec in raw.split("\x1e"):
        rec = rec.strip("\n")
        if not rec:
            continue
        sha, parents, date, subject = (rec.split("\x1f") + ["", "", ""])[:4]
        yield sha, parents.split(), date, subject


def changed_files(repo, parent, sha):
    raw = git(repo, "diff", "--no-renames", "--name-status", "-z", parent, sha)
    items = raw.split("\0")
    files = []
    i = 0
    while i + 1 < len(items):
        status, path = items[i], items[i + 1]
        files.append((status[:1], path))
        i += 2
    return files


def numstat(repo, parent, sha, paths=None):
    args = ["diff", "--no-renames", "--numstat", parent, sha]
    if paths:
        args += ["--", *paths]
    rows = []
    for line in git(repo, *args).splitlines():
        a, d, p = line.split("\t", 2)
        rows.append((a, d, p))
    return rows


def blob(repo, commit, path):
    """(mode, bytes) of path at commit, or None when absent."""
    ls = git(repo, "ls-tree", "-z", commit, "--", path).split("\0")[0]
    if not ls:
        return None
    meta, _ = ls.split("\t", 1)
    mode, kind, obj = meta.split()
    if kind != "blob":
        return None
    return mode, git(repo, "cat-file", "blob", obj, binary=True)


def tree_files(repo, commit, prefix=None):
    args = ["ls-tree", "-r", "-z", "--name-only", commit]
    if prefix:
        args += ["--", prefix]
    return [p for p in git(repo, *args).split("\0") if p]


# ---------------------------------------------------------------- materialise
def write_file(root, rel, data):
    if not safe_path(rel):
        raise ValueError(f"unsafe path: {rel!r}")
    dest = os.path.join(root, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as fh:
        fh.write(data)


def put_from(repo, commit, rel, root, dest_rel=None):
    b = blob(repo, commit, rel)
    if b is None:
        return False
    mode, data = b
    if mode == "120000":
        raise ValueError(f"symlink in history: {rel}")
    write_file(root, dest_rel or rel, data)
    return True


def helper_files(repo, commit, test_paths):
    """Test infrastructure the tests rely on: conftest.py up to the root, helpers in each test dir, root runner configs."""
    have = set(tree_files(repo, commit))
    found = set()
    for t in test_paths:
        d = os.path.dirname(t)
        parts = d.split("/") if d else []
        for i in range(len(parts) + 1):
            c = "/".join(parts[:i] + ["conftest.py"])
            if c in have:
                found.add(c)
        for f in have:
            if os.path.dirname(f) == d and f not in test_paths:
                base = os.path.basename(f)
                if base in ("conftest.py", "__init__.py") or base.endswith(".bash") or "helper" in base:
                    found.add(f)
    for f in INFRA_ROOT_FILES:
        if f in have:
            found.add(f)
    return sorted(found)


def sibling_files(repo, commit, sources, roots, exclude):
    """The other non-test files in each touched source file's directory (the modules it most likely imports)."""
    dirs = {os.path.dirname(p) for p in sources}
    out = []
    for f in tree_files(repo, commit):
        if os.path.dirname(f) in dirs and f not in exclude and not is_test(f) and safe_path(f) \
                and not mount_owned(f) and under_roots(f, roots):
            out.append(f)
    return sorted(out)


def counts(output, runner):
    if runner == "bats":
        passed = len(re.findall(r"^ok ", output, re.M))
        failed = len(re.findall(r"^not ok ", output, re.M))
        return passed, failed
    tail = output.strip().splitlines()[-1] if output.strip() else ""
    num = lambda w: sum(int(n) for n in re.findall(r"(\d+) " + w, tail))
    return num("passed"), num("failed") + num("errors?")


def run_tests(tree, cmd, runner):
    """Run the task's test command under env -i (plus the host's user base so a user-site pytest is found)."""
    home = tempfile.mkdtemp(prefix="seed-home.")
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "LC_ALL": "C",
           "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUSERBASE": site.getuserbase()}
    argv = list(cmd)
    if runner == "pytest":
        argv = argv[:3] + ["-p", "no:cacheprovider"] + argv[3:]
    elif runner == "bats" and os.environ.get("LOA_SEED_BATS"):
        argv[0] = os.environ["LOA_SEED_BATS"]
    try:
        p = subprocess.run(argv, cwd=tree, env=env, capture_output=True, timeout=RUN_TIMEOUT)
        text = (p.stdout + p.stderr).decode("utf-8", "replace")
        rc = p.returncode
    except subprocess.TimeoutExpired:
        text, rc = "timeout", 124
    except OSError as e:
        text, rc = f"cannot run {argv[0]}: {e}", 127
    finally:
        shutil.rmtree(home, ignore_errors=True)
    passed, failed = counts(text, runner)
    return rc, passed, failed


def apply_patch(tree, patch_file):
    if shutil.which("patch"):
        cmd = ["patch", "-s", "-p1", "--no-backup-if-mismatch", "-i", patch_file]
    else:
        cmd = ["git", "apply", "-p1", patch_file]
    return subprocess.run(cmd, cwd=tree, capture_output=True).returncode == 0


def overlay(task_dir, tree, manifest):
    for e in manifest["files"]:
        src = os.path.join(task_dir, "hidden", e["src"])
        dest = os.path.join(tree, e["dest"])
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(src, dest)


def copy_tree(src, dest):
    shutil.copytree(src, dest, symlinks=True)


# ---------------------------------------------------------------- text
def subject_rest(subject):
    m = re.match(r"^[a-z]+(\([^)]*\))?!?:\s*(.*)$", subject)
    return (m.group(2) if m else subject).strip()


def sanitise(text, stems):
    """Agent-facing text from a commit subject: no control characters, paths, file names, test names, grader words."""
    text = "".join(c if c.isprintable() else " " for c in text)
    words = []
    for w in text.split():
        if "/" in w or re.search(r"\.(py|sh|bats|js|ts|mjs|json|ya?ml|md|toml|cfg|ini|txt|patch)\b", w) \
                or re.match(r"[\W]*test_\w+", w) or "hidden" in w.lower() \
                or any(s and s.lower() in w.lower() for s in stems):
            words.append("…")
        else:
            words.append(w)
    return re.sub(r"(… ?)+", "… ", " ".join(words)).strip() or "the change"


def yq(v):
    return json.dumps(v, ensure_ascii=False)


def task_yaml(tid, mode, source, criterion, success, test_cmd, ref_patch, protected, suite_version):
    src = "{" + ", ".join(f"{k}: {yq(v) if not isinstance(v, dict) else '{' + ', '.join(f'{a}: {b}' for a, b in v.items()) + '}'}"
                          for k, v in source.items()) + "}"
    lines = [
        f"id: {tid}",
        "schema_version: 1",
        f"type: {TYPE[mode]}",
        f"source: {src}",
        f"post_cutoff: {'true' if source['date'] >= CUTOFF else 'false'}",
        f"fixture: tasks/{tid}/fixture",
        f"criterion: {yq(criterion)}",
        f"success_criterion: {yq(success)}",
        f"test_command: {yq(test_cmd)}",
        "regression_command: null",
        f"reference_patch: {ref_patch}",
        f"grader_protected: {yq(protected)}",
        "structural_check: null",
        "bounds: {max_turns: {}, timeout_min: {}}",
        "review_catch: null",
        f"suite_version: {suite_version}",
    ]
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- selection
def classify(mode, repo, sha, parents, roots):
    """('candidate', files) | ('refused', path) | ('skipped', reason)."""
    if len(parents) != 1:
        return "skipped", "not a single-parent commit"
    files = changed_files(repo, parents[0], sha)
    for _, p in files:
        if not safe_path(p):
            return "refused", "unsafe path " + json.dumps(p)
    for _, p in files:
        if mount_owned(p):
            return "refused", p
    for _, p in files:
        if not under_roots(p, roots):
            return "skipped", f"outside the allowed roots: {p}"
    for a, d, p in numstat(repo, parents[0], sha):
        if a == "-" or d == "-":
            return "skipped", f"binary change: {p}"
    tests = [p for _, p in files if is_test(p)]
    sources = [p for _, p in files if not is_test(p)]
    if mode == "bugfix":
        if not tests:
            return "skipped", "no test file touched"
        if not sources:
            return "skipped", "no source file touched"
        added_or_modified = [p for s, p in files if is_test(p) and s in "AM"]
        runners = {runner_of(p) for p in added_or_modified} - {None}
        if not runners:
            return "skipped", "no runnable test file (test_*.py, *_test.py, *.bats) added or changed"
        if len(runners) > 1:
            return "skipped", "mixed test runners (pytest and bats)"
    else:
        if tests:
            return "skipped", f"touches a test file: {tests[0]}"
        if len(sources) < 2:
            return "skipped", f"touches {len(sources)} source file(s), want at least 2"
    return "candidate", files


def next_id(tasks_dir, prefix, taken):
    n = 1
    while True:
        tid = f"{prefix}-{n:02d}"
        if tid not in taken and not os.path.exists(os.path.join(tasks_dir, tid)):
            taken.add(tid)
            return tid
        n += 1


def covering_tests(repo, parent, sources, roots):
    """Test files at parent (under the roots) that name a touched source file."""
    names = set()
    for s in sources:
        base = os.path.basename(s)
        names.add(base)
        if base.endswith(".py"):
            names.add(base[:-3])
    pats = [re.compile(r"(?<![A-Za-z0-9_])" + re.escape(n) + r"(?![A-Za-z0-9_])") for n in sorted(names)]
    hits = []
    for r in roots:
        for f in tree_files(repo, parent, r):
            if not is_test(f) or runner_of(f) is None or not safe_path(f) or mount_owned(f):
                continue
            b = blob(repo, parent, f)
            if b is None or b[0] == "120000":
                continue
            text = b[1].decode("utf-8", "replace")
            if any(p.search(text) for p in pats):
                hits.append(f)
    return sorted(set(hits))[:MAX_COVERING_TESTS]


def test_dirs(paths):
    return sorted({os.path.dirname(p) or "." for p in paths})


# ---------------------------------------------------------------- build one task
def build_bugfix(repo, sha, parent, date, subject, files, tid, stage, no_secrets, roots):
    tdir = os.path.join(stage, tid)
    fx = os.path.join(tdir, "fixture")
    os.makedirs(fx)
    tests_am = [p for s, p in files if is_test(p) and s in "AM"]
    sources = [p for s, p in files if not is_test(p)]
    runner = {runner_of(p) for p in tests_am} - {None}
    runner = runner.pop()
    for p in sources:
        put_from(repo, parent, p, fx)
    for p in sibling_files(repo, parent, sources, roots, set(sources) | set(tests_am)):
        put_from(repo, parent, p, fx)
    for p in tests_am:
        put_from(repo, parent, p, fx)          # the base version of a changed test (absent when added)
    protected = [h for h in helper_files(repo, parent, tests_am) if h not in tests_am and h not in sources]
    for h in protected:
        put_from(repo, parent, h, fx)
    hidden = os.path.join(tdir, "hidden")
    manifest = {"files": []}
    for p in tests_am:
        put_from(repo, sha, p, hidden, "tests/" + p)
        manifest["files"].append({"src": "tests/" + p, "dest": p})
    write_file(hidden, "manifest.json", (json.dumps(manifest) + "\n").encode())
    diff = git(repo, "diff", "--no-color", "--no-ext-diff", "--no-renames", "--src-prefix=a/", "--dst-prefix=b/",
               parent, sha, "--", *sources, binary=True)
    write_file(hidden, "reference.patch", diff)
    runnable = [p for p in tests_am if runner_of(p)]
    test_cmd = (["python3", "-m", "pytest", "-q"] if runner == "pytest" else ["bats"]) + test_dirs(runnable)

    # proof: red at base, green at reference (hidden tests overlaid on both)
    work = tempfile.mkdtemp(prefix="seed-proof.")
    try:
        base, ref = os.path.join(work, "base"), os.path.join(work, "ref")
        copy_tree(fx, base)
        overlay(tdir, base, manifest)
        rc_b, pass_b, fail_b = run_tests(base, test_cmd, runner)
        copy_tree(fx, ref)
        if not apply_patch(ref, os.path.join(hidden, "reference.patch")):
            return None, "the reference patch does not apply to the fixture"
        overlay(tdir, ref, manifest)
        rc_r, pass_r, fail_r = run_tests(ref, test_cmd, runner)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if rc_b == 0 or fail_b < 1:
        return None, f"not red at base (exit {rc_b}, {fail_b} failed, {pass_b} passed)"
    if rc_r != 0 or fail_r > 0 or pass_r < 1:
        return None, f"not green at reference (exit {rc_r}, {fail_r} failed, {pass_r} passed)"
    proof = f"red {fail_b} failed / green {pass_r} passed"

    stems = [os.path.splitext(os.path.basename(p))[0] for p in tests_am]
    rest = sanitise(subject_rest(subject), stems)
    criterion = f"the behaviour this change describes holds: {rest}; the checks for it pass and the existing behaviour is unchanged"
    hidden_list = ", ".join("hidden/tests/" + p for p in runnable)
    success = (f"{hidden_list} (overlaid at {', '.join(runnable)}) passes {pass_r} of {pass_r} under {' '.join(test_cmd)}; "
               f"red at base ({fail_b} failed), green with hidden/reference.patch")
    source = {"kind": "loa-history", "fix_commit": sha, "base_commit": parent, "date": date}
    write_file(tdir, "task.yaml", task_yaml(tid, "bugfix", source, criterion, success, test_cmd,
                                           "hidden/reference.patch", protected, SUITE_VERSION).encode())
    task_md = (f"# Task: {rest}\n\n"
               f"**Bug (observed):** with the code as it is, {fail_b} of {fail_b + pass_b} checks for this behaviour fail "
               f"when the test command below runs.\n\n"
               f"**Expected:** {rest}. Every check passes and behaviour elsewhere is unchanged.\n\n"
               f"Fix the bug in place and add a regression test of your own. Run the tests with `{' '.join(test_cmd)}`.\n")
    write_file(tdir, "TASK.md", task_md.encode())
    if not secrets_clean(no_secrets, tdir):
        return "secret", "a secret pattern in the materialised task"
    return tdir, proof


def build_refactor(repo, sha, parent, date, subject, files, tid, stage, no_secrets, roots):
    sources = [p for s, p in files if not is_test(p)]
    tests = covering_tests(repo, parent, sources, roots)
    runners = {runner_of(t) for t in tests}
    if not tests:
        return "skip", "no test at the parent names a touched file"
    if len(runners) > 1:
        return "skip", "the covering tests mix pytest and bats"
    runner = runners.pop()
    tdir = os.path.join(stage, tid)
    fx = os.path.join(tdir, "fixture")
    os.makedirs(fx)
    for p in sources:
        put_from(repo, parent, p, fx)
    for p in sibling_files(repo, parent, sources, roots, set(sources) | set(tests)):
        put_from(repo, parent, p, fx)
    for t in tests:
        put_from(repo, parent, t, fx)
    protected = [h for h in helper_files(repo, parent, tests) if h not in tests and h not in sources]
    for h in protected:
        put_from(repo, parent, h, fx)
    hidden = os.path.join(tdir, "hidden")
    diff = git(repo, "diff", "--no-color", "--no-ext-diff", "--no-renames", "--src-prefix=a/", "--dst-prefix=b/",
               parent, sha, binary=True)
    write_file(hidden, "reference.patch", diff)
    write_file(hidden, "manifest.json", b'{"files": []}\n')
    test_cmd = (["python3", "-m", "pytest", "-q"] if runner == "pytest" else ["bats"]) + test_dirs(tests)

    work = tempfile.mkdtemp(prefix="seed-proof.")
    try:
        base, ref = os.path.join(work, "base"), os.path.join(work, "ref")
        copy_tree(fx, base)
        rc_b, pass_b, fail_b = run_tests(base, test_cmd, runner)
        copy_tree(fx, ref)
        if not apply_patch(ref, os.path.join(hidden, "reference.patch")):
            return None, "the reference patch does not apply to the fixture"
        rc_r, pass_r, fail_r = run_tests(ref, test_cmd, runner)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if rc_b != 0 or fail_b > 0 or pass_b < 1:
        return None, f"suite not green at base (exit {rc_b}, {fail_b} failed, {pass_b} passed)"
    if rc_r != 0 or fail_r > 0 or pass_r < 1:
        return None, f"suite not green at reference (exit {rc_r}, {fail_r} failed, {pass_r} passed)"
    proof = f"green at base ({pass_b} passed) / green at reference ({pass_r} passed)"

    rows = numstat(repo, parent, sha)
    churn = {"files": len(rows), "insertions": sum(int(a) for a, _, _ in rows), "deletions": sum(int(d) for _, d, _ in rows)}
    rest = sanitise(subject_rest(subject), [])
    criterion = f"the structure this change describes is in place: {rest}; the existing suite stays green without edits"
    success = (f"structural check (to be authored under hidden/structural/) red at base and green with hidden/reference.patch; "
               f"{' '.join(test_cmd)} passes {pass_b} of {pass_b} at base and {pass_r} of {pass_r} at reference")
    source = {"kind": "loa-history", "fix_commit": sha, "base_commit": parent, "date": date, "churn": churn}
    write_file(tdir, "task.yaml", task_yaml(tid, "refactor", source, criterion, success, test_cmd,
                                           "hidden/reference.patch", protected, SUITE_VERSION).encode())
    task_md = (f"# Task: {rest}\n\n"
               f"**Refactor:** {rest}.\n\n"
               f"**Unchanged behaviour:** the existing suite must stay green without edits. Run it with `{' '.join(test_cmd)}`.\n")
    write_file(tdir, "TASK.md", task_md.encode())
    if not secrets_clean(no_secrets, tdir):
        return "secret", "a secret pattern in the materialised task"
    return tdir, proof + "\t" + json.dumps(churn)


def secrets_clean(no_secrets, tdir):
    if not no_secrets:
        return True
    p = subprocess.run(["bash", no_secrets, tdir], capture_output=True)
    return p.returncode == 0


# ---------------------------------------------------------------- main
SUITE_VERSION = 1


def parse(argv):
    ap = argparse.ArgumentParser(prog="seed-tasks", add_help=False)
    ap.add_argument("mode", choices=("bugfix", "refactor"))
    ap.add_argument("--repo-default", required=True)
    ap.add_argument("--no-secrets", default="")
    ap.add_argument("--since", required=True)
    ap.add_argument("--select", type=int, default=4)
    ap.add_argument("--out", required=True)
    ap.add_argument("--repo")
    ap.add_argument("--paths", default=DEFAULT_PATHS)
    ap.add_argument("--suite-version", type=int, default=1)
    ap.add_argument("--dry-run", action="store_true")
    try:
        a = ap.parse_args(argv)
    except SystemExit:
        raise Usage("bad arguments (see --help)")
    try:
        datetime.date.fromisoformat(a.since)
    except ValueError:
        raise Usage(f"--since must be YYYY-MM-DD, got {a.since!r}")
    if a.select < 1:
        raise Usage("--select must be at least 1")
    if a.suite_version < 1:
        raise Usage("--suite-version must be at least 1")
    a.repo = a.repo or a.repo_default
    if subprocess.run(["git", "-C", a.repo, "rev-parse", "--git-dir"], capture_output=True).returncode != 0:
        raise Usage(f"not a git repository: {a.repo}")
    roots = [r.strip().strip("/") for r in a.paths.split(",") if r.strip().strip("/")]
    if not roots or any(not safe_path(r) or mount_owned(r) for r in roots):
        raise Usage(f"--paths must be relative roots outside the mount-owned paths: {a.paths!r}")
    a.roots = roots
    return a


def main(argv):
    global SUITE_VERSION
    try:
        a = parse(argv)
    except Usage as e:
        print(f"seed-{a_mode(argv)}: {e}", file=sys.stderr)
        return 2
    SUITE_VERSION = a.suite_version
    name = f"seed-{a.mode}"
    cands, refused, skipped = [], 0, 0
    for sha, parents, date, subject in commits_since(a.repo, a.since):
        if not SUBJECT[a.mode].match(subject):
            continue
        verdict, detail = classify(a.mode, a.repo, sha, parents, a.roots)
        if verdict == "refused":
            refused += 1
            out(f"refused {sha[:12]}: {detail}")
        elif verdict == "skipped":
            skipped += 1
            out(f"skipped {sha[:12]}: {detail}")
        else:
            cands.append((sha, parents[0], date, subject, detail))
            out(f"candidate {sha[:12]} {date} {''.join(c if c.isprintable() else ' ' for c in subject)}")
    selected = cands[: a.select]
    if a.dry_run:
        out(f"{name}: {len(cands)} candidate(s), {refused} refused, {skipped} skipped; dry run, nothing written")
        return 0
    tasks_dir = os.path.join(a.out, "tasks")
    stage = tempfile.mkdtemp(prefix="seed-stage.")
    written = failed = 0
    taken = set()
    try:
        for sha, parent, date, subject, files in selected:
            tid = next_id(tasks_dir, ID_PREFIX[a.mode], taken)
            try:
                if a.mode == "bugfix":
                    tdir, info = build_bugfix(a.repo, sha, parent, date, subject, files, tid, stage, a.no_secrets, a.roots)
                else:
                    tdir, info = build_refactor(a.repo, sha, parent, date, subject, files, tid, stage, a.no_secrets, a.roots)
            except (ValueError, RuntimeError, OSError) as e:
                tdir, info = None, str(e)
            if tdir == "secret":
                refused += 1
                out(f"refused {sha[:12]}: {info}")
                taken.discard(tid)
                continue
            if tdir == "skip":
                skipped += 1
                out(f"skipped {sha[:12]}: {info}")
                taken.discard(tid)
                continue
            if tdir is None:
                failed += 1
                out(f"proof-failed {sha[:12]}: {info}")
                taken.discard(tid)
                continue
            os.makedirs(tasks_dir, exist_ok=True)
            shutil.move(tdir, os.path.join(tasks_dir, tid))
            written += 1
            if a.mode == "bugfix":
                out(f"proof {tid} {sha[:12]}: {info}")
            else:
                proof, churn = info.split("\t")
                c = json.loads(churn)
                out(f"proof {tid} {sha[:12]}: {proof}")
                out(f"churn {tid}: files {c['files']}, insertions {c['insertions']}, deletions {c['deletions']}")
                out(f"todo {tid}: author the structural check under hidden/structural/, list it in hidden/manifest.json "
                    f"and set structural_check (validate-suite.sh requires it for refactor)")
            out(f"wrote {os.path.join(tasks_dir, tid)}")
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    out(f"{name}: {len(cands)} candidate(s), {refused} refused, {skipped} skipped; "
        f"selected {len(selected)}, written {written}, proof failed {failed}")
    return 1 if failed else 0


def a_mode(argv):
    return argv[0] if argv and argv[0] in ("bugfix", "refactor") else "tasks"


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
