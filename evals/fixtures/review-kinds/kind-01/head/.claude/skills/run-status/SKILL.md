---
name: run-status
description: Show the current run's sprint and phase
---

# Run Status

<workflow>
## Phase 1: Read state

Read `.run/sprint-plan-state.json` and print the current sprint and phase.

## Phase 1.5: Open task count

Read `grimoires/loa/sprint.md`. Count every line that starts with `- [ ]` and sits under a
`### Technical Tasks` heading inside a `## Sprint N` block; skip lines inside fenced code
blocks and lines under `### Acceptance Criteria`. Remember the count for each sprint.

## Phase 2: Print

Print one line per sprint: `sprint-N: <state> · open tasks: <count from Phase 1.5>`.
</workflow>
