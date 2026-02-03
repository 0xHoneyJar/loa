# /run sprint-plan Command

## Purpose

Execute all sprints in sequence for complete release cycles. Autonomous implementation of an entire sprint plan with a **single consolidated PR** at the end (v1.15.1).

## Usage

```
/run sprint-plan                      # Consolidated PR at end (default, recommended)
/run sprint-plan --from 2
/run sprint-plan --from 2 --to 4
/run sprint-plan --max-cycles 15 --timeout 12
/run sprint-plan --no-consolidate     # Legacy: separate PR per sprint
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
| `--no-consolidate` | Create separate PR per sprint (legacy) | false |

## Consolidated PR (Default - v1.15.1)

By default, `/run sprint-plan` creates a **single consolidated PR** after all sprints complete:

- All sprints execute on the same feature branch
- Each sprint's work is committed with clear sprint markers (e.g., `feat(sprint-1): ...`)
- A single draft PR is created at the end containing all changes
- PR summary includes per-sprint breakdown table
- Commits are grouped by sprint in the PR description

**Benefits**:
- Easier to review (single PR instead of scattered sprints)
- Clean git history with sprint markers
- Comprehensive overview of all changes
- Matches how Loa handles release PRs

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

### Flatline Review Summary (v1.22.0)

$(generate_flatline_summary)

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

### Consolidated PR Format (Default - v1.15.1)

```bash
create_plan_pr() {
  # 1. Clean context directory for next cycle
  cleanup_context_directory

  local body="## 🚀 Run Mode: Sprint Plan Complete

### Summary

| Metric | Value |
|--------|-------|
| **Sprints Completed** | $(jq '.sprints.completed' .run/sprint-plan-state.json) |
| **Total Cycles** | $(jq '.metrics.total_cycles' .run/sprint-plan-state.json) |
| **Files Changed** | $(jq '.metrics.total_files_changed' .run/sprint-plan-state.json) |
| **Findings Fixed** | $(jq '.metrics.total_findings_fixed' .run/sprint-plan-state.json) |

### Sprint Breakdown

| Sprint | Status | Cycles | Files Changed |
|--------|--------|--------|---------------|
$(generate_sprint_table)

$(generate_deleted_tree)

### Commits by Sprint

$(generate_commits_by_sprint)

### Flatline Review Summary (v1.22.0)

$(generate_flatline_summary)

### Test Results
All tests passing (verified by /audit-sprint for each sprint).

### Context Cleanup
Discovery context cleaned and ready for next cycle.

---
🤖 Generated autonomously with Run Mode
"

  .claude/scripts/run-mode-ice.sh pr-create \
    "Run Mode: Sprint Plan implementation" \
    "\$body" \
    --draft
}
```

### Commits by Sprint Section

The consolidated PR groups commits by sprint for easy review:

```markdown
#### Sprint 1: User Authentication
- `abc1234` feat(sprint-1): implement login endpoint
- `def5678` feat(sprint-1): add JWT token generation
- `ghi9012` fix(sprint-1): address review feedback

#### Sprint 2: Dashboard
- `jkl3456` feat(sprint-2): create dashboard layout
- `mno7890` feat(sprint-2): add widgets
...
```

### Sprint Table Generation

```bash
generate_sprint_table() {
  jq -r '.sprints.list[] |
    "| \(.id) | \(if .status == "completed" then "✅ Complete" else "⏳ \(.status)" end) | \(.cycles) | \(.files_changed // "-") |"
  ' .run/sprint-plan-state.json
}

generate_commits_by_sprint() {
  for sprint in $(jq -r '.sprints.list[].id' .run/sprint-plan-state.json); do
    local title=$(get_sprint_title "$sprint")
    echo "#### $sprint: $title"
    echo ""
    git log --oneline --grep="($sprint)" | while read -r line; do
      echo "- \`${line%% *}\` ${line#* }"
    done
    echo ""
  done
}

generate_flatline_summary() {
  # Aggregate Flatline results from all phases
  local flatline_dir=".flatline/runs"
  local plan_id=$(jq -r '.plan_id' .run/sprint-plan-state.json)

  if [[ ! -d "$flatline_dir" ]]; then
    echo "_No Flatline reviews executed during this run._"
    return
  fi

  # Find all run manifests from this sprint plan
  local manifests=$(find "$flatline_dir" -name "*.json" -newer .run/sprint-plan-state.json 2>/dev/null)

  if [[ -z "$manifests" ]]; then
    echo "_No Flatline reviews executed during this run._"
    return
  fi

  # Aggregate metrics
  local total_high=0
  local total_disputed=0
  local total_blockers=0
  local phases_reviewed=""

  for manifest in $manifests; do
    local phase=$(jq -r '.phase // "unknown"' "$manifest")
    local high=$(jq -r '.metrics.high_consensus // 0' "$manifest")
    local disputed=$(jq -r '.metrics.disputed // 0' "$manifest")
    local blockers=$(jq -r '.metrics.blockers // 0' "$manifest")
    local status=$(jq -r '.status // "unknown"' "$manifest")

    total_high=$((total_high + high))
    total_disputed=$((total_disputed + disputed))
    total_blockers=$((total_blockers + blockers))

    phases_reviewed="${phases_reviewed}| ${phase^^} | $high | $disputed | $blockers | $(echo $status | sed 's/completed/✅/; s/escalated/⚠️/') |\n"
  done

  # Output summary table
  echo "| Phase | HIGH | DISPUTED | BLOCKER | Status |"
  echo "|-------|------|----------|---------|--------|"
  echo -e "$phases_reviewed"
  echo ""
  echo "**Totals:** $total_high integrated, $total_disputed disputed (logged), $total_blockers blockers"

  # List disputed items for post-review if any
  if [[ $total_disputed -gt 0 ]]; then
    echo ""
    echo "<details>"
    echo "<summary>Disputed items for post-review ($total_disputed)</summary>"
    echo ""
    for manifest in $manifests; do
      local run_id=$(jq -r '.run_id' "$manifest")
      local disputed_file=".flatline/runs/${run_id}-disputed.json"
      if [[ -f "$disputed_file" ]]; then
        jq -r '.[] | "- **\(.id // "Item")**: \(.description // .text // "No description") (delta: \(.delta // "N/A"))"' "$disputed_file" 2>/dev/null
      fi
    done
    echo ""
    echo "</details>"
  fi

  # Add rollback command if integrations were made
  if [[ $total_high -gt 0 ]]; then
    echo ""
    echo "**Rollback:** To revert Flatline integrations:"
    echo "\`\`\`bash"
    echo ".claude/scripts/flatline-rollback.sh run --run-id <run_id> --dry-run"
    echo "\`\`\`"
  fi
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
    # Consolidated PR behavior (v1.15.1)
    consolidate_pr: true           # Create single PR for all sprints (default)
    commit_prefix: "feat"          # Prefix for sprint commits
    include_commits_by_sprint: true  # Group commits by sprint in PR
```
