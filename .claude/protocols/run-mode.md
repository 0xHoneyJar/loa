# Run Mode Protocol

**Version:** 1.0.0
**Status:** Active
**Updated:** 2026-01-19

---

## Overview

Run Mode enables autonomous execution of implementation cycles. The human-in-the-loop (HITL) shifts from phase checkpoints to PR review, allowing Claude to complete entire sprints without interruption.

## Safety Model: Defense in Depth

Run Mode employs a 4-level defense architecture:

```
┌─────────────────────────────────────────────────────────────────┐
│                     LEVEL 4: VISIBILITY                         │
│  Draft PRs only • Deleted files tracking • Full trajectory      │
├─────────────────────────────────────────────────────────────────┤
│                     LEVEL 3: OPT-IN                             │
│  run_mode.enabled = false by default • Explicit activation      │
├─────────────────────────────────────────────────────────────────┤
│                     LEVEL 2: CIRCUIT BREAKER                    │
│  Same issue 3x → halt • No progress 5x → halt • Rate limiting   │
├─────────────────────────────────────────────────────────────────┤
│                     LEVEL 1: ICE (IMMUTABLE)                    │
│  Protected branches • No merge • No force push • No delete      │
└─────────────────────────────────────────────────────────────────┘
```

### Level 1: ICE (Intrusion Countermeasures Electronics)

Hard-coded git safety that cannot be configured or bypassed.

#### Protected Branches (Immutable)

| Branch | Type |
|--------|------|
| `main` | Exact match |
| `master` | Exact match |
| `staging` | Exact match |
| `develop` | Exact match |
| `development` | Exact match |
| `production` | Exact match |
| `prod` | Exact match |
| `release/*` | Pattern match |
| `release-*` | Pattern match |
| `hotfix/*` | Pattern match |
| `hotfix-*` | Pattern match |

#### Blocked Operations (Always)

| Operation | Rationale |
|-----------|-----------|
| `git merge` | Humans merge PRs |
| `gh pr merge` | Humans merge PRs |
| `git branch -d/-D` | Humans delete branches |
| `git push --force` | Dangerous, data loss risk |
| Checkout to protected | Prevents accidental work on main |
| Push to protected | Prevents direct commits |

#### Allowed Operations

| Operation | Constraint |
|-----------|------------|
| `git checkout` | Feature branches only |
| `git push` | Feature branches only |
| `gh pr create` | Draft mode only |
| `rm` | Within repo, on feature branch |
| `mkdir`, `cp`, `mv` | Within repo |

### Level 2: Circuit Breaker

Automatic halt on repeated failures or lack of progress.

#### Trigger Conditions

| Trigger | Threshold | Description |
|---------|-----------|-------------|
| Same Issue | 3 repetitions | Same finding hash appears 3 times |
| No Progress | 5 cycles | No file changes for 5 consecutive cycles |
| Cycle Limit | Configurable (default: 20) | Maximum cycles exceeded |
| Timeout | Configurable (default: 8h) | Maximum runtime exceeded |

#### State Machine

```
     ┌─────────────────────────────────────────┐
     │                                         │
     ▼                                         │
  CLOSED ─────────► OPEN ─────────► HALF_OPEN ─┘
  (normal)    (trigger)   (--reset-ice)
     │                │
     │                ▼
     │           RECOVERY
     │           (success)
     │                │
     └────────────────┘
```

| State | Description |
|-------|-------------|
| CLOSED | Normal operation, executing cycles |
| OPEN | Halted, waiting for human intervention |
| HALF_OPEN | Recovery attempt after reset |

#### Circuit Breaker Storage

File: `.run/circuit-breaker.json`

```json
{
  "state": "CLOSED",
  "triggers": {
    "same_issue": {"count": 0, "last_hash": null},
    "no_progress": {"count": 0},
    "cycle_count": {"current": 3, "limit": 20},
    "timeout": {"started": "2026-01-19T10:00:00Z", "limit_hours": 8}
  },
  "history": [
    {"timestamp": "...", "trigger": "same_issue", "hash": "abc123"}
  ]
}
```

### Level 3: Opt-In Activation

Run Mode is disabled by default. Explicit configuration required.

```yaml
# .loa.config.yaml
run_mode:
  enabled: true  # Must be explicitly set to true
```

### Level 4: Visibility

All actions are visible for human review:

1. **Draft PRs Only**: All PRs created as drafts, never ready for merge
2. **Deleted Files Tracking**: Prominent section in PR body listing all deletions
3. **Full Trajectory**: Complete audit trail in `grimoires/loa/a2a/trajectory/`
4. **State Persistence**: `.run/state.json` shows current progress

## Execution Flow

### State Machine

```
                            ┌───────────────────┐
                            │      READY        │
                            │  (initial state)  │
                            └─────────┬─────────┘
                                      │ /run
                                      ▼
                            ┌───────────────────┐
                            │     JACK_IN       │
                            │  (pre-flight)     │
                            └─────────┬─────────┘
                                      │ pass
                                      ▼
              ┌─────────────────────────────────────────────┐
              │                  RUNNING                    │
              │                                             │
              │   ┌────────┐    ┌────────┐    ┌────────┐   │
              │   │IMPLEMENT├───►│ REVIEW ├───►│ AUDIT  │   │
              │   └────┬───┘    └───┬────┘    └───┬────┘   │
              │        │            │              │        │
              │        │            │ findings     │ findings
              │        │            ▼              ▼        │
              │        │      ┌─────────────────────┐       │
              │        └──────┤     IMPLEMENT       │◄──────┘
              │               │     (fix cycle)     │       │
              │               └─────────────────────┘       │
              │                                             │
              │             all pass ▼                      │
              └─────────────────────────────────────────────┘
                                      │
              ┌───────────────────────┴───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
    ┌───────────────┐      ┌───────────────┐      ┌───────────────┐
    │   COMPLETE    │      │    HALTED     │      │  JACKED_OUT   │
    │  (PR created) │      │(circuit trip) │      │  (user halt)  │
    └───────────────┘      └───────────────┘      └───────────────┘
```

