# Hunks — pr-25

The later fix changed 29 region(s) in 6 of the change's 12 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — evals/harness/ablation-grade.sh — head line 220

Head context (head/evals/harness/ablation-grade.sh, lines 208–232):

~~~~text
   208 | #    regression check), snapshot_tests {implement?,
   209 | #    fix1?: {passed, total}} (refactor: the structural check), recall (review-catch
   210 | #    {defects_seeded, defects_caught, recall, flags, missed}; else null),
   211 | #    false_positives, verdict, verdicts {review, audit}, verdict_accuracy,
   212 | #    verdict_accuracy_per_gate {review, audit}, diff_lines, files_changed,
   213 | #    symlinks_dropped, harness_files_removed, oversized_files_skipped, history_probes,
   214 | #    heredoc_interpreters (1.2.6: heredocs in Bash inputs whose operator line's command, the
   215 | #    first word after the last ; & | ( or { before << and after NAME=value assignments, by
   216 | #    basename, is python3, python3.N, python, bash, sh, node, perl or ruby; counted up to the
   217 | #    first contamination hit, like history_probes; telemetry, not a row field), contaminated}
   218 | # grader 1.2.1 (Sprint 260 calibration, DEC-0540): git history probes are telemetry; a
   219 | # one-component absolute word is a command token unless it names root, home, mnt, media or srv.
>  220 | # grader 1.2.11 (Sprint 261): 1.2.10's --import-mode=importlib is reverted (it broke the sibling-module imports hidden
   221 | # suites and fixture suites rely on: import _oracle_x, from helpers import …); instead a Python file the agent added
   222 | # (no fixture file and no hidden overlay at its path) whose basename equals a hidden overlay's or a fixture test file's
   223 | # basename is removed before any command runs (counted in grade.json colliding_tests_removed, paths beside the tree in
   224 | # grading/<label>.colliding-removed.txt): under pytest's default import mode two test modules with one basename in
   225 | # package-less directories abort collection (import file mismatch) and would grade a correct solution as failing.
   226 | # grader 1.2.10 (Sprint 261, superseded by 1.2.11): pytest ran with --import-mode=importlib.
   227 | # grader 1.2.9 (Sprint 260 audit round 2): the glob rule reads * and ? only — a [ after a one-component word
   228 | # is a regex bracket expression (two P1 commands read as contaminated under 1.2.8: grep '/home[^"]*…',
   229 | # sed 's/job\["status"\]…'; KF-046 recurrence 7) — and a quoted one-component pattern stays exempt.
   230 | # grader 1.2.8 (Sprint 260 audit round 1, DISS-C-001, C-002): the dot-directory skip applies after
   231 | # os.path.normpath (/./root/x is /root/x); an empty quoted string before a path is not a glued token
   232 | # (''/root/x); a one-component word followed by a glob metacharacter stays a candidate (/roo*, /ro?t);
~~~~

The change from head to the fix:

~~~~diff
@@ -220 +220,23 @@
-# grader 1.2.11 (Sprint 261): 1.2.10's --import-mode=importlib is reverted (it broke the sibling-module imports hidden
+# grader 1.2.13 (Sprint 261 dissent run 2 DISS-001, DISS-C-004, DISS-C-005): the removal compares pytest import
+# names, not basenames. Under the default prepend import mode a test module imports by its dotted path from its basedir
+# (the first ancestor without __init__.py), so tests/hidden/pkg/test_x.py and an agent tests/pkg/test_x.py are both
+# pkg.test_x when each pkg/ is a package: 1.2.12 kept such a file and collection still aborted. Protected modules (the
+# hidden overlay file dests, files inside directory overlays, the fixture's tests/ or test/ files) are named from the
+# overlay-or-fixture view of __init__.py files; an agent-added (unowned) collectable module is named from the grading
+# tree's real __init__.py files and removed when its name is a protected collectable module's. A narrow helper rule
+# removes an unowned non-collectable module whose stem is a protected helper's (a package-less protected .py beside a
+# protected collectable module or conftest.py, or at the root: what import _oracle_x reaches) only when its directory
+# is package-less and also holds a collectable module (the one case pytest puts it on sys.path and the agent's copy
+# can answer the protected import), and removes the unowned test modules in that directory with it (the helper alone
+# would leave their import _oracle_x an ImportError that aborts collection). Collectable means pytest's python_files: -o python_files=… or a
+# -c file visible in test_command, else the fixture root's pytest.ini, .pytest.ini, pyproject.toml
+# ([tool.pytest.ini_options]), tox.ini ([pytest]) or setup.cfg ([tool:pytest]), else test_*.py and *_test.py;
+# grade.json collision_rule {python_files, source} records the patterns used (null for review-catch).
+# grader 1.2.12 (Sprint 261 dissent DISS-001/DISS-C-001/DISS-002/DISS-C-002; superseded by 1.2.13): the 1.2.11 removal is narrowed to
+# what pytest's import file mismatch actually hits. Reserved basenames are only pytest-collectable ones (test_*.py,
+# *_test.py; never __init__.py, conftest.py or helper modules), taken from the hidden overlay files, the .py files
+# inside directory overlays (unprotected under 1.2.11) and the fixture's tests/ or test/ files. A grading-tree file is
+# removed only when its basename is reserved, it is at no owned overlay path and no fixture path, and its directory
+# has no __init__.py (pytest's default prepend mode imports only package-less test modules by bare basename). Under
+# 1.2.11 an agent's src/app/helpers.py beside a fixture tests/helpers.py was deleted and a correct solution failed.
+# grader 1.2.11 (Sprint 261, narrowed by 1.2.12): 1.2.10's --import-mode=importlib is reverted (it broke the sibling-module imports hidden
~~~~

## H02 — evals/harness/ablation-grade.sh — head line 299

Head context (head/evals/harness/ablation-grade.sh, lines 287–311):

~~~~text
   287 | # Tested by evals/tests/ablation-grade.bats (docker = evals/tests/fixtures/docker-stub.sh).
   288 | # No .claude/ code is sourced and nothing is sourced or eval'd from a variable (eval.yml
   289 | # trust boundary); hashing is Python hashlib.
   290 | # =============================================================================
   291 | set -euo pipefail
   292 | export LC_ALL=C
   293 | 
   294 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   295 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
   296 | case "${1:-}" in -h|--help) sed -n '3,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
   297 | 
   298 | exec python3 -I - "$SCRIPT_DIR" "$REPO_ROOT" "${EVAL_DOCKER_BIN:-docker}" "$@" <<'PY'
>  299 | import argparse, difflib, filecmp, json, os, re, shutil, signal, site, stat, subprocess, sys, tarfile, tempfile, threading, time
   300 | # 1.2.7 (Sprint 260 review round 2, DISS-C-002): a SIGTERM (the runner's post-run deadline) becomes SystemExit so
   301 | # the finally below removes SCRATCH; a running docker command ends at its own in-container deadline (--init forwards
   302 | # TERM; names carry this pid, so a later grade never collides)
   303 | signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))
   304 | 
   305 | GRADER_VERSION = "1.2.11"
   306 | SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
   307 | SPRINT = "sprint-1"
   308 | _t = os.environ.get("LOA_EVAL_GRADE_TIMEOUT_S", "")
   309 | TEST_TIMEOUT_S = int(_t) if re.fullmatch(r"[1-9][0-9]{0,3}", _t) else 120   # tests shorten it
   310 | KILL_AFTER_S = 10                                    # timeout --kill-after (MEDIUM-A1)
   311 | OUTER_GRACE_S = max(5, min(60, TEST_TIMEOUT_S // 2))  # the client deadline beyond T + KILL_AFTER_S
~~~~

The change from head to the fix:

~~~~diff
@@ -299 +321 @@
-import argparse, difflib, filecmp, json, os, re, shutil, signal, site, stat, subprocess, sys, tarfile, tempfile, threading, time
+import argparse, configparser, difflib, filecmp, fnmatch, json, os, re, shlex, shutil, signal, site, stat, subprocess, sys, tarfile, tempfile, threading, time, tomllib
~~~~

## H03 — evals/harness/ablation-grade.sh — head line 305

Head context (head/evals/harness/ablation-grade.sh, lines 293–317):

~~~~text
   293 | 
   294 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   295 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
   296 | case "${1:-}" in -h|--help) sed -n '3,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
   297 | 
   298 | exec python3 -I - "$SCRIPT_DIR" "$REPO_ROOT" "${EVAL_DOCKER_BIN:-docker}" "$@" <<'PY'
   299 | import argparse, difflib, filecmp, json, os, re, shutil, signal, site, stat, subprocess, sys, tarfile, tempfile, threading, time
   300 | # 1.2.7 (Sprint 260 review round 2, DISS-C-002): a SIGTERM (the runner's post-run deadline) becomes SystemExit so
   301 | # the finally below removes SCRATCH; a running docker command ends at its own in-container deadline (--init forwards
   302 | # TERM; names carry this pid, so a later grade never collides)
   303 | signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))
   304 | 
