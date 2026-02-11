#!/usr/bin/env bash
# compare.sh — Baseline comparison engine for Loa Eval Sandbox
# Compares current eval results against stored baselines.
# Exit codes: 0 = no regressions, 1 = regressions found, 2 = error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_DIR="$REPO_ROOT/evals"
BASELINES_DIR="$EVALS_DIR/baselines"

usage() {
  cat <<'USAGE'
Usage: compare.sh [options]

Options:
  --results <file>       Results JSONL file to compare
  --run-dir <dir>        Run directory containing results.jsonl
  --suite <name>         Suite name (for baseline file lookup)
  --baseline <file>      Explicit baseline YAML file
  --threshold <float>    Regression threshold (default: 0.10)
  --strict               Exit 1 on any regression
  --update-baseline      Generate updated baseline from results
  --reason <text>        Reason for baseline update (required with --update-baseline)
  --json                 JSON output
  --quiet                Minimal output

Exit codes:
  0  No regressions
  1  Regressions detected
  2  Error
USAGE
  exit 2
}

# --- Parse args ---
RESULTS_FILE=""
RUN_DIR=""
SUITE=""
BASELINE_FILE=""
THRESHOLD="0.10"
STRICT=false
UPDATE_BASELINE=false
REASON=""
JSON_OUTPUT=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --results) RESULTS_FILE="$2"; shift 2 ;;
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --suite) SUITE="$2"; shift 2 ;;
    --baseline) BASELINE_FILE="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    --update-baseline) UPDATE_BASELINE=true; shift ;;
    --reason) REASON="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --quiet) QUIET=true; shift ;;
    --help|-h) usage ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Resolve results file
if [[ -n "$RUN_DIR" && -z "$RESULTS_FILE" ]]; then
  RESULTS_FILE="$RUN_DIR/results.jsonl"
fi

if [[ -z "$RESULTS_FILE" ]]; then
  echo "ERROR: --results or --run-dir required" >&2
  exit 2
fi

if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "ERROR: Results file not found: $RESULTS_FILE" >&2
  exit 2
fi

# Resolve baseline file
if [[ -z "$BASELINE_FILE" && -n "$SUITE" ]]; then
  BASELINE_FILE="$BASELINES_DIR/${SUITE}.baseline.yaml"
fi

# Update baseline requires --reason
if [[ "$UPDATE_BASELINE" == "true" && -z "$REASON" ]]; then
  echo "ERROR: --reason is required with --update-baseline" >&2
  exit 2
fi

# --- Aggregate results by task ---
aggregate_results() {
  local results_file="$1"

  # Group by task_id, compute pass rate and mean score
  jq -s '
    group_by(.task_id) | map({
      task_id: .[0].task_id,
      trials: length,
      passes: [.[] | select(.composite.pass == true)] | length,
      pass_rate: (([.[] | select(.composite.pass == true)] | length) / length),
      mean_score: ([.[].composite.score] | add / length),
      status: "active"
    })
  ' "$results_file"
}

# --- Early stopping check for multi-trial evals ---
# Returns "true" if regression is inevitable even if all remaining trials pass.
# Used by run-eval.sh to skip remaining trials when outcome is determined.
# Uses raw pass rate (not Wilson CI) to avoid false positives from wide CIs at small n.
# Wilson CI is applied at comparison time for the final verdict; early stopping
# only needs to answer: "can the best-case pass rate reach the baseline?"
# Args: $1=passes, $2=failures, $3=remaining, $4=baseline_pass_rate, $5=threshold
can_early_stop() {
  local passes="$1"
  local failures="$2"
  local remaining="$3"
  local bl_pass_rate="${4:-1.0}"
  local threshold="${5:-0.10}"

  python3 -c "
passes = $passes
failures = $failures
remaining = $remaining
bl_pass_rate = $bl_pass_rate
threshold = $threshold

# Best case: all remaining trials pass
best_passes = passes + remaining
total = passes + failures + remaining

if total == 0:
    print('false')
else:
    best_pass_rate = best_passes / total
    # Regression inevitable if best-case pass rate still below threshold
    if best_pass_rate < bl_pass_rate - threshold:
        print('true')
    else:
        print('false')
" 2>/dev/null || echo "false"
}

