# Sprint 260 implementer G — Task 3.2 `run-ablation.sh`, `lib/arms-common.sh`, `run-ablation.bats`

Patch: `~/.cache/loa/cycle-130/patches/s3-g.patch` (stat beside it). Seven files, +1893/−60. It applies cleanly to the main checkout at 9ad48150. Nothing was committed, no docker, no model call.

## What was built
- `evals/harness/run-ablation.sh` (1,090 lines). The header (1–188) documents everything. Code landmarks: resume settings :301, detach :321, pre-flight :427–508 (gate :427, freeze :451), plan :511, `write_manifest` :573, lock and orphan guard :633, `account_row` :680, `write_status` :706, resume reconciliation :732, `drift_check` :788, `run_trial` :830, `append_and_validate` :913, `collect` :931, `watchdog_tick` :972, `reap` :997, dispatch :1045, end state :1071.
- `evals/harness/lib/arms-common.sh` (157 lines): `usd_ok`, `fadd`, `json_array` :53–55; `is_transport_failure` :62 (verbatim); `is_pipeline_transport_failure` :72; keyed `est_record`/`est_next` :96–124; `spend_charge` :125 (same log text); `budget_gate` :139.
- `evals/harness/run-arms.sh` sources the lib by a literal path after `pushd` (:91–97). Its duplicates are gone, and `collect` calls `spend_charge`/`est_record`. Header unchanged.
- Test stubs `evals/tests/fixtures/ablation-{pipeline,grade,docker}-stub.sh`. The pipeline stub writes run dirs the real took-effect.sh accepts or rejects, with modes per run_id glob. `evals/tests/run-ablation.bats` has 15 cases.

## Interface as built
```
run-ablation.sh --arms CSV --source-commit SHA [--tasks CSV] [--types CSV] [--trials-build N] [--trials-review N]
  [--max-usd USD] [--run-cap USD] [--concurrency 3] [--batch NAME] [--results-root DIR] [--rows F]
  [--suite-root DIR] [--suite-file F] [--image IMG] [--executor container|host] [--pre-registration-ref TEXT]
  [--seed N] [--self-check-log F] [--smoke] [--dry-run] [--resume] [--detach] [--clear-arm ID]...
  [--pipeline-bin P] [--grade-bin G] [--row-bin R] [--took-effect-bin T] [--docker-bin D]
```
- **Outputs.** Batch files are `<root>/<batch>/{MANIFEST.json, STATUS.json, run.log, spend.txt, REFUSED.txt, driver.log, .gitignore}`. Per trial there is a run dir `<arm>/<task>-t<n>[-r<k>]/` and a log `<arm>/<task>-t<n>.log`. Rows go to the rows file.
- **Environment.** `LOA_ABLATION_SOURCE_TREE`, `_SOURCE_REPO`, `_CACHE`, `_RETRY_WAIT_S` (120), `_WATCHDOG_S`, `_WATCHDOG_GRACE_S` (60), `_POLL_S` (1).
- **Exit codes.**
  - 0: complete.
  - 1: partial (cut, a paused arm with trials left, an excluded row, a trial without a row, or a signalled driver).
  - 2: usage error or pre-flight refusal.
  - 3: failed (drift, invalid or duplicate rows, no completed trial without a cut, or every arm paused).

## Tests added (every RAB case fails before: run-ablation.sh did not exist)
| Case | Proves |
|---|---|
| RAB-1 | dry-run plan shape, `refused:` line, trial-major, every §3.4 MANIFEST field, no run dir |
| RAB-2 | seeded shuffle equals an independent `random.Random` derivation; another seed differs |
| RAB-3 | hard gate refusals with REFUSED.txt only; gate hashes in MANIFEST |
| RAB-4 | `--smoke`: no gate, freeze kept, own rows, `--tasks-dir smoke` |
| RAB-5 | agent_error never retried; transport retried once, twice is transport_error; cap charge; grade exit 2; exact counters and spend |
| RAB-6 | took-effect pause and `--resume --clear-arm` |
| RAB-7 | CLI and model drift fail the batch; resume refused |
| RAB-8 | watchdog with and without a record: rowed interrupted |
| RAB-9 | `--max-usd` cut at trial 3 with the exact `cuts[]` |
| RAB-10 | resume: `-r2` rerun, no duplicate run_id |
| RAB-11 | `--detach` |
| RAB-12 | usage and pre-flight refusals; default arms |
| RAB-13 | signalled driver: partial, process group killed, resume reruns |
| RAB-14 | transport classifier unit cases (fails before the result-text extension) |
| RAB-15 | orphan process group refusal (fails before that guard) |

A mutation spot-check disabled eight guards one at a time: drift, pause, REVIEW.md gate, retry, cap charge, budget, resume done-set and orphan guard. Each one turned its case red.

