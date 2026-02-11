#!/usr/bin/env bash
# run-eval.sh — Main eval harness orchestrator for Loa Eval Sandbox
# Pipeline: PREFLIGHT → INIT → LOAD_SUITE → VALIDATE_TASKS → EXECUTE_TRIALS → GRADE → FINALIZE → COMPARE → REPORT → DONE
# Exit codes: 0 = pass, 1 = regression, 2 = infrastructure error, 3 = config error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_DIR="$REPO_ROOT/evals"
HARNESS_DIR="$EVALS_DIR/harness"
GRADERS_DIR="$EVALS_DIR/graders"
RESULTS_DIR="$EVALS_DIR/results"
BASELINES_DIR="$EVALS_DIR/baselines"
SUITES_DIR="$EVALS_DIR/suites"
TASKS_DIR="$EVALS_DIR/tasks"

HARNESS_VERSION="1.0.0"

usage() {
  cat <<'USAGE'
Usage: run-eval.sh [options]

Run evaluation suites for the Loa framework.

Options:
  --suite <name>         Run a named suite (e.g., framework, regression)
  --task <id>            Run a single task by ID
  --skill <name>         Run all tasks for a skill
  --update-baseline      Update baselines from results
  --reason <text>        Reason for baseline update (required with --update-baseline)
  --compare <run-id>     Compare against a specific run
  --json                 JSON output mode
  --trusted              Required for local execution (no container sandbox)
  --sandbox-mode <mode>  Sandbox mode: local (default), container
  --concurrency <n>      Max parallel tasks (default: 4)
  --no-color             Disable color output
  --verbose              Verbose output
  --help                 Show this help

Exit codes:
  0  All tasks pass, no regressions
  1  Regressions detected
  2  Infrastructure error
  3  Configuration error

Examples:
  run-eval.sh --suite framework --trusted
  run-eval.sh --task constraint-never-code-outside-implement --trusted
  run-eval.sh --suite regression --json --trusted
  run-eval.sh --update-baseline --suite framework --reason "Initial baseline"
USAGE
  exit 3
}

# --- Parse args ---
SUITE=""
TASK_ID=""
SKILL=""
UPDATE_BASELINE=false
REASON=""
COMPARE_RUN=""
JSON_OUTPUT=false
TRUSTED=false
SANDBOX_MODE="local"
CONCURRENCY=4
NO_COLOR=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite) SUITE="$2"; shift 2 ;;
    --task) TASK_ID="$2"; shift 2 ;;
    --skill) SKILL="$2"; shift 2 ;;
    --update-baseline) UPDATE_BASELINE=true; shift ;;
    --reason) REASON="$2"; shift 2 ;;
    --compare) COMPARE_RUN="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --trusted) TRUSTED=true; shift ;;
    --sandbox-mode) SANDBOX_MODE="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    --no-color) NO_COLOR=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --help|-h) usage ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 3 ;;
  esac
done

# --- PHASE: PREFLIGHT ---
log() {
  if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo "$@" >&2
  fi
}

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    log "$@"
  fi
}

preflight() {
  log "[PREFLIGHT] Checking required tools..."

  local missing=()
  for tool in bash jq git timeout mktemp sha256sum yq; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}" >&2
    echo "" >&2
    echo "Install guidance:" >&2
    for tool in "${missing[@]}"; do
      case "$tool" in
        jq) echo "  jq: apt install jq / brew install jq" >&2 ;;
        yq) echo "  yq: pip install yq / brew install yq (mikefarah/yq)" >&2 ;;
        timeout) echo "  timeout: part of coreutils (apt install coreutils)" >&2 ;;
        sha256sum) echo "  sha256sum: part of coreutils (apt install coreutils)" >&2 ;;
        *) echo "  $tool: check your system package manager" >&2 ;;
      esac
    done
    exit 3
  fi

  # Bash version check (≥4 for associative arrays)
  if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: Bash ≥4 required (found: $BASH_VERSION)" >&2
    exit 3
  fi

  # Trusted mode check
  if [[ "$TRUSTED" != "true" && "$SANDBOX_MODE" == "local" ]]; then
    echo "ERROR: Local execution requires --trusted flag." >&2
    echo "" >&2
    echo "The eval harness runs code in your local environment." >&2
    echo "Use --trusted to acknowledge this, or use --sandbox-mode container for isolation." >&2
    exit 3
  fi

  # Check evals directory exists
  if [[ ! -d "$EVALS_DIR" ]]; then
    echo "ERROR: Evals directory not found: $EVALS_DIR" >&2
    exit 3
  fi

  log "[PREFLIGHT] All checks passed."
}

