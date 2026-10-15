# ablation-2.0 task suite (cycle-130)

The frozen task suite for the Loa 2.0 component ablation (PRD FR-5, SDD §3.2). Grader-only material lives under each task's `hidden/` directory and is never copied into a sandbox.

## Layout

```
grimoires/loa/evals/ablation-2.0/
  MANIFEST.sha256        freeze.sh: one "<sha256>  <relpath>" line per file (tasks/, and smoke/ with --smoke)
  tasks/<id>/            the sixteen frozen tasks (Sprint 259)
    task.yaml            schema below; validate-suite.sh checks it
    TASK.md              the brief the agent sees (no grader paths, defect ids or arm ids)
    REVIEW.md            the fairness review (Sprint 259)
    fixture/             build tasks: the base tree (never .claude/, CLAUDE.md, .loa.config.yaml, grimoires/, .run/)
    hidden/              manifest.json {"files": [{"src", "dest"}]}, tests/…, reference.patch
  smoke/<id>/            the two Sprint 258 smoke tasks, same layout
```

## task.yaml (schema_version 1)

`id`, `schema_version: 1`, `type` (feature-build | bug-fix | refactor | review-catch), `source {kind, fix_commit?, base_commit?, bead?, date}`, `post_cutoff`, `fixture` (directory relative to this root; null for review-catch), `criterion` (agent-facing behaviour, never a path or test name), `success_criterion` (grader-facing), `test_command` (array, first token python3 | pytest | bats | bash | node | npx; null for review-catch), `regression_command` (array or null), `reference_patch` (under `hidden/` or null), `grader_protected` (paths restored before grading), `structural_check` (under `hidden/` or null; required for refactor), `bounds {max_turns{}, timeout_min{}}` (empty maps = the suite's phase defaults), `review_catch` (null, or `{fixture, manifest, labels?}` for review-catch), `suite_version`.

## Tools

- `evals/harness/validate-suite.sh [--root DIR] [--smoke] [--allow-partial] [--suite-file F]`
- `evals/harness/freeze.sh [--root DIR] [--smoke] [--check] [--allow-partial]`

## Smoke tasks

- `smoke/smoke-review-01` — review-catch on the frozen corpus PR `review-prs/pr-01`; `TASK.md` carries the arm-neutral output contract (`review.md`, one `head/<path>:<line> — <description>` per finding, a final `Verdict:` line).
- `smoke/smoke-build-01` — bug-fix from `evals/fixtures/implement-tasks/01` with its test moved to `hidden/tests/test_slug.py` (plus two collapse cases, so it is red at base) and a reference patch that makes it green.
