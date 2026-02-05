# /run Command

## Purpose

Autonomous execution of sprint implementation with cycle loop until review and audit pass.

## Usage

```
/run <target> [options]
/run sprint-1
/run sprint-1 --max-cycles 10 --timeout 4
/run sprint-1 --branch feature/my-branch
/run sprint-1 --dry-run
/run sprint-1 --local
/run sprint-1 --confirm-push
```

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `target` | Sprint to implement (e.g., `sprint-1`) | Yes |

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--max-cycles N` | Maximum iteration cycles | 20 |
| `--timeout H` | Maximum runtime in hours | 8 |
| `--branch NAME` | Feature branch name | `feature/<target>` |
| `--dry-run` | Validate but don't execute | false |
| `--reset-ice` | Reset circuit breaker before starting | false |
| `--local` | Keep all changes local (no push, no PR) | false |
| `--confirm-push` | Prompt before pushing to remote | false |

## Pre-flight Checks (Jack-In)

Before execution begins, validate:

1. **Configuration Check**
   ```bash
   # Check if run_mode.enabled is true in .loa.config.yaml
   if ! yq '.run_mode.enabled // false' .loa.config.yaml | grep -q true; then
     echo "ERROR: Run Mode not enabled. Set run_mode.enabled: true in .loa.config.yaml"
     exit 1
   fi
   ```

2. **Beads-First Check (v1.29.0)**
   ```bash
   # Autonomous mode REQUIRES beads by default
   health=$(.claude/scripts/beads/beads-health.sh --quick --json)
   status=$(echo "$health" | jq -r '.status')

   if [[ "$status" != "HEALTHY" && "$status" != "DEGRADED" ]]; then
     # Check for override
     beads_required=$(yq '.beads.autonomous.requires_beads // true' .loa.config.yaml)
     if [[ "$beads_required" == "true" ]]; then
       echo "HALT: Autonomous mode requires beads (status: $status)"
       echo ""
       echo "Beads provides:"
       echo "  - Task state persistence across context windows"
       echo "  - Progress tracking for overnight/unattended execution"
       echo "  - Recovery from interruptions"
       echo ""
       echo "To fix:"
       echo "  cargo install beads_rust && br init"
       echo ""
       echo "To override (not recommended):"
       echo "  Set beads.autonomous.requires_beads: false in .loa.config.yaml"
       echo "  Or: export LOA_BEADS_AUTONOMOUS_OVERRIDE=true"
       exit 1
     fi
   fi

   # Update health state
   .claude/scripts/beads/update-beads-state.sh --health "$status"
   ```

3. **Branch Safety Check**
   ```bash
   # Verify not on protected branch using ICE
   .claude/scripts/run-mode-ice.sh validate
   ```

4. **Permission Check**
   ```bash
   # Verify all required permissions configured
   .claude/scripts/check-permissions.sh --quiet
   ```

5. **State Check**
   ```bash
   # Check for conflicting .run/ state
   if [[ -f .run/state.json ]]; then
     current_state=$(jq -r '.state' .run/state.json)
     if [[ "$current_state" == "RUNNING" ]]; then
       echo "ERROR: Run already in progress. Use /run-halt or /run-resume"
       exit 1
     fi
   fi
   ```

## Execution Flow

### State Machine

```
READY → JACK_IN → RUNNING → COMPLETE/HALTED → JACKED_OUT
```

### Main Loop

```
initialize_state()
while circuit_breaker.state == CLOSED:
  1. /implement $target
  2. commit_changes()
  3. track_deleted_files()
  4. update_state(phase: REVIEW)

  5. /review-sprint $target
  6. if has_findings(engineer-feedback.md):
       record_cycle(findings)
       check_circuit_breaker()
       continue  # Loop back to implement

  7. update_state(phase: AUDIT)
  8. /audit-sprint $target
  9. if has_findings(auditor-sprint-feedback.md):
       record_cycle(findings)
       check_circuit_breaker()
       continue  # Loop back to implement

  10. if COMPLETED marker exists:
        update_state(state: COMPLETE)
        break

