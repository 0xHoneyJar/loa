#!/usr/bin/env bash
# =============================================================================
# adversarial-review.sh — Adversarial cross-model dissent for code review/audit
# =============================================================================
# Version: 1.0.0
# Part of: Adversarial Flatline Protocol (#224)
#
# Usage:
#   adversarial-review.sh --type <review|audit> --sprint-id <id> --diff-file <path> [options]
#
# Options:
#   --type <review|audit>     Dissent type (required)
#   --sprint-id <id>          Sprint identifier (required)
#   --diff-file <path>        Path to git diff file (required)
#   --context-file <path>     Reviewer findings (review only; omit for audit independence)
#   --model <model>           Dissenter model (default: from config or gpt-5.2-codex)
#   --budget <cents>          Max cost in cents (default: from config or 150)
#   --timeout <seconds>       API timeout (default: from config or 60)
#   --dry-run                 Assemble context without calling API
#   --json                    Output as JSON (default)
#
# Exit codes:
#   0 - Success (findings returned, may be empty)
#   1 - Configuration error (disabled, missing config)
#   2 - Invalid arguments
#   3 - API call failed (all retries exhausted)
#   4 - Budget exceeded
#   5 - Invalid response (schema validation failed)
#   6 - Timeout
#
# Environment:
#   OPENAI_API_KEY            Required for GPT models
#   FLATLINE_MOCK_MODE=true   Use mock responses for testing
#   FLATLINE_MOCK_DIR=<path>  Custom mock fixtures directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/.loa.config.yaml}"

# Source shared content processing functions (file_priority, prepare_content, estimate_tokens)
# These were extracted from gpt-review-api.sh into lib-content.sh to avoid the
# brittle eval+sed import pattern. See: Bridgebuilder Review Finding #1 (PR #235)
# NOTE: Use absolute path stored in a global so it survives eval-based test sourcing.
_LIB_CONTENT_PATH="$SCRIPT_DIR/lib-content.sh"
# shellcheck source=lib-content.sh
# The `|| true` allows eval-based test sourcing where BASH_SOURCE[0] resolves
# to a temp dir. Tests pre-source lib-content.sh; the double-source guard prevents
# duplicate loading. See: Bridgebuilder Review Finding #1 (PR #235)
source "$_LIB_CONTENT_PATH" 2>/dev/null || true

# Token budgets (with 80% safety margin per D-009)
DEFAULT_PRIMARY_TOKEN_BUDGET=24000    # 80% of 30k
DEFAULT_SECONDARY_TOKEN_BUDGET=12000  # 80% of 15k
MAX_ESCALATED_FILES=3                 # Per D-011

# =============================================================================
# Logging
# =============================================================================

log() { echo "[adversarial-review] $*" >&2; }
error() { echo "ERROR: $*" >&2; }

# =============================================================================
# Configuration
# =============================================================================

load_adversarial_config() {
  local type="$1"

  # Defaults
  CONF_ENABLED="false"
  CONF_MODEL="gpt-5.2-codex"
  CONF_TIMEOUT=60
  CONF_BUDGET_CENTS=150
  CONF_ESCALATION_ENABLED="true"
  CONF_SECONDARY_BUDGET=$DEFAULT_SECONDARY_TOKEN_BUDGET
  CONF_MAX_FILE_LINES=500
  CONF_MAX_FILE_BYTES=51200
  CONF_SECRET_SCANNING="true"
  CONF_SECRET_ALLOWLIST=()  # Patterns that should NOT be redacted

  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Config file not found, using defaults"
    return 0
  fi

  if ! command -v yq &>/dev/null; then
    log "WARNING: yq not available, using hardcoded defaults"
    return 0
  fi

  local config_key
  if [[ "$type" == "review" ]]; then
    config_key="code_review"
  else
    config_key="security_audit"
  fi

  CONF_ENABLED=$(yq eval ".flatline_protocol.${config_key}.enabled // false" "$CONFIG_FILE" 2>/dev/null || echo "false")
  CONF_MODEL=$(yq eval ".flatline_protocol.${config_key}.model // \"gpt-5.2-codex\"" "$CONFIG_FILE" 2>/dev/null || echo "gpt-5.2-codex")
  CONF_TIMEOUT=$(yq eval ".flatline_protocol.${config_key}.timeout_seconds // 60" "$CONFIG_FILE" 2>/dev/null || echo "60")
  CONF_BUDGET_CENTS=$(yq eval ".flatline_protocol.${config_key}.budget_cents // 150" "$CONFIG_FILE" 2>/dev/null || echo "150")
  CONF_ESCALATION_ENABLED=$(yq eval ".flatline_protocol.context_escalation.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")
  CONF_SECONDARY_BUDGET=$(yq eval ".flatline_protocol.context_escalation.secondary_token_budget // $DEFAULT_SECONDARY_TOKEN_BUDGET" "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_SECONDARY_TOKEN_BUDGET")
  CONF_MAX_FILE_LINES=$(yq eval ".flatline_protocol.context_escalation.max_file_lines // 500" "$CONFIG_FILE" 2>/dev/null || echo "500")
  CONF_MAX_FILE_BYTES=$(yq eval ".flatline_protocol.context_escalation.max_file_bytes // 51200" "$CONFIG_FILE" 2>/dev/null || echo "51200")
  CONF_SECRET_SCANNING=$(yq eval ".flatline_protocol.secret_scanning.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")

  # Load allowlist patterns — content matching these is restored after redaction.
  # Wires config to runtime. See: Bridgebuilder Review Finding #4
  local allowlist_raw
  allowlist_raw=$(yq eval '.flatline_protocol.secret_scanning.allowlist // [] | .[]' "$CONFIG_FILE" 2>/dev/null || true)
  CONF_SECRET_ALLOWLIST=()
  if [[ -n "$allowlist_raw" ]]; then
    while IFS= read -r pattern; do
      [[ -n "$pattern" ]] && CONF_SECRET_ALLOWLIST+=("$pattern")
    done <<< "$allowlist_raw"
  fi
}

