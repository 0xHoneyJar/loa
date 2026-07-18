---
name: "run-sprint-plan"
version: "1.0.0"
description: |
  Execute all sprints in sequence for complete release cycles, with a single
  consolidated draft PR at the end.

arguments:
  - name: "from"
    type: "string"
    required: false
    description: "Start from sprint N (default 1)"
  - name: "to"
    type: "string"
    required: false
    description: "End at sprint N (default last sprint)"
  - name: "max-cycles"
    type: "string"
    required: false
    description: "Maximum cycles per sprint (default 20)"
  - name: "timeout"
    type: "string"
    required: false
    description: "Maximum runtime in hours (default 8)"
  - name: "branch"
    type: "string"
    required: false
    description: "Feature branch name (default feature/release)"
  - name: "dry-run"
    type: "flag"
    required: false
    description: "Validate but don't execute"
  - name: "no-consolidate"
    type: "flag"
    required: false
    description: "Create separate PR per sprint (legacy) instead of one consolidated PR"

agent: "run-mode"
agent_path: "skills/run-mode/"

pre_flight:
  - check: "file_exists"
    path: ".loa-version.json"
    error: "Loa not mounted. Run /mount first."

outputs:
  - path: ".run/sprint-plan-state.json"
    type: "file"
    description: "Sprint plan progress across all sprints"

mode:
  default: "foreground"
  allow_background: true
---

# /run sprint-plan - Execute All Sprints

## Usage

```
/run sprint-plan                      # Consolidated PR at end (default, recommended)
/run sprint-plan --from 2 --to 4
/run sprint-plan --no-consolidate     # Legacy: separate PR per sprint
```

## Agent

Launches `run-mode` from `skills/run-mode/`.

See: `.claude/skills/run-mode/SKILL.md` ("Sprint Plan Execution Loop") for sprint discovery
priority order, the per-sprint main loop, failure handling, and the consolidated PR template —
full behavior lives there.

## Related

- `/run sprint-N` — Execute single sprint
- `/run-status` — Check current progress
- `/run-halt` — Stop execution
- `/run-resume` — Continue from halt
