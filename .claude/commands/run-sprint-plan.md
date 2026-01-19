# /run sprint-plan Command

## Purpose

Execute all sprints in sequence for complete release cycles. Autonomous implementation of an entire sprint plan.

## Usage

```
/run sprint-plan
/run sprint-plan --from 2
/run sprint-plan --from 2 --to 4
/run sprint-plan --max-cycles 15 --timeout 12
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--from N` | Start from sprint N | 1 |
| `--to N` | End at sprint N | Last sprint |
| `--max-cycles N` | Maximum cycles per sprint | 20 |
| `--timeout H` | Maximum runtime in hours | 8 |
| `--branch NAME` | Feature branch name | `feature/release` |
| `--dry-run` | Validate but don't execute | false |

## Sprint Discovery

The command discovers sprints in priority order:

### Priority 1: sprint.md Sections

```bash
discover_from_sprint_md() {
  local sprint_file="grimoires/loa/sprint.md"

  if [[ ! -f "$sprint_file" ]]; then
    return 1
  fi

  # Extract sprint sections: ## Sprint N: Title
  grep -E "^## Sprint [0-9]+:" "$sprint_file" | \
    sed 's/## Sprint \([0-9]*\):.*/sprint-\1/' | \
    sort -t'-' -k2 -n
}
```

### Priority 2: ledger.json Sprints

```bash
discover_from_ledger() {
  local ledger="grimoires/loa/ledger.json"

  if [[ ! -f "$ledger" ]]; then
    return 1
  fi

  # Get active cycle's sprints
  local active_cycle=$(jq -r '.active_cycle' "$ledger")

  jq -r --arg cycle "$active_cycle" '
    .cycles[] |
    select(.id == $cycle) |
    .sprints[] |
    .local_label
  ' "$ledger"
}
```

### Priority 3: a2a Directories

```bash
discover_from_directories() {
  # Find existing sprint directories
  find grimoires/loa/a2a -maxdepth 1 -type d -name "sprint-*" | \
    sed 's|.*/||' | \
    sort -t'-' -k2 -n
}
```

### Discovery Function

```bash
discover_sprints() {
  local sprints=""

  # Try each source in priority order
  sprints=$(discover_from_sprint_md)
  if [[ -z "$sprints" ]]; then
    sprints=$(discover_from_ledger)
  fi
  if [[ -z "$sprints" ]]; then
    sprints=$(discover_from_directories)
  fi

  if [[ -z "$sprints" ]]; then
    echo "ERROR: No sprints found"
    exit 1
  fi

  echo "$sprints"
}
```

## Pre-flight Checks

Before execution begins:

```bash
preflight_sprint_plan() {
  # 1. Same as /run pre-flight
  if ! yq '.run_mode.enabled // false' .loa.config.yaml | grep -q true; then
    echo "ERROR: Run Mode not enabled"
    exit 1
  fi

  .claude/scripts/run-mode-ice.sh validate
  .claude/scripts/check-permissions.sh --quiet

  # 2. Check for conflicting state
  if [[ -f .run/state.json ]]; then
    local current_state=$(jq -r '.state' .run/state.json)
    if [[ "$current_state" == "RUNNING" ]]; then
      echo "ERROR: Run already in progress"
      exit 1
    fi
  fi

  # 3. Verify sprints exist
  local sprints=$(discover_sprints)
  if [[ -z "$sprints" ]]; then
    echo "ERROR: No sprints discovered"
    exit 1
  fi

  echo "Discovered sprints:"
  echo "$sprints"
}
```

## Execution Flow

### Main Loop

```
initialize_sprint_plan_state()

for sprint in filtered_sprints:
  1. Check if sprint already COMPLETED
     - If COMPLETED: skip
     - If not: proceed

  2. /run $sprint --max-cycles $max_cycles --timeout $sprint_timeout

  3. Check run result:
     - If COMPLETE: continue to next sprint
     - If HALTED: halt entire plan, preserve state

  4. Update sprint plan state

create_plan_pr()
update_state(state: JACKED_OUT)
```

### State File Structure

File: `.run/sprint-plan-state.json`

```json
{
  "plan_id": "plan-20260119-abc123",
  "branch": "feature/release",
  "state": "RUNNING",
  "timestamps": {
    "started": "2026-01-19T10:00:00Z",
    "last_activity": "2026-01-19T14:30:00Z"
  },
  "sprints": {
    "total": 4,
    "completed": 2,
    "current": "sprint-3",
    "list": [
      {"id": "sprint-1", "status": "completed", "cycles": 2},
      {"id": "sprint-2", "status": "completed", "cycles": 3},
      {"id": "sprint-3", "status": "in_progress", "cycles": 1},
      {"id": "sprint-4", "status": "pending"}
    ]
  },
  "options": {
    "from": 1,
    "to": 4,
    "max_cycles": 20,
    "timeout_hours": 8
  },
  "metrics": {
    "total_cycles": 6,
    "total_files_changed": 45,
    "total_findings_fixed": 12
  }
}
```

## Sprint Filtering

### --from and --to Options

```bash
filter_sprints() {
  local all_sprints="$1"
  local from="${2:-1}"
  local to="${3:-999}"

  echo "$all_sprints" | while read -r sprint; do
    # Extract sprint number
    local num=$(echo "$sprint" | sed 's/sprint-//')

    if [[ $num -ge $from && $num -le $to ]]; then
      echo "$sprint"
    fi
  done
}
```

## Failure Handling

### On Sprint Failure

