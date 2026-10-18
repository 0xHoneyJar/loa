# Sprint 261 fix implementer G2 — grader 1.2.13 (import-name collisions, helper shadowing, python_files)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s4g2` (branch `wt/cycle-130-s4g2`, HEAD ff7fb403). Patch `~/.cache/loa/cycle-130/patches/s4-g2.patch` (+ `.stat`). Nothing committed. Owned files only: `evals/harness/ablation-grade.sh`, `evals/tests/ablation-grade.bats` (plus this report copy).

## What was built
- `evals/harness/ablation-grade.sh:220` header paragraph for 1.2.13; the 1.2.12 paragraph is kept as history and marked "superseded by 1.2.13"; 1.2.11 kept.
- `:305` imports `configparser`, `shlex`, `tomllib` (stdlib, 3.11+).
- `:327` `GRADER_VERSION = "1.2.13"`.
- `:1094` `PYTEST_DEFAULT_FILES`, `PYTEST_INI_ORDER`; `:1099` `_ini_section`, `:1112` `_toml_section`, `:1127` `_patterns`, `:1139` `collision_rule(t)` (cached on the task).
- `:1191` `collectable(rel, pats)` (pytest's fnmatch_ex shape), `:1206` `import_name(rel, has_init)`.
- `:1217` `remove_colliding()` rewritten (import-name rule + helper rule). `colliding_tests_removed` and `grading/<label>.colliding-removed.txt` unchanged in shape.
- `:1979` `grade.json` gains `collision_rule: {python_files: [...], source}` for build tasks, `null` for review-catch. Nothing else in the grader changed.
- `evals/tests/ablation-grade.bats`: AG-33 literal → 1.2.13; `pyini` helper; AG-41 … AG-44 at the end (`:1237` …).

## The exact rule as built
Patterns: `-o`/`--override-ini python_files=…` in `test_command` wins (source `test_command`); else `-c`/`--config-file <fixture-relative file>` is read alone; else the first fixture-root file pytest would pick, in pytest's order `pytest.ini` (always picked), `.pytest.ini` (always), `pyproject.toml` (only with `[tool.pytest.ini_options]`, tomllib; array or shell-split string), `tox.ini` (only with `[pytest]`), `setup.cfg` (only with `[tool:pytest]`); configparser for the ini shapes, values shell-split (pytest's `args` type). A picked file without `python_files`, an unreadable file, or no file → defaults `test_*.py`, `*_test.py`, source `default`. `collectable`: a `.py` that is not `__init__.py`/`conftest.py` and matches a pattern (basename match; a pattern with `/` matches the path, like pytest).

