# Agent Teams Reference

> Version: v1.39.0
> Source: [#337](https://github.com/0xHoneyJar/loa/issues/337)
> Status: Experimental (Claude Code Agent Teams is an experimental feature)

## Overview

Claude Code Agent Teams enables multi-session orchestration where a lead agent spawns teammates that work in parallel. Teammates have their own context windows, load the same project CLAUDE.md, and coordinate via a shared task list and peer-to-peer messaging.

**Enable**: Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in environment or `~/.claude/settings.json`:
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

When enabled, the lead gains 7 tools: `TeamCreate`, `TaskCreate`, `TaskUpdate`, `TaskList`, `TaskGet`, `SendMessage`, `TeamDelete`.

## Detection

Agent Teams is active when the `TeamCreate` tool is available. There is no programmatic check — the lead should attempt to use team tools and proceed with single-agent mode if they're unavailable.

**Config gate** (`.loa.config.yaml`):
```yaml
agent_teams:
  enabled: auto    # auto: use if available | true: require | false: disable
```

## Skill Invocation Matrix

| Skill | Lead | Teammate | Rationale |
|-------|------|----------|-----------|
| `/plan-and-analyze` | Yes | No | Single PRD per cycle |
| `/architect` | Yes | No | Single SDD per cycle |
| `/sprint-plan` | Yes | No | Single sprint plan per cycle |
| `/simstim` | Yes | No | Orchestration workflow |
| `/run sprint-plan` | Yes | No | Orchestrates implement calls |
| `/run-bridge` | Yes | No | Orchestrates review loop |
| `/implement sprint-N` | Yes | Yes | Core parallel work pattern |
| `/review-sprint sprint-N` | Yes | Yes | Can review another teammate's work |
| `/audit-sprint sprint-N` | Yes | Yes | Can audit another teammate's work |
| `/bug` | Yes | Yes | Bug triage is independent |
| `/ride` | Yes | No | Single reality output |
| `/update-loa` | Yes | No | Framework management |

**Rule**: If a skill writes to a single shared artifact (PRD, SDD, sprint plan, state files), it is lead-only. If it writes to sprint-scoped directories (`a2a/sprint-N/`), teammates can invoke it.

## Beads Protocol (Lead-Only)

Beads (`br`) uses SQLite with single-writer semantics. In Agent Teams mode, ALL beads operations are serialized through the lead.

### Workflow

```
1. Lead: br sync --import-only          (session start)
2. Lead: br create tasks from sprint    (before spawning teammates)
3. Lead: br update <id> --status in_progress  (on behalf of teammate)
4. Teammate: SendMessage to lead → "claiming task <id>"
5. Lead: br update <id> --status in_progress
6. Teammate: [implements task]
7. Teammate: SendMessage to lead → "completed task <id>"
8. Lead: br close <id> --reason "..."
9. Lead: br sync --flush-only           (session end)
```

### Why Not Direct Beads Access?

- SQLite WAL mode allows concurrent reads but only one writer
- `br sync --flush-only` does a full read-write cycle on the database
- Two teammates running `br close` simultaneously can deadlock
- The lead serializing requests adds ~1s latency per operation, which is negligible for task lifecycle changes

## State File Ownership

| File | Owner | Teammates |
|------|-------|-----------|
| `.run/simstim-state.json` | Lead | Read-only, report via SendMessage |
| `.run/bridge-state.json` | Lead | Read-only, report via SendMessage |
| `.run/sprint-plan-state.json` | Lead | Read-only, report via SendMessage |
| `.run/bugs/*/state.json` | Creator | Others read-only |
| `.run/audit.jsonl` | Any (append-only) | POSIX atomic appends are safe |
| `grimoires/loa/NOTES.md` | Any (append-only) | Prefix entries with `[teammate-name]` |
| `grimoires/loa/a2a/sprint-N/` | Assigned teammate | Others don't write here |
| `grimoires/loa/a2a/index.md` | Lead | Updated after teammate completes |

### Append-Only Safety

Files that support append-only writes (JSONL, NOTES.md) are safe for concurrent access **only when using Bash append** (`echo "..." >> file`), which uses POSIX atomic writes up to `PIPE_BUF` (typically 4096 bytes). The Write tool does a full read-modify-write and is NOT safe for concurrent access. Teammates MUST use Bash append for NOTES.md and audit.jsonl, not the Write tool. Keep individual append operations under 4096 bytes.

## Team Topology Templates

### Template 1: Parallel Sprint Implementation

The primary use case — parallelize sprint execution across teammates.

```
Lead (Orchestrator)
├── Creates team via TeamCreate
├── Creates tasks from sprint plan (1 task per sprint)
├── Manages beads centrally
├── Runs review/audit after each teammate completes
│
├── Teammate A: sprint-1 implementer
│   └── /implement sprint-1 → reviewer.md → SendMessage "done"
├── Teammate B: sprint-2 implementer
│   └── /implement sprint-2 → reviewer.md → SendMessage "done"
└── Teammate C: sprint-3 implementer
    └── /implement sprint-3 → reviewer.md → SendMessage "done"
```

**When to use**: Multiple independent sprints with minimal cross-sprint dependencies.

### Template 2: Isolated Attention (FE/BE/QA)

Separate concerns by domain expertise — teammates don't share context.

```
Lead (Orchestrator — Opus)
├── Coordinates cross-concern handoffs
├── Runs integration review after all teammates
│
├── Teammate FE: Frontend tasks
│   └── UI components, styling, client state
├── Teammate BE: Backend tasks
│   └── API endpoints, database, auth
└── Teammate QA: Test writer
    └── E2E tests, integration tests, edge cases
```

**When to use**: Full-stack features where frontend, backend, and tests can be developed in parallel.

### Template 3: Bridgebuilder Review Swarm

Parallel code review with different perspectives.

```
Lead (Review Orchestrator)
├── Collects reviews from all teammates
├── Synthesizes into unified feedback
│
├── Teammate A: Architecture reviewer
│   └── Design patterns, separation of concerns, scalability
├── Teammate B: Security auditor
│   └── OWASP, auth, input validation, secrets
└── Teammate C: Performance analyst
    └── N+1 queries, caching, bundle size, lazy loading
```

**When to use**: Complex PRs that benefit from multi-perspective review.

## Hook Propagation

Loa's safety hooks are project-scoped (defined in `.claude/hooks/settings.hooks.json`). Teammates working in the same project directory inherit all hooks automatically:

- **block-destructive-bash.sh**: Fires for ALL teammates (PreToolUse:Bash)
- **mutation-logger.sh**: Fires for ALL teammates (PostToolUse:Bash)
- **run-mode-stop-guard.sh**: Fires for ALL teammates (Stop)
- **Deny rules**: Apply to ALL teammates (`.claude/hooks/settings.deny.json`)

No additional configuration is needed for hook propagation.

## Quality Gate Preservation

Every teammate's code MUST go through the full quality cycle:

```
Teammate implements → Lead runs /review-sprint → Lead runs /audit-sprint
```

The lead is responsible for ensuring no teammate's work is merged without review and audit. In the parallel sprint template, the workflow is:

1. Teammate completes `/implement sprint-N`
2. Teammate sends `SendMessage` to lead: "sprint-N implementation complete"
3. Lead runs `/review-sprint sprint-N` (or assigns to a different teammate)
4. Lead runs `/audit-sprint sprint-N` (or assigns to a different teammate)
5. Lead updates beads: `br close <task-id>`

**Cross-review pattern**: For higher quality, Teammate A reviews Teammate B's work and vice versa. The lead orchestrates this via task assignments.

## Environment Variables

| Variable | Purpose | Set By |
|----------|---------|--------|
| `LOA_TEAM_ID` | Team identifier for audit trail | Lead (before spawning) |
| `LOA_TEAM_MEMBER` | Teammate name for audit trail | Lead (per teammate) |
| `LOA_CURRENT_MODEL` | Model identifier (existing) | Runtime |
| `LOA_CURRENT_PROVIDER` | Provider identifier (existing) | Runtime |
| `LOA_TRACE_ID` | Distributed trace ID (existing) | Runtime |

These variables are captured by the mutation logger (`mutation-logger.sh`) in `.run/audit.jsonl`.

## Troubleshooting

### "TaskCreate not available"

Agent Teams is not enabled. Set the environment variable:
```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

### Beads lock contention

A teammate ran `br` directly instead of going through the lead. Resolution:
1. Wait for the lock to release (SQLite timeout is typically 5s)
2. If stuck, the lead runs `br sync` to recover state

### Teammate ignoring constraints

Teammates load CLAUDE.md but may not follow all constraints perfectly. The lead should verify teammate output before marking tasks complete. The quality gates (review + audit) serve as the safety net.

### State file corruption

If `.run/` state files become inconsistent:
1. Check the audit trail for recent state file writes: `grep 'simstim-state' .run/audit.jsonl | tail -5`
2. Restore from the lead's last known good state
3. Have teammates re-report their status via SendMessage