# =============================================================================
# Secret Scanning (NFR-4)
# =============================================================================

secret_scan_content() {
  local content="$1"

  # Use temp files to avoid ARG_MAX limits on large diffs.
  # printf '%s' "$content" | sed works for small input but fails when
  # content approaches 128KB+ because the shell passes it as an argument.
  # Piping through files avoids this entirely.
  # See: Bridgebuilder Review Finding #3
  local scan_tmp
  scan_tmp=$(mktemp)
  printf '%s' "$content" > "$scan_tmp"
  local redaction_count=0

  # Pre-scan: protect allowlisted matches with unique placeholders before redaction.
  # This ensures patterns like SHA-256 hashes and UUIDs survive the redaction pass.
  # See: Bridgebuilder Review Finding #4
  if [[ ${#CONF_SECRET_ALLOWLIST[@]} -gt 0 ]]; then
    local al_idx=0
    for pattern in "${CONF_SECRET_ALLOWLIST[@]}"; do
      local matches
      matches=$(grep -oE "$pattern" "$scan_tmp" 2>/dev/null | sort -u || true)
      if [[ -n "$matches" ]]; then
        while IFS= read -r match; do
          [[ -z "$match" ]] && continue
          local placeholder="__ALLOWLIST_${al_idx}__"
          # Record placeholder→original mapping for post-redaction restore
          printf '%s\t%s\n' "$placeholder" "$match" >> "${scan_tmp}.allowlist"
          # Replace in file (literal match via perl to avoid regex in match)
          perl -i -pe "s/\Q${match}\E/${placeholder}/g" "$scan_tmp" 2>/dev/null || true
          ((al_idx++))
        done <<< "$matches"
      fi
    done
  fi

  # AWS access keys
  sed -E -i 's/AKIA[0-9A-Z]{16}/[REDACTED:aws_key]/g' "$scan_tmp"

  # Private keys
  sed -E -i 's/-----BEGIN[A-Z ]*PRIVATE KEY-----/[REDACTED:private_key]/g' "$scan_tmp"

  # GitHub PATs
  sed -E -i 's/ghp_[A-Za-z0-9]{36}/[REDACTED:github_pat]/g' "$scan_tmp"

  # OpenAI keys
  sed -E -i 's/sk-[A-Za-z0-9]{20}T3BlbkFJ[A-Za-z0-9]{20}/[REDACTED:openai_key]/g' "$scan_tmp"

  # Generic credentials (password/secret/token/api_key = "value")
  sed -E -i 's/(password|secret|token|api_key)[[:space:]]*[:=][[:space:]]*["'"'"'][^'"'"'"]{8,}/\1=[REDACTED:credential]/g' "$scan_tmp"

  # Apply allowlist: replace placeholder tokens back with original values.
  # Strategy: before redaction we saved allowlisted matches with unique placeholders.
  # After redaction, we restore them. This handles the case where e.g. a SHA-256
  # hash accidentally matches the generic credential pattern.
  # See: Bridgebuilder Review Finding #4
  if [[ ${#CONF_SECRET_ALLOWLIST[@]} -gt 0 && -f "${scan_tmp}.allowlist" ]]; then
    while IFS=$'\t' read -r placeholder original; do
      [[ -z "$placeholder" || -z "$original" ]] && continue
      # Use perl for literal string replacement (no regex interpretation)
      perl -i -pe "s/\Q${placeholder}\E/${original}/g" "$scan_tmp" 2>/dev/null || true
    done < "${scan_tmp}.allowlist"
    rm -f "${scan_tmp}.allowlist"
  fi

  # Count redactions by comparing with original
  local scanned
  scanned=$(cat "$scan_tmp")
  if [[ "$scanned" != "$content" ]]; then
    redaction_count=$(diff <(printf '%s' "$content") <(printf '%s' "$scanned") | grep -c '^<' || true)
    log "Secret scan: $redaction_count redaction(s) applied"
  fi

  cat "$scan_tmp"
  rm -f "$scan_tmp" "${scan_tmp}.allowlist"
}

# =============================================================================
# Severity Ranking
# =============================================================================

severity_rank() {
  local sev="$1"
  case "$sev" in
    CRITICAL)        echo 4 ;;
    HIGH|BLOCKING)   echo 3 ;;
    MEDIUM|ADVISORY) echo 2 ;;
    LOW)             echo 1 ;;
    *)               echo 0 ;;
  esac
}

# =============================================================================
# Finding Validation (jq-based, per D-006)
# =============================================================================

validate_finding() {
  local finding="$1"
  local type="$2"

  local valid_severities
  if [[ "$type" == "review" ]]; then
    valid_severities='["BLOCKING","ADVISORY"]'
  else
    valid_severities='["CRITICAL","HIGH","MEDIUM","LOW"]'
  fi

  local valid_categories='["injection","authz","data-loss","null-safety","concurrency","type-error","resource-leak","error-handling","spec-violation","performance","secrets","xss","ssrf","deserialization","crypto","info-disclosure","rate-limiting","input-validation","config","other"]'

  echo "$finding" | jq -e --argjson sevs "$valid_severities" --argjson cats "$valid_categories" '
    (.id | type) == "string" and
    (.severity | IN($sevs[])) and
    (.category | IN($cats[])) and
    (.description | type) == "string" and (.description | length) > 0 and
    (.failure_mode | type) == "string" and (.failure_mode | length) > 0
  ' > /dev/null 2>&1
}

# =============================================================================
# Anchor Validation Pipeline (SDD Section 5)
# =============================================================================

validate_anchor() {
  local finding="$1"
  local type="$2"
  local diff_files="$3"  # newline-separated list of files in the diff

  local anchor severity scope trigger_anchor cross_file_justification
  anchor=$(echo "$finding" | jq -r '.anchor // ""')
  severity=$(echo "$finding" | jq -r '.severity')
  scope=$(echo "$finding" | jq -r '.scope // "diff"')
  trigger_anchor=$(echo "$finding" | jq -r '.trigger_anchor // ""')
  cross_file_justification=$(echo "$finding" | jq -r '.cross_file_justification // ""')

  local sev_rank
  sev_rank=$(severity_rank "$severity")

  # Only enforce anchors for high-severity findings (rank >= 3)
  if [[ $sev_rank -lt 3 ]]; then
    echo "$finding" | jq '.anchor_status = "valid"'
    return 0
  fi

  # Step 1: Check anchor exists
  if [[ -z "$anchor" ]]; then
    if [[ "$type" == "review" ]]; then
      # Review: demote severity
      local new_sev="ADVISORY"
      echo "$finding" | jq --arg ns "$new_sev" '
        .severity = $ns |
        .anchor_status = "unresolved" |
        .demotion_reason = "Demoted: missing stable anchor"
      '
    elif [[ $sev_rank -ge 3 ]]; then
      # Audit HIGH+: needs_triage (per D-010)
      echo "$finding" | jq '.anchor_status = "needs_triage"'
    else
      # Audit MEDIUM/LOW: demote
      echo "$finding" | jq '
        .severity = "LOW" |
        .anchor_status = "unresolved" |
        .demotion_reason = "Demoted: missing stable anchor"
      '
    fi
    return 0
  fi

  # Extract file path from anchor (format: file:symbol or file:@@hunk)
  local anchor_file
  anchor_file=$(echo "$anchor" | cut -d: -f1)

  # Step 2: Check anchor references file in diff
  if echo "$diff_files" | grep -qF "$anchor_file"; then
    # Anchor file is in diff — valid
    local stability="symbol"
    if echo "$anchor" | grep -q '@@'; then
      stability="hunk_header"
    elif echo "$anchor" | grep -qE ':[0-9]+$'; then
      stability="line_number"
    fi
    echo "$finding" | jq --arg s "$stability" '
      .anchor_status = "valid" |
      .anchor_stability = $s
    '
  elif [[ "$scope" == "cross_file" && -n "$cross_file_justification" && -n "$trigger_anchor" ]]; then
    # Cross-file: check trigger_anchor is in diff
    local trigger_file
    trigger_file=$(echo "$trigger_anchor" | cut -d: -f1)
    if echo "$diff_files" | grep -qF "$trigger_file"; then
      echo "$finding" | jq '.anchor_status = "cross_file" | .anchor_stability = "symbol"'
    else
      # Trigger not in diff — out of scope
      local demoted_sev
      if [[ "$type" == "review" ]]; then demoted_sev="ADVISORY"; else demoted_sev="MEDIUM"; fi
      echo "$finding" | jq --arg ns "$demoted_sev" '
        .severity = $ns |
        .anchor_status = "out_of_scope" |
        .demotion_reason = "Demoted: trigger_anchor not in diff"
      '
    fi
  else
    # Not in diff, not valid cross-file — out of scope
    local demoted_sev
    if [[ "$type" == "review" ]]; then demoted_sev="ADVISORY"; else demoted_sev="MEDIUM"; fi
    echo "$finding" | jq --arg ns "$demoted_sev" '
      .severity = $ns |
      .anchor_status = "out_of_scope" |
      .demotion_reason = "Demoted: anchor not in diff scope"
    '
  fi
}

# =============================================================================
# Context Assembly (FR-1.3 + FR-1.3.1)
# =============================================================================

# File denylist for context escalation
is_denied_file() {
  local filepath="$1"
  case "$filepath" in
    *.pem|*.key|*.p12|*.pfx) return 0 ;;
    id_rsa*|.env*|credentials.*|secrets.*|*.secret) return 0 ;;
    *) return 1 ;;
  esac
}

