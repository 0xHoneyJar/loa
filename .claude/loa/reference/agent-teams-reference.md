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
| `/autonomous` | Yes | No | Orchestration workflow |
| `/run sprint-plan` | Yes | No | Orchestrates implement calls |
| `/run-bridge` | Yes | No | Orchestrates review loop |
| `/run` | Yes | No | Orchestrates sprint execution |
| `/plan` | Yes | No | Golden path: routes to plan-and-analyze + architect + sprint-plan |
| `/ship` | Yes | No | Golden path: routes to deploy + archive |
| `/deploy-production` | Yes | No | Infrastructure management |
| `/ride` | Yes | No | Single reality output |
| `/update-loa` | Yes | No | Framework management |
| `/mount` | Yes | No | Framework installation |
| `/loa-eject` | Yes | No | Framework removal |
| `/loa-setup` | Yes | No | Environment setup |
| `/archive-cycle` | Yes | No | Lifecycle management |
| `/implement sprint-N` | Yes | Yes | Core parallel work pattern |
| `/review-sprint sprint-N` | Yes | Yes | Can review another teammate's work |
| `/audit-sprint sprint-N` | Yes | Yes | Can audit another teammate's work |
| `/bug` | Yes | Yes | Bug triage is independent |
| `/build` | Yes | Yes | Golden path: routes to implement |
| `/review` | Yes | Yes | Golden path: routes to review + audit |
| `/feedback` | Yes | Yes | Developer feedback |
| `/translate` | Yes | Yes | Documentation translation |
| `/validate` | Yes | Yes | Validation checks |
| `/compound` | Yes | Yes | Independent analysis |
| `/enhance` | Yes | Yes | Prompt enhancement |
| `/loa` | Yes | Yes | Read-only status check |
| `/flatline-review` | Yes | No | Multi-model review orchestration |
| `/constructs` | Yes | No | Framework pack management |
| `/eval` | Yes | No | Eval runner |

**Rule**: If a skill writes to a single shared artifact (PRD, SDD, sprint plan, state files) or manages lifecycle/infrastructure, it is lead-only. If it writes to sprint-scoped directories (`a2a/sprint-N/`), teammates can invoke it. Enforced mechanically by `team-skill-guard.sh` (PreToolUse:Skill).

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

