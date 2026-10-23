# Reviewer concerns (Phase 2) — sprint-1 (PR: sprint-264, cycle-131 FR-5 arms)

1. evals/suites/ablation-2.0.yaml:55 — `priority` not updated with the four new arms; run-ablation.sh:570-571 derives the default arm set from `.priority`, so a default batch never schedules a0_bare_fable, a1_review_only, a1_no_dissent, a1_full_openmount.
2. evals/harness/ablation-report.py:653-658 — `primaries()` returns [hidden_test_pass_rate, defect_catch_rate] for any arm whose task_types contains review-catch; the three new review-catch-only components have no build rows so the pass-rate comparison is never usable → decide() returns inconclusive (no valid pair) whenever investigate/keep do not fire; remove/simplify unreachable.
3. evals/harness/ablation-report.py:1913, 2003 — the eval_only arm is dropped from components AND detail_arms, so the open-mount A/B it exists for is never rendered.
4. evals/harness/pipeline-run.sh:338-346 — dry-run config_edits re-implements apply_arm_toggles' mapping by hand (drift risk vs lib/sandbox-mount.sh).
5. evals/suites/ablation-2.0.yaml:29-31, 117 — stale header text ("every mounted review-catch arm runs the closed mount", "over 6 components").
6. PR.md claims a suite root (bounds 50/40) and an image self-check; neither is in the diff.
