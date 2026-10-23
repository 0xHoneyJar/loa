# Reviewer concerns — sprint-1 (PR: cycle-131 sprint-263)

Scope: pr/head.diff (35 files). Cite as head/<path>:<line>.

## Primary concern
1. pipeline-run.sh runs `overlay_answer_paths` BEFORE `apply_arm_toggles`, then `check_mount_closed`
   compares the sandbox against the overlay_sha256 recorded at overlay time. The `effort` toggle
   (lib/sandbox-mount.sh apply_arm_toggles) rewrites every `.claude/skills/*/SKILL.md` frontmatter and
   `.claude/defaults/model-config.yaml`. On arm a7_effort_medium (task_types: all) for a review-catch PR
   whose answer set holds a SKILL.md with an `effort:` line, clause (c) reports mount_mutated and the
   trial is refused as infrastructure_error before any phase. Same class for karpathy_block
   (CLAUDE.loa.md, constraints.json), rule_files, audit_delta_instruction.

## Other areas to probe
2. recall-vs-defects.sh 1.3.0 scope detection: markdown `#` lines inside fenced code blocks read as
   headings; bash `close_line` uses raw indentation while headers use expandtabs(8).
3. recall-vs-defects.sh head_dir fallback `$workspace/pr/head` is the agent-writable sandbox copy when
   EVAL_HEAD_DIR is unset and the manifest-dir fixture is absent.
4. ablation-grade.sh oracle detector: `split_segments` splits on `&` so `2>&1` breaks a segment;
   `exposed_unknown` fires on any non-error diff body without ranges.
5. ablation-grade.sh corpus_sha256 re-opens the file by path after read_regular (TOCTOU, no NOFOLLOW).
6. took-effect.sh resolve_fixture with --task-yaml does not try $SOURCE_TREE/evals/fixtures (pipeline-run
   resolve_rel does) and does not fall back to the overlay_fixture evidence.
7. ablation-row.sh 1.4: poslist nulls a whole list when a v1-only id's position exceeds defects_seeded.
8. adversarial-review.sh: budget_scale diff with budget_cents_max below budget_cents lowers the budget
   (documented); budget_cents_max 0 accepted.
9. ablation-report.py: partition keys now carry pin/rule text used in version-labelled messages.
