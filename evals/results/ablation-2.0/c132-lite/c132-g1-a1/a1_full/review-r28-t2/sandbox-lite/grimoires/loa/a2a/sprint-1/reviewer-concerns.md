# Reviewer concerns — sprint-1 (PR: sprint-264, cycle-131 FR-5 arms)

Scope: pr/head.diff (11 files under evals/). Cite as head/<path>:<line>.

1. ablation-report.py:1913 adds three review-catch-only arms (a0_bare_fable, a1_review_only,
   a1_no_dissent) to `components`, but `Analysis.primaries()` (line 653-658) returns
   [hidden_test_pass_rate, defect_catch_rate] for any arm whose task_types contains review-catch.
   The pass-rate comparison can never pair (the arm runs no build task), so `decide()` (846-877)
   always appends "no valid pair (hidden_test_pass_rate)" and `decidable` (922) is always false:
   remove/simplify are unreachable for the arms this sprint adds. Check whether the suite rules
   (primaries_by_arm has only build_only / all_types) were meant to gain a review_only entry.
2. a0_bare_fable is a baseline variant yet counted as a "component" (k=9 in the EFP line).
3. a1_full_openmount (eval_only) rows are kept by _classify but never rendered: not in
   components, not in detail_arms (2003). Where does the oracle A/B get reported?
4. pipeline-run.sh:341-345 dry-run re-implements apply_arm_toggles' config-edit mapping in jq;
   drift between the two makes the dry run misreport.
5. suite priority (line 55) omits the four new arms: a default batch (--arms unset) never runs them.
6. PR title claims "the cycle-131 suite root (bounds 50/40) with its image self-check" — no such
   files in the diff. Tests VS-14/VS-16/RAB-c131-5 depend on took-effect.sh rules and a frozen
   suite root that are outside the diff.
7. validate-suite.sh:177-180 eval_only/oracle_open coupling and type-exact toggle check look right;
   anything missed (e.g. toggles: null, duplicate arm ids)?
8. pipeline-run.sh:258-262 refusal placement before mkdir (356) looks right; LOA_ABLATION_BATCH_CONTEXT
   is a soft guard by design.
