# Fairness review — bugfix-03

**Reviewer:** fairness session R2 (s2-review-r2, Claude Opus 5.5), 2026-10-15 · **Author:** implementer D · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md gives observed spellings that split one tag ("`"Straße"` and `"STRASSE"` are two tags", the full-width form, the composed and decomposed accent) and the removal miss. It gives the expected rule ("equal after Unicode compatibility normalisation, full case folding and collapsing every run of whitespace … Every operation that compares tags (adding, counting, merging, removing) uses that same rule"). The rule is already in the fixture's own module docstring, so the brief restates the spec rather than the fix. It names no function to change and no test. "Every operation … uses that same rule" points at the removal path behaviourally, which is fair for a bug report. The `criterion` names no path.

## 2. Red then green

Runner: host Python 3.13.5, pytest 9 from the user site, invoked as the grader does (`python3 -I -s -m pytest -q -p no:cacheprovider --rootdir <tree>`, `PYTHONDONTWRITEBYTECODE=1`). Plain `python3 -I` cannot see the user-site pytest, so a three-line shim appends only that path; a second run with `python3 -m pytest -p no:cacheprovider` gave identical counts. Fresh copies of `fixture/` per side, overlay copied from `manifest.json` to its `dest`, reference applied with `patch -p1` (dry run clean first). The image Python (bookworm 3.11) was not run here; the lead's in-image rerun is binding.

```
[base] pytest -q tests                           => 6 failed, 7 passed
[base] pytest -q tests --ignore=tests/acceptance => 6 passed
  patching file src/tagidx/index.py
  patching file src/tagidx/keys.py
[ref]  pytest -q tests                           => 13 passed
[ref]  pytest -q tests --ignore=tests/acceptance => 6 passed
```

The overlay contributes 7 cases, 6 red at base, all assertion failures. The overlay's composed and decomposed constants are distinct code-point sequences, since that case is red at base.

## 3. Criterion mechanical

PASS. One line of counts. `criterion` is testable from the public API. The stability expectations ("the key of a key is itself, and a key is in NFKC form") are written in TASK.md.

## Notes

- Difficulty: low to medium. About 6 to 12 Opus turns. The second defect is a separate key computation in the removal path, which a fix confined to the key function misses.
- Fixture: 40K, 6 files. Clean, `no-secrets.sh` exits 0.
- `grader_protected` covers `tests/conftest.py`, the only infrastructure file.
- The idempotence requirement is met by a single normalise-then-casefold for the overlay's inputs. The reference's second normalisation is belt and braces, not an unstated requirement.