# --- Wilson confidence interval (95%) ---
# Computes lower and upper bounds for a binomial proportion.
# Uses the Wilson score interval: more accurate than normal approximation for small n.
# z = 1.96 for 95% confidence
wilson_interval() {
  local passes="$1"
  local trials="$2"

  # Return JSON: {"lower": float, "upper": float}
  python3 -c "
import math, json
n = $trials
p = $passes / n if n > 0 else 0
z = 1.96
denom = 1 + z*z/n
center = (p + z*z/(2*n)) / denom
spread = z * math.sqrt((p*(1-p) + z*z/(4*n)) / n) / denom
lower = max(0, center - spread)
upper = min(1, center + spread)
print(json.dumps({'lower': round(lower, 4), 'upper': round(upper, 4)}))
" 2>/dev/null || echo '{"lower":0,"upper":1}'
}

# --- Compare against baseline ---
compare_baseline() {
  local current_json="$1"
  local baseline_file="$2"
  local threshold="$3"

  if [[ ! -f "$baseline_file" ]]; then
    # No baseline — all tasks are "new"
    echo "$current_json" | jq '[.[] | . + {classification: "new", baseline_pass_rate: null, delta: null, wilson_ci: null, advisory: false}]'
    return
  fi

  # Read baseline tasks and model version
  local baseline_tasks
  baseline_tasks="$(yq -o=json '.tasks' "$baseline_file")"
  local baseline_model
  baseline_model="$(yq -r '.model_version // "unknown"' "$baseline_file")"

  # Get current model version from results
  local current_model="unknown"
  if [[ -f "$RESULTS_FILE" ]]; then
    current_model="$(jq -r '.[0].model_version // "unknown"' "$RESULTS_FILE" 2>/dev/null || echo "unknown")"
  fi

  # Detect model version skew
  local model_skew=false
  if [[ "$baseline_model" != "unknown" && "$current_model" != "unknown" && "$baseline_model" != "$current_model" ]]; then
    model_skew=true
  fi

  # Build comparison with Wilson intervals for agent evals
  local task_count
  task_count="$(echo "$current_json" | jq 'length')"
  local result_array="["
  local first=true

  for i in $(seq 0 $((task_count - 1))); do
    local task_json
    task_json="$(echo "$current_json" | jq ".[$i]")"
    local tid passes trials
    tid="$(echo "$task_json" | jq -r '.task_id')"
    passes="$(echo "$task_json" | jq -r '.passes')"
    trials="$(echo "$task_json" | jq -r '.trials')"
    local pass_rate
    pass_rate="$(echo "$task_json" | jq -r '.pass_rate')"

    # Get baseline data
    local bl_pass_rate bl_trials bl_status
    bl_pass_rate="$(echo "$baseline_tasks" | jq -r --arg tid "$tid" '.[$tid].pass_rate // -1')"
    bl_trials="$(echo "$baseline_tasks" | jq -r --arg tid "$tid" '.[$tid].trials // 0')"
    bl_status="$(echo "$baseline_tasks" | jq -r --arg tid "$tid" '.[$tid].status // "active"')"

    local classification="new"
    local delta="null"
    local wilson_ci="null"
    local advisory=false

    if [[ "$bl_pass_rate" == "-1" ]]; then
      classification="new"
    elif [[ "$bl_status" == "quarantined" ]]; then
      classification="quarantined"
      delta="$(echo "$pass_rate - $bl_pass_rate" | bc 2>/dev/null || echo "0")"
    elif [[ "$trials" -eq 1 ]]; then
      # Single trial — exact match comparison (framework evals or emergency agent eval)
      if echo "$pass_rate >= $bl_pass_rate" | bc -l 2>/dev/null | grep -q '^1'; then
        if echo "$pass_rate > $bl_pass_rate" | bc -l 2>/dev/null | grep -q '^1'; then
          classification="improvement"
        else
          classification="pass"
        fi
      elif echo "$pass_rate < $bl_pass_rate - $threshold" | bc -l 2>/dev/null | grep -q '^1'; then
        classification="regression"
        # Single-trial agent eval with regression — advisory only
        if [[ "$bl_trials" -gt 1 ]]; then
          advisory=true
        fi
      else
        classification="degraded"
      fi
      delta="$(echo "$pass_rate - $bl_pass_rate" | bc 2>/dev/null || echo "0")"
    else
      # Multi-trial: use Wilson confidence intervals
      local ci
      ci="$(wilson_interval "$passes" "$trials")"
      wilson_ci="$ci"
      local ci_lower ci_upper
      ci_lower="$(echo "$ci" | jq -r '.lower')"
      ci_upper="$(echo "$ci" | jq -r '.upper')"

      # Compute baseline Wilson CI
      local bl_passes
      bl_passes="$(echo "$bl_pass_rate * $bl_trials" | bc 2>/dev/null | cut -d. -f1)"
      bl_passes="${bl_passes:-0}"
      local bl_ci
      bl_ci="$(wilson_interval "$bl_passes" "$bl_trials")"
      local bl_ci_upper
      bl_ci_upper="$(echo "$bl_ci" | jq -r '.upper')"

      # Regression: lower bound of current < upper bound of baseline - threshold
      if echo "$ci_lower < $bl_ci_upper - $threshold" | bc -l 2>/dev/null | grep -q '^1'; then
        classification="regression"
      elif echo "$pass_rate > $bl_pass_rate" | bc -l 2>/dev/null | grep -q '^1'; then
        classification="improvement"
      elif echo "$pass_rate >= $bl_pass_rate" | bc -l 2>/dev/null | grep -q '^1'; then
        classification="pass"
      else
        classification="degraded"
      fi
      delta="$(echo "$pass_rate - $bl_pass_rate" | bc 2>/dev/null || echo "0")"
    fi

    # Model skew makes all results advisory
    if [[ "$model_skew" == "true" ]]; then
      advisory=true
    fi

    [[ "$first" == "true" ]] && first=false || result_array+=","
    result_array+="$(echo "$task_json" | jq \
      --arg cl "$classification" \
      --argjson bl_pr "$bl_pass_rate" \
      --argjson delta "${delta:-null}" \
      --argjson wilson "$wilson_ci" \
      --argjson adv "$advisory" \
      '. + {classification: $cl, baseline_pass_rate: (if $bl_pr == -1 then null else $bl_pr end), delta: $delta, wilson_ci: $wilson, advisory: $adv}')"
  done

  # Add missing tasks
  local missing_tasks
  missing_tasks="$(echo "$current_json" | jq --argjson baseline "$baseline_tasks" '
    [
      $baseline | to_entries[] |
      .key as $tid |
      .value as $bl |
      if (input | map(.task_id) | index($tid)) == null then
        {task_id: $tid, trials: 0, passes: 0, pass_rate: 0, mean_score: 0, status: $bl.status,
         classification: "missing", baseline_pass_rate: $bl.pass_rate, delta: (0 - $bl.pass_rate),
         wilson_ci: null, advisory: false}
      else
        empty
      end
    ]
  ' 2>/dev/null || echo "[]")"

  # Merge missing tasks
  for missing in $(echo "$missing_tasks" | jq -c '.[]' 2>/dev/null); do
    [[ "$first" == "true" ]] && first=false || result_array+=","
    result_array+="$missing"
  done

  result_array+="]"
  echo "$result_array" | jq .
}

