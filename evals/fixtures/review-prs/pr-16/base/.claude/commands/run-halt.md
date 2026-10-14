---
name: "run-halt"
version: "1.0.0"
description: |
  Gracefully stop a running run. Completes the current phase, commits state,
  pushes to branch, and creates a draft PR marked incomplete.

arguments:
  - name: "force"
    type: "flag"
    required: false
    description: "Stop immediately without completing the current phase"
  - name: "reason"
    type: "string"
    required: false
    description: "Reason for halt (included in the PR); default \"Manual halt\""

agent: "run-mode"
agent_path: "skills/run-mode/"

pre_flight:
  - check: "file_exists"
    path: ".run/state.json"
    error: "No run in progress. Nothing to halt."

outputs:
  - path: ".run/state.json"
    type: "file"
    description: "Updated to state: HALTED"

mode:
  default: "foreground"
  allow_background: true
---

# /run-halt - Gracefully Stop Execution

## Usage

```
/run-halt
/run-halt --force
/run-halt --reason "Need to review approach"
```

## Agent

Launches `run-mode` from `skills/run-mode/`.

See: `.claude/skills/run-mode/SKILL.md` ("`/run-halt` — Graceful Stop") for the commit/push/PR
flow and the halt-state and PR-body templates — full behavior lives there.

## Related

- `/run-status` - Check current state
- `/run-resume` - Continue from halt
- `/run sprint-N` - Start new run