# estimate_tokens() is now provided by lib-content.sh (sourced at top)
# Using bytes/3 for code-aware estimation. See: Bridgebuilder Review Finding #5

assemble_dissent_context() {
  local diff_file="$1"
  local type="$2"
  local context_file="${3:-}"

  local diff_content
  diff_content=$(cat "$diff_file")

  # file_priority() and prepare_content() are provided by lib-content.sh
  # No eval+sed hack needed. See: Bridgebuilder Review Finding #1

  # Primary content: priority-sorted diff with 80% budget
  # prepare_content is guaranteed available from lib-content.sh
  local prepared_diff
  prepared_diff=$(prepare_content "$diff_content" "$DEFAULT_PRIMARY_TOKEN_BUDGET")

  # P0 file escalation (if enabled)
  local escalated_content=""
  local escalation_used="false"
  if [[ "$CONF_ESCALATION_ENABLED" == "true" ]]; then
    local escalated_tokens=0
    local escalated_count=0
    local diff_files
    diff_files=$(grep -E '^diff --git a/' "$diff_file" | sed 's|^diff --git a/\(.*\) b/.*|\1|' || true)

    while IFS= read -r filepath; do
      [[ -z "$filepath" ]] && continue
      [[ $escalated_count -ge $MAX_ESCALATED_FILES ]] && break

      # Check if P0 — file_priority() provided by lib-content.sh
      local priority
      priority=$(file_priority "$filepath")
      [[ "$priority" != "0" ]] && continue

      # Denylist check
      if is_denied_file "$filepath"; then
        log "Denylist: skipping $filepath"
        continue
      fi

      # Check file exists and is text
      local full_path="$PROJECT_ROOT/$filepath"
      [[ ! -f "$full_path" ]] && continue
      if file --mime "$full_path" 2>/dev/null | grep -q 'binary'; then
        log "Binary: skipping $filepath"
        continue
      fi

      # Size cap
      local file_bytes file_lines
      file_bytes=$(wc -c < "$full_path")
      file_lines=$(wc -l < "$full_path")
      if [[ $file_bytes -gt $CONF_MAX_FILE_BYTES || $file_lines -gt $CONF_MAX_FILE_LINES ]]; then
        log "Size cap: skipping $filepath ($file_lines lines, $file_bytes bytes)"
        continue
      fi

      # Token accounting
      local file_content
      file_content=$(cat "$full_path")
      local file_tokens
      file_tokens=$(estimate_tokens "$file_content")
      if [[ $(( escalated_tokens + file_tokens )) -gt $CONF_SECONDARY_BUDGET ]]; then
        log "Token budget: skipping $filepath (would exceed secondary budget)"
        continue
      fi

      escalated_content+=$'\n'"--- FULL FILE: $filepath (P0 escalated) ---"$'\n'"$file_content"$'\n'
      escalated_tokens=$(( escalated_tokens + file_tokens ))
      ((escalated_count++))
      escalation_used="true"
      log "Escalated P0 file: $filepath ($file_tokens tokens, $escalated_count/$MAX_ESCALATED_FILES)"
    done <<< "$diff_files"
  fi

  # Secret scanning
  if [[ "$CONF_SECRET_SCANNING" == "true" ]]; then
    prepared_diff=$(secret_scan_content "$prepared_diff")
    if [[ -n "$escalated_content" ]]; then
      escalated_content=$(secret_scan_content "$escalated_content")
    fi
  fi

  # Build system prompt
  local system_prompt
  if [[ "$type" == "review" ]]; then
    system_prompt='You are an adversarial code reviewer. Your role is to find production-impact problems that the primary reviewer may have missed.

RULES:
- Find REAL problems: runtime failures, security exposure, spec violations, data corruption
- Every BLOCKING finding MUST include a stable anchor (file:function_name or file:hunk_header)
- Do NOT flag: style preferences, theoretical risks, items outside the provided diff
- Cross-file impacts ARE valid if you reference at least one diff-touched file as the trigger
- If you find nothing meaningful, return {"findings": []}

SEVERITY LEVELS (code review):
- BLOCKING: Will cause runtime failure, security exposure, data corruption, or spec violation
- ADVISORY: Low-likelihood concern, tech debt, or hardening suggestion

CATEGORY (required, one of):
  injection, authz, data-loss, null-safety, concurrency, type-error,
  resource-leak, error-handling, spec-violation, performance, other

OUTPUT: JSON object {"findings": [...]}. Each finding:
{"id": "DISS-NNN", "severity": "BLOCKING|ADVISORY", "category": "...",
 "anchor": "file:symbol", "anchor_type": "function|hunk|line",
 "scope": "diff|cross_file",
 "trigger_anchor": "file:symbol (required if scope=cross_file; must be in diff)",
 "cross_file_justification": "...(required if scope=cross_file)",
 "description": "...", "failure_mode": "...", "suggested_fix": "..."}'
  else
    system_prompt='You are an adversarial security auditor. Find exploitable vulnerabilities.

RULES:
- Prioritize OWASP Top 10: injection, auth bypass, SSRF, deserialization, secrets exposure
- Verify all untrusted input flows reach sinks through validated paths
- Check for hardcoded credentials, information disclosure in errors, missing rate limiting
- Every CRITICAL/HIGH finding MUST include a stable anchor
- Cross-file impacts ARE valid if you reference at least one diff-touched file as trigger
- If you find nothing meaningful, return {"findings": []}

SEVERITY LEVELS (security audit):
- CRITICAL: Exploitable vulnerability, immediate risk
- HIGH: Significant security gap, likely exploitable
- MEDIUM: Defense-in-depth concern
- LOW: Hardening recommendation

CATEGORY (required, one of):
  injection, authz, secrets, xss, ssrf, deserialization, crypto,
  info-disclosure, rate-limiting, input-validation, config, other

OUTPUT: JSON object {"findings": [...]}. Same field structure as code review.'
  fi

  # Build user prompt
  local user_prompt="## Code Changes (git diff)\n\n$prepared_diff"
  if [[ -n "$escalated_content" ]]; then
    user_prompt+="\n\n## Full File Context (P0 Security-Critical)\n\n$escalated_content"
  fi
  if [[ -n "$context_file" && -f "$context_file" ]]; then
    local ctx
    ctx=$(cat "$context_file")
    user_prompt+="\n\n## Reviewer Context\n\n$ctx"
  fi

  # Return assembled context as JSON
  jq -n \
    --arg system "$system_prompt" \
    --arg user "$user_prompt" \
    --argjson escalated "$( [[ "$escalation_used" == "true" ]] && echo true || echo false )" \
    '{system_prompt: $system, user_prompt: $user, context_escalated: $escalated}'
}

