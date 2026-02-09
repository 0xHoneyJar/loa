#!/usr/bin/env bash
# post-pr-doc-test.sh - RTFM Documentation Testing Manifest Generator
# Part of Loa Framework v1.32.0
#
# Identifies changed .md files in a PR, filters and caps them,
# then writes an RTFM manifest for the calling agent to consume.
#
# This script does NOT invoke RTFM directly (RTFM is a skill, not a CLI).
# The calling agent reads the manifest and invokes /rtfm for each doc.
#
# Usage:
#   post-pr-doc-test.sh --pr-url <url> [--dry-run]
#
# Exit codes:
#   0 - Manifest written (or no docs to test)
#   2 - ESCALATED (fail_closed policy triggered on error)
#   3 - ERROR (script error)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default exclude patterns (used when config missing)
readonly DEFAULT_EXCLUDES=(
  "grimoires/loa/a2a/**"
  "CHANGELOG.md"
  "**/reviewer.md"
  "**/engineer-feedback.md"
  "**/auditor-sprint-feedback.md"
)

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

# ============================================================================
# Failure Policy (shared with post-pr-audit.sh)
# ============================================================================

resolve_failure_policy() {
  local phase="${1:-doc_test}"

  local explicit=""
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    explicit=$(yq ".post_pr_validation.phases.${phase}.failure_policy // \"\"" \
      .loa.config.yaml 2>/dev/null || echo "")
  fi

  if [[ -n "$explicit" ]]; then
    echo "$explicit"
    return
  fi

  if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${CLAWDBOT_GATEWAY_TOKEN:-}" ]]; then
    echo "fail_closed"
  else
    echo "fail_open"
  fi
}

