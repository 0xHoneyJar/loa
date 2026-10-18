# Sprint 260 implementer I: the drift guard and the degraded rule narrowed to substitution; `--clear-drift` and `--rerow` on resume

Worktree `/home/merlin/Documents/thj/code/loa-wt-s3i` at `f6487a31`; nothing committed.
Patch: `~/.cache/loa/cycle-130/patches/s3-i.patch` (stat beside it, `s3-i.stat`). No new files, so no `git add -N` was needed.
It applies with `git apply --check` at f6487a31. The lead's HEAD has since moved to `ff4edc35`, which touches only `ablation-grade.sh`, `ablation-grade.bats`, `decisions.yaml` and `known-failures.md`; none overlap this patch.

## What was built (landmarks in the patched files)

**A. `evals/harness/run-ablation.sh` drift guard (DEC-0545)**
- `drift_check` (:459) was moved up into the helpers section so the pre-lock `--clear-drift` check can call it. It is read-only on the run dir and prints two lines: the drift (or `null`), then the extra models `{"<raw id>": {"phases": [...], "output_tokens": N}}` (or `{}`).
- Model rule per executed phase: the `model_requested` ≠ manifest check is unchanged. The old "every models_used key allowed" loop is gone. A phase drifts as `models_used.<LABEL>` only when `models_used` is a non-empty object and the normalised requested model is not among its normalised keys. `expected` is the manifest model for that phase, normalised. `got` is the sorted keys. Every other key is collected as an extra model. The CLI-version and image checks are unchanged.
- `post_run` (:910) is the chain factored out of `run_trial`: took-effect, drift_check, the extra-model log lines, grade, then ablation-row.sh. It writes its results to `PR_*` globals. The trial log gets one line per extra model:
  `run-ablation: extra model <id> in <LABELS> (<N> output tokens; a WebFetch summariser or built-in subagent, not drift — DEC-0545)`.
- `run_trial` (:949) now calls `post_run`. Its result json is unchanged except for a new `extra_models` key.
- `apply_flags` (:1028) holds the took-effect pause and first-drift stop, factored out of `collect` and also used by `--rerow`. `record_extra` (:1040) stores a run's extra models per run_id.
- `write_status` (:845) adds `drift_cleared`, `rerowed`, `extra_models` (the aggregate) and `extra_models_by_run`.
- Header rule 4 is rewritten to cite DEC-0545. The STATUS text, the `--resume` text and the options list are updated.

**B. `evals/harness/ablation-row.sh`**
- Header :25 describes the new cause (1).
- jq `model_missing` (:318) is non-empty only when `models_used` is a non-empty object, `model_requested` is a non-empty string, and its normalised id is not among the normalised keys.
- Reason text (:325) is `"<LABEL>: requested <model> absent from models_used (<keys, comma-joined>)"`. An extra model is no degradation.

**C. `--clear-drift`** (parsed at :266; usage check at :297)
- The resume refusal at :337 is kept unless `--clear-drift` is given. Its message now points at `--clear-drift`.
- `run_dir_of` (:723) resolves the dir through the MANIFEST plan's `run_dir`, then the highest `-r<k>` sibling.
- The read-only check (:736) runs before the lock. It dies with exit 2 when the run still drifts (printing the result), when the drift guard cannot read the run, or when the run dir is missing.
- The STATUS change is applied in reconciliation (:1197). There `drift_cleared[]` gets `{run_id, previous, cleared_at, harness_commit}` and the log line `resume: --clear-drift <run_id> (previous drift re-read under the current rule: none)` is written. `drift` comes out `null` because the resumed driver starts with no drift.

**D. `--rerow RUN_ID`** (parsed at :267; usage check at :298; validated read-only before the lock at :753)
- `replace_row` (:1145) works under `flock` on `$ROWS.lock`. A `python3 -I` program re-counts the rows for the id inside the lock. It writes `$ROWS.rerow.$$` beside the rows file with the one line replaced in place, so file order is kept. The temp file is run through `ablation-row.sh --validate`, with `--allow-ungraded` for smoke, and then moved over the rows file.
- `rerow_all` (:1175) runs `post_run` with the old row's `attempts` and `retry_reason`, and the pipeline status from `final_status`. It then logs `rerow <id>: <old> → <new>` and appends to `rerowed[]`. STATUS.json is patched after each rerow, so a later failure does not lose the record. Its extra models are recorded and `apply_flags` runs.
- The reconciliation block was moved below the function definitions. It calls `rerow_all` (:1215) before the rows loop, so `spent` and `per_arm` come from the final rows.

**E. Tests**
- `evals/tests/fixtures/ablation-pipeline-stub.sh` gains the `extra_model` mode (:103). The last phase's `models_used` is `{<requested>: 100, "global.anthropic.claude-haiku-4-5-20251001-v1:0": 516}`.
- `drift_model` is unchanged.

