# Reviewer concerns — sprint-1 (PR: cycle-131 sprint-264 review-catch arms)

1. ablation-report.py `Analysis.primaries()` (head/evals/harness/ablation-report.py:654-658) returns [hidden_test_pass_rate, defect_catch_rate] for any arm whose task_types contain review-catch. The three new review-catch-only components (a0_bare_fable, a1_review_only, a1_no_dissent) therefore always get a `no valid pair (hidden_test_pass_rate)` clause in `decide()` and can never reach `remove` or `simplify`. rules.primaries_by_arm has only build_only/all_types keys.
2. The eval_only arm a1_full_openmount is excluded from `components` and `detail_arms`, but `list_reason()` has no eval_only branch, so its rows enter cells and are then rendered nowhere (not listed, not decided, not in arms JSON).
3. suites/ablation-2.0.yaml `priority:` (line 55) was not extended with the four new arms; run-ablation.sh derives the default --arms from priority, so a default batch never schedules them.
4. pipeline-run.sh dry-run block re-derives the sandbox config edits (toggle → .loa.config.yaml keys) by hand instead of asking lib/sandbox-mount.sh apply_arm_toggles; validate-suite.sh hard-codes the toggle vocabulary while reading rule ids from took-effect.sh — three copies of the toggle semantics.
5. Stale comment: suite rules.multiple_comparisons says "over 6 components" (now 9).
6. PR description claims "the cycle-131 suite root (bounds 50/40) with its image self-check" but no suite-root file is in the diff.