create_draft_pr()
update_state(state: JACKED_OUT)
```

## State Management

### State File Structure

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
      {"cycle": 1, "phase": "IMPLEMENT", "findings": 5, "files_changed": 10},
      {"cycle": 2, "phase": "REVIEW", "findings": 2, "files_changed": 3}
    ]
  },
  "metrics": {
    "files_changed": 15,
    "files_deleted": 2,
    "commits": 3,
    "findings_fixed": 7
  },
  "options": {
    "max_cycles": 20,
    "timeout_hours": 8,
    "dry_run": false,
    "local_mode": false,
    "confirm_push": false,
    "push_mode": "AUTO"
  },
  "completion": {
    "pushed": false,
    "pr_created": false,
    "pr_url": null,
    "skipped_reason": null
  }
}
```

### Push Mode Options (v1.30.0)

| Field | Type | Description |
|-------|------|-------------|
| `options.local_mode` | boolean | True if `--local` flag was used |
| `options.confirm_push` | boolean | True if `--confirm-push` flag was used |
| `options.push_mode` | string | Resolved mode: `LOCAL`, `PROMPT`, or `AUTO` |
| `completion.pushed` | boolean | Whether commits were pushed to remote |
| `completion.pr_created` | boolean | Whether PR was created |
| `completion.pr_url` | string\|null | PR URL if created, null otherwise |
| `completion.skipped_reason` | string\|null | Why push was skipped (e.g., `local_mode`, `user_declined`) |

### Atomic State Updates

```bash
# Write to temp file first
state_update() {
  local temp_file=".run/state.json.tmp"
  local state_file=".run/state.json"

  # Update state with jq
  jq "$1" "$state_file" > "$temp_file"

  # Atomic rename
  mv "$temp_file" "$state_file"
}
```

## Circuit Breaker

### Circuit Breaker File

File: `.run/circuit-breaker.json`

```json
{
  "state": "CLOSED",
  "triggers": {
    "same_issue": {
      "count": 0,
      "threshold": 3,
      "last_hash": null
    },
    "no_progress": {
      "count": 0,
      "threshold": 5
    },
    "cycle_count": {
      "current": 3,
      "limit": 20
    },
    "timeout": {
      "started": "2026-01-19T10:00:00Z",
      "limit_hours": 8
    }
  },
  "history": []
}
```

### Trigger Checks

```bash
check_circuit_breaker() {
  local cb_file=".run/circuit-breaker.json"

  # Check same issue threshold
  local same_count=$(jq '.triggers.same_issue.count' "$cb_file")
  local same_threshold=$(jq '.triggers.same_issue.threshold' "$cb_file")
  if [[ $same_count -ge $same_threshold ]]; then
    trip_breaker "same_issue" "Same finding repeated $same_count times"
    return 1
  fi

  # Check no progress threshold
  local no_progress=$(jq '.triggers.no_progress.count' "$cb_file")
  local no_progress_threshold=$(jq '.triggers.no_progress.threshold' "$cb_file")
  if [[ $no_progress -ge $no_progress_threshold ]]; then
    trip_breaker "no_progress" "No file changes for $no_progress cycles"
    return 1
  fi

  # Check cycle limit
  local current_cycle=$(jq '.triggers.cycle_count.current' "$cb_file")
  local cycle_limit=$(jq '.triggers.cycle_count.limit' "$cb_file")
  if [[ $current_cycle -ge $cycle_limit ]]; then
    trip_breaker "cycle_limit" "Maximum cycles ($cycle_limit) exceeded"
    return 1
  fi

  # Check timeout
  local started=$(jq -r '.triggers.timeout.started' "$cb_file")
  local limit_hours=$(jq '.triggers.timeout.limit_hours' "$cb_file")
  local elapsed_seconds=$(($(date +%s) - $(date -d "$started" +%s)))
  local limit_seconds=$((limit_hours * 3600))
  if [[ $elapsed_seconds -ge $limit_seconds ]]; then
    trip_breaker "timeout" "Timeout exceeded (${limit_hours}h)"
    return 1
  fi

  return 0
}

trip_breaker() {
  local trigger="$1"
  local reason="$2"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Update circuit breaker state
  jq --arg t "$trigger" --arg r "$reason" --arg ts "$timestamp" '
    .state = "OPEN" |
    .history += [{"timestamp": $ts, "trigger": $t, "reason": $r}]
  ' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json

  # Update run state
  jq '.state = "HALTED"' .run/state.json > .run/state.json.tmp
  mv .run/state.json.tmp .run/state.json

  echo "CIRCUIT BREAKER TRIPPED: $reason"
  echo "Run halted. Use /run-resume --reset-ice to continue."
}
```

