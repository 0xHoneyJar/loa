# Reviewer concerns — sprint-1 (PR: sprint-263, closed review-catch mount / grader 1.3.0 / dissent anchors)

Phase 2 notes for the cross-model dissenter. Line numbers refer to pr/head/ files.

1. evals/harness/pipeline-run.sh:565-578 — check_mount_closed runs AFTER apply_arm_toggles. The
   `effort` toggle (lib/sandbox-mount.sh:357-389) rewrites every .claude/skills/*/SKILL.md and
   .claude/defaults/model-config.yaml. When a review-catch fixture's answer set holds such a file,
   clause (c) fails (mount_mutated) and the trial is infrastructure_error. Reproduced locally with the
   real library: overlay → effort:medium → check → "FAIL (c) .claude/skills/s2/SKILL.md: mount_mutated".
   Arm a7_effort_medium has task_types [all] in evals/suites/ablation-2.0.yaml.
2. evals/harness/ablation-report.py:1138-1160 part_split — when one suite_version holds two grader
   rules, build rows (rule None) get their own "rule n/a" partition, separated from every review row;
   the largest partition becomes the primary. Reproduced: three partitions each "H1: established".
3. evals/graders/recall-vs-defects.sh:137-141 — EVAL_HEAD_DIR falls back to <workspace>/pr/head; in
   the ablation grader the workspace is the grading copy of the agent-writable sandbox pr/. Only
   reached when resolve_pr_fixture fails (ablation-grade.sh:1628-1635 swallows GradeError).
4. evals/graders/recall-vs-defects.sh:285-289 CLOSE_ONE — a header line like `f() { local x=${1}`
   ends with `}` and is read as a one-line definition; the body then has no scope.
5. .claude/scripts/adversarial-review.sh:162-187 — budget_scale read only via yq tag; a yq failure
   ("unreadable") sets CONF_BUDGET_SCALE_SET=true and the envelope then names a scaling the config
   never wrote.
6. evals/suites/ablation-2.0.yaml:77 — oracle_closed is listed for a1_full only; a3_one_voice and
   a7_effort_medium run the closed mount but are never post-run verified.
7. evals/harness/ablation-grade.sh envelope_texts:1564-1573 — anchor path part regex requires a
   file extension; an anchor on an extensionless script (e.g. `.claude/hooks/pre-commit:main`) falls
   back to `file`, which may be absent, so the numeric anchor is dropped.
8. Tests: tests/unit/adversarial-review-*.bats could not run here (helper file not in the PR);
   evals/tests/sandbox-mount.bats 12/12 pass; ablation-row/report/run-ablation suites pass;
   took-effect/pipeline-run/grader suites need fixtures absent from this frozen tree.
