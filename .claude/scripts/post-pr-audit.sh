#!/usr/bin/env bash
# post-pr-audit.sh - Consolidated PR Audit for Post-PR Validation Loop
# Part of Loa Framework v1.25.0
#
# Fetches PR changes and runs security/quality audit with fix classification.
#
# Usage:
#   post-pr-audit.sh --pr-url <url> [--context-dir <dir>] [--dry-run]
#
# Exit codes:
#   0 - APPROVED (no issues found)
#   1 - CHANGES_REQUIRED (auto-fixable issues found)
#   2 - ESCALATED (complex issues requiring human review)
#   3 - ERROR (script error)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_SCRIPT="${SCRIPT_DIR}/post-pr-state.sh"

# Retry policy (Flatline IMP-003)
readonly MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
readonly BACKOFF_DELAYS=(1 2 4)  # Exponential backoff in seconds
readonly TIMEOUT_PER_ATTEMPT="${TIMEOUT_PER_ATTEMPT:-30}"

# Output directories
readonly BASE_CONTEXT_DIR="${BASE_CONTEXT_DIR:-grimoires/loa/a2a}"

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

log_debug() {
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

# Retry with exponential backoff (Flatline IMP-003)
# H-1 fix: Use array-based execution to avoid bash -c string injection
# Usage: retry_with_backoff output_file cmd [args...]
retry_with_backoff() {
  local output_file="$1"
  shift
  local -a cmd_array=("$@")
  local attempt=1

  while (( attempt <= MAX_ATTEMPTS )); do
    log_debug "Attempt $attempt/$MAX_ATTEMPTS: ${cmd_array[*]}"

    local result=0
    # Execute command array directly, redirect output to file
    if timeout "$TIMEOUT_PER_ATTEMPT" "${cmd_array[@]}" > "$output_file" 2>/dev/null; then
      return 0
    else
      result=$?
    fi

    if (( attempt < MAX_ATTEMPTS )); then
      local delay="${BACKOFF_DELAYS[$((attempt - 1))]:-4}"
      log_info "Attempt $attempt failed, retrying in ${delay}s..."
      sleep "$delay"
    fi

    ((++attempt))
  done

  log_error "All $MAX_ATTEMPTS attempts failed"
  return 1
}

# ============================================================================
# Finding Identity Algorithm (Flatline IMP-004)
# ============================================================================

# Generate stable 16-char hash for a finding
# Uses: category, rule_id, file, normalized_line, severity
finding_identity() {
  local category="${1:-}"
  local rule_id="${2:-}"
  local file="${3:-}"
  local line="${4:-0}"
  local severity="${5:-}"

  # Normalize line number to ±5 tolerance (round to nearest 10)
  local normalized_line
  normalized_line=$(( (line / 10) * 10 ))

  # Build identity string
  local identity_str="${category}|${rule_id}|${file}|${normalized_line}|${severity}"

  # Generate SHA256 and take first 16 chars
  echo -n "$identity_str" | sha256sum | cut -c1-16
}

# Check if finding identity is already known (circuit breaker)
is_known_finding() {
  local identity="$1"
  local state_file="${2:-}"

  if [[ -z "$state_file" ]] || [[ ! -f "$state_file" ]]; then
    return 1
  fi

  # Check if identity is in finding_identities array
  if jq -e --arg id "$identity" '.audit.finding_identities | index($id)' "$state_file" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

# Add finding identity to state
add_finding_identity() {
  local identity="$1"

  if [[ -x "$STATE_SCRIPT" ]]; then
    # Get current identities
    local current
    current=$("$STATE_SCRIPT" get "audit.finding_identities" 2>/dev/null || echo "[]")

    # Add new identity
    local updated
    updated=$(echo "$current" | jq --arg id "$identity" '. + [$id] | unique')

    # Update state (using jq to set array)
    local state_file
    state_file=$("$STATE_SCRIPT" get 2>/dev/null | jq -r 'empty' 2>/dev/null && echo ".run/post-pr-state.json" || echo "")

    if [[ -n "$state_file" ]] && [[ -f ".run/post-pr-state.json" ]]; then
      jq --argjson ids "$updated" '.audit.finding_identities = $ids' ".run/post-pr-state.json" > ".run/post-pr-state.json.tmp"
      mv ".run/post-pr-state.json.tmp" ".run/post-pr-state.json"
    fi
  fi
}

# ============================================================================
# PR Metadata Fetching
# ============================================================================

fetch_pr_metadata() {
  local pr_url="$1"
  local output_file="$2"

  # Extract owner/repo/number from URL
  local pr_path
  pr_path=$(echo "$pr_url" | sed 's|https://github.com/||')
  local owner repo number
  owner=$(echo "$pr_path" | cut -d'/' -f1)
  repo=$(echo "$pr_path" | cut -d'/' -f2)
  number=$(echo "$pr_path" | cut -d'/' -f4)

  log_info "Fetching PR #$number from $owner/$repo"

  # Fetch with retry - H-1 fix: use array-based execution
  if retry_with_backoff "$output_file" gh pr view "$number" --repo "$owner/$repo" \
      --json number,title,body,files,additions,deletions,changedFiles,baseRefName,headRefName,state; then
    log_info "PR metadata fetched successfully"
    return 0
  else
    log_error "Failed to fetch PR metadata after $MAX_ATTEMPTS attempts"
    return 1
  fi
}

# Get list of changed files from PR metadata
get_changed_files() {
  local metadata_file="$1"

  jq -r '.files[].path' "$metadata_file" 2>/dev/null || echo ""
}

# ============================================================================
# Audit Execution
# ============================================================================

# Create audit context directory with PR information
create_audit_context() {
  local pr_number="$1"
  local metadata_file="$2"
  local context_dir="${BASE_CONTEXT_DIR}/pr-${pr_number}"

  mkdir -p "$context_dir"

  # Copy metadata
  cp "$metadata_file" "${context_dir}/pr-metadata.json"

  # Create summary
  local title body additions deletions
  title=$(jq -r '.title' "$metadata_file")
  body=$(jq -r '.body // "No description"' "$metadata_file")
  additions=$(jq -r '.additions' "$metadata_file")
  deletions=$(jq -r '.deletions' "$metadata_file")

  cat > "${context_dir}/pr-summary.md" << EOF
# PR #${pr_number}: ${title}

## Stats
- Additions: ${additions}
- Deletions: ${deletions}

## Description
${body}

## Changed Files
$(jq -r '.files[].path' "$metadata_file" | sed 's/^/- /')
EOF

  echo "$context_dir"
}

# Run audit and classify findings
run_audit() {
  local context_dir="$1"
  local findings_file="${context_dir}/audit-findings.json"
  local report_file="${context_dir}/audit-report.md"

  log_info "Running audit on PR changes..."

  # Get changed files
  local changed_files
  changed_files=$(jq -r '.files[].path' "${context_dir}/pr-metadata.json" 2>/dev/null | tr '\n' ' ')

  if [[ -z "$changed_files" ]]; then
    log_info "No files changed, audit APPROVED"
    echo '{"findings": [], "verdict": "APPROVED"}' > "$findings_file"
    return 0
  fi

  # Initialize findings array
  local findings='[]'
  local has_auto_fixable=false
  local has_complex=false

  # Run basic checks on each file
  for file in $changed_files; do
    if [[ ! -f "$file" ]]; then
      continue
    fi

    # Check for common security issues
    # 1. Hardcoded secrets
    if grep -nE "(password|secret|api_key|apikey|token)\s*[:=]\s*['\"][^'\"]+['\"]" "$file" 2>/dev/null; then
      local line
      line=$(grep -nE "(password|secret|api_key|apikey|token)\s*[:=]\s*['\"][^'\"]+['\"]" "$file" | head -1 | cut -d: -f1)
      local identity
      identity=$(finding_identity "security" "hardcoded-secret" "$file" "$line" "high")

      findings=$(echo "$findings" | jq --arg f "$file" --arg l "$line" --arg id "$identity" '. + [{
        "id": $id,
        "category": "security",
        "rule_id": "hardcoded-secret",
        "file": $f,
        "line": ($l | tonumber),
        "severity": "high",
        "message": "Potential hardcoded secret detected",
        "auto_fixable": false
      }]')
      has_complex=true
      add_finding_identity "$identity"
    fi

    # 2. Console.log in production code (auto-fixable)
    if [[ "$file" == *.ts || "$file" == *.js ]] && [[ "$file" != *.test.* ]] && [[ "$file" != *.spec.* ]]; then
      if grep -nE "console\.(log|debug|info)" "$file" 2>/dev/null | grep -v "// eslint-disable"; then
        local line
        line=$(grep -nE "console\.(log|debug|info)" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        local identity
        identity=$(finding_identity "quality" "console-log" "$file" "$line" "low")

        findings=$(echo "$findings" | jq --arg f "$file" --arg l "$line" --arg id "$identity" '. + [{
          "id": $id,
          "category": "quality",
          "rule_id": "console-log",
          "file": $f,
          "line": ($l | tonumber),
          "severity": "low",
          "message": "Console statement in production code",
          "auto_fixable": true,
          "fix_hint": "Remove or replace with proper logging"
        }]')
        has_auto_fixable=true
        add_finding_identity "$identity"
      fi
    fi

    # 3. TODO/FIXME comments (auto-fixable)
    if grep -nE "(TODO|FIXME|XXX|HACK):" "$file" 2>/dev/null; then
      local line
      line=$(grep -nE "(TODO|FIXME|XXX|HACK):" "$file" 2>/dev/null | head -1 | cut -d: -f1)
      local identity
      identity=$(finding_identity "quality" "todo-comment" "$file" "$line" "low")

      findings=$(echo "$findings" | jq --arg f "$file" --arg l "$line" --arg id "$identity" '. + [{
        "id": $id,
        "category": "quality",
        "rule_id": "todo-comment",
        "file": $f,
        "line": ($l | tonumber),
        "severity": "low",
        "message": "Unresolved TODO/FIXME comment",
        "auto_fixable": true,
        "fix_hint": "Resolve or remove the comment"
      }]')
      has_auto_fixable=true
      add_finding_identity "$identity"
    fi

    # 4. Missing error handling in catch blocks
    if [[ "$file" == *.ts || "$file" == *.js ]]; then
      if grep -nE "catch\s*\([^)]*\)\s*\{\s*\}" "$file" 2>/dev/null; then
        local line
        line=$(grep -nE "catch\s*\([^)]*\)\s*\{\s*\}" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        local identity
        identity=$(finding_identity "quality" "empty-catch" "$file" "$line" "medium")

        findings=$(echo "$findings" | jq --arg f "$file" --arg l "$line" --arg id "$identity" '. + [{
          "id": $id,
          "category": "quality",
          "rule_id": "empty-catch",
          "file": $f,
          "line": ($l | tonumber),
          "severity": "medium",
          "message": "Empty catch block - errors silently swallowed",
          "auto_fixable": false
        }]')
        has_complex=true
        add_finding_identity "$identity"
      fi
    fi
  done

  # Determine verdict
  local verdict="APPROVED"
  if [[ "$has_complex" == "true" ]]; then
    verdict="ESCALATED"
  elif [[ "$has_auto_fixable" == "true" ]]; then
    verdict="CHANGES_REQUIRED"
  fi

  # Save findings
  echo "$findings" | jq --arg v "$verdict" '{findings: ., verdict: $v}' > "$findings_file"

  # Generate report
  generate_audit_report "$findings_file" "$report_file"

  log_info "Audit complete: $verdict ($(echo "$findings" | jq 'length') findings)"

  return 0
}

