# /run-halt Command

## Purpose

Gracefully stop a running run. Completes current phase, commits state, pushes to branch, and creates draft PR marked as incomplete.

## Usage

```
/run-halt
/run-halt --force
/run-halt --reason "Need to review approach"
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--force` | Stop immediately without completing phase | false |
| `--reason "..."` | Reason for halt (included in PR) | "Manual halt" |

## Pre-flight Checks

```bash
preflight_halt() {
  local state_file=".run/state.json"

  # Check if run is in progress
  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: No run in progress"
    echo "Nothing to halt."
    exit 1
  fi

  # Check current state
  local current_state=$(jq -r '.state' "$state_file")

  if [[ "$current_state" == "JACKED_OUT" ]]; then
    echo "ERROR: Run already completed"
    exit 1
  fi

  if [[ "$current_state" == "HALTED" ]]; then
    echo "Run is already halted."
    echo "Use /run-resume to continue or clean up with:"
    echo "  rm -rf .run/"
    exit 0
  fi
}
```

## Execution Flow

### Graceful Halt (Default)

```
1. Check current phase
2. If phase incomplete:
   - Wait for phase completion (if possible)
   - Or skip to commit
3. Commit current changes
4. Push to feature branch
5. Create draft PR marked INCOMPLETE
6. Preserve .run/ state for resume
7. Update state to HALTED
8. Output summary
```

### Force Halt

```
1. Immediately interrupt current operation
2. Commit any staged changes
3. Push to feature branch
4. Create draft PR marked INCOMPLETE
5. Preserve .run/ state for resume
6. Update state to HALTED
7. Output summary with warning
```

## Implementation

### Halt Execution

```bash
halt_run() {
  local force="${1:-false}"
  local reason="${2:-Manual halt}"
  local state_file=".run/state.json"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Get current info
  local run_id=$(jq -r '.run_id' "$state_file")
  local target=$(jq -r '.target' "$state_file")
  local branch=$(jq -r '.branch' "$state_file")
  local phase=$(jq -r '.phase' "$state_file")

  echo "[HALT] Stopping run $run_id..."
  echo "Target: $target"
  echo "Phase: $phase"
  echo "Reason: $reason"

  if [[ "$force" == "true" ]]; then
    echo ""
    echo "WARNING: Force halt - current phase interrupted"
  else
    # Complete current phase if safe
    complete_current_phase "$phase"
  fi

  # Commit any pending changes
  commit_pending_changes "$reason"

  # Push to branch
  push_to_branch "$branch"

  # Create incomplete PR
  create_incomplete_pr "$target" "$reason"

  # Update state
  update_halt_state "$reason" "$timestamp"

  # Output summary
  output_halt_summary "$run_id" "$target" "$branch" "$reason"
}
```

### Complete Current Phase

```bash
complete_current_phase() {
  local phase="$1"

  case "$phase" in
    "IMPLEMENT")
      echo "Completing implementation phase..."
      # Implementation is already committed in cycles
      echo "✓ Implementation phase safe to halt"
      ;;
    "REVIEW")
      echo "Review in progress..."
      echo "✓ Review can be resumed"
      ;;
    "AUDIT")
      echo "Audit in progress..."
      echo "✓ Audit can be resumed"
      ;;
    *)
      echo "Unknown phase: $phase"
      ;;
  esac
}
```

### Commit Pending Changes

```bash
commit_pending_changes() {
  local reason="$1"

  # Check for uncommitted changes
  if git diff --quiet && git diff --staged --quiet; then
    echo "No pending changes to commit"
    return 0
  fi

  echo "Committing pending changes..."

  # Stage all changes
  git add -A

  # Commit with halt message
  git commit -m "WIP: Run halted - $reason

This commit contains work-in-progress from an interrupted Run Mode session.
Use /run-resume to continue from this point.

Run ID: $(jq -r '.run_id' .run/state.json)
Target: $(jq -r '.target' .run/state.json)
Cycle: $(jq '.cycles.current' .run/state.json)
Phase: $(jq -r '.phase' .run/state.json)
"

  echo "✓ Changes committed"
}
```

### Push to Branch

```bash
push_to_branch() {
  local branch="$1"

  echo "Pushing to $branch..."

  # Use ICE for safe push
  .claude/scripts/run-mode-ice.sh push origin "$branch"

  echo "✓ Pushed to $branch"
}
```

### Create Incomplete PR