### Issue Hash Tracking

```bash
# Generate hash of findings for comparison
hash_findings() {
  local feedback_file="$1"
  if [[ -f "$feedback_file" ]]; then
    # Extract finding sections and hash them
    grep -A 100 "## Findings\|## Issues\|## Changes Required" "$feedback_file" | \
      head -50 | md5sum | cut -d' ' -f1
  else
    echo "none"
  fi
}

check_same_issue() {
  local new_hash="$1"
  local cb_file=".run/circuit-breaker.json"
  local last_hash=$(jq -r '.triggers.same_issue.last_hash // "none"' "$cb_file")

  if [[ "$new_hash" == "$last_hash" && "$new_hash" != "none" ]]; then
    # Same issue detected
    jq '.triggers.same_issue.count += 1' "$cb_file" > "$cb_file.tmp"
    mv "$cb_file.tmp" "$cb_file"
  else
    # New issue, reset counter
    jq --arg h "$new_hash" '
      .triggers.same_issue.count = 1 |
      .triggers.same_issue.last_hash = $h
    ' "$cb_file" > "$cb_file.tmp"
    mv "$cb_file.tmp" "$cb_file"
  fi
}
```

## Deleted Files Tracking

### Log File

File: `.run/deleted-files.log`

Format: `file_path|sprint|cycle`

### Collection

```bash
track_deleted_files() {
  local sprint="$1"
  local cycle="$2"

  # Get deleted files from last commit
  git diff --name-status HEAD~1 HEAD 2>/dev/null | \
    grep "^D" | \
    cut -f2 | \
    while read -r file; do
      echo "$file|$sprint|$cycle" >> .run/deleted-files.log
    done
}
```

### Tree View Generator

```bash
generate_deleted_tree() {
  local log_file=".run/deleted-files.log"

  if [[ ! -f "$log_file" || ! -s "$log_file" ]]; then
    echo "No files deleted during this run."
    return
  fi

  local count=$(wc -l < "$log_file")

  echo "## 🗑️ DELETED FILES - REVIEW CAREFULLY"
  echo ""
  echo "**Total: $count files deleted**"
  echo ""
  echo '```'

  # Generate tree-like output
  cut -d'|' -f1 "$log_file" | sort | while read -r file; do
    local dir=$(dirname "$file")
    local base=$(basename "$file")
    local meta=$(grep "^$file|" "$log_file" | cut -d'|' -f2,3 | tr '|' ', ')
    echo "$dir/"
    echo "└── $base ($meta)"
  done

  echo '```'
  echo ""
  echo "> ⚠️ These deletions are intentional but please verify they are correct."
}
```

## Completion and PR Creation (v1.30.0)

### Push Mode Resolution

The completion flow respects user preferences for push behavior:

```bash
# Resolve push mode from flags and config
# Priority: --local > --confirm-push > config > default (AUTO)
# Delegates entirely to ICE as single source of truth for push decisions
resolve_push_mode() {
  if [[ "${LOCAL_FLAG:-false}" == "true" ]]; then
    .claude/scripts/run-mode-ice.sh should-push local
  elif [[ "${CONFIRM_PUSH_FLAG:-false}" == "true" ]]; then
    .claude/scripts/run-mode-ice.sh should-push prompt
  else
    .claude/scripts/run-mode-ice.sh should-push
  fi
}
```

### Completion Flow

```bash
complete_run() {
  local target="$1"
  local push_mode

  # Determine push mode
  push_mode=$(resolve_push_mode)

  # Update state with resolved mode
  jq --arg mode "$push_mode" '.options.push_mode = $mode' .run/state.json > .run/state.json.tmp
  mv .run/state.json.tmp .run/state.json

  case "$push_mode" in
    LOCAL)
      complete_local "$target"
      ;;
    PROMPT)
      confirm_and_complete "$target"
      ;;
    AUTO)
      push_and_create_pr "$target"
      ;;
  esac
}
```

### Local Mode Completion

```bash
complete_local() {
  local target="$1"
  local branch=$(jq -r '.branch' .run/state.json)
  local commits=$(jq '.metrics.commits' .run/state.json)
  local files=$(jq '.metrics.files_changed' .run/state.json)

  # Update completion + run state atomically
  jq '.completion = {
    "pushed": false,
    "pr_created": false,
    "pr_url": null,
    "skipped_reason": "local_mode"
  } | .state = "JACKED_OUT"' .run/state.json > .run/state.json.tmp
  mv .run/state.json.tmp .run/state.json

  cat << EOF