# --- PHASE: INIT ---
init_run() {
  local timestamp
  timestamp="$(date -u +%Y%m%d-%H%M%S)"
  local hash
  hash="$(echo "${timestamp}-$$" | sha256sum | cut -c1-8)"

  RUN_ID="run-${timestamp}-${hash}"
  RUN_DIR="$RESULTS_DIR/$RUN_ID"
  mkdir -p "$RUN_DIR"

  RUN_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  RUN_START_MS="$(date +%s%N | cut -c1-13)"

  log "[INIT] Run ID: $RUN_ID"
  log "[INIT] Run directory: $RUN_DIR"
}

# --- PHASE: LOAD_SUITE ---
load_tasks() {
  TASK_FILES=()

  if [[ -n "$TASK_ID" ]]; then
    # Single task mode
    local task_file
    task_file="$(find "$TASKS_DIR" -name "${TASK_ID}.yaml" -o -name "${TASK_ID}.yml" | head -1)"
    if [[ -z "$task_file" ]]; then
      echo "ERROR: Task not found: $TASK_ID" >&2
      exit 3
    fi
    TASK_FILES=("$task_file")
    [[ -z "$SUITE" ]] && SUITE="single"
    log "[LOAD] Loaded single task: $TASK_ID"
    return
  fi

  if [[ -n "$SKILL" ]]; then
    # Skill filter mode
    while IFS= read -r -d '' task_file; do
      local task_skill
      task_skill="$(yq -r '.skill // ""' "$task_file")"
      if [[ "$task_skill" == "$SKILL" ]]; then
        TASK_FILES+=("$task_file")
      fi
    done < <(find "$TASKS_DIR" -name '*.yaml' -o -name '*.yml' | tr '\n' '\0')
    [[ -z "$SUITE" ]] && SUITE="skill-$SKILL"
    log "[LOAD] Found ${#TASK_FILES[@]} tasks for skill: $SKILL"
    return
  fi

  if [[ -n "$SUITE" ]]; then
    local suite_file="$SUITES_DIR/${SUITE}.yaml"
    if [[ ! -f "$suite_file" ]]; then
      echo "ERROR: Suite not found: $suite_file" >&2
      exit 3
    fi

    # Read include patterns from suite
    local include_count
    include_count="$(yq -r '.tasks.include | length // 0' "$suite_file")"

    for i in $(seq 0 $((include_count - 1))); do
      local pattern
      pattern="$(yq -r ".tasks.include[$i]" "$suite_file")"

      # Resolve glob pattern relative to evals/
      # Use bash globbing with globstar for ** patterns
      local had_globstar=false
      shopt -q globstar 2>/dev/null && had_globstar=true
      shopt -s globstar 2>/dev/null || true

      local glob_expanded=false
      for task_file in $EVALS_DIR/$pattern; do
        if [[ -f "$task_file" ]]; then
          TASK_FILES+=("$task_file")
          glob_expanded=true
        fi
      done

      # Restore globstar
      if [[ "$had_globstar" == "false" ]]; then
        shopt -u globstar 2>/dev/null || true
      fi

      # Fallback: if glob didn't match, try find in the directory
      if [[ "$glob_expanded" == "false" ]]; then
        # Extract directory portion from pattern
        local pattern_dir="${pattern%/*}"
        if [[ -d "$EVALS_DIR/$pattern_dir" ]]; then
          while IFS= read -r -d '' task_file; do
            TASK_FILES+=("$task_file")
          done < <(find "$EVALS_DIR/$pattern_dir" \( -name '*.yaml' -o -name '*.yml' \) -type f -print0 2>/dev/null)
        fi
      fi
    done

    # Apply exclude patterns
    local exclude_count
    exclude_count="$(yq -r '.tasks.exclude | length // 0' "$suite_file" 2>/dev/null || echo "0")"
    if [[ "$exclude_count" -gt 0 ]]; then
      local filtered_tasks=()
      for task_file in "${TASK_FILES[@]}"; do
        local excluded=false
        for j in $(seq 0 $((exclude_count - 1))); do
          local exclude_pattern
          exclude_pattern="$(yq -r ".tasks.exclude[$j]" "$suite_file")"
          if [[ "$(basename "$task_file")" == $exclude_pattern ]]; then
            excluded=true
            break
          fi
        done
        [[ "$excluded" == "false" ]] && filtered_tasks+=("$task_file")
      done
      TASK_FILES=("${filtered_tasks[@]}")
    fi

    # Read suite defaults
    SUITE_TRIALS="$(yq -r '.defaults.trials // 1' "$suite_file")"
    SUITE_TIMEOUT_TRIAL="$(yq -r '.defaults.timeout.per_trial // 120' "$suite_file")"
    SUITE_TIMEOUT_GRADER="$(yq -r '.defaults.timeout.per_grader // 30' "$suite_file")"
    SUITE_STRATEGY="$(yq -r '.defaults.composite_strategy // "all_must_pass"' "$suite_file")"

    log "[LOAD] Suite '$SUITE': ${#TASK_FILES[@]} tasks, ${SUITE_TRIALS} trial(s)"
    return
  fi

  # Default: run all tasks
  while IFS= read -r -d '' task_file; do
    TASK_FILES+=("$task_file")
  done < <(find "$TASKS_DIR" -name '*.yaml' -o -name '*.yml' | sort | tr '\n' '\0')
  SUITE="all"
  log "[LOAD] Loaded ${#TASK_FILES[@]} tasks (all)"
}

