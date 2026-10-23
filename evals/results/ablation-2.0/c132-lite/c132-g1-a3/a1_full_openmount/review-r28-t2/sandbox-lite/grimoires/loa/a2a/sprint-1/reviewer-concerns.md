# Reviewer concerns — sprint-1 (PR: sprint-264 cycle-131 arms, eval_only refusal, validate-suite arm schema)

Scope: pr/head.diff (11 files under evals/). Cite as head/<path>:<line>.

1. head/evals/harness/ablation-report.py:1913 — the three new review-catch-only arms (a0_bare_fable, a1_review_only,
   a1_no_dissent) are now components. Analysis.primaries() (line 653-657) gives any arm whose task_types holds
   review-catch BOTH primaries (hidden_test_pass_rate + defect_catch_rate); decide() (line ~848-887) requires every
   primary usable (n > 0) before `remove`/`simplify`; the pass-rate primary can never pair for an arm that runs no
   build task, so these components can only ever read investigate/keep/inconclusive. primaries_by_arm has
   build_only but no review_only.
2. head/evals/harness/ablation-report.py:1913 and :2003 — a1_full_openmount (eval_only) is in the suite and not absent,
   so list_reason() (line 1108) lets its rows into the cells, but it is excluded from components AND detail_arms,
   so its rows are reported nowhere (not decided, not listed, not detailed, absent from report.json .arms). The
   open-mount oracle A/B that the arm exists for is not surfaced.
3. head/evals/harness/ablation-report.py:1913 — a0_bare_fable is a bare baseline (A0 on the review model) but is
   treated as a removable component with a keep/remove/simplify decision vs a1_full, and inflates k in the
   expected-false-positive line (9). The suite rules comment (ablation-2.0.yaml:117) still says "over 6 components"
   and the rules block is pre-registered/mirrored in NOTES.
4. head/evals/harness/pipeline-run.sh:341-345 — the dry-run re-derives apply_arm_toggles' config edits in jq (a second
   copy of the toggle→config mapping; validate-suite.sh TOGGLE_VALUES at :137-139 is a third). No test checks parity
   with lib/sandbox-mount.sh.
5. head/evals/tests/run-ablation.bats:1173-1175 — RAB-c131-4 (pre-existing) appends a second `a0_bare_fable` to a copy
   of the committed suite, which now already declares it; run-ablation picks [0] (the committed one), so the test
   exercises a duplicated arm id and its appended definition is dead.
6. PR title promises "the cycle-131 suite root (bounds 50/40) with its image self-check" — no grimoires/loa/evals
   files are in the diff.
7. head/evals/harness/validate-suite.sh:171-172 — took_effect is now REQUIRED on every non-absent arm (previously
   optional) — check-8 text says "is a list"; any fixture suite lacking it now fails validation.
