# Fairness review — refactor-03

**Reviewer:** fairness session R2 (s2-review-r2, Claude Opus 5.5), 2026-10-15 · **Author:** implementer D · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md states the structural goal. It asks for a frozen dataclass `Config` in `fetchq.core` with four named fields and defaults that checks on construction, and for each listed planning and batch function to take `config` as its first parameter. It also sets the end state: "no module in the package holds mutable module-level state (`__all__` aside), uses `global`, defines `configure` or refers to the old settings dict". These are the target structure, not the patch. No test or overlay path is named.

## 2. Red then green

Runner: host Python 3.13.5, pytest 9 from the user site, invoked as the grader does (`python3 -I -s -m pytest -q -p no:cacheprovider --rootdir <tree>`, `PYTHONDONTWRITEBYTECODE=1`). A three-line shim appends only the user-site path, which plain `-I` hides. A plain `python3 -m pytest -p no:cacheprovider` run gave identical counts. Fresh `fixture/` copy per side, structural file copied to its `manifest.json` `dest`, reference applied with `patch -p1` after a clean dry run. Image Python (bookworm 3.11) not run here.

```
[base] pytest -q tests --ignore=tests/structure => 10 passed
[base] pytest -q tests/structure                => 10 failed
  patching file src/fetchq/api.py
  patching file src/fetchq/core.py
  patching file src/fetchq/jobs.py
[ref]  pytest -q tests --ignore=tests/structure => 10 passed
[ref]  pytest -q tests/structure                => 10 passed
```

The fixture suite is green at both ends with 10 cases. The structural check is red at base with 10 of 10 and green at the reference.

## 3. Criterion mechanical

PASS. `success_criterion` is one line of counts. Every structural probe maps to a TASK.md sentence: the module-level mutable literals, global and nonlocal, the configure definition, the old dict name, the first parameter, the frozen dataclass field set, construction raising `ValueError`, and two independent configs. Two graders would agree.

## Notes

- Difficulty: medium. About 10 to 18 Opus turns, with signatures threaded through two modules and the API.
- Fixture: 40K, 6 files. Clean, `no-secrets.sh` exits 0.
- The old unknown-setting check has no equivalent after the refactor because the dataclass raises `TypeError`. The public `plan` and `replay` signatures make it unreachable, so "behaving exactly as before" holds.
- `grader_protected` lists `tests/conftest.py`, the only infrastructure file. Advisory, suite-wide: TASK.md says the existing suite "must stay green without edits", but the fixture test file is not protected, so an agent that edits it can turn `test_command` green over a behaviour change. Listing the fixture test file in `grader_protected` would enforce the sentence. The README allows this; the validator only requires that listed paths exist.
