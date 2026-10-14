# Parallel Review — Splitting Strategy

Referenced from `reviewing-code/SKILL.md` `<parallel_execution>` when a sprint is LARGE (or
MEDIUM with >3 tasks); see Phase -1 there for the size thresholds.

## Splitting Strategy: By Sprint Task

For each task with code changes, spawn parallel Explore agent:

```
Task(
  subagent_type="Explore",
  prompt="Review Sprint {X} Task {Y.Z} ({Task Name}):

  **Acceptance Criteria:**
  {Copy from sprint.md}

  **Files to Review:**
  {List from reviewer.md}

  **Check for:**
  1. All acceptance criteria met
  2. Code quality and best practices
  3. Security issues
  4. Test coverage
  5. Architecture alignment

  **Return:** Verdict (PASS/FAIL) with specific issues (file:line) or confirmation"
)
```

## Consolidation

After parallel reviews complete:
1. Collect verdicts from each sub-review
2. If ANY task FAILS → Overall = CHANGES REQUIRED
3. If ALL tasks PASS → Overall = APPROVED
4. Combine issues into single feedback document