```bash
handle_sprint_failure() {
  local failed_sprint="$1"
  local reason="$2"

  # Update sprint plan state
  jq --arg s "$failed_sprint" --arg r "$reason" '
    .state = "HALTED" |
    .failure = {
      "sprint": $s,
      "reason": $r,
      "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
    }
  ' .run/sprint-plan-state.json > .run/sprint-plan-state.json.tmp
  mv .run/sprint-plan-state.json.tmp .run/sprint-plan-state.json

  # Create draft PR marked INCOMPLETE
  create_incomplete_pr "$failed_sprint" "$reason"

  echo "Sprint plan halted at $failed_sprint"
  echo "Reason: $reason"
  echo "Use /run-resume to continue from this point"
}
```

### Incomplete PR

```bash
create_incomplete_pr() {
  local failed_sprint="$1"
  local reason="$2"

  local body="## Run Mode Sprint Plan - INCOMPLETE

### Status: HALTED

Sprint plan execution stopped at **$failed_sprint**.

**Reason:** $reason

### Completed Sprints
$(list_completed_sprints)

### Remaining Sprints
$(list_remaining_sprints)

### Metrics
- Total cycles: $(jq '.metrics.total_cycles' .run/sprint-plan-state.json)
- Files changed: $(jq '.metrics.total_files_changed' .run/sprint-plan-state.json)
- Findings fixed: $(jq '.metrics.total_findings_fixed' .run/sprint-plan-state.json)

$(generate_deleted_tree)

---
:warning: **INCOMPLETE** - Use \`/run-resume\` to continue

:robot: Generated autonomously with Run Mode
"

  .claude/scripts/run-mode-ice.sh pr-create \
    "[INCOMPLETE] Run Mode: Sprint Plan" \
    "$body" \
    --draft
}
```

## Completion PR

### On Full Success

```bash
create_plan_pr() {
  # 1. Clean context directory for next cycle
  cleanup_context_directory

  local body="## Run Mode Sprint Plan - COMPLETE

### Summary
- **Sprints Completed:** $(jq '.sprints.completed' .run/sprint-plan-state.json)
- **Total Cycles:** $(jq '.metrics.total_cycles' .run/sprint-plan-state.json)
- **Files Changed:** $(jq '.metrics.total_files_changed' .run/sprint-plan-state.json)
- **Findings Fixed:** $(jq '.metrics.total_findings_fixed' .run/sprint-plan-state.json)

### Sprint Details
$(generate_sprint_summary)

$(generate_deleted_tree)

### Test Results
All tests passing (verified by /audit-sprint for each sprint).

### Context Cleanup
Discovery context cleaned and ready for next cycle.

---
:robot: Generated autonomously with Run Mode
"

  .claude/scripts/run-mode-ice.sh pr-create \
    "Run Mode: Sprint Plan implementation" \
    "$body" \
    --draft
}
```

### Context Cleanup

After all sprints complete, the discovery context is archived and cleaned to prepare for the next development cycle:

```bash
cleanup_context_directory() {
  # Use the cleanup-context.sh script (archives before cleaning)
  .claude/scripts/cleanup-context.sh --verbose
}
```

**Script**: `.claude/scripts/cleanup-context.sh`

The cleanup script:
1. **Archives** context files to `{archive-path}/context/`
2. **Removes** all files from `grimoires/loa/context/` except `README.md`
3. **Preserves** `README.md` that explains the directory purpose

**Archive Location Priority**:
1. Active cycle's archive_path from ledger.json
2. Most recent archived cycle's path
3. Most recent `grimoires/loa/archive/20*` directory
4. Fallback dated directory

**Manual Usage**:
```bash
# Preview what would be archived and cleaned
.claude/scripts/cleanup-context.sh --dry-run --verbose

# Archive and clean context directory
.claude/scripts/cleanup-context.sh

# Just delete without archiving (not recommended)
.claude/scripts/cleanup-context.sh --no-archive
```

## Output

On successful completion:
- Draft PR created with all sprint implementations
- `.run/sprint-plan-state.json` shows state: `JACKED_OUT`
- Summary of all sprints and metrics displayed

On halt:
- Draft PR created marked `[INCOMPLETE]`
- `.run/sprint-plan-state.json` shows state: `HALTED` with failure info
- Instructions for resume displayed

## Example Session

```
> /run sprint-plan --from 1 --to 4

[JACK_IN] Pre-flight checks...
✓ run_mode.enabled = true
✓ Not on protected branch
✓ All permissions configured

[DISCOVERY] Finding sprints...
✓ Found 4 sprints: sprint-1, sprint-2, sprint-3, sprint-4

[INIT] Creating feature branch...
✓ Checked out feature/release

[SPRINT 1/4] Running sprint-1...
→ Cycles: 2
→ Files: 8
→ Findings fixed: 3
✓ COMPLETED

[SPRINT 2/4] Running sprint-2...
→ Cycles: 3
→ Files: 12
→ Findings fixed: 5
✓ COMPLETED

[SPRINT 3/4] Running sprint-3...
→ Cycles: 1
→ Files: 6
→ Findings fixed: 0
✓ COMPLETED

[SPRINT 4/4] Running sprint-4...
→ Cycles: 2
→ Files: 10
→ Findings fixed: 2
✓ COMPLETED

[COMPLETE] All sprints passed!
Creating PR...
✓ PR #42 created: https://github.com/org/repo/pull/42

[JACKED_OUT] Sprint plan complete.
Total sprints: 4
Total cycles: 8
Total files changed: 36
Total findings fixed: 10
```

## Related

- `/run sprint-N` - Execute single sprint
- `/run-status` - Check current progress
- `/run-halt` - Stop execution
- `/run-resume` - Continue from halt

## Configuration

```yaml
# .loa.config.yaml
run_mode:
  enabled: true
  defaults:
    max_cycles: 20
    timeout_hours: 8
  sprint_plan:
    branch_prefix: "feature/"
    default_branch_name: "release"
```
