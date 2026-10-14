# Sprint Plan: Run status counts (fixture)

**Version:** 1.0
**Date:** 2026-10-14

## Sprint 1: Open task count

### Sprint Goal
`/run-status` shows how many tasks are still open in each sprint.

### Acceptance Criteria
- [ ] AC-1.1 `/run-status` prints `open tasks: N` per sprint, and a bats test pins the count on a fixture plan with fenced code and an Acceptance Criteria list

### Technical Tasks
- [ ] Task 1.1: Add `.claude/scripts/count-open-tasks.sh` (prints `sprint-N<TAB>count` for the unchecked task lines under `### Technical Tasks`, fences skipped) with `tests/unit/count-open-tasks.bats`, and call it from the run-status skill → **[G-1]** ⇐ none · kind: mechanical