# Generate markdown audit report
generate_audit_report() {
  local findings_file="$1"
  local report_file="$2"

  local verdict
  verdict=$(jq -r '.verdict' "$findings_file")
  local findings_count
  findings_count=$(jq '.findings | length' "$findings_file")

  cat > "$report_file" << EOF
# Audit Report

**Verdict:** ${verdict}
**Findings:** ${findings_count}
**Generated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Summary

EOF

  if (( findings_count == 0 )); then
    echo "No issues found. PR is approved." >> "$report_file"
  else
    # Group by category
    echo "### By Category" >> "$report_file"
    echo "" >> "$report_file"

    jq -r '.findings | group_by(.category) | .[] | "- **\(.[0].category)**: \(length) finding(s)"' "$findings_file" >> "$report_file"

    echo "" >> "$report_file"
    echo "### Findings" >> "$report_file"
    echo "" >> "$report_file"

    # List each finding
    jq -r '.findings[] | "#### [\(.severity | ascii_upcase)] \(.rule_id)\n- **File:** \(.file):\(.line)\n- **Message:** \(.message)\n- **Auto-fixable:** \(.auto_fixable)\n"' "$findings_file" >> "$report_file"
  fi
}

# ============================================================================
# Main
# ============================================================================

main() {
  local pr_url=""
  local context_dir=""
  local dry_run=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr-url)
        pr_url="$2"
        shift 2
        ;;
      --context-dir)
        context_dir="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --help|-h)
        echo "Usage: post-pr-audit.sh --pr-url <url> [--context-dir <dir>] [--dry-run]"
        echo ""
        echo "Exit codes:"
        echo "  0 - APPROVED"
        echo "  1 - CHANGES_REQUIRED"
        echo "  2 - ESCALATED"
        echo "  3 - ERROR"
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        exit 3
        ;;
    esac
  done

  # Validate arguments
  if [[ -z "$pr_url" ]]; then
    log_error "Missing required argument: --pr-url"
    exit 3
  fi

  # Extract PR number
  local pr_number
  pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')

  if [[ -z "$pr_number" ]]; then
    log_error "Could not extract PR number from URL: $pr_url"
    exit 3
  fi

  # Set context directory
  if [[ -z "$context_dir" ]]; then
    context_dir="${BASE_CONTEXT_DIR}/pr-${pr_number}"
  fi

  # Dry run
  if [[ "$dry_run" == "true" ]]; then
    echo "Would audit PR #$pr_number"
    echo "Context directory: $context_dir"
    exit 0
  fi

  # Create temp file for metadata
  local metadata_file
  metadata_file=$(mktemp)
  trap "rm -f '$metadata_file'" EXIT

  # Fetch PR metadata
  if ! fetch_pr_metadata "$pr_url" "$metadata_file"; then
    log_error "Failed to fetch PR metadata"
    exit 3
  fi

  # Create audit context
  context_dir=$(create_audit_context "$pr_number" "$metadata_file")
  log_info "Audit context: $context_dir"

  # Run audit
  run_audit "$context_dir"

  # Get verdict
  local verdict
  verdict=$(jq -r '.verdict' "${context_dir}/audit-findings.json")

  case "$verdict" in
    APPROVED)
      log_info "Audit APPROVED - no issues found"
      exit 0
      ;;
    CHANGES_REQUIRED)
      log_info "Audit requires changes - auto-fixable issues found"
      exit 1
      ;;
    ESCALATED)
      log_info "Audit ESCALATED - complex issues require human review"
      exit 2
      ;;
    *)
      log_error "Unknown verdict: $verdict"
      exit 3
      ;;
  esac
}

main "$@"
