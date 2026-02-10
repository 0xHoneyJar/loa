---
name: "bug"
version: "1.0.0"
description: |
  Triage a bug report through structured phases: eligibility check, hybrid interview,
  codebase analysis, and micro-sprint creation. Produces a handoff contract for /implement.
  Test-first is non-negotiable. Bugs always get their own micro-sprint.

arguments:
  - name: "description"
    type: "string"
    required: false
    description: "Free-form bug description, error message, or stack trace"
    examples:
      - "Login fails when email contains a + character"
      - "TypeError: Cannot read property 'map' of undefined in CartCheckout.tsx:47"
  - name: "--from-issue"
    type: "integer"
    required: false
    description: "GitHub issue number to import as bug report"
    examples: ["42", "278"]

agent: "bug-triaging"
agent_path: "skills/bug-triaging/"

context_files:
  - path: "grimoires/loa/ledger.json"
    required: false
    purpose: "Sprint Ledger for global sprint numbering"
  - path: ".loa.config.yaml"
    required: false
    purpose: "Configuration for PII filters and guardrails"

pre_flight:
  - check: "tool_exists"
    tool: "jq"
    error: "jq is required. Install with: brew install jq / apt install jq"

  - check: "tool_exists"
    tool: "git"
    error: "git is required for branch creation"

outputs:
  - path: "grimoires/loa/a2a/bug-{id}/triage.md"
    type: "file"
    description: "Bug triage handoff contract"
  - path: "grimoires/loa/a2a/bug-{id}/sprint.md"
    type: "file"
    description: "Micro-sprint plan"
  - path: ".run/bugs/{id}/state.json"
    type: "file"
    description: "Bug fix state tracking"
  - path: "grimoires/loa/ledger.json"
    type: "file"
    description: "Sprint Ledger (updated with bugfix cycle)"

mode:
  default: "foreground"
  allow_background: false
---

# Bug Triage

## Purpose

Triage a reported bug through structured phases and produce a handoff contract
for the implementation phase. Test-first is non-negotiable.

## Invocation

```
/bug "description of the bug"
/bug --from-issue 42
/bug
```

## Agent

Launches `bug-triaging` from `skills/bug-triaging/`.

See: `skills/bug-triaging/SKILL.md` for full workflow details.

## Workflow

1. **Phase 0 — Dependency Check**: Verify required tools (jq, git) and optional tools (gh, br)
2. **Phase 1 — Eligibility Check**: Validate the report is a bug (not a feature request)
3. **Phase 2 — Hybrid Interview**: Fill gaps with targeted follow-up questions
4. **Phase 3 — Codebase Analysis**: Identify suspected files, tests, and test infrastructure
5. **Phase 4 — Micro-Sprint Creation**: Generate bug ID, state, sprint, triage handoff

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `description` | Free-form bug description | No (prompted if missing) |
| `--from-issue N` | Import from GitHub issue | No |

## Outputs

| Path | Description |
|------|-------------|
| `grimoires/loa/a2a/bug-{id}/triage.md` | Triage handoff contract |
| `grimoires/loa/a2a/bug-{id}/sprint.md` | Micro-sprint plan |
| `.run/bugs/{id}/state.json` | Bug state tracking |
| `grimoires/loa/ledger.json` | Updated Sprint Ledger |

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "This looks like a feature request" | Eligibility check failed | Use `/plan` instead |
| "Insufficient evidence" | Score < 2 | Provide stack trace, failing test, or repro steps |
| "No test runner detected" | No test infrastructure | Set up tests first |
| "jq is required" | Missing dependency | Install jq |

## After Triage

In interactive mode:
```
/implement sprint-bug-N
```

In autonomous mode:
```
/run --bug "description"
```