# --- Update baseline ---
update_baseline() {
  local current_json="$1"
  local suite="$2"
  local reason="$3"
  local output_file="${4:-}"

  if [[ -z "$output_file" ]]; then
    output_file="$BASELINES_DIR/${suite}.baseline.yaml"
  fi

  # Get model version from results
  local model_version
  model_version="$(jq -r '.[0].model_version // "unknown"' "$RESULTS_FILE" 2>/dev/null || echo "unknown")"

  # Get run_id from results
  local run_id
  run_id="$(jq -r '.[0].run_id // "unknown"' "$RESULTS_FILE" 2>/dev/null || echo "unknown")"

  # Generate baseline YAML
  {
    echo "version: 1"
    echo "suite: $suite"
    echo "model_version: \"$model_version\""
    echo "recorded_at: \"$(date -u +%Y-%m-%d)\""
    echo "recorded_from_run: \"$run_id\""
    echo "update_reason: \"$reason\""
    echo "tasks:"
    echo "$current_json" | jq -r '.[] | "  \(.task_id):\n    pass_rate: \(.pass_rate)\n    trials: \(.trials)\n    mean_score: \(.mean_score | floor)\n    status: active"'
  } > "$output_file"

  echo "Baseline updated: $output_file" >&2
}

# --- Main ---
current_aggregated="$(aggregate_results "$RESULTS_FILE")"

