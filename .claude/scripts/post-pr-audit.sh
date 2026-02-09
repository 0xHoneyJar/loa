#!/usr/bin/env bash
# post-pr-audit.sh - Bridgebuilder-Powered PR Audit for Post-PR Validation Loop
# Part of Loa Framework v1.32.0
#
# Phase 1: Deterministic fast-pass (secrets, console.log, empty catch)
# Phase 2: LLM-powered deep analysis via Bridgebuilder
#
# Usage:
#   post-pr-audit.sh --pr-url <url> [--context-dir <dir>] [--dry-run]
#
# Exit codes:
#   0 - APPROVED (no issues found)
#   1 - CHANGES_REQUIRED (findings above min_severity threshold)
#   2 - ESCALATED (fail_closed policy triggered on error)
#   3 - ERROR (script error)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_SCRIPT="${SCRIPT_DIR}/post-pr-state.sh"
readonly SKILL_DIR="${SCRIPT_DIR}/../skills/bridgebuilder-review"
readonly BB_ENTRY="${SKILL_DIR}/resources/entry.sh"

# Retry policy
readonly MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
readonly BACKOFF_DELAYS=(1 2 4)
readonly TIMEOUT_PER_ATTEMPT="${TIMEOUT_PER_ATTEMPT:-30}"

# Bridgebuilder timeout (IMP-001)
readonly BB_TIMEOUT="${BB_TIMEOUT:-120}"

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

log_warning() {
  echo "[WARN] $*" >&2
}

