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
import fnmatch
import json
import os
import re
import shlex
import shutil
import signal
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
RUN_TIMEOUT = 120   # the proof's per-run deadline in seconds; LOA_EVAL_GRADE_TIMEOUT_S (the grader's) overrides it, see parse()
MAX_COVERING_TESTS = 20
RUNNERS = ("pytest", "bats", "ts")   # the order a skip reason names them in

# The TypeScript path (seed-bugfix-tasks.sh header § TypeScript). A *.test.ts / *.spec.ts file is a `ts` test; the command
# comes from the test script of the package.json nearest above it (vitest → npx vitest run, node --test → node --test),
# both reporting TAP, which counts() and ablation-grade.sh already read. The proof needs the project's installed
# dependencies: --node-modules DIR (link_node_modules), else a ts candidate is skipped by name.
TS_TEST_RX = re.compile(r".*\.(test|spec)\.ts$")
NODE_INFRA = ("package.json", "pnpm-workspace.yaml", ".npmrc")   # carried from the test's directory up to the root
NODE_INFRA_RX = re.compile(r"^(tsconfig[^/]*\.json|vitest\.(config|workspace|setup)\.[cm]?[jt]sx?|vite\.config\.[cm]?[jt]s)$")
NODE_VALUE_FLAGS = ("--import", "--require", "-r", "--loader", "--experimental-loader", "--test-name-pattern",
                    "--test-concurrency", "--test-reporter", "--test-reporter-destination")
IMPORT_RX = re.compile(r"""(?:\bfrom\s*|\bimport\s*\(\s*|\brequire\s*\(\s*|^\s*import\s+)['"]([^'"\n]+)['"]""", re.M)
TS_EXTS = (".ts", ".tsx", ".mts", ".cts", ".js", ".mjs", ".cjs", ".json")
NM_SKIP = {".vite", ".vitest", ".cache"}   # a runner's cache directories are never linked, so what it writes lands in the proof's tree
MAX_IMPORTED = 1000
NODE_MODULES = None   # --node-modules DIR, see parse()


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
    return "tests" in parts[:-1] or re.fullmatch(r"test_.*\.py|.*_test\.py", base) is not None or base.endswith(".bats") \
        or TS_TEST_RX.match(base) is not None


def runner_of(p):
    base = p.rsplit("/", 1)[-1]
    if p.endswith(".bats"):
        return "bats"
    if p.endswith(".py") and re.fullmatch(r"test_.*\.py|.*_test\.py", base):
        return "pytest"
    if TS_TEST_RX.match(base):
        return "ts"
    return None


def runners_text(runners):
    names = [r for r in RUNNERS if r in runners]
    return " and ".join([", ".join(names[:-1]), names[-1]]) if len(names) > 1 else "".join(names)


def under_roots(p, roots):
    return any(p == r or p.startswith(r + "/") for r in roots)


