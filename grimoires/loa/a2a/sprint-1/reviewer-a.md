# Implementer A report: Sprint 263 Tasks 1.1, 1.2, 1.7

Worktree `/home/merlin/Documents/thj/code/loa-wt-s1a` at `7600bd7d`. Patch `~/.cache/loa/cycle-131/patches/s1-a.patch`. No model call, no evaluation container, no git write.

## What was built

**Task 1.1: closed mount, pre-launch check, toggles, eval config.**
- `evals/harness/lib/sandbox-mount.sh` has a new shared Python core, `_sm_oracle_py`, with three commands: `answer-set`, `overlay` and `check`. It also gains `overlay_answer_paths`, `check_mount_closed` and `apply_eval_config_variant`, plus three toggles in `apply_arm_toggles`: `bare_model: fable`, `dissent: false` and `oracle_open: true`. The header documents each one.
- The diff parser handles quoted, octal and spaced paths, renames under both names, `/dev/null`, binary lines and CRLF. It skips hunk bodies by line count.
- `evals/harness/pipeline-run.sh` runs these steps in order: mount, overlay, the `copy_source == source_commit` refusal, toggles, eval config, grimoire, beads, manifest, then `check_mount_closed`. The check runs only on mounted review-catch runs without `oracle_open`. With `oracle_open` the run records `mount_overlay=none`.
- `review_catch.overlay_mode` takes `head`, the default, or `base`. Any other value is a usage error.
- With `bare_model: fable`, the BARE phase runs on `global.anthropic.claude-fable-5-1`.
- A failed library call's infra reason now carries its last stderr line.

**Task 1.2.** `evals/harness/took-effect.sh` gains the five rules and the options `--task-yaml` and `--source-repo`. `oracle_closed` runs the pre-launch check's own code, sourced by a literal path.

**Task 1.7: `--allow-partial`.** `evals/harness/run-ablation.sh` passes the flag to the freeze check and to every grader call, and writes `MANIFEST.json.allow_partial`. On `--resume`, the value comes from the batch manifest, and a conflicting flag is a usage error. Two related changes are in the same file:
- took-effect now receives `--task-yaml`.
- The drift guard expects Fable on BARE when the run's toggles set `bare_model: fable`. Without this, every `a0_bare_fable` run would count as drift.

**Suite and docs.**
- `evals/suites/ablation-2.0.yaml` has `oracle_closed` on `a1_full` and a comment block listing the toggles. The four new arms are not added.
- `grimoires/loa/evals/ablation-2.0/README.md` has a new section on the closed mount. This README is not covered by `MANIFEST.sha256`.

**Tests and test stubs.**
- New file `evals/tests/sandbox-mount.bats`. New cases in `took-effect.bats`, `pipeline-run.bats` and `run-ablation.bats`.
- Changed stubs: `fixtures/mount-lib-stub.sh`, `fixtures/ablation-pipeline-stub.sh` and `fixtures/ablation-grade-stub.sh`.

## How it was tested

| File | Cases | New |
|---|---|---|
| sandbox-mount.bats | 12 | 12 |
| took-effect.bats | 30 | 8 |
| pipeline-run.bats | 73 | 9 |
| run-ablation.bats | 46 | 4 |
| **evals/tests/ total** | **480** | 33 (447 before) |

```
bash -c '~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats evals/tests/'
```

- **First full run:** 479 of 479 green, before RAB-c131-4 was added.
- **Final run:** 480 of 480 green, exit 0.
- **Other checks:** `bash -n` passes on every changed script, `validate-suite.sh` is OK on both roots, and the eval.yml trust-boundary scan finds nothing.
- **Real-corpus check:** overlay plus `check_mount_closed` passed on all seven smoke PRs in both modes, against a copy of this worktree's `.claude/`. Answer-path counts: pr-05 3, pr-08 2, pr-12 12, pr-13 47, pr-16 23, pr-17 24, pr-18 20.

## AC evidence

- **FR-1 AC 1: PASS.** The pipeline-run.bats "real library" case snapshots the evidence file and the gate script at the first `-p` launch: all evidence lines are present and the script is at head. sandbox-mount.bats cases 1 to 4 cover every path shape, including the never-followed symlink. The stub-order case proves the call order.
- **FR-1 AC 2: PASS.** took-effect.bats fails (a) on an unmodified mount, (b) on a stray copy, (c) on a mutated path and (d) on a second commit, and passes otherwise. sandbox-mount.bats adds a remote and a dangling later blob.
- **FR-1 AC 5: PASS.** The overlay and its evidence, the oracle_closed pass and fail cases, and the three toggles are all covered. The detector cases belong to Task 1.3 and are not mine.
- **FR-3 AC 1: PASS.** I ran the dry run on the host against a pristine temporary clone at `7600bd7d`, because a dirty source tree is refused. The self-check log came from `record/cycle-130-analysis` (`self-check-replication.log`, 6 PASS lines) and was extracted to `/tmp`. Without the flag the run is refused at the freeze check: "counts: 2 review-catch task(s) … want 4". With the flag it exits 0 with "plan: 1 arms, 2 tasks, 2 trials", and the manifest has `allow_partial: true`. RAB-c131-1 and RAB-c131-2 pin this, and RAB-c131-2 also checks that the grader call carries the flag.
- **FR-5 AC 1, toggle part: PASS.** sandbox-mount.bats has the toggle and refusal cases. pipeline-run.bats covers `dissent`, `bare_model` (dry run, `--phase-models` override, A0 still on Opus) and `oracle_open` skipping the overlay. RAB-c131-4 covers the drift guard. The arm declarations belong to Sprint 2.

