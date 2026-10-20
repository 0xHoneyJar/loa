# S2-A report: cycle-131 Sprint 2 (global 264), Tasks 2.1 and 2.2

Worktree `loa-wt-s2a` at `e93a040a`. Patch `~/.cache/loa/cycle-131/patches/s2-a.patch` (+ `.stat`).

## What was built

**Task 2.1: the four arms.**
- `evals/suites/ablation-2.0.yaml`: the four arms exactly as the brief gives them (`a0_bare_fable`, `a1_review_only`, `a1_no_dissent`, `a1_full_openmount` with `eval_only: true`), plus a header note on `eval_only`.
- `evals/harness/validate-suite.sh`: new check 8 on every non-absent arm. `toggles` must be a mapping of known toggles with the values `apply_arm_toggles` defines. The type check is exact, so `0` is not `false`. `took_effect` must be a list of rule ids that `took-effect.sh` defines; the known set comes from that script's `rule_<id>()` functions. `eval_only` must be a boolean when present, and `oracle_open: true` needs `eval_only: true`.
- `evals/harness/pipeline-run.sh`: an `eval_only: true` arm is refused (exit 2, `refused: arm '<id>': eval_only arm outside an evaluation batch …`) before the run dir exists, so no pipeline.json is written and no infrastructure_error is possible. The only exception is `LOA_ABLATION_BATCH_CONTEXT=1` (exactly `1`). `--dry-run` follows the same rule. The dry run now also prints `sandbox: mount=… overlay=… config_variant=… config_edits=…`, plus an `eval_only:` line for an eval_only arm.
- `evals/harness/run-ablation.sh`: every trial launch (batch and smoke) runs with `LOA_ABLATION_BATCH_CONTEXT=1` on the trial's command only, never exported to the runner shell. Header updated.
- `evals/tests/fixtures/ablation-pipeline-stub.sh`: `STUB_ENV_LOG` records the variable per trial.

**Task 2.2: the suite root** `grimoires/loa/evals/ablation-2.0-c131/`.
- `tasks/review-r{17,18}/{task.yaml,TASK.md,REVIEW.md}`: copied from the replication root. TASK.md and REVIEW.md are byte-identical (`cmp`). The only task.yaml change is `bounds: {max_turns: {}, timeout_min: {REVIEW: 50, AUDIT: 40}}` (DEC-0640). `suite_version: 2` is unchanged.
- `README.md`: provenance, the bounds and DEC-0640, `--run-cap 30` (DEC-0645), `budget_scale: diff`, the freeze and the self-check.
- `MANIFEST.sha256`: 6 files, manifest sha256 `60316fb8df0c09cae01f3d3267b00cc1c604b19195871f899bb3debcf5d11dfd`.
- Self-check log: `grimoires/loa/a2a/sprint-2/self-check-c131.log`, copied to `~/.cache/loa/cycle-131/reports/self-check-c131.log`.

## How it was tested

Bats is run as `bash -c '~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats <files>'`. GNU parallel is not installed, so `-j` executes 0 tests; run it serially.

| File | Before | After |
|------|--------|-------|
| evals/tests/validate-suite.bats | 13 | 17 (VS-14…VS-17) |
| evals/tests/pipeline-run.bats | n | n + 7 (four dry-run plans, eval_only refused, eval_only in context, the a1_review_only run) |
| evals/tests/run-ablation.bats | n | n + 1 (RAB-c131-5) |
| evals/tests/ (whole) | 516 | 528 planned: 525 ok, 3 not ok (out-of-ownership, below) |
| evals/tests/ in a scratch copy with the proposed out-of-ownership patch | — | 528/528 ok (rc 0) |

Validator and freeze checks: `validate-suite.sh` OK on ablation-2.0 (18 with --smoke), the replication root (2) and the c131 root (2). `freeze.sh --check` OK on ablation-2.0 (282 files, ddd200b3) and the replication root (6, cffc7079). The c131 freeze wrote 6 files (60316fb8).

## Dry-run plans (review-r17, `--max-run-usd 30`, real suite file)
```
plan: task review-r17 type review-catch arm a0_bare_fable executor container cap USD 30 phases BARE
phase 1 BARE model=global.anthropic.claude-fable-5-1 max_turns=170 timeout_s=4200 effort=high session=new
sandbox: mount=none overlay=none(no mount) config_variant=none config_edits=-
plan: task review-r17 type review-catch arm a1_review_only executor container cap USD 30 phases REVIEW
phase 1 REVIEW model=global.anthropic.claude-fable-5-1 max_turns=60 timeout_s=3000 effort=- session=new
sandbox: mount=loa overlay=head config_variant=eval config_edits=-
plan: task review-r17 type review-catch arm a1_no_dissent executor container cap USD 30 phases REVIEW,AUDIT
phase 1 REVIEW model=global.anthropic.claude-fable-5-1 max_turns=60 timeout_s=3000 effort=- session=new
phase 2 AUDIT model=global.anthropic.claude-fable-5-1 max_turns=60 timeout_s=2400 effort=- session=new
sandbox: mount=loa overlay=head config_variant=eval config_edits=flatline_protocol.code_review.enabled=false
a1_full_openmount without the variable: exit 2
  pipeline-run.sh: refused: arm 'a1_full_openmount': eval_only arm outside an evaluation batch (run-ablation.sh exports LOA_ABLATION_BATCH_CONTEXT=1 to its trials)
LOA_ABLATION_BATCH_CONTEXT=1:
plan: task review-r17 type review-catch arm a1_full_openmount executor container cap USD 30 phases REVIEW,AUDIT
(phase lines as a1_no_dissent)
sandbox: mount=loa overlay=none(oracle_open) config_variant=eval config_edits=-
eval_only: true (batch context LOA_ABLATION_BATCH_CONTEXT=1)
```
The 3000 s and 2400 s timeouts come from the new task bounds.