### Pre-Flight Checks (Jack-In)

Before starting, validate:

1. **Configuration**: `run_mode.enabled = true`
2. **Branch Safety**: Not on protected branch
3. **Permissions**: All required permissions configured
4. **State Clean**: No conflicting `.run/` state

### Main Loop

```
WHILE not complete AND circuit_breaker.state == CLOSED:
    1. /implement sprint-N
    2. Commit changes
    3. Track deleted files
    4. /review-sprint sprint-N
    5. IF review findings:
           Loop back to step 1
    6. /audit-sprint sprint-N
    7. IF audit findings:
           Loop back to step 1
    8. IF all pass:
           Mark complete
```

### Completion (Jack-Out)

On successful completion:

1. Push all commits to feature branch
2. Create draft PR with:
   - Summary of changes
   - Cycle count and metrics
   - Deleted files section (prominent)
   - Test results
3. Update state to COMPLETE
4. Output PR URL

## Rate Limiting

Prevents API exhaustion during long-running operations.

### Configuration

```yaml
# .loa.config.yaml
run_mode:
  rate_limiting:
    calls_per_hour: 100
```

### Behavior

| Condition | Action |
|-----------|--------|
| Under limit | Continue normally |
| At limit | Wait until hour boundary |
| 5 consecutive waits | Halt with circuit breaker |

### Storage

File: `.run/rate-limit.json`

```json
{
  "current_hour": "2026-01-19T10:00:00Z",
  "calls_this_hour": 45,
  "limit": 100,
  "consecutive_waits": 0
}
```

## Deleted Files Tracking

All file deletions are logged and prominently displayed in the PR.

### Log Format

File: `.run/deleted-files.log`

```
src/old-module.ts|sprint-1|cycle-3
tests/deprecated.test.ts|sprint-1|cycle-5
```

### PR Section

```markdown
## 🗑️ DELETED FILES - REVIEW CAREFULLY

**Total: 2 files deleted**

```
src/
└── old-module.ts (sprint-1, cycle-3)
tests/
└── deprecated.test.ts (sprint-1, cycle-5)
```

> ⚠️ These deletions are intentional but please verify they are correct.
```

## State Management

### State File

File: `.run/state.json`

```json
{
  "run_id": "run-20260119-abc123",
  "target": "sprint-1",
  "branch": "feature/sprint-1",
  "state": "RUNNING",
  "phase": "IMPLEMENT",
  "timestamps": {
    "started": "2026-01-19T10:00:00Z",
    "last_activity": "2026-01-19T11:30:00Z"
  },
  "cycles": {
    "current": 3,
    "limit": 20,
    "history": [
      {"cycle": 1, "phase": "IMPLEMENT", "findings": 5},
      {"cycle": 2, "phase": "REVIEW", "findings": 2},
      {"cycle": 3, "phase": "IMPLEMENT", "findings": 0}
    ]
  },
  "metrics": {
    "files_changed": 15,
    "commits": 3,
    "findings_fixed": 7
  }
}
```

### Atomic Updates

State updates use atomic write pattern:
1. Write to temporary file
2. Rename to target (atomic on POSIX)
3. Verify write success

## Commands

### /run

Main autonomous execution command.

```
/run <target> [options]

Options:
  --max-cycles N      Maximum iteration cycles (default: 20)
  --timeout H         Maximum runtime in hours (default: 8)
  --branch NAME       Feature branch name (default: feature/<target>)
  --dry-run           Validate but don't execute
```

### /run sprint-plan

Execute all sprints in sequence.

```
/run sprint-plan [options]

Options:
  --from N            Start from sprint N
  --to N              End at sprint N
```

### /run-status

Display current run progress.

```
/run-status

Output:
  - Run ID, state, target, branch
  - Current cycle and phase
  - Runtime vs timeout
  - Circuit breaker status
  - Metrics
```

### /run-halt

Gracefully stop execution.

```
/run-halt

Actions:
  1. Complete current phase
  2. Commit and push
  3. Create draft PR marked "INCOMPLETE"
  4. Preserve state for resume
```

### /run-resume

Continue from last checkpoint.

```
/run-resume [options]

Options:
  --reset-ice         Reset circuit breaker
```

## Configuration Reference

```yaml
# .loa.config.yaml
run_mode:
  # Master toggle (required to enable)
  enabled: false

  # Default limits
  defaults:
    max_cycles: 20
    timeout_hours: 8

  # Rate limiting
  rate_limiting:
    calls_per_hour: 100

  # Circuit breaker thresholds
  circuit_breaker:
    same_issue_threshold: 3
    no_progress_threshold: 5

  # Git settings
  git:
    branch_prefix: "feature/"
    create_draft_pr: true
```

## Scripts

| Script | Purpose |
|--------|---------|
| `run-mode-ice.sh` | Git safety wrapper (ICE) |
| `check-permissions.sh` | Pre-flight permission validation |

## Related Protocols

- `feedback-loops.md` - Quality gate definitions
- `trajectory-evaluation.md` - Audit trail logging
- `git-safety.md` - Template protection (different scope)

---

*Protocol Version: 1.0.0*
*Run Mode Target Version: v0.18.0*