# =============================================================================
# Dissenter Invocation
# =============================================================================

invoke_dissenter() {
  local system_prompt_file="$1"
  local user_prompt_file="$2"
  local model="$3"
  local timeout="$4"

  "$SCRIPT_DIR/model-adapter.sh" \
    --model "$model" \
    --mode dissent \
    --input "$user_prompt_file" \
    --context "$system_prompt_file" \
    --timeout "$timeout"
}

# =============================================================================
# Response Processing (4-state machine per SDD Section 4.1)
# =============================================================================

process_findings() {
  local raw_response="$1"
  local type="$2"
  local model="$3"
  local sprint_id="$4"
  local api_exit_code="${5:-0}"
  local diff_files="$6"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # STATE 1: API failure
  if [[ "$api_exit_code" != "0" ]]; then
    local degraded="false"
    if [[ "$type" == "audit" ]]; then degraded="true"; fi
    jq -n \
      --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
      --arg ts "$timestamp" --argjson degraded "$degraded" \
      --arg err "API call failed with exit code $api_exit_code" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "api_failure", degraded: $degraded, error: $err}}'
    return 0
  fi

  # Extract content from model-adapter response
  local content
  content=$(echo "$raw_response" | jq -r '.content // empty' 2>/dev/null || echo "")

  # Try to parse as JSON (handle markdown ```json wrapping)
  local parsed
  parsed=$(echo "$content" | sed -n '/^```json/,/^```$/p' | sed '1d;$d' 2>/dev/null || echo "")
  if [[ -z "$parsed" ]]; then
    parsed="$content"
  fi

  # STATE 2: Malformed response
  local findings_array
  findings_array=$(echo "$parsed" | jq -r '.findings // empty' 2>/dev/null || echo "")
  if [[ -z "$findings_array" ]]; then
    log "Malformed response: missing 'findings' key"
    jq -n \
      --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
      --arg ts "$timestamp" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "malformed_response", degraded: false}}'
    return 0
  fi

  # STATE 3: Empty findings
  local finding_count
  finding_count=$(echo "$parsed" | jq '.findings | length' 2>/dev/null || echo "0")
  if [[ "$finding_count" == "0" ]]; then
    jq -n \
      --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
      --arg ts "$timestamp" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "clean", degraded: false}}'
    return 0
  fi

  # STATE 4: Populated findings — validate and process
  local validated_findings="[]"
  local i=0
  while [[ $i -lt $finding_count ]]; do
    local finding
    finding=$(echo "$parsed" | jq ".findings[$i]")

    if validate_finding "$finding" "$type"; then
      # Run anchor validation
      local validated
      validated=$(validate_anchor "$finding" "$type" "$diff_files")
      validated_findings=$(echo "$validated_findings" | jq --argjson f "$validated" '. + [$f]')
    else
      log "Rejected invalid finding at index $i"
    fi
    ((i++))
  done

  # Extract token/cost metadata from model-adapter response
  local tokens_in tokens_out cost latency
  tokens_in=$(echo "$raw_response" | jq -r '.tokens_input // 0')
  tokens_out=$(echo "$raw_response" | jq -r '.tokens_output // 0')
  cost=$(echo "$raw_response" | jq -r '.cost_usd // 0')
  latency=$(echo "$raw_response" | jq -r '.latency_ms // 0')

  jq -n \
    --argjson findings "$validated_findings" \
    --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
    --arg ts "$timestamp" \
    --argjson ti "$tokens_in" --argjson to "$tokens_out" \
    --argjson cost "$cost" --argjson lat "$latency" \
    '{findings: $findings, metadata: {type: $type, model: $model, sprint_id: $sid,
      timestamp: $ts, tokens_input: $ti, tokens_output: $to, cost_usd: $cost,
      latency_ms: $lat, status: "reviewed", degraded: false}}'
}

