# /run-resume Command

## Purpose

Resume a halted run from last checkpoint. Validates state, verifies branch integrity, and continues execution.

## Usage

```
/run-resume
/run-resume --reset-ice
/run-resume --force
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--reset-ice` | Reset circuit breaker before resuming | false |
| `--force` | Skip branch divergence check | false |

## Pre-flight Checks

```bash
preflight_resume() {
  local state_file=".run/state.json"
  local cb_file=".run/circuit-breaker.json"

  # 1. Verify state file exists
  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: No run state found"
    echo "Start a new run with /run sprint-N"
    exit 1
  fi

  # 2. Verify state is HALTED
  local current_state=$(jq -r '.state' "$state_file")
  if [[ "$current_state" != "HALTED" ]]; then
    echo "ERROR: Run is not halted (state: $current_state)"
    if [[ "$current_state" == "RUNNING" ]]; then
      echo "Run is already in progress. Use /run-status to check."
    elif [[ "$current_state" == "JACKED_OUT" ]]; then
      echo "Run is already complete. Start a new run with /run sprint-N"
    fi
    exit 1
  fi

  # 3. Verify branch matches
  local expected_branch=$(jq -r '.branch' "$state_file")
  local current_branch=$(git branch --show-current)

  if [[ "$current_branch" != "$expected_branch" ]]; then
    echo "ERROR: Branch mismatch"
    echo "Expected: $expected_branch"
    echo "Current:  $current_branch"
    echo ""
    echo "Checkout the correct branch:"
    echo "  git checkout $expected_branch"
    exit 1
  fi

  # 4. Verify branch hasn't diverged (unless --force)
  if [[ "$1" != "--force" ]]; then
    check_branch_divergence "$expected_branch"
  fi

  # 5. Check circuit breaker state
  if [[ -f "$cb_file" ]]; then
    local cb_state=$(jq -r '.state' "$cb_file")
    if [[ "$cb_state" == "OPEN" && "$2" != "--reset-ice" ]]; then
      echo "WARNING: Circuit breaker is OPEN"
      echo ""
      show_circuit_breaker_reason
      echo ""
      echo "To reset and continue:"
      echo "  /run-resume --reset-ice"
      echo ""
      echo "To continue without reset (may halt again):"
      echo "  /run-resume --force"
      exit 1
    fi
  fi
}
```

### Check Branch Divergence

```bash
check_branch_divergence() {
  local branch="$1"

  # Fetch latest from remote
  git fetch origin "$branch" 2>/dev/null || true

  # Check if local and remote have diverged
  local local_head=$(git rev-parse HEAD)
  local remote_head=$(git rev-parse "origin/$branch" 2>/dev/null || echo "none")

  if [[ "$remote_head" == "none" ]]; then
    # Remote branch doesn't exist yet, that's fine
    return 0
  fi

  # Check if they're the same
  if [[ "$local_head" == "$remote_head" ]]; then
    return 0
  fi

  # Check if local is ahead of remote (that's fine)
  if git merge-base --is-ancestor "origin/$branch" HEAD; then
    return 0
  fi

  # Branch has diverged
  echo "ERROR: Branch has diverged from remote"
  echo ""
  echo "Local:  $local_head"
  echo "Remote: $remote_head"
  echo ""
  echo "This can happen if:"
  echo "  - Someone else pushed to the branch"
  echo "  - You made changes outside of Run Mode"
  echo ""
  echo "To force resume (may cause conflicts):"
  echo "  /run-resume --force"
  echo ""
  echo "To sync with remote first:"
  echo "  git pull --rebase origin $branch"
  exit 1
}
```

### Show Circuit Breaker Reason

```bash
show_circuit_breaker_reason() {
  local cb_file=".run/circuit-breaker.json"

  if [[ ! -f "$cb_file" ]]; then
    return
  fi

  local last_trip=$(jq '.history[-1]' "$cb_file")

  if [[ "$last_trip" != "null" ]]; then
    local trigger=$(echo "$last_trip" | jq -r '.trigger')
    local reason=$(echo "$last_trip" | jq -r '.reason')
    local timestamp=$(echo "$last_trip" | jq -r '.timestamp')

    echo "Circuit breaker tripped:"
    echo "  Trigger:   $trigger"
    echo "  Reason:    $reason"
    echo "  Timestamp: $timestamp"
  fi
}
```

## Execution Flow

### Resume Run

```bash
resume_run() {
  local reset_ice="${1:-false}"
  local state_file=".run/state.json"
  local cb_file=".run/circuit-breaker.json"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Get run info
  local run_id=$(jq -r '.run_id' "$state_file")
  local target=$(jq -r '.target' "$state_file")
  local phase=$(jq -r '.phase' "$state_file")
  local current_cycle=$(jq '.cycles.current' "$state_file")

  echo "[RESUME] Continuing run $run_id..."
  echo "Target: $target"
  echo "Phase: $phase"
  echo "Cycle: $current_cycle"

  # Reset circuit breaker if requested
  if [[ "$reset_ice" == "true" ]]; then
    reset_circuit_breaker
  fi

  # Update state to RUNNING
  jq --arg ts "$timestamp" '
    .state = "RUNNING" |
    del(.halt) |
    .timestamps.last_activity = $ts
  ' "$state_file" > "$state_file.tmp"
  mv "$state_file.tmp" "$state_file"

  echo ""
  echo "✓ State updated to RUNNING"
  echo ""
  echo "Continuing from $phase phase..."

  # Continue execution based on phase
  continue_from_phase "$target" "$phase"
}
```