> **Local filesystem assumption**: `PIPE_BUF` atomicity is guaranteed by POSIX for local filesystems only. Network-mounted volumes (NFS, CIFS) and some Docker storage drivers may not preserve atomicity for concurrent appends. If teammates run on separate containers with a shared volume ([loa-finn#31](https://github.com/0xHoneyJar/loa-finn/issues/31) Section 8), use the lead-serialized pattern for all writes — teammates report via `SendMessage` and the lead performs the actual write.

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

### Template 4: Model-Heterogeneous Expert Swarm

Teammates invoke different models via `cheval.py` for domain-specific expertise.

```
Lead (Orchestrator — Opus)
├── Creates team and distributes research tasks
├── Collects and synthesizes results from all tracks
├── Manages beads centrally, serializes br operations
│
├── Teammate A: Deep Researcher
│   └── cheval.py --agent deep-researcher --prompt "..." → cited analysis
├── Teammate B: Deep Thinker (extended reasoning)
│   └── cheval.py --agent deep-thinker --prompt "..." → reasoned analysis
├── Teammate C: Fast Thinker (quick iterations)
│   └── cheval.py --agent fast-thinker --prompt "..." → rapid prototyping
└── Teammate D: Literature Reviewer
    └── cheval.py --agent literature-reviewer --prompt "..." → survey
```

**Agent binding presets** (configured in `model-config.yaml`):
- `deep-researcher`: Gemini Deep Research Pro (`api_mode: interactions`, per-task pricing)
- `deep-thinker`: Gemini 3 Pro with `thinkingLevel: high`
- `fast-thinker`: Gemini 3 Flash with `thinkingLevel: medium`
- `literature-reviewer`: Gemini 2.5 Pro with `thinkingBudget: -1` (dynamic)

**Cost considerations**:
- Deep Research uses flat per-task pricing (~$2-5 per query), not per-token
- Daily budget limits enforced via `BudgetEnforcer` across all teammates
- `metering.budget.daily_micro_usd` shared across the entire team
- Monitor with: `cheval.py --print-effective-config | grep metering`

**Environment variables**: Teammates inherit `GOOGLE_API_KEY` from the lead process automatically. No per-teammate key configuration needed.

**Example: MAGI-style construct** (3 parallel research tracks):
```
Lead creates 3 research tasks with different angles:
  Task 1 → Teammate "caspar" (deep-researcher): "Analyze market dynamics..."
  Task 2 → Teammate "melchior" (deep-thinker): "Reason about technical approach..."
  Task 3 → Teammate "balthasar" (literature-reviewer): "Survey prior art..."
Each teammate invokes cheval.py, sends results via SendMessage.
Lead synthesizes into unified analysis.
```

**When to use**: Research-heavy tasks where different model strengths (deep research, extended reasoning, speed) map to distinct subtasks.

## Hook Propagation

Loa's safety hooks are project-scoped (defined in `.claude/hooks/settings.hooks.json`). Teammates working in the same project directory inherit all hooks automatically:

- **block-destructive-bash.sh**: Fires for ALL teammates (PreToolUse:Bash)
- **team-role-guard.sh**: Blocks lead-only operations for teammates (PreToolUse:Bash). Only active when `LOA_TEAM_MEMBER` is set — no-op in single-agent mode. Fail-open design.
- **team-role-guard-write.sh**: Blocks teammate writes/edits to System Zone (`.claude/`), state files (`.run/*.json`), and append-only files (PreToolUse:Write, PreToolUse:Edit). Same activation and fail-open design.
- **team-skill-guard.sh**: Blocks lead-only skill invocations for teammates (PreToolUse:Skill). Blocklist-based — checks `tool_input.skill` against lead-only skills. Same activation and fail-open design.
- **mutation-logger.sh**: Fires for ALL teammates (PostToolUse:Bash)
- **write-mutation-logger.sh**: Logs Write/Edit file modifications for ALL teammates (PostToolUse:Write, PostToolUse:Edit)
- **run-mode-stop-guard.sh**: Fires for ALL teammates (Stop)
- **Deny rules**: Apply to ALL teammates (`.claude/hooks/settings.deny.json`)

No additional configuration is needed for hook propagation.

### Mechanical Enforcement (team-role-guard.sh)

The `team-role-guard.sh` hook provides defense-in-depth enforcement of C-TEAM constraints. When `LOA_TEAM_MEMBER` is set, it blocks:

| Pattern | Constraint | Rationale |
|---------|-----------|-----------|
| `br ` commands | C-TEAM-002 | Beads serialization through lead |
| Overwrite (`>`), `cp`/`mv`, `tee` to `.run/*.json` | C-TEAM-003 | State file ownership |
| `git commit`, `git push` | C-TEAM-004 | Git working tree serialization |
| `cp`/`mv`, redirect (`>`), `tee`, `sed -i`, `install`, `patch` to `.claude/` | C-TEAM-005 | System Zone is read-only |

**Allowed for teammates**: `>>` append to any file (POSIX atomic), `git status/diff/log` (read-only), all non-git/non-br commands.

### Mechanical Enforcement (team-role-guard-write.sh)

The `team-role-guard-write.sh` hook extends defense-in-depth to the Write and Edit tools. When `LOA_TEAM_MEMBER` is set, it blocks:

| Pattern | Constraint | Rationale |
|---------|-----------|-----------|
| Write/Edit to `.claude/*` | C-TEAM-005 | System Zone is lead-only |
| Write/Edit to `.run/*.json` (top-level) | C-TEAM-003 | State file ownership |
| Write/Edit to `.run/audit.jsonl` | Append-only | Must use Bash `>>` for POSIX atomic writes |
| Write/Edit to `grimoires/loa/NOTES.md` | Append-only | Must use Bash `>>` for POSIX atomic writes |

**Allowed for teammates**: Write/Edit to `grimoires/loa/a2a/`, `app/`, `.run/bugs/*/` (subdirectories), and all other non-protected paths.

**Script**: `.claude/hooks/safety/team-role-guard-write.sh`

### Mechanical Enforcement (team-skill-guard.sh)

The `team-skill-guard.sh` hook enforces the Skill Invocation Matrix mechanically. When `LOA_TEAM_MEMBER` is set, it blocks lead-only skill invocations by matching `tool_input.skill` against a blocklist:

| Blocked Skills | Constraint | Rationale |
|----------------|-----------|-----------|
| `/plan-and-analyze`, `/architect`, `/sprint-plan` | C-TEAM-001 | Single PRD/SDD/sprint per cycle |
| `/simstim`, `/autonomous` | C-TEAM-001 | Orchestration workflows |
| `/run-sprint-plan`, `/run-bridge`, `/run` | C-TEAM-001 | Run mode orchestration |
| `/ride`, `/update-loa`, `/ship`, `/deploy-production` | C-TEAM-001 | Framework/infrastructure management |
| `/mount`, `/loa-eject`, `/loa-setup`, `/plan`, `/archive-cycle` | C-TEAM-001 | Lifecycle management |
| `/flatline-review`, `/constructs`, `/eval` | C-TEAM-001 | Multi-model review, framework packs, eval runner |

**Allowed for teammates**: `/implement`, `/review-sprint`, `/audit-sprint`, `/bug`, `/review`, `/build`, `/feedback`, `/translate`, `/validate`, `/compound`, `/enhance`, `/loa`.

**Script**: `.claude/hooks/safety/team-skill-guard.sh`

## Enforcement Coverage

Systematic inventory of advisory vs. mechanical enforcement for each Agent Teams constraint. Making the gap visible is honest engineering.

| Constraint | Advisory (CLAUDE.md) | Mechanical (Hook) | Tool Coverage | Gaps |
|-----------|---------------------|-------------------|---------------|------|
| C-TEAM-001 (planning skills lead-only) | Yes | Yes (Skill) | Skill: blocklist-based guard via `team-skill-guard.sh` | — |
| C-TEAM-002 (beads serialization) | Yes | Yes (Bash) | Bash: `br` commands blocked | Write/Edit: no beads files to protect (not a gap) |
| C-TEAM-003 (state file ownership) | Yes | Yes (Bash + Write + Edit) | Full coverage. Append-only files also protected from Write/Edit misuse | — |
| C-TEAM-004 (git serialization) | Yes | Yes (Bash) | Bash: `git commit/push` blocked | Git ops only available via Bash (not a gap) |
| C-TEAM-005 (System Zone readonly) | Yes | Yes (Bash + Write + Edit) | Bash: `cp`/`mv`, redirect, `tee`, `sed -i`, `install`, `patch`; Write/Edit: `realpath -m` normalization | — |

> **Skill Matrix is mechanically enforced**: The Skill Invocation Matrix is enforced via `PreToolUse:Skill` hook (`team-skill-guard.sh`). Lead-only skills are blocked for teammates by matching `tool_input.skill` against a blocklist. The `Skill` tool is a regular Claude Code tool — `PreToolUse:Skill` hooks fire just like `PreToolUse:Bash`.

### Audit Coverage

| Tool | PreToolUse Guard | PostToolUse Audit | Coverage |
|------|-----------------|-------------------|----------|
| Bash | `block-destructive-bash.sh`, `team-role-guard.sh` | `mutation-logger.sh` | Full |
| Write | `team-role-guard-write.sh` | `write-mutation-logger.sh` | Full |
| Edit | `team-role-guard-write.sh` | `write-mutation-logger.sh` | Full |
| Skill | `team-skill-guard.sh` | — | Guard only (skill invocations are not mutations) |
| NotebookEdit | — | — | Not covered (no `.ipynb` in protected zones) |

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