## bats counts
| Run | Result |
|---|---|
| Before (lead's figure at ba11b860) | 328/328 |
| After, full `evals/tests/` | 343 total (328 + 15), 342 passing |
| After, run-ablation.bats | 15/15 |
| After, run-arms.bats alone | 14/14 on four separate runs (the golden check) |

The one full-suite failure, run-arms RA-9, is a host collision, not the extraction. `sandbox.sh destroy --trial-id X` removes every `/tmp/loa-eval-X-*` (sandbox.sh:238–244), and run-arms trial ids are deterministic. Implementer H's worktree had eight bats processes running at the time. Two simultaneous runs of the same run-arms.bats gave 11/14 and 14/14; the next run alone gave 14/14.

## DECISION:
- DECISION: Added `--rows F`; `--seed` and `--self-check-log` as the brief names them. Timing knobs are env-only (LOA_ABLATION_RETRY_WAIT_S 120, _WATCHDOG_GRACE_S 60, _POLL_S, _CACHE, _SOURCE_REPO).
- DECISION: Rows go to the tracked runs.jsonl only with the default results root; with `--results-root`, to `<root>/runs.jsonl`. Smoke writes `<batch>/rows.jsonl` and refuses the tracked file.
- DECISION: Shuffle: one `random.Random(seed)`; each block arm-major, tasks by id, `random.shuffle`, blocks in trial order.
- DECISION: run_id = `<batch>-<arm>-<task>-t<n>` for good; retries and reruns only get a fresh `-r<k>` dir.
- DECISION: A run_id with a row is done, so `--resume` never reruns an interrupted row (DEC-0405 applies to trials without a row).
- DECISION: took-effect runs only on completed, agent_error and cap_failure runs.
- DECISION: Drift = a phase's model_requested ≠ MANIFEST phase_models, a models_used key outside the manifest's models (refusal fallbacks stay `degraded`), or init `claude_code_version` ≠ cli_version (semver); image_digest when no init version.
- DECISION: Drift and took-effect FAIL rows are infrastructure_error and ungraded; interrupted and transport rows are ungraded.
- DECISION: cli_version = semver of `docker run --rm --network none <image> claude --version` (`cli_version_raw` kept; `unknown` skips the check); image_digest uses pipeline-run.sh's inspect format.
- DECISION: est_next key = arm|kind (build, review-catch), pooled per kind, `cost_hint[kind]` last; run-arms uses pool "all".
- DECISION: cap_failure is charged max(cost, run_cap), counted as assumed when cost < run_cap.
- DECISION: A transport first attempt's spent_usd counts in spent (`spend.ledger_usd`, `retries[].first_attempt_usd`).
- DECISION: Transport = agent_error whose last non-zero-exit phase shows the stderr regex, `api_error_status`, or an is_error result matching "API Error" or the regex. Timeouts and assistant text never count.
- DECISION: per_arm: failed = agent_error; excluded = transport, infrastructure, interrupted, contaminated; plus degraded, skipped_paused. resume_cursor = first plan index without a row.
- DECISION: Hard gate: PASS lines ≥ 2 × tasks + review tasks (36), no FAIL line, REVIEW.md in every tasks/<id>/.
- DECISION: freeze `--check` gets `--smoke` when MANIFEST.sha256 lists smoke/ (as frozen).
- DECISION: `--dry-run` runs the full pre-flight, creating the pinned worktree; MANIFEST.dry-run.json when STATUS.json exists.
- DECISION: `--smoke` defaults to 1/1 trials; the smoke- prefix is reserved; pre_registration_ref is optional.
- DECISION: Non-smoke batches write `<batch>/.gitignore` (run dirs, logs, .lock, .jobs).
- DECISION: The parent is the only rows writer: flock on `<rows>.lock`, `--validate` after each append, duplicate run_id refused.
- DECISION: Pipelines run under `setsid`; watchdog = 2 × phase-sum × 60 s per attempt, TERM, KILL after grace; a missing record is synthesized.
- DECISION: A signalled driver: partial, `signalled: true`, exit 1, live groups TERMed.
- DECISION: `--resume` takes plan and settings from MANIFEST (`--max-usd`, `--concurrency` may change) and refuses recorded drift or a changed commit, suite hash, image or CLI.
- DECISION: The lib leaves `write_status`, `aggregate_status` and `arm_index` per runner.

## Could not do / limitations
- Cut-ladder rungs 2–3 need per-arm trial counts; the binding interface has per-type counts only. Use separate batches.
- The real pipeline-run.sh and ablation-grade.sh were never driven by the runner; the smoke is the first real exercise.
- bash 3.2 is untested (host bash 5.2); the shipped scripts avoid 4.x features.
- GNU `timeout` inside pipeline-run.sh has its own process group, so a SIGKILL after the grace can leave it alive until its own deadline. SIGTERM does reach pipeline-run.sh, which kills its phase.
- `<rows>.lock` appears beside the tracked runs.jsonl; `.gitignore` is outside my files.
- run-arms.bats flakes when two runs share a host (above).

## Handoff notes for the lead
Smoke (Task 3.3). Run the dry run first, then the same command with `--detach` instead of `--dry-run`. The plan is 12 trials, est USD 88 at the hints.
```
evals/harness/run-ablation.sh --smoke --source-commit <sprint-258 sha> \
  --arms a0_bare,a1_full,a2_no_sprint_plan,a3_one_voice,a4_no_gates,a5_no_flatline,a6_one_window,a7_effort_medium \
  --max-usd 100 --pre-registration-ref "<NOTES heading> <ts>" --dry-run
```
Priority batch (Task 3.4), with `--max-usd` = 1500 − spend − 250 − 3 × 12 (DEC-0429). Run the dry run first, then `--detach`.
```
evals/harness/run-ablation.sh --source-commit <sha> \
  --arms a0_bare,a1_full,a2_no_sprint_plan,a3_one_voice,a4_no_gates \
  --trials-build 3 --trials-review 3 --concurrency 3 --max-usd <figure> \
  --batch batch-priority-1 --pre-registration-ref "<NOTES batch-plan heading> <ts>" --dry-run
```
- **Plan size.** The full default plan (8 arms, 3/3) is 336 trials, est USD 2,400. A cut-ladder rung with fewer trials for some arms needs its own batch with `--arms` and `--trials-*`.
- **Monitoring.** Watch STATUS.json, run.log, spend.txt. A pause needs `--batch <name> --resume --clear-arm <id>` after reading the cause.
- **Gitignore.** Add `grimoires/loa/reports/ablation-2.0/runs.jsonl.lock` to `.gitignore`.