## Interface as built
- `--clear-drift`: needs `--resume`. A batch with no recorded drift logs a note to stderr and continues.
- `--rerow RUN_ID`: repeatable and needs `--resume`. The id must match `^[A-Za-z0-9._-]{1,200}$`, and the same id twice is a usage error.
- Refusals exit 2 with nothing written. They cover an id not `<batch>-…`, an id not in the plan, a missing rows file, a row count other than 1, an `interrupted` or `transport_error` row, and a missing `<run dir>/meta/pipeline.json`.
- A rerow whose row build or replacement fails dies with exit 2. The rows file is left unchanged and the temp file removed.
- New STATUS.json fields:
  - `drift_cleared: [{run_id, previous, cleared_at, harness_commit}]`, default `[]`.
  - `rerowed: [{run_id, from, to, at}]`, default `[]`.
  - `extra_models: {<raw id>: {runs, output_tokens}}`, `{}` when none.
  - `extra_models_by_run: {<run_id>: {<raw id>: output_tokens}}`, the per-run source the aggregate is derived from.
- The extra-models output is the second stdout line of `drift_check`, `extra_models` in the trial result json, the trial-log line, and the two STATUS fields.

## Tests added, and what each proves
- **ablation-row: "degraded: the requested model absent from models_used (a substitution, DEC-0545)"** replaces the old case. With `{"claude-sonnet-5": 90}` the row is degraded with the new reason text.
- **ablation-row: "not degraded: an extra model beside the requested one"**. Opus 6000 plus Haiku 516 gives `degraded` false and `degraded_reason` null.
- **RAB-16**: an `extra_model` trial does not drift, completes and is graded with pass 0.75. The trial log has the extra-model line and the clean trial's log does not. `STATUS.extra_models` is Haiku with runs 1 and 516 tokens. The row is completed and not degraded. A batch without extras has `extra_models` equal to `{}`.
- **RAB-17**: a drift written into STATUS for an `extra_model` run makes `--resume` alone exit 2 with STATUS byte-identical. `--clear-drift` without `--resume` exits 2. `--resume --clear-drift` exits 0 with the state complete, drift null, `drift_cleared[0]` holding the run_id, the previous field, a timestamp and a harness commit, and the run.log line present. The two remaining trials run and the cleared run is not re-run. With a `drift_model` run, the clear exits 2 with "still drifts", leaves STATUS.json and the rows byte-identical, and leaves no lock.
- **RAB-18**: the fixture is an `extra_model` run whose row was rebuilt as the old rule left it, ungraded with `--status infrastructure_error`, at its original line, plus a recorded drift. The refusals are each checked against the byte-identical rows file:
  - no `--resume`;
  - `--rerow` with the drift not cleared;
  - an unknown id;
  - another batch's id;
  - a duplicated row;
  - an `interrupted` row.

  The rerow itself exits 0. It makes no pipeline call and one grade call. Exactly one row remains for the id, at the same line, completed, not degraded, attempts 1, and the other rows are untouched. The rows file validates. `rerowed` is `[{run_id, from: infrastructure_error, to: completed}]`. `spend.rows_usd` is 7.5 with 3 completed, 0 excluded and 3 launched, so the row is counted once. `extra_models` is correct, the log lines are present, and no temp file is left.
- **RAB-7**: one assertion changed (see DECISION). The `drift_model` case still fails the batch.

## bats counts

| Run | f6487a31 | patched |
|---|---|---|
| `evals/tests/` (whole) | 365/365 | 369/369 |
| `evals/tests/run-ablation.bats` | 15/15 | 18/18 |
| `evals/tests/ablation-row.bats` | 27/27 | 28/28 |

The brief expected 366 at f6487a31. A clean clone at f6487a31 runs 365, all green (`1..365`), so the extra one is not in that tree. Both baselines were run in a clean clone at f6487a31 under `/tmp`, not in the worktree.

## Mutation spot-check
Each guard was disabled once in place, the matching cases were run, and the file was restored from a saved copy and checked with `cmp`.

| Guard disabled | Red |
|---|---|
| an extra key treated as drift again | RAB-16, RAB-17 |
| substitution check off (`if False`) | RAB-7, RAB-17 |
| `--clear-drift needs --resume` | RAB-17 |
| `--clear-drift` still-drift refusal | RAB-17 |
| `--rerow needs --resume` | RAB-18 |
| interrupted/transport_error refusal | RAB-18 |
| exactly-one-row check | RAB-18 |
| `<batch>-` prefix check | RAB-18 |
| `rerow_all` call removed | RAB-18 |
| `rerow_all` moved after the rows loop (ordering) | RAB-18 (old row counted, exit 1) |
| `record_extra` in collect removed | RAB-16 |
| ablation-row `model_missing` never fires | "degraded: the requested model absent…" |
| ablation-row back to "any other key degrades" | "not degraded: an extra model…" |