```bash
create_incomplete_pr() {
  local target="$1"
  local reason="$2"

  local state_file=".run/state.json"
  local run_id=$(jq -r '.run_id' "$state_file")
  local current_cycle=$(jq '.cycles.current' "$state_file")
  local files_changed=$(jq '.metrics.files_changed' "$state_file")
  local findings_fixed=$(jq '.metrics.findings_fixed' "$state_file")

  local body="## Run Mode Implementation - INCOMPLETE

### Status: HALTED

**Run ID:** $run_id
**Target:** $target
**Halt Reason:** $reason

### Progress at Halt
- Cycles completed: $current_cycle
- Files changed: $files_changed
- Findings fixed: $findings_fixed

### Cycle History
\`\`\`
$(jq -r '.cycles.history[] | "Cycle \(.cycle): \(.phase) - \(.findings) findings"' "$state_file")
\`\`\`

$(generate_deleted_tree)

---
:warning: **INCOMPLETE** - This PR represents partial work.

### To Resume
\`\`\`
/run-resume
\`\`\`

### To Abandon
\`\`\`
rm -rf .run/
git branch -D $(jq -r '.branch' "$state_file")
\`\`\`

:robot: Generated autonomously with Run Mode
"

  # Check if PR already exists
  local existing_pr=$(gh pr list --head "$(jq -r '.branch' "$state_file")" --json number -q '.[0].number' 2>/dev/null)

  if [[ -n "$existing_pr" ]]; then
    echo "Updating existing PR #$existing_pr..."
    gh pr edit "$existing_pr" --title "[INCOMPLETE] Run Mode: $target" --body "$body"
  else
    echo "Creating draft PR..."
    .claude/scripts/run-mode-ice.sh pr-create \
      "[INCOMPLETE] Run Mode: $target" \
      "$body" \
      --draft
  fi

  echo "✓ PR created/updated"
}
```

### Update Halt State

```bash
update_halt_state() {
  local reason="$1"
  local timestamp="$2"
  local state_file=".run/state.json"

  jq --arg r "$reason" --arg ts "$timestamp" '
    .state = "HALTED" |
    .halt = {
      "reason": $r,
      "timestamp": $ts
    } |
    .timestamps.last_activity = $ts
  ' "$state_file" > "$state_file.tmp"
  mv "$state_file.tmp" "$state_file"
}
```

### Output Summary

```bash
output_halt_summary() {
  local run_id="$1"
  local target="$2"
  local branch="$3"
  local reason="$4"

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                    RUN HALTED                                 ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║ Run ID:    $run_id"
  echo "║ Target:    $target"
  echo "║ Branch:    $branch"
  echo "║ Reason:    $reason"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║ State preserved in .run/"
  echo "║"
  echo "║ To resume:"
  echo "║   /run-resume"
  echo "║"
  echo "║ To reset circuit breaker and resume:"
  echo "║   /run-resume --reset-ice"
  echo "║"
  echo "║ To abandon:"
  echo "║   rm -rf .run/"
  echo "╚══════════════════════════════════════════════════════════════╝"
}
```

## State After Halt

### state.json

```json
{
  "run_id": "run-20260119-abc123",
  "target": "sprint-3",
  "branch": "feature/sprint-3",
  "state": "HALTED",
  "phase": "REVIEW",
  "halt": {
    "reason": "Manual halt",
    "timestamp": "2026-01-19T14:30:00Z"
  },
  "timestamps": {
    "started": "2026-01-19T10:00:00Z",
    "last_activity": "2026-01-19T14:30:00Z"
  },
  "cycles": {
    "current": 3,
    "limit": 20,
    "history": [...]
  },
  "metrics": {
    "files_changed": 15,
    "files_deleted": 2,
    "commits": 3,
    "findings_fixed": 7
  }
}
```

## Example Session

```
> /run-halt --reason "Need to review architecture approach"

[HALT] Stopping run run-20260119-abc123...
Target: sprint-3
Phase: REVIEW
Reason: Need to review architecture approach

Completing review phase...
✓ Review can be resumed

Committing pending changes...
✓ Changes committed

Pushing to feature/sprint-3...
✓ Pushed to feature/sprint-3

Creating draft PR...
✓ PR created/updated

╔══════════════════════════════════════════════════════════════╗
║                    RUN HALTED                                 ║
╠══════════════════════════════════════════════════════════════╣
║ Run ID:    run-20260119-abc123
║ Target:    sprint-3
║ Branch:    feature/sprint-3
║ Reason:    Need to review architecture approach
╠══════════════════════════════════════════════════════════════╣
║ State preserved in .run/
║
║ To resume:
║   /run-resume
║
║ To reset circuit breaker and resume:
║   /run-resume --reset-ice
║
║ To abandon:
║   rm -rf .run/
╚══════════════════════════════════════════════════════════════╝
```

## Related

- `/run-status` - Check current state
- `/run-resume` - Continue from halt
- `/run sprint-N` - Start new run
