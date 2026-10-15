# Fairness review — feature-03

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-15 · **Author:** implementer E · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md is a precise behavioural spec covering the interface, the scan rules, the single pass and the error table. Judged against: "The reference ends at the first `}` after `${`. `NAME` (the text before `:-`, or the whole text between the braces when there is no `:-`) must match `[A-Za-z_][A-Za-z0-9_]*`." The new exception class and the `env` argument are named because they are interface, not implementation. No overlaid path, test name or code location appears. The criterion names behaviour only.

## 2. Red then green

Runner: host `python3 -I -m pytest` cannot see pytest (it lives in the user site, which `-I` hides), so every pytest run used `PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -q -p no:cacheprovider` (pytest 9.0.2, Python 3.13). Each run used a fresh copy of `fixture/`, the manifest entries overlaid at their `dest`, and `patch -p1` for the reference.

| run | `pytest -q tests` | `pytest -q tests/test_loader.py` |
|-----|-------------------|---------------------------------|
| base | `10 failed, 6 passed in 0.04s` | `6 passed in 0.01s` |
| reference | both files patched; `16 passed in 0.02s` | `6 passed in 0.01s` |

The patch applies cleanly to both package files. All 10 overlaid cases fail at base and pass at the reference. Every assertion traces to TASK.md. That covers `$$` chains, a literal `$` in its three listed shapes, a verbatim default containing `:-` and `=`, `${A:x}` as an invalid name, the empty-name message, comment lines left alone, and the process environment read at call time.

## 3. Criterion mechanical

PASS. The success criterion gives counts at both ends and green for the regression file. Two graders would agree.

## Notes

- Difficulty is about 10–20 Opus turns.
- The fixture is 32K and holds 4 files, with no caches and nothing named `hidden*`. `no-secrets.sh` exits 0.
- `grader_protected` lists conftest and the fixture suite. That is complete.
- The overlaid test imports the new class from the loader module only. TASK.md promises both import sites, so an agent that exports it from the package alone would fail. That is fair because the spec requires both.
