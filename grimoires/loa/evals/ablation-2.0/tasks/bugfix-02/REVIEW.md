# Fairness review — bugfix-02

**Reviewer:** fairness session R2 (s2-review-r2, Claude Opus 5.5), 2026-10-15 · **Author:** implementer D · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md lists four observed symptoms (reload not seen, unset not seen, the first caller's default kept, a value from a discarded store) and the expected rule ("a read always reflects the current layers of the store it is given, whatever changed them (`load`, `set` or `unset`), and never a value from another store"). It names public API only. It does not mention the change counter, the memo key, `id()` or weak references. The sentence "any value may serve as a default, including a list" is a fair warning against a fix that would put the default into a hashed key, and it is behavioural. The `criterion` names no path.

## 2. Red then green

Runner: host Python 3.13.5, pytest 9 from the user site, invoked as the grader does (`python3 -I -s -m pytest -q -p no:cacheprovider --rootdir <tree>`, `PYTHONDONTWRITEBYTECODE=1`). Plain `python3 -I` cannot see the user-site pytest, so a three-line shim appends only that path; a second run with `python3 -m pytest -p no:cacheprovider` gave identical counts. Fresh copies of `fixture/` per side, overlay copied from `manifest.json` to its `dest`, reference applied with `patch -p1` (dry run clean first). The image Python (bookworm 3.11) was not run here; the lead's in-image rerun is binding.

```
[base] pytest -q tests                           => 6 failed, 7 passed
[base] pytest -q tests --ignore=tests/acceptance => 5 passed
  patching file src/layercfg/lookup.py
  patching file src/layercfg/store.py
[ref]  pytest -q tests                           => 13 passed
[ref]  pytest -q tests --ignore=tests/acceptance => 5 passed
```

The overlay contributes 8 cases, 6 red at base on CPython, all assertion failures. The reference result is deterministic. Only the base-side red count of the discarded-store case depends on address reuse, which `success_criterion` states.

## 3. Criterion mechanical

PASS. The grading end is mechanical: 8 of 8 green plus the regression command green. The hedged base count ("6 failed on CPython; at least 5 on any interpreter") describes the red side only and does not affect grading of an agent's tree. `criterion` is testable without the overlay, including the memo-hit requirement through `lookup_stats()`.

## Notes

- Difficulty: medium. About 12 to 20 Opus turns. There are three distinct defects (no change count on two mutators, a per-call default captured in the memo, identity reuse) and the memo must keep its hit pattern.
- Fixture: 36K, 5 files. Clean, `no-secrets.sh` exits 0, nothing stray.
- `grader_protected` covers the only infrastructure file (`tests/conftest.py`).