def commits_since(repo, since, rev="HEAD"):
    raw = git(repo, "log", rev, f"--since={since}", "--no-merges", "--format=%H%x1f%P%x1f%cs%x1f%s%x1e")
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
def write_file(root, rel, data, mode=None):
    """Write bytes under root; a blob of git mode 100755 keeps its executable bit (a shell tool the tests run)."""
    if not safe_path(rel):
        raise ValueError(f"unsafe path: {rel!r}")
    dest = os.path.join(root, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as fh:
        fh.write(data)
    if mode == "100755":
        os.chmod(dest, 0o755)


def put_from(repo, commit, rel, root, dest_rel=None, skip_links=False):
    b = blob(repo, commit, rel)
    if b is None:
        return False
    mode, data = b
    if mode == "120000":
        if skip_links:
            return False
        raise ValueError(f"symlink in history: {rel}")
    write_file(root, dest_rel or rel, data, mode)
    return True


def helper_files(repo, commit, test_paths):
    """Test infrastructure the tests rely on: conftest.py up to the root, every non-test file in and below each
    test's directory (import shims, synthetic-data builders, fixtures: an agent must not be able to change what
    the hidden check runs against), root runner configs."""
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
            if (f.startswith(d + "/") if d else True) and f not in test_paths and runner_of(f) is None \
                    and safe_path(f) and not mount_owned(f):
                found.add(f)
    for f in INFRA_ROOT_FILES:
        if f in have:
            found.add(f)
    for t in test_paths:   # a ts test's node infrastructure: package.json, tsconfig*, vitest/vite configs, from its directory to the root
        if runner_of(t) != "ts":
            continue
        parts = os.path.dirname(t).split("/") if os.path.dirname(t) else []
        for i in range(len(parts) + 1):
            pre = "/".join(parts[:i] + [""])
            for f in have:
                name = f[len(pre):]
                if f.startswith(pre) and "/" not in name and (name in NODE_INFRA or NODE_INFRA_RX.match(name)):
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


def root_files(repo, commit, roots, exclude):
    """--fixture-scope roots: every file under the allowed roots at commit (the repository slice the tests
    see), minus exclude; mount-owned paths never (and symlinks are skipped by the caller: a frozen suite holds none)."""
    out = set()
    for r in roots:
        for f in tree_files(repo, commit, r):
            if f not in exclude and safe_path(f) and not mount_owned(f):
                out.add(f)
    return sorted(out)


# ---------------------------------------------------------------- the TypeScript path
def nearest_package(path, have):
    """The package.json closest above path (the package a ts test belongs to), or None."""
    parts = os.path.dirname(path).split("/") if os.path.dirname(path) else []
    for i in range(len(parts), -1, -1):
        c = "/".join(parts[:i] + ["package.json"])
        if c in have:
            return c
    return None


def read_json_blob(repo, commit, path):
    b = blob(repo, commit, path)
    if b is None or b[0] == "120000":
        return None
    try:
        v = json.loads(b[1].decode("utf-8", "replace"))
    except ValueError:
        return None
    return v if isinstance(v, dict) else None


def workspace_packages(repo, commit, have):
    """{name: directory} of the workspace packages at commit: the globs of pnpm-workspace.yaml `packages:` or of the
    root package.json `workspaces`, matched against the directories holding a package.json."""
    globs = []
    b = blob(repo, commit, "pnpm-workspace.yaml")
    if b is not None and b[0] != "120000":
        globs += re.findall(r"^\s*-\s*['\"]?([^'\"\s#!]+)", b[1].decode("utf-8", "replace"), re.M)
    ws = (read_json_blob(repo, commit, "package.json") or {}).get("workspaces")
    if isinstance(ws, dict):
        ws = ws.get("packages")
    if isinstance(ws, list):
        globs += [w for w in ws if isinstance(w, str) and not w.startswith("!")]
    out = {}
    for f in have:
        d = os.path.dirname(f)
        if os.path.basename(f) != "package.json" or not d or "node_modules" in d.split("/"):
            continue
        if any(fnmatch.fnmatchcase(d, g.strip("/")) for g in globs):
            name = (read_json_blob(repo, commit, f) or {}).get("name")
            if isinstance(name, str) and name:
                out[name] = d
    return out


def resolve_import(spec, from_dir, have, ws):
    """The repository file a static import names: a relative specifier under TypeScript's extension rules (x, x.ts,
    x.js standing for x.ts, x/index.ts), or a workspace package name (its directory, with a trailing slash). None for
    a dependency or a builtin."""
    if spec.startswith("."):
        p = os.path.normpath(os.path.join(from_dir, spec)) if from_dir else os.path.normpath(spec)
        if p == ".." or p.startswith("../"):
            return None
        stem, ext = os.path.splitext(p)
        swap = {".js": ".ts", ".mjs": ".mts", ".cjs": ".cts", ".jsx": ".tsx"}.get(ext)
        cands = [p] + ([stem + swap] if swap else []) + [p + e for e in TS_EXTS] + \
                [p + "/index" + e for e in (".ts", ".tsx", ".mts", ".js", ".mjs")]
        return next((c for c in cands if c in have), None)
    for name in sorted(ws, key=len, reverse=True):
        if spec == name or spec.startswith(name + "/"):
            return ws[name] + "/"
    return None


def imported_files(repo, parent, seeds):
    """The files the seeds (commit, path) reach through static imports, resolved against the parent tree: relative
    imports transitively, a workspace package whole (its non-test files, each followed in turn); at most MAX_IMPORTED."""
    have = set(tree_files(repo, parent))
    ws = workspace_packages(repo, parent, have)
    found, queue, scanned = set(), list(seeds), set()
    while queue and len(found) < MAX_IMPORTED:
        commit, f = queue.pop()
        if (commit, f) in scanned or not re.search(r"\.[cm]?[jt]sx?$", f):
            continue
        scanned.add((commit, f))
        b = blob(repo, commit, f)
        if b is None or b[0] == "120000":
            continue
        for spec in IMPORT_RX.findall(b[1].decode("utf-8", "replace")):
            r = resolve_import(spec, os.path.dirname(f), have, ws)
            if r is None:
                continue
            targets = [x for x in have if x.startswith(r) and not is_test(x)] if r.endswith("/") else [r]
            for t in targets:
                if t not in found and safe_path(t) and not mount_owned(t):
                    found.add(t)
                    queue.append((parent, t))
    return sorted(found)


def ts_command(repo, parent, tests):
    """The ts command's prefix from the package the tests belong to (its package.json test script at the parent):
    `node … --test …` → node --test <the script's flags> --test-reporter=tap; `vitest …` (or no script and vitest among
    the dependencies) → npx [--prefix <pkg>] vitest run --reporter=tap-flat [--root <pkg>], the package's own vitest
    (npx looks in the prefix's node_modules, never on PATH). Returns (argv, package_dir, None) or (None, None, reason)."""
    have = set(tree_files(repo, parent))
    pkgs = {nearest_package(t, have) for t in tests}
    if len(pkgs) != 1:
        return None, None, f"the changed tests belong to {len(pkgs)} packages"
    pkg = pkgs.pop()
    if pkg is None:
        return None, None, "no package.json above the changed tests"
    meta = read_json_blob(repo, parent, pkg)
    if meta is None:
        return None, None, f"{pkg} is not a JSON object"
    pdir = os.path.dirname(pkg)
    scripts = meta.get("scripts") if isinstance(meta.get("scripts"), dict) else {}
    script = scripts.get("test") if isinstance(scripts.get("test"), str) else ""
    try:
        toks = shlex.split(script)
    except ValueError:
        toks = []
    deps = {**(meta.get("dependencies") or {}), **(meta.get("devDependencies") or {})}
    if toks[:1] == ["node"] and "--test" in toks:
        flags, i = [], 1
        while i < len(toks):
            t = toks[i]
            if t in NODE_VALUE_FLAGS and i + 1 < len(toks):
                if not t.startswith("--test-reporter"):
                    flags += [t, toks[i + 1]]
                i += 2
                continue
            if t.startswith("-") and t != "--test" and not t.startswith("--test-reporter"):
                flags.append(t)
            i += 1
        return ["node", "--test", *flags, "--test-reporter=tap"], pdir, None
    if any(t == "vitest" or t.endswith("/vitest") for t in toks[:4]) or (not toks and "vitest" in deps):
        where = ["--prefix", pdir] if pdir else []
        return ["npx", *where, "vitest", "run", "--reporter=tap-flat"] + (["--root", pdir] if pdir else []), pdir, None
    return None, None, f"the test script of {pkg} is not vitest or node --test: {script!r}"


def ts_targets(argv, runnable, scope):
    """What the ts command names: roots scope the changed test files; touched scope each test directory's
    *.test.ts / *.spec.ts (a glob node --test expands itself: there is no shell) or, for vitest, the directory as a filter."""
    if scope == "roots":
        return list(runnable)
    if argv[0] == "node":
        return sorted({os.path.dirname(p) + "/*" + re.search(r"\.(test|spec)\.ts$", p).group(0) for p in runnable})
    return [d + "/" for d in test_dirs(runnable) if d != "."]


def link_node_modules(tree, nm):
    """--node-modules: give the proof's tree the installed checkout's dependencies without copying or writing them. For
    the tree root and every tree directory holding a package.json whose counterpart <checkout>/<dir>/node_modules exists,
    a real node_modules directory of symlinks to that directory's entries (caches left out, so what a runner writes lands
    in the tree); an entry that is itself a workspace package of the checkout points at the same path inside the tree."""
    checkout = os.path.dirname(nm)
    for d, dirs, files in os.walk(tree):
        dirs[:] = sorted(x for x in dirs if x != "node_modules")
        rel = os.path.relpath(d, tree)
        if rel != "." and "package.json" not in files:
            continue
        src = nm if rel == "." else os.path.join(checkout, rel, "node_modules")
        dest = os.path.join(d, "node_modules")
        if not os.path.isdir(src) or os.path.lexists(dest):
            continue
        os.mkdir(dest)
        for e in sorted(os.listdir(src)):
            if e in NM_SKIP:
                continue
            s = os.path.join(src, e)
            if e.startswith("@") and os.path.isdir(s) and not os.path.islink(s):
                os.mkdir(os.path.join(dest, e))
                for f in sorted(os.listdir(s)):
                    link_entry(os.path.join(s, f), os.path.join(dest, e, f), checkout, tree)
            else:
                link_entry(s, os.path.join(dest, e), checkout, tree)


def link_entry(src, dest, checkout, tree):
    inside = os.path.relpath(os.path.realpath(src), checkout)
    if not inside.startswith("..") and "node_modules" not in inside.split("/"):   # a workspace package: the tree's copy
        os.symlink(os.path.join(tree, inside), dest)
    else:
        os.symlink(src, dest)


def first_error(text):
    """The first line of a ts run that names what went wrong (a module not found, a bad node option, npx refusing),
    for the proof-failed reason; the empty string when there is none."""
    for rx in (r"Cannot find|canceled|bad option|npm error|is not defined|is not a function",   # the message itself
               r"ERR_[A-Z_]+|SyntaxError|ReferenceError|TypeError",                              # else its code or class
               r"\berror[:\s]"):                                                                   # else any error line
        for l in text.splitlines():
            if re.search(rx, l) and len(l.strip()) > 8:
                return "; first error: " + l.strip()[:160]
    return ""


def fixture_tests(fx):
    """Every file under the fixture's top-level tests/ (validate-suite.sh: grader_protected names each of them)."""
    out = []
    t = os.path.join(fx, "tests")
    if os.path.isdir(t) and not os.path.islink(t):
        for r, _, fs in os.walk(t):
            for f in fs:
                out.append(os.path.relpath(os.path.join(r, f), fx))
    return sorted(out)


def copy_scope(repo, parent, fx, scope, sources, roots, exclude):
    """The fixture's context files: the touched files' directory siblings (touched) or the whole roots slice (roots)."""
    if scope == "roots":
        for p in root_files(repo, parent, roots, exclude):
            put_from(repo, parent, p, fx, skip_links=True)
    else:
        for p in sibling_files(repo, parent, sources, roots, exclude):
            put_from(repo, parent, p, fx)


def counts(output, runner):
    if runner in ("bats", "ts"):   # TAP: top-level results (a nested subtest is indented, as ablation-grade.sh reads it)
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
    elif runner == "ts":   # plain output; npx never installs (a vitest missing from the tree fails by name) nor phones home
        env.update({"NO_COLOR": "1", "CI": "1", "npm_config_yes": "false", "npm_config_update_notifier": "false"})
    try:
        # its own session: at the deadline the whole group dies (bats leaves grandchildren that would
        # otherwise hold the pipe open and run the rest of the suite before the call returns)
        p = subprocess.Popen(argv, cwd=tree, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             start_new_session=True)
        try:
            out, _ = p.communicate(timeout=RUN_TIMEOUT)
            text, rc = out.decode("utf-8", "replace"), p.returncode
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            p.communicate()
            text, rc = "timeout", 124
    except OSError as e:
        text, rc = f"cannot run {argv[0]}: {e}", 127
    finally:
        shutil.rmtree(home, ignore_errors=True)
    passed, failed = counts(text, runner)
    return rc, passed, failed, text


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
def classify(mode, repo, sha, parents, roots, ignore=(), runner=None):
    """('candidate', (files, ignored)) | ('refused', path) | ('skipped', reason).
    ignore: path prefixes whose touched files are left out of the task (--ignore-paths) before any rule
    runs; runner: with a mixed candidate (--runner), the runner whose changed tests are the hidden check."""
    if len(parents) != 1:
        return "skipped", "not a single-parent commit"
    files = changed_files(repo, parents[0], sha)
    for _, p in files:
        if not safe_path(p):
            return "refused", "unsafe path " + json.dumps(p)
    ignored = [p for _, p in files if under_roots(p, ignore)]
    files = [(st, p) for st, p in files if p not in ignored]
    if not files:
        return "skipped", "every touched path is ignored"
    for _, p in files:
        if mount_owned(p):
            return "refused", p
    for _, p in files:
        if not under_roots(p, roots):
            return "skipped", f"outside the allowed roots: {p}"
    for a, d, p in numstat(repo, parents[0], sha, [p for _, p in files]):
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
            return "skipped", "no runnable test file (test_*.py, *_test.py, *.bats, *.test.ts, *.spec.ts) added or changed"
        if runner and runner not in runners:
            return "skipped", f"no {runner} test added or changed"
        if len(runners) > 1 and not runner:
            return "skipped", f"mixed test runners ({runners_text(runners)})"
    else:
        if tests:
            return "skipped", f"touches a test file: {tests[0]}"
        if len(sources) < 2:
            return "skipped", f"touches {len(sources)} source file(s), want at least 2"
    return "candidate", (files, ignored)


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
def origin_note(ignored, other_runner_tests):
    """source.origin: what the task leaves out of the commit (grader-side record; TASK.md never carries it)."""
    parts = []
    if ignored:
        parts.append("touched paths left out of the task (--ignore-paths): " + ", ".join(sorted(ignored)))
    if other_runner_tests:
        parts.append("changed tests of the other runner left at base (--runner): " + ", ".join(sorted(other_runner_tests)))
    return "; ".join(parts)


def build_bugfix(repo, sha, parent, date, subject, files, tid, stage, no_secrets, roots, scope="touched",
                 runner=None, ignored=()):
    tdir = os.path.join(stage, tid)
    fx = os.path.join(tdir, "fixture")
    os.makedirs(fx)
    tests_am = [p for s, p in files if is_test(p) and s in "AM"]
    sources = [p for s, p in files if not is_test(p)]
    # --runner: a changed test of the other runner is not a hidden test (it stays at its base version
    # wherever the fixture scope carries it); its name goes to source.origin
    other = [p for p in tests_am if runner and runner_of(p) not in (None, runner)]
    tests_am = [p for p in tests_am if p not in other]
    runner = runner or ({runner_of(p) for p in tests_am} - {None}).pop()
    runnable = [p for p in tests_am if runner_of(p)]
    if runner == "ts":
        if NODE_MODULES is None:
            return "skip", "no node_modules for the proof (--node-modules DIR)"
        runner_argv, _, why = ts_command(repo, parent, runnable)
        if why:
            return "skip", why
        test_cmd = runner_argv + ts_targets(runner_argv, runnable, scope)
    else:
        runner_argv = ["python3", "-m", "pytest", "-q"] if runner == "pytest" else ["bats"]
        # roots: the test directories hold the suite's other tests too, so the command names the changed files
        test_cmd = runner_argv + (runnable if scope == "roots" else test_dirs(runnable))
    for p in sources:
        put_from(repo, parent, p, fx)
    copy_scope(repo, parent, fx, scope, sources, roots, set(sources) | set(tests_am))
    for p in tests_am:
        put_from(repo, parent, p, fx)          # the base version of a changed test (absent when added)
    if runner == "ts":   # what the tests and the touched sources import, at both ends of the change
        seeds = [(sha, p) for p in tests_am + sources] + [(parent, p) for p in tests_am + sources]
        for p in imported_files(repo, parent, seeds):
            if p not in sources and p not in tests_am and not os.path.lexists(os.path.join(fx, p)):
                put_from(repo, parent, p, fx, skip_links=True)
    protected = [h for h in helper_files(repo, parent, tests_am) if h not in tests_am and h not in sources]
    if scope == "roots":
        protected = sorted(set(protected) | set(fixture_tests(fx)) - set(sources))
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

    # proof: red at base, green at reference (hidden tests overlaid on both)
    work = tempfile.mkdtemp(prefix="seed-proof.")
    try:
        base, ref = os.path.join(work, "base"), os.path.join(work, "ref")
        copy_tree(fx, base)
        overlay(tdir, base, manifest)
        if runner == "ts":
            link_node_modules(base, NODE_MODULES)
        rc_b, pass_b, fail_b, out_b = run_tests(base, test_cmd, runner)
        copy_tree(fx, ref)
        if not apply_patch(ref, os.path.join(hidden, "reference.patch")):
            return None, "the reference patch does not apply to the fixture"
        overlay(tdir, ref, manifest)
        if runner == "ts":
            link_node_modules(ref, NODE_MODULES)
        rc_r, pass_r, fail_r, out_r = run_tests(ref, test_cmd, runner)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if rc_b == 0 or fail_b < 1:
        return None, f"not red at base (exit {rc_b}, {fail_b} failed, {pass_b} passed)" + (first_error(out_b) if runner == "ts" else "")
    if rc_r != 0 or fail_r > 0 or pass_r < 1:
        return None, f"not green at reference (exit {rc_r}, {fail_r} failed, {pass_r} passed)" + (first_error(out_r) if runner == "ts" else "")
    proof = f"red {fail_b} failed / green {pass_r} passed"

    stems = [os.path.splitext(os.path.basename(p))[0] for p in tests_am]
    rest = sanitise(subject_rest(subject), stems)
    criterion = f"the behaviour this change describes holds: {rest}; the checks for it pass and the existing behaviour is unchanged"
    hidden_list = ", ".join("hidden/tests/" + p for p in runnable)
    success = (f"{hidden_list} (overlaid at {', '.join(runnable)}) passes {pass_r} of {pass_r} under {' '.join(test_cmd)}; "
               f"red at base ({fail_b} failed), green with hidden/reference.patch")
    source = {"kind": "loa-history", "fix_commit": sha, "base_commit": parent, "date": date}
    origin = origin_note(ignored, other)
    if origin:
        source["origin"] = origin
    write_file(tdir, "task.yaml", task_yaml(tid, "bugfix", source, criterion, success, test_cmd,
                                           "hidden/reference.patch", protected, SUITE_VERSION).encode())
    if scope == "roots":   # the brief may not name a hidden test file: the directory and the runner only
        run_line = (f"Run the tests under `{'`, `'.join(test_dirs(runnable))}` that cover the code you change, "
                    f"with `{' '.join(runner_argv)} <file>`.")
    else:
        run_line = f"Run the tests with `{' '.join(test_cmd)}`."
    task_md = (f"# Task: {rest}\n\n"
               f"**Bug (observed):** with the code as it is, {fail_b} of {fail_b + pass_b} checks for this behaviour fail "
               f"when the test command below runs.\n\n"
               f"**Expected:** {rest}. Every check passes and behaviour elsewhere is unchanged.\n\n"
               f"Fix the bug in place and add a regression test of your own. {run_line}\n")
    write_file(tdir, "TASK.md", task_md.encode())
    if not secrets_clean(no_secrets, tdir):
        return "secret", "a secret pattern in the materialised task"
    return tdir, proof


def build_refactor(repo, sha, parent, date, subject, files, tid, stage, no_secrets, roots, scope="touched",
                   runner=None, ignored=()):
    sources = [p for s, p in files if not is_test(p)]
    tests = [t for t in covering_tests(repo, parent, sources, roots) if runner is None or runner_of(t) == runner]
    runners = {runner_of(t) for t in tests}
    if not tests:
        return "skip", "no test at the parent names a touched file"
    if len(runners) > 1:
        return "skip", f"the covering tests mix {runners_text(runners)}"
    runner = runners.pop()
    if runner == "ts":
        if NODE_MODULES is None:
            return "skip", "no node_modules for the proof (--node-modules DIR)"
        runner_argv, _, why = ts_command(repo, parent, tests)
        if why:
            return "skip", why
        test_cmd = runner_argv + ts_targets(runner_argv, tests, scope)
    else:
        test_cmd = (["python3", "-m", "pytest", "-q"] if runner == "pytest" else ["bats"]) + (tests if scope == "roots" else test_dirs(tests))
    tdir = os.path.join(stage, tid)
    fx = os.path.join(tdir, "fixture")
    os.makedirs(fx)
    for p in sources:
        put_from(repo, parent, p, fx)
    copy_scope(repo, parent, fx, scope, sources, roots, set(sources) | set(tests))
    for t in tests:
        put_from(repo, parent, t, fx)
    if runner == "ts":
        seeds = [(parent, p) for p in tests + sources] + [(sha, p) for p in sources]
        for p in imported_files(repo, parent, seeds):
            if p not in sources and p not in tests and not os.path.lexists(os.path.join(fx, p)):
                put_from(repo, parent, p, fx, skip_links=True)
    protected = [h for h in helper_files(repo, parent, tests) if h not in tests and h not in sources]
    if scope == "roots":
        protected = sorted(set(protected) | set(fixture_tests(fx)) - set(sources))
    for h in protected:
        put_from(repo, parent, h, fx)
    hidden = os.path.join(tdir, "hidden")
    diff = git(repo, "diff", "--no-color", "--no-ext-diff", "--no-renames", "--src-prefix=a/", "--dst-prefix=b/",
               parent, sha, binary=True)
    write_file(hidden, "reference.patch", diff)
    write_file(hidden, "manifest.json", b'{"files": []}\n')

    work = tempfile.mkdtemp(prefix="seed-proof.")
    try:
        base, ref = os.path.join(work, "base"), os.path.join(work, "ref")
        copy_tree(fx, base)
        if runner == "ts":
            link_node_modules(base, NODE_MODULES)
        rc_b, pass_b, fail_b, out_b = run_tests(base, test_cmd, runner)
        copy_tree(fx, ref)
        if not apply_patch(ref, os.path.join(hidden, "reference.patch")):
            return None, "the reference patch does not apply to the fixture"
        if runner == "ts":
            link_node_modules(ref, NODE_MODULES)
        rc_r, pass_r, fail_r, out_r = run_tests(ref, test_cmd, runner)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if rc_b != 0 or fail_b > 0 or pass_b < 1:
        return None, f"suite not green at base (exit {rc_b}, {fail_b} failed, {pass_b} passed)" + (first_error(out_b) if runner == "ts" else "")
    if rc_r != 0 or fail_r > 0 or pass_r < 1:
        return None, f"suite not green at reference (exit {rc_r}, {fail_r} failed, {pass_r} passed)" + (first_error(out_r) if runner == "ts" else "")
    proof = f"green at base ({pass_b} passed) / green at reference ({pass_r} passed)"

    rows = numstat(repo, parent, sha)
    churn = {"files": len(rows), "insertions": sum(int(a) for a, _, _ in rows), "deletions": sum(int(d) for _, d, _ in rows)}
    rest = sanitise(subject_rest(subject), [])
    criterion = f"the structure this change describes is in place: {rest}; the existing suite stays green without edits"
    success = (f"structural check (to be authored under hidden/structural/) red at base and green with hidden/reference.patch; "
               f"{' '.join(test_cmd)} passes {pass_b} of {pass_b} at base and {pass_r} of {pass_r} at reference")
    source = {"kind": "loa-history", "fix_commit": sha, "base_commit": parent, "date": date, "churn": churn}
    origin = origin_note(ignored, [])
    if origin:
        source["origin"] = origin
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
    ap.add_argument("--rev", default="HEAD")
    ap.add_argument("--paths", default=DEFAULT_PATHS)
    ap.add_argument("--suite-version", type=int, default=1)
    ap.add_argument("--id-prefix")
    ap.add_argument("--fixture-scope", choices=("touched", "roots"), default="touched")
    ap.add_argument("--ignore-paths", default="")
    ap.add_argument("--runner", choices=RUNNERS)
    ap.add_argument("--node-modules")
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
    t = os.environ.get("LOA_EVAL_GRADE_TIMEOUT_S", "")
    if t:
        if not re.fullmatch(r"[1-9][0-9]{0,3}", t):
            raise Usage(f"LOA_EVAL_GRADE_TIMEOUT_S must be 1-9999 seconds, got {t!r}")
        global RUN_TIMEOUT
        RUN_TIMEOUT = int(t)
    a.id_prefix = a.id_prefix or ID_PREFIX[a.mode]
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,60}", a.id_prefix):
        raise Usage(f"--id-prefix must match [a-z0-9][a-z0-9-]{{0,60}}, got {a.id_prefix!r}")
    a.repo = a.repo or a.repo_default
    if subprocess.run(["git", "-C", a.repo, "rev-parse", "--git-dir"], capture_output=True).returncode != 0:
        raise Usage(f"not a git repository: {a.repo}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/~^-]{0,120}", a.rev) or a.rev.startswith("-") or \
            subprocess.run(["git", "-C", a.repo, "rev-parse", "--verify", "--quiet", a.rev + "^{commit}"],
                           capture_output=True).returncode != 0:
        raise Usage(f"--rev is not a commit of {a.repo}: {a.rev!r}")
    roots = [r.strip().strip("/") for r in a.paths.split(",") if r.strip().strip("/")]
    if not roots or any(not safe_path(r) or mount_owned(r) for r in roots):
        raise Usage(f"--paths must be relative roots outside the mount-owned paths: {a.paths!r}")
    a.roots = roots
    a.ignore = [r.strip().strip("/") for r in a.ignore_paths.split(",") if r.strip().strip("/")]
    if any(not safe_path(r) for r in a.ignore):
        raise Usage(f"--ignore-paths must be relative prefixes: {a.ignore_paths!r}")
    if a.node_modules is not None:
        nm = os.path.abspath(a.node_modules)
        if os.path.basename(nm) != "node_modules" or not os.path.isdir(nm):
            raise Usage(f"--node-modules must be an installed node_modules directory, got {a.node_modules!r}")
        a.node_modules = nm
    return a


