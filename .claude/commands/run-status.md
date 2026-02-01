# /run-status Command

## Purpose

Display current run state and progress. Shows run details, cycle progress, metrics, and circuit breaker status.

## Usage

```
/run-status
/run-status --json
/run-status --verbose
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--json` | Output as JSON | false |
| `--verbose` | Show detailed breakdown | false |

## Output

### Standard Output

```
╔══════════════════════════════════════════════════════════════╗
║                    RUN MODE STATUS                            ║
╠══════════════════════════════════════════════════════════════╣
║ Run ID:    run-20260119-abc123                                ║
║ State:     RUNNING                                            ║
║ Target:    sprint-3                                           ║
║ Branch:    feature/sprint-3                                   ║
╠══════════════════════════════════════════════════════════════╣
║ PROGRESS                                                      ║
║ ─────────────────────────────────────────────────────────────║
║ Cycle:     3 / 20                                             ║
║ Phase:     REVIEW                                             ║
║ Runtime:   1h 23m / 8h 00m                                    ║
╠══════════════════════════════════════════════════════════════╣
║ METRICS                                                       ║
║ ─────────────────────────────────────────────────────────────║
║ Files changed:   15                                           ║
║ Files deleted:   2                                            ║
║ Commits:         3                                            ║
║ Findings fixed:  7                                            ║
╠══════════════════════════════════════════════════════════════╣
║ CIRCUIT BREAKER: CLOSED                                       ║
║ ─────────────────────────────────────────────────────────────║
║ Same issue:      1/3                                          ║
║ No progress:     0/5                                          ║
║ Cycle count:     3/20                                         ║
║ Timeout:         1h 23m / 8h 00m                              ║
╚══════════════════════════════════════════════════════════════╝
```

## Implementation

### Check State Files

```bash
check_run_status() {
  local state_file=".run/state.json"
  local cb_file=".run/circuit-breaker.json"

  # Check if run is in progress
  if [[ ! -f "$state_file" ]]; then
    echo "No run in progress."
    echo ""
    echo "Start a new run with:"
    echo "  /run sprint-N"
    echo "  /run sprint-plan"
    return 0
  fi

  # Load state
  local run_id=$(jq -r '.run_id' "$state_file")
  local state=$(jq -r '.state' "$state_file")
  local target=$(jq -r '.target' "$state_file")
  local branch=$(jq -r '.branch' "$state_file")
  local phase=$(jq -r '.phase' "$state_file")

  # Calculate runtime
  local started=$(jq -r '.timestamps.started' "$state_file")
  local runtime=$(calculate_runtime "$started")

  # Load circuit breaker
  local cb_state=$(jq -r '.state' "$cb_file")
  local same_issue=$(jq '.triggers.same_issue.count' "$cb_file")
  local same_threshold=$(jq '.triggers.same_issue.threshold' "$cb_file")
  local no_progress=$(jq '.triggers.no_progress.count' "$cb_file")
  local no_progress_threshold=$(jq '.triggers.no_progress.threshold' "$cb_file")
  local current_cycle=$(jq '.cycles.current' "$state_file")
  local cycle_limit=$(jq '.cycles.limit' "$state_file")
  local timeout_hours=$(jq '.options.timeout_hours' "$state_file")

  # Load metrics
  local files_changed=$(jq '.metrics.files_changed' "$state_file")
  local files_deleted=$(jq '.metrics.files_deleted' "$state_file")
  local commits=$(jq '.metrics.commits' "$state_file")
  local findings_fixed=$(jq '.metrics.findings_fixed' "$state_file")

  # Display status
  display_status
}
```

### Calculate Runtime

```bash
calculate_runtime() {
  local started="$1"
  local started_seconds=$(date -d "$started" +%s)
  local now_seconds=$(date +%s)
  local elapsed=$((now_seconds - started_seconds))

  local hours=$((elapsed / 3600))
  local minutes=$(((elapsed % 3600) / 60))

  echo "${hours}h ${minutes}m"
}
```

### Format Timeout

```bash
format_timeout() {
  local hours="$1"
  echo "${hours}h 00m"
}
```

### Display Status

```bash
display_status() {
  local width=60

  # Header
  echo "$(box_top $width)"
  echo "$(box_center 'RUN MODE STATUS' $width)"
  echo "$(box_separator $width)"

  # Run info
  echo "$(box_line "Run ID:    $run_id" $width)"
  echo "$(box_line "State:     $state" $width)"
  echo "$(box_line "Target:    $target" $width)"
  echo "$(box_line "Branch:    $branch" $width)"

  echo "$(box_separator $width)"
  echo "$(box_center 'PROGRESS' $width)"
  echo "$(box_line_thin $width)"

  echo "$(box_line "Cycle:     $current_cycle / $cycle_limit" $width)"
  echo "$(box_line "Phase:     $phase" $width)"
  echo "$(box_line "Runtime:   $runtime / $(format_timeout $timeout_hours)" $width)"

  echo "$(box_separator $width)"
  echo "$(box_center 'METRICS' $width)"
  echo "$(box_line_thin $width)"

  echo "$(box_line "Files changed:   $files_changed" $width)"
  echo "$(box_line "Files deleted:   $files_deleted" $width)"
  echo "$(box_line "Commits:         $commits" $width)"
  echo "$(box_line "Findings fixed:  $findings_fixed" $width)"

  echo "$(box_separator $width)"
  echo "$(box_center "CIRCUIT BREAKER: $cb_state" $width)"
  echo "$(box_line_thin $width)"

  echo "$(box_line "Same issue:      $same_issue/$same_threshold" $width)"
  echo "$(box_line "No progress:     $no_progress/$no_progress_threshold" $width)"
  echo "$(box_line "Cycle count:     $current_cycle/$cycle_limit" $width)"
  echo "$(box_line "Timeout:         $runtime / $(format_timeout $timeout_hours)" $width)"

  echo "$(box_bottom $width)"
}
```