# Suite defaults
SUITE_TRIALS=1
SUITE_TIMEOUT_TRIAL=120
SUITE_TIMEOUT_GRADER=30
SUITE_STRATEGY="all_must_pass"

# --- PHASE: VALIDATE_TASKS ---
validate_tasks() {
  log "[VALIDATE] Validating ${#TASK_FILES[@]} tasks..."

  local valid_tasks=()
  local invalid_count=0

  for task_file in "${TASK_FILES[@]}"; do
    local result
    result="$("$HARNESS_DIR/validate-task.sh" "$task_file" 2>/dev/null)" || true

    local valid
    valid="$(echo "$result" | jq -r '.valid // false' 2>/dev/null || echo "false")"

    if [[ "$valid" == "true" ]]; then
      valid_tasks+=("$task_file")
    else
      invalid_count=$((invalid_count + 1))
      local errors
      errors="$(echo "$result" | jq -r '.errors[]? // empty' 2>/dev/null || echo "validation failed")"
      log "  INVALID: $(basename "$task_file"): $errors"
    fi
  done

  if [[ $invalid_count -gt 0 ]]; then
    log "[VALIDATE] $invalid_count invalid task(s) skipped"
  fi

  TASK_FILES=("${valid_tasks[@]}")
  log "[VALIDATE] ${#TASK_FILES[@]} valid tasks ready"

  if [[ ${#TASK_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No valid tasks to run" >&2
    exit 3
  fi
}

# --- PHASE: EXECUTE_TRIALS ---
execute_task() {
  local task_file="$1"
  local task_id
  task_id="$(yq -r '.id' "$task_file")"
  local category
  category="$(yq -r '.category // "framework"' "$task_file")"
  local fixture
  fixture="$(yq -r '.fixture' "$task_file")"
  local trials
  trials="$(yq -r ".trials // $SUITE_TRIALS" "$task_file")"
  local timeout_trial
  timeout_trial="$(yq -r ".timeout.per_trial // $SUITE_TIMEOUT_TRIAL" "$task_file")"
  local timeout_grader
  timeout_grader="$(yq -r ".timeout.per_grader // $SUITE_TIMEOUT_GRADER" "$task_file")"

  local task_result_file="$RUN_DIR/task-${task_id}.jsonl"

  log_verbose "  [TASK] $task_id ($category, ${trials} trial(s))"

  # Early stopping counters for multi-trial tasks
  local es_passes=0
  local es_failures=0

  for trial_num in $(seq 1 "$trials"); do
    local trial_id="${RUN_ID}-${task_id}-trial-${trial_num}"
    local trial_start_ms
    trial_start_ms="$(date +%s%N | cut -c1-13)"

    # Create sandbox
    local sandbox_path=""
    sandbox_path="$("$HARNESS_DIR/sandbox.sh" create \
      --fixture "$fixture" \
      --run-id "$RUN_ID" \
      --trial-id "$trial_id" 2>/dev/null)" || {
      # Infrastructure error
      local trial_end_ms
      trial_end_ms="$(date +%s%N | cut -c1-13)"
      jq -cn \
        --arg run_id "$RUN_ID" \
        --arg task_id "$task_id" \
        --argjson trial "$trial_num" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson duration_ms "$(( trial_end_ms - trial_start_ms ))" \
        --arg status "error" \
        --argjson schema_version 1 \
        '{run_id:$run_id,task_id:$task_id,trial:$trial,timestamp:$timestamp,duration_ms:$duration_ms,status:$status,schema_version:$schema_version,
          composite:{strategy:"all_must_pass",pass:false,score:0},graders:[],error:{type:"infrastructure_error",message:"Sandbox creation failed"}}' \
        >> "$task_result_file"
      continue
    }

    # For framework tasks, there's no agent execution — just run graders directly
    # For agent tasks (skill-quality, e2e), agent execution would happen here (Phase 3+)

    # Run graders
    local grade_output=""
    local grade_exit=0
    grade_output="$("$HARNESS_DIR/grade.sh" \
      --task-yaml "$task_file" \
      --workspace "$sandbox_path" \
      --timeout "$timeout_grader" 2>/dev/null)" || grade_exit=$?

    local trial_end_ms
    trial_end_ms="$(date +%s%N | cut -c1-13)"
    local trial_duration=$(( trial_end_ms - trial_start_ms ))

    # Parse grader results
    local graders_json composite_json status_str error_json
    if echo "$grade_output" | jq . &>/dev/null; then
      graders_json="$(echo "$grade_output" | jq '.graders')"
      composite_json="$(echo "$grade_output" | jq '.composite')"
    else
      graders_json="[]"
      composite_json='{"strategy":"all_must_pass","pass":false,"score":0}'
    fi

    case $grade_exit in
      0) status_str="completed" ; error_json="null" ;;
      1) status_str="completed" ; error_json="null" ;;
      2) status_str="error"     ; error_json='{"type":"infrastructure_error","message":"Grader error"}' ;;
      *) status_str="error"     ; error_json='{"type":"infrastructure_error","message":"Unknown grader exit: '"$grade_exit"'"}' ;;
    esac

    # Write per-trial result (compact JSONL)
    jq -cn \
      --arg run_id "$RUN_ID" \
      --arg task_id "$task_id" \
      --argjson trial "$trial_num" \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson duration_ms "$trial_duration" \
      --arg model_version "none" \
      --arg status "$status_str" \
      --argjson graders "$graders_json" \
      --argjson composite "$composite_json" \
      --argjson error "$error_json" \
      --argjson schema_version 1 \
      '{run_id:$run_id,task_id:$task_id,trial:$trial,timestamp:$timestamp,duration_ms:$duration_ms,
        model_version:$model_version,status:$status,graders:$graders,composite:$composite,
        error:$error,schema_version:$schema_version}' \
      >> "$task_result_file"

    # Cleanup sandbox
    "$HARNESS_DIR/sandbox.sh" destroy --trial-id "$trial_id" 2>/dev/null || true

    # Track pass/fail for early stopping
    local trial_passed
    trial_passed="$(echo "${composite_json:-{}}" | jq -r '.pass // false' 2>/dev/null || echo "false")"
    if [[ "$trial_passed" == "true" ]]; then
      es_passes=$((es_passes + 1))
    else
      es_failures=$((es_failures + 1))
    fi

    # Early stopping for multi-trial tasks: skip remaining trials if regression is inevitable
    # Uses raw pass rate: if best-case (all remaining pass) still below baseline - threshold, stop.
    # Note: 0.90 assumes baseline=1.0 threshold=0.10 (conservative default since baselines
    # aren't loaded during EXECUTE phase — they're loaded in the later COMPARE phase).
    if [[ "$trials" -gt 1 && "$trial_num" -lt "$trials" ]]; then
      local remaining=$(( trials - trial_num ))
      local should_stop
      should_stop="$(python3 -c "
