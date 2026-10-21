# ablation-2.0 cycle-132 suite (Sprint 269 Task 1.11, 2026-10-21)

The suite root for the cycle-132 "conclusive review-catch answer" batches (PRD FR-3/FR-7, SDD §5.3, PREREGISTRATION.md). It holds fourteen review-catch tasks, `review-r11` … `review-r28`, one per candidate fixture of `candidates.tsv` (DEC-0715: the record fixtures the pipeline had never been evaluated on). The schema is that of `grimoires/loa/evals/ablation-2.0/` (see its README); rows from this root go to their own batches under `evals/results/ablation-2.0/c132-*/` and are never pooled with cycle-130 or cycle-131 rows.

## Provenance

| File | Derived from | Change |
|------|--------------|--------|
| `tasks/review-rNN/TASK.md` | `grimoires/loa/evals/ablation-2.0-c131/tasks/review-r18/TASK.md` | line 3's change summary only: the fixture's `PR.md` title without the conventional-commit prefix and sprint tag |
| `tasks/review-rNN/task.yaml` | `…/ablation-2.0-c131/tasks/review-r18/task.yaml` | `id`, `source.origin`, `source.date` (the head commit's UTC date), the fixture id and the expected verdict in `success_criterion` (CHANGES_REQUIRED when the v2 key holds a high or critical defect, else APPROVED: pr-11, pr-24), `review_catch.manifest` → the v2 manifest `evals/fixtures/review-prs/manifests/pr-NN.json`, and the two matched-arm fields `bare_sessions_matched` (k, Opus 5.5) and `bare_sessions_matched_fable` (k′) from the power run's cost fits (`grimoires/loa/reports/ablation-2.0/power-c132/power.json`, PRD D18) |
| `candidates.tsv` | implementer A's Task 1.1 candidate table | the eligibility proxy and the exclusions documented in its header |

`bounds: {max_turns: {}, timeout_min: {REVIEW: 50, AUDIT: 40}}` and `suite_version: 2` are the cycle-131 values (DEC-0640). Each task carries a `REVIEW.md` fairness review produced by the lead with the three mechanical checks of the cycle-131 fairness sessions (no solution leak; red then green from the image self-check; criterion mechanical) run as a script; the blind key is the two-annotator v2 label set (`grimoires/loa/a2a/sprint-269/annotation/result.md`). The runner refuses a task without one (DEC-0435).

## How the batches run this root

- **Registration.** Every batch passes `--registration grimoires/loa/evals/ablation-2.0-c132/REGISTRATION.json`; the runner refuses a changed registration, a source commit other than the pin, an image other than the bound digest, and derives `--max-usd` from the cycle meter (cap USD 3,800, DEC-0718). The batches run from a checkout at the pinned commit.
- **Arms.** `a1_full` (REVIEW → AUDIT, closed mount, eval config variant), `a0_bare_matched` (k BARE sessions, Opus 5.5, union-graded), `a0_bare_fable_matched` (k′ sessions, Fable 5.1), `a1_review_only`, and `a1_full_openmount` on G1 only (positive control). Per-run cap `--run-cap 30`; concurrency 3 (overshoot bound USD 90).
- **Groups and looks.** [6, 4, 4] PRs in seeded order (pr-27, 28, 23, 14, 15, 25 | 16, 26, 21, 19 | 24, 20, 22, 11); a look after each group with `reads-c132.py --look N`.
- **Partial suite.** Fourteen review-catch tasks and no other type, so every freeze check, run and grade passes `--allow-partial`.

## Freeze and self-check

- `MANIFEST.sha256` is written by `bash evals/harness/freeze.sh --root grimoires/loa/evals/ablation-2.0-c132 --allow-partial` and covers `tasks/` only (`candidates.tsv`, `PREREGISTRATION.md` and `REGISTRATION.json` are bound by the registration instead).
- The image self-check (`ablation-grade.sh --self-check base|reference|noisy` for every task, run inside `loa-ablation:258`, grader 1.3.3) is recorded at `grimoires/loa/reports/ablation-2.0/self-check-c132.txt` (42/42 PASS); the batch driver passes it with `--self-check-log`.
