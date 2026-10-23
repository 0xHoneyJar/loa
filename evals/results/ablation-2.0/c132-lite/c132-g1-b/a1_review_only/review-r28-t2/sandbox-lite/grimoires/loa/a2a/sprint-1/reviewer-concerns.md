# Reviewer concerns — sprint-1 (PR: cycle-131 sprint-264)

Diff under review: pr/head.diff (11 files under evals/).

1. ablation-report.py: the component filter now admits the three review-catch-only arms
   (a0_bare_fable, a1_review_only, a1_no_dissent) but `Analysis.primaries()` has no review-only
   branch — a review-catch-only arm gets [hidden_test_pass_rate, defect_catch_rate]; the pass-rate
   comparison has n == 0 (the arm never runs build tasks), `usable()` is false, `nopair` is true,
   so `decide()` can never return remove/simplify for these arms (always inconclusive unless
   investigate/keep on defect_catch_rate).
2. ablation-report.py: a0_bare_fable is a bare baseline, yet it is counted as a "component" decision
   (keep/remove/simplify of a component) and inflates the expected-false-positive count.
3. ablation-report.py: a1_full_openmount (eval_only) is excluded from components and detail_arms, so
   its rows are never surfaced anywhere — the open-mount A/B the arm exists for has no report output.
4. ablation-2.0.yaml: the four new arms are not in `priority`, so run-ablation.sh's default arm set
   never schedules them; rules comment still says "over 6 components".
5. pipeline-run.sh: the eval_only refusal exits before the REFUSAL (not declared / absent /
   inapplicable task type) is reported, masking the more specific reason; the dry-run sandbox line
   hand-mirrors apply_arm_toggles (drift risk); validate-suite.sh hardcodes TOGGLE_VALUES instead of
   reading lib/sandbox-mount.sh as it does for took-effect.sh rule ids.
6. PR description claims "the cycle-131 suite root (bounds 50/40) with its image self-check" — no
   such change is in the diff.
7. Tests: run-ablation.bats RAB-c131-5 smoke case assumes the smoke root yields exactly two trials
   for a1_full; pipeline-run.bats c131_arms now loads real arms (a0_bare_fable became review-catch
   only).