>  305 | GRADER_VERSION = "1.2.11"
   306 | SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
   307 | SPRINT = "sprint-1"
   308 | _t = os.environ.get("LOA_EVAL_GRADE_TIMEOUT_S", "")
   309 | TEST_TIMEOUT_S = int(_t) if re.fullmatch(r"[1-9][0-9]{0,3}", _t) else 120   # tests shorten it
   310 | KILL_AFTER_S = 10                                    # timeout --kill-after (MEDIUM-A1)
   311 | OUTER_GRACE_S = max(5, min(60, TEST_TIMEOUT_S // 2))  # the client deadline beyond T + KILL_AFTER_S
   312 | OUTPUT_CAP = 4 * 1024 * 1024      # captured stdout per command (MEDIUM-A1)
   313 | FILE_CAP = 16 * 1024 * 1024       # a regular file above this is not copied (MEDIUM-A3)
   314 | READ_CAP = 2 * 1024 * 1024        # verdict, citation and envelope reads (MEDIUM-A3)
   315 | NODE_FILE_CAP = 1024 * 1024       # a test file read for case order (MEDIUM-A2)
   316 | # pytest and bats load these from the tree under test (HIGH-A1); see is_harness()
   317 | HARNESS_NAMES = {"conftest.py", "pytest.ini", ".pytest.ini", "pyproject.toml", "setup.cfg", "tox.ini",
~~~~

The change from head to the fix:

~~~~diff
@@ -305 +327 @@
-GRADER_VERSION = "1.2.11"
+GRADER_VERSION = "1.2.13"
~~~~

## H04 — evals/harness/ablation-grade.sh — head lines 1071–1102

Head context (head/evals/harness/ablation-grade.sh, lines 1059–1114):

~~~~text
  1059 |             if os.path.isdir(p) and not os.path.islink(p):
  1060 |                 continue
  1061 |             if same_as_fixture(t, tree, rel):
  1062 |                 continue
  1063 |             found.append((rel, p))
  1064 |     for _rel, p in found:
  1065 |         os.unlink(p)
  1066 |     with open(tree.rstrip("/") + ".harness-removed.txt", "w", encoding="utf-8") as f:
  1067 |         f.write("".join(rel + "\n" for rel, _p in sorted(found)))
  1068 |     return len(found)
  1069 | 
  1070 | 
> 1071 | COLLIDING = [0]   # agent-added .py files removed for a basename collision in this grade (1.2.11)
> 1072 | 
> 1073 | 
> 1074 | def remove_colliding(t, tree):
> 1075 |     """1.2.11: a .py file at a path that is neither a hidden overlay dest nor present in the fixture, whose basename
> 1076 |     equals the basename of a hidden overlay .py file or of a fixture .py file under tests/ or test/, is removed: under
> 1077 |     the default import mode pytest imports package-less test modules by basename and a second module with the same
> 1078 |     basename aborts collection. Paths go to grading/<label>.colliding-removed.txt beside the tree → count"""
> 1079 |     owned = {d for _s, d, f in t.overlay if not os.path.isdir(f)}
> 1080 |     owned_dirs = tuple(d + "/" for _s, d, f in t.overlay if os.path.isdir(f))
> 1081 |     reserved = {d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}
> 1082 |     fx = t.fixture or ""
> 1083 |     if fx and os.path.isdir(fx):
> 1084 |         for r, _ds, fs in os.walk(fx, followlinks=False):
> 1085 |             parts = os.path.relpath(r, fx).replace(os.sep, "/").split("/")
> 1086 |             if any(p in ("tests", "test") for p in parts):
> 1087 |                 reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))
> 1088 |     reserved.discard("conftest.py")   # pytest registers conftest modules per directory; remove_harness owns them
> 1089 |     found = []
> 1090 |     for r, ds, fs in os.walk(tree, followlinks=False):
> 1091 |         relr = os.path.relpath(r, tree)
> 1092 |         for name in sorted(fs):
> 1093 |             if name not in reserved:
> 1094 |                 continue
> 1095 |             rel = name if relr == "." else relr.replace(os.sep, "/") + "/" + name
> 1096 |             if rel in owned or rel.startswith(owned_dirs) or (fx and os.path.lexists(os.path.join(fx, *rel.split("/")))):
> 1097 |                 continue
> 1098 |             found.append((rel, os.path.join(r, name)))
> 1099 |     for _rel, p in found:
> 1100 |         os.unlink(p)
> 1101 |     with open(tree.rstrip("/") + ".colliding-removed.txt", "w", encoding="utf-8") as f:
> 1102 |         f.write("".join(rel + "\n" for rel, _p in sorted(found)))
  1103 |     return len(found)
  1104 | 
  1105 | 
  1106 | def git_env(home):
  1107 |     return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "LC_ALL": "C",
  1108 |             "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
  1109 | 
  1110 | 
  1111 | SNAPSHOT_LINKS_DROPPED = [0]   # escaping links removed from snapshot trees in this grade
  1112 | 
  1113 | 
  1114 | def extract_snapshot(run_dir, label, commit, tree):
~~~~

The change from head to the fix:

~~~~diff
@@ -1071,32 +1093,215 @@
-COLLIDING = [0]   # agent-added .py files removed for a basename collision in this grade (1.2.11)
+COLLIDING = [0]   # agent-added modules removed for an import-name collision or a helper shadow in this grade (1.2.11; 1.2.12; 1.2.13)
+PYTEST_DEFAULT_FILES = ["test_*.py", "*_test.py"]   # pytest's default python_files
+PYTEST_INI_ORDER = (("pytest.ini", "pytest"), (".pytest.ini", "pytest"), ("pyproject.toml", None),
+                    ("tox.ini", "pytest"), ("setup.cfg", "tool:pytest"))   # pytest's inifile precedence at one directory
+
+
+def _ini_section(path, section):
+    """configparser read of one ini file → (section found, python_files value or None); unreadable → (False, None)"""
+    cp = configparser.ConfigParser(interpolation=None)
+    try:
+        with open(path, encoding="utf-8") as f:
+            cp.read_file(f)
+    except (OSError, UnicodeError, configparser.Error):
+        return False, None
+    if not cp.has_section(section):
+        return False, None
+    return True, cp.get(section, "python_files", fallback=None)
+
+
+def _toml_section(path):
+    """tomllib read of pyproject.toml → (tool.pytest.ini_options found, python_files value or None)"""
+    try:
+        with open(path, "rb") as f:
+            doc = tomllib.load(f)
+    except (OSError, ValueError):
+        return False, None
+    tool = doc.get("tool")
+    pt = tool.get("pytest") if isinstance(tool, dict) else None
+    opts = pt.get("ini_options") if isinstance(pt, dict) else None
+    if not isinstance(opts, dict):
+        return False, None
+    return True, opts.get("python_files")
+
+
+def _patterns(v):
+    """an ini value is pytest's args type (shell-split); a TOML array is taken as is → list or None"""
+    if isinstance(v, list):
+        return [x for x in v if isinstance(x, str)]
+    if isinstance(v, str):
+        try:
+            return shlex.split(v)
+        except ValueError:
+            return v.split()
+    return None
+
+
+def collision_rule(t):
+    """1.2.13 (DISS-C-004): the python_files patterns pytest uses for this task → {python_files, source}. A -o/--override-ini
+    python_files=… in test_command wins (source "test_command"); else -c/--config-file <fixture-relative file> in
+    test_command is read alone; else the first of pytest.ini, .pytest.ini, pyproject.toml ([tool.pytest.ini_options]),
+    tox.ini ([pytest]), setup.cfg ([tool:pytest]) at the fixture root that pytest would pick; the defaults when the picked
+    file sets no python_files or no file is picked (source "default"). Cached on the task."""
+    if getattr(t, "_collision_rule", None) is not None:
+        return t._collision_rule
+    cmd = list(t.test_command or [])
+    override, cfg = None, None
+    for i, a in enumerate(cmd):
+        nxt = cmd[i + 1] if i + 1 < len(cmd) else None
+        val = None
+        if a in ("-o", "--override-ini"):
+            val = nxt
+        elif a.startswith("--override-ini="):
+            val = a.split("=", 1)[1]
+        elif a.startswith("-o") and not a.startswith("--"):
+            val = a[2:]
+        if isinstance(val, str) and val.startswith("python_files="):
+            override = _patterns(val.split("=", 1)[1]) or []
+        if a in ("-c", "--config-file") and nxt:
+            cfg = nxt
+        elif a.startswith("--config-file="):
+            cfg = a.split("=", 1)[1]
+    rule = {"python_files": list(PYTEST_DEFAULT_FILES), "source": "default"}
+    fx = t.fixture or ""
+    if override is not None:
+        rule = {"python_files": override, "source": "test_command"}
+    elif fx and os.path.isdir(fx):
+        if cfg is not None:
+            parts = safe_rel(cfg)
+            name = parts[-1] if parts else ""
+            cands = [("/".join(parts), None if name.endswith(".toml") else ("tool:pytest" if name == "setup.cfg" else "pytest"))] if parts else []
+            explicit = True
+        else:
+            cands, explicit = list(PYTEST_INI_ORDER), False
+        for rel, section in cands:
+            p = os.path.join(fx, *rel.split("/"))
+            if os.path.islink(p) or not os.path.isfile(p) or not is_within(p, fx):
+                continue
+            found, val = _toml_section(p) if section is None else _ini_section(p, section)
+            if not (found or explicit or rel in ("pytest.ini", ".pytest.ini")):
+                continue   # pyproject.toml, tox.ini and setup.cfg count only with their pytest section; pytest.ini always
+            pats = _patterns(val)
+            if pats is not None:
+                rule = {"python_files": pats, "source": rel}
+            break
+    t._collision_rule = rule
+    return rule
+
+
+def collectable(rel, pats):
+    """a .py file pytest collects as a test module under python_files pats (pytest's fnmatch_ex: a pattern without / is
+    matched against the basename, one with / against the path); __init__.py and conftest.py never"""
+    name = rel.rsplit("/", 1)[-1]
+    if not name.endswith(".py") or name in ("__init__.py", "conftest.py"):
+        return False
+    for pat in pats:
+        if "/" in pat:
+            if fnmatch.fnmatchcase("/" + rel, pat if pat.startswith("/") else "*/" + pat):
+                return True
+        elif fnmatch.fnmatchcase(name, pat):
+            return True
+    return False
+
+
+def import_name(rel, has_init):
+    """pytest's prepend-mode module name of rel: walk up while the directory has an __init__.py (has_init(dir-rel));
+    the dotted path from that basedir, without .py"""
+    parts = rel.split("/")
+    names, dirs = [parts[-1][:-3]], parts[:-1]
+    while dirs and has_init("/".join(dirs)):
+        names.insert(0, dirs[-1])
+        dirs = dirs[:-1]
+    return ".".join(names)
 
 
 def remove_colliding(t, tree):
-    """1.2.11: a .py file at a path that is neither a hidden overlay dest nor present in the fixture, whose basename
-    equals the basename of a hidden overlay .py file or of a fixture .py file under tests/ or test/, is removed: under
-    the default import mode pytest imports package-less test modules by basename and a second module with the same
-    basename aborts collection. Paths go to grading/<label>.colliding-removed.txt beside the tree → count"""
+    """1.2.13 (DISS-001, DISS-C-005, DISS-C-004). Protected modules are the hidden overlay file dests, the files inside
+    directory overlays (at their dests) and the fixture's files under a tests/ or test/ directory. Each protected .py
+    gets its prepend-mode import name, with __init__.py presence read from the overlay-or-fixture view (an overlay file
+    dest, a file inside a directory overlay, or a fixture file). A candidate is a .py in the grading tree that is not
+    owned (no overlay file dest, not inside a directory overlay, no fixture file at that path).
+    (1) collision: a candidate pytest collects (collision_rule's python_files) whose import name, from the tree's real
+    __init__.py files, equals a protected collectable module's import name is removed (import file mismatch).
+    (2) helper shadow: a protected helper is a non-collectable protected .py (never __init__.py or conftest.py) in a
+    package-less directory of the view that pytest puts on sys.path (the tree root, or a directory holding a protected
+    collectable module or conftest.py), so a protected module can import it by bare name. A non-collectable candidate
+    (never __init__.py or conftest.py) whose stem is such a helper's, in a package-less directory that also holds a
+    collectable module after (1), is removed together with the unowned collectable modules in that directory (pytest
+    puts that directory on sys.path and, when an agent module there imports the helper first, the agent's copy answers
+    the protected import; removing the helper alone would turn that import into a collection-aborting ImportError). Paths go to grading/<label>.colliding-removed.txt beside the tree → count"""
+    pats = collision_rule(t)["python_files"]
     owned = {d for _s, d, f in t.overlay if not os.path.isdir(f)}
     owned_dirs = tuple(d + "/" for _s, d, f in t.overlay if os.path.isdir(f))
-    reserved = {d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}
     fx = t.fixture or ""
+    prot = set(owned)
+    for _s, d, f in t.overlay:
+        if os.path.isdir(f) and not os.path.islink(f):
+            for r, _ds, fs in os.walk(f, followlinks=False):
+                relr = os.path.relpath(r, f).replace(os.sep, "/")
+                prot.update(d + "/" + (n if relr == "." else relr + "/" + n) for n in fs)
+    view = set(prot)   # the overlay-or-fixture view (for __init__.py lookups)
     if fx and os.path.isdir(fx):
         for r, _ds, fs in os.walk(fx, followlinks=False):
-            parts = os.path.relpath(r, fx).replace(os.sep, "/").split("/")
-            if any(p in ("tests", "test") for p in parts):
-                reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))
-    reserved.discard("conftest.py")   # pytest registers conftest modules per directory; remove_harness owns them
-    found = []
-    for r, ds, fs in os.walk(tree, followlinks=False):
-        relr = os.path.relpath(r, tree)
+            relr = os.path.relpath(r, fx).replace(os.sep, "/")
+            rels = [n if relr == "." else relr + "/" + n for n in fs]
+            view.update(rels)
+            if any(p in ("tests", "test") for p in relr.split("/")):
+                prot.update(rels)
+
+    def view_init(dr):
+        return (dr + "/__init__.py") in view
+
+    def tree_init(dr):
+        return os.path.isfile(os.path.join(tree, *dr.split("/"), "__init__.py"))
+
+    prot_coll, prot_help, live_dirs = set(), set(), {""}
+    for rel in prot:
+        dr, _sep, name = rel.rpartition("/")
+        if name == "conftest.py" or (name.endswith(".py") and name != "__init__.py" and collectable(rel, pats)):
+            live_dirs.add(dr)   # pytest imports this module, so a package-less dr is on sys.path
+        if not name.endswith(".py") or name in ("__init__.py", "conftest.py"):
+            continue
+        if collectable(rel, pats):
+            prot_coll.add(import_name(rel, view_init))
+    for rel in prot:
+        dr, _sep, name = rel.rpartition("/")
+        if name.endswith(".py") and name not in ("__init__.py", "conftest.py") and not collectable(rel, pats) \
+                and dr in live_dirs and not (dr and view_init(dr)):
+            prot_help.add(name[:-3])   # a helper a protected module imports by bare name (import _oracle_x)
+    cands = []
+    for r, _ds, fs in os.walk(tree, followlinks=False):
+        relr = os.path.relpath(r, tree).replace(os.sep, "/")
         for name in sorted(fs):
-            if name not in reserved:
+            rel = name if relr == "." else relr + "/" + name
+            if not name.endswith(".py") or rel in owned or rel.startswith(owned_dirs):
                 continue
-            rel = name if relr == "." else relr.replace(os.sep, "/") + "/" + name
-            if rel in owned or rel.startswith(owned_dirs) or (fx and os.path.lexists(os.path.join(fx, *rel.split("/")))):
+            if fx and os.path.lexists(os.path.join(fx, *rel.split("/"))):
                 continue
-            found.append((rel, os.path.join(r, name)))
-    for _rel, p in found:
-        os.unlink(p)
+            cands.append(rel)
+    cand_set = set(cands)
+    found = [rel for rel in cands if collectable(rel, pats) and import_name(rel, tree_init) in prot_coll]
+    gone = set(found)
+    for rel in cands:
+        if rel in gone or collectable(rel, pats) or rel.rsplit("/", 1)[-1] in ("__init__.py", "conftest.py"):
+            continue
+        dr, _sep, name = rel.rpartition("/")
+        if name[:-3] not in prot_help or (dr and tree_init(dr)):
+            continue
+        d_abs = os.path.join(tree, *dr.split("/")) if dr else tree
+        try:
+            sib = os.listdir(d_abs)
+        except OSError:
+            continue
+        sib_rels = [n if not dr else dr + "/" + n for n in sorted(sib)]
+        live = [x for x in sib_rels if x not in gone and os.path.isfile(os.path.join(tree, *x.split("/"))) and collectable(x, pats)]
+        if live:
+            # the helper and the unowned test modules beside it go together: a module that imports the helper and
+            # stays would abort collection with an ImportError (pytest 9, checked by hand), worse than the shadow
+            for x in [rel] + [x for x in live if x in cand_set]:
+                if x not in gone:
+                    gone.add(x)
+                    found.append(x)
+    for rel in found:
+        os.unlink(os.path.join(tree, *rel.split("/")))
     with open(tree.rstrip("/") + ".colliding-removed.txt", "w", encoding="utf-8") as f:
-        f.write("".join(rel + "\n" for rel, _p in sorted(found)))
+        f.write("".join(rel + "\n" for rel in sorted(found)))
~~~~

## H05 — evals/harness/ablation-grade.sh — insertion after head line 1773

Head context (head/evals/harness/ablation-grade.sh, lines 1762–1785):

~~~~text
  1762 |             ok = snap_res[gates[gate]][1]
  1763 |             acc[gate] = (v == "APPROVED" and ok) or (v == "CHANGES_REQUIRED" and not ok)
  1764 |     else:
  1765 |         if os.path.isdir(os.path.join(sb, "pr")) and not os.path.islink(os.path.join(sb, "pr")):
  1766 |             g["symlinks_dropped"] = copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
  1767 |         g["recall"], g["false_positives"] = grade_recall(t, run_dir, grading)
  1768 |         key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
  1769 |         for gate, v in (("review", v_review), ("audit", v_audit)):
  1770 |             if v is not None:
  1771 |                 acc[gate] = (v == "CHANGES_REQUIRED") == key_cr and v in ("APPROVED", "CHANGES_REQUIRED")
  1772 |     g["oversized_files_skipped"] = OVERSIZED[0]
  1773 |     g["colliding_tests_removed"] = COLLIDING[0]
  1774 |     g["verdict_accuracy_per_gate"] = acc
  1775 |     g["verdict_accuracy"] = acc["audit"] if acc["audit"] is not None else acc["review"]
  1776 |     g["contaminated"] = contamination(run_dir)
  1777 |     g["history_probes"] = HISTORY_PROBES[0]
  1778 |     g["heredoc_interpreters"] = HEREDOC_INTERP[0]
  1779 |     return g
  1780 | 
  1781 | 
  1782 | def structural_command(t):
  1783 |     dest = t.structural
  1784 |     if dest.endswith(".bats"):
  1785 |         return ["bats", dest]
~~~~

The change from head to the fix:

~~~~diff
@@ -1773,0 +1979 @@
+    g["collision_rule"] = collision_rule(t) if t.build else None
~~~~

## H06 — evals/harness/pipeline-run.sh — head line 607

Head context (head/evals/harness/pipeline-run.sh, lines 595–619):

~~~~text
   595 |   tpl="$(subst "$tpl" TASK_ID "$TASK_ID")"
   596 |   tpl="$(subst "$tpl" FLATLINE "$FLATLINE")"
   597 |   tpl="$(subst "$tpl" CHANGE_NOTE "$CHANGE_NOTE")"
   598 |   printf '%s\n' "$tpl" > "$out"
   599 | }
   600 | 
   601 | # --- per-run HOME (container mode; DEC-0411 as amended in Sprint 258) -------------------------
   602 | # One writable host directory mounted at /home/evaluser: the CLI's session store lives
   603 | # there for the whole run (A6 --resume continues across phases), and it holds only the
   604 | # codex CLI's own files: config.toml verbatim and auth.json with a PLACEHOLDER tokens.refresh_token
   605 | # (KF-048: the refresh token is single-use, so a container that refreshed with a verbatim
   606 | # copy invalidated the host's token and every later run's; an unreadable auth.json gives
>  607 | # the run no codex credential and one WARN line). ~/.claude/.credentials.json and
   608 | # ~/.claude/settings.json are never copied: the Bedrock route authenticates from AWS_BEARER_TOKEN_BEDROCK in the environment,
   609 | # and --setting-sources project ignores user settings.
   610 | CREDS_HOME="${LOA_EVAL_CREDS_HOME:-$HOME}"
   611 | make_home() {
   612 |   mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/.aws" "$HOME_DIR/.codex"
   613 |   # the sandbox project is pre-trusted so the mounted tree's project settings apply without the dialog
   614 |   # (the CLI otherwise ignores permissions.allow and warns; lead, Sprint 258 smoke)
   615 |   printf '{"projects":{"/workspace":{"hasTrustDialogAccepted":true}}}\n' > "$HOME_DIR/.claude.json"
   616 |   if [[ -f "$CREDS_HOME/.codex/config.toml" ]]; then cp "$CREDS_HOME/.codex/config.toml" "$HOME_DIR/.codex/config.toml"; fi
   617 |   # auth.json: a copy whose refresh token is a placeholder (KF-048). The real one is single-use; a
   618 |   # container that refreshed with a verbatim copy consumed the host's token and every later run and
   619 |   # the host failed with 401 refresh_token_reused. The key must stay: the codex CLI treats a missing
~~~~

The change from head to the fix:

~~~~diff
@@ -607 +607,7 @@
-# the run no codex credential and one WARN line). ~/.claude/.credentials.json and
+# the run no codex credential and one WARN line). EXPOSURE (Sprint 261 audit DISS-C-001, bead
+# bd-lfrkn): the copy carries tokens.access_token, id_token and account_id because the codex CLI
+# needs all three (a copy without id_token gets 401 Missing bearer), and /home/evaluser is
+# readable by the agent under evaluation, so the bearer is exposed to it for the token's lifetime
+# (bounded by run-ablation.sh's pre-flight horizon). A long-lived OPENAI_API_KEY is never copied
+# unless LOA_EVAL_CODEX_APIKEY_COPY=1 (API-key mode only; the run otherwise has no codex
+# credential and says so). ~/.claude/.credentials.json and
~~~~

## H07 — evals/harness/pipeline-run.sh — insertion after head line 636

Head context (head/evals/harness/pipeline-run.sh, lines 625–648):

~~~~text
   625 | src, dst = sys.argv[1], sys.argv[2]
   626 | try:
   627 |     with open(src, "rb") as fh:
   628 |         data = json.loads(fh.read().decode("utf-8"))
   629 | except Exception:
   630 |     data = None
   631 | if not isinstance(data, dict):
   632 |     sys.exit(3)
   633 | tok = data.get("tokens")
   634 | if isinstance(tok, dict):
   635 |     if "refresh_token" in tok:
   636 |         tok["refresh_token"] = "loa-ablation-no-refresh-token"
   637 | fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
   638 | os.fchmod(fd, 0o600)
   639 | with os.fdopen(fd, "w", encoding="utf-8") as out:
   640 |     json.dump(data, out)
   641 |     out.write("\n")
   642 | ' "$CREDS_HOME/.codex/auth.json" "$HOME_DIR/.codex/auth.json" \
   643 |       || { rm -f "$HOME_DIR/.codex/auth.json"
   644 |            echo "pipeline-run: WARN codex auth.json unreadable; the run has no codex credential" >&2; }
   645 |   fi
   646 |   chmod 0700 "$HOME_DIR" "$HOME_DIR/.claude" "$HOME_DIR/.aws" "$HOME_DIR/.codex"
   647 | }
   648 | [[ "$EXECUTOR" == container ]] && make_home
