---
name: "run"
version: "1.0.0"
description: |
  Autonomous execution of sprint implementation with cycle loop until review and
  audit pass.

arguments:
  - name: "target"
    type: "string"
    required: true
    description: "Sprint to implement (e.g., sprint-1), or 'sprint-plan'"
  - name: "max-cycles"
    type: "string"
    required: false
    description: "Maximum iteration cycles (default 20)"
  - name: "timeout"
    type: "string"
    required: false
    description: "Maximum runtime in hours (default 8)"
  - name: "branch"
    type: "string"
    required: false
    description: "Feature branch name (default feature/<target>)"
  - name: "dry-run"
    type: "flag"
    required: false
    description: "Validate but don't execute"
  - name: "reset-ice"
    type: "flag"
    required: false
    description: "Reset circuit breaker before starting"
  - name: "local"
    type: "flag"
    required: false
    description: "Keep all changes local (no push, no PR)"
  - name: "confirm-push"
    type: "flag"
    required: false
    description: "Prompt before pushing to remote"
  - name: "bug"
    type: "flag"
    required: false
    description: "Bug Run Mode: triage → implement → review → audit"
  - name: "from-issue"
    type: "string"
    required: false
    description: "Bug Run Mode: GitHub issue number to triage from"
  - name: "allow-high"
    type: "flag"
    required: false
    description: "Allow high-risk skills / bug areas in autonomous mode"

agent: "run-mode"
agent_path: "skills/run-mode/"

pre_flight:
  - check: "file_exists"
    path: ".loa-version.json"
    error: "Loa not mounted. Run /mount first."

outputs:
  - path: ".run/state.json"
    type: "file"
    description: "Run progress, metrics, options"
  - path: ".run/circuit-breaker.json"
    type: "file"
    description: "Circuit breaker trigger counts and history"

mode:
  default: "foreground"
  allow_background: true
---

# /run - Autonomous Sprint Execution

## Usage

```
/run sprint-1
/run sprint-1 --max-cycles 10 --timeout 4
/run sprint-1 --local
/run sprint-plan
/run --bug "Login fails when email contains + character"
```

## Agent

Launches `run-mode` from `skills/run-mode/`.

See: `.claude/skills/run-mode/SKILL.md` for pre-flight checks, the state machine, circuit breaker,
completion/PR flow, rate limiting, and Bug Run Mode — full behavior lives there.

## Related

- `/run sprint-plan` — Execute all sprints (consolidated PR)
- `/run-status` — Check current run progress
- `/run-halt` — Gracefully stop execution
- `/run-resume` — Continue from checkpoint
