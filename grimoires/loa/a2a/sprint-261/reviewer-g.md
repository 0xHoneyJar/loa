# Sprint 261 fix implementer G — grader 1.2.12 (narrowed basename-collision removal)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s4g` (branch `wt/cycle-130-s4g`, HEAD 4af3294b). Patch `~/.cache/loa/cycle-130/patches/s4-g.patch` (+ `.stat`). Nothing committed.

## What was built
- `evals/harness/ablation-grade.sh:220` header: new 1.2.12 paragraph (the rule and the reason); the 1.2.11 paragraph kept as history, retitled "narrowed by 1.2.12".
- `evals/harness/ablation-grade.sh:306` imports `fnmatch` (stdlib).
- `evals/harness/ablation-grade.sh:312` `GRADER_VERSION = "1.2.12"`.
- `evals/harness/ablation-grade.sh:1079` `PYTEST_FILES = ("test_*.py", "*_test.py")`, `:1082` `collectable(name)`.
- `evals/harness/ablation-grade.sh:1087` `remove_colliding()` rewritten. `colliding_tests_removed` in grade.json and the `grading/<label>.colliding-removed.txt` sidecar are unchanged in shape. Nothing else in the grader changed.
- `evals/tests/ablation-grade.bats`: AG-33's version literal set to 1.2.12 (AG-33 is the case that pins the version, not AG-1). A new `hidden_add` helper and AG-36…AG-40 at the end of the file.

## The exact new rule
`reserved` is the set of pytest-collectable basenames (`test_*.py` or `*_test.py`, fnmatchcase) drawn from three sources. These are the basenames of the hidden overlay file dests, every file inside a directory overlay's source (walked, links not followed) and every fixture file under a `tests/` or `test/` directory. `__init__.py`, `conftest.py` and helper modules can never be reserved. A file in the grading tree is removed only when all of these hold:
(a) its basename is reserved;
(b) its path is not an owned overlay file dest, is not inside a directory overlay dest, and does not exist in the fixture at that path;
(c) its directory has no `__init__.py` (os.path.isfile), so it is package-less for pytest's default prepend import mode.

## Tests added (fails on 1.2.11 / passes on 1.2.12, checked by swapping in the HEAD grader and restoring it)
- AG-36: the fixture has `tests/helpers.py` and the agent adds `src/pkg/helpers.py` inside a package. The file is kept and the count is 0. FAIL before, PASS after.
- AG-37: the agent adds a package-less `tests/test_x.py` while the hidden overlay has `tests/hidden/test_x.py`. The file is removed, the count is 1, the sidecar lists exactly it, and hidden tests are 8/8. The agent's `src/textkit/helpers.py` beside a hidden `tests/hidden/helpers.py` is kept. FAIL before (1.2.11 counted 2), PASS after.
- AG-38: the agent adds `tests/pkg/__init__.py` and `tests/pkg/test_slug.py`, which shares the hidden test's basename. The file is kept, the count is 0, and hidden tests are 8/8 because pytest collects both. FAIL before, PASS after.
- AG-39: a directory overlay `suite` maps to `tests/suite` and holds `test_y.py` and `support.py`. The agent's package-less `tests/test_y.py` is removed with count 1. The agent's `lib/support.py` is kept and hidden tests are 8/8. FAIL before (1.2.11 counted 0), PASS after.
- AG-40: the hidden overlays include `tests/oracle/__init__.py` and `_oracle_z.py`. The agent's `src/newpkg/__init__.py`, `src/newpkg/_oracle_z.py` and the package-less `scripts/_oracle_z.py` all stay, with count 0. FAIL before, PASS after.
- AG-35 (1.2.11's case) still passes unchanged.

## bats counts
- Before: 414/414 (`evals/tests/`, per the brief, at HEAD).
- After: 419/419 green (`bash -c '~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats evals/tests/'`).

## DECISION bullets
- DECISION: The grader parses no pytest config, so the two default `python_files` patterns are hard-coded in `PYTEST_FILES`. A fixture `python_files` override is not honoured, as the brief allows.
- DECISION: The package test is "the file's own directory has an `__init__.py` (isfile)". This matches the brief's rule (c). It does not model rootdir or `rootdir/conftest` subtleties beyond that.
- DECISION: Reserved names from directory overlays come from walking the overlay source with `followlinks=False`, and every collectable name is reserved, whatever package status the overlay's own directory has. This is the conservative reading of "from BOTH … AND the `.py` files inside directory overlays".
- DECISION: The fixture-source walk keeps 1.2.11's `tests/`/`test/` scope, now filtered to collectable names. Fixture test modules elsewhere are not reserved, which is unchanged from 1.2.11.
- DECISION: AG-37 also carries a helper-overlay assertion so it fails on 1.2.11 as the brief requires. Its kept-behaviour half alone would pass on 1.2.11.
- DECISION: The brief said AG-1 pins the version string, but the literal lives in AG-33. Only that literal was changed.

## Limitations and handoff
- The official image self-check (`--self-check` in `loa-ablation:258`, Python 3.11) and any re-grade of real run directories are the lead's. No docker or live calls were made. The code uses only 3.11-safe stdlib (fnmatch, os).
- The lead says no real grade.json has `colliding_tests_removed` > 0, so no recorded row changes. Rows graded under 1.2.11 keep their grader_version.
- The report-side fixtures in `evals/tests/ablation-report.bats` that mention 1.2.11 are data literals and were left alone.