~~~~

The change from head to the fix:

~~~~diff
@@ -636,0 +643,12 @@
+# OPENAI_API_KEY (Sprint 261 audit DISS-C-001): a long-lived key never reaches the agent-writable HOME
+# unless the operator accepts the exposure with LOA_EVAL_CODEX_APIKEY_COPY=1 and the file is in API-key
+# mode (no usable access token); in ChatGPT mode the key is unused by codex and is dropped.
+has_at = isinstance(tok, dict) and isinstance(tok.get("access_token"), str) and bool(tok.get("access_token"))
+key = data.get("OPENAI_API_KEY")
+if isinstance(key, str) and key:
+    if has_at or os.environ.get("LOA_EVAL_CODEX_APIKEY_COPY") != "1":
+        data["OPENAI_API_KEY"] = None
+        if not has_at:
+            sys.stderr.write("pipeline-run: WARN codex auth.json is in API-key mode; the key is not copied into the "
+                             "agent-writable HOME (set LOA_EVAL_CODEX_APIKEY_COPY=1 to accept the exposure); "
+                             "the run has no codex credential\n")
~~~~

## H08 — evals/harness/run-ablation.sh — head lines 115–121

Head context (head/evals/harness/run-ablation.sh, lines 103–133):

~~~~text
   103 | #   3. seed-corpus-from-record.sh --check (the review-catch corpus SHA256SUMS)
   104 | #   4. container: the docker CLI and the image (`docker image inspect`)
   105 | #   5. the pinned source tree: $LOA_ABLATION_SOURCE_TREE when set (tests; must be a git tree
   106 | #      at the commit, with .claude/), else a detached worktree
   107 | #      $LOA_ABLATION_CACHE/ablation-src-<sha12> (default ~/.cache/loa) cut from
   108 | #      $LOA_ABLATION_SOURCE_REPO (default this repository) with git worktree add --detach;
   109 | #      it must be at the commit and pristine (git status --porcelain --ignored empty)
   110 | #   6. codex token freshness (KF-048), non-smoke batches only (fresh, --resume and --dry-run),
   111 | #      after the plan is built, when a planned arm uses codex (every arm except one whose
   112 | #      toggles set loa_mount: false; a0_bare never runs the dissent): the exp claim of the JWT
   113 | #      tokens.access_token in ${LOA_EVAL_CREDS_HOME:-$HOME}/.codex/auth.json (the file
   114 | #      pipeline-run.sh copies with a placeholder refresh token; payload decoded with base64url, no
>  115 | #      signature check) must be later than required_until = now + 2 x (sum of the plan's
>  116 | #      watchdog_s) / concurrency (on --resume the whole recorded plan counts). Refused: exp <=
>  117 | #      required_until (`codex access token expires <ISO>, before the batch's required horizon
>  118 | #      <ISO> (now + 2 x summed watchdog / concurrency; KF-048) — run codex login on the host`),
>  119 | #      and a present file that is not JSON or whose access token is missing, not a three-part
>  120 | #      JWT or has no numeric exp. A missing auth.json is no refusal: one `run-ablation: WARN no
>  121 | #      codex auth.json under <dir>; codex-using arms will run without the OpenAI voice` line.
   122 | #   --resume also refuses when the source commit, the suite manifest hash, the image digest
   123 | #   or the CLI version differ from MANIFEST.json, or when STATUS.json records a drift
   124 | #   (unless --clear-drift re-reads that run clean under the current rule).
   125 | #
   126 | # Plan: arms × tasks × trials. An arm whose task_types excludes a task's type is dropped for
   127 | # that task with one `refused:` line and never dispatched (DEC-0405). The order is
   128 | # trial-major (every arm × task once before any second trial); inside each trial block the
   129 | # entries (arm-major, tasks by id) are shuffled with one python3 random.Random(<seed>)
   130 | # generator, blocks in trial order (Fisher-Yates via random.shuffle: reproducible for a seed
   131 | # across CPython 3.x). run_id = <batch>-<arm>-<task>-t<n>; run dir <batch>/<arm>/<task>-t<n>,
   132 | # a fresh <…>-r<k> (k ≥ 2) for a transport retry or a resumed rerun (the run_id stays).
   133 | # --dry-run prints `plan: …`, the `refused:` lines and one line per trial
~~~~

The change from head to the fix:

~~~~diff
@@ -115,7 +115,24 @@
-#      signature check) must be later than required_until = now + 2 x (sum of the plan's
-#      watchdog_s) / concurrency (on --resume the whole recorded plan counts). Refused: exp <=
-#      required_until (`codex access token expires <ISO>, before the batch's required horizon
-#      <ISO> (now + 2 x summed watchdog / concurrency; KF-048) — run codex login on the host`),
-#      and a present file that is not JSON or whose access token is missing, not a three-part
-#      JWT or has no numeric exp. A missing auth.json is no refusal: one `run-ablation: WARN no
-#      codex auth.json under <dir>; codex-using arms will run without the OpenAI voice` line.
+#      signature check) must be later than required_until = now + 2 x max(S / concurrency, W),
+#      S the sum and W the largest of watchdog_s over the trials this invocation counts (the
+#      lower bound W: one trial takes its whole watchdog whatever the concurrency, DISS-C-001):
+#      every plan entry on a fresh batch or a dry run; on --resume only the entries without a row
+#      of this batch, plus the --rerun ids, the rows a --rerun-status names and the run_ids of
+#      STATUS.json rerun_pending (never a --rerow id; a paused arm's trials still count). The
+#      count is a superset of what the launcher runs: a rerun_pending id that is not flagged
+#      again (--rerun / --rerun-status) keeps its old row and is not relaunched, so it lengthens
+#      the horizon only (the safe direction); a run_id with two rows is read last-row-wins here,
+#      where the launcher refuses the resume on the duplicate after this check (DISS-C-003).
+#      $LOA_ABLATION_CODEX_HORIZON_S (positive whole seconds, an operator knob) replaces
+#      the computed horizon: required_until = now + that. Refused: exp <= required_until (`codex
+#      access token expires <ISO>, before the batch's required horizon <ISO> (now + 2 x
+#      max(summed watchdog of <n> trial(s) / concurrency, longest watchdog) | now +
+#      LOA_ABLATION_CODEX_HORIZON_S; KF-048) — run codex login on the host`), a present file
+#      that is not a JSON object, an access token not a three-part JWT or without a numeric
+#      exp, and a file with neither a tokens.access_token nor a non-empty OPENAI_API_KEY (`… — run codex login on the host, or set OPENAI_API_KEY
+#      in auth.json`). API-key mode (no usable tokens.access_token, a non-empty OPENAI_API_KEY;
+#      pipeline-run.sh copies the key into the per-run HOME only under LOA_EVAL_CODEX_APIKEY_COPY=1,
+#      audit DISS-C-001; otherwise that run has no codex credential) passes without reading an exp, with one
+#      `run-ablation: codex auth.json is in API-key mode; no token horizon applies (KF-048
+#      concerns the ChatGPT refresh token only)` line; the key is never printed. A missing
+#      auth.json is no refusal: one `run-ablation: WARN no codex auth.json under <dir>;
+#      codex-using arms will run without the OpenAI voice` line.
~~~~

## H09 — evals/harness/run-ablation.sh — head line 230

Head context (head/evals/harness/run-ablation.sh, lines 218–242):

~~~~text
   218 | #   suite_file, suite_root, tasks_dir, rows_file, suite_version, suite_manifest_sha256, arms,
   219 | #   tasks, refused, trials_per_type, trials_planned, plan, arm_map, shuffle_seed, shuffle,
   220 | #   fingerprint, image, image_digest, executor_mode, cli_version (`docker run --rm --network
   221 | #   none <image> claude --version`, host: the CLI's), cli_version_raw, tools, phase_models,
   222 | #   caps {cycle_usd, run_usd (the single-cap fallback), reserve_usd, max_usd,
   223 | #   run_usd_by_type {build, review-catch} (the effective per-kind caps after the chain)},
   224 | #   cost_hint, concurrency, retry,
   225 | #   watchdog {multiplier, override_s, grace_s, grade_timeout_s, took_effect_timeout_s},
   226 | #   pre_registration_ref, gate (null for smoke), corpus, agy_opt_in,
   227 | #   codex_token_exp (the access token's exp, ISO 8601 UTC, or null when not checked),
   228 | #   codex_preflight {checked (true only when the token was read and its exp compared),
   229 | #   auth_file_present, codex_arms (the planned arms that use codex, sorted), token_exp,
>  230 | #   required_until (ISO or null)} (pre-flight 6; --resume keeps the start's record), environment.
   231 | #   STATUS.json (§3.4), rewritten after every trial: {schema_version, suite, batch, smoke,
   232 | #   state: running|complete|partial|failed, per_arm: {<arm>: {trials_planned, launched,
   233 | #   completed, failed (agent_error), excluded (transport_error, infrastructure_error,
   234 | #   interrupted, contaminated), cap_failures, degraded, skipped_paused}}, retries: [{run_id,
   235 | #   reason, first_attempt_usd}], cuts: [...], paused_arms: {<arm>: reason}, spend: {rows_usd,
   236 | #   ledger_usd (transport first attempts, and the reported cost of rows a rerun replaced), spent_usd, max_usd, assumed_cap_trials}, resume_cursor (the
   237 | #   index of the first plan entry without a row), drift: null | {run_id, field, expected,
   238 | #   got}, drift_cleared: [{run_id, previous, cleared_at, harness_commit}] (--clear-drift),
   239 | #   rerowed: [{run_id, from, to, at}] (--rerow), rerun: [{run_id, from, to, old_cost_usd, at}]
   240 | #   (--rerun, --rerun-status), rerun_pending: [run_id…] (flagged, no replacement yet), outage:
   241 | #   null | {at, consecutive, last_run_id, message} (the breaker), outage_history: [the
   242 | #   outages a later --resume cleared], extra_models: {<raw id>: {runs,
~~~~

The change from head to the fix:

~~~~diff
@@ -230 +247,5 @@
-#   required_until (ISO or null)} (pre-flight 6; --resume keeps the start's record), environment.
+#   required_until (ISO or null), auth_mode ("chatgpt" | "apikey" | null when the file was not
+#   read or not classified), trials_counted (the trials the horizon covers, or null),
+#   horizon_source ("plan" | "override" | null when no horizon was computed)} (pre-flight 6;
+#   --resume keeps the start's record; STATUS.json codex_preflight holds the latest
+#   invocation's; both writers take it from a shell variable, never a scratch file), environment.
~~~~

## H10 — evals/harness/run-ablation.sh — head line 242

Head context (head/evals/harness/run-ablation.sh, lines 230–254):

~~~~text
   230 | #   required_until (ISO or null)} (pre-flight 6; --resume keeps the start's record), environment.
   231 | #   STATUS.json (§3.4), rewritten after every trial: {schema_version, suite, batch, smoke,
   232 | #   state: running|complete|partial|failed, per_arm: {<arm>: {trials_planned, launched,
   233 | #   completed, failed (agent_error), excluded (transport_error, infrastructure_error,
   234 | #   interrupted, contaminated), cap_failures, degraded, skipped_paused}}, retries: [{run_id,
   235 | #   reason, first_attempt_usd}], cuts: [...], paused_arms: {<arm>: reason}, spend: {rows_usd,
   236 | #   ledger_usd (transport first attempts, and the reported cost of rows a rerun replaced), spent_usd, max_usd, assumed_cap_trials}, resume_cursor (the
   237 | #   index of the first plan entry without a row), drift: null | {run_id, field, expected,
   238 | #   got}, drift_cleared: [{run_id, previous, cleared_at, harness_commit}] (--clear-drift),
   239 | #   rerowed: [{run_id, from, to, at}] (--rerow), rerun: [{run_id, from, to, old_cost_usd, at}]
   240 | #   (--rerun, --rerun-status), rerun_pending: [run_id…] (flagged, no replacement yet), outage:
   241 | #   null | {at, consecutive, last_run_id, message} (the breaker), outage_history: [the
>  242 | #   outages a later --resume cleared], extra_models: {<raw id>: {runs,
   243 | #   output_tokens}} ({} when none; derived from extra_models_by_run: {<run_id>: {<raw id>:
   244 | #   output_tokens}}, the per-run source a rerow replaces), rows_invalid, started,
   245 | #   finished}. At the end the spend.sh line and a batch line go to <batch>/spend.txt.
   246 | #
   247 | # --resume: reads MANIFEST.json (plan, arms, suite paths, executor, image, run caps, rows
   248 | #   file) and STATUS.json (paused_arms, cuts, retries, first-attempt spend); a plan run_id
   249 | #   with a row of this batch is done; a trial without a row reruns into a fresh -r<k> run
   250 | #   dir (the stale dir is kept); counters and spend are recomputed from the rows.
   251 | #   --max-usd and --concurrency may change on resume; --clear-arm, --clear-drift and
   252 | #   --rerow need --resume (order: --clear-drift, --rerow and --rerun are checked before the lock,
   253 | #   then --rerow replaces rows, then the counters are recomputed with the rerun-flagged rows left
   254 | #   out of the done set; the reruns are dispatched with the plan). A resume clears STATUS.json
~~~~

The change from head to the fix:

~~~~diff
@@ -242 +263,3 @@
-#   outages a later --resume cleared], extra_models: {<raw id>: {runs,
+#   outages a later --resume cleared], codex_preflight (this invocation's pre-flight 6 record,
+#   the MANIFEST shape, null if STATUS.json is written before pre-flight 6 ran; on --resume
+#   trials_counted is the remaining trials, rerun_pending included), extra_models: {<raw id>: {runs,
~~~~

## H11 — evals/harness/run-ablation.sh — head line 272

Head context (head/evals/harness/run-ablation.sh, lines 260–284):

~~~~text
   260 | #       interrupted or contaminated), 1 partial (cut, the outage breaker, a paused arm with trials left, an
   261 | #       excluded row, or the driver was signalled), 2 usage or refused, 3 failed (drift, an
   262 | #       invalid or duplicated row, no trial completed without a cut, or every arm of the
   263 | #       plan paused)
   264 | #
   265 | # Env: LOA_ABLATION_SOURCE_TREE, LOA_ABLATION_SOURCE_REPO, LOA_ABLATION_CACHE,
   266 | #   LOA_ABLATION_RETRY_WAIT_S, LOA_ABLATION_WATCHDOG_S, LOA_ABLATION_WATCHDOG_GRACE_S,
   267 | #   LOA_ABLATION_POLL_S (reap poll, default 1), LOA_ABLATION_OUTAGE_BREAKER (default 3),
   268 | #   LOA_ABLATION_GRADE_TIMEOUT_S (grade deadline, default 1800: above the grader's own per-command deadline of
   269 | #   120 + 10 s over at most ten container commands per grade, plus the tree copies; the outage breaker counts
   270 | #   transport_error rows only, never these infrastructure_error rows) and
   271 | #   LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S (took-effect deadline, default 300), both whole seconds
>  272 | #   1 … 999999 (else exit 2), EVAL_DOCKER_BIN, EVAL_CLAUDE_BIN (host CLI).
   273 | # Library: lib/arms-common.sh beside this script, sourced by a literal relative path.
   274 | # Tested by evals/tests/run-ablation.bats (stub pipeline, grader and docker; no model call).
   275 | # =============================================================================
   276 | set -euo pipefail
   277 | export LC_ALL=C
   278 | 
   279 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   280 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
   281 | # eval.yml trust boundary: a literal in-tree path, no variable on the source line
   282 | pushd "$SCRIPT_DIR" >/dev/null
   283 | # shellcheck source=lib/arms-common.sh
   284 | source ./lib/arms-common.sh || { popd >/dev/null; echo "run-ablation: lib/arms-common.sh failed to load" >&2; exit 2; }