## DECISION bullets
- DECISION: `drift_check` reports extra models as a **second stdout line**, not a file in the run dir. That keeps it read-only, which `--clear-drift` relies on when it re-reads an old run.
- DECISION: when `model_requested` is null or empty, the absence test uses the manifest's phase model. A phase with neither, or with an empty or non-object `models_used`, is not checked.
- DECISION: `got` for a `models_used.<LABEL>` drift is the sorted key list and `expected` is a normalised string, as the brief specifies. RAB-7's single assertion `.drift.got == "global.anthropic.claude-haiku-9-9"` became `[field, expected, got] == ["models_used.PLAN","claude-opus-5-5",["global.anthropic.claude-haiku-9-9"]]`. That is the only edit to RAB-1 … RAB-15.
- DECISION: the first hit still wins, but `drift_check` now walks every phase before printing so the extra models are complete. The CLI/image checks run only when no model hit was found, which matches the old exit-at-first-hit order.
- DECISION: STATUS keeps a per-run source, `extra_models_by_run`, and derives `extra_models` from it. A rerow then replaces that run's contribution instead of double-counting it. The brief named only `extra_models`, so this extra field is additive.
- DECISION: `--clear-drift` does not record the cleared run's extra models. `--rerow` of that run does, which is the lead's planned command.
- DECISION: `--clear-drift` on a batch with no recorded drift is a no-op note, not a refusal, so the same resume command can be run again safely.
- DECISION: `--clear-drift` and the `--rerow` preconditions are checked read-only **before the lock** and before any STATUS write. The STATUS changes happen only after the lock, in reconciliation.
- DECISION: `post_run` takes `<override>` and `<log>` arguments and no `<arm>`, unlike the brief's sketch. `run_trial` needs the override to skip the chain for watchdog and transport rows, and `--rerow` passes an empty one. It returns its results in `PR_*` globals rather than through dynamic scoping.
- DECISION: a rerow that drifts or fails took-effect under the current rule is rowed `infrastructure_error`. It goes through `apply_flags` like a trial, so it records a drift or pauses the arm and the batch then fails or pauses as usual.
- DECISION: rows are replaced **in place**, keeping line order. A row line that does not parse as JSON is kept byte-for-byte. A row matches only when its `batch` and `run_id` both match.
- DECISION: STATUS.json `rerowed` is patched after each successful rerow, so an exit 2 on a later rerow does not lose the record of an earlier one.

## Could not do / limitations
- The "no run dir" refusal of `--rerow`, and a `transport_error` row, are implemented but not covered by a bats case. The interrupted case covers the shared branch.
- No case shows a validation failure of the replacement temp file. Every rows file the runner can build validates, so that branch is untested.
- The diff on `run-ablation.sh` is large, about 430 lines. Most of it is two block moves: `drift_check` into the helpers section, and resume reconciliation below the function definitions so rerows can run before it. The reconciliation logic itself is unchanged apart from the new loads and the `rerow_all` call.
- shellcheck is not installed on this host, so no lint was run.
- No docker, no model call, and nothing was written under the lead's checkout. The only look at it was a read-only run of the new drift-check Python against the live run dirs. It gave `feature-04-t1` drift `null` with extras `{"global.anthropic.claude-haiku-4-5-20251001-v1:0": {"output_tokens": 516, "phases": ["AUDIT"]}}`. `review-04-t1` and `feature-03-t1` gave null with `{}`.

## Handoff notes for the lead
1. The `priority-p1` driver has exited. run.log ends with `failed: drift in priority-p1-a1_full-feature-04-t1` at 11:27:46Z, and there is no `.lock`. Confirm that no `.jobs/*.pgid` process group is still alive before resuming.
2. Apply the patch on the current HEAD, then run the resume:
   ```
   git apply ~/.cache/loa/cycle-130/patches/s3-i.patch
   evals/harness/run-ablation.sh --batch priority-p1 --resume --clear-drift \
     --rerow priority-p1-a1_full-feature-04-t1 --rerow priority-p1-a1_full-review-04-t1 --detach
   ```
3. The rerows re-grade with the grader in the tree, now 1.2.3 (DEC-0546). The other rows of the batch were graded with 1.2.2, so the batch will hold rows from two grader versions. The two rerowed grade.json files will say 1.2.3. Decide whether that needs a NOTES line.
4. `review-04-t1`'s pipeline status is `cap_failure`. Rerowed, its status becomes `cap_failure` unless the grader still flags contamination. It is not `completed`, so expect `rerow …: contaminated → cap_failure` in run.log.
5. The resume pre-flight compares the source commit, the suite manifest hash, the image digest and the CLI version with MANIFEST.json, as before. `harness_commit` in `drift_cleared[]` will be the HEAD the patch is applied on.
