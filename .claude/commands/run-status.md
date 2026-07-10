---
name: "run-status"
version: "1.0.0"
description: |
  Display current run state and progress — run details, cycle progress,
  metrics, and circuit breaker status.

arguments:
  - name: "json"
    type: "flag"
    required: false
    description: "Output as JSON"
  - name: "verbose"
    type: "flag"
    required: false
    description: "Show detailed breakdown (cycle history, circuit breaker history, deleted files)"

agent: "run-mode"
agent_path: "skills/run-mode/"

outputs: []

mode:
  default: "foreground"
  allow_background: false
---

# /run-status - Display Run Progress

## Usage

```
/run-status
/run-status --json
/run-status --verbose
```

## Agent

Launches `run-mode` from `skills/run-mode/`.

See: `.claude/skills/run-mode/SKILL.md` ("`/run-status` — Display Progress") for the report
layout, JSON schema, verbose sections, and the sprint-plan status variant — full behavior lives
there.

## Related

- `/run sprint-N` - Start a run
- `/run-halt` - Stop execution
- `/run-resume` - Continue from halt