p = $es_passes; f = $es_failures; r = $remaining
best = (p + r) / (p + f + r) if (p + f + r) > 0 else 0
print('true' if best < 0.90 else 'false')
" 2>/dev/null)" || should_stop="false"
      if [[ "$should_stop" == "true" ]]; then
        log_verbose "  Task $task_id: early stopped at trial $trial_num/$trials — regression inevitable"
        # Mark remaining trials as skipped in result
        jq -cn \
          --arg run_id "$RUN_ID" \
          --arg task_id "$task_id" \
          --argjson trial "$((trial_num + 1))" \
          --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          --argjson duration_ms 0 \
          --arg model_version "none" \
          --arg status "skipped" \
          --argjson schema_version 1 \
          '{run_id:$run_id,task_id:$task_id,trial:$trial,timestamp:$timestamp,duration_ms:$duration_ms,
            model_version:$model_version,status:$status,graders:[],
            composite:{strategy:"all_must_pass",pass:false,score:0},
            error:null,schema_version:$schema_version,early_stopped:true}' \
          >> "$task_result_file"
        break
      fi
    fi
  done
}

execute_all_tasks() {
  log "[EXECUTE] Running ${#TASK_FILES[@]} tasks (concurrency: $CONCURRENCY)..."

  local pids=()
  local running=0

  for task_file in "${TASK_FILES[@]}"; do
    # Wait if at concurrency limit
    while [[ $running -ge $CONCURRENCY ]]; do
      for i in "${!pids[@]}"; do
        if ! kill -0 "${pids[$i]}" 2>/dev/null; then
          wait "${pids[$i]}" 2>/dev/null || true
          unset "pids[$i]"
          running=$((running - 1))
        fi
      done
      [[ $running -ge $CONCURRENCY ]] && sleep 0.1
    done

    # Execute task in background
    execute_task "$task_file" &
    pids+=($!)
    running=$((running + 1))
  done

  # Wait for all tasks to complete
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  log "[EXECUTE] All tasks completed."
}

