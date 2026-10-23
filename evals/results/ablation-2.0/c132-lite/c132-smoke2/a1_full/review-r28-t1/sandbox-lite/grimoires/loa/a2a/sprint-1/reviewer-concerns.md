# Reviewer concerns — sprint-1 (PR: sprint-264, cycle-131 FR-5 arms)

Scope: pr/head.diff (11 files: evals/harness/{ablation-report.py,pipeline-run.sh,run-ablation.sh,validate-suite.sh}, evals/suites/ablation-2.0.yaml, evals/tests/*).

1. ablation-report.py `primaries()` (head:653-658, unchanged) returns [hidden_test_pass_rate, defect_catch_rate] for any arm whose task_types contains "review-catch". The PR adds the first review-catch-only arms (a0_bare_fable, a1_review_only, a1_no_dissent, suite head:98-103) and counts them as components (head:1913). For those arms compare(PASS) can never pair (no build rows) → usable() false → decide() falls to "inconclusive: no valid pair (hidden_test_pass_rate)" unless investigate/keep fires on CATCH. remove/simplify unreachable; decidable always False.
2. a1_full_openmount rows (eval_only) are neither decided, listed (list_reason returns None: arm present, applies to review-catch) nor rendered (not in components/detail_arms). Valid rows vanish from the report; only its excluded rows show in the Exclusions table.
3. a0_bare_fable (a bare baseline on the review model) is counted as a "component" in the Decisions table and in k for the expected-false-positive line (9). Component semantics (remove/simplify) do not fit a baseline arm.
4. Suite rules comment head:117 still says "over 6 components".
5. validate-suite.sh TOGGLE_VALUES (head:137-139) is a hand copy of lib/sandbox-mount.sh apply_arm_toggles vocabulary; RULE_IDS is read from took-effect.sh but the toggle vocabulary is not read from the lib. Drift risk. Arm-level `effort`, `phases`, `label` are not schema-checked.
6. pipeline-run.sh dry-run `sb_edits` jq (head:337-341) duplicates apply_arm_toggles' config-edit mapping; no parity test against the lib (only literal string expectations).
7. PR title claims "the cycle-131 suite root (bounds 50/40) with its image self-check" — no such files in the diff. reviewer.md has no AC Verification section.
8. took-effect.sh is not in the PR; the five new rule ids (oracle_closed, oracle_open_recorded, bare_model_fable, review_only_phases, no_review_dissent_envelope) are assumed to exist (VS-16 would fail otherwise). Unverifiable here.
