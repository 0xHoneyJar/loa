# Reviewer concerns — sprint-1 (PR: sprint-264, cycle-131 FR-5 arms)

Paths are under pr/head/.

1. HIGH — evals/harness/ablation-report.py:653-658 `primaries()`: an arm with task_types [review-catch] (the three new
   component arms a0_bare_fable, a1_review_only, a1_no_dissent) gets `all_types` = [hidden_test_pass_rate, defect_catch_rate].
   compare(arm, a1_full, hidden_test_pass_rate) can never pair (the arm has no build rows), so usable() is False, decide()
   sets nopair and returns "inconclusive: no valid pair (hidden_test_pass_rate...)" whenever investigate/keep do not fire.
   `remove` and `simplify` are unreachable and `decidable` is always False for those arms. The H1/A4 path has a
   not_testable read (assess()); the component path has none. No test covers a review-catch-only component with rows.
2. MEDIUM — ablation-report.py:1913 counts a0_bare_fable as a "component" although the suite comment (ablation-2.0.yaml:94-95)
   calls it "A0 on the review model" — a baseline. It gets a keep/remove/simplify decision row and inflates k in the
   expected-false-positives line.
3. MEDIUM — evals/suites/ablation-2.0.yaml:55 `priority` not extended: the three decision arms never run by default,
   yet the report counts them (k=9) and prints no_rows decisions for them.
4. LOW — ablation-2.0.yaml:117 stale comment "over 6 components".
5. LOW — pipeline-run.sh:341-345 dry-run config_edits re-implements apply_arm_toggles' mapping by hand from the raw
   SUITE_TOGGLES (not the library-resolved TOGGLES used at run time, line 510-515): drift risk, and toggles like
   karpathy_block/rule_files/audit_delta_instruction are not reported.
6. LOW — validate-suite.sh:137-139 TOGGLE_VALUES is a hand-copied vocabulary of lib/sandbox-mount.sh (while RULE_IDS is
   derived from took-effect.sh); a new toggle in the library without a validator edit is rejected silently.
7. LOW — PR.md title claims "the cycle-131 suite root (bounds 50/40) with its image self-check", absent from the diff.