def main(argv):
    global SUITE_VERSION, NODE_MODULES
    try:
        a = parse(argv)
    except Usage as e:
        print(f"seed-{a_mode(argv)}: {e}", file=sys.stderr)
        return 2
    SUITE_VERSION = a.suite_version
    NODE_MODULES = a.node_modules
    name = f"seed-{a.mode}"
    cands, refused, skipped = [], 0, 0
    for sha, parents, date, subject in commits_since(a.repo, a.since, a.rev):
        if not SUBJECT[a.mode].match(subject):
            continue
        verdict, detail = classify(a.mode, a.repo, sha, parents, a.roots, a.ignore, a.runner)
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
        for sha, parent, date, subject, (files, ignored) in selected:
            tid = next_id(tasks_dir, a.id_prefix, taken)
            try:
                if a.mode == "bugfix":
                    tdir, info = build_bugfix(a.repo, sha, parent, date, subject, files, tid, stage, a.no_secrets, a.roots,
                                              a.fixture_scope, a.runner, ignored)
                else:
                    tdir, info = build_refactor(a.repo, sha, parent, date, subject, files, tid, stage, a.no_secrets, a.roots,
                                                a.fixture_scope, a.runner, ignored)
            except (ValueError, RuntimeError, OSError) as e:
                tdir, info = None, str(e)
            if tdir in ("secret", "skip", None):
                # a candidate that is not written leaves nothing staged: its id is reused by the
                # next one, and a stale <stage>/<tid> would make every later build fail with EEXIST
                shutil.rmtree(os.path.join(stage, tid), ignore_errors=True)
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
