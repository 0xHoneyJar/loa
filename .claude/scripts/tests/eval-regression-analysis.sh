#!/usr/bin/env bash
# eval-regression-analysis.sh — Analyze eval regression pass rate patterns
# Version: 1.0.0
#
# Bridgebuilder Part I flagged 10 regression eval tasks showing 50% pass rate.
# This script runs each task multiple times to classify the failure pattern:
#   HARNESS_BUG: trial 1 always passes, trial 2 always fails (systematic)
#   FLAKY: randomly passes/fails across trials (non-deterministic)
#   REGRESSION: always fails (deterministic failure)
#   HEALTHY: always passes (no issue)
#
# Usage:
#   .claude/scripts/tests/eval-regression-analysis.sh [OPTIONS]
#
# Options:
#   --trials N         Number of trials per task (default: 4)
#   --task ID          Analyze a single task (default: all regression tasks)
#   --json             Output JSON only
#   --dry-run          Show what would be analyzed without running
#   --help             Show usage
#
# Exit Codes:
#   0 - Analysis complete, results saved
#   1 - Infrastructure error
#   2 - No regression tasks found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EVALS_DIR="$REPO_ROOT/evals"
HARNESS="$EVALS_DIR/harness/run-eval.sh"
RESULTS_DIR="$REPO_ROOT/.run"
OUTPUT_FILE="$RESULTS_DIR/eval-regression-analysis.json"

TRIALS=4
SINGLE_TASK=""
JSON_OUT="false"
DRY_RUN="false"

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<'USAGE'
Usage: eval-regression-analysis.sh [OPTIONS]

Analyze regression eval pass rate patterns to classify failures.

Options:
  --trials N         Number of trials per task (default: 4)
  --task ID          Analyze a single task
  --json             JSON output only
  --dry-run          Show analysis plan without running
  --help             Show usage

Classifications:
  HARNESS_BUG  - Systematic pattern (e.g., trial 1 pass, trial 2 fail)
  FLAKY        - Random pass/fail (non-deterministic)
  REGRESSION   - Always fails (deterministic)
  HEALTHY      - Always passes (no issue)
USAGE
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --trials)   TRIALS="$2"; shift 2 ;;
        --task)     SINGLE_TASK="$2"; shift 2 ;;
        --json)     JSON_OUT="true"; shift ;;
        --dry-run)  DRY_RUN="true"; shift ;;
        --help)     usage; exit 0 ;;
        *)          echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# =============================================================================
# Pre-flight
# =============================================================================

if [[ ! -x "$HARNESS" ]]; then
    echo "ERROR: Eval harness not found or not executable: $HARNESS"
    exit 1
fi

# Collect regression task IDs
TASK_DIR="$EVALS_DIR/tasks/regression"
if [[ ! -d "$TASK_DIR" ]]; then
    echo "ERROR: Regression tasks directory not found: $TASK_DIR"
    exit 2
fi

if [[ -n "$SINGLE_TASK" ]]; then
    TASK_IDS=("$SINGLE_TASK")
