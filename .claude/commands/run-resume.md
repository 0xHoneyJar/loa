---
name: "run-resume"
version: "1.0.0"
description: |
  Resume a halted run from its last checkpoint. Validates state, verifies
  branch integrity, and continues execution.

arguments:
  - name: "reset-ice"
    type: "flag"
    required: false
    description: "Reset circuit breaker before resuming"
  - name: "force"
    type: "flag"
    required: false
    description: "Skip branch divergence check"

agent: "run-mode"
agent_path: "skills/run-mode/"

pre_flight:
  - check: "file_exists"
    path: ".run/state.json"
    error: "No run state found. Start a new run with /run sprint-N."

outputs:
  - path: ".run/state.json"
    type: "file"
    description: "Updated to state: RUNNING"

mode:
  default: "foreground"
  allow_background: true
---

# /run-resume - Continue From Checkpoint

## Usage

```
/run-resume
/run-resume --reset-ice
/run-resume --force
```

## Agent

Launches `run-mode` from `skills/run-mode/`.

See: `.claude/skills/run-mode/SKILL.md` ("`/run-resume` — Continue From Checkpoint") for the
pre-flight validation (state, branch match, divergence, circuit breaker) and phase-continuation
logic — full behavior lives there.

## Related

- `/run-halt` - Stop execution
- `/run-status` - Check current state
- `/run sprint-N` - Start new run
