#!/usr/bin/env bash
# grade.sh — Grader orchestrator for Loa Eval Sandbox
# Runs all graders for a task and produces composite results.
# Exit codes: 0 = pass, 1 = fail, 2 = error (grader infrastructure)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_DIR="$REPO_ROOT/evals"
GRADERS_DIR="$EVALS_DIR/graders"

usage() {
  cat <<'USAGE'
Usage: grade.sh --task-yaml <path> --workspace <path> [--timeout <seconds>]

Runs all graders for a task against a workspace directory.

Options:
  --task-yaml <path>   Path to task YAML file
  --workspace <path>   Path to sandbox workspace
  --timeout <seconds>  Per-grader timeout (default: 30)

Output: JSON array of grader results to stdout
Exit codes: 0 = all pass, 1 = fail, 2 = grader error
USAGE
  exit 2
}

# --- Parse args ---
TASK_YAML=""
WORKSPACE=""
GRADER_TIMEOUT=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-yaml) TASK_YAML="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --timeout) GRADER_TIMEOUT="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TASK_YAML" || -z "$WORKSPACE" ]]; then
  echo "ERROR: --task-yaml and --workspace are required" >&2
  exit 2
fi

if [[ ! -f "$TASK_YAML" ]]; then
  echo "ERROR: Task YAML not found: $TASK_YAML" >&2
  exit 2
fi

if [[ ! -d "$WORKSPACE" ]]; then
  echo "ERROR: Workspace not found: $WORKSPACE" >&2
  exit 2
fi

# --- Read task config ---
composite_strategy="$(yq -r '.graders_strategy // "all_must_pass"' "$TASK_YAML" 2>/dev/null || echo "all_must_pass")"
grader_count="$(yq -r '.graders | length // 0' "$TASK_YAML")"
task_timeout="$(yq -r '.timeout.per_grader // ""' "$TASK_YAML" 2>/dev/null || echo "")"
[[ -n "$task_timeout" ]] && GRADER_TIMEOUT="$task_timeout"

if [[ "$grader_count" -eq 0 ]]; then
  echo "ERROR: No graders defined in task" >&2
  exit 2
fi

# --- Run graders ---
results=()
had_error=false
had_fail=false

for i in $(seq 0 $((grader_count - 1))); do
  grader_script="$(yq -r ".graders[$i].script" "$TASK_YAML")"
  grader_weight="$(yq -r ".graders[$i].weight // 1.0" "$TASK_YAML")"

  # Read args as array
  arg_count="$(yq -r ".graders[$i].args | length // 0" "$TASK_YAML")"
  grader_args=()
  for j in $(seq 0 $((arg_count - 1))); do
    arg="$(yq -r ".graders[$i].args[$j]" "$TASK_YAML")"
    grader_args+=("$arg")
  done

  # Resolve grader path — absolute path via controlled lookup
  grader_path="$GRADERS_DIR/$grader_script"
  if [[ ! -f "$grader_path" ]]; then
    result='{"name":"'"$grader_script"'","pass":false,"score":0,"details":"Grader not found: '"$grader_script"'","exit_code":2,"duration_ms":0,"weight":'"$grader_weight"'}'
    results+=("$result")
    had_error=true
    continue
  fi

  if [[ ! -x "$grader_path" ]]; then
    result='{"name":"'"$grader_script"'","pass":false,"score":0,"details":"Grader not executable: '"$grader_script"'","exit_code":2,"duration_ms":0,"weight":'"$grader_weight"'}'
    results+=("$result")
    had_error=true
    continue
  fi

  # Execute grader with timeout — strict execution model (no eval, no sh -c)
  start_ms="$(date +%s%N | cut -c1-13)"
  grader_output=""
  grader_exit=0

  grader_output="$(timeout --signal=TERM --kill-after=10 "$GRADER_TIMEOUT" \
    "$grader_path" "$WORKSPACE" "${grader_args[@]}" 2>/dev/null)" || grader_exit=$?

  end_ms="$(date +%s%N | cut -c1-13)"
  duration_ms=$(( end_ms - start_ms ))

  # Handle timeout (exit 124 from timeout command)
  if [[ $grader_exit -eq 124 ]]; then
    result="$(jq -n \
      --arg name "$grader_script" \
      --argjson exit_code 2 \
      --argjson duration_ms "$duration_ms" \
      --argjson weight "$grader_weight" \
      '{name:$name,pass:false,score:0,details:"Grader timed out after '"$GRADER_TIMEOUT"'s",exit_code:$exit_code,duration_ms:$duration_ms,weight:$weight}')"
    results+=("$result")
    had_error=true
    continue
  fi

  # Parse grader JSON output
  if echo "$grader_output" | jq . &>/dev/null; then
    grader_pass="$(echo "$grader_output" | jq -r '.pass // false')"
    grader_score="$(echo "$grader_output" | jq -r '.score // 0')"
    grader_details="$(echo "$grader_output" | jq -r '.details // ""')"
    grader_version="$(echo "$grader_output" | jq -r '.grader_version // "1.0.0"')"
  else
    # Non-JSON output — use exit code to determine pass/fail
    grader_pass="false"
    grader_score=0
    grader_details="Non-JSON output: ${grader_output:0:200}"
    grader_version="1.0.0"
    if [[ $grader_exit -eq 0 ]]; then
      grader_pass="true"
      grader_score=100
    fi
  fi

  if [[ $grader_exit -eq 2 ]]; then
    had_error=true
  elif [[ $grader_exit -eq 1 || "$grader_pass" == "false" ]]; then
    had_fail=true
  fi

  result="$(jq -n \
    --arg name "$grader_script" \
    --argjson pass "$grader_pass" \
    --argjson score "$grader_score" \
    --arg details "$grader_details" \
    --argjson exit_code "$grader_exit" \
    --argjson duration_ms "$duration_ms" \
    --argjson weight "$grader_weight" \
    --arg grader_version "$grader_version" \
    '{name:$name,pass:$pass,score:$score,details:$details,exit_code:$exit_code,duration_ms:$duration_ms,weight:$weight,grader_version:$grader_version}')"
  results+=("$result")