~~~~

The change from head to the fix:

~~~~diff
@@ -272 +295,4 @@
-#   1 … 999999 (else exit 2), EVAL_DOCKER_BIN, EVAL_CLAUDE_BIN (host CLI).
+#   1 … 999999 (else exit 2), LOA_ABLATION_CODEX_HORIZON_S (operator override of the codex
+#   token horizon of pre-flight 6, whole seconds 1 … 999999999, else exit 2; not a test gate),
+#   LOA_EVAL_CREDS_HOME (where .codex/auth.json is read; default $HOME), EVAL_DOCKER_BIN,
+#   EVAL_CLAUDE_BIN (host CLI).
~~~~

## H12 — evals/harness/run-ablation.sh — insertion after head line 312

Head context (head/evals/harness/run-ablation.sh, lines 301–324):

~~~~text
   301 | PIPELINE_BIN="$SCRIPT_DIR/pipeline-run.sh" GRADE_BIN="$SCRIPT_DIR/ablation-grade.sh"
   302 | ROW_BIN="$SCRIPT_DIR/ablation-row.sh" TOOK_BIN="$SCRIPT_DIR/took-effect.sh"
   303 | DOCKER_BIN="${EVAL_DOCKER_BIN:-docker}"
   304 | FREEZE_BIN="$SCRIPT_DIR/freeze.sh" CORPUS_BIN="$SCRIPT_DIR/seed-corpus-from-record.sh"
   305 | SPEND_BIN="$SCRIPT_DIR/spend.sh" FP_BIN="$SCRIPT_DIR/fingerprint.sh"
   306 | RETRY_WAIT="${LOA_ABLATION_RETRY_WAIT_S:-120}"
   307 | WATCHDOG_OVERRIDE="${LOA_ABLATION_WATCHDOG_S:-}"
   308 | WATCHDOG_GRACE="${LOA_ABLATION_WATCHDOG_GRACE_S:-60}"
   309 | POLL_S="${LOA_ABLATION_POLL_S:-1}"
   310 | OUTAGE_BREAKER="${LOA_ABLATION_OUTAGE_BREAKER:-3}"
   311 | GRADE_TIMEOUT_S="${LOA_ABLATION_GRADE_TIMEOUT_S:-1800}"
   312 | TOOK_TIMEOUT_S="${LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S:-300}"
   313 | 
   314 | usage() { sed -n '2,/^# =====.*$/p' "$0" | sed '1d;$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
   315 | die() { echo "run-ablation: $*" >&2; exit 2; }
   316 | 
   317 | while [[ $# -gt 0 ]]; do
   318 |   case "$1" in
   319 |     --arms) ARMS_CSV="${2:-}"; shift 2 ;;
   320 |     --source-commit) SOURCE_COMMIT="${2:-}"; shift 2 ;;
   321 |     --tasks) TASKS_CSV="${2:-}"; shift 2 ;;
   322 |     --types) TYPES_CSV="${2:-}"; shift 2 ;;
   323 |     --trials-build) TRIALS_BUILD="${2:-}"; shift 2 ;;
   324 |     --trials-review) TRIALS_REVIEW="${2:-}"; shift 2 ;;
~~~~

The change from head to the fix:

~~~~diff
@@ -312,0 +339,2 @@
+CODEX_HORIZON_OVERRIDE="${LOA_ABLATION_CODEX_HORIZON_S:-}"
+CODEX_PF_JSON=null   # the pre-flight 6 record (JSON); null until pre-flight 6 sets it (DISS-C-002)
~~~~

## H13 — evals/harness/run-ablation.sh — insertion after head line 394

Head context (head/evals/harness/run-ablation.sh, lines 383–406):

~~~~text
   383 | for s in ${RERUN_STATUSES[@]+"${RERUN_STATUSES[@]}"}; do
   384 |   case "$s" in transport_error|interrupted|infrastructure_error) ;;
   385 |     *) die "--rerun-status must be transport_error, interrupted or infrastructure_error (got '$s')" ;; esac
   386 | done
   387 | for r in ${RERUN_IDS[@]+"${RERUN_IDS[@]}"}; do
   388 |   [[ "$r" =~ ^[A-Za-z0-9._-]{1,200}$ ]] || die "invalid --rerun '$r'"
   389 |   for q in ${REROW_IDS[@]+"${REROW_IDS[@]}"}; do [[ "$q" != "$r" ]] || die "--rerun $r is also a --rerow (a run is rowed again or launched again, not both)"; done
   390 | done
   391 | [[ "$(printf '%s\n' ${RERUN_IDS[@]+"${RERUN_IDS[@]}"} | sort | uniq -d)" == "" ]] || die "--rerun lists a run_id twice"
   392 | [[ "$OUTAGE_BREAKER" =~ ^[0-9]{1,4}$ ]] || die "LOA_ABLATION_OUTAGE_BREAKER must be a whole number (0 disables)"
   393 | [[ "$GRADE_TIMEOUT_S" =~ ^[1-9][0-9]{0,5}$ ]] || die "LOA_ABLATION_GRADE_TIMEOUT_S must be positive whole seconds (at most 999999)"
   394 | [[ "$TOOK_TIMEOUT_S" =~ ^[1-9][0-9]{0,5}$ ]] || die "LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S must be positive whole seconds (at most 999999)"
   395 | # the post-run deadlines (Sprint 260 LOW-4): unwrapped when timeout(1) is absent
   396 | GRADE_TMO=() TOOK_TMO=() TMO_ON=false
   397 | if command -v timeout >/dev/null 2>&1; then
   398 |   # the portable short flags (GNU and BusyBox; review round 2 DISS-C-003); MANIFEST records null when unwrapped
   399 |   GRADE_TMO=(timeout -s TERM -k 30 "$GRADE_TIMEOUT_S")
   400 |   TOOK_TMO=(timeout -s TERM -k 30 "$TOOK_TIMEOUT_S")
   401 |   TMO_ON=true
   402 | fi
   403 | [[ "$RESUME" != true || "$DRY_RUN" != true ]] || die "--resume and --dry-run are exclusive"
   404 | [[ "$RESUME" == true || -n "$SOURCE_COMMIT" ]] || die "--source-commit is required"
   405 | 
   406 | if [[ -z "$BATCH" ]]; then
~~~~

The change from head to the fix:

~~~~diff
@@ -394,0 +423,2 @@
+[[ -z "$CODEX_HORIZON_OVERRIDE" || "$CODEX_HORIZON_OVERRIDE" =~ ^[1-9][0-9]{0,8}$ ]] \
+  || die "LOA_ABLATION_CODEX_HORIZON_S must be positive whole seconds (at most 999999999)"
~~~~

## H14 — evals/harness/run-ablation.sh — head lines 786–788

Head context (head/evals/harness/run-ablation.sh, lines 774–800):

~~~~text
   774 | PY
   775 | fi
   776 | jq -c '.plan' "$WORK/plan.json" > "$WORK/plan-only.json"
   777 | PLAN_N="$(jq 'length' "$WORK/plan-only.json")"
   778 | [[ "$PLAN_N" -gt 0 ]] || die "the plan is empty: every arm is refused on every selected task (task_types)"
   779 | 
   780 | # --- codex token freshness (KF-048): the access token must outlive the batch's horizon -------
   781 | # The per-run HOME carries a placeholder refresh token (pipeline-run.sh), so a container cannot renew an
   782 | # expired access token; a batch that would outlive it degrades every codex-using row. Only the
   783 | # JWT payload's exp claim is read (no signature check); no token value is printed.
   784 | CODEX_AUTH="${LOA_EVAL_CREDS_HOME:-$HOME}/.codex/auth.json"
   785 | CODEX_SKIP=false; [[ "$SMOKE" == true ]] && CODEX_SKIP=true
>  786 | CODEX_PF="$(python3 -I - "$CODEX_AUTH" "$WORK/plan-only.json" "$WORK/suite.json" "$CONCURRENCY" "$CODEX_SKIP" <<'PY'
>  787 | import base64, json, math, os, sys, time
>  788 | auth, plan_p, suite_p, conc, skip = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5] == "true"
   789 | plan = json.load(open(plan_p)); suite = json.load(open(suite_p))
   790 | defs = {a.get("id"): a for a in suite.get("arms") or []}
   791 | iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
   792 | def uses_codex(a):   # a0_bare (loa_mount: false) never runs the dissent
   793 |     return ((defs.get(a) or {}).get("toggles") or {}).get("loa_mount") is not False
   794 | arms = sorted({e["arm"] for e in plan if uses_codex(e["arm"])})
   795 | present = os.path.isfile(auth)
   796 | pf = {"checked": False, "auth_file_present": present, "codex_arms": arms, "token_exp": None, "required_until": None}
   797 | out = {"preflight": pf, "refuse": None, "warn": None}
   798 | def done():
   799 |     print(json.dumps(out, sort_keys=True)); sys.exit(0)
   800 | if skip or not arms:
~~~~

The change from head to the fix:

~~~~diff
@@ -786,3 +816,14 @@
-CODEX_PF="$(python3 -I - "$CODEX_AUTH" "$WORK/plan-only.json" "$WORK/suite.json" "$CONCURRENCY" "$CODEX_SKIP" <<'PY'
+# the trials this invocation launches: every plan entry on a fresh batch (and a dry run); on --resume the
+# entries without a row of this batch, plus the --rerun ids, the --rerun-status rows and STATUS.json
+# rerun_pending (never a --rerow id)
+jq -n --argjson resume "$RESUME" --arg rows "$ROWS" --arg batch "$BATCH" \
+  --argjson ids "$(json_array ${RERUN_IDS[@]+"${RERUN_IDS[@]}"})" \
+  --argjson sts "$(json_array ${RERUN_STATUSES[@]+"${RERUN_STATUSES[@]}"})" \
+  --argjson rerow "$(json_array ${REROW_IDS[@]+"${REROW_IDS[@]}"})" \
+  --arg status "$BATCH_DIR/STATUS.json" \
+  '{resume: $resume, rows: $rows, batch: $batch, rerun_ids: $ids, rerun_statuses: $sts, rerow_ids: $rerow, status: $status}' > "$WORK/codex-scope.json"
+CODEX_PF="$(python3 -I - "$CODEX_AUTH" "$WORK/plan-only.json" "$WORK/suite.json" "$CONCURRENCY" "$CODEX_SKIP" \
+  "$WORK/codex-scope.json" "$CODEX_HORIZON_OVERRIDE" <<'PY'
 import base64, json, math, os, sys, time
 auth, plan_p, suite_p, conc, skip = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5] == "true"
+scope = json.load(open(sys.argv[6])); override = int(sys.argv[7]) if sys.argv[7] else None
~~~~

## H15 — evals/harness/run-ablation.sh — head lines 796–797

Head context (head/evals/harness/run-ablation.sh, lines 784–809):

~~~~text
   784 | CODEX_AUTH="${LOA_EVAL_CREDS_HOME:-$HOME}/.codex/auth.json"
   785 | CODEX_SKIP=false; [[ "$SMOKE" == true ]] && CODEX_SKIP=true
   786 | CODEX_PF="$(python3 -I - "$CODEX_AUTH" "$WORK/plan-only.json" "$WORK/suite.json" "$CONCURRENCY" "$CODEX_SKIP" <<'PY'
   787 | import base64, json, math, os, sys, time
   788 | auth, plan_p, suite_p, conc, skip = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5] == "true"
   789 | plan = json.load(open(plan_p)); suite = json.load(open(suite_p))
   790 | defs = {a.get("id"): a for a in suite.get("arms") or []}
   791 | iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
   792 | def uses_codex(a):   # a0_bare (loa_mount: false) never runs the dissent
   793 |     return ((defs.get(a) or {}).get("toggles") or {}).get("loa_mount") is not False
   794 | arms = sorted({e["arm"] for e in plan if uses_codex(e["arm"])})
   795 | present = os.path.isfile(auth)
>  796 | pf = {"checked": False, "auth_file_present": present, "codex_arms": arms, "token_exp": None, "required_until": None}
>  797 | out = {"preflight": pf, "refuse": None, "warn": None}
   798 | def done():
   799 |     print(json.dumps(out, sort_keys=True)); sys.exit(0)
   800 | if skip or not arms:
   801 |     done()
   802 | if not present:
   803 |     out["warn"] = "run-ablation: WARN no codex auth.json under %s; codex-using arms will run without the OpenAI voice" % os.path.dirname(auth)
   804 |     done()
   805 | now = time.time()
   806 | required = int(math.ceil(now + 2 * sum(float(e.get("watchdog_s") or 0) for e in plan) / max(conc, 1)))
   807 | pf["required_until"] = iso(required)
   808 | def bad(why):
   809 |     out["refuse"] = "codex auth.json %s: %s (KF-048) — run codex login on the host" % (auth, why); done()
~~~~

The change from head to the fix:

~~~~diff
@@ -796,2 +837,3 @@
-pf = {"checked": False, "auth_file_present": present, "codex_arms": arms, "token_exp": None, "required_until": None}
-out = {"preflight": pf, "refuse": None, "warn": None}
+pf = {"checked": False, "auth_file_present": present, "codex_arms": arms, "token_exp": None, "required_until": None,
+      "auth_mode": None, "trials_counted": None, "horizon_source": None}
+out = {"preflight": pf, "refuse": None, "warn": None, "note": None}
~~~~

## H16 — evals/harness/run-ablation.sh — head lines 805–817

Head context (head/evals/harness/run-ablation.sh, lines 793–829):

~~~~text
   793 |     return ((defs.get(a) or {}).get("toggles") or {}).get("loa_mount") is not False
   794 | arms = sorted({e["arm"] for e in plan if uses_codex(e["arm"])})
   795 | present = os.path.isfile(auth)
   796 | pf = {"checked": False, "auth_file_present": present, "codex_arms": arms, "token_exp": None, "required_until": None}
   797 | out = {"preflight": pf, "refuse": None, "warn": None}
   798 | def done():
   799 |     print(json.dumps(out, sort_keys=True)); sys.exit(0)
   800 | if skip or not arms:
   801 |     done()
   802 | if not present:
   803 |     out["warn"] = "run-ablation: WARN no codex auth.json under %s; codex-using arms will run without the OpenAI voice" % os.path.dirname(auth)
   804 |     done()
>  805 | now = time.time()
>  806 | required = int(math.ceil(now + 2 * sum(float(e.get("watchdog_s") or 0) for e in plan) / max(conc, 1)))
>  807 | pf["required_until"] = iso(required)
>  808 | def bad(why):
>  809 |     out["refuse"] = "codex auth.json %s: %s (KF-048) — run codex login on the host" % (auth, why); done()
>  810 | try:
>  811 |     data = json.loads(open(auth, "rb").read().decode("utf-8"))
>  812 | except Exception:
>  813 |     bad("is not JSON")
>  814 | tok = (data.get("tokens") if isinstance(data, dict) else None) or {}
>  815 | at = tok.get("access_token") if isinstance(tok, dict) else None
>  816 | if not isinstance(at, str) or not at:
>  817 |     bad("has no tokens.access_token")
   818 | parts = at.split(".")
   819 | if len(parts) != 3:
   820 |     bad("tokens.access_token is not a three-part JWT")
   821 | try:
   822 |     seg = parts[1] + "=" * (-len(parts[1]) % 4)
   823 |     claims = json.loads(base64.urlsafe_b64decode(seg.encode("ascii")).decode("utf-8"))
   824 | except Exception:
   825 |     bad("the access token's JWT payload does not decode")
   826 | exp = claims.get("exp") if isinstance(claims, dict) else None
   827 | if isinstance(exp, bool) or not isinstance(exp, (int, float)) or not math.isfinite(exp):
   828 |     bad("the access token has no numeric exp claim")
   829 | exp = int(exp)
~~~~

The change from head to the fix:

~~~~diff
@@ -805,13 +847,52 @@
+def pending():   # STATUS.json rerun_pending: flagged by an earlier invocation, no replacement row yet
+    try:
+        v = json.load(open(scope["status"], "rb")).get("rerun_pending")
+    except Exception:
+        return set()
+    return {x for x in v if isinstance(x, str) and x} if isinstance(v, list) else set()
+def remaining():   # the plan entries this invocation will launch (a superset on rerun_pending; see the header)
+    if not scope["resume"] or not os.path.isfile(scope["rows"]):
+        return plan
+    st = {}
+    for line in open(scope["rows"], "rb"):
+        try:
+            r = json.loads(line.decode("utf-8"))
+        except Exception:
+            continue
+        if isinstance(r, dict) and r.get("batch") == scope["batch"] and isinstance(r.get("run_id"), str):
+            st[r["run_id"]] = r.get("status")
+    ids, sts, rerow = ({x for x in scope[k] if x} for k in ("rerun_ids", "rerun_statuses", "rerow_ids"))   # json_array of none is [""]
+    pend = pending() - rerow
+    return [e for e in plan if e["run_id"] not in st or e["run_id"] in ids or e["run_id"] in pend
+            or (st[e["run_id"]] in sts and e["run_id"] not in rerow)]
 now = time.time()
-required = int(math.ceil(now + 2 * sum(float(e.get("watchdog_s") or 0) for e in plan) / max(conc, 1)))
+todo = remaining()
+pf["trials_counted"] = len(todo)
+if override is not None:
+    required = int(math.ceil(now + override)); pf["horizon_source"] = "override"
+else:
+    # DISS-C-001: never below one trial's own deadline (one trial at concurrency 3 still takes its whole watchdog)
+    wds = [float(e.get("watchdog_s") or 0) for e in todo]
+    required = int(math.ceil(now + 2 * max(sum(wds) / max(conc, 1), max(wds or [0]))))
+    pf["horizon_source"] = "plan"
 pf["required_until"] = iso(required)
-def bad(why):
-    out["refuse"] = "codex auth.json %s: %s (KF-048) — run codex login on the host" % (auth, why); done()
+REMEDY = "run codex login on the host, or set OPENAI_API_KEY in auth.json"
+def bad(why, remedy="run codex login on the host"):
+    out["refuse"] = "codex auth.json %s: %s (KF-048) — %s" % (auth, why, remedy); done()
 try:
     data = json.loads(open(auth, "rb").read().decode("utf-8"))
 except Exception:
-    bad("is not JSON")
-tok = (data.get("tokens") if isinstance(data, dict) else None) or {}
+    bad("is not JSON", REMEDY)
+if not isinstance(data, dict):
+    bad("is not a JSON object", REMEDY)
+tok = data.get("tokens") or {}
 at = tok.get("access_token") if isinstance(tok, dict) else None
 if not isinstance(at, str) or not at:
-    bad("has no tokens.access_token")
+    key = data.get("OPENAI_API_KEY")
+    if isinstance(key, str) and key.strip():   # API-key mode: no access token, no refresh, no horizon
+        pf["auth_mode"] = "apikey"
+        out["note"] = ("run-ablation: codex auth.json is in API-key mode; no token horizon applies "
+                       "(KF-048 concerns the ChatGPT refresh token only)")
+        done()
+    bad("has neither a tokens.access_token nor an OPENAI_API_KEY", REMEDY)
+pf["auth_mode"] = "chatgpt"
~~~~

## H17 — evals/harness/run-ablation.sh — head lines 832–839

Head context (head/evals/harness/run-ablation.sh, lines 820–851):

~~~~text
   820 |     bad("tokens.access_token is not a three-part JWT")
   821 | try:
   822 |     seg = parts[1] + "=" * (-len(parts[1]) % 4)
   823 |     claims = json.loads(base64.urlsafe_b64decode(seg.encode("ascii")).decode("utf-8"))
   824 | except Exception:
   825 |     bad("the access token's JWT payload does not decode")
   826 | exp = claims.get("exp") if isinstance(claims, dict) else None
   827 | if isinstance(exp, bool) or not isinstance(exp, (int, float)) or not math.isfinite(exp):
   828 |     bad("the access token has no numeric exp claim")
   829 | exp = int(exp)
   830 | pf["checked"] = True; pf["token_exp"] = iso(exp)
   831 | if exp <= required:
>  832 |     out["refuse"] = ("codex access token expires %s, before the batch's required horizon %s "
>  833 |                      "(now + 2 x summed watchdog / concurrency; KF-048) — run codex login on the host") % (iso(exp), iso(required))
>  834 | done()
>  835 | PY
>  836 | )" || die "the codex token pre-flight failed"
>  837 | printf '%s' "$CODEX_PF" | jq -c '.preflight' > "$WORK/codex-preflight.json"
>  838 | CODEX_WARN="$(jq -r '.warn // ""' <<<"$CODEX_PF")"
>  839 | [[ -z "$CODEX_WARN" ]] || echo "$CODEX_WARN" >&2
   840 | CODEX_REFUSE="$(jq -r '.refuse // ""' <<<"$CODEX_PF")"
   841 | [[ -z "$CODEX_REFUSE" ]] || refuse "$CODEX_REFUSE"
   842 | PL_ARM=() PL_TASK=() PL_TYPE=() PL_KIND=() PL_TRIAL=() PL_RUN=() PL_YAML=() PL_WD=()
   843 | while IFS=$'\t' read -r a t ty k tr rid y wd; do
   844 |   PL_ARM+=("$a"); PL_TASK+=("$t"); PL_TYPE+=("$ty"); PL_KIND+=("$k"); PL_TRIAL+=("$tr"); PL_RUN+=("$rid"); PL_YAML+=("$y"); PL_WD+=("$wd")
   845 | done < <(jq -r '.[] | [.arm, .task_id, .type, .kind, (.trial | tostring), .run_id, .task_yaml, (.watchdog_s | tostring)] | @tsv' "$WORK/plan-only.json")
   846 | EST_TOTAL=0
   847 | for k in ${PL_KIND[@]+"${PL_KIND[@]}"}; do EST_TOTAL="$(fadd "$EST_TOTAL" "$(est_hint "x|$k")")"; done
   848 | N_TASKS="$(jq 'length' "$WORK/tasks.json")"
   849 | # the in-flight reservation per running trial: the largest cap among the plan's kinds (DEC-0567)
   850 | RESERVE_CAP=0
   851 | for k in ${PL_KIND[@]+"${PL_KIND[@]}"}; do
~~~~

The change from head to the fix:

~~~~diff
@@ -832,8 +913,13 @@
+    how = ("now + LOA_ABLATION_CODEX_HORIZON_S" if override is not None
+           else "now + 2 x max(summed watchdog of %d trial(s) / concurrency, longest watchdog)" % len(todo))
     out["refuse"] = ("codex access token expires %s, before the batch's required horizon %s "
-                     "(now + 2 x summed watchdog / concurrency; KF-048) — run codex login on the host") % (iso(exp), iso(required))
+                     "(%s; KF-048) — run codex login on the host") % (iso(exp), iso(required), how)
 done()
 PY
 )" || die "the codex token pre-flight failed"
-printf '%s' "$CODEX_PF" | jq -c '.preflight' > "$WORK/codex-preflight.json"
+# DISS-C-002: held in a variable, not a $WORK file (write_status may run after cleanup removed $WORK)
+CODEX_PF_JSON="$(jq -c '.preflight' <<<"$CODEX_PF")"
 CODEX_WARN="$(jq -r '.warn // ""' <<<"$CODEX_PF")"
 [[ -z "$CODEX_WARN" ]] || echo "$CODEX_WARN" >&2
+CODEX_NOTE="$(jq -r '.note // ""' <<<"$CODEX_PF")"
+[[ -z "$CODEX_NOTE" ]] || echo "$CODEX_NOTE" >&2
~~~~

## H18 — evals/harness/run-ablation.sh — head line 865

Head context (head/evals/harness/run-ablation.sh, lines 853–877):

~~~~text
   853 | done
   854 | PLAN_LINE="plan: ${#ARMS[@]} arms, $N_TASKS tasks, $PLAN_N trials, shuffle seed $SEED, est USD $EST_TOTAL (cap ${MAX_USD:-none}, run caps build $CAP_BUILD review-catch $CAP_REVIEW, in-flight reserve $RESERVE_CAP per trial, reserve $(jq -r '.caps.reserve_usd // "n/a"' <<<"$SUITE_JSON"))"
   855 | 
   856 | write_manifest() {  # write_manifest <path> <dry_run>
   857 |   local out="$1" dry="$2" harness_commit harness_dirty=false
   858 |   harness_commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
   859 |   [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- evals/harness evals/suites grimoires/loa/evals/ablation-2.0 2>/dev/null)" ]] && harness_dirty=true
   860 |   mkdir -p "$(dirname "$out")"
   861 |   printf '%s' "$DELTA" > "$WORK/delta.txt"
   862 |   printf '%s' "$GATE_JSON" > "$WORK/gate.json"
   863 |   jq -n \
   864 |     --slurpfile plan_f "$WORK/plan.json" --slurpfile suite_f "$WORK/suite.json" --slurpfile tasks_f "$WORK/tasks.json" \
>  865 |     --slurpfile gate_f "$WORK/gate.json" --rawfile delta "$WORK/delta.txt" --slurpfile cpf_f "$WORK/codex-preflight.json" \
   866 |     --arg batch "$BATCH" --argjson dry "$dry" --argjson smoke "$SMOKE" --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   867 |     --arg src "$SRC_FULL" --arg tree "$TREE" --arg hc "$harness_commit" --argjson hd "$harness_dirty" \
   868 |     --arg suite_file "${SUITE_FILE#"$REPO_ROOT"/}" --arg suite_file_path "$SUITE_FILE" --arg suite_root "$SUITE_ROOT" \
   869 |     --arg tasks_dir "$TASKS_DIR_NAME" --arg rows "$ROWS" --arg msha "$SUITE_MANIFEST_SHA" \
   870 |     --argjson arms "$(json_array "${ARMS[@]}")" --argjson tb "$TB" --argjson tr "$TR" --argjson seed "$SEED" \
   871 |     --arg fp "$FINGERPRINT" --arg image "$IMAGE" --arg digest "$IMAGE_DIGEST" --arg mode "$EXECUTOR" \
   872 |     --arg cli "$CLI_VERSION" --arg cli_raw "$CLI_RAW" --arg max_usd "$MAX_USD" --arg run_cap "$RUN_CAP" --arg cap_b "$CAP_BUILD" --arg cap_r "$CAP_REVIEW" \
   873 |     --arg hb "$HINT_BUILD" --arg hr "$HINT_REVIEW" --argjson conc "$CONCURRENCY" --argjson rw "$RETRY_WAIT" \
   874 |     --arg wdo "$WATCHDOG_OVERRIDE" --argjson grace "$WATCHDOG_GRACE" --arg gto "$GRADE_TIMEOUT_S" --arg tto "$TOOK_TIMEOUT_S" --argjson tmo "$TMO_ON" --arg prr "$PRE_REG_REF" \
   875 |     --arg corpus "$CORPUS_SHA" --arg os "$(uname -srm)" --arg bash_v "$BASH_VERSION" \
   876 |     --arg jq_v "$(jq --version 2>/dev/null)" --arg yq_v "$(yq --version 2>/dev/null)" \
   877 |     --arg py_v "$(python3 --version 2>/dev/null)" --arg git_v "$(git --version 2>/dev/null)" '
~~~~

The change from head to the fix:

~~~~diff
@@ -865 +951 @@
-    --slurpfile gate_f "$WORK/gate.json" --rawfile delta "$WORK/delta.txt" --slurpfile cpf_f "$WORK/codex-preflight.json" \
+    --slurpfile gate_f "$WORK/gate.json" --rawfile delta "$WORK/delta.txt" --argjson cpf "$CODEX_PF_JSON" \
~~~~

## H19 — evals/harness/run-ablation.sh — head line 903

Head context (head/evals/harness/run-ablation.sh, lines 891–915):

~~~~text
   891 |        cli_version: $cli, cli_version_raw: $cli_raw,
   892 |        tools: ($s.phase_defaults.tools // null), phase_models: ($s.phase_defaults.models // {}),
   893 |        caps: {cycle_usd: ($s.caps.cycle_usd // null), run_usd: ($run_cap | tonumber), reserve_usd: ($s.caps.reserve_usd // null),
   894 |               max_usd: (if $max_usd == "" then null else ($max_usd | tonumber) end),
   895 |               run_usd_by_type: {build: ($cap_b | tonumber), "review-catch": ($cap_r | tonumber)}},
   896 |        cost_hint: {build: ($hb | tonumber), "review-catch": ($hr | tonumber)},
   897 |        concurrency: $conc, retry: {transport_retries: 1, wait_s: $rw},
   898 |        watchdog: {multiplier: 2, override_s: (if $wdo == "" then null else ($wdo | tonumber) end), grace_s: $grace,
   899 |                  grade_timeout_s: (if $tmo then ($gto | tonumber) else null end), took_effect_timeout_s: (if $tmo then ($tto | tonumber) else null end)},
   900 |        pre_registration_ref: (if $prr == "" then null else $prr end),
   901 |        gate: $g, corpus: {manifest: "evals/fixtures/review-prs/SHA256SUMS", sha256: (if $corpus == "" then null else $corpus end)},
   902 |        agy_opt_in: ($s.agy_opt_in // false),
>  903 |        codex_token_exp: $cpf_f[0].token_exp, codex_preflight: $cpf_f[0],
   904 |        environment: {os: $os, bash: $bash_v, jq: $jq_v, yq: $yq_v, python: $py_v, git: $git_v}}' > "$out.tmp"
   905 |   mv "$out.tmp" "$out"
   906 | }
   907 | 
   908 | if [[ "$DRY_RUN" == true ]]; then
   909 |   mpath="$MAN_PATH"; [[ -f "$BATCH_DIR/STATUS.json" ]] && mpath="$BATCH_DIR/MANIFEST.dry-run.json"
   910 |   write_manifest "$mpath" true
   911 |   echo "run-ablation (dry run): batch=$BATCH source=${SRC_FULL:0:12} executor=$EXECUTOR image=$IMAGE cli=$CLI_VERSION tree=$TREE"
   912 |   echo "$PLAN_LINE"
   913 |   jq -r '.refused[] | "refused: \(.arm) \(.task_id) \(.type) (task_types \(.task_types | tojson)) DEC-0405"' "$WORK/plan.json"
   914 |   jq -r '.[] | "\(.arm) \(.task_id) \(.type) \(.trial) \(.run_id)"' "$WORK/plan-only.json"
   915 |   echo "manifest: $mpath"
~~~~

The change from head to the fix:

~~~~diff
@@ -903 +989 @@
-       codex_token_exp: $cpf_f[0].token_exp, codex_preflight: $cpf_f[0],
+       codex_token_exp: ($cpf // {}).token_exp, codex_preflight: $cpf,
~~~~

## H20 — evals/harness/run-ablation.sh — head line 1076

Head context (head/evals/harness/run-ablation.sh, lines 1064–1088):

~~~~text
  1064 |       '. + {($a): {trials_planned: $p, launched: $l, completed: $c, failed: $f, excluded: $x, cap_failures: $cap,
  1065 |                    degraded: $d, skipped_paused: $s}}' <<<"$per")"
  1066 |   done
  1067 |   [[ "$STATE" != running ]] && finished="\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  1068 |   jq -n --arg batch "$BATCH" --argjson smoke "$SMOKE" --arg state "$STATE" --argjson per "$per" \
  1069 |     --argjson retries "$RETRIES_JSON" --argjson cuts "$CUTS_JSON" --argjson paused "$PAUSED_JSON" \
  1070 |     --arg rows_usd "$ROWS_USD" --arg ledger "$LEDGER_USD" --arg spent "$SPENT" --arg max "$MAX_USD" \
  1071 |     --argjson assumed "$ASSUMED_CAP" --argjson cursor "$(resume_cursor)" --argjson drift "$DRIFT_JSON" \
  1072 |     --argjson invalid "$ROWS_INVALID" --arg started "$STARTED" --argjson finished "$finished" \
  1073 |     --arg src "$SRC_FULL" --arg rows "$ROWS" --argjson planned "$PLAN_N" --argjson signalled "$SIGNALLED" \
  1074 |     --argjson ebr "$EXTRA_RUNS_JSON" --argjson cleared "$DRIFT_CLEARED_JSON" --argjson rerowed "$REROWED_JSON" \
  1075 |     --argjson rerun "$RERUN_JSON" --argjson pending "$(printf '%s' "$RERUN_LIST" | sed '/^$/d' | jq -R . | jq -sc .)" \
> 1076 |     --argjson outage "$OUTAGE_JSON" --argjson ohist "$OUTAGE_HISTORY_JSON" \
  1077 |     '{schema_version: 1, suite: "ablation-2.0", batch: $batch, smoke: $smoke, state: $state, per_arm: $per,
  1078 |       retries: $retries, cuts: $cuts, paused_arms: $paused,
  1079 |       spend: {rows_usd: ($rows_usd | tonumber), ledger_usd: ($ledger | tonumber), spent_usd: ($spent | tonumber),
  1080 |               max_usd: (if $max == "" then null else ($max | tonumber) end), assumed_cap_trials: $assumed},
  1081 |       trials_planned: $planned, resume_cursor: $cursor, drift: $drift, drift_cleared: $cleared, rerowed: $rerowed,
  1082 |       rerun: $rerun, rerun_pending: $pending, outage: $outage, outage_history: $ohist,
  1083 |       extra_models: ([$ebr | to_entries[] | .value | to_entries[]] | group_by(.key)
  1084 |                      | map({key: .[0].key, value: {runs: length, output_tokens: (map(.value) | add)}}) | from_entries),
  1085 |       extra_models_by_run: $ebr, rows_invalid: $invalid, signalled: $signalled,
  1086 |       source_commit: $src, rows_file: $rows, started: $started, finished: $finished}' > "$BATCH_DIR/STATUS.json.tmp"
  1087 |   mv "$BATCH_DIR/STATUS.json.tmp" "$BATCH_DIR/STATUS.json"
  1088 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -1076 +1162 @@