[COMPLETE] Sprint implementation finished (LOCAL MODE)

Changes committed to local branch: $branch
Total commits: $commits
Files changed: $files

⚠️  LOCAL MODE: No push or PR created.

To push manually when ready:
  git push -u origin $branch

To create PR:
  gh pr create --draft
EOF
}
```

### Confirmation Prompt (PROMPT Mode)

When push mode is PROMPT, use AskUserQuestion before pushing:

```bash
confirm_and_complete() {
  local target="$1"
  local branch=$(jq -r '.branch' .run/state.json)
  local commits=$(jq '.metrics.commits' .run/state.json)
  local files=$(jq '.metrics.files_changed' .run/state.json)

  # Display summary and use AskUserQuestion tool
  # Options:
  #   1. "Push and create PR" - proceeds with push_and_create_pr()
  #   2. "Keep local only" - calls complete_declined()
  #
  # The AskUserQuestion tool is invoked by Claude, not bash
}

complete_declined() {
  local target="$1"
  local branch=$(jq -r '.branch' .run/state.json)
  local commits=$(jq '.metrics.commits' .run/state.json)
  local files=$(jq '.metrics.files_changed' .run/state.json)

  # Update completion + run state atomically
  jq '.completion = {
    "pushed": false,
    "pr_created": false,
    "pr_url": null,
    "skipped_reason": "user_declined"
  } | .state = "JACKED_OUT"' .run/state.json > .run/state.json.tmp
  mv .run/state.json.tmp .run/state.json

  cat << EOF
[COMPLETE] Sprint implementation finished

Changes committed to local branch: $branch
Total commits: $commits
Files changed: $files

ℹ️  Push skipped at your request.

To push when ready:
  git push -u origin $branch

To create PR:
  gh pr create --draft