Protected modules: hidden overlay file dests, every file inside a directory overlay (at its dest), fixture files under a `tests/` or `test/` directory. Each gets its prepend-mode import name: walk up while `dir/__init__.py` is in the overlay-or-fixture view (overlay dests, directory-overlay files, all fixture files); dotted path from the basedir without `.py`. Candidates: `.py` files in the grading tree that are not an overlay file dest, not inside a directory overlay dest, and not present in the fixture at that path.
1. **Collision:** a collectable candidate whose import name (from the tree's real `__init__.py` files) equals a protected collectable module's import name is removed.
2. **Helper shadow:** a protected helper is a non-collectable protected `.py` (not `__init__`/`conftest`) in a package-less view directory that pytest puts on `sys.path`: the tree root, or a directory holding a protected collectable module or a protected `conftest.py`. A non-collectable candidate (not `__init__`/`conftest`) whose stem equals such a helper's stem, in a package-less directory that still holds a collectable module after (1), is removed **together with the unowned collectable modules in that directory**.

Physics checked by hand with pytest 9.0.2 in a scratch dir: the packaged pair `tests/hidden/pkg/test_x.py` + `tests/pkg/test_x.py` aborts collection ("Interrupted: 1 error during collection"); the helper shadow bites only when an agent module in the earlier-collected directory imports the helper (hidden `assert 2 == 1`); removing the helper alone then turns the agent test's `import _oracle_q` into a collection-aborting ImportError (all tests lost), while removing helper + sibling test modules leaves the hidden test green.

## Tests added (each FAILS on the HEAD 1.2.12 grader, swapped in and restored; PASSES on 1.2.13)
- AG-41: hidden `tests/hidden/pkg/{__init__,test_x}.py` (two file overlays); agent `tests/pkg/{__init__,test_x}.py` → `tests/pkg/test_x.py` removed, count 1, sidecar exactly it; agent `tests/other/{__init__,test_x}.py` kept; hidden 9/9. Before: count 0.
- AG-42: hidden `tests/hidden/_oracle_q.py` (Q = 1) + `tests/hidden/test_q.py` (`import _oracle_q`, asserts Q == 1); agent package-less `tests/api/_oracle_q.py` (Q = 2) + `tests/api/test_api.py` importing it → both removed, count 2, sidecar lists both; agent `src/app/_oracle_q.py` kept; agent `tests/lib/_oracle_q.py` beside only `notes.py` kept; hidden 8/8. Before: count 0 and hidden 8/9 (test_q shadowed).
- AG-43: fixture `pytest.ini` `python_files = check_*.py`; hidden `tests/hidden/check_x.py`; agent `tests/check_x.py` → removed, count 1, `collision_rule` = `check_*.py` / `pytest.ini`; with `[pytest]` and no setting the same files → kept, count 0, `collision_rule` = defaults / `default`. Before: count 0 and no `collision_rule`.
- AG-44: with no `pytest.ini`, each shape grades once: pyproject array, pyproject string, tox.ini `[pytest]` (multi-line value), setup.cfg `[tool:pytest]` → source that file, removal 1; tox.ini without `[pytest]` → `default`, removal 0; `test_command` `-o python_files=…` → source `test_command`, removal 1. Before: `collision_rule` absent.
- AG-35 … AG-40 unchanged and green.

## bats counts
- Before: 423/423 (`evals/tests/`, HEAD ff7fb403).
- After: 427/427 (`bash -c '~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats evals/tests/'`).

## DECISION bullets
- DECISION: The helper rule removes the agent helper together with the unowned collectable modules in its directory, not the helper alone as the brief says. Removing the helper alone is a no-op when nothing imports it and makes things worse when an agent test imports it (collection-aborting ImportError, checked with pytest 9.0.2). AG-42 therefore expects count 2.
- DECISION: A protected helper counts only when a protected module could import it by bare name: its view directory is package-less and is the tree root or holds a protected collectable module or conftest.py. Without this, AG-43's no-config half fails, because the hidden `check_x.py` becomes a helper and the agent's `tests/check_x.py` sits beside `test_existing.py`. The brief wanted that half kept.
- DECISION: Helper matching compares the agent's bare stem with the helper's stem, and only package-less helpers qualify. Packaged helpers import by dotted name, so a bare agent module cannot shadow them.
- DECISION: Protected import names use the overlay-or-fixture view of `__init__.py` files, as briefed. Candidate names use the grading tree's real files. An agent-added `__init__.py` that changes a protected module's real import name is not modelled.
- DECISION: `pyproject.toml` is read with `tomllib` (stdlib since 3.11), not a regex. A string value is shell-split like pytest's `args` ini type.
- DECISION: `-o`/`--override-ini` and `-c`/`--config-file` are read from `test_command` only. `regression_command`, the structural command, `-p`, `addopts`, `rootdir`/`testpaths`/`pythonpath` and ini files below the fixture root (e.g. `tests/pytest.ini`) are not read.
- DECISION: AG-43 uses `python_files = check_*.py` exactly as briefed. AG-44 uses `check_*.py test_*.py` so the slug cases still run in those grades.
- DECISION: Collectability ignores which paths `test_command` passes (e.g. `--ignore=tests/structure`). Every collectable file in the tree counts, which is the conservative reading.

## Could not do / limitations
- The official image self-check (`--self-check` in `loa-ablation:258`, Python 3.11) and re-grading real run directories are the lead's. No docker and no live calls were used. The code compiles under host 3.13 with `py_compile`. Python 3.11 is not on the host. Only 3.11-safe stdlib is used.
- The helper rule can now remove agent test modules, not only agent helpers. Those are agent-added files only, and they would otherwise abort collection or shadow the oracle. Agent modules in other directories that import the removed helper are not followed.
- Package-name shadowing is not modelled. An example is an agent `tests/api/pkg.py` hiding a protected package `pkg`.
- The lead verified that no real grade.json has `colliding_tests_removed` > 0. Under 1.2.13 a real row changes only if an agent added a helper with a protected helper's stem beside its own test module. Re-grading is the check for that.
