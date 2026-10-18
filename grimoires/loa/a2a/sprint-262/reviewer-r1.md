# s5-r1 report: row writer fields `defects_missed` (bd-yz1rd) and `regressions_final_green` (bd-m0hw7)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s5r1` at `d80c5c32`. Files changed: `evals/harness/ablation-row.sh`, `evals/tests/ablation-row.bats` (plus this report copy under `grimoires/loa/a2a/sprint-262/`). Patch: `~/.cache/loa/cycle-130/patches/s5-r1.patch` (+ `.stat`).

## What was built
- `evals/harness/ablation-row.sh:52-68` header: both fields in the derived-field list with their grade.json source path, the optional-key rule for `--validate`, why `schema_version` stays 1, and a "Row writer version: 1.2" line with a short history. `--help` range moved from `2,84p` to `2,101p` (same end point: the blank line before "Tested by").
- `evals/harness/ablation-row.sh:410-414` row program: `defects_missed` and `regressions_final_green`, placed after `regressions`.
- `evals/harness/ablation-row.sh:165-170` `--validate`: two checks that fire only when the key is present.

## Field definitions
- `defects_missed`: grade.json `recall.missed` copied as is on a review-catch row (a list of non-empty strings, `[]` when all caught). null when the task type is not review-catch, with no grade.json, when `recall` is null or absent, or when `missed` is absent or not a list of non-empty strings. `--validate`: key optional; if present, a list of non-empty strings or null.
- `regressions_final_green`: grade.json `regressions.final_green` when it is a boolean. null when `regressions` is null, absent or not an object (review-catch rows, ungraded rows), or `final_green` is not a boolean. `--validate`: key optional; if present, boolean or null.

## Tests added (`evals/tests/ablation-row.bats` cases 29-33; each fails on the `d80c5c32` writer and passes on the new one)
- 29 review-catch with `missed: ["d2","d5"]`: `["d2","d5"]`, `regressions_final_green` null, validates.
- 30 `missed: []` gives `[]`; an absent `missed`, a null `recall`, and a string `missed` give null.
- 31 build with `final_green: true` gives true and `defects_missed` null (even with a planted `recall.missed`); false gives false; `"yes"` and `regressions: null` give null; validates.
- 32 ungraded runs (review a1-review, build a5-build; no grade.json) carry both keys as null; validates with `--allow-ungraded`. It checks `has()`, so a missing key fails.
- 33 `--validate` rejects `defects_missed: "d2"`, `["d2", 3]` and `[""]`, and `regressions_final_green: "yes"`, naming the line. It accepts null/true and a legacy row with both keys deleted.

## Bats counts
- `ablation-row.bats`: 28/28 before, 33/33 after.
- `evals/tests/`: 386/386 before (per brief), after 391 cases. First full run: 390/391. The one failure was `pipeline-run.bats` "container: the per-run HOME persists ... deleted when interrupted" (`rc -eq 4`, a SIGTERM timing test, file not touched). It passed 2/2 run alone. Second full run: 391/391 green (rc 0).

## Real-data smoke (read-only from the lead's checkout, rows to /tmp; both files `--validate` clean)
```
{"run_id":"priority-v2-p1-a1_full-review-01-t1","defects_missed":[],"regressions_final_green":null,"defect_catch_rate":1.0}
{"run_id":"priority-v2-p1-a0_bare-review-02-t1","task_type":"review-catch","defects_missed":["d3"],"regressions_final_green":null}
{"run_id":"priority-p1-a1_full-bugfix-01-t1","task_type":"bug-fix","defects_missed":null,"regressions_final_green":true}
```
The bugfix-01 task.yaml came from git history into /tmp, because the v1 task directory is no longer in the tree. The lead's `git status` was clean afterwards.

## DECISION: bullets
- DECISION: No writer version constant exists in the script or the row. The only per-row version is `schema_version: 1`, and `ablation-report.py` refuses any other value (AR-15). So `schema_version` stays 1. The version bump is a header line "Row writer version: 1.2", taking the brief's "row writer 1.1" as the current version. No new row field was added for it.
- DECISION: `defects_missed` is gated on the task type from task.yaml (else pipeline.json), not on the grade's `task_type`. The grade's field is null in the fixtures, and the brief says "null when the task is not review-catch".
- DECISION: A malformed `missed` (not a list, or with a non-string or empty element) and a non-boolean `final_green` read null, never a coerced value. This follows the writer's rule that it never emits a row `--validate` rejects (the `boolish` pattern).
- DECISION: `[]` is kept distinct from null: "graded, nothing missed" versus "no data".
- DECISION: The new validate checks are written inline, not with `need()`, because `need()` requires the key and legacy rows must keep validating.
- DECISION: The bats file has no case ids, so the five cases were appended after case 28 with descriptive names and a section comment.

## Limitations / handoff
- Pre-existing hazard, out of scope and not fixed: if the row program's object construction yields an empty stream, `ROW` is empty. The writer then prints a blank line with exit 0. `--validate` skips blank lines, so the row silently vanishes. My first draft hit this: `$g.regressions | objects` on a null emptied every row. The fix uses `first(…, null)`. A one-line guard after the jq call, `[[ -n "$ROW" ]] || usage "row build failed for $RUN_ID"`, would close it. Recommend it as a separate bead.
- Existing rows files do not gain the fields until they are re-rowed (for example `run-ablation.sh --resume --rerow`). `ablation-report.py` does not read them yet.
