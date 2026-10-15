# Fairness review — feature-01

**Reviewer:** fairness session R1 (Claude Opus 5.5), 2026-10-15 · **Author:** implementer E · **Verdict:** PASS

## 1. No solution leak

PASS. TASK.md is a precise behavioural spec. It names the fixture script and its mode, which the agent must edit anyway, and it gives the three generated-path rules with positive and negative examples. Judged against: "When the manifest is built, a `fix` row whose `file` is a generated path is skipped: it produces no fix region." It does not name the overlaid test file, any test name, the helper function the reference adds, or the line to change. The criterion names behaviour only, with no path or test name.

## 2. Red then green

Runner: host bats 1.13 (`~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats` on PATH as `bats`), fresh fixture copy, manifest overlay, `patch -p1` for the reference. The suite has 12 cases: 5 from the fixture and 7 overlaid.

| run | `bats tests` | `bats tests/build-manifest.bats` |
|-----|--------------|-------------------------------|
| base | 1..12, 6 ok, 6 not ok (overlaid cases 6–9, 11, 12 fail) | 5 of 5 ok |
| reference | `patching file evals/harness/seed-corpus-from-record.sh`; 12 of 12 ok | 5 of 5 ok |

The single overlaid case that is green at base is the lookalike-paths case, by design, as the success criterion says. The patch applies cleanly. Every assertion follows from a TASK.md sentence: dist at any depth, maps and declarations, the four names at any depth, ids/lines/order kept, lookalikes kept, review/audit labels untouched, and the summary count.

## 3. Criterion mechanical

PASS. The success criterion states counts at both ends (7 of 7, 12 of 12, 6 failed at base) and green/red for the regression suite. Two graders would agree. The criterion is testable from TASK.md alone.

## Notes

- Difficulty is about 15–25 Opus turns, mostly reading a 900-line script to find the manifest builder.
- The fixture is 76K and holds 4 files. It has no caches and nothing named `hidden*`. `no-secrets.sh` exits 0 on it.
- The fixture script is the original at 4374c446. Its own text uses the word for the record manifest (lines 771 and 797). That is not a leak about this task, and validate-suite accepts it.
- `grader_protected` covers the helper, the regression suite and `no-secrets.sh`, which the seed mode calls. That list is complete.
- `bats tests` also runs any test the agent adds. A broken self-test turns the run red, which is the intended behaviour.