log_debug() {
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

# Retry with exponential backoff
# Usage: retry_with_backoff output_file cmd [args...]
retry_with_backoff() {
  local output_file="$1"
  shift
  local -a cmd_array=("$@")
  local attempt=1

  while (( attempt <= MAX_ATTEMPTS )); do
    log_debug "Attempt $attempt/$MAX_ATTEMPTS: ${cmd_array[*]}"

    local result=0
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
# Finding Identity Algorithm
# ============================================================================

finding_identity() {
  local category="${1:-}"
  local rule_id="${2:-}"
  local file="${3:-}"
  local line="${4:-0}"
  local severity="${5:-}"

  local normalized_line
  normalized_line=$(( (line / 10) * 10 ))

  local identity_str="${category}|${rule_id}|${file}|${normalized_line}|${severity}"
  echo -n "$identity_str" | sha256sum | cut -c1-16
}

is_known_finding() {
  local identity="$1"
  local state_file="${2:-}"

  if [[ -z "$state_file" ]] || [[ ! -f "$state_file" ]]; then
    return 1
  fi

  if jq -e --arg id "$identity" '.audit.finding_identities | index($id)' "$state_file" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

add_finding_identity() {
  local identity="$1"

  if [[ -x "$STATE_SCRIPT" ]]; then
    local current
    current=$("$STATE_SCRIPT" get "audit.finding_identities" 2>/dev/null || echo "[]")

    local updated
    updated=$(echo "$current" | jq --arg id "$identity" '. + [$id] | unique')

    if [[ -f ".run/post-pr-state.json" ]]; then
      jq --argjson ids "$updated" '.audit.finding_identities = $ids' ".run/post-pr-state.json" > ".run/post-pr-state.json.tmp"
      mv ".run/post-pr-state.json.tmp" ".run/post-pr-state.json"
    fi
  fi
}

# ============================================================================
# Failure Policy (SKP-001 / SDD §3.1)
# ============================================================================

# Resolve failure policy with environment-aware defaults
# Precedence: config override > environment default > hard default
resolve_failure_policy() {
  local phase="${1:-audit}"

  # 1. Explicit config takes precedence
  local explicit=""
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    explicit=$(yq ".post_pr_validation.phases.${phase}.failure_policy // \"\"" \
      .loa.config.yaml 2>/dev/null || echo "")
  fi

  if [[ -n "$explicit" ]]; then
    echo "$explicit"
    return
  fi

  # 2. Environment-aware default
  if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${CLAWDBOT_GATEWAY_TOKEN:-}" ]]; then
    echo "fail_closed"
  else
    echo "fail_open"
  fi
}

# Handle phase error — always creates degraded marker (NFR-1: never silent approval)
handle_phase_error() {
  local phase="$1"
  local error_msg="$2"
  local policy
  policy=$(resolve_failure_policy "$phase")

  log_warning "Phase error: $error_msg (policy: $policy)"

  # Always create degraded marker
  mkdir -p .run
  jq -n --arg phase "$phase" --arg reason "$error_msg" \
    --arg policy "$policy" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{phase: $phase, reason: $reason, policy: $policy, timestamp: $ts}' \
    > .run/post-pr-degraded.json

  if [[ "$policy" == "fail_closed" ]]; then
    log_error "fail_closed: blocking pipeline"
    exit 2
  else
    log_warning "fail_open: continuing with degraded marker"
    exit 0
  fi
}

# ============================================================================
# Provider Resolution
# ============================================================================

resolve_audit_provider() {
  local provider="bridgebuilder"
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    provider=$(yq '.post_pr_validation.phases.audit.provider // "bridgebuilder"' \
      .loa.config.yaml 2>/dev/null || echo "bridgebuilder")
  fi
  echo "$provider"
}

resolve_min_severity() {
  local min_severity="medium"
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    min_severity=$(yq '.post_pr_validation.phases.audit.min_severity // "medium"' \
      .loa.config.yaml 2>/dev/null || echo "medium")
  fi
  echo "$min_severity"
}

resolve_bb_timeout() {
  local timeout="$BB_TIMEOUT"
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    local cfg_timeout
    cfg_timeout=$(yq '.post_pr_validation.phases.audit.timeout_seconds // ""' \
      .loa.config.yaml 2>/dev/null || echo "")
    if [[ -n "$cfg_timeout" ]]; then
      timeout="$cfg_timeout"
    fi
  fi
  echo "$timeout"
}

# ============================================================================
# PR Metadata — Canonical Extraction (SKP-004)
# ============================================================================

# Verify gh CLI is installed and authenticated
verify_gh_auth() {
  if ! command -v gh >/dev/null 2>&1; then
    handle_phase_error "POST_PR_AUDIT" "gh CLI not installed"
  fi

  if ! gh auth status >/dev/null 2>&1; then
    handle_phase_error "POST_PR_AUDIT" "gh CLI not authenticated (run: gh auth login)"
  fi
}

# Extract PR number and repo from URL using gh (SKP-004: canonical, not URL parsing)
extract_pr_info() {
  local pr_url="$1"

  # Use gh pr view to canonically resolve PR info
  local pr_json
  pr_json=$(gh pr view "$pr_url" --json number,headRefName,baseRefName,url 2>&1) || {
    handle_phase_error "POST_PR_AUDIT" "gh pr view failed for $pr_url"
  }

  local pr_number
  pr_number=$(echo "$pr_json" | jq -r '.number')

  # Extract owner/repo from canonical URL
  local canonical_url
  canonical_url=$(echo "$pr_json" | jq -r '.url')
  local repo_name
  repo_name=$(echo "$canonical_url" | sed 's|https://github.com/||' | sed 's|/pull/[0-9]*||')

  if [[ -z "$pr_number" || "$pr_number" == "null" ]]; then
    handle_phase_error "POST_PR_AUDIT" "Could not extract PR number from $pr_url"
  fi

  echo "${pr_number}|${repo_name}"
}

fetch_pr_metadata() {
  local pr_url="$1"
  local output_file="$2"

  # Extract owner/repo from canonical URL for --repo flag
  local pr_info
  pr_info=$(extract_pr_info "$pr_url")
  local pr_number repo_name
  pr_number="${pr_info%%|*}"
  repo_name="${pr_info##*|}"

  log_info "Fetching PR #$pr_number from $repo_name"

  if retry_with_backoff "$output_file" gh pr view "$pr_number" --repo "$repo_name" \
      --json number,title,body,files,additions,deletions,changedFiles,baseRefName,headRefName,state; then
    log_info "PR metadata fetched successfully"
    return 0
  else
    log_error "Failed to fetch PR metadata after $MAX_ATTEMPTS attempts"
    return 1
  fi
}

# ============================================================================
# Phase 1: Deterministic Fast-Pass (SKP-003)
# ============================================================================

run_fast_checks() {
  local context_dir="$1"
  local findings_file="${context_dir}/fast-check-findings.json"

  log_info "Running deterministic fast-pass checks..."

  local changed_files
  changed_files=$(jq -r '.files[].path' "${context_dir}/pr-metadata.json" 2>/dev/null | tr '\n' ' ')

  if [[ -z "$changed_files" ]]; then
    log_info "No files changed, fast-pass APPROVED"
    echo '{"findings": [], "verdict": "APPROVED"}' > "$findings_file"
    return 0
  fi

  local findings='[]'
  local has_critical=false

  for file in $changed_files; do
    if [[ ! -f "$file" ]]; then
      continue
    fi

    # Check 1: Hardcoded secrets (critical — exit immediately)
    if grep -nE "(password|secret|api_key|apikey|token)\s*[:=]\s*['\"][^'\"]+['\"]" "$file" 2>/dev/null | head -1 | read -r match; then
      local line
      line=$(echo "$match" | cut -d: -f1)
      local identity
      identity=$(finding_identity "security" "hardcoded-secret" "$file" "$line" "critical")

      findings=$(echo "$findings" | jq --arg f "$file" --arg l "$line" --arg id "$identity" '. + [{
        "id": $id,
        "category": "security",
        "rule_id": "hardcoded-secret",
        "file": $f,
        "line": ($l | tonumber),
        "severity": "critical",
        "message": "Potential hardcoded secret detected",
        "auto_fixable": false
      }]')
      has_critical=true
      add_finding_identity "$identity"
    fi

    # Check 2: Console.log in production code
    if [[ "$file" == *.ts || "$file" == *.js ]] && [[ "$file" != *.test.* ]] && [[ "$file" != *.spec.* ]]; then
      if grep -nE "console\.(log|debug|info)" "$file" 2>/dev/null | grep -v "// eslint-disable" | head -1 | read -r match; then
        local line
        line=$(echo "$match" | cut -d: -f1)
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
          "auto_fixable": true
        }]')
        add_finding_identity "$identity"
      fi
    fi

    # Check 3: Empty catch blocks
    if [[ "$file" == *.ts || "$file" == *.js ]]; then
      if grep -nE "catch\s*\([^)]*\)\s*\{\s*\}" "$file" 2>/dev/null | head -1 | read -r match; then
        local line
        line=$(echo "$match" | cut -d: -f1)
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
        add_finding_identity "$identity"
      fi
    fi
  done

  local fast_count
  fast_count=$(echo "$findings" | jq 'length')
  log_info "Fast-pass complete: $fast_count findings"

  # Save fast-pass findings
  echo "$findings" | jq '{findings: ., fast_pass: true}' > "$findings_file"

  # If critical findings (secrets), exit immediately — no need for Bridgebuilder
  if [[ "$has_critical" == "true" ]]; then
    log_error "Critical finding (hardcoded secret) detected in fast-pass — blocking"
    return 1
  fi

  return 0
}

