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

### Level 5: Push Control (v1.30.0)

User-controlled push behavior prevents accidental remote operations.

#### Control Hierarchy

| Priority | Control | Effect |
|----------|---------|--------|
| 1 (highest) | `--local` flag | Never push, never create PR |
| 2 | `--confirm-push` flag | Prompt before pushing |
| 3 | `run_mode.git.auto_push` config | Default behavior |
| 4 (lowest) | Hardcoded default | Auto push (backwards compatible) |

#### Push Mode Settings

| Setting | Behavior |
|---------|----------|
| `true` (default) | Push commits and create draft PR automatically |
| `false` | Never auto-push, keep all changes local |
| `prompt` | Ask user before pushing (HITL confirmation) |

#### Configuration

```yaml
run_mode:
  git:
    auto_push: true    # true | false | prompt
    create_draft_pr: true  # Always true, cannot be changed
```

#### State Tracking

Push mode is recorded in `.run/state.json`:

```json
{
  "options": {
    "local_mode": false,
    "confirm_push": false,
    "push_mode": "AUTO"
  },
  "completion": {
    "pushed": true,
    "pr_created": true,
    "pr_url": "https://github.com/...",
    "skipped_reason": null
  }
}
```

### Level 6: Danger Level Enforcement (v1.20.0)

Skills are classified by risk level and enforced before execution.

#### Danger Levels in Autonomous Mode

| Level | Behavior |
|-------|----------|
| **safe** | Execute immediately |
| **moderate** | Execute with enhanced logging |
| **high** | BLOCK unless `--allow-high` flag |
| **critical** | ALWAYS BLOCK (no override) |

#### Skill Classifications

| Skill | Level | Rationale |
|-------|-------|-----------|
| `implementing-tasks` | moderate | Writes code files |
| `deploying-infrastructure` | high | Creates infrastructure |
| `run-mode` | high | Autonomous execution |
| `autonomous-agent` | high | Full orchestration control |

#### Using --allow-high

```bash
# Execute with high-risk skills allowed
/run sprint-1 --allow-high
/run sprint-plan --allow-high
```

**Warning**: The `--allow-high` flag allows skills that can create infrastructure
or perform external operations. Use with caution.

#### Input Guardrails

Before each skill invocation in Run Mode:

1. **Danger Level Check** - Verify skill allowed in autonomous mode
2. **PII Filter** - Redact sensitive data from input
3. **Injection Detection** - Check for prompt manipulation

All guardrail events logged to `trajectory/guardrails-{date}.jsonl`.

#### Configuration

```yaml
# .loa.config.yaml
guardrails:
  danger_level:
    enforce: true
    autonomous:
      safe: execute
      moderate: execute_with_log
      high: block_without_flag
      critical: always_block
```

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

Execute all sprints in sequence with automatic continuation and consolidated PR.

```
/run sprint-plan [options]

Options:
  --from N            Start from sprint N
  --to N              End at sprint N
  --no-consolidate    Create separate PRs per sprint (legacy behavior)
```

**Sprint Discovery Priority:**
1. `grimoires/loa/sprint.md` sections (`## Sprint N:`)
2. `grimoires/loa/ledger.json` active cycle sprints
3. `grimoires/loa/a2a/sprint-*` directories

**Auto-Continuation Behavior:**
- After Sprint N completes, automatically advances to Sprint N+1
- Circuit breaker state preserved across sprint transitions
- State tracked in `.run/sprint-plan-state.json`
- On any sprint HALTED, outer loop breaks and state preserved

**Sprint Transition Logging:**
```
[SPRINT 1/4] sprint-1 COMPLETE (2 cycles)
[SPRINT 2/4] Starting sprint-2...
```

**Consolidated PR (v1.15.1 - Default Behavior):**

By default, `/run sprint-plan` creates a **single consolidated PR** after all sprints complete:

1. All sprints execute on the same feature branch
2. Each sprint's work is committed with clear sprint markers
3. A single draft PR is created at the end containing all changes
4. PR summary includes per-sprint breakdown

**Consolidated PR Format:**
```markdown
## 🚀 Run Mode: Sprint Plan Complete

**Sprints Completed:** 4
**Total Cycles:** 12
**Files Changed:** 47

### Sprint Breakdown

| Sprint | Status | Cycles | Files Changed |
|--------|--------|--------|---------------|
| sprint-1 | ✅ Complete | 2 | 12 |
| sprint-2 | ✅ Complete | 4 | 18 |
| sprint-3 | ✅ Complete | 3 | 10 |
| sprint-4 | ✅ Complete | 3 | 7 |

### 🗑️ DELETED FILES - REVIEW CAREFULLY
...

### Commits by Sprint

#### Sprint 1
- abc1234 feat: implement user authentication
- def5678 fix: address review feedback

#### Sprint 2
...
```

**Legacy Behavior:**

To create separate PRs per sprint (not recommended):
```
/run sprint-plan --no-consolidate
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
