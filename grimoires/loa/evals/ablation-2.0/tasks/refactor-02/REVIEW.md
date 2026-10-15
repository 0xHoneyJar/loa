# Fairness review — refactor-02

**Reviewer:** fairness session R2 (s2-review-r2, Claude Opus 5.5), 2026-10-15 · **Author:** implementer D · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md states the target structure precisely: the three function names and signatures, what each must not do, the composition identity, "`build_report` itself is at most eight statements, and no function in the module has more than forty statements", and how statements are counted. It leaves the summary shape open ("The shape of the summary object is up to you"). It names no test or overlay path and gives no code.

## 2. Red then green

Runner: host Python 3.13.5, pytest 9 from the user site, invoked as the grader does (`python3 -I -s -m pytest -q -p no:cacheprovider --rootdir <tree>`, `PYTHONDONTWRITEBYTECODE=1`). A three-line shim appends only the user-site path, which plain `-I` hides. A plain `python3 -m pytest -p no:cacheprovider` run gave identical counts. Fresh `fixture/` copy per side, structural file copied to its `manifest.json` `dest`, reference applied with `patch -p1` after a clean dry run. Image Python (bookworm 3.11) not run here.

```
[base] pytest -q tests --ignore=tests/structure => 11 passed
[base] pytest -q tests/structure                => 8 failed
  patching file src/salesreport/report.py
[ref]  pytest -q tests --ignore=tests/structure => 11 passed
[ref]  pytest -q tests/structure                => 8 passed
```

The fixture suite is green at both ends with 11 cases. The structural check is red at base with 8 of 8 and green at the reference.

## 3. Criterion mechanical

PASS. `success_criterion` is one line of counts. The statement counter matches TASK.md's counting rule, and a docstring counts as one statement, which the budget of eight absorbs. One wording nit: `criterion` says "composing them in a few statements" while TASK.md says "at most eight". Suggested rewording: "with build_report composing them in at most eight statements".

## Notes

- Difficulty: medium. About 10 to 18 Opus turns.
- Fixture: 32K, 4 files. Clean, `no-secrets.sh` exits 0.
- The "produces no text" probe on the aggregation step also bans f-strings and `join`/`format`. An aggregation step that raises with an f-string message would fail. The `top` check message at base is a plain literal and the reference keeps it in the composer, so a natural split passes.
- `grader_protected` lists `tests/conftest.py`, the only infrastructure file. Advisory, suite-wide: TASK.md says the existing suite "must stay green without edits", but the fixture test file is not protected, so an agent that edits it can turn `test_command` green over a behaviour change. Listing the fixture test file in `grader_protected` would enforce the sentence. The README allows this; the validator only requires that listed paths exist.