# ============================================================================
# Phase 2: Bridgebuilder Deep Analysis
# ============================================================================

validate_bb_output() {
  local output="$1"

  # Must be valid JSON with at minimum runId and reviewed fields
  if ! echo "$output" | jq -e '.runId and (.reviewed != null)' >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

run_bridgebuilder_audit() {
  local pr_url="$1"
  local context_dir="$2"

  # Extract PR info
  local pr_info
  pr_info=$(extract_pr_info "$pr_url")
  local pr_number repo_name
  pr_number="${pr_info%%|*}"
  repo_name="${pr_info##*|}"

  # Verify Bridgebuilder entry.sh exists
  if [[ ! -x "$BB_ENTRY" ]]; then
    handle_phase_error "POST_PR_AUDIT" "Bridgebuilder entry.sh not found or not executable at $BB_ENTRY"
  fi

  # Check ANTHROPIC_API_KEY
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    handle_phase_error "POST_PR_AUDIT" "ANTHROPIC_API_KEY not set — Bridgebuilder requires API access"
  fi

  log_info "Invoking Bridgebuilder on PR #$pr_number ($repo_name)..."

  local bb_timeout
  bb_timeout=$(resolve_bb_timeout)

  # Invoke Bridgebuilder — stdout is JSON RunSummary, stderr is diagnostics
  local bb_output=""
  local bb_exit=0
  bb_output=$(timeout "$bb_timeout" "$BB_ENTRY" --pr "$pr_number" --repo "$repo_name" 2>/dev/null) || bb_exit=$?

  # Handle timeout
  if [[ "$bb_exit" -eq 124 ]]; then
    handle_phase_error "POST_PR_AUDIT" "Bridgebuilder timed out after ${bb_timeout}s"
  fi

  # Handle non-zero exit (Bridgebuilder reports errors via exit 1)
  if [[ "$bb_exit" -ne 0 ]]; then
    # Validate output even on failure — Bridgebuilder may have partial results
    if [[ -n "$bb_output" ]] && validate_bb_output "$bb_output"; then
      local errors
      errors=$(echo "$bb_output" | jq -r '.errors // 0')
      if [[ "$errors" -gt 0 ]]; then
        log_warning "Bridgebuilder reported $errors error(s)"
        # Continue — we can still process partial results
      fi
    else
      handle_phase_error "POST_PR_AUDIT" "Bridgebuilder failed (exit $bb_exit) with invalid output"
    fi
  fi

  # Validate JSON output schema (SKP-004)
  if [[ -z "$bb_output" ]]; then
    handle_phase_error "POST_PR_AUDIT" "Bridgebuilder produced empty output"
  fi

  if ! validate_bb_output "$bb_output"; then
    handle_phase_error "POST_PR_AUDIT" "Invalid Bridgebuilder output: missing required fields (runId, reviewed)"
  fi

  # Parse RunSummary
  local reviewed skipped errors
  reviewed=$(echo "$bb_output" | jq -r '.reviewed // 0')
  skipped=$(echo "$bb_output" | jq -r '.skipped // 0')
  errors=$(echo "$bb_output" | jq -r '.errors // 0')

  log_info "Bridgebuilder results: reviewed=$reviewed, skipped=$skipped, errors=$errors"

  # Write structured results (IMP-003)
  local status="clean"
  if [[ "$errors" -gt 0 ]]; then
    status="error"
  elif [[ "$reviewed" -gt 0 ]]; then
    status="clean"
  elif [[ "$skipped" -gt 0 ]]; then
    status="skipped"
  fi

  mkdir -p .run
  jq -n \
    --arg tool "bridgebuilder" \
    --arg version "2.1.0" \
    --argjson pr_number "$pr_number" \
    --arg repo "$repo_name" \
    --arg status "$status" \
    --argjson reviewed "$reviewed" \
    --argjson skipped "$skipped" \
    --argjson errors "$errors" \
    --arg run_id "$(echo "$bb_output" | jq -r '.runId // "unknown"')" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      tool: $tool,
      version: $version,
      pr_number: $pr_number,
      repo: $repo,
      status: $status,
      bridgebuilder_summary: {
        reviewed: $reviewed,
        skipped: $skipped,
        errors: $errors,
        run_id: $run_id
      },
      review_posted: ($reviewed > 0),
      error_message: null,
      timestamp: $ts
    }' > .run/post-pr-audit-results.json

  # Save raw Bridgebuilder output to context
  echo "$bb_output" > "${context_dir}/bridgebuilder-output.json"

  # Determine verdict based on errors
  if [[ "$errors" -gt 0 ]]; then
    return 1  # CHANGES_REQUIRED
  fi

  return 0  # APPROVED
}

