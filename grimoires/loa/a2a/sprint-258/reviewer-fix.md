# Sprint 258 fix round 1: implementer "fix" report

Worktree: `/home/merlin/Documents/thj/code/loa-wt-s1-fix` at `05442536`. Patch: `~/.cache/loa/cycle-130/patches/s1-fix.patch` (+ `s1-fix.stat`). Scope: MEDIUM-1, MEDIUM-2 and LOW-1 … LOW-5 of `grimoires/loa/a2a/sprint-258/engineer-feedback.md`. No other change.

## What was changed

- **MEDIUM-1** `evals/harness/Dockerfile.ablation:19-20`: deleted the `FROM rust:1-bookworm AS brbuild` stage and its `cargo install`. The line-80 comment explaining why `br` is absent stays. The file now has one `FROM`.
- **MEDIUM-2** `evals/harness/ablation-row.sh:177-179`: a `mktemp -d` work dir, removed by an EXIT trap (`find -mindepth 1 -delete` + `rmdir`, the repo's test-teardown idiom). Pipeline, task, grade, manifest, MODELINV, both envelopes and the transcript write list are written there. They reach jq through `--slurpfile` (`:240-243`) and are rebound with `$x_f[0] as $x`. `--arg` remains for scalars; `--argjson` only for `$ATTEMPTS`, which is a validated integer. The header (`:60-67`) documents this.
- **LOW-1** `ablation-row.sh`:
  - `ms()` (`:247`) returns null on empty input and on a parse failure (`try … catch null`). `wall_clock_ms` falls back to the phase sum when either end is null.
  - `voices()` (`:250-256`) guards `verdict_quality` as an object and reads `companion_planned` through `objects` with `first(…, null)`, so `false` stays `false`.
  - `model_mismatches` (`:270`) uses `($ph.models_used // {} | objects // {})` before `keys[]`.
  - Writer defaults (`:310-311`) are `name: (.name // .label // "")`, `model_requested: (.model_requested // "")` and `models_used: (.models_used // {} | obj)`.
  - `verdict_accuracy`, `_review` and `_audit` (`:330-334`) are coerced to boolean or null.
  - `ROW="$(jq …)" || usage "row build failed for $RUN_ID"` (`:354`). That line is documented under exit 2 in the header, and the 0/1/2 contract is kept.
- **LOW-2** `evals/harness/spend.sh`:
  - Dedup keeps the max `cost_usd` per `run_id` (`:129`).
  - A row with an empty or missing `run_id` counts on its own. Each such file gets one stderr warning naming it (`:153`).
  - When any line was skipped, the text line gains ` INCOMPLETE (N skipped)` (`:190`) and the exit is 1 (`:191`).
  - `--json` adds `complete` and `runs_rows_no_run_id` (`:184`).
  - The header's `--runs`, `--json`, Output and Exit lines (`:16-38`) are updated, and the `--help` range now follows the longer header.
- **LOW-3** `evals/harness/run-arms.sh`:
  - The `! -path "$SUITE_DIR/screen-*"` filter is gone (`:399`).
  - The aggregate program starts with `map(select(.screen != true))` (`:386`), so `batches`, `cuts`, `per_arm`, `state`, `source_commit` and `model_id` all exclude screen batches.
  - `--batch screen-*` without `--screen` dies with exit 2 (`:167-169`).
  - The header's Screen paragraph says this.
- **LOW-4** `evals/harness/freeze.sh:72-94`:
  - A newline-path probe (`find -name '*\n*'`) runs first.
  - The listing is `find "$d" \( -type f -o -type l \) -print`, and any `[[ -L ]]` entry is refused with `freeze: refused — the suite holds a symlink: <relpath>` and exit 1.
  - A newline path gets `… a path with a newline: <relpath with \n>` and exit 1.
  - Both checks run before hashing, for write and for `--check`.
  - The header documents both lines and the exit-1 cases, and the `--help` range is updated.
- **LOW-5** `evals/harness/pipeline-run.sh:85`: "codex 0.137.0" became "codex 0.162.1". The CHANGELOG and SDD rows are the lead's, per the feedback.

## Tests added

Every new case was run against the `05442536` version of its script, restored from `git show HEAD:<path>` into the worktree and then put back. Each one failed there and passes now.

| Finding | Test | On 05442536 | Now |
|---|---|---|---|
| MEDIUM-1 | `pipeline-run.bats` "Dockerfile.ablation: a single build stage, no cargo install …" | fails, two `FROM` | pass |
| LOW-5 | `pipeline-run.bats` "pipeline-run.sh header names the codex version Dockerfile.ablation pins" | fails, says 0.137.0 | pass |
| MEDIUM-2 | `ablation-row.bats` "a MODELINV ledger over 200 KB reaches jq as a file …" | fails | pass |
| LOW-1 | `ablation-row.bats` "an empty finished timestamp and a boolean companion_voice still yield a valid row" | fails | pass |
| LOW-1 | `ablation-row.bats` "odd field shapes: an offset timestamp, an array models_used, a string verdict_accuracy, no name or model_requested" | fails | pass |
| LOW-1 | `ablation-row.bats` "a row program abort exits 2 naming the run" | fails, jq's own exit | pass |
| LOW-2 | `spend.bats` SP-4, changed to expect exit 1 and `complete: false` | fails | pass |
| LOW-2 | `spend.bats` SP-7 INCOMPLETE text line + exit 1, SP-8 costs 3 and 5 for one run_id, both orders, give runs_usd 5, SP-9 rows without a run_id | fail | pass |
| LOW-3 | `run-arms.bats` RA-11, marker-based exclusion with `screen-foo` (screen false) aggregated and `batch-x` (screen true, with a cut) excluded | fails | pass |
| LOW-3 | `run-arms.bats` RA-12, `--batch screen-foo` without `--screen` exits 2 | fails | pass |
| LOW-4 | `freeze.bats` FZ-7 symlink refused on write and on `--check`, no manifest; FZ-8 newline path refused | fail, exit 0 | pass |

The MEDIUM-2 test appends 400 MODELINV rows with a 600-byte payload, giving a ledger over 204,800 bytes. The REVIEW phase owns all of them, so they are read as well as loaded; the test asserts its `voice_cost_usd` is 1.1. The old script on that input:

```
/tmp/s1fix/ablation-row.orig.sh: line 327: /usr/bin/jq: Argument list too long
old exit 126
new exit 0
```

On the old `run-arms.sh`, RA-12 did not fail fast: it hung. The old `find` dropped the only STATUS file, which was in `screen-foo`, so `jq -s` got no file argument and read stdin. I killed that process (my own test's `run-arms.sh`) to finish the check.

## Commands and results

| Command | Exit | Result |
|---|---|---|
| `bash -c '…/bats evals/tests/'` before (05442536) | 0 | 256/256 |
| `bash -c '…/bats evals/tests/'` after | 0 | 269/269 (13 new) |
| `bats evals/tests/ablation-row.bats` | 0 | 22/22 |
| `bats evals/tests/spend.bats` | 0 | 9/9 |
| `bats evals/tests/run-arms.bats` | 0 | 12/12 |
| `bats evals/tests/freeze.bats` | 0 | 8/8 |
| `bash tools/check-no-raw-sha256sum.sh` | 0 | OK |
| `bash -n` on every changed script | 0 | OK |

The shell-compat lint scans `.claude/scripts/` only; none of its patterns appear in the diff. The eval.yml trust check passes on the diff: no `source` or `.` line with `$`, no `eval` with `$`, no raw `sha256sum` or `curl`, no `((x++))`, no `declare -A`.

## Decisions

- DECISION: The writer coerces a non-object `models_used` to `{}` rather than only defaulting a missing one (`// {}`), so the row always passes its own `--validate`. `// {}` alone would pass an array through and fail validation, which the feedback rules out.
- DECISION: `verdict_accuracy_review` and `verdict_accuracy_audit` get the same boolean-or-null coercion as `verdict_accuracy`, and a non-object `verdict_accuracy_per_gate` reads as null. Without this the writer would still emit rows its validator rejects.
- DECISION: `voices()` reads `verdict_quality` through an object guard as well as `companion_voice`. A boolean or string `verdict_quality` would abort the same way.
- DECISION: An unparseable `started` or `finished` (empty, a `+00:00` offset, a non-string) parses as null, and `wall_clock_ms` then uses the phase sum. Offsets are not normalised, which keeps the fix to the specified `try … catch null`.
- DECISION: The work dir is removed with `find -mindepth 1 -delete` + `rmdir` instead of `rm -rf`. It is the idiom the repo's tests use, and the fence refuses `rm -rf` text in tool calls.
- DECISION: In `spend.sh`, `runs_rows` counts unique run_ids plus rows without a run_id. `runs_rows_deduped` counts every row folded into an earlier one. The new `runs_rows_no_run_id` field reports the rows that cannot be deduplicated.
- DECISION: The no-run_id warning is one line per file, giving that file's count: `spend: <file>: N row(s) without a run_id counted individually (no dedup possible)`.
- DECISION: SP-4 is changed rather than kept, because its old expectation (exit 0 with a skipped line) is exactly the behaviour LOW-2 removes.
- DECISION: The `screen-` refusal applies only to a user-given `--batch`. Under `--screen` the name is still generated as `screen-<UTC ts>`, and `--batch` is ignored as before.
- DECISION: The freeze newline check uses a separate `find -name '*<newline>*'` probe before the listing. A newline splits a `-print` listing into two lines, so it cannot be seen there. The message shows the newline as `\n`.
- DECISION: The pipeline-run version test reads `CODEX_VERSION` from the Dockerfile and requires that no other `codex X.Y.Z` string remains in the `pipeline-run.sh` header. A future repoint then breaks the test until the comment follows.

## Known limitations and not done

- `aggregate_status` still calls `jq -s` with a `$(find …)` file list. With zero files jq reads stdin, which is the hang seen on the old code. With this fix the current batch's STATUS is always listed, so that cannot occur. Paths with whitespace still word-split. Both are outside LOW-3 and left as is.
- `CHANGELOG.md:17` and `grimoires/loa/sdd.md:139` still say codex 0.137.0. The feedback assigns them to the lead at integration.

## Handoff notes for the lead

- The report copy under `grimoires/loa/a2a/sprint-258/` is gitignored, so it is not in the patch; it is on disk in the worktree.
- Apply the patch. No image rebuild is needed for correctness: BuildKit already skipped the deleted stage, so the image content is unchanged. The legacy builder now builds it too.
- Correct the codex version in CHANGELOG and the SDD row, noting the Sprint 258 amendment.
- `spend.sh` now exits 1 when a line is skipped. No script in the tree calls it; any operator-side wrapper that treated exit 0 as "printed" should now treat 1 with `INCOMPLETE` as a lower bound.
