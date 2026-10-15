# Fairness review — feature-04

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-15 · **Author:** implementer E · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md is a precise behavioural spec covering line shape, the escape order, the minimum width, padding per alignment with the odd space on the right, the exact separator cells, a worked example and the errors. Judged against: "`center` splits the padding with the odd space on the right (`ab` centred in 7 is two spaces, `ab`, three spaces)." This sentence is a real trap, because the fixture's existing padding uses `str.center`, which places the odd space on the left for that case. The spec states the rule, so the trap is fair. No overlaid path, test name or code location appears.

## 2. Red then green

Runner: host `python3 -I -m pytest` cannot see pytest (it lives in the user site, which `-I` hides), so every pytest run used `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider` (pytest 9.0.2, Python 3.13). Each run used a fresh copy of `fixture/`, the manifest entries overlaid at their `dest`, and `patch -p1` for the reference.

| run | `pytest -q tests` | `pytest -q tests/test_text.py` |
|-----|-------------------|-------------------------------|
| base | `9 failed, 5 passed in 0.03s` | `5 passed in 0.01s` |
| reference | `patching file src/tabular/report.py`; `14 passed in 0.01s` | `5 passed in 0.01s` |

The patch applies cleanly. All 9 overlaid cases fail at base and pass at the reference. The worked example in TASK.md is one of the asserted tables, character for character. The other assertions cover the minimum width, escaped pipes counted in the width, all three line-break forms, shared cell formatting, a missing key, empty rows, an iterator input and both errors.

## 3. Criterion mechanical

PASS. The success criterion gives counts at both ends and green for the regression file. Two graders would agree.

## Notes

- Difficulty is about 8–15 Opus turns.
- The fixture is 32K and holds 4 files, with no caches and nothing named `hidden*`. `no-secrets.sh` exits 0.
- `grader_protected` lists conftest and the fixture suite. That is complete.