EOF
}
```

### Push and Create PR (AUTO Mode)

```bash
push_and_create_pr() {
  local target="$1"
  local branch=$(jq -r '.branch' .run/state.json)
  local metrics=$(jq '.metrics' .run/state.json)
  local cycles=$(jq '.cycles.current' .run/state.json)

  # Push using ICE wrapper
  .claude/scripts/run-mode-ice.sh push origin "$branch"

  # Generate PR body
  local body="## Run Mode Autonomous Implementation

### Summary
- **Target:** $target
- **Cycles:** $cycles
- **Files Changed:** $(echo "$metrics" | jq '.files_changed')
- **Commits:** $(echo "$metrics" | jq '.commits')
- **Findings Fixed:** $(echo "$metrics" | jq '.findings_fixed')

$(generate_deleted_tree)

### Test Results
All tests passing (verified by /audit-sprint).

---
🤖 Generated autonomously with Run Mode
"

  # Create draft PR using ICE wrapper
  local pr_url
  pr_url=$(.claude/scripts/run-mode-ice.sh pr-create \
    "Run Mode: $target implementation" \
    "$body")

  # Update completion + run state atomically
  jq --arg url "$pr_url" '.completion = {
    "pushed": true,
    "pr_created": true,
    "pr_url": $url,
    "skipped_reason": null
  } | .state = "JACKED_OUT"' .run/state.json > .run/state.json.tmp
  mv .run/state.json.tmp .run/state.json

  echo "[COMPLETE] All checks passed!"
  echo "✓ PR created: $pr_url"
  echo ""
  echo "[JACKED_OUT] Run complete."
}
```

## Initialization

### Directory Setup

```bash
initialize_run() {
  local target="$1"
  local branch="${2:-feature/$target}"
  local max_cycles="${3:-20}"
  local timeout_hours="${4:-8}"
  local local_mode="${5:-false}"
  local confirm_push="${6:-false}"

  # Create .run directory
  mkdir -p .run

  # Generate run ID
  local run_id="run-$(date +%Y%m%d)-$(openssl rand -hex 4)"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Resolve initial push mode via ICE (single source of truth)
  local push_mode
  if [[ "$local_mode" == "true" ]]; then
    push_mode=$(.claude/scripts/run-mode-ice.sh should-push local)
  elif [[ "$confirm_push" == "true" ]]; then
    push_mode=$(.claude/scripts/run-mode-ice.sh should-push prompt)
  else
    push_mode=$(.claude/scripts/run-mode-ice.sh should-push)
  fi

  # Initialize state.json
  cat > .run/state.json << EOF
{
  "run_id": "$run_id",
  "target": "$target",
  "branch": "$branch",
  "state": "JACK_IN",
  "phase": "INIT",
  "timestamps": {
    "started": "$timestamp",
    "last_activity": "$timestamp"
  },
  "cycles": {
    "current": 0,
    "limit": $max_cycles,
    "history": []
  },
  "metrics": {
    "files_changed": 0,
    "files_deleted": 0,
    "commits": 0,
    "findings_fixed": 0
  },
  "options": {
    "max_cycles": $max_cycles,
    "timeout_hours": $timeout_hours,
    "dry_run": false,
    "local_mode": $local_mode,
    "confirm_push": $confirm_push,
    "push_mode": "$push_mode"
  },
  "completion": {
    "pushed": false,
    "pr_created": false,
    "pr_url": null,
    "skipped_reason": null
  }
}
EOF

  # Initialize circuit-breaker.json
  cat > .run/circuit-breaker.json << EOF
{
  "state": "CLOSED",
  "triggers": {
    "same_issue": {
      "count": 0,
      "threshold": 3,
      "last_hash": null
    },
    "no_progress": {
      "count": 0,
      "threshold": 5
    },
    "cycle_count": {
      "current": 0,
      "limit": $max_cycles
    },
    "timeout": {
      "started": "$timestamp",
      "limit_hours": $timeout_hours
    }
  },
  "history": []
}
EOF

  # Initialize empty deleted files log
  touch .run/deleted-files.log

  # Create/checkout feature branch
  .claude/scripts/run-mode-ice.sh ensure-branch "$target"
}
```

## Output

On successful completion:
- Draft PR created on feature branch
- `.run/state.json` shows state: `JACKED_OUT`
- PR URL displayed to user

On circuit breaker trip:
- Run halted
- `.run/state.json` shows state: `HALTED`
- `.run/circuit-breaker.json` shows state: `OPEN` with trigger reason
- Instructions for resume displayed

## Example Session

```
> /run sprint-1 --max-cycles 10

[JACK_IN] Pre-flight checks...
✓ run_mode.enabled = true
✓ Not on protected branch
✓ All permissions configured
✓ No conflicting state

[INIT] Creating feature branch...
✓ Checked out feature/sprint-1

[RUNNING] Starting cycle 1...
→ Phase: IMPLEMENT
  Executing /implement sprint-1...
  ✓ Implementation complete
  ✓ 5 files changed, 0 deleted
  ✓ Committed: abc1234

→ Phase: REVIEW
  Executing /review-sprint sprint-1...
  ⚠ Findings: 3 issues identified

[RUNNING] Starting cycle 2...
→ Phase: IMPLEMENT
  Addressing review feedback...
  ✓ 3 issues fixed
  ✓ Committed: def5678

→ Phase: REVIEW
  Executing /review-sprint sprint-1...
  ✓ All good

→ Phase: AUDIT
  Executing /audit-sprint sprint-1...
  ✓ APPROVED - LET'S FUCKING GO

[COMPLETE] All checks passed!
Creating draft PR...
✓ PR #42 created: https://github.com/org/repo/pull/42