else
    TASK_IDS=()
    for f in "$TASK_DIR"/*.yaml; do
        [[ -f "$f" ]] || continue
        tid=$(yq '.id' "$f" 2>/dev/null || basename "$f" .yaml)
        TASK_IDS+=("$tid")
    done
fi

if [[ ${#TASK_IDS[@]} -eq 0 ]]; then
    echo "ERROR: No regression tasks found"
    exit 2
fi

[[ "$JSON_OUT" != "true" ]] && echo "Analyzing ${#TASK_IDS[@]} regression tasks with $TRIALS trials each"

# =============================================================================
# Dry Run
# =============================================================================

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "Tasks to analyze:"
    for tid in "${TASK_IDS[@]}"; do
        echo "  - $tid ($TRIALS trials)"
    done
    echo ""
    echo "Total eval runs: $((${#TASK_IDS[@]} * TRIALS))"
    echo "Output: $OUTPUT_FILE"
    exit 0
fi

# =============================================================================
# Analysis
# =============================================================================

mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TASK_RESULTS=()

for tid in "${TASK_IDS[@]}"; do
    [[ "$JSON_OUT" != "true" ]] && echo ""
    [[ "$JSON_OUT" != "true" ]] && echo "[$tid] Running $TRIALS trials..."

    PASSES=0
    FAILURES=0
    TRIAL_RESULTS=()

    for t in $(seq 1 "$TRIALS"); do
        # Run single task via harness
        if "$HARNESS" --task "$tid" --trusted --json 2>/dev/null | \
           jq -e '.tasks[0].composite.pass == true' &>/dev/null; then
            TRIAL_RESULTS+=("pass")
            PASSES=$((PASSES + 1))
            [[ "$JSON_OUT" != "true" ]] && echo "  Trial $t: PASS"
        else
            TRIAL_RESULTS+=("fail")
            FAILURES=$((FAILURES + 1))
            [[ "$JSON_OUT" != "true" ]] && echo "  Trial $t: FAIL"
        fi
    done

    # Classify the pattern
    PASS_RATE=$(echo "scale=2; $PASSES / $TRIALS" | bc)

    if [[ "$PASSES" -eq "$TRIALS" ]]; then
        CLASSIFICATION="HEALTHY"
    elif [[ "$PASSES" -eq 0 ]]; then
        CLASSIFICATION="REGRESSION"
    else
        # Check for systematic pattern: alternating pass/fail
        SYSTEMATIC="true"
        FIRST="${TRIAL_RESULTS[0]}"
        for i in $(seq 1 $((${#TRIAL_RESULTS[@]} - 1))); do
            if [[ $((i % 2)) -eq 0 ]]; then
                # Even indices should match first
                [[ "${TRIAL_RESULTS[$i]}" != "$FIRST" ]] && SYSTEMATIC="false"
            else
                # Odd indices should differ from first
                if [[ "$FIRST" == "pass" ]]; then
                    [[ "${TRIAL_RESULTS[$i]}" != "fail" ]] && SYSTEMATIC="false"
                else
                    [[ "${TRIAL_RESULTS[$i]}" != "pass" ]] && SYSTEMATIC="false"
                fi
            fi
        done

        if [[ "$SYSTEMATIC" == "true" && "$TRIALS" -ge 4 ]]; then
            CLASSIFICATION="HARNESS_BUG"
        else
            CLASSIFICATION="FLAKY"
        fi
    fi

    [[ "$JSON_OUT" != "true" ]] && echo "  Classification: $CLASSIFICATION (pass rate: $PASS_RATE)"

    # Build trial results JSON array
    TRIALS_JSON="["
    for i in "${!TRIAL_RESULTS[@]}"; do
        [[ $i -gt 0 ]] && TRIALS_JSON+=","
        TRIALS_JSON+="\"${TRIAL_RESULTS[$i]}\""
    done
    TRIALS_JSON+="]"

    TASK_RESULTS+=("$(jq -nc \
        --arg task_id "$tid" \
        --arg classification "$CLASSIFICATION" \
        --argjson passes "$PASSES" \
        --argjson failures "$FAILURES" \
        --arg pass_rate "$PASS_RATE" \
        --argjson trials "$TRIALS_JSON" \
        '{task_id: $task_id, classification: $classification, passes: $passes, failures: $failures, pass_rate: $pass_rate, trials: $trials}'
    )")
done

# =============================================================================
# Output
# =============================================================================

# Build full results JSON
RESULTS_JSON="["
for i in "${!TASK_RESULTS[@]}"; do
    [[ $i -gt 0 ]] && RESULTS_JSON+=","
    RESULTS_JSON+="${TASK_RESULTS[$i]}"
done
RESULTS_JSON+="]"

# Count classifications
HARNESS_BUG_COUNT=$(echo "$RESULTS_JSON" | jq '[.[] | select(.classification == "HARNESS_BUG")] | length')
FLAKY_COUNT=$(echo "$RESULTS_JSON" | jq '[.[] | select(.classification == "FLAKY")] | length')
REGRESSION_COUNT=$(echo "$RESULTS_JSON" | jq '[.[] | select(.classification == "REGRESSION")] | length')
HEALTHY_COUNT=$(echo "$RESULTS_JSON" | jq '[.[] | select(.classification == "HEALTHY")] | length')

FULL_OUTPUT=$(jq -nc \
    --arg timestamp "$TIMESTAMP" \
    --argjson trials_per_task "$TRIALS" \
    --argjson total_tasks "${#TASK_IDS[@]}" \
    --argjson harness_bug "$HARNESS_BUG_COUNT" \
    --argjson flaky "$FLAKY_COUNT" \
    --argjson regression "$REGRESSION_COUNT" \
    --argjson healthy "$HEALTHY_COUNT" \
    --argjson tasks "$RESULTS_JSON" \
    '{
        timestamp: $timestamp,
        trials_per_task: $trials_per_task,
        total_tasks: $total_tasks,
        summary: {
            harness_bug: $harness_bug,
            flaky: $flaky,
            regression: $regression,
            healthy: $healthy
        },
        tasks: $tasks
    }')

# Save to file
echo "$FULL_OUTPUT" | jq '.' > "$OUTPUT_FILE"

if [[ "$JSON_OUT" == "true" ]]; then
    echo "$FULL_OUTPUT" | jq '.'
else
    echo ""
    echo "════════════════════════════════════════"
    echo "Analysis Summary"
    echo "════════════════════════════════════════"
    echo "  HARNESS_BUG: $HARNESS_BUG_COUNT"
    echo "  FLAKY:       $FLAKY_COUNT"
    echo "  REGRESSION:  $REGRESSION_COUNT"
    echo "  HEALTHY:     $HEALTHY_COUNT"
    echo ""
    echo "Results saved to: $OUTPUT_FILE"
fi

exit 0