# --- PHASE: FINALIZE ---
finalize_results() {
  log "[FINALIZE] Merging per-task results..."

  local merged_file="$RUN_DIR/results.jsonl"
  : > "$merged_file"

  # Single-threaded merge of per-task result files
  local tasks_total=0
  local tasks_passed=0
  local tasks_failed=0
  local tasks_error=0
  local total_duration=0

  for result_file in "$RUN_DIR"/task-*.jsonl; do
    [[ -f "$result_file" ]] || continue

    cat "$result_file" >> "$merged_file"

    # Count task-level pass/fail (based on last trial)
    local task_pass
    task_pass="$(tail -1 "$result_file" | jq -r '.composite.pass // false')"
    local task_status
    task_status="$(tail -1 "$result_file" | jq -r '.status // "error"')"

    tasks_total=$((tasks_total + 1))
    if [[ "$task_status" == "error" ]]; then
      tasks_error=$((tasks_error + 1))
    elif [[ "$task_pass" == "true" ]]; then
      tasks_passed=$((tasks_passed + 1))
    else
      tasks_failed=$((tasks_failed + 1))
    fi
  done

  # Append to eval ledger (with flock for atomicity)
  local ledger_file="$RESULTS_DIR/eval-ledger.jsonl"
  if [[ -f "$merged_file" && -s "$merged_file" ]]; then
    (
      flock -w 5 200 || { log "WARNING: Could not acquire ledger lock"; exit 0; }
      cat "$merged_file" >> "$ledger_file"
    ) 200>"$ledger_file.lock"
    rm -f "$ledger_file.lock"
  fi

  # Write run metadata
  local run_end_ms
  run_end_ms="$(date +%s%N | cut -c1-13)"
  local run_duration=$(( run_end_ms - RUN_START_MS ))

  jq -n \
    --arg run_id "$RUN_ID" \
    --arg suite "$SUITE" \
    --arg started_at "$RUN_START" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson duration_ms "$run_duration" \
    --argjson tasks_total "$tasks_total" \
    --argjson tasks_passed "$tasks_passed" \
    --argjson tasks_failed "$tasks_failed" \
    --argjson tasks_error "$tasks_error" \
    --arg model_version "none" \
    --arg git_sha "$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")" \
    --arg git_branch "$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "unknown")" \
    --arg harness_version "$HARNESS_VERSION" \
    --argjson cost_usd 0.00 \
    --arg environment "$SANDBOX_MODE" \
    --argjson schema_version 1 \
    '{run_id:$run_id,suite:$suite,started_at:$started_at,completed_at:$completed_at,
      duration_ms:$duration_ms,tasks_total:$tasks_total,tasks_passed:$tasks_passed,
      tasks_failed:$tasks_failed,tasks_error:$tasks_error,model_version:$model_version,
      git_sha:$git_sha,git_branch:$git_branch,harness_version:$harness_version,
      cost_usd:$cost_usd,environment:$environment,schema_version:$schema_version}' \
    > "$RUN_DIR/run-meta.json"

  TASKS_TOTAL=$tasks_total
  TASKS_PASSED=$tasks_passed
  TASKS_FAILED=$tasks_failed
  TASKS_ERROR=$tasks_error

  log "[FINALIZE] $tasks_passed/$tasks_total passed, $tasks_failed failed, $tasks_error errors"
}