[JACKED_OUT] Run complete.
Total cycles: 2
Files changed: 8
Findings fixed: 3
```

## Related

- `/run-status` - Check current run progress
- `/run-halt` - Gracefully stop execution
- `/run-resume` - Continue from checkpoint
- `/run sprint-plan` - Execute all sprints

## Rate Limiting

### Rate Limit File

File: `.run/rate-limit.json`

```json
{
  "hour_boundary": "2026-01-19T10:00:00Z",
  "calls_this_hour": 45,
  "limit": 100,
  "waits": []
}
```

### Rate Limit Logic

```bash
check_rate_limit() {
  local rate_file=".run/rate-limit.json"
  local config_limit=$(yq '.run_mode.rate_limiting.calls_per_hour // 100' .loa.config.yaml)

  # Initialize if missing
  if [[ ! -f "$rate_file" ]]; then
    init_rate_limit "$config_limit"
  fi

  # Get current hour boundary
  local current_hour=$(date -u +"%Y-%m-%dT%H:00:00Z")
  local stored_hour=$(jq -r '.hour_boundary' "$rate_file")

  # Reset if new hour
  if [[ "$current_hour" != "$stored_hour" ]]; then
    reset_rate_limit "$current_hour" "$config_limit"
  fi

  # Check if limit reached
  local calls=$(jq '.calls_this_hour' "$rate_file")
  local limit=$(jq '.limit' "$rate_file")

  if [[ $calls -ge $limit ]]; then
    wait_for_next_hour
    return
  fi

  # Increment counter
  jq '.calls_this_hour += 1' "$rate_file" > "$rate_file.tmp"
  mv "$rate_file.tmp" "$rate_file"
}

init_rate_limit() {
  local limit="$1"
  local current_hour=$(date -u +"%Y-%m-%dT%H:00:00Z")

  cat > .run/rate-limit.json << EOF
{
  "hour_boundary": "$current_hour",
  "calls_this_hour": 0,
  "limit": $limit,
  "waits": []
}
EOF
}

reset_rate_limit() {
  local new_hour="$1"
  local limit="$2"

  jq --arg h "$new_hour" --argjson l "$limit" '
    .hour_boundary = $h |
    .calls_this_hour = 0 |
    .limit = $l
  ' .run/rate-limit.json > .run/rate-limit.json.tmp
  mv .run/rate-limit.json.tmp .run/rate-limit.json
}

wait_for_next_hour() {
  local rate_file=".run/rate-limit.json"
  local current_hour=$(jq -r '.hour_boundary' "$rate_file")

  # Calculate seconds until next hour
  local current_seconds=$(date +%s)
  local hour_start=$(date -d "$current_hour" +%s)
  local next_hour=$((hour_start + 3600))
  local wait_seconds=$((next_hour - current_seconds + 60))  # Add 60s buffer

  echo "Rate limit reached ($calls/$limit calls this hour)"
  echo "Waiting until next hour boundary..."

  # Record wait
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg ts "$timestamp" --argjson w "$wait_seconds" '
    .waits += [{"timestamp": $ts, "wait_seconds": $w}]
  ' "$rate_file" > "$rate_file.tmp"
  mv "$rate_file.tmp" "$rate_file"

  # Update state to show waiting
  jq '.phase = "RATE_LIMITED"' .run/state.json > .run/state.json.tmp
  mv .run/state.json.tmp .run/state.json

  # Sleep (in real implementation, Claude would wait)
  echo "Estimated wait: $((wait_seconds / 60)) minutes"
  echo "Run will auto-resume when limit resets."
}
```

### 5-Hour Limit Handling

For extended runs that may hit the 5-hour conversation limit:

```bash
handle_extended_wait() {
  local wait_seconds="$1"

  if [[ $wait_seconds -gt 3600 ]]; then
    echo ""
    echo "WARNING: Long wait detected ($(($wait_seconds / 60)) minutes)"
    echo ""
    echo "The run will be automatically suspended."
    echo "State is preserved in .run/"
    echo ""
    echo "After the rate limit resets, resume with:"
    echo "  /run-resume"
  fi
}
```

### Rate Limit in Main Loop

The rate limit check is called before each phase:

```
while circuit_breaker.state == CLOSED:
  check_rate_limit()  # Wait if needed

  1. /implement $target
  check_rate_limit()

  2. /review-sprint $target
  check_rate_limit()

  3. /audit-sprint $target
  ...
```

## Configuration

```yaml
# .loa.config.yaml
run_mode:
  enabled: true  # Required to use /run
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