### JSON Output

```bash
output_json() {
  local state_file=".run/state.json"
  local cb_file=".run/circuit-breaker.json"

  if [[ ! -f "$state_file" ]]; then
    echo '{"status": "no_run_in_progress"}'
    return
  fi

  jq -s '
    {
      "run": .[0],
      "circuit_breaker": .[1],
      "computed": {
        "runtime_seconds": (now - (.[0].timestamps.started | fromdateiso8601)),
        "timeout_remaining_seconds": ((.[0].options.timeout_hours * 3600) - (now - (.[0].timestamps.started | fromdateiso8601)))
      }
    }
  ' "$state_file" "$cb_file"
}
```

### Verbose Output

```bash
output_verbose() {
  check_run_status

  if [[ -f ".run/state.json" ]]; then
    echo ""
    echo "=== Cycle History ==="
    jq -r '.cycles.history[] | "Cycle \(.cycle): \(.phase) - \(.findings) findings, \(.files_changed) files"' .run/state.json

    echo ""
    echo "=== Circuit Breaker History ==="
    if [[ -f ".run/circuit-breaker.json" ]]; then
      local history_count=$(jq '.history | length' .run/circuit-breaker.json)
      if [[ $history_count -gt 0 ]]; then
        jq -r '.history[] | "[\(.timestamp)] \(.trigger): \(.reason)"' .run/circuit-breaker.json
      else
        echo "No circuit breaker trips"
      fi
    fi

    echo ""
    echo "=== Deleted Files ==="
    if [[ -f ".run/deleted-files.log" && -s ".run/deleted-files.log" ]]; then
      cat .run/deleted-files.log
    else
      echo "No files deleted"
    fi
  fi
}
```

## No Run In Progress

When no run is active:

```
No run in progress.

Start a new run with:
  /run sprint-N
  /run sprint-plan
```

## Sprint Plan Status

When running a sprint plan, additional info is shown:

```
╔══════════════════════════════════════════════════════════════╗
║                 RUN MODE STATUS (Sprint Plan)                 ║
╠══════════════════════════════════════════════════════════════╣
║ Plan ID:   plan-20260119-abc123                               ║
║ State:     RUNNING                                            ║
║ Branch:    feature/release                                    ║
╠══════════════════════════════════════════════════════════════╣
║ SPRINT PROGRESS                                               ║
║ ─────────────────────────────────────────────────────────────║
║ [✓] sprint-1  (2 cycles)                                      ║
║ [✓] sprint-2  (3 cycles)                                      ║
║ [→] sprint-3  (cycle 1, REVIEW)                               ║
║ [ ] sprint-4                                                  ║
║                                                               ║
║ Progress: 2/4 sprints (50%)                                   ║
╠══════════════════════════════════════════════════════════════╣
║ TOTAL METRICS                                                 ║
║ ─────────────────────────────────────────────────────────────║
║ Total cycles:      6                                          ║
║ Files changed:     26                                         ║
║ Findings fixed:    8                                          ║
╚══════════════════════════════════════════════════════════════╝
```

## State Indicators

| State | Display | Meaning |
|-------|---------|---------|
| JACK_IN | Initializing | Pre-flight checks in progress |
| RUNNING | Running | Active execution |
| HALTED | HALTED | Circuit breaker tripped |
| COMPLETE | Complete | All checks passed |
| JACKED_OUT | Finished | PR created, run ended |

## Phase Indicators

| Phase | Display | Meaning |
|-------|---------|---------|
| INIT | Initializing | Setup in progress |
| IMPLEMENT | Implementing | Code implementation |
| REVIEW | In Review | Senior lead review |
| AUDIT | In Audit | Security audit |

## Circuit Breaker States

| State | Display | Meaning |
|-------|---------|---------|
| CLOSED | CLOSED | Normal operation |
| OPEN | OPEN | Halted, manual intervention needed |

## Example Usage

```bash
# Quick status check
/run-status

# Full details
/run-status --verbose

# For scripting
/run-status --json | jq '.run.state'
```

## Related

- `/run sprint-N` - Start a run
- `/run-halt` - Stop execution
- `/run-resume` - Continue from halt