# Track totals
TASKS_TOTAL=0
TASKS_PASSED=0
TASKS_FAILED=0
TASKS_ERROR=0

# --- PHASE: COMPARE ---
run_compare() {
  log "[COMPARE] Comparing against baseline..."

  local compare_args=("--run-dir" "$RUN_DIR" "--suite" "$SUITE")
  [[ "$JSON_OUTPUT" == "true" ]] && compare_args+=("--json")

  local baseline_file="$BASELINES_DIR/${SUITE}.baseline.yaml"
  if [[ -f "$baseline_file" ]]; then
    compare_args+=("--baseline" "$baseline_file")
  fi

  local compare_output=""
  local compare_exit=0
  compare_output="$("$HARNESS_DIR/compare.sh" --results "$RUN_DIR/results.jsonl" "${compare_args[@]}" --json 2>/dev/null)" || compare_exit=$?

  # Save comparison for report
  echo "$compare_output" > "$RUN_DIR/comparison.json"

  COMPARE_EXIT=$compare_exit
}

COMPARE_EXIT=0

# --- PHASE: REPORT ---
run_report() {
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    # JSON output: merge run-meta + comparison
    local meta
    meta="$(cat "$RUN_DIR/run-meta.json")"
    local comparison="{}"
    [[ -f "$RUN_DIR/comparison.json" ]] && comparison="$(cat "$RUN_DIR/comparison.json")"

    jq -n \
      --argjson meta "$meta" \
      --argjson comparison "$comparison" \
      '{meta:$meta,comparison:$comparison}'
  else
    local report_args=("--run-dir" "$RUN_DIR")
    [[ -f "$RUN_DIR/comparison.json" ]] && report_args+=("--comparison" "$RUN_DIR/comparison.json")
    [[ "$NO_COLOR" == "true" ]] && report_args+=("--no-color")

    "$HARNESS_DIR/report.sh" "${report_args[@]}" 2>/dev/null || true
  fi
}

# --- PHASE: UPDATE_BASELINE ---
run_update_baseline() {
  if [[ "$UPDATE_BASELINE" != "true" ]]; then
    return
  fi

  log "[BASELINE] Updating baseline for suite: $SUITE"
  "$HARNESS_DIR/compare.sh" \
    --results "$RUN_DIR/results.jsonl" \
    --suite "$SUITE" \
    --update-baseline \
    --reason "$REASON"
}

# --- MAIN PIPELINE ---
main() {
  preflight
  init_run
  load_tasks
  validate_tasks
  execute_all_tasks
  finalize_results
  run_compare
  run_report
  run_update_baseline

  # Cleanup all run sandboxes
  "$HARNESS_DIR/sandbox.sh" destroy-all --run-id "$RUN_ID" 2>/dev/null || true

  log "[DONE] Run complete: $RUN_ID"

  # Exit code based on comparison
  if [[ $COMPARE_EXIT -eq 1 ]]; then
    exit 1  # Regressions
  elif [[ $TASKS_ERROR -gt 0 ]]; then
    exit 2  # Infrastructure errors
  else
    exit 0  # All good
  fi
}

main
