# Fairness review — feature-02

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-15 · **Author:** implementer E · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md is a precise behavioural spec covering options, the three accepted forms, offset rules, date-only semantics, and the two exact error messages. Judged against: "A date alone means the whole UTC day: `--since 2026-10-15` starts at `2026-10-15T00:00:00Z`; `--until 2026-10-15` keeps every record before `2026-10-16T00:00:00Z`". It names the public entry point the tests call, which is part of the spec, not the fix. It does not name the overlaid test file or any test. The criterion names behaviour only.

## 2. Red then green

Runner: host `python3 -I -m pytest` cannot see pytest (it lives in the user site, which `-I` hides), so every pytest run used `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider` (pytest 9.0.2, Python 3.13). Each run used a fresh copy of `fixture/`, the manifest entries overlaid at their `dest`, and `patch -p1` for the reference.

| run | `pytest -q tests` | `pytest -q tests/test_cli.py` |
|-----|-------------------|------------------------------|
| base | `9 failed, 6 passed in 0.04s` | `6 passed in 0.01s` |
| reference | `patching file src/logq/cli.py`; `15 passed in 0.03s` | `6 passed in 0.01s` |

The patch applies cleanly. All 9 overlaid cases fail at base and pass at the reference. Every assertion traces to a TASK.md sentence. That includes the rejected values, which are fractional seconds, a bare hour, a date with `Z`, the empty string, month 13 and hour 25. It also includes the equal-instant window and the empty-window error.

## 3. Criterion mechanical

PASS. The success criterion gives counts at both ends and green for the regression file. Two graders would agree.

## Notes

- Difficulty is about 10–20 Opus turns.
- The fixture is 36K and holds 5 files, with no caches and nothing named `hidden*`. `no-secrets.sh` exits 0.
- `grader_protected` lists `tests/conftest.py` and `tests/test_cli.py`. The fixture has no `pytest.ini` or `pyproject.toml`, so the list is complete.
- The reference's regex uses `\d`, which also matches non-ASCII digits. No test exercises that case, and the spec says nothing about it.
