#!/usr/bin/env bash
# pr-comment.sh — Generate and post structured PR comment with eval results
# Exit codes: 0 = success, 2 = error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage: pr-comment.sh [options]

Options:
  --run-dir <dir>         Run directory with results and metadata
  --comparison <file>     Comparison JSON from compare.sh
  --pr <number>           PR number to comment on
  --repo <owner/repo>     Repository (default: from git remote)
  --dry-run               Print comment without posting
  --incomplete            Mark as incomplete run
  --model-skew <text>     Model version skew warning

Exit codes:
  0  Success
  2  Error
USAGE
  exit 2
}

# --- Parse args ---
RUN_DIR=""
COMPARISON=""
PR_NUMBER=""
REPO=""
DRY_RUN=false
INCOMPLETE=false
MODEL_SKEW=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --comparison) COMPARISON="$2"; shift 2 ;;
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --incomplete) INCOMPLETE=true; shift ;;
    --model-skew) MODEL_SKEW="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
  esac
done

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
if [[ ! -f "$meta_file" ]]; then
  echo "ERROR: run-meta.json not found" >&2
  exit 2
fi

run_id="$(jq -r '.run_id' "$meta_file")"
suite="$(jq -r '.suite // "default"' "$meta_file")"
duration_ms="$(jq -r '.duration_ms // 0' "$meta_file")"
model="$(jq -r '.model_version // "unknown"' "$meta_file")"
git_sha="$(jq -r '.git_sha // "unknown"' "$meta_file")"
tasks_total="$(jq -r '.tasks_total // 0' "$meta_file")"
tasks_passed="$(jq -r '.tasks_passed // 0' "$meta_file")"
tasks_failed="$(jq -r '.tasks_failed // 0' "$meta_file")"
tasks_error="$(jq -r '.tasks_error // 0' "$meta_file")"

# Format duration
duration_sec=$((duration_ms / 1000))
duration_min=$((duration_sec / 60))
duration_rem=$((duration_sec % 60))
duration_fmt="${duration_min}m ${duration_rem}s"

# --- Read comparison data ---
regressions=0
improvements=0
passes=0
new_count=0
quarantined=0

if [[ -n "$COMPARISON" && -f "$COMPARISON" ]]; then
  regressions="$(jq '.summary.regressions // 0' "$COMPARISON")"
  improvements="$(jq '.summary.improvements // 0' "$COMPARISON")"
  passes="$(jq '.summary.passes // 0' "$COMPARISON")"
  new_count="$(jq '.summary.new // 0' "$COMPARISON")"
  quarantined="$(jq '.summary.quarantined // 0' "$COMPARISON")"
fi

# --- Determine status emoji ---
if [[ "$INCOMPLETE" == "true" ]]; then
  status_emoji="⚠️"
  status_text="INCOMPLETE"
elif [[ "$regressions" -gt 0 ]]; then
  status_emoji="❌"
  status_text="REGRESSIONS DETECTED"
elif [[ "$tasks_failed" -gt 0 ]]; then
  status_emoji="⚠️"
  status_text="FAILURES DETECTED"
else
  status_emoji="✅"
  status_text="ALL PASS"
fi

# --- Generate comment body ---
comment_body="## ${status_emoji} Eval Results — ${suite}

| Metric | Value |
|--------|-------|
| **Status** | ${status_text} |
| **Run ID** | \`${run_id}\` |
| **Duration** | ${duration_fmt} |
| **Model** | ${model} |
| **Git SHA** | \`${git_sha}\` |

### Summary

| Category | Count |
|----------|-------|
| ✅ Pass | ${passes} |
| ❌ Fail | ${tasks_failed} |
| 🔴 Regression | ${regressions} |
| 🆕 New | ${new_count} |
| ⏭️ Quarantined | ${quarantined} |
| **Total** | **${tasks_total}** |"

# Add regression details
if [[ "$regressions" -gt 0 && -n "$COMPARISON" && -f "$COMPARISON" ]]; then
  regression_table="$(jq -r '.results[] | select(.classification == "regression") |
    "| \(.task_id) | \(.baseline_pass_rate * 100 | floor)% | \(.pass_rate * 100 | floor)% | \(.delta * 100 | floor)% |"
  ' "$COMPARISON" 2>/dev/null || true)"

  if [[ -n "$regression_table" ]]; then
    comment_body+="

### 🔴 Regressions

| Task | Baseline | Current | Delta |
|------|----------|---------|-------|
${regression_table}"
  fi
fi

# Add improvement details
if [[ "$improvements" -gt 0 && -n "$COMPARISON" && -f "$COMPARISON" ]]; then
  improvement_table="$(jq -r '.results[] | select(.classification == "improvement") |
    "| \(.task_id) | \(.baseline_pass_rate * 100 | floor)% | \(.pass_rate * 100 | floor)% | +\(.delta * 100 | floor)% |"
  ' "$COMPARISON" 2>/dev/null || true)"

  if [[ -n "$improvement_table" ]]; then
    comment_body+="

### ✅ Improvements

| Task | Baseline | Current | Delta |
|------|----------|---------|-------|
${improvement_table}"
  fi
fi

# Add new tasks
if [[ "$new_count" -gt 0 && -n "$COMPARISON" && -f "$COMPARISON" ]]; then
  new_list="$(jq -r '.results[] | select(.classification == "new") |
    "- \(.task_id) — \(.pass_rate * 100 | floor)% pass rate"
  ' "$COMPARISON" 2>/dev/null || true)"

  if [[ -n "$new_list" ]]; then
    comment_body+="

### 🆕 New Tasks

${new_list}"
  fi
fi

# Model version skew warning
if [[ -n "$MODEL_SKEW" ]]; then
  comment_body+="

> ⚠️ **Model Version Skew**: ${MODEL_SKEW}
> Results are advisory only. Consider updating baselines for the new model."
fi

# Incomplete run warning
if [[ "$INCOMPLETE" == "true" ]]; then
  comment_body+="

> ⚠️ **Incomplete Run**: This eval run did not complete fully. Results may be partial."
fi

# Full details in collapsible
if [[ -n "$COMPARISON" && -f "$COMPARISON" ]]; then
  full_details="$(jq -r '.results[] |
    "| \(.task_id) | \(.classification) | \(.pass_rate * 100 | floor)% | \(.mean_score | floor) | \(.trials) |"
  ' "$COMPARISON" 2>/dev/null || true)"

  if [[ -n "$full_details" ]]; then
    comment_body+="

<details>
<summary>Full Results (${tasks_total} tasks)</summary>

| Task | Status | Pass Rate | Score | Trials |
|------|--------|-----------|-------|--------|
${full_details}

</details>"
  fi
fi

comment_body+="

---
*Generated by [Loa Eval Sandbox](https://github.com/0xHoneyJar/loa) — Run \`${run_id}\`*"

# --- Post or print ---
if [[ "$DRY_RUN" == "true" ]]; then
  echo "$comment_body"
  exit 0
fi

if [[ -z "$PR_NUMBER" ]]; then
  echo "ERROR: --pr required for posting (use --dry-run to preview)" >&2
  exit 2
fi

# Resolve repo
if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")"
  if [[ -z "$REPO" ]]; then
    echo "ERROR: Could not determine repository. Use --repo flag." >&2
    exit 2
  fi
fi

# Post comment via gh
echo "$comment_body" | gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file -

echo "Comment posted to PR #${PR_NUMBER}" >&2
