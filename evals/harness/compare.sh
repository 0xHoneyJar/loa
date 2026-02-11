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

# --- Compare against baseline ---
compare_baseline() {
  local current_json="$1"
  local baseline_file="$2"
  local threshold="$3"

  if [[ ! -f "$baseline_file" ]]; then
    # No baseline — all tasks are "new"
    echo "$current_json" | jq '[.[] | . + {classification: "new", baseline_pass_rate: null, delta: null}]'
    return
  fi

  # Read baseline tasks
  local baseline_tasks
  baseline_tasks="$(yq -o=json '.tasks' "$baseline_file")"

  echo "$current_json" | jq --argjson baseline "$baseline_tasks" --argjson threshold "$threshold" '
    . as $current |
    [
      .[] |
      .task_id as $tid |
      ($baseline[$tid] // null) as $bl |
      if $bl == null then
        . + {classification: "new", baseline_pass_rate: null, delta: null}
      elif $bl.status == "quarantined" then
        . + {classification: "quarantined", baseline_pass_rate: $bl.pass_rate, delta: (.pass_rate - $bl.pass_rate)}
      elif .pass_rate >= $bl.pass_rate then
        if .pass_rate > $bl.pass_rate then
          . + {classification: "improvement", baseline_pass_rate: $bl.pass_rate, delta: (.pass_rate - $bl.pass_rate)}
        else
          . + {classification: "pass", baseline_pass_rate: $bl.pass_rate, delta: 0}
        end
      elif (.pass_rate < ($bl.pass_rate - $threshold)) then
        . + {classification: "regression", baseline_pass_rate: $bl.pass_rate, delta: (.pass_rate - $bl.pass_rate)}
      else
        . + {classification: "degraded", baseline_pass_rate: $bl.pass_rate, delta: (.pass_rate - $bl.pass_rate)}
      end
    ] +
    # Find missing tasks (in baseline but not in current)
    [
      $baseline | to_entries[] |
      .key as $tid |
      .value as $bl |
      if ($current | map(.task_id) | index($tid)) == null then
        {task_id: $tid, trials: 0, passes: 0, pass_rate: 0, mean_score: 0, status: $bl.status, classification: "missing", baseline_pass_rate: $bl.pass_rate, delta: (0 - $bl.pass_rate)}
      else
        empty
      end
    ]
  '
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