done

# --- Compute composite score ---
compute_composite() {
  local strategy="$1"
  shift
  local all_results=("$@")

  local total_score=0
  local total_weight=0
  local all_pass=true
  local any_pass=false
  local min_score=100
  local max_score=0

  for r in "${all_results[@]}"; do
    local pass score weight
    pass="$(echo "$r" | jq -r '.pass')"
    score="$(echo "$r" | jq -r '.score')"
    weight="$(echo "$r" | jq -r '.weight')"
    exit_code="$(echo "$r" | jq -r '.exit_code')"

    # Skip errored graders in composite (exit_code 2)
    [[ "$exit_code" == "2" ]] && continue

    total_score="$(echo "$total_score + $score * $weight" | bc 2>/dev/null || echo "0")"
    total_weight="$(echo "$total_weight + $weight" | bc 2>/dev/null || echo "1")"

    [[ "$pass" == "false" ]] && all_pass=false
    [[ "$pass" == "true" ]] && any_pass=true
    [[ "$score" -lt "$min_score" ]] 2>/dev/null && min_score="$score"
    [[ "$score" -gt "$max_score" ]] 2>/dev/null && max_score="$score"
  done

  local composite_pass=false
  local composite_score=0

  case "$strategy" in
    all_must_pass)
      composite_pass=$all_pass
      composite_score="$min_score"
      ;;
    weighted_average)
      if [[ "$total_weight" != "0" ]]; then
        composite_score="$(echo "$total_score / $total_weight" | bc 2>/dev/null || echo "0")"
      fi
      [[ "$composite_score" -ge 50 ]] 2>/dev/null && composite_pass=true
      ;;
    any_pass)
      composite_pass=$any_pass
      composite_score="$max_score"
      ;;
  esac

  jq -n \
    --arg strategy "$strategy" \
    --argjson pass "$composite_pass" \
    --argjson score "${composite_score:-0}" \
    '{strategy:$strategy,pass:$pass,score:$score}'
}

composite="$(compute_composite "$composite_strategy" "${results[@]}")"

# --- Build output ---
results_json="$(printf '%s\n' "${results[@]}" | jq -s .)"

jq -n \
  --argjson graders "$results_json" \
  --argjson composite "$composite" \
  '{graders:$graders,composite:$composite}'

# --- Exit code ---
if [[ "$had_error" == "true" ]]; then
  exit 2
elif [[ "$(echo "$composite" | jq -r '.pass')" == "false" ]]; then
  exit 1
else
  exit 0
fi