## DECISION bullets

- DECISION: `.claude/checksums.json` is excluded from the answer set. It is harness-owned and regenerated, and it holds hashes rather than content. The pr-12 and pr-18 fix commits touch it.
- DECISION: a symlink in the fixture's `head/` or `base/`, or a symlink component in the path, means the path has no version. It is removed from the mount, expected absent, and never written as a link. The corpus holds no symlinks.
- DECISION: clause (b) only compares later-only pinned versions. These are non-empty, match no expected version and match no fixture `head/` or `base/` file. This avoids false hits on pure renames or reverts. The scan skips `pr/` and `.git/`.
- DECISION: a path whose pre-run hash was correct and then changed reports (c) `mount_mutated`. A path whose pre-run hash was already wrong reports (a). Failures sort by clause a, b, c, d; the first is printed with a "(+N more)" count.
- DECISION: clause (d) also rejects an `objects/info/alternates` file and any later-only pinned blob in the sandbox object store. git runs with an empty global and system config, `core.fsmonitor=false`, no pager and literal pathspecs, because the sandbox `.git/config` is writable by the agent.
- DECISION: `copy_source` ends in `-dirty` when the source tree's `.claude/` has uncommitted or untracked changes. A dirty or non-git copy source refuses the overlay.
- DECISION: a fix-commit path outside the PR takes `git show <head_commit>:X` in both modes. When `head_commit` is unknown, the path is removed.
- DECISION: `gate_scripts_at_pr_version` lists the answer paths present after the overlay under `.claude/scripts/`, `.claude/hooks/` or `.claude/skills/*/SKILL.md`, fix-commit paths included. The value is empty, not "none", when there are none.
- DECISION: the overlay writes five extra evidence keys: `overlay_removed`, `overlay_fix_commit`, `overlay_fixture`, `overlay_source_tree` and `mount_closed`. took-effect falls back to `overlay_fixture` when it gets no `--task-yaml`, and never accepts a fixture inside the run directory.
- DECISION: `oracle_closed` passes, with that stated as its evidence, on build runs and on runs with no mount, because `a1_full` applies to every task type.
- DECISION: `bare_model_fable` requires exactly one model key starting `global.anthropic.claude-fable` and no `global.anthropic.claude-opus` key. Other models, such as the WebFetch summariser recorded in DEC-0545, are allowed.
- DECISION: `bare_model: fable` overrides `--phase-models` and the suite's `phase_defaults` for BARE. run-ablation's drift guard expects Fable for those runs.
- DECISION: `no_review_dissent_envelope` also fails when a review envelope exists in the sandbox, not only in `eval/`.
- DECISION: `apply_eval_config_variant` runs for every mounted arm, build and review-catch alike. The keys `budget_scale: "diff"` and `budget_cents_max: 600` do nothing until implementer C's knob lands.
- DECISION: on `--resume`, a manifest without `allow_partial` counts as false. Passing the flag on a batch that started without it is a usage error. Without the flag, the run takes the manifest's value.
- DECISION: I edited three existing stubs without the `c131-` prefix, because the old ones fail under the new code: `mount-lib-stub.sh`, `ablation-pipeline-stub.sh` (a real overlay for `oracle_closed` arms, the `bare_model` mapping, a `bad_overlay` mode) and `ablation-grade-stub.sh` (accepts `--allow-partial`).
- DECISION: toggles that edit `.claude/` content (`effort`, `karpathy_block`, `rule_files`, `audit_delta_instruction`) fail the pre-launch check on a review-catch PR whose answer set includes the edited file. No cycle-131 arm uses them. `a7_effort_medium` on such a PR would be refused.

## What the lead must do

1. **Implementer C:** I wrote these key names: `flatline_protocol.{code_review,security_audit}.budget_scale` (the string "diff") and `.budget_cents_max` (600).
2. **Row writer:** take the overlay mode from the prefix of `mount_overlay`. `gate_scripts_at_pr_version` is a comma list, empty when there are none. `config_variant` is `eval`. In `pipeline.json.arm_evidence` the repeated `overlay_sha256` key collapses to its last value, so the per-path lines exist only in `meta/arm-evidence.txt`.
3. **Smoke risk on pr-12:** head mode removes `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py`, which the fix commit added and which is absent at `head_commit`. Any pinned file that still imports it may break cheval on pr-12. Read that run first.
4. **Fixtures not regenerated:** I did not rerun `ablation-runs/regen.sh`; a rerun would add the new evidence lines.
5. **Sprint 2:** declare the four arms. No `.claude/` file changed, so `checksums.json` needs no regeneration.