if [[ "$UPDATE_BASELINE" == "true" ]]; then
  suite_name="${SUITE:-unknown}"
  update_baseline "$current_aggregated" "$suite_name" "$REASON"
  exit 0
fi

# Compare against baseline
if [[ -n "$BASELINE_FILE" && -f "$BASELINE_FILE" ]]; then
  comparison="$(compare_baseline "$current_aggregated" "$BASELINE_FILE" "$THRESHOLD")"
else
  comparison="$(echo "$current_aggregated" | jq '[.[] | . + {classification: "new", baseline_pass_rate: null, delta: null}]')"
fi

# Count classifications
regressions="$(echo "$comparison" | jq '[.[] | select(.classification == "regression")] | length')"
improvements="$(echo "$comparison" | jq '[.[] | select(.classification == "improvement")] | length')"
passes="$(echo "$comparison" | jq '[.[] | select(.classification == "pass")] | length')"
degraded="$(echo "$comparison" | jq '[.[] | select(.classification == "degraded")] | length')"
new_tasks="$(echo "$comparison" | jq '[.[] | select(.classification == "new")] | length')"
missing="$(echo "$comparison" | jq '[.[] | select(.classification == "missing")] | length')"
quarantined="$(echo "$comparison" | jq '[.[] | select(.classification == "quarantined")] | length')"

# Output
if [[ "$JSON_OUTPUT" == "true" ]]; then
  jq -n \
    --argjson results "$comparison" \
    --argjson regressions "$regressions" \
    --argjson improvements "$improvements" \
    --argjson passes "$passes" \
    --argjson degraded "$degraded" \
    --argjson new "$new_tasks" \
    --argjson missing "$missing" \
    --argjson quarantined "$quarantined" \
    '{
      summary: {
        regressions: $regressions,
        improvements: $improvements,
        passes: $passes,
        degraded: $degraded,
        new: $new,
        missing: $missing,
        quarantined: $quarantined
      },
      results: $results
    }'
elif [[ "$QUIET" != "true" ]]; then
  echo "Comparison: $passes pass, $regressions regressions, $improvements improvements, $degraded degraded, $new_tasks new, $missing missing, $quarantined quarantined"

  if [[ "$regressions" -gt 0 ]]; then
    echo ""
    echo "REGRESSIONS:"
    echo "$comparison" | jq -r '.[] | select(.classification == "regression") | "  \(.task_id): \(.baseline_pass_rate * 100 | floor)% → \(.pass_rate * 100 | floor)% (\(.delta * 100 | floor)%)"'
  fi

  if [[ "$improvements" -gt 0 ]]; then
    echo ""
    echo "IMPROVEMENTS:"
    echo "$comparison" | jq -r '.[] | select(.classification == "improvement") | "  \(.task_id): \(.baseline_pass_rate * 100 | floor)% → \(.pass_rate * 100 | floor)% (+\(.delta * 100 | floor)%)"'
  fi
fi

# Exit code
if [[ "$regressions" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
