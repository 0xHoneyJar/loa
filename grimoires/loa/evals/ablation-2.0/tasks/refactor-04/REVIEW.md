# Fairness review — refactor-04

**Reviewer:** fairness session R2 (s2-review-r2, Claude Opus 5.5), 2026-10-15 · **Author:** implementer D · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md states the structural goal. It asks for "a module `jobboard.status` defining `Status`, an `enum.Enum` subclass with the members `PENDING`, `RUNNING`, `DONE` and `FAILED`", requires jobs to carry members, and bans raw status strings from the three modules. It also names the compatibility to keep: string equality, `with_status("running")`, plain-string count keys, JSON and the summary line. It does not say to mix in `str` or to use `StrEnum`; the agent must work that out from the compatibility sentence. No test or overlay path is named.

## 2. Red then green

Runner: host Python 3.13.5, pytest 9 from the user site, invoked as the grader does (`python3 -I -s -m pytest -q -p no:cacheprovider --rootdir <tree>`, `PYTHONDONTWRITEBYTECODE=1`). A three-line shim appends only the user-site path, which plain `-I` hides. A plain `python3 -m pytest -p no:cacheprovider` run gave identical counts. Fresh `fixture/` copy per side, structural file copied to its `manifest.json` `dest`, reference applied with `patch -p1` after a clean dry run. Image Python (bookworm 3.11) not run here.

```
[base] pytest -q tests --ignore=tests/structure => 6 passed
[base] pytest -q tests/structure                => 9 failed
  patching file src/jobboard/board.py
  patching file src/jobboard/policy.py
  patching file src/jobboard/report.py
  patching file src/jobboard/status.py
[ref]  pytest -q tests --ignore=tests/structure => 6 passed
[ref]  pytest -q tests/structure                => 9 passed
```

The fixture suite is green at both ends with 6 cases. The structural check is red at base with 9 of 9 and green at the reference.

## 3. Criterion mechanical

PASS. `success_criterion` is one line of counts. The raw-string probe matches whole string constants only, so the queue module's docstring, which lists the four statuses inside one longer string, does not trip it. Every probe maps to a TASK.md sentence.

## Notes

- Difficulty: medium. About 10 to 18 Opus turns.
- Fixture: 40K, 6 files. Clean, `no-secrets.sh` exits 0.
- Interpreter sensitivity: f-string formatting of a `str`-mixin enum member changed between Python 3.11 and 3.12+. The reference renders through `.value` everywhere, so it is version-independent. An agent tree may differ, and the summary-line test in the fixture suite catches that on whichever interpreter the image runs. This is fair, but it confirms that the in-image rerun is the binding proof.
- `grader_protected` lists `tests/conftest.py`, the only infrastructure file. Advisory, suite-wide: TASK.md says the existing suite "must stay green without edits", but the fixture test file is not protected, so an agent that edits it can turn `test_command` green over a behaviour change. Listing the fixture test file in `grader_protected` would enforce the sentence. The README allows this; the validator only requires that listed paths exist.