### Reset Circuit Breaker

```bash
reset_circuit_breaker() {
  local cb_file=".run/circuit-breaker.json"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  echo "Resetting circuit breaker..."

  jq --arg ts "$timestamp" '
    .state = "CLOSED" |
    .triggers.same_issue.count = 0 |
    .triggers.same_issue.last_hash = null |
    .triggers.no_progress.count = 0 |
    .triggers.cycle_count.current = 0 |
    .triggers.timeout.started = $ts
  ' "$cb_file" > "$cb_file.tmp"
  mv "$cb_file.tmp" "$cb_file"

  echo "✓ Circuit breaker reset"
}
```

### Continue From Phase

```bash
continue_from_phase() {
  local target="$1"
  local phase="$2"

  case "$phase" in
    "INIT")
      # Start from beginning
      echo "Restarting from initialization..."
      # Continue with /run logic
      ;;
    "IMPLEMENT")
      echo "Resuming implementation..."
      # /implement $target then continue loop
      ;;
    "REVIEW")
      echo "Resuming from review..."
      # /review-sprint $target then continue loop
      ;;
    "AUDIT")
      echo "Resuming from audit..."
      # /audit-sprint $target then continue loop
      ;;
    *)
      echo "Unknown phase: $phase"
      echo "Starting from implementation..."
      ;;
  esac

  # The actual continuation happens in the /run command
  # This command just validates and updates state
  echo ""
  echo "Ready to continue. The run will resume execution."
}
```

## Output

### Successful Resume

```
[RESUME] Continuing run run-20260119-abc123...
Target: sprint-3
Phase: REVIEW
Cycle: 3

✓ State updated to RUNNING

Continuing from REVIEW phase...
Resuming from review...

Ready to continue. The run will resume execution.
```

### With Circuit Breaker Reset

```
[RESUME] Continuing run run-20260119-abc123...
Target: sprint-3
Phase: IMPLEMENT
Cycle: 4

Resetting circuit breaker...
✓ Circuit breaker reset

✓ State updated to RUNNING

Continuing from IMPLEMENT phase...
Resuming implementation...

Ready to continue. The run will resume execution.
```

## Error Cases

### No State Found

```
ERROR: No run state found
Start a new run with /run sprint-N
```

### Run Not Halted

```
ERROR: Run is not halted (state: RUNNING)
Run is already in progress. Use /run-status to check.
```

### Branch Mismatch

```
ERROR: Branch mismatch
Expected: feature/sprint-3
Current:  main

Checkout the correct branch:
  git checkout feature/sprint-3
```

### Branch Diverged

```
ERROR: Branch has diverged from remote

Local:  abc1234
Remote: def5678

This can happen if:
  - Someone else pushed to the branch
  - You made changes outside of Run Mode

To force resume (may cause conflicts):
  /run-resume --force

To sync with remote first:
  git pull --rebase origin feature/sprint-3
```

### Circuit Breaker Open

```
WARNING: Circuit breaker is OPEN

Circuit breaker tripped:
  Trigger:   same_issue
  Reason:    Same finding repeated 3 times
  Timestamp: 2026-01-19T14:25:00Z

To reset and continue:
  /run-resume --reset-ice

To continue without reset (may halt again):
  /run-resume --force
```

## State After Resume

### state.json

```json
{
  "run_id": "run-20260119-abc123",
  "target": "sprint-3",
  "branch": "feature/sprint-3",
  "state": "RUNNING",
  "phase": "REVIEW",
  "timestamps": {
    "started": "2026-01-19T10:00:00Z",
    "last_activity": "2026-01-19T15:00:00Z"
  },
  "cycles": {
    "current": 3,
    "limit": 20,
    "history": [...]
  },
  "metrics": {...}
}
```

Note: The `halt` field is removed on resume.

## Example Session

```
> /run-resume --reset-ice

[RESUME] Continuing run run-20260119-abc123...
Target: sprint-3
Phase: REVIEW
Cycle: 3

Resetting circuit breaker...
✓ Circuit breaker reset

✓ State updated to RUNNING

Continuing from REVIEW phase...
Resuming from review...

Ready to continue. The run will resume execution.

[RUNNING] Cycle 3 continuing...
→ Phase: REVIEW
  Executing /review-sprint sprint-3...
  ✓ All good

→ Phase: AUDIT
  Executing /audit-sprint sprint-3...
  ✓ APPROVED - LET'S FUCKING GO

[COMPLETE] All checks passed!
...
```

## Related

- `/run-halt` - Stop execution
- `/run-status` - Check current state
- `/run sprint-N` - Start new run