handle_phase_error() {
  local phase="$1"
  local error_msg="$2"
  local policy
  policy=$(resolve_failure_policy "$phase")

  log_warning "Phase error: $error_msg (policy: $policy)"

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
# Config Resolution
# ============================================================================

is_doc_test_enabled() {
  local enabled="true"
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    enabled=$(yq '.post_pr_validation.phases.doc_test.enabled // true' \
      .loa.config.yaml 2>/dev/null || echo "true")
  fi
  [[ "$enabled" == "true" ]]
}

resolve_max_docs() {
  local max_docs=5
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    local cfg
    cfg=$(yq '.post_pr_validation.phases.doc_test.max_docs // 5' \
      .loa.config.yaml 2>/dev/null || echo "5")
    if [[ "$cfg" =~ ^[0-9]+$ ]]; then
      max_docs="$cfg"
    fi
  fi
  echo "$max_docs"
}

resolve_timeout_per_doc() {
  local timeout=180
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    local cfg
    cfg=$(yq '.post_pr_validation.phases.doc_test.timeout_per_doc // 180' \
      .loa.config.yaml 2>/dev/null || echo "180")
    if [[ "$cfg" =~ ^[0-9]+$ ]]; then
      timeout="$cfg"
    fi
  fi
  echo "$timeout"
}

resolve_timeout_total() {
  local timeout=600
  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    local cfg
    cfg=$(yq '.post_pr_validation.phases.doc_test.timeout_total // 600' \
      .loa.config.yaml 2>/dev/null || echo "600")
    if [[ "$cfg" =~ ^[0-9]+$ ]]; then
      timeout="$cfg"
    fi
  fi
  echo "$timeout"
}

# ============================================================================
# Exclude Pattern Matching
# ============================================================================

get_exclude_patterns() {
  local patterns=()

  if command -v yq >/dev/null 2>&1 && [[ -f .loa.config.yaml ]]; then
    local cfg_patterns
    cfg_patterns=$(yq '.post_pr_validation.phases.doc_test.exclude_patterns[]' \
      .loa.config.yaml 2>/dev/null || echo "")

    if [[ -n "$cfg_patterns" ]]; then
      while IFS= read -r pattern; do
        [[ -n "$pattern" ]] && patterns+=("$pattern")
      done <<< "$cfg_patterns"
    fi
  fi

  # Use defaults if no config patterns
  if [[ ${#patterns[@]} -eq 0 ]]; then
    patterns=("${DEFAULT_EXCLUDES[@]}")
  fi

  printf '%s\n' "${patterns[@]}"
}

matches_exclude() {
  local file="$1"

  local patterns
  patterns=$(get_exclude_patterns)

  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    # Use bash extended glob matching
    # shellcheck disable=SC2254
    if [[ "$file" == $pattern ]]; then
      return 0
    fi
  done <<< "$patterns"

  return 1
}

# ============================================================================
# PR Info Extraction
# ============================================================================

verify_gh_auth() {
  if ! command -v gh >/dev/null 2>&1; then
    handle_phase_error "DOC_TEST" "gh CLI not installed"
  fi

  if ! gh auth status >/dev/null 2>&1; then
    handle_phase_error "DOC_TEST" "gh CLI not authenticated (run: gh auth login)"
  fi
}

extract_pr_number() {
  local pr_url="$1"

  local pr_json
  pr_json=$(gh pr view "$pr_url" --json number,url 2>&1) || {
    handle_phase_error "DOC_TEST" "gh pr view failed for $pr_url"
  }

  echo "$pr_json" | jq -r '.number'
}

# ============================================================================
# Generate Run ID
# ============================================================================

generate_run_id() {
  local timestamp
  timestamp=$(date -u +%Y%m%dT%H%M%S)
  local random
  random=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
  echo "rtfm-${timestamp}-${random}"
}

# ============================================================================
# Main
# ============================================================================

main() {
  local pr_url=""
  local dry_run=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr-url)
        pr_url="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --help|-h)
        echo "Usage: post-pr-doc-test.sh --pr-url <url> [--dry-run]"
        echo ""
        echo "Generates RTFM manifest for changed .md files in a PR."
        echo "The calling agent consumes the manifest and invokes /rtfm."
        echo ""
        echo "Exit codes:"
        echo "  0 - Manifest written (or no docs to test)"
        echo "  2 - ESCALATED (fail_closed policy on error)"
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

  # Check if doc_test is enabled
  if ! is_doc_test_enabled; then
    log_info "Doc test phase disabled (config), skipping"
    exit 0
  fi

  # Verify gh CLI (SKP-004)
  verify_gh_auth

  # Extract PR number
  local pr_number
  pr_number=$(extract_pr_number "$pr_url")

  if [[ -z "$pr_number" || "$pr_number" == "null" ]]; then
    handle_phase_error "DOC_TEST" "Could not extract PR number from $pr_url"
  fi

  log_info "Checking changed files for PR #$pr_number..."

  # Get changed files via gh pr diff (IMP-009: explicit exit code check)
  local changed_files=""
  changed_files=$(gh pr diff "$pr_number" --name-only 2>&1) || {
    handle_phase_error "DOC_TEST" "gh pr diff failed for PR #$pr_number"
  }

  if [[ -z "$changed_files" ]]; then
    log_info "No files changed in PR, skipping doc test"
    exit 0
  fi

  # Filter to *.md files only
  local md_files
  md_files=$(echo "$changed_files" | grep '\.md$' || true)

  if [[ -z "$md_files" ]]; then
    log_info "No .md files changed, skipping doc test"
    exit 0
  fi

  # Apply exclude patterns
  local docs_to_test=()
  local docs_excluded=()

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    if matches_exclude "$file"; then
      docs_excluded+=("$file")
      log_debug "Excluded: $file"
    else
      docs_to_test+=("$file")
    fi
  done <<< "$md_files"

  if [[ ${#docs_to_test[@]} -eq 0 ]]; then
    log_info "All .md files matched exclude patterns, skipping doc test"
    log_info "Excluded: ${docs_excluded[*]:-none}"
    exit 0
  fi

  # Cap at max_docs (IMP-004)
  local max_docs
  max_docs=$(resolve_max_docs)

  local capped_docs=()
  local i=0
  for doc in "${docs_to_test[@]}"; do
    if (( i >= max_docs )); then
      log_warning "Capped at $max_docs docs (${#docs_to_test[@]} total)"
      break
    fi
    capped_docs+=("$doc")
    ((++i))
  done

  log_info "Docs to test: ${#capped_docs[@]} (excluded: ${#docs_excluded[@]})"

  # Dry run
  if [[ "$dry_run" == "true" ]]; then
    echo "Would test ${#capped_docs[@]} docs:"
    printf '  - %s\n' "${capped_docs[@]}"
    echo "Excluded: ${#docs_excluded[@]}"
    printf '  - %s\n' "${docs_excluded[@]}"
    exit 0
  fi

  # Generate run_id for correlation (IMP-001, SKP-002)
  local run_id
  run_id=$(generate_run_id)

  # Resolve config values
  local timeout_per_doc timeout_total failure_policy
  timeout_per_doc=$(resolve_timeout_per_doc)
  timeout_total=$(resolve_timeout_total)
  failure_policy=$(resolve_failure_policy "doc_test")

  # Build JSON arrays
  local docs_json excluded_json
  docs_json=$(printf '%s\n' "${capped_docs[@]}" | jq -R . | jq -s .)
  excluded_json=$(printf '%s\n' "${docs_excluded[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")

  # Write manifest (SDD §3.2)
  mkdir -p .run
  jq -n \
    --arg run_id "$run_id" \
    --arg status "pending" \
    --argjson pr_number "$pr_number" \
    --argjson docs "$docs_json" \
    --argjson excluded "$excluded_json" \
    --argjson max_docs "$max_docs" \
    --argjson timeout_per_doc "$timeout_per_doc" \
    --argjson timeout_total "$timeout_total" \
    --arg failure_policy "$failure_policy" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      run_id: $run_id,
      status: $status,
      pr_number: $pr_number,
      docs: $docs,
      excluded: $excluded,
      max_docs: $max_docs,
      timeout_per_doc: $timeout_per_doc,
      timeout_total: $timeout_total,
      failure_policy: $failure_policy,
      timestamp: $ts
    }' > .run/rtfm-manifest.json

  log_info "RTFM manifest written: .run/rtfm-manifest.json (run_id: $run_id)"
  log_info "Docs: ${capped_docs[*]}"
  log_info "Awaiting agent to consume manifest and invoke /rtfm"

  exit 0
}

main "$@"
