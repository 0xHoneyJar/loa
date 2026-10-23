#!/usr/bin/env bash
# report.sh — CLI report for Loa Eval results
# Exit codes: 0 = success, 2 = error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: report.sh --run-dir <dir> [--comparison <json>] [--no-color]
       report.sh --arms [--suite S] [--partial] [--results-dir <dir>] [--out <file>] [--date YYYY-MM-DD]

Options:
  --run-dir <dir>       Run directory with results.jsonl and run-meta.json
  --comparison <json>   Comparison JSON from compare.sh
  --no-color            Disable color output

Control arms (cycle-129 FR-2, SDD D-2.3):
  --arms                Write the control-arm report from run-arms.sh results
                        (default dir evals/results/arms/<suite>/) to
                        evals/results/arms-report-<date>.md: per-arm recall
                        (mean, min, max, spread), refuted share, tokens per
                        call, the bootstrap interval of the recall drop, the
                        pre-registered verdict and the missed labels
  --suite S             review-recall or audit-recall (default: both present)
  --partial             Write even when STATUS.json is not `complete`; the
                        header says so and every verdict reads inconclusive

Exit codes:
  0  Success
  1  (--arms) refused: a suite's STATUS.json is not complete and no --partial
  2  Error
USAGE
  exit 2
}

# --- control-arm report (cycle-129 FR-2) ---
if [[ " $* " == *" --arms "* ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  a_suite="" a_partial=() a_root="$REPO_ROOT/evals/results/arms" a_out="" a_date="$(date -u +%Y-%m-%d)"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --arms) shift ;;
      --suite) a_suite="${2:-}"; shift 2 ;;
      --partial) a_partial=(--partial); shift ;;
      --results-dir) a_root="${2:-}"; shift 2 ;;
      --out) a_out="${2:-}"; shift 2 ;;
      --date) a_date="${2:-}"; shift 2 ;;
      --help|-h) usage ;;
      *) echo "ERROR: Unknown option for --arms: $1" >&2; exit 2 ;;
    esac
  done
  case "$a_suite" in ""|review-recall|audit-recall) ;; *) echo "ERROR: --suite must be review-recall or audit-recall" >&2; exit 2 ;; esac
  [[ "$a_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "ERROR: --date must be YYYY-MM-DD" >&2; exit 2; }
  [[ -n "$a_out" ]] || a_out="$REPO_ROOT/evals/results/arms-report-$a_date.md"
  exec python3 -I "$SCRIPT_DIR/arms-report.py" --results-root "$a_root" --suites-dir "$REPO_ROOT/evals/suites" \
    --suites "$a_suite" --out "$a_out" --date "$a_date" ${a_partial[@]+"${a_partial[@]}"}
fi

# --- Colors ---
setup_colors() {
  if [[ "${NO_COLOR:-}" == "true" ]] || [[ ! -t 1 ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" NC="" BOLD=""
  else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
    BOLD='\033[1m'
  fi
}

# --- Parse args ---
RUN_DIR=""
COMPARISON=""
NO_COLOR=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --comparison) COMPARISON="$2"; shift 2 ;;
    --no-color) NO_COLOR=true; shift ;;
    --help|-h) usage ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ "$NO_COLOR" == "true" ]] && export NO_COLOR=true
setup_colors

if [[ -z "$RUN_DIR" ]]; then
  echo "ERROR: --run-dir required" >&2
  exit 2
fi

if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR: Run directory not found: $RUN_DIR" >&2
  exit 2
fi

# --- Read run metadata ---
meta_file="$RUN_DIR/run-meta.json"
results_file="$RUN_DIR/results.jsonl"

if [[ ! -f "$meta_file" ]]; then
  echo "ERROR: run-meta.json not found in $RUN_DIR" >&2
  exit 2
fi

run_id="$(jq -r '.run_id' "$meta_file")"
suite="$(jq -r '.suite // "default"' "$meta_file")"
duration_ms="$(jq -r '.duration_ms // 0' "$meta_file")"
model="$(jq -r '.model_version // "unknown"' "$meta_file")"
git_sha="$(jq -r '.git_sha // "unknown"' "$meta_file")"
git_branch="$(jq -r '.git_branch // "unknown"' "$meta_file")"
tasks_total="$(jq -r '.tasks_total // 0' "$meta_file")"
tasks_passed="$(jq -r '.tasks_passed // 0' "$meta_file")"
tasks_failed="$(jq -r '.tasks_failed // 0' "$meta_file")"
tasks_error="$(jq -r '.tasks_error // 0' "$meta_file")"

# Format duration
duration_sec=$((duration_ms / 1000))
duration_min=$((duration_sec / 60))
duration_rem=$((duration_sec % 60))
duration_fmt="${duration_min}m ${duration_rem}s"

# --- Print report ---
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  EVAL RESULTS — ${suite}${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Run ID:    ${CYAN}${run_id}${NC}"
echo -e "  Duration:  ${duration_fmt}"
echo -e "  Model:     ${model}"
echo -e "  Git SHA:   ${git_sha} (${git_branch})"
echo ""

# --- Summary from comparison data or results ---
if [[ -n "$COMPARISON" && -f "$COMPARISON" ]]; then
  regressions="$(jq '.summary.regressions // 0' "$COMPARISON")"
  improvements="$(jq '.summary.improvements // 0' "$COMPARISON")"
  passes="$(jq '.summary.passes // 0' "$COMPARISON")"
  new_count="$(jq '.summary.new // 0' "$COMPARISON")"
  quarantined="$(jq '.summary.quarantined // 0' "$COMPARISON")"

  echo -e "  ${BOLD}Summary:${NC}"
  echo -e "    ${GREEN}Pass:${NC}        $passes"
  echo -e "    ${RED}Fail:${NC}        $tasks_failed"
  echo -e "    ${RED}Regression:${NC}  $regressions"
  echo -e "    ${BLUE}New:${NC}         $new_count"
  echo -e "    ${YELLOW}Quarantined:${NC} $quarantined"

  # Regressions detail
  if [[ "$regressions" -gt 0 ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}Regressions:${NC}"
    jq -r '.results[] | select(.classification == "regression") |
      "    \(.task_id)  \(.baseline_pass_rate * 100 | floor)% → \(.pass_rate * 100 | floor)%  (\(.delta * 100 | floor)%)"' "$COMPARISON" 2>/dev/null || true
  fi

  # Improvements detail
  if [[ "$improvements" -gt 0 ]]; then
    echo ""
    echo -e "  ${GREEN}${BOLD}Improvements:${NC}"
    jq -r '.results[] | select(.classification == "improvement") |
      "    \(.task_id)  \(.baseline_pass_rate * 100 | floor)% → \(.pass_rate * 100 | floor)%  (+\(.delta * 100 | floor)%)"' "$COMPARISON" 2>/dev/null || true
  fi
else
  echo -e "  ${BOLD}Summary:${NC}"
  echo -e "    ${GREEN}Pass:${NC}  $tasks_passed"
  echo -e "    ${RED}Fail:${NC}  $tasks_failed"
  echo -e "    Error: $tasks_error"
  echo -e "    Total: $tasks_total"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
