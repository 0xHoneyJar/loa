# ablation-2.0 cycle-131 suite (Sprint 264, 2026-10-20)

This is the suite root for the cycle-131 "honest review-catch measurement" batches (PRD FR-5, sprint Task 2.2). It holds two review-catch tasks, `review-r17` and `review-r18`, built on the review-corpus PRs pr-17 and pr-18. The schema is the same as `grimoires/loa/evals/ablation-2.0/` (see its README). Rows from this suite go to their own results root and are never pooled with the cycle-130 read or the replication-01 rows.

## Provenance

| File | Copied from | Change |
|------|-------------|--------|
| `tasks/review-r17/TASK.md`, `tasks/review-r17/REVIEW.md` | `grimoires/loa/evals/ablation-2.0-replication/tasks/review-r17/` | none (byte-identical) |
| `tasks/review-r18/TASK.md`, `tasks/review-r18/REVIEW.md` | `grimoires/loa/evals/ablation-2.0-replication/tasks/review-r18/` | none (byte-identical) |
| `tasks/review-r17/task.yaml`, `tasks/review-r18/task.yaml` | the same directories | the `bounds` line only |

The one change is the `bounds` line of both `task.yaml` files, which becomes `bounds: {max_turns: {}, timeout_min: {REVIEW: 50, AUDIT: 40}}` (DEC-0640). The cycle-131 closed-mount smoke's pr-17 REVIEW phase hit the suite's 30-minute REVIEW cap while the diff-scaled dissent ran. The bound is a per-task fallback declared before any batch, not a change to the suite's phase defaults. `max_turns` stays empty, so the suite's phase defaults apply. `suite_version: 2` is unchanged, and every other field is the replication root's.

`REVIEW.md` is the agent-facing review brief and stays byte-identical to the replication root's, so this note lives here and not in the task directories.

## How the batches run this root

- **Per-run cap.** The batch driver passes `run-ablation.sh --run-cap 30`, a per-run cap of USD 30 for these two large PRs (DEC-0645, after the smoke priced a closed-mount run with the dissent at USD 18-22 on pr-17 and pr-18).
- **Eval config variant.** Every mounted arm runs the harness's eval config variant: both gates get `budget_scale: diff` with `budget_cents_max: 600` in the sandbox `.loa.config.yaml` (`evals/harness/lib/sandbox-mount.sh` `apply_eval_config_variant`; run evidence `config_variant=eval`). The shipped `.loa.config.yaml` is untouched.
- **Closed mount.** Every mounted review-catch arm runs under the closed mount (head overlay), except the evaluation-only open-mount arm, which records `mount_overlay=none`.
- **Partial suite.** Two tasks are fewer than four per type, so every freeze check, run and grade passes `--allow-partial`.

## Freeze and self-check

- `MANIFEST.sha256` is written by `bash evals/harness/freeze.sh --root grimoires/loa/evals/ablation-2.0-c131 --allow-partial` and covers `tasks/` only.
- The image self-check (`ablation-grade.sh --self-check base|reference|noisy`, two tasks × three modes, image `loa-ablation:258`) is recorded at `grimoires/loa/a2a/sprint-2/self-check-c131.log`. Pass it to the batch with `--self-check-log`.