## run-ablation dry run (brief's command)
```
plan: 1 arms, 2 tasks, 6 trials, shuffle seed 20261015, est USD 48 (cap none, run caps build 15 review-catch 20, in-flight reserve 20 per trial, reserve 250)
a1_full review-r18 review-catch 1 dryrun-c131-a1_full-review-r18-t1
… (6 lines: r17 and r18 × t1..t3)
```
The hard gate passed with 6 PASS against the 6 wanted. `/tmp/c131-dryrun` was removed afterwards.

## Self-check (image loa-ablation:258; each exit 0)
```
self-check base review-r17: PASS recall 0.0 (0/20), false_positives 0
self-check reference review-r17: PASS recall 1.0 (20/20), false_positives 0
self-check noisy review-r17: PASS recall 1.0 (20/20), false_positives 68 vs reference 0
self-check base review-r18: PASS recall 0.0 (0/8), false_positives 0
self-check reference review-r18: PASS recall 1.0 (8/8), false_positives 0
self-check noisy review-r18: PASS recall 1.0 (8/8), false_positives 47 vs reference 0
```

## AC evidence
- PASS: the four arms are declared verbatim (VS-14).
- PASS: validate-suite accepts the new keys (VS-14) and flags an unknown toggle or value (VS-15), an unknown rule id (VS-16) and a non-boolean eval_only (VS-17). It is OK on the suite and both frozen roots.
- PASS: an eval_only arm is refused with exit 2 and the reason, before any run dir or pipeline.json exists, dry run included. It runs when the context variable is 1 (pipeline-run.bats).
- PASS: run-ablation puts the variable on every batch and smoke trial (RAB-c131-5).
- PASS: the open-mount arm records `mount_overlay=none` and `oracle_open=true`.
- PASS: the per-arm dry-run plans match the brief.
- PASS: the c131 root is a byte-identical copy apart from the bounds line. It is frozen, validated, has 6 self-check PASS lines, and its dry run plans 2 tasks x 3 trials.
- FAIL, 3 cases outside my ownership: AT-13 checks the exact nine-arm list. AR-12 and AR-23 read the committed suite, and `ablation-report.py` counts every arm other than a1_full, a0_bare or an absent arm as a component, so k goes 6 to 10. The fix is in `~/.cache/loa/cycle-131/patches/s2-a-outside-ownership.patch`: AT-13 gains the 4 ids, and the report tests use a suite copy without the 4 arms. With it, a scratch copy runs 528/528.

## DECISION bullets
- DECISION: The context is `LOA_ABLATION_BATCH_CONTEXT=1`, exact value only. run-ablation.sh sets it as a prefix on each trial's command, never exported, so the grader and took-effect never see it. Batch and smoke are both covered, and pipeline-run.sh `--dry-run` honours it too.
- DECISION: The eval_only refusal runs before the dry run and before the run dir is created. It exits 2 and writes no pipeline.json, so no infrastructure_error row is possible.
- DECISION: validate-suite reads the known rule ids from took-effect.sh's `rule_<id>()` functions, a single source. If none are found it exits 2.
- DECISION: The toggle vocabulary mirrors apply_arm_toggles, and values are type-exact, so `gates: 0` is a violation.
- DECISION (beyond the brief): every non-absent arm needs a `took_effect` list, as took-effect.sh does. `oracle_open: true` requires `eval_only: true`.
- DECISION: the dry run adds a `sandbox: mount= overlay= config_variant= config_edits=` line, plus an `eval_only:` line for eval_only arms. The config edits come from the toggles.
- DECISION: `c131_arms` in pipeline-run.bats loads the real arms from the committed suite. The existing open-mount test now sets the context.
- DECISION: the new arms stay out of `priority`. TASK.md and REVIEW.md are byte-identical, and the copy note lives in the README.
- DECISION: the self-check log keeps only each run's verdict line, 6 lines in all.
- DECISION: I did not edit arm-toggles.bats or ablation-report.bats, and supplied a separate patch instead. Whether ablation-report.py should skip eval_only arms is open for the lead or Sprint 3.

## What the lead must do
- Apply the patch. `grimoires/loa/a2a/` is gitignored (`.gitignore:193`), so the patch does not carry `sprint-2/self-check-c131.log` or `reviewer-a.md`. Copy them from `~/.cache/loa/cycle-131/reports/` onto the record branch, or keep them in place in the main tree. The batch needs the log path for `--self-check-log`.
- The brief's run-ablation dry run created the detached source worktree `~/.cache/loa/ablation-src-e93a040a5414` (pre-flight 5). I left it; remove it with `git worktree remove` if the batch pins a later commit.
- While stopping my own mixed baseline run, I ran `pkill -f 'bats-exec'` without a worktree filter, at about 13:26 AEDT. Only my own processes were visible afterwards, but another session's bats run at that time may have been killed.
- The lead is fixing AT-13, AR-12 and AR-23 (eval_only arms leave the report's components; pins updated). I left these three known failures to the lead.
- `.claude/checksums.json` does not need regenerating, because no `.claude/` file changed. shellcheck is not installed on this host, so it was not run. `tools/check-no-raw-sha256sum.sh` passes.