# =============================================================================
# Finding ID Computation (unified — Bridgebuilder Review Finding #2)
# =============================================================================
# Single function, single scheme (sha256), used by all code paths.
# Design decision: sha256 over base64 because it's fixed-length (8 chars),
# collision-resistant, and order-independent. No-anchor findings get a
# unique sentinel to prevent false dedup. — Bridgebuilder Finding #2

compute_finding_id() {
  local anchor="${1:-no_anchor}"
  local category="$2"
  local index="${3:-0}"

  if [[ "$anchor" == "no_anchor" ]]; then
    # No-anchor findings are always unique — include index to prevent collision
    printf 'noanch:%s:%s' "$category" "$index" | sha256sum | cut -c1-8
  else
    printf '%s:%s' "$anchor" "$category" | sha256sum | cut -c1-8
  fi
}

# =============================================================================
# Merge / Dedup (SDD Section 5)
# =============================================================================

merge_findings() {
  local dissenter_json="$1"
  local existing_file="${2:-}"

  local dissenter_findings
  dissenter_findings=$(echo "$dissenter_json" | jq '.findings')

  if [[ -z "$existing_file" || ! -f "$existing_file" ]]; then
    # No existing findings to merge against — compute finding_ids via shell loop
    local count i result="[]"
    count=$(echo "$dissenter_findings" | jq 'length')
    i=0
    while [[ $i -lt $count ]]; do
      local finding anchor category fid
      finding=$(echo "$dissenter_findings" | jq ".[$i]")
      anchor=$(echo "$finding" | jq -r '.anchor // "no_anchor"')
      category=$(echo "$finding" | jq -r '.category')
      fid=$(compute_finding_id "$anchor" "$category" "$i")
      finding=$(echo "$finding" | jq --arg fid "$fid" '. + {finding_id: $fid, source: "dissenter"}')
      result=$(echo "$result" | jq --argjson f "$finding" '. + [$f]')
      ((i++))
    done
    echo "$result"
    return 0
  fi

  local existing_findings
  existing_findings=$(jq '.findings // []' "$existing_file" 2>/dev/null || echo "[]")

  # Build merged set
  local merged="$existing_findings"
  local finding_count
  finding_count=$(echo "$dissenter_findings" | jq 'length')

  local i=0
  while [[ $i -lt $finding_count ]]; do
    local finding anchor category
    finding=$(echo "$dissenter_findings" | jq ".[$i]")
    anchor=$(echo "$finding" | jq -r '.anchor // "no_anchor"')
    category=$(echo "$finding" | jq -r '.category')

    # Compute finding_id via unified function (Bridgebuilder Finding #2)
    local finding_id
    finding_id=$(compute_finding_id "$anchor" "$category" "$i")

    finding=$(echo "$finding" | jq --arg fid "$finding_id" '. + {finding_id: $fid, source: "dissenter"}')

    # Check for duplicate in existing
    local match_idx
    match_idx=$(echo "$merged" | jq --arg fid "$finding_id" '
      [to_entries[] | select(.value.finding_id == $fid)] | .[0].key // -1
    ' 2>/dev/null || echo "-1")

    if [[ "$match_idx" != "-1" && "$match_idx" != "null" ]]; then
      # Merge: max severity wins
      local existing_sev dissenter_sev
      existing_sev=$(echo "$merged" | jq -r ".[$match_idx].severity")
      dissenter_sev=$(echo "$finding" | jq -r '.severity')

      local existing_rank dissenter_rank
      existing_rank=$(severity_rank "$existing_sev")
      dissenter_rank=$(severity_rank "$dissenter_sev")

      if [[ $dissenter_rank -gt $existing_rank ]]; then
        merged=$(echo "$merged" | jq --argjson idx "$match_idx" --arg sev "$dissenter_sev" '
          .[$idx].severity = $sev |
          .[$idx].confirmed_by_cross_model = true |
          .[$idx].note = "Confirmed by cross-model review"
        ')
      else
        merged=$(echo "$merged" | jq --argjson idx "$match_idx" '
          .[$idx].confirmed_by_cross_model = true |
          .[$idx].note = "Confirmed by cross-model review"
        ')
      fi
    else
      # New finding
      merged=$(echo "$merged" | jq --argjson f "$finding" '. + [$f]')
    fi
    ((i++))
  done

  echo "$merged"
}

# =============================================================================
# Output Writing
# =============================================================================

write_output() {
  local result_json="$1"
  local sprint_id="$2"
  local type="$3"

  local output_dir="$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}"
  mkdir -p "$output_dir"

  local filename="adversarial-${type}.json"
  local output_path="$output_dir/$filename"

  # Atomic write via .tmp + mv
  local tmp_path="${output_path}.tmp"
  echo "$result_json" | jq '.' > "$tmp_path"
  mv "$tmp_path" "$output_path"
  log "Output written: $output_path"

  # Trajectory logging
  local trajectory_dir="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
  mkdir -p "$trajectory_dir"
  local trajectory_file="$trajectory_dir/adversarial-$(date -u +%Y-%m-%d).jsonl"

  local trajectory_entry
  trajectory_entry=$(echo "$result_json" | jq -c '{
    timestamp: .metadata.timestamp,
    type: .metadata.type,
    model: .metadata.model,
    sprint_id: .metadata.sprint_id,
    status: .metadata.status,
    finding_count: (.findings | length),
    cost_usd: .metadata.cost_usd
  }')

  # Append with flock if available, otherwise mkdir-based lock
  if command -v flock &>/dev/null; then
    (
      flock -w 5 200
      echo "$trajectory_entry" >> "$trajectory_file"
    ) 200>"${trajectory_file}.lock"
  else
    # Portable fallback: mkdir-based lock
    local lock_dir="${trajectory_file}.lockdir"
    local max_wait=5 waited=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
      ((waited++))
      if [[ $waited -ge $max_wait ]]; then
        log "WARNING: Could not acquire lock, writing without lock"
        echo "$trajectory_entry" >> "$trajectory_file"
        return 0
      fi
      sleep 1
    done
    echo "$trajectory_entry" >> "$trajectory_file"
    rmdir "$lock_dir"
  fi
}

# =============================================================================
# Main
# =============================================================================

main() {
  local type="" sprint_id="" diff_file="" context_file="" model="" budget="" timeout=""
  local dry_run="false" json_output="true"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)       type="$2"; shift 2 ;;
      --sprint-id)  sprint_id="$2"; shift 2 ;;
      --diff-file)  diff_file="$2"; shift 2 ;;
      --context-file) context_file="$2"; shift 2 ;;
      --model)      model="$2"; shift 2 ;;
      --budget)     budget="$2"; shift 2 ;;
      --timeout)    timeout="$2"; shift 2 ;;
      --dry-run)    dry_run="true"; shift ;;
      --json)       json_output="true"; shift ;;
      *)            error "Unknown option: $1"; exit 2 ;;
    esac
  done

  # Validate required args
  if [[ -z "$type" ]]; then error "Missing --type"; exit 2; fi
  if [[ "$type" != "review" && "$type" != "audit" ]]; then
    error "Invalid --type: $type (must be review or audit)"; exit 2
  fi
  if [[ -z "$sprint_id" ]]; then error "Missing --sprint-id"; exit 2; fi
  if [[ -z "$diff_file" ]]; then error "Missing --diff-file"; exit 2; fi
  if [[ ! -f "$diff_file" ]]; then error "Diff file not found: $diff_file"; exit 2; fi

  # Load config
  load_adversarial_config "$type"

  # Apply argument overrides
  model="${model:-$CONF_MODEL}"
  budget="${budget:-$CONF_BUDGET_CENTS}"
  timeout="${timeout:-$CONF_TIMEOUT}"

  # Check enabled
  if [[ "$CONF_ENABLED" != "true" ]]; then
    log "Adversarial $type review is disabled"
    jq -n --arg type "$type" '{findings: [], metadata: {type: $type, status: "disabled"}}'
    exit 1
  fi

  log "Starting adversarial $type review for $sprint_id"
  log "Model: $model, Budget: ${budget}c, Timeout: ${timeout}s"

  # Create per-run workdir (concurrency safety)
  # NOTE: workdir must NOT be local — the EXIT trap runs in global scope
  # where local variables are out of scope, causing "unbound variable" with set -u.
  _ADVERSARIAL_WORKDIR="/tmp/adversarial-${sprint_id}-$$"
  mkdir -p "$_ADVERSARIAL_WORKDIR"
  chmod 700 "$_ADVERSARIAL_WORKDIR"
  trap 'rm -rf "$_ADVERSARIAL_WORKDIR"' EXIT

  # Extract diff file list
  local diff_files
  diff_files=$(grep -E '^diff --git a/' "$diff_file" | sed 's|^diff --git a/\(.*\) b/.*|\1|' || true)

  # Budget pre-check (before API call per sprint Task 1.3)
  local diff_size_bytes
  diff_size_bytes=$(wc -c < "$diff_file")
  local estimated_input_tokens=$(( diff_size_bytes / 3 + 500 ))  # bytes/3 for code, +500 for system prompt
  # Rough cost estimate: input_tokens * $10/1M + estimated_output * $30/1M
  local estimated_cost_cents
  estimated_cost_cents=$(echo "scale=0; ($estimated_input_tokens * 10 / 10000) + (2000 * 30 / 10000)" | bc -l 2>/dev/null || echo "0")
  if [[ $estimated_cost_cents -gt $budget ]]; then
    error "Estimated cost (${estimated_cost_cents}c) exceeds budget (${budget}c)"
    jq -n --arg type "$type" --argjson est "$estimated_cost_cents" --argjson bud "$budget" \
      '{findings: [], metadata: {type: $type, status: "budget_exceeded",
        estimated_cents: $est, budget_cents: $bud}}'
    exit 4
  fi

  # Assemble context
  local context_json
  context_json=$(assemble_dissent_context "$diff_file" "$type" "$context_file")

  # Write prompts to workdir
  echo "$context_json" | jq -r '.system_prompt' > "$_ADVERSARIAL_WORKDIR/system-prompt.txt"
  echo "$context_json" | jq -r '.user_prompt' > "$_ADVERSARIAL_WORKDIR/user-prompt.txt"

  if [[ "$dry_run" == "true" ]]; then
    log "Dry run — context assembled, skipping API call"
    local escalated
    escalated=$(echo "$context_json" | jq -r '.context_escalated')
    jq -n --arg type "$type" --arg sid "$sprint_id" --argjson esc "$escalated" \
      '{dry_run: true, type: $type, sprint_id: $sid, context_escalated: $esc,
        system_prompt_tokens: ($ARGS.positional[0] | tonumber),
        user_prompt_tokens: ($ARGS.positional[1] | tonumber)}' \
      --jsonargs \
      "$(estimate_tokens "$(cat "$_ADVERSARIAL_WORKDIR/system-prompt.txt")")" \
      "$(estimate_tokens "$(cat "$_ADVERSARIAL_WORKDIR/user-prompt.txt")")"
    exit 0
  fi

  # Invoke dissenter
  local raw_response="" api_exit=0
  raw_response=$(invoke_dissenter "$_ADVERSARIAL_WORKDIR/system-prompt.txt" "$_ADVERSARIAL_WORKDIR/user-prompt.txt" "$model" "$timeout") || api_exit=$?

  # Process findings (4-state machine)
  local result
  result=$(process_findings "$raw_response" "$type" "$model" "$sprint_id" "$api_exit" "$diff_files")

  # Write output
  write_output "$result" "$sprint_id" "$type"

  # Output to stdout
  echo "$result"
}

main "$@"