-    --argjson outage "$OUTAGE_JSON" --argjson ohist "$OUTAGE_HISTORY_JSON" \
+    --argjson outage "$OUTAGE_JSON" --argjson ohist "$OUTAGE_HISTORY_JSON" --argjson cpf "$CODEX_PF_JSON" \
~~~~

## H21 — evals/harness/run-ablation.sh — insertion after head line 1082

Head context (head/evals/harness/run-ablation.sh, lines 1071–1094):

~~~~text
  1071 |     --argjson assumed "$ASSUMED_CAP" --argjson cursor "$(resume_cursor)" --argjson drift "$DRIFT_JSON" \
  1072 |     --argjson invalid "$ROWS_INVALID" --arg started "$STARTED" --argjson finished "$finished" \
  1073 |     --arg src "$SRC_FULL" --arg rows "$ROWS" --argjson planned "$PLAN_N" --argjson signalled "$SIGNALLED" \
  1074 |     --argjson ebr "$EXTRA_RUNS_JSON" --argjson cleared "$DRIFT_CLEARED_JSON" --argjson rerowed "$REROWED_JSON" \
  1075 |     --argjson rerun "$RERUN_JSON" --argjson pending "$(printf '%s' "$RERUN_LIST" | sed '/^$/d' | jq -R . | jq -sc .)" \
  1076 |     --argjson outage "$OUTAGE_JSON" --argjson ohist "$OUTAGE_HISTORY_JSON" \
  1077 |     '{schema_version: 1, suite: "ablation-2.0", batch: $batch, smoke: $smoke, state: $state, per_arm: $per,
  1078 |       retries: $retries, cuts: $cuts, paused_arms: $paused,
  1079 |       spend: {rows_usd: ($rows_usd | tonumber), ledger_usd: ($ledger | tonumber), spent_usd: ($spent | tonumber),
  1080 |               max_usd: (if $max == "" then null else ($max | tonumber) end), assumed_cap_trials: $assumed},
  1081 |       trials_planned: $planned, resume_cursor: $cursor, drift: $drift, drift_cleared: $cleared, rerowed: $rerowed,
  1082 |       rerun: $rerun, rerun_pending: $pending, outage: $outage, outage_history: $ohist,
  1083 |       extra_models: ([$ebr | to_entries[] | .value | to_entries[]] | group_by(.key)
  1084 |                      | map({key: .[0].key, value: {runs: length, output_tokens: (map(.value) | add)}}) | from_entries),
  1085 |       extra_models_by_run: $ebr, rows_invalid: $invalid, signalled: $signalled,
  1086 |       source_commit: $src, rows_file: $rows, started: $started, finished: $finished}' > "$BATCH_DIR/STATUS.json.tmp"
  1087 |   mv "$BATCH_DIR/STATUS.json.tmp" "$BATCH_DIR/STATUS.json"
  1088 | }
  1089 | 
  1090 | cleanup() {
  1091 |   local f p
  1092 |   for f in "$JOBS_DIR"/*.pgid; do
  1093 |     [[ -f "$f" ]] || continue
  1094 |     read -r p _ < "$f" || continue
~~~~

The change from head to the fix:

~~~~diff
@@ -1082,0 +1169 @@
+      codex_preflight: $cpf,
~~~~

## H22 — evals/tests/ablation-grade.bats — head line 1136

Head context (head/evals/tests/ablation-grade.bats, lines 1124–1137):

~~~~text
  1124 |   bash_case null $'python3 - <<\'PY\'\nprint(1)\nPY'
  1125 |   [ "$(G '.heredoc_interpreters')" = 1 ]
  1126 |   bash_case null $'cat <<EOF\nx\nEOF'
  1127 |   [ "$(G '.heredoc_interpreters')" = 0 ]
  1128 |   RD="$T/interp"; make_run rc-x "$RD"
  1129 |   tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'cd /workspace && python3 - <<\'PY\'\nprint(1)\nPY' '{command: $c}')"
  1130 |   tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'bash <<EOF\necho hi\nEOF\n/usr/bin/node - <<JS\nconsole.log(1)\nJS' '{command: $c}')"
  1131 |   tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'X=1 perl <<EOF\nprint 1\nEOF\ncat <<EOF | sh\nls\nEOF\npython3.11 <<"PY"\nprint(2)\nPY' '{command: $c}')"
  1132 |   grade "$RD" rc-x
  1133 |   [ "$status" -eq 0 ]
  1134 |   [ "$(G '.contaminated')" = null ]
  1135 |   [ "$(G '.heredoc_interpreters')" = 5 ]
> 1136 |   [ "$(G '.grader_version')" = 1.2.11 ]
  1137 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -1136 +1136,191 @@
-  [ "$(G '.grader_version')" = 1.2.11 ]
+  [ "$(G '.grader_version')" = 1.2.13 ]
+}
+
+# --- grader 1.2.12: the collision removal reaches only pytest-collectable, package-less test modules --------------
+
+# hidden_add <rel-src> <rel-dest>: one more hidden manifest entry on bf-py (src under hidden/ must already exist)
+hidden_add() {
+  local m="$S/tasks/bf-py/hidden/manifest.json"
+  jq --arg s "$1" --arg d "$2" '.files += [{src: $s, dest: $d}]' "$m" > "$m.tmp" && mv "$m.tmp" "$m"
+}
+
+@test "AG-36 basename collisions (1.2.12): an agent helper module in a package keeps its file although the fixture has tests/helpers.py" {
+  printf 'X = 1\n' > "$S/tasks/bf-py/fixture/tests/helpers.py"
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  mkdir -p "$RD/sandbox/src/pkg"
+  : > "$RD/sandbox/src/pkg/__init__.py"
+  printf 'def helper():\n    return 1\n' > "$RD/sandbox/src/pkg/helpers.py"
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 0 ]
+  [ -f "$RD/grading/final/src/pkg/helpers.py" ]
+  [ -f "$RD/grading/final/tests/helpers.py" ]
+  [ ! -s "$RD/grading/final.colliding-removed.txt" ]
+}
+
+@test "AG-37 basename collisions (1.2.12): a package-less agent tests/test_x.py beside a hidden tests/hidden/test_x.py is still removed and listed; the agent helpers.py beside a hidden helpers.py stays" {
+  printf 'def test_x_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/tests/test_x.py"
+  printf 'H = 1\n' > "$S/tasks/bf-py/hidden/tests/helpers.py"
+  hidden_add tests/test_x.py tests/hidden/test_x.py
+  hidden_add tests/helpers.py tests/hidden/helpers.py
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  printf 'def test_x_mine():\n    assert True\n' > "$RD/sandbox/tests/test_x.py"
+  printf 'def helper():\n    return 1\n' > "$RD/sandbox/src/textkit/helpers.py"   # 1.2.11 removed this too
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 1 ]
+  [ ! -e "$RD/grading/final/tests/test_x.py" ]
+  [ -f "$RD/grading/final/tests/hidden/test_x.py" ]
+  [ -f "$RD/grading/final/src/textkit/helpers.py" ]
+  grep -qx 'tests/test_x.py' "$RD/grading/final.colliding-removed.txt"
+  [ "$(wc -l < "$RD/grading/final.colliding-removed.txt" | tr -d ' ')" = 1 ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]   # the 7 slug cases + the hidden test_x
+}
+
+@test "AG-38 basename collisions (1.2.12): an agent test module inside a package (tests/pkg/__init__.py) shares a hidden basename and stays" {
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  mkdir -p "$RD/sandbox/tests/pkg"
+  : > "$RD/sandbox/tests/pkg/__init__.py"
+  printf 'def test_pkg_mine():\n    assert True\n' > "$RD/sandbox/tests/pkg/test_slug.py"   # basename of the hidden tests/test_slug.py
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 0 ]
+  [ -f "$RD/grading/final/tests/pkg/test_slug.py" ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]   # pytest collects both: the packaged module is pkg.test_slug
+}
+
+@test "AG-39 basename collisions (1.2.12): a directory overlay's test_y.py reserves its basename; a package-less agent tests/test_y.py is removed" {
+  mkdir -p "$S/tasks/bf-py/hidden/suite"
+  printf 'def test_y_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/suite/test_y.py"
+  printf 'Y = 2\n' > "$S/tasks/bf-py/hidden/suite/support.py"
+  hidden_add suite tests/suite
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  printf 'def test_y_mine():\n    assert True\n' > "$RD/sandbox/tests/test_y.py"
+  mkdir -p "$RD/sandbox/lib"
+  printf 'Z = 3\n' > "$RD/sandbox/lib/support.py"   # a helper basename of the overlay dir: never reserved
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 1 ]
+  [ ! -e "$RD/grading/final/tests/test_y.py" ]
+  [ -f "$RD/grading/final/tests/suite/test_y.py" ]
+  [ -f "$RD/grading/final/lib/support.py" ]
+  grep -qx 'tests/test_y.py' "$RD/grading/final.colliding-removed.txt"
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]
+}
+
+@test "AG-40 basename collisions (1.2.12): hidden __init__.py and _oracle_z.py overlays never make the agent's own __init__.py or _oracle_z.py candidates" {
+  mkdir -p "$S/tasks/bf-py/hidden/tests/oracle"
+  : > "$S/tasks/bf-py/hidden/tests/oracle/__init__.py"
+  printf 'ORACLE = 1\n' > "$S/tasks/bf-py/hidden/tests/oracle/_oracle_z.py"
+  hidden_add tests/oracle/__init__.py tests/oracle/__init__.py
+  hidden_add tests/oracle/_oracle_z.py tests/oracle/_oracle_z.py
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  mkdir -p "$RD/sandbox/src/newpkg" "$RD/sandbox/scripts"
+  : > "$RD/sandbox/src/newpkg/__init__.py"
+  printf 'Z = 1\n' > "$RD/sandbox/src/newpkg/_oracle_z.py"
+  printf 'Z = 2\n' > "$RD/sandbox/scripts/_oracle_z.py"   # package-less, but not pytest-collectable
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 0 ]
+  [ -f "$RD/grading/final/src/newpkg/__init__.py" ]
+  [ -f "$RD/grading/final/src/newpkg/_oracle_z.py" ]
+  [ -f "$RD/grading/final/scripts/_oracle_z.py" ]
+}
+
+# --- grader 1.2.13: pytest import names, helper shadowing, the fixture's python_files ------------------------------
+
+# pyini <python_files value or empty>: the bf-py fixture's pytest.ini, with that python_files line when one is given
+pyini() {
+  if [[ -n "$1" ]]; then printf '[pytest]\npython_files = %s\n' "$1"; else printf '[pytest]\n'; fi > "$S/tasks/bf-py/fixture/pytest.ini"
+}
+
+@test "AG-41 import names (1.2.13, DISS-001): an agent tests/pkg/test_x.py is pkg.test_x like the hidden tests/hidden/pkg/test_x.py and is removed; tests/other/test_x.py stays" {
+  mkdir -p "$S/tasks/bf-py/hidden/tests/pkg"
+  : > "$S/tasks/bf-py/hidden/tests/pkg/__init__.py"
+  printf 'def test_x_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/tests/pkg/test_x.py"
+  hidden_add tests/pkg/__init__.py tests/hidden/pkg/__init__.py
+  hidden_add tests/pkg/test_x.py tests/hidden/pkg/test_x.py
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  mkdir -p "$RD/sandbox/tests/pkg" "$RD/sandbox/tests/other"
+  : > "$RD/sandbox/tests/pkg/__init__.py"
+  printf 'def test_x_mine():\n    assert True\n' > "$RD/sandbox/tests/pkg/test_x.py"
+  : > "$RD/sandbox/tests/other/__init__.py"
+  printf 'def test_x_other():\n    assert True\n' > "$RD/sandbox/tests/other/test_x.py"   # other.test_x: no clash
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 1 ]
+  [ ! -e "$RD/grading/final/tests/pkg/test_x.py" ]
+  [ -f "$RD/grading/final/tests/other/test_x.py" ]
+  [ -f "$RD/grading/final/tests/hidden/pkg/test_x.py" ]
+  [ "$(cat "$RD/grading/final.colliding-removed.txt")" = tests/pkg/test_x.py ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "9/9" ]   # 7 slug cases + the hidden pkg.test_x + the agent's other.test_x
+}
+
+@test "AG-42 helper shadowing (1.2.13, DISS-C-005): an agent _oracle_q.py beside its own test module goes with that module so the hidden import _oracle_q gets the oracle; with no test module beside it it stays" {
+  printf 'Q = 1\n' > "$S/tasks/bf-py/hidden/tests/_oracle_q.py"
+  printf 'import _oracle_q\n\n\ndef test_q():\n    assert _oracle_q.Q == 1\n' > "$S/tasks/bf-py/hidden/tests/test_q.py"
+  hidden_add tests/_oracle_q.py tests/hidden/_oracle_q.py
+  hidden_add tests/test_q.py tests/hidden/test_q.py
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  mkdir -p "$RD/sandbox/tests/api" "$RD/sandbox/src/app" "$RD/sandbox/tests/lib"
+  printf 'Q = 2\n' > "$RD/sandbox/tests/api/_oracle_q.py"
+  printf 'import _oracle_q\n\n\ndef test_api():\n    assert _oracle_q.Q\n' > "$RD/sandbox/tests/api/test_api.py"   # imported first (api < hidden): Q = 2 would answer the hidden import
+  printf 'Q = 3\n' > "$RD/sandbox/src/app/_oracle_q.py"     # no test module beside it: never on sys.path by pytest
+  printf 'Q = 4\n' > "$RD/sandbox/tests/lib/_oracle_q.py"   # tests/lib holds no collectable module
+  printf 'N = 1\n' > "$RD/sandbox/tests/lib/notes.py"
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 2 ]
+  [ ! -e "$RD/grading/final/tests/api/_oracle_q.py" ]
+  [ ! -e "$RD/grading/final/tests/api/test_api.py" ]   # left alone, its import _oracle_q would abort collection
+  [ -f "$RD/grading/final/src/app/_oracle_q.py" ]
+  [ -f "$RD/grading/final/tests/lib/_oracle_q.py" ]
+  [ "$(cat "$RD/grading/final.colliding-removed.txt")" = $'tests/api/_oracle_q.py\ntests/api/test_api.py' ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "8/8" ]   # 7 slug cases + the hidden test_q (oracle Q == 1)
+}
+
+@test "AG-43 python_files (1.2.13, DISS-C-004): a fixture pytest.ini python_files = check_*.py makes tests/check_x.py collide with a hidden tests/hidden/check_x.py; with no setting both stay; collision_rule records the patterns" {
+  printf 'def test_check_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/tests/check_x.py"
+  hidden_add tests/check_x.py tests/hidden/check_x.py
+  pyini 'check_*.py'
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  printf 'def test_check_mine():\n    assert True\n' > "$RD/sandbox/tests/check_x.py"
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 1 ]
+  [ ! -e "$RD/grading/final/tests/check_x.py" ]
+  [ "$(G '.collision_rule | "\(.python_files | join(","))|\(.source)"')" = 'check_*.py|pytest.ini' ]
+  pyini ''
+  RD="$T/plain"; make_run bf-py "$RD"; apply_ref "$RD"
+  printf 'def test_check_mine():\n    assert True\n' > "$RD/sandbox/tests/check_x.py"
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.colliding_tests_removed')" = 0 ]
+  [ -f "$RD/grading/final/tests/check_x.py" ]
+  [ "$(G '.collision_rule | "\(.python_files | join(","))|\(.source)"')" = 'test_*.py,*_test.py|default' ]
+}
+
+@test "AG-44 python_files sources (1.2.13): pyproject.toml (array and string), tox.ini [pytest], setup.cfg [tool:pytest] and test_command -o are read; a tox.ini without [pytest] is not" {
+  printf 'def test_check_hidden():\n    assert True\n' > "$S/tasks/bf-py/hidden/tests/check_x.py"
+  hidden_add tests/check_x.py tests/hidden/check_x.py
+  local fx="$S/tasks/bf-py/fixture" n=0 shape want
+  rm -f "$fx/pytest.ini"
+  for shape in toml-array toml-string tox cfg tox-nosection override; do
+    rm -f "$fx/pyproject.toml" "$fx/tox.ini" "$fx/setup.cfg"
+    want=1
+    case "$shape" in
+      toml-array) printf '[project]\nname = "x"\n\n[tool.pytest.ini_options]\npython_files = ["check_*.py", "test_*.py"]\n' > "$fx/pyproject.toml"; src=pyproject.toml ;;
+      toml-string) printf '[tool.pytest.ini_options]\npython_files = "check_*.py test_*.py"\n' > "$fx/pyproject.toml"; src=pyproject.toml ;;
+      tox) printf '[tox]\nenvlist = py\n\n[pytest]\npython_files =\n    check_*.py\n    test_*.py\n' > "$fx/tox.ini"; src=tox.ini ;;
+      cfg) printf '[metadata]\nname = x\n\n[tool:pytest]\npython_files = check_*.py test_*.py\n' > "$fx/setup.cfg"; src=setup.cfg ;;
+      tox-nosection) printf '[tox]\nenvlist = py\n' > "$fx/tox.ini"; src=default; want=0 ;;
+      override) sed -i 's/^test_command: .*/test_command: ["python3", "-m", "pytest", "-q", "-o", "python_files=check_*.py test_*.py", "tests"]/' "$S/tasks/bf-py/task.yaml"; src=test_command ;;
+    esac
+    n=$((n+1)); RD="$T/r$n"; make_run bf-py "$RD"; apply_ref "$RD"
+    printf 'def test_check_mine():\n    assert True\n' > "$RD/sandbox/tests/check_x.py"
+    grade "$RD" bf-py
+    echo "$shape: status=$status rule=$(G '.collision_rule') removed=$(G '.colliding_tests_removed')"
+    [ "$status" -eq 0 ]
+    [ "$(G '.collision_rule.source')" = "$src" ]
+    [ "$(G '.colliding_tests_removed')" = "$want" ]
+  done
~~~~

## H23 — evals/tests/pipeline-run.bats — insertion after head line 984

Head context (head/evals/tests/pipeline-run.bats, lines 973–984):

~~~~text
   973 |   ! grep -q 'codex/auth.json' "$T/dlog/run-1.mounts"
   974 | }
   975 | 
   976 | @test "container: KF-048 — a JSON auth.json that is not an object is unreadable too" {
   977 |   printf '[1, 2]\n' > "$T/home/.codex/auth.json"
   978 |   snap_docker
   979 |   run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
   980 |     --suite-file "$T/suite.yaml" --executor container --docker-bin "$T/docker"
   981 |   [ "$status" -eq 0 ]
   982 |   grep -q 'pipeline-run: WARN codex auth.json unreadable' <<<"$output"
   983 |   [ ! -e "$T/snap/.codex/auth.json" ]
   984 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -984,0 +985,27 @@
+
+@test "container: audit DISS-C-001 — an API-key auth.json is copied without the key (WARN) unless LOA_EVAL_CODEX_APIKEY_COPY=1; a ChatGPT-mode file drops a stray key" {
+  printf '{"OPENAI_API_KEY": "sk-test-dummy-key", "auth_mode": "apikey"}\n' > "$T/home/.codex/auth.json"
+  snap_docker
+  run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r1 --trial 1 --source-tree "$T/src" \
+    --suite-file "$T/suite.yaml" --executor container --docker-bin "$T/docker"
+  [ "$status" -eq 0 ]
+  [ "$(grep -c 'pipeline-run: WARN codex auth.json is in API-key mode; the key is not copied' <<<"$output")" -eq 1 ]
+  jq -e '.OPENAI_API_KEY == null and .auth_mode == "apikey"' "$T/snap/.codex/auth.json"
+  ! grep -q 'sk-test-dummy-key' "$T/snap/.codex/auth.json"
+  ! tr '\0' '\n' < "$T/dlog/run-1.argv" | grep -q 'sk-test-dummy-key'
+  # the operator accepts the exposure
+  find "$T/run" -mindepth 1 -delete; find "$T/snap" -mindepth 1 -delete 2>/dev/null; rmdir "$T/snap" 2>/dev/null || true
+  LOA_EVAL_CODEX_APIKEY_COPY=1 run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r2 --trial 1 --source-tree "$T/src" \
+    --suite-file "$T/suite.yaml" --executor container --docker-bin "$T/docker"
+  [ "$status" -eq 0 ]
+  ! grep -q 'the key is not copied' <<<"$output"
+  jq -e '.OPENAI_API_KEY == "sk-test-dummy-key"' "$T/snap/.codex/auth.json"
+  # ChatGPT mode with a stray key: the key is dropped silently, the tokens stay
+  printf '{"OPENAI_API_KEY": "sk-test-dummy-key", "auth_mode": "chatgpt", "tokens": {"access_token": "x.y.z", "refresh_token": "R", "id_token": "i.d.t", "account_id": "acct-1"}}\n' > "$T/home/.codex/auth.json"
+  find "$T/run" -mindepth 1 -delete; find "$T/snap" -mindepth 1 -delete 2>/dev/null; rmdir "$T/snap" 2>/dev/null || true
+  run "$PR" --task-yaml "$BUILD" --arm a1_full --run-dir "$T/run" --run-id r3 --trial 1 --source-tree "$T/src" \
+    --suite-file "$T/suite.yaml" --executor container --docker-bin "$T/docker"
+  [ "$status" -eq 0 ]
+  ! grep -q 'API-key mode' <<<"$output"
+  jq -e '.OPENAI_API_KEY == null and .tokens.access_token == "x.y.z" and .tokens.id_token == "i.d.t" and .tokens.refresh_token == "loa-ablation-no-refresh-token"' "$T/snap/.codex/auth.json"
+}
~~~~

## H24 — evals/tests/run-ablation.bats — head line 886

Head context (head/evals/tests/run-ablation.bats, lines 874–898):

~~~~text
   874 | exp = int(time.time()) + int(sys.argv[2])
   875 | pl = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
   876 | json.dump({"auth_mode": "chatgpt", "tokens": {"access_token": "h.%s.s" % pl, "refresh_token": "R", "account_id": "a"}},
   877 |           open(sys.argv[1], "w"))
   878 | print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(exp)))
   879 | PY
   880 | }
   881 | 
   882 | @test "RAB-28 KF-048 pre-flight: an expired codex access token with a1_full planned refuses a fresh batch (exit 2, REFUSED.txt names codex and KF-048, no MANIFEST.json)" {
   883 |   codex_auth -60 >/dev/null
   884 |   ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf1 --max-usd 100
   885 |   [ "$status" -eq 2 ]
>  886 |   grep -q 'codex access token expires .*Z, before the batch.s required horizon .*Z (now + 2 x summed watchdog / concurrency; KF-048) — run codex login on the host' "$RES/kf1/REFUSED.txt"
   887 |   [ ! -e "$RES/kf1/MANIFEST.json" ]
   888 |   [ ! -e "$T/stub.log" ]
   889 |   # no token material in the refusal
   890 |   ! grep -qE 'h\.[A-Za-z0-9_-]+\.s|"R"' "$RES/kf1/REFUSED.txt" || false
   891 |   ! grep -q 'refresh' <<<"$output"
   892 | }
   893 | 
   894 | @test "RAB-29 KF-048 pre-flight: a token that expires inside the horizon (now + 60 s; 2 x summed watchdog / concurrency is hours) is refused" {
   895 |   codex_auth 60 >/dev/null
   896 |   ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf2 --dry-run
   897 |   [ "$status" -eq 2 ]
   898 |   grep -q 'KF-048' "$RES/kf2/REFUSED.txt"
~~~~

The change from head to the fix:

~~~~diff
@@ -886 +886 @@
-  grep -q 'codex access token expires .*Z, before the batch.s required horizon .*Z (now + 2 x summed watchdog / concurrency; KF-048) — run codex login on the host' "$RES/kf1/REFUSED.txt"
+  grep -q 'codex access token expires .*Z, before the batch.s required horizon .*Z (now + 2 x max(summed watchdog of 1 trial(s) / concurrency, longest watchdog); KF-048) — run codex login on the host' "$RES/kf1/REFUSED.txt"
~~~~

## H25 — evals/tests/run-ablation.bats — head line 907

Head context (head/evals/tests/run-ablation.bats, lines 895–919):

~~~~text
   895 |   codex_auth 60 >/dev/null
   896 |   ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf2 --dry-run
   897 |   [ "$status" -eq 2 ]
   898 |   grep -q 'KF-048' "$RES/kf2/REFUSED.txt"
   899 | }
   900 | 
   901 | @test "RAB-30 KF-048 pre-flight: a fresh token (now + 10 days) is accepted; MANIFEST.json records codex_token_exp at second precision and codex_preflight" {
   902 |   local exp; exp="$(codex_auth 864000)"
   903 |   ra --arms a0_bare,a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf3 --dry-run
   904 |   [ "$status" -eq 0 ]
   905 |   M="$RES/kf3/MANIFEST.json"
   906 |   [ "$(jq -r '.codex_token_exp' "$M")" = "$exp" ]
>  907 |   [ "$(jq -c '.codex_preflight | keys' "$M")" = '["auth_file_present","checked","codex_arms","required_until","token_exp"]' ]
   908 |   [ "$(jq -r '.codex_preflight.checked' "$M")" = true ]
   909 |   [ "$(jq -r '.codex_preflight.auth_file_present' "$M")" = true ]
   910 |   [ "$(jq -c '.codex_preflight.codex_arms' "$M")" = '["a1_full"]' ]
   911 |   [ "$(jq -r '.codex_preflight.token_exp' "$M")" = "$exp" ]
   912 |   # required_until = now + 2 x (9600 + 16800) / 3 s, about 4.9 h ahead
   913 |   jq -e '.codex_preflight.required_until | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$M"
   914 |   local ru; ru="$(jq -r '.codex_preflight.required_until' "$M")"
   915 |   python3 -I -c '
   916 | import calendar, sys, time
   917 | ru = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")); d = ru - time.time()
   918 | sys.exit(0 if 17600 - 120 < d < 17600 + 5 else 1)' "$ru"
   919 |   ! grep -q 'WARN no codex auth.json' <<<"$output" || false
~~~~

The change from head to the fix:

~~~~diff
@@ -907 +907 @@
-  [ "$(jq -c '.codex_preflight | keys' "$M")" = '["auth_file_present","checked","codex_arms","required_until","token_exp"]' ]
+  [ "$(jq -c '.codex_preflight | keys' "$M")" = '["auth_file_present","auth_mode","checked","codex_arms","horizon_source","required_until","token_exp","trials_counted"]' ]
~~~~

## H26 — evals/tests/run-ablation.bats — head line 912

Head context (head/evals/tests/run-ablation.bats, lines 900–924):

~~~~text
   900 | 
   901 | @test "RAB-30 KF-048 pre-flight: a fresh token (now + 10 days) is accepted; MANIFEST.json records codex_token_exp at second precision and codex_preflight" {
   902 |   local exp; exp="$(codex_auth 864000)"
   903 |   ra --arms a0_bare,a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf3 --dry-run
   904 |   [ "$status" -eq 0 ]
   905 |   M="$RES/kf3/MANIFEST.json"
   906 |   [ "$(jq -r '.codex_token_exp' "$M")" = "$exp" ]
   907 |   [ "$(jq -c '.codex_preflight | keys' "$M")" = '["auth_file_present","checked","codex_arms","required_until","token_exp"]' ]
   908 |   [ "$(jq -r '.codex_preflight.checked' "$M")" = true ]
   909 |   [ "$(jq -r '.codex_preflight.auth_file_present' "$M")" = true ]
   910 |   [ "$(jq -c '.codex_preflight.codex_arms' "$M")" = '["a1_full"]' ]
   911 |   [ "$(jq -r '.codex_preflight.token_exp' "$M")" = "$exp" ]
>  912 |   # required_until = now + 2 x (9600 + 16800) / 3 s, about 4.9 h ahead
   913 |   jq -e '.codex_preflight.required_until | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$M"
   914 |   local ru; ru="$(jq -r '.codex_preflight.required_until' "$M")"
   915 |   python3 -I -c '
   916 | import calendar, sys, time
   917 | ru = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")); d = ru - time.time()
   918 | sys.exit(0 if 17600 - 120 < d < 17600 + 5 else 1)' "$ru"
   919 |   ! grep -q 'WARN no codex auth.json' <<<"$output" || false
   920 | }
   921 | 
   922 | @test "RAB-31 KF-048 pre-flight: an expired token with only a0_bare planned is not refused; checked false, codex_arms []" {
   923 |   codex_auth -60 >/dev/null
   924 |   ra --arms a0_bare --tasks bugfix-v2-02 --trials-build 1 --batch kf4 --dry-run
~~~~

The change from head to the fix:

~~~~diff
@@ -912 +912,3 @@
-  # required_until = now + 2 x (9600 + 16800) / 3 s, about 4.9 h ahead
+  [ "$(jq -r '.codex_preflight.auth_mode, .codex_preflight.trials_counted, .codex_preflight.horizon_source' "$M" | tr '\n' ' ')" = "chatgpt 2 plan " ]
+  # required_until = now + 2 x max((9600 + 16800) / 3, 16800) s = now + 33600 s (DISS-C-001: the longest
+  # watchdog bounds the horizon from below; the summed share alone, 17600 s, was shorter than one trial)
~~~~

## H27 — evals/tests/run-ablation.bats — head line 918

Head context (head/evals/tests/run-ablation.bats, lines 906–930):

~~~~text
   906 |   [ "$(jq -r '.codex_token_exp' "$M")" = "$exp" ]
   907 |   [ "$(jq -c '.codex_preflight | keys' "$M")" = '["auth_file_present","checked","codex_arms","required_until","token_exp"]' ]
   908 |   [ "$(jq -r '.codex_preflight.checked' "$M")" = true ]
   909 |   [ "$(jq -r '.codex_preflight.auth_file_present' "$M")" = true ]
   910 |   [ "$(jq -c '.codex_preflight.codex_arms' "$M")" = '["a1_full"]' ]
   911 |   [ "$(jq -r '.codex_preflight.token_exp' "$M")" = "$exp" ]
   912 |   # required_until = now + 2 x (9600 + 16800) / 3 s, about 4.9 h ahead
   913 |   jq -e '.codex_preflight.required_until | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$M"
   914 |   local ru; ru="$(jq -r '.codex_preflight.required_until' "$M")"
   915 |   python3 -I -c '
   916 | import calendar, sys, time
   917 | ru = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")); d = ru - time.time()
>  918 | sys.exit(0 if 17600 - 120 < d < 17600 + 5 else 1)' "$ru"
   919 |   ! grep -q 'WARN no codex auth.json' <<<"$output" || false
   920 | }
   921 | 
   922 | @test "RAB-31 KF-048 pre-flight: an expired token with only a0_bare planned is not refused; checked false, codex_arms []" {
   923 |   codex_auth -60 >/dev/null
   924 |   ra --arms a0_bare --tasks bugfix-v2-02 --trials-build 1 --batch kf4 --dry-run
   925 |   [ "$status" -eq 0 ]
   926 |   M="$RES/kf4/MANIFEST.json"
   927 |   [ "$(jq -r '.codex_preflight.checked' "$M")" = false ]
   928 |   [ "$(jq -c '.codex_preflight.codex_arms' "$M")" = '[]' ]
   929 |   [ "$(jq -r '.codex_token_exp' "$M")" = null ]
   930 |   [ ! -e "$RES/kf4/REFUSED.txt" ]
~~~~

The change from head to the fix:

~~~~diff
@@ -918 +920 @@
-sys.exit(0 if 17600 - 120 < d < 17600 + 5 else 1)' "$ru"
+sys.exit(0 if 33600 - 120 < d < 33600 + 5 else 1)' "$ru"
~~~~

## H28 — evals/tests/run-ablation.bats — head line 939

Head context (head/evals/tests/run-ablation.bats, lines 927–951):

~~~~text
   927 |   [ "$(jq -r '.codex_preflight.checked' "$M")" = false ]
   928 |   [ "$(jq -c '.codex_preflight.codex_arms' "$M")" = '[]' ]
   929 |   [ "$(jq -r '.codex_token_exp' "$M")" = null ]
   930 |   [ ! -e "$RES/kf4/REFUSED.txt" ]
   931 | }
   932 | 
   933 | @test "RAB-32 KF-048 pre-flight: no auth.json is not a refusal; one WARN line, codex_token_exp null" {
   934 |   ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf5 --dry-run
   935 |   [ "$status" -eq 0 ]
   936 |   [ "$(grep -c "^run-ablation: WARN no codex auth.json under $T/creds/.codex; codex-using arms will run without the OpenAI voice\$" <<<"$output")" -eq 1 ]
   937 |   M="$RES/kf5/MANIFEST.json"
   938 |   [ "$(jq -r '.codex_token_exp' "$M")" = null ]
>  939 |   [ "$(jq -c '.codex_preflight' "$M")" = '{"auth_file_present":false,"checked":false,"codex_arms":["a1_full"],"required_until":null,"token_exp":null}' ]
   940 | }
   941 | 
   942 | @test "RAB-33 KF-048 pre-flight: --smoke skips the check (an expired token is not refused)" {
   943 |   codex_auth -60 >/dev/null
   944 |   ra --smoke --arms a1_full --batch smoke-kf6 --dry-run
   945 |   [ "$status" -eq 0 ]
   946 |   [ ! -e "$RES/smoke-kf6/REFUSED.txt" ]
   947 |   [ "$(jq -r '.codex_preflight.checked' "$RES/smoke-kf6/MANIFEST.json")" = false ]
   948 | }
   949 | 
   950 | @test "RAB-34 KF-048 pre-flight: --dry-run with an expired token is refused (the dry run is where the operator sees it first); a malformed access token is refused too" {
   951 |   codex_auth -60 >/dev/null
~~~~

The change from head to the fix:

~~~~diff
@@ -939 +941 @@
-  [ "$(jq -c '.codex_preflight' "$M")" = '{"auth_file_present":false,"checked":false,"codex_arms":["a1_full"],"required_until":null,"token_exp":null}' ]
+  [ "$(jq -c '.codex_preflight' "$M")" = '{"auth_file_present":false,"auth_mode":null,"checked":false,"codex_arms":["a1_full"],"horizon_source":null,"required_until":null,"token_exp":null,"trials_counted":null}' ]
~~~~

## H29 — evals/tests/run-ablation.bats — insertion after head line 968

Head context (head/evals/tests/run-ablation.bats, lines 957–968):

~~~~text
   957 |   ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf8 --dry-run
   958 |   [ "$status" -eq 2 ]
   959 |   grep -q 'not a three-part JWT (KF-048)' "$RES/kf8/REFUSED.txt"
   960 |   echo '{"tokens": {"access_token": "h.e30.s"}}' > "$T/creds/.codex/auth.json"   # payload {}
   961 |   ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf9 --dry-run
   962 |   [ "$status" -eq 2 ]
   963 |   grep -q 'no numeric exp claim (KF-048)' "$RES/kf9/REFUSED.txt"
   964 |   echo 'nope' > "$T/creds/.codex/auth.json"
   965 |   ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf10 --dry-run
   966 |   [ "$status" -eq 2 ]
   967 |   grep -q 'is not JSON (KF-048)' "$RES/kf10/REFUSED.txt"
   968 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -968,0 +971,152 @@
+
+@test "RAB-35 KF-048 pre-flight (DISS-C-003): an API-key auth.json is not refused; auth_mode apikey, checked false, one stderr note, the key never printed, MANIFEST.json written" {
+  echo '{"OPENAI_API_KEY": "sk-test-dummy", "auth_mode": "apikey"}' > "$T/creds/.codex/auth.json"
+  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf11 --dry-run
+  [ "$status" -eq 0 ]
+  M="$RES/kf11/MANIFEST.json"
+  [ -f "$M" ]; [ ! -e "$RES/kf11/REFUSED.txt" ]
+  [ "$(grep -c '^run-ablation: codex auth.json is in API-key mode; no token horizon applies (KF-048 concerns the ChatGPT refresh token only)$' <<<"$output")" -eq 1 ]
+  [ "$(jq -r '.codex_preflight.auth_mode' "$M")" = apikey ]
+  [ "$(jq -r '.codex_preflight.checked' "$M")" = false ]
+  [ "$(jq -r '.codex_preflight.token_exp, .codex_token_exp' "$M" | tr '\n' ' ')" = "null null " ]
+  jq -e '.codex_preflight.required_until | test("^[0-9-]{10}T[0-9:]{8}Z$")' "$M"
+  ! grep -rq 'sk-test-dummy' "$RES" || false
+  ! grep -q 'sk-test-dummy' <<<"$output" || false
+  # tokens present but empty, the key set: still API-key mode
+  echo '{"OPENAI_API_KEY": "sk-test-dummy", "tokens": null}' > "$T/creds/.codex/auth.json"
+  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf12 --dry-run
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.codex_preflight.auth_mode' "$RES/kf12/MANIFEST.json")" = apikey ]
+}
+
+@test "RAB-36 KF-048 pre-flight (DISS-C-003): an auth.json with neither a tokens.access_token nor an OPENAI_API_KEY is refused, and the reason names both remedies" {
+  echo '{"OPENAI_API_KEY": "", "tokens": {"refresh_token": "R"}}' > "$T/creds/.codex/auth.json"
+  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf13 --dry-run
+  [ "$status" -eq 2 ]
+  grep -q 'has neither a tokens.access_token nor an OPENAI_API_KEY (KF-048) — run codex login on the host, or set OPENAI_API_KEY in auth.json' "$RES/kf13/REFUSED.txt"
+  [ ! -e "$RES/kf13/MANIFEST.json" ]
+  ! grep -q '"R"' "$RES/kf13/REFUSED.txt" || false
+}
+
+@test "RAB-37 KF-048 pre-flight (DISS-C-004): --resume counts only the trials without a row; a token that outlives one trial's horizon but not the whole plan's is not refused; trials_counted 1 in STATUS.json" {
+  codex_auth 864000 >/dev/null
+  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07 --trials-build 1 --batch kr1 --concurrency 1
+  [ "$status" -eq 0 ]
+  B="$RES/kr1"
+  [ "$(jq -r '.codex_preflight.trials_counted' "$B/MANIFEST.json")" = 4 ]
+  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 4 ]
+  # one trial's horizon is 2 x its watchdog; the whole plan's is the sum of four
+  one="$(jq -r '.plan[3].watchdog_s' "$B/MANIFEST.json")"; all="$(jq -r '[.plan[].watchdog_s] | add' "$B/MANIFEST.json")"
+  off=$(( (2 * one + 2 * all) / 2 ))
+  [ "$off" -gt $(( 2 * one + 600 )) ]; [ "$off" -lt $(( 2 * all - 600 )) ]
+  head -3 "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
+  jq '.state = "running" | .finished = null | .resume_cursor = 3' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"
+  # the same token is refused for a fresh batch of that plan (the whole plan counts)
+  codex_auth "$off" >/dev/null
+  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05,bugfix-v2-06,bugfix-v2-07 --trials-build 1 --batch kr2 --concurrency 1 --dry-run
+  [ "$status" -eq 2 ]; grep -q 'summed watchdog of 4 trial(s)' "$RES/kr2/REFUSED.txt"
+  : > "$T/stub.log"
+  ra --batch kr1 --resume --concurrency 1
+  [ "$status" -eq 0 ]
+  [ ! -e "$B/REFUSED.txt" ]
+  [ "$(wc -l < "$T/stub.log")" -eq 1 ]
+  [ "$(jq -r '.codex_preflight.trials_counted, .codex_preflight.horizon_source, .codex_preflight.checked' "$B/STATUS.json" | tr '\n' ' ')" = "1 plan true " ]
+  [ "$(jq -r '.codex_preflight.trials_counted' "$B/MANIFEST.json")" = 4 ]   # the start's record is kept
+  [ "$(jq -r '.state' "$B/STATUS.json")" = complete ]
+  # --rerun-status brings a rowed trial back into the count
+  jq -c 'if .run_id == "'"$(jq -r '.plan[0].run_id' "$B/MANIFEST.json")"'" then .status = "transport_error" else . end' "$RES/runs.jsonl" > "$T/rows" && mv "$T/rows" "$RES/runs.jsonl"
+  codex_auth 864000 >/dev/null
+  ra --batch kr1 --resume --concurrency 1 --rerun-status transport_error
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 1 ]
+}
+
+@test "RAB-38 KF-048 pre-flight (DISS-C-004): LOA_ABLATION_CODEX_HORIZON_S replaces the computed horizon (60 s against a token of 120 s, a plan of hours: not refused, horizon_source override); a non-numeric or zero value is a usage error" {
+  codex_auth 120 >/dev/null
+  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf14 --dry-run
+  [ "$status" -eq 2 ]   # the computed horizon (hours) refuses it
+  LOA_ABLATION_CODEX_HORIZON_S=60 ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf15 --dry-run
+  [ "$status" -eq 0 ]
+  M="$RES/kf15/MANIFEST.json"
+  [ "$(jq -r '.codex_preflight.horizon_source, .codex_preflight.checked, .codex_preflight.trials_counted' "$M" | tr '\n' ' ')" = "override true 1 " ]
+  local ru; ru="$(jq -r '.codex_preflight.required_until' "$M")"
+  python3 -I -c '
+import calendar, sys, time
+d = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")) - time.time()
+sys.exit(0 if 0 < d < 62 else 1)' "$ru"
+  # an override that the token does not outlive is refused, and the reason names the override
+  LOA_ABLATION_CODEX_HORIZON_S=600 ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf16 --dry-run
+  [ "$status" -eq 2 ]; grep -q 'now + LOA_ABLATION_CODEX_HORIZON_S; KF-048' "$RES/kf16/REFUSED.txt"
+  for v in abc 0 -5 1.5; do
+    LOA_ABLATION_CODEX_HORIZON_S="$v" ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kf17 --dry-run
+    [ "$status" -eq 2 ]
+    grep -q 'LOA_ABLATION_CODEX_HORIZON_S must be positive whole seconds' <<<"$output"
+    [ ! -e "$RES/kf17" ]
+  done
+}
+
+@test "RAB-39 KF-048 pre-flight (DISS-C-001): the horizon is never below one trial's own watchdog; one trial (16,800 s) at concurrency 3 with a token between 2 x w / 3 and 2 x w is refused, one past 2 x w passes" {
+  codex_auth 22400 >/dev/null   # 2 x 16800 / 3 = 11200 < 22400 < 33600 = 2 x 16800
+  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kh1 --concurrency 3 --dry-run
+  [ "$status" -eq 2 ]
+  grep -q '(now + 2 x max(summed watchdog of 1 trial(s) / concurrency, longest watchdog); KF-048) — run codex login on the host' "$RES/kh1/REFUSED.txt"
+  [ ! -e "$RES/kh1/MANIFEST.json" ]
+  codex_auth 34200 >/dev/null
+  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch kh2 --concurrency 3 --dry-run
+  [ "$status" -eq 0 ]
+  M="$RES/kh2/MANIFEST.json"
+  [ "$(jq -r '.plan[0].watchdog_s, .codex_preflight.trials_counted, .codex_preflight.checked' "$M" | tr '\n' ' ')" = "16800 1 true " ]
+  python3 -I -c '
+import calendar, sys, time
+d = calendar.timegm(time.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")) - time.time()
+sys.exit(0 if 33600 - 120 < d < 33600 + 5 else 1)' "$(jq -r '.codex_preflight.required_until' "$M")"
+}
+
+@test "RAB-40 KF-048 pre-flight (DISS-C-002): STATUS.json is written without the scratch dir: a driver signalled after its \$WORK is gone still records state partial with the pre-flight record (valid JSON, codex_preflight equal to MANIFEST's)" {
+  codex_auth 864000 >/dev/null
+  export STUB_HANG=1 TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
+  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch ks1 --detach
+  [ "$status" -eq 0 ]
+  pid="$(sed -n 's/.* pid \([0-9]*\).*/\1/p' <<<"$output")"
+  [ -n "$pid" ]
+  for _ in $(seq 1 100); do ls "$RES/ks1/.jobs/"*.pgid >/dev/null 2>&1 && break; sleep 0.2; done
+  ls "$RES/ks1/.jobs/"*.pgid >/dev/null
+  [ "$(jq -r '.state' "$RES/ks1/STATUS.json")" = running ]
+  # the scratch dir disappears under the driver (a tmp reaper, or cleanup ahead of a late write_status)
+  ls -d "$TMPDIR"/run-ablation.* >/dev/null
+  find "$TMPDIR" -mindepth 1 -delete
+  kill -TERM "$pid"
+  for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
+  ! kill -0 "$pid" 2>/dev/null || false
+  unset STUB_HANG TMPDIR
+  jq -e . "$RES/ks1/STATUS.json" >/dev/null
+  [ "$(jq -r '.state, .signalled' "$RES/ks1/STATUS.json" | tr '\n' ' ')" = "partial true " ]
+  [ "$(jq -c '.codex_preflight' "$RES/ks1/STATUS.json")" = "$(jq -c '.codex_preflight' "$RES/ks1/MANIFEST.json")" ]
+  [ "$(jq -r '.codex_preflight.checked' "$RES/ks1/STATUS.json")" = true ]
+  [ ! -e "$RES/ks1/STATUS.json.tmp" ]
+}
+
+@test "RAB-41 KF-048 pre-flight (DISS-C-003): --resume counts STATUS.json rerun_pending (a flagged trial with its old row, no replacement yet); a --rerow of that id takes it out again" {
+  codex_auth 864000 >/dev/null
+  ra --arms a1_full --tasks bugfix-v2-02,bugfix-v2-05 --trials-build 1 --batch kp1 --concurrency 1
+  [ "$status" -eq 0 ]
+  B="$RES/kp1"
+  r0="$(jq -r '.plan[0].run_id' "$B/MANIFEST.json")"
+  plant() { jq --arg r "$r0" '.state = "running" | .finished = null | .rerun_pending = [$r]' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"; }
+  plant
+  ra --batch kp1 --resume --concurrency 1
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 1 ]
+  # the planted id is not flagged again on this invocation, so the launcher keeps its row (the documented superset)
+  [ "$(jq -c '.rerun_pending' "$B/STATUS.json")" = '[]' ]
+  [ "$(wc -l < "$RES/runs.jsonl")" -eq 2 ]
+  plant
+  ra --batch kp1 --resume --concurrency 1 --rerow "$r0"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 0 ]
+  # a malformed rerun_pending is ignored, not fatal
+  jq '.state = "running" | .finished = null | .rerun_pending = {"x": 1}' "$B/STATUS.json" > "$T/st" && mv "$T/st" "$B/STATUS.json"
+  ra --batch kp1 --resume --concurrency 1
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.codex_preflight.trials_counted' "$B/STATUS.json")" = 0 ]
+}
~~~~
