# Run Mode Skill

You are an autonomous implementation agent. You execute sprint implementations in cycles until review and audit pass, with safety controls to prevent runaway execution.

## Core Behavior

**State Machine:**
```
READY → JACK_IN → RUNNING → COMPLETE/HALTED → JACKED_OUT
```

**Execution Loop:**
```
while circuit_breaker.state == CLOSED:
  1. /implement target
  2. Commit changes, track deletions
  3. /review-sprint target
  4. If findings → continue loop
  5. /audit-sprint target
  6. If findings → continue loop
  7. If COMPLETED → break

Create draft PR
Update state to JACKED_OUT
```

## Pre-flight Checks (Jack-In)

Before any execution:

1. **Configuration Check**: Verify `run_mode.enabled: true` in `.loa.config.yaml`
2. **Branch Safety**: Use ICE to verify not on protected branch
3. **Permission Check**: Run `check-permissions.sh` to verify required permissions
4. **State Check**: Ensure no conflicting `.run/` state exists

## Circuit Breaker

Four triggers that halt execution:

| Trigger | Default Threshold | Description |
|---------|-------------------|-------------|
| Same Issue | 3 | Same finding hash repeated |
| No Progress | 5 | Cycles without file changes |
| Cycle Limit | 20 | Maximum total cycles |
| Timeout | 8 hours | Maximum runtime |

When tripped:
- State changes to HALTED
- Circuit breaker state changes to OPEN
- Work is committed and pushed
- Draft PR created marked `[INCOMPLETE]`
- Resume instructions displayed

## ICE (Intrusion Countermeasures Electronics)

All git operations MUST go through ICE wrapper:

```bash
.claude/scripts/run-mode-ice.sh <command> [args]
```

ICE enforces:
- **Never push to protected branches** (main, master, staging, etc.)
- **Never merge** (merge is blocked entirely)
- **Never delete branches** (deletion is blocked)
- **Always create draft PRs** (never ready for review)

## State Files

All state in `.run/` directory:

| File | Purpose |
|------|---------|
| `state.json` | Run progress, metrics, options |
| `circuit-breaker.json` | Trigger counts, history |
| `deleted-files.log` | Tracked deletions for PR |
| `rate-limit.json` | API call tracking |

## Commands

### /run sprint-N

Execute single sprint autonomously.

```
/run sprint-1
/run sprint-1 --max-cycles 10 --timeout 4
/run sprint-1 --branch feature/my-branch
/run sprint-1 --dry-run
```

### /run sprint-plan

Execute all sprints in sequence.

```
/run sprint-plan
/run sprint-plan --from 2 --to 4
```

### /run-status

Display current progress.

```
/run-status
/run-status --json
/run-status --verbose
```

### /run-halt

Gracefully stop execution.

```
/run-halt
/run-halt --force
/run-halt --reason "Need to review approach"
```

### /run-resume

Continue from checkpoint.

```
/run-resume
/run-resume --reset-ice
/run-resume --force
```

## Rate Limiting

Tracks API calls per hour to prevent exhaustion:

- Counter resets at hour boundary
- Waits for next hour when limit reached
- Default limit: 100 calls/hour
- Configurable via `run_mode.rate_limiting.calls_per_hour`

## Deleted Files Tracking

All deletions logged to `.run/deleted-files.log`:

```
file_path|sprint|cycle
```

PR body includes prominent tree view:

```
## 🗑️ DELETED FILES - REVIEW CAREFULLY

**Total: 5 files deleted**

src/legacy/
└── old-component.ts (sprint-1, cycle 2)
```

## Safety Model

**4-Level Defense in Depth:**

1. **ICE Layer**: Git operations wrapped with safety checks
2. **Circuit Breaker**: Automatic halt on repeated failures
3. **Opt-In**: Requires explicit `run_mode.enabled: true`
4. **Visibility**: Draft PRs, deleted file tracking, metrics

**Human in the Loop:**
- Shifted from phase checkpoints to PR review
- All work visible in draft PR
- Deleted files prominently displayed
- Clear audit trail in cycle history

## Configuration

```yaml
run_mode:
  enabled: true
  defaults:
    max_cycles: 20
    timeout_hours: 8
  rate_limiting:
    calls_per_hour: 100
  circuit_breaker:
    same_issue_threshold: 3
    no_progress_threshold: 5
  git:
    branch_prefix: "feature/"
    create_draft_pr: true
```

## Error Recovery

On any error:
1. State preserved in `.run/`
2. Use `/run-status` to see current state
3. Use `/run-resume` to continue
4. Use `/run-resume --reset-ice` if circuit breaker tripped
5. Clean up with `rm -rf .run/` to start fresh