# ============================================================================
# Audit Context
# ============================================================================

create_audit_context() {
  local pr_number="$1"
  local metadata_file="$2"
  local context_dir="${BASE_CONTEXT_DIR}/pr-${pr_number}"

  mkdir -p "$context_dir"
  cp "$metadata_file" "${context_dir}/pr-metadata.json"

  local title additions deletions
  title=$(jq -r '.title' "$metadata_file")
  additions=$(jq -r '.additions' "$metadata_file")
  deletions=$(jq -r '.deletions' "$metadata_file")

  cat > "${context_dir}/pr-summary.md" << EOF
# PR #${pr_number}: ${title}

## Stats
- Additions: ${additions}
- Deletions: ${deletions}

## Changed Files
$(jq -r '.files[].path' "$metadata_file" | sed 's/^/- /')
EOF

  echo "$context_dir"
}

generate_audit_report() {
  local findings_file="$1"
  local report_file="$2"

  local findings_count
  findings_count=$(jq '.findings | length' "$findings_file")

  cat > "$report_file" << EOF
# Audit Report

**Generated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Fast-pass findings:** ${findings_count}

## Fast-Pass Results

EOF

  if (( findings_count == 0 )); then
    echo "No fast-pass issues found." >> "$report_file"
  else
    echo "### Findings" >> "$report_file"
    echo "" >> "$report_file"
    jq -r '.findings[] | "#### [\(.severity | ascii_upcase)] \(.rule_id)\n- **File:** \(.file):\(.line)\n- **Message:** \(.message)\n"' "$findings_file" >> "$report_file"
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
        echo "Runs two-phase audit: deterministic fast-pass + Bridgebuilder deep analysis."
        echo ""
        echo "Exit codes:"
        echo "  0 - APPROVED (no issues found)"
        echo "  1 - CHANGES_REQUIRED (findings above min_severity)"
        echo "  2 - ESCALATED (fail_closed policy on error)"
        echo "  3 - ERROR (script error)"
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

  # Check provider config
  local provider
  provider=$(resolve_audit_provider)

  case "$provider" in
    skip)
      log_info "Audit provider: skip — exiting with APPROVED"
      exit 0
      ;;
    bridgebuilder)
      log_info "Audit provider: bridgebuilder"
      ;;
    *)
      log_error "Unknown audit provider: $provider"
      exit 3
      ;;
  esac

  # Verify gh CLI auth (SKP-004)
  verify_gh_auth

  # Dry run
  if [[ "$dry_run" == "true" ]]; then
    echo "Would audit PR: $pr_url"
    echo "Provider: $provider"
    echo "Failure policy: $(resolve_failure_policy audit)"
    exit 0
  fi

  # Extract PR info for context directory
  local pr_info
  pr_info=$(extract_pr_info "$pr_url")
  local pr_number
  pr_number="${pr_info%%|*}"

  if [[ -z "$context_dir" ]]; then
    context_dir="${BASE_CONTEXT_DIR}/pr-${pr_number}"
  fi

  # Create temp file for metadata
  local metadata_file
  metadata_file=$(mktemp)
  trap "rm -f '$metadata_file'" EXIT

  # Fetch PR metadata
  if ! fetch_pr_metadata "$pr_url" "$metadata_file"; then
    handle_phase_error "POST_PR_AUDIT" "Failed to fetch PR metadata"
  fi

  # Create audit context
  context_dir=$(create_audit_context "$pr_number" "$metadata_file")
  log_info "Audit context: $context_dir"

  # ========== Phase 1: Deterministic fast-pass (SKP-003) ==========
  local fast_result=0
  run_fast_checks "$context_dir" || fast_result=$?

  if [[ "$fast_result" -ne 0 ]]; then
    # Critical finding in fast-pass — generate report and exit
    generate_audit_report "${context_dir}/fast-check-findings.json" "${context_dir}/audit-report.md"
    log_error "Fast-pass detected critical issues — CHANGES_REQUIRED"

    # Write results
    mkdir -p .run
    jq -n \
      --arg tool "fast-pass" \
      --argjson pr_number "$pr_number" \
      --arg status "findings" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{tool: $tool, pr_number: $pr_number, status: $status, phase: "fast_pass", timestamp: $ts}' \
      > .run/post-pr-audit-results.json

    exit 1
  fi

  # ========== Phase 2: Bridgebuilder deep analysis ==========
  local bb_result=0
  run_bridgebuilder_audit "$pr_url" "$context_dir" || bb_result=$?

  # Generate combined report
  if [[ -f "${context_dir}/fast-check-findings.json" ]]; then
    generate_audit_report "${context_dir}/fast-check-findings.json" "${context_dir}/audit-report.md"
  fi

  case "$bb_result" in
    0)
      log_info "Audit APPROVED — Bridgebuilder review posted, no errors"
      exit 0
      ;;
    1)
      log_info "Audit CHANGES_REQUIRED — Bridgebuilder reported errors"
      exit 1
      ;;
    *)
      log_error "Unexpected Bridgebuilder result: $bb_result"
      exit 3
      ;;
  esac
}

main "$@"
