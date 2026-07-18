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
#   --model <model>           Dissenter model (default: from config or gpt-5.3-codex)
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

# sprint-bug-172 / bug-911: sha256_portable from compat-lib.
# Defensive source pattern (`|| true`) mirrors the lib-content.sh import
# below: under eval-based test sourcing, BASH_SOURCE[0] resolves to a bats
# temp file, so the absolute SCRIPT_DIR-rooted path is the safe form, and
# the soft-failure allows tests to pre-source compat-lib.sh in setup().
# See: Bridgebuilder Review Finding #1 (PR #235), KF-011 debug regression.
_COMPAT_LIB_PATH="$SCRIPT_DIR/compat-lib.sh"
# shellcheck source=compat-lib.sh
source "$_COMPAT_LIB_PATH" 2>/dev/null || true

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

# cycle-117 item D (#1177): shared DEGRADED/FAILED trajectory + page helper.
# Same defensive `|| true` soft-source as the libs above — sourcing must not
# fail under eval-based test sourcing or on a downstream repo mid-update.
_DEGRADED_VERDICT_LIB_PATH="$SCRIPT_DIR/lib/degraded-verdict-lib.sh"
# shellcheck source=lib/degraded-verdict-lib.sh
source "$_DEGRADED_VERDICT_LIB_PATH" 2>/dev/null || true

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
  CONF_MODEL="gpt-5.3-codex"
  CONF_TIMEOUT=60
  CONF_BUDGET_CENTS=150
  CONF_ESCALATION_ENABLED="true"
  CONF_SECONDARY_BUDGET=$DEFAULT_SECONDARY_TOKEN_BUDGET
  CONF_MAX_FILE_LINES=500
  CONF_MAX_FILE_BYTES=51200
  CONF_SECRET_SCANNING="true"
  CONF_SECRET_ALLOWLIST=()  # Patterns that should NOT be redacted
  # cycle-119 C14 (KF-004 repair loop) — default OFF. Only wired under
  # flatline_protocol.code_review in .loa.config.yaml.example per spec;
  # loaded generically here (keyed by config_key like every other knob
  # above) so a downstream repo can opt audit in independently.
  CONF_REPAIR_LOOP="false"

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
  CONF_MODEL=$(yq eval ".flatline_protocol.${config_key}.model // \"gpt-5.3-codex\"" "$CONFIG_FILE" 2>/dev/null || echo "gpt-5.3-codex")
  CONF_TIMEOUT=$(yq eval ".flatline_protocol.${config_key}.timeout_seconds // 60" "$CONFIG_FILE" 2>/dev/null || echo "60")
  CONF_BUDGET_CENTS=$(yq eval ".flatline_protocol.${config_key}.budget_cents // 150" "$CONFIG_FILE" 2>/dev/null || echo "150")
  CONF_ESCALATION_ENABLED=$(yq eval ".flatline_protocol.context_escalation.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")
  CONF_SECONDARY_BUDGET=$(yq eval ".flatline_protocol.context_escalation.secondary_token_budget // $DEFAULT_SECONDARY_TOKEN_BUDGET" "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_SECONDARY_TOKEN_BUDGET")
  CONF_MAX_FILE_LINES=$(yq eval ".flatline_protocol.context_escalation.max_file_lines // 500" "$CONFIG_FILE" 2>/dev/null || echo "500")
  CONF_MAX_FILE_BYTES=$(yq eval ".flatline_protocol.context_escalation.max_file_bytes // 51200" "$CONFIG_FILE" 2>/dev/null || echo "51200")
  CONF_SECRET_SCANNING=$(yq eval ".flatline_protocol.secret_scanning.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")
  CONF_REPAIR_LOOP=$(yq eval ".flatline_protocol.${config_key}.repair_loop // false" "$CONFIG_FILE" 2>/dev/null || echo "false")

  # Security invariant: secret_scanning MUST be on. Override if config says false.
  if [[ "$CONF_SECRET_SCANNING" != "true" ]]; then
    echo "CRITICAL: secret_scanning.enabled is false — overriding to true. Raw code must never be sent to external providers without redaction." >&2
    CONF_SECRET_SCANNING="true"
  fi

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
          al_idx=$((al_idx + 1))
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

# cycle-102 sprint-1F (#814 / KF-004 closure): companion to validate_finding
# that returns a specific reject reason on stdout. Used by the rejection
# sidecar so operators triaging "0 findings + N silent rejections" can see
# WHY each payload was dropped without re-running the dissenter.
#
# Returns empty string on stdout if valid; first-failing-rule reason if not.
# Mirrors validate_finding's rule order so the boolean fast-path stays the
# canonical truth and the reason path is diagnostic-only.
_validate_finding_reason() {
  local finding="$1"
  local type="$2"

  local valid_severities
  if [[ "$type" == "review" ]]; then
    valid_severities='["BLOCKING","ADVISORY"]'
  else
    valid_severities='["CRITICAL","HIGH","MEDIUM","LOW"]'
  fi
  local valid_categories='["injection","authz","data-loss","null-safety","concurrency","type-error","resource-leak","error-handling","spec-violation","performance","secrets","xss","ssrf","deserialization","crypto","info-disclosure","rate-limiting","input-validation","config","other"]'

  echo "$finding" | jq -r --argjson sevs "$valid_severities" --argjson cats "$valid_categories" '
    if (.id // null) == null or (.id | type) != "string" then
      "missing-or-non-string-id"
    elif (.severity // null) == null then
      "missing-severity"
    elif ((.severity | IN($sevs[])) | not) then
      "severity-not-in-enum (got: \(.severity // "null"))"
    elif (.category // null) == null then
      "missing-category"
    elif ((.category | IN($cats[])) | not) then
      "category-not-in-enum (got: \(.category // "null"))"
    elif (.description // null) == null or (.description | type) != "string" or (.description | length) == 0 then
      "missing-or-empty-description"
    elif (.failure_mode // null) == null or (.failure_mode | type) != "string" or (.failure_mode | length) == 0 then
      "missing-or-empty-failure_mode"
    else
      ""
    end
  ' 2>/dev/null
}

# cycle-102 sprint-1F (#814 / KF-004 closure): write a rejected-finding entry
# to the per-sprint sidecar JSONL. One entry per rejected finding, append-only
# within a single process_findings invocation. Schema:
#   {ts_utc, sprint_id, type, model, index, reject_reason, payload}
# Caller MUST have ensured the sidecar parent dir exists and (optionally)
# truncated the file at the start of process_findings.
#
# cycle-119 C14 (KF-004 repair loop): two OPTIONAL trailing args,
# repair_attempted / repair_succeeded ("true"/"false"). Omitted (empty
# string, the default) => neither key is added to the entry, so callers
# that don't pass them (repair_loop disabled) get the byte-identical
# legacy schema. Passed => booleans are added, per C14 contract item 5.
_write_rejected_sidecar() {
  local sidecar_path="$1"
  local finding="$2"
  local reject_reason="$3"
  local index="$4"
  local sprint_id="$5"
  local type="$6"
  local model="$7"
  local repair_attempted="${8:-}"
  local repair_succeeded="${9:-}"

  [[ -n "$sidecar_path" ]] || return 0

  jq -nc \
    --argjson f "$finding" \
    --arg r "${reject_reason:-unknown-reason}" \
    --argjson idx "$index" \
    --arg sid "$sprint_id" \
    --arg t "$type" \
    --arg m "$model" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg ra "$repair_attempted" \
    --arg rs "$repair_succeeded" \
    '{ts_utc: $ts, sprint_id: $sid, type: $t, model: $m, index: $idx, reject_reason: $r, payload: $f}
     + (if $ra == "" then {} else {repair_attempted: ($ra == "true")} end)
     + (if $rs == "" then {} else {repair_succeeded: ($rs == "true")} end)' \
    >> "$sidecar_path" 2>/dev/null || true
}

# =============================================================================
# KF-004 Repair Loop (cycle-119 C14) — flag default OFF
# =============================================================================
# When flatline_protocol.code_review.repair_loop is true, a finding that
# fails validate_finding gets ONE bounded repair round-trip to the SAME
# model before being rejected. Four safety constraints (adversarial
# design panel, non-negotiable):
#   1. Normalization pre-pass BEFORE validate_finding: case-fold
#      severity/category + whitespace trim ONLY — no synonym mapping.
#      (_normalize_finding_for_validation, below.)
#   2. On residual validation failure: ONE repair round-trip to the SAME
#      model, sending ONLY the offending finding JSON + the violated
#      clause text from _validate_finding_reason.
#      (_repair_finding_via_model, below.)
#   3. The repaired finding re-enters the FULL pipeline — validate_finding
#      AND the anchor/hallucination stages — never just the failed clause.
#      Wired into process_findings' main loop: a successful repair is
#      pushed through validate_anchor exactly like any first-try-valid
#      finding, and the hallucination filter runs unconditionally on the
#      whole result array later in main().
#   4. Byte-diff immutability guard: every field EXCEPT the violated
#      one(s) must be byte-identical to the rejected original, else
#      sidecar with reject_reason=repair-mutated-nonviolated-field.
#      (_repair_diff_ok, below.)

# _normalize_finding_for_validation <finding_json>
# Case-fold + trim ONLY. severity -> upper (matches the uppercase enum);
# category -> lower (matches the lowercase enum). No synonym mapping — a
# model that emits "warning" instead of "ADVISORY" still gets rejected.
# Absent keys stay absent (no null keys introduced).
_normalize_finding_for_validation() {
  local finding="$1"
  echo "$finding" | jq '
    (if has("severity") and (.severity | type) == "string"
     then .severity |= (gsub("^\\s+|\\s+$"; "") | ascii_upcase)
     else . end)
    | (if has("category") and (.category | type) == "string"
       then .category |= (gsub("^\\s+|\\s+$"; "") | ascii_downcase)
       else . end)
  ' 2>/dev/null
}

# _repair_violated_field <reject_reason>
# Maps a _validate_finding_reason string to the single field name it
# names as violated. Unknown/unmapped reasons yield "" (empty) — the
# byte-diff guard then requires the repaired finding to be fully
# identical to the original (no field is authorized to change).
_repair_violated_field() {
  local reason="$1"
  case "$reason" in
    missing-or-non-string-id)        echo "id" ;;
    missing-severity|severity-not-in-enum*)  echo "severity" ;;
    missing-category|category-not-in-enum*)  echo "category" ;;
    missing-or-empty-description)    echo "description" ;;
    missing-or-empty-failure_mode)   echo "failure_mode" ;;
    *)                                echo "" ;;
  esac
}

# _repair_diff_ok <original_json> <repaired_json> <allowed_field>
# Structural-equality guard (jq ==, so key order/whitespace never counts
# as a mutation): original and repaired must be identical after deleting
# allowed_field from both. Catches added/removed keys AND changed values
# on any field other than the one the model was authorized to touch.
_repair_diff_ok() {
  local original="$1"
  local repaired="$2"
  local allowed_field="$3"

  jq -e -n --argjson orig "$original" --argjson rep "$repaired" --arg af "$allowed_field" '
    ($orig | del(.[$af])) == ($rep | del(.[$af]))
  ' >/dev/null 2>&1
}

# _repair_finding_via_model <finding_json> <type> <violated_clause> <model> <timeout>
# ONE bounded repair round-trip to the SAME model. Sends ONLY the
# offending finding JSON + the violated-clause reason text — never the
# diff, never other findings (bounded cost, bounded blast radius per the
# adversarial panel). Prints the repaired finding JSON on stdout; prints
# nothing and returns non-zero on any failure (missing binary, timeout,
# unparseable response) — caller treats that as "repair unavailable".
#
# Test seam: bats tests source this file and REDEFINE this function with
# a mock responder (bash allows re-declaring a sourced function) — see
# tests/unit/adversarial-review-repair-loop.bats. This real implementation
# is only exercised in a live run with repair_loop enabled.
_repair_finding_via_model() {
  local finding_json="$1"
  local type="$2"
  local violated_clause="$3"
  local model="$4"
  local timeout="${5:-60}"

  local workdir
  workdir=$(mktemp -d "${TMPDIR:-/tmp}/adv-repair.XXXXXX") || return 1
  local sys_file="$workdir/repair-system.txt"
  local user_file="$workdir/repair-user.txt"

  cat > "$sys_file" <<'EOF'
You are repairing a single adversarial-review finding JSON object that
failed schema validation. You will be given the finding object and the
SPECIFIC violated validation clause. Return ONLY the corrected finding as
a single JSON object on stdout — no markdown fences, no prose, no
surrounding envelope. Change ONLY the field(s) needed to satisfy the
stated violation. Every other field MUST remain byte-identical to the
input (do not add, remove, or rename any field).
EOF

  if ! jq -n --argjson f "$finding_json" --arg vc "$violated_clause" \
      '{finding: $f, violated_clause: $vc}' > "$user_file" 2>/dev/null; then
    rm -rf "$workdir" 2>/dev/null || true
    return 1
  fi

  local raw rc=0
  raw=$(invoke_dissenter "$sys_file" "$user_file" "$model" "$timeout" "" "$type" 2>/dev/null) || rc=$?
  rm -rf "$workdir" 2>/dev/null || true
  [[ $rc -eq 0 ]] || return 1
  [[ -n "$raw" ]] || return 1

  local content
  content=$(printf '%s' "$raw" | jq -r '.content // empty' 2>/dev/null) || return 1
  [[ -n "$content" ]] || return 1

  # Extract the first balanced JSON object from the (possibly
  # fence-wrapped / prose-prefixed) content, mirroring process_findings'
  # own reasoning-class-model tolerance (KF-011).
  local extracted
  extracted=$(printf '%s' "$content" | python3 -c '
import sys, json
text = sys.stdin.read()
decoder = json.JSONDecoder()
i = 0
while i < len(text):
    if text[i] == "{":
        try:
            obj, _ = decoder.raw_decode(text[i:])
            print(json.dumps(obj))
            break
        except json.JSONDecodeError:
            pass
    i += 1
' 2>/dev/null) || return 1
  [[ -n "$extracted" ]] || return 1
  printf '%s' "$extracted"
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
      escalated_count=$((escalated_count + 1))
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
  # cycle-109 Sprint 2 T2.5 — optional sidecar path. When provided,
  # LOA_VERDICT_QUALITY_SIDECAR is exported for the cheval subprocess
  # so the verdict_quality envelope lands in this file. Backward-compat:
  # callers that don't pass the arg get the legacy non-sidecar behavior.
  local vq_sidecar="${5:-}"
  # Cycle-112 D-6 (#931) — attribution type so MODELINV envelopes record
  # which phase of adversarial review (review/audit/design) issued the
  # call. Defaults empty for backward-compat with any pre-D-6 caller.
  local type="${6:-}"

  # Build the skill string for /loa status --economy attribution AND
  # (cycle-119 C16 / D-6 slice) MODELINV calling_primitive attribution —
  # model-adapter.sh forwards --skill straight through to cheval, which
  # stamps it into the MODELINV envelope. Value is exactly `adversarial-
  # <type>` (adversarial-review / adversarial-audit) per the C16 contract.
  # Empty when type wasn't supplied — model-adapter.sh treats absent
  # --skill as no-op.
  local -a skill_args=()
  if [[ -n "$type" ]]; then
    # bug-868 residue: also pass --phase so model-adapter logs the real
    # phase instead of its cosmetic "prd" default on review/audit calls.
    skill_args=(--skill "adversarial-$type" --phase "$type")
  fi

  if [[ -n "$vq_sidecar" ]]; then
    LOA_VERDICT_QUALITY_SIDECAR="$vq_sidecar" \
      "$SCRIPT_DIR/model-adapter.sh" \
      --model "$model" \
      --mode dissent \
      --input "$user_prompt_file" \
      --context "$system_prompt_file" \
      --timeout "$timeout" \
      ${skill_args[@]+"${skill_args[@]}"}
  else
    "$SCRIPT_DIR/model-adapter.sh" \
      --model "$model" \
      --mode dissent \
      --input "$user_prompt_file" \
      --context "$system_prompt_file" \
      --timeout "$timeout" \
      ${skill_args[@]+"${skill_args[@]}"}
  fi
}

# cycle-109 Sprint 2 T2.5 — verdict_quality multi-attempt aggregator.
# Shells out to the canonical Python aggregator
# (loa_cheval.verdict.aggregate per SDD §5.2.1) on the list of per-attempt
# envelope files collected during the fallback_chain walk. Bash never
# reimplements the merge logic — drift impossible by construction.
#
# Usage:
#   _adv_aggregate_envelopes <file1> [<file2> ...]
#     Echoes aggregated multi-voice envelope JSON (compact) to stdout.
#     Returns 0 on success, non-zero when no valid envelope files supplied.
#
# Skips missing / empty / malformed-JSON files silently — adversarial-
# review's fallback walk may produce zero or partial envelopes when
# cheval is older / a write failed / the sidecar mechanism is unavailable.
_adv_aggregate_envelopes() {
  local f
  local -a valid_files=()
  for f in "$@"; do
    [[ -s "$f" ]] || continue
    if jq empty < "$f" 2>/dev/null; then
      valid_files+=("$f")
    fi
  done
  if [[ ${#valid_files[@]} -eq 0 ]]; then
    return 1
  fi
  PYTHONPATH="$PROJECT_ROOT/.claude/adapters" \
    python3 -m loa_cheval.verdict.aggregate "${valid_files[@]}"
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
  # sprint-bug-208 (#1025) / KF-004 guard: a parse failure here must be LOUD
  # and route to malformed_response — never alias to empty-but-clean content.
  if ! content=$(echo "$raw_response" | JQ_STRICT_CTX="adversarial-review:content-extract" jq_strict -r '.content // empty'); then
    log "Adapter response is not parseable JSON — emitting malformed_response (KF-004 guard, #1025)"
    jq -n \
      --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
      --arg ts "$timestamp" \
      --arg err "adapter response failed JSON parse at content extraction" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "malformed_response", degraded: false, error: $err}}'
    return 0
  fi

  # Try to parse as JSON (handle markdown ```json wrapping)
  local parsed
  parsed=$(echo "$content" | sed -n '/^```json/,/^```$/p' | sed '1d;$d' 2>/dev/null || echo "")
  if [[ -z "$parsed" ]]; then
    parsed="$content"
  fi

  # KF-011 fix (closes second observation 2026-05-17): reasoning-class models
  # (gpt-5.5-pro, gpt-5.5, opus-4-7) now routinely emit a conversational
  # preamble BEFORE the JSON envelope, e.g.:
  #   "Using the `ubs` review skill because... I'll keep the final response
  #    to the requested JSON shape.\n{"findings":[...]}"
  # Direct jq on the full content fails because `.findings` doesn't exist at
  # the top level of "prose\n{json}". Extract the first balanced JSON object
  # containing "findings" using Python's json.JSONDecoder.raw_decode, which
  # handles arbitrarily nested envelopes safely. Falls back to original
  # `parsed` if no embedded envelope is found (preserves prior behavior for
  # the literal-JSON path).
  if ! echo "$parsed" | jq -e '.findings' >/dev/null 2>&1; then
    local extracted
    extracted=$(echo "$content" | python3 -c '
import sys, json
text = sys.stdin.read()
decoder = json.JSONDecoder()
i = 0
while i < len(text):
    if text[i] == "{":
        try:
            obj, _ = decoder.raw_decode(text[i:])
            if isinstance(obj, dict) and "findings" in obj:
                print(json.dumps(obj))
                break
        except json.JSONDecodeError:
            pass
    i += 1
' 2>/dev/null || echo "")
    if [[ -n "$extracted" ]]; then
      parsed="$extracted"
    fi
  fi

  # STATE 2: Malformed response
  local findings_array
  if ! findings_array=$(echo "$parsed" | JQ_STRICT_CTX="adversarial-review:findings-presence" jq_strict -r '.findings // empty'); then
    log "Parsed content failed JSON parse at findings extraction — malformed_response path (KF-004 guard, #1025)"
    findings_array=""
  fi
  if [[ -z "$findings_array" ]]; then
    log "Malformed response: missing 'findings' key"

    # KF-011 diagnostic capture (issue #930).
    # When LOA_ADVERSARIAL_DEBUG=1, write the raw response body to a sidecar
    # so future fixes can disambiguate between (a) prompt-schema drift,
    # (b) parser brittleness on wrapped envelopes, (c) reasoning-class
    # meta-commentary. Pipes through log-redactor for NFR-Sec-1.
    # Default behavior (env unset) is unchanged — no observable change.
    if [[ "${LOA_ADVERSARIAL_DEBUG:-0}" == "1" ]]; then
      local debug_dir="$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}"
      mkdir -p "$debug_dir" 2>/dev/null || true
      # Slug the model name to a filesystem-safe form (provider:id has `:`).
      # Use `__` so the namespace boundary stays visible in filenames
      # (single `_` would be ambiguous with literal underscores in model ids).
      local model_slug
      model_slug=$(echo "$model" | sed 's|:|__|g; s|/|__|g')
      # Slug colons out of the ISO timestamp too — `:` is illegal in
      # filenames on Windows/FAT and confuses cross-platform tarball
      # extraction. Replace with `-` for human readability.
      local timestamp_slug
      timestamp_slug=$(echo "$timestamp" | tr ':' '-')
      local debug_file="$debug_dir/adversarial-debug-${model_slug}-${timestamp_slug}.txt"
      local redactor="$PROJECT_ROOT/.claude/scripts/lib/log-redactor.sh"
      {
        echo "# KF-011 debug capture (LOA_ADVERSARIAL_DEBUG=1)"
        echo "# model: $model"
        echo "# sprint_id: $sprint_id"
        echo "# type: $type"
        echo "# timestamp: $timestamp"
        echo "# ---"
        echo "## raw_response (model-adapter envelope):"
        echo "$raw_response"
        echo ""
        echo "## extracted content (.content field):"
        echo "$content"
        echo ""
        echo "## parsed (post markdown-fence strip):"
        echo "$parsed"
      } | (
        if [[ -x "$redactor" ]]; then
          "$redactor"
        else
          cat
        fi
      ) > "$debug_file" 2>/dev/null || true
      log "KF-011 debug: raw response captured to $debug_file"
    fi

    jq -n \
      --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
      --arg ts "$timestamp" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "malformed_response", degraded: false}}'
    return 0
  fi

  # STATE 3: Empty findings
  local finding_count
  if ! finding_count=$(echo "$parsed" | JQ_STRICT_CTX="adversarial-review:finding-count" jq_strict '.findings | length'); then
    # KF-004: an extraction failure must NEVER alias to clean-zero — that is
    # the literal mechanism behind >=20 zero-findings canonical verdicts that
    # masked real findings (#1025).
    log "finding-count extraction failed on parsed content — emitting malformed_response, not clean-zero (KF-004 guard, #1025)"
    jq -n \
      --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
      --arg ts "$timestamp" \
      --arg err "finding-count extraction failed (.findings | length)" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "malformed_response", degraded: false, error: $err}}'
    return 0
  fi
  if [[ "$finding_count" == "0" ]]; then
    # bug-809: keep status "clean" for backward compat, but qualify it —
    # zero findings means nothing met the BLOCKING/ADVISORY bar, NOT an
    # affirmative approval of the reviewed surface. verdict_quality covers
    # the degraded axis; status_note covers the high-bar-lens axis.
    jq -n \
      --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
      --arg ts "$timestamp" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "clean",
        status_note: "no findings met the BLOCKING/ADVISORY bar — not an approval of unreviewed surface",
        degraded: false}}'
    return 0
  fi

  # STATE 4: Populated findings — validate and process
  #
  # cycle-102 sprint-1F (#814 / KF-004 closure): rejected-finding sidecar.
  # When validate_finding rejects a payload, the payload is preserved in
  # `adversarial-rejected-${type}.jsonl` alongside the main output. This
  # closes the silent-rejection observability gap that vision-024 named as
  # the third consensus-classification failure mode and that the operator's
  # suspicion-lens interjections caught manually across cycle-102.
  #
  # Sidecar is truncated at start of every process_findings invocation
  # (idempotent within a single run; multiple runs on the same sprint do
  # NOT accumulate). Disable via LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=1
  # (env opt-out for environments that can't write the sidecar).
  local rejected_sidecar=""
  if [[ -z "${LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE:-}" ]]; then
    local rej_dir="$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}"
    mkdir -p "$rej_dir" 2>/dev/null || true
    rejected_sidecar="$rej_dir/adversarial-rejected-${type}.jsonl"
    : > "$rejected_sidecar" 2>/dev/null || rejected_sidecar=""
  fi

  local validated_findings="[]"
  local i=0
  local rejected_count=0
  # cycle-119 C14 (KF-004 repair loop) — only meaningful when the flag is
  # on; stays 0 and is omitted from output metadata otherwise (flag OFF
  # must be byte-identical legacy behavior).
  local repaired_count=0
  while [[ $i -lt $finding_count ]]; do
    local finding
    finding=$(echo "$parsed" | jq ".findings[$i]")

    # Constraint 1: normalization pre-pass BEFORE validate_finding —
    # case-fold + trim ONLY, gated entirely behind the flag so disabled
    # behavior never differs from pre-C14.
    local candidate="$finding"
    if [[ "${CONF_REPAIR_LOOP:-false}" == "true" ]]; then
      candidate=$(_normalize_finding_for_validation "$finding")
    fi

    if validate_finding "$candidate" "$type"; then
      # Run anchor validation
      local validated
      validated=$(validate_anchor "$candidate" "$type" "$diff_files")
      validated_findings=$(echo "$validated_findings" | jq --argjson f "$validated" '. + [$f]')
    else
      local reject_reason
      reject_reason=$(_validate_finding_reason "$candidate" "$type")

      local repair_attempted="false" repair_succeeded="false"
      local sidecar_reject_reason="$reject_reason"
      local accepted_finding=""

      if [[ "${CONF_REPAIR_LOOP:-false}" == "true" ]]; then
        repair_attempted="true"
        local violated_field
        violated_field=$(_repair_violated_field "$reject_reason")
        local repaired
        if repaired=$(_repair_finding_via_model "$candidate" "$type" "$reject_reason" "$model" "${CONF_TIMEOUT:-60}") \
           && [[ -n "$repaired" ]] \
           && echo "$repaired" | jq empty >/dev/null 2>&1; then
          if _repair_diff_ok "$candidate" "$repaired" "$violated_field"; then
            # Constraint 3: repaired finding re-enters the FULL pipeline —
            # validate_finding + validate_anchor here; the hallucination
            # filter runs unconditionally on the whole result array later
            # in main(), so a successful repair passes through it too.
            if validate_finding "$repaired" "$type"; then
              accepted_finding=$(validate_anchor "$repaired" "$type" "$diff_files")
              repair_succeeded="true"
            else
              sidecar_reject_reason=$(_validate_finding_reason "$repaired" "$type")
            fi
          else
            # Constraint 4: byte-diff immutability guard failed.
            sidecar_reject_reason="repair-mutated-nonviolated-field"
          fi
        fi
        # Repair call itself failed/unavailable: sidecar_reject_reason
        # stays the original reject_reason — repair_attempted=true,
        # repair_succeeded=false still records that a round-trip happened.
      fi

      if [[ "$repair_succeeded" == "true" ]]; then
        validated_findings=$(echo "$validated_findings" | jq --argjson f "$accepted_finding" '. + [$f]')
        repaired_count=$((repaired_count + 1))
      else
        log "Rejected invalid finding at index $i: ${sidecar_reject_reason:-unknown-reason}"
        if [[ "${CONF_REPAIR_LOOP:-false}" == "true" ]]; then
          _write_rejected_sidecar "$rejected_sidecar" "$finding" "$sidecar_reject_reason" "$i" "$sprint_id" "$type" "$model" "$repair_attempted" "$repair_succeeded"
        else
          _write_rejected_sidecar "$rejected_sidecar" "$finding" "$sidecar_reject_reason" "$i" "$sprint_id" "$type" "$model"
        fi
        rejected_count=$((rejected_count + 1))
      fi
    fi
    i=$((i + 1))
  done

  # cycle-102 sprint-1F: surface aggregate rejection count in the main
  # output's metadata so consumers (operator, /audit-sprint, BB triage) see
  # the rejection signal without needing to grep stderr or open the sidecar.
  # The sidecar path is also surfaced for one-jump triage.

  # Extract token/cost metadata from model-adapter response
  local tokens_in tokens_out cost latency
  tokens_in=$(echo "$raw_response" | jq -r '.tokens_input // 0')
  tokens_out=$(echo "$raw_response" | jq -r '.tokens_output // 0')
  cost=$(echo "$raw_response" | jq -r '.cost_usd // 0')
  latency=$(echo "$raw_response" | jq -r '.latency_ms // 0')

  # Compute relative path to sidecar from PROJECT_ROOT (cleaner for downstream
  # logs / triage). Empty string when sidecar disabled.
  local rejected_sidecar_rel=""
  if [[ -n "$rejected_sidecar" ]]; then
    rejected_sidecar_rel="${rejected_sidecar#"$PROJECT_ROOT/"}"
  fi

  # cycle-119 C14: repaired_count only appears in metadata when the flag
  # is on — omitted entirely when off, so the envelope is byte-identical
  # to pre-C14 output in the disabled (default) case.
  local repair_metadata_json="{}"
  if [[ "${CONF_REPAIR_LOOP:-false}" == "true" ]]; then
    repair_metadata_json=$(jq -nc --argjson rc "$repaired_count" '{repaired_count: $rc}')
  fi

  jq -n \
    --argjson findings "$validated_findings" \
    --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
    --arg ts "$timestamp" \
    --argjson ti "$tokens_in" --argjson to "$tokens_out" \
    --argjson cost "$cost" --argjson lat "$latency" \
    --argjson rejc "$rejected_count" \
    --arg rejs "$rejected_sidecar_rel" \
    --argjson repairmeta "$repair_metadata_json" \
    '{findings: $findings, metadata: ({type: $type, model: $model, sprint_id: $sid,
      timestamp: $ts, tokens_input: $ti, tokens_output: $to, cost_usd: $cost,
      latency_ms: $lat, status: "reviewed", degraded: false,
      rejected_count: $rejc,
      rejected_sidecar: (if $rejs == "" then null else $rejs end)} + $repairmeta)}'
}

# =============================================================================
# Dissenter Hallucination Filter — cycle-093 T1.3 / #618
# =============================================================================
# Certain dissenter models (notably gpt-5.2 in ampersand-adjacent bash/TS
# contexts) hallucinate literal `{{DOCUMENT_CONTENT}}` tokens into findings
# that never appeared in the source. At 50% rate on shell/TS diffs this
# drives ~10 min/review of manual triage per the #618 field report.
#
# This filter applies bidirectional token-match semantics per Flatline IMP-003:
#
#   | Diff contains token | Finding contains token | Action                      |
#   |---------------------|------------------------|-----------------------------|
#   | No                  | Yes                    | Downgrade to ADVISORY       |
#   | No                  | No                     | No-op                       |
#   | Yes                 | Yes                    | No-op (legitimate doc/tpl)  |
#   | Yes                 | No                     | No-op                       |
#
# Normalization per SDD §3.7 recognizes variants the model emits:
# canonical, escaped ({{DOCUMENT_CONTENT}}, \{\{DOCUMENT_CONTENT\}\}),
# spaced ({{ DOCUMENT_CONTENT }}), case variants, and bare DOCUMENT_CONTENT
# token outside braces.

# _normalize_doc_content_tokens — stdin → stdout
# Normalizes escape/spacing/case variants to canonical {{DOCUMENT_CONTENT}}.
_normalize_doc_content_tokens() {
    sed -E '
        s/\\\{\\\{/{{/g;
        s/\\\}\\\}/}}/g;
        s/\{\{[[:space:]]*([Dd][Oo][Cc][Uu][Mm][Ee][Nn][Tt]_[Cc][Oo][Nn][Tt][Ee][Nn][Tt])[[:space:]]*\}\}/{{DOCUMENT_CONTENT}}/g;
    '
}

# _text_contains_doc_content_token <text> — returns 0 if any variant present
_text_contains_doc_content_token() {
    local text="$1"
    local normalized
    normalized=$(printf '%s' "$text" | _normalize_doc_content_tokens)
    # Match canonical brace form OR bare-word DOCUMENT_CONTENT (case-insensitive)
    echo "$normalized" | grep -qiE '\{\{DOCUMENT_CONTENT\}\}|\bDOCUMENT_CONTENT\b'
}

# _apply_hallucination_filter <process_findings_result> <diff_file_path>
# → stdout: modified result with suspect findings downgraded, AND with
#   `metadata.hallucination_filter` ALWAYS populated (cycle-094 G-6).
# Non-fatal on all errors: on any failure, returns input unchanged (safe default).
#
# Metadata schema:
#   metadata.hallucination_filter = {
#     applied: bool,             // did the filter traverse findings?
#     downgraded: int,           // number of findings downgraded (0 if !applied)
#     reason: string (optional)  // present when applied=false; one of:
#                                //   "no_diff_file", "no_findings", "diff_contains_token"
#   }
_apply_hallucination_filter() {
    local result="$1"
    local diff_file="$2"

    # Defensive: missing diff file → emit metadata with reason, return.
    # G-6 (cycle-094): metadata is always present on the result; absence
    # was previously ambiguous between "filter not run" and "filter ran with
    # no downgrades". Now `applied: false, reason: "no_diff_file"` makes
    # the early-return state legible.
    if [[ -z "$diff_file" ]] || [[ ! -f "$diff_file" ]]; then
        printf '%s' "$result" | jq '.metadata.hallucination_filter = {applied: false, downgraded: 0, reason: "no_diff_file"}'
        return 0
    fi

    # Short-circuit: no findings → nothing to filter, but emit metadata.
    local finding_count
    if ! finding_count=$(echo "$result" | JQ_STRICT_CTX="adversarial-review:hallucination-filter" jq_strict '.findings | length'); then
        # Documented non-fatal contract: return input unchanged — but LOUDLY
        # (#1025). Annotating an unparseable result is impossible; the
        # downstream result-status guard handles the malformed result.
        log "hallucination filter: result unparseable — passing through unchanged (KF-004 guard, #1025)"
        printf '%s' "$result"
        return 0
    fi
    if [[ "$finding_count" == "0" ]]; then
        printf '%s' "$result" | jq '.metadata.hallucination_filter = {applied: false, downgraded: 0, reason: "no_findings"}'
        return 0
    fi

    # Check if diff legitimately contains the token (handles docs/templates that discuss it)
    local diff_has_token="false"
    if _text_contains_doc_content_token "$(cat "$diff_file")"; then
        diff_has_token="true"
    fi

    # If diff DIRTY, any finding mentioning the token could be legitimate —
    # no-op on findings, but emit metadata so downstream consumers can
    # distinguish "filter ran and decided not to downgrade" from
    # "filter never ran".
    if [[ "$diff_has_token" == "true" ]]; then
        printf '%s' "$result" | jq '.metadata.hallucination_filter = {applied: false, downgraded: 0, reason: "diff_contains_token"}'
        return 0
    fi

    # Diff CLEAN: iterate findings, downgrade any that mention the token family
    local filtered='[]'
    local downgrade_count=0
    local i=0
    while [[ $i -lt $finding_count ]]; do
        local finding description suggested_fix combined
        finding=$(echo "$result" | jq ".findings[$i]")
        description=$(echo "$finding" | jq -r '.description // ""')
        suggested_fix=$(echo "$finding" | jq -r '.suggested_fix // ""')
        combined="$description $suggested_fix"

        if _text_contains_doc_content_token "$combined"; then
            # Downgrade: severity → ADVISORY, category → MODEL_ARTEFACT_SUSPECTED,
            # prefix description with downgrade marker so reviewers see it fired
            finding=$(echo "$finding" | jq '
                .severity = "ADVISORY"
                | .category = "MODEL_ARTEFACT_SUSPECTED"
                | .description = "[downgraded: dissenter-output contained {{DOCUMENT_CONTENT}} token that is absent from the diff] " + (.description // "")
            ')
            downgrade_count=$((downgrade_count + 1))
        fi

        filtered=$(echo "$filtered" | jq --argjson f "$finding" '. + [$f]')
        i=$((i + 1))
    done

    if [[ "$downgrade_count" -gt 0 ]]; then
        log "Hallucination filter downgraded $downgrade_count finding(s) to ADVISORY (#618 mitigation)"
        result=$(echo "$result" | jq \
            --argjson filtered "$filtered" \
            --argjson downgraded "$downgrade_count" \
            '.findings = $filtered
             | .metadata.hallucination_filter = {applied: true, downgraded: $downgraded}')
    else
        result=$(echo "$result" | jq '.metadata.hallucination_filter = {applied: true, downgraded: 0}')
    fi

    printf '%s' "$result"
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
    printf 'noanch:%s:%s' "$category" "$index" | sha256_portable | cut -c1-8
  else
    printf '%s:%s' "$anchor" "$category" | sha256_portable | cut -c1-8
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
      i=$((i + 1))
    done
    echo "$result"
    return 0
  fi

  local existing_findings
  # sprint-bug-208 (#1025): a corrupt existing-findings file must fail the
  # merge loudly — silently merging against [] would drop prior findings.
  # `.findings // []` still yields [] for a VALID file without the key
  # (absence != parse failure).
  if ! existing_findings=$(JQ_STRICT_CTX="adversarial-review:merge-existing" jq_strict '.findings // []' "$existing_file"); then
    log "merge_findings: existing findings file unparseable: $existing_file (KF-004 guard, #1025)"
    return 1
  fi
  # DISS-002 (review iter-1): jq exits 0 with NO output on zero-byte input —
  # the swallow's quieter sibling. A valid findings artifact is never empty;
  # refuse to merge against unknown state.
  if [[ -z "$existing_findings" ]]; then
    log "merge_findings: existing findings file is empty — refusing merge against unknown state: $existing_file (KF-004 guard, #1025)"
    return 1
  fi

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
    i=$((i + 1))
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
  # cycle-117 item D (#1177): exit code of the last-attempted model in the
  # fallback chain (0 when the winning attempt succeeded). Optional —
  # callers that don't have one (none currently) get the "-" no-op default.
  local api_exit_code="${4:--}"

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
      waited=$((waited + 1))
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

  # cycle-117 item D (#1177): uniform DEGRADED/FAILED trajectory record +
  # page. Preferred signal: result_json.verdict_quality.status (the
  # multi-voice aggregator's canonical classification, SDD §3.2.2).
  # Fallback (no envelope — legacy/pre-T2.3 cheval emits, or the STATE-1
  # api_failure short-circuit in process_findings which never reaches the
  # aggregator): metadata.status == "api_failure" counts as DEGRADED for
  # THIS signal regardless of type (review or audit) — deliberately
  # broader than the pre-existing metadata.degraded field (audit-only,
  # left untouched below), since a review-type API outage is exactly the
  # crate 4-day-outage scenario this signal exists to catch.
  local _c117d_band="" _c117d_reason="unknown" _c117d_mec="$api_exit_code"
  local -a _c117d_legs=()
  local _c117d_vq_status
  _c117d_vq_status=$(echo "$result_json" | jq -r '.verdict_quality.status // empty' 2>/dev/null) || _c117d_vq_status=""
  if [[ -n "$_c117d_vq_status" ]]; then
    _c117d_band="$_c117d_vq_status"
    _c117d_reason=$(echo "$result_json" | jq -r '.verdict_quality.voices_dropped[0].reason // "unknown"' 2>/dev/null) || _c117d_reason="unknown"
    local _c117d_vq_mec
    _c117d_vq_mec=$(echo "$result_json" | jq -r '.verdict_quality.voices_dropped[0].exit_code // empty' 2>/dev/null) || _c117d_vq_mec=""
    [[ -n "$_c117d_vq_mec" ]] && _c117d_mec="$_c117d_vq_mec"
    while IFS= read -r _c117d_leg; do
      [[ -n "$_c117d_leg" ]] && _c117d_legs+=("$_c117d_leg")
    done < <(echo "$result_json" | jq -r '.verdict_quality.voices_dropped[]?.voice // empty' 2>/dev/null)
  else
    local _c117d_meta_status
    _c117d_meta_status=$(echo "$result_json" | jq -r '.metadata.status // empty' 2>/dev/null) || _c117d_meta_status=""
    if [[ "$_c117d_meta_status" == "api_failure" ]]; then
      _c117d_band="DEGRADED"
      _c117d_reason=$(echo "$result_json" | jq -r '.metadata.error // "unknown"' 2>/dev/null) || _c117d_reason="unknown"
      local _c117d_meta_model
      _c117d_meta_model=$(echo "$result_json" | jq -r '.metadata.model // empty' 2>/dev/null) || _c117d_meta_model=""
      [[ -n "$_c117d_meta_model" ]] && _c117d_legs+=("$_c117d_meta_model")
    fi
  fi

  if [[ "$_c117d_band" == "DEGRADED" || "$_c117d_band" == "FAILED" ]] \
     && declare -F degraded_verdict_maybe_emit >/dev/null 2>&1; then
    degraded_verdict_maybe_emit "adversarial-review:${type}" "$_c117d_band" \
      "$_c117d_reason" "$sprint_id" "$_c117d_mec" \
      ${_c117d_legs[@]+"${_c117d_legs[@]}"}
  fi

  # cycle-119 C14 (KF-004 repair loop, #1177-D wiring): rejected+repaired
  # counts feed the SAME uniform degraded-trajectory channel so "N
  # findings still silently eaten even after a repair attempt" is visible
  # without opening the sidecar. Gated on the flag AND rejected_count>0 —
  # a clean run (or the flag OFF default) never reaches this; distinct
  # gate suffix so it never collides with the api_failure/verdict_quality
  # record above.
  if [[ "${CONF_REPAIR_LOOP:-false}" == "true" ]] \
     && declare -F degraded_verdict_maybe_emit >/dev/null 2>&1; then
    local _c14_rejected _c14_repaired
    _c14_rejected=$(echo "$result_json" | jq -r '.metadata.rejected_count // 0' 2>/dev/null) || _c14_rejected=0
    _c14_repaired=$(echo "$result_json" | jq -r '.metadata.repaired_count // 0' 2>/dev/null) || _c14_repaired=0
    if [[ "$_c14_rejected" =~ ^[0-9]+$ ]] && [[ "$_c14_rejected" -gt 0 ]]; then
      degraded_verdict_maybe_emit "adversarial-review:${type}:repair-loop" "DEGRADED" \
        "kf-004-repair-loop: ${_c14_rejected} rejected finding(s) survived repair (${_c14_repaired} repaired)" \
        "$sprint_id" "-"
    fi
  fi
}

# =============================================================================
# Main
# =============================================================================

# sprint-bug-208 (#1025) / KF-004 guard: status extraction from a
# process_findings result. A result that fails to parse is a
# malformed_response (drives the fallback chain to the next model) — never
# a silent "unknown" that reads as success. Absence of .metadata.status
# inside VALID JSON still yields "unknown" (absence != parse failure).
_extract_result_status() {
  local result="$1"
  local status
  if ! status=$(printf '%s' "$result" | JQ_STRICT_CTX="adversarial-review:result-status" jq_strict -r '.metadata.status // "unknown"'); then
    log "process_findings result failed to parse — treating as malformed_response (KF-004 guard, #1025)"
    printf 'malformed_response'
    return 0
  fi
  # DISS-002 (review iter-1): empty result through jq -r yields "" with
  # exit 0; the fallback-chain loop would read "" as success. A valid
  # process_findings envelope is never empty.
  if [[ -z "$status" ]]; then
    log "process_findings result was empty — treating as malformed_response (KF-004 guard, #1025)"
    printf 'malformed_response'
    return 0
  fi
  printf '%s' "$status"
}

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
    local disabled_result
    disabled_result=$(jq -n --arg type "$type" --arg sid "$sprint_id" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{findings: [], metadata: {type: $type, sprint_id: $sid, timestamp: $ts, status: "skipped_by_config", model: null, cost_usd: 0}}')
    # Emit trajectory line so the absence of adversarial output is explainable
    # rather than a silent void. The gate hook does not require the full output
    # file here because config says disabled, but visibility still matters.
    local trajectory_dir="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
    mkdir -p "$trajectory_dir"
    local trajectory_file="$trajectory_dir/adversarial-$(date -u +%Y-%m-%d).jsonl"
    echo "$disabled_result" | jq -c '{
      timestamp: .metadata.timestamp,
      type: .metadata.type,
      model: .metadata.model,
      sprint_id: .metadata.sprint_id,
      status: .metadata.status,
      finding_count: 0,
      cost_usd: 0
    }' >> "$trajectory_file" 2>/dev/null || true
    echo "$disabled_result"
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

  # cycle-102 sprint-1F: model-fallback chain.
  #
  # Invoke the configured primary model. If the result is `malformed_response`
  # or `api_failure` (the empty-content failure modes that have plagued
  # cycle-102 — KF-002, Sprint 1B T1B.4 manual swap), retry with the next
  # model in the fallback chain. Each model is tried at most once. The first
  # model that returns parseable findings (or `clean` = legitimate
  # zero-findings response) becomes canonical for the rest of the pipeline
  # (hallucination filter, output write, trajectory log).
  #
  # The fallback chain is built from (in priority order):
  #   1. The configured primary model (--model arg or
  #      flatline_protocol.{type}.model)
  #   2. flatline_protocol.{type}.fallback_chain (operator-curated list,
  #      optional)
  #   3. flatline_protocol.models.{secondary, tertiary} (already part of
  #      the multi-model PRD/SDD review chain — repurposed here as the
  #      default fallback when no explicit fallback_chain is configured)
  #
  # Duplicates are deduped (same model only tried once even if it appears
  # in multiple sources). Empty/null entries are skipped.
  #
  # Operator opt-out: set LOA_ADVERSARIAL_DISABLE_FALLBACK=1 (env) or
  # flatline_protocol.{type}.fallback_chain: [] (empty list in config).
  # When opted out, behavior reverts to single-model invocation.
  #
  # Result annotation: metadata.model_attempts records [<model>:<status>, …]
  # for the entire chain that was tried; metadata.final_model records which
  # model produced the canonical result. Single-model invocations (one entry,
  # one final) preserve back-compat with consumers that read metadata.model.
  local -a fallback_chain=()
  fallback_chain+=("$model")
  if [[ -z "${LOA_ADVERSARIAL_DISABLE_FALLBACK:-}" ]]; then
    # Build extension list from config. yq returns one entry per line for arrays.
    local fallback_yaml
    fallback_yaml=$(yq eval -e ".flatline_protocol.${type//-/_}.fallback_chain[]?" "$CONFIG_FILE" 2>/dev/null || true)
    # Map type→config key (review uses code_review; audit uses security_audit)
    local config_key="code_review"; [[ "$type" == "audit" ]] && config_key="security_audit"
    if [[ -z "$fallback_yaml" ]]; then
      fallback_yaml=$(yq eval -e ".flatline_protocol.${config_key}.fallback_chain[]?" "$CONFIG_FILE" 2>/dev/null || true)
    fi
    if [[ -n "$fallback_yaml" ]]; then
      while IFS= read -r m; do
        [[ -n "$m" && "$m" != "null" ]] && fallback_chain+=("$m")
      done <<< "$fallback_yaml"
    else
      # No explicit fallback_chain — fall back to flatline_protocol.models.*
      local m_secondary m_tertiary
      m_secondary=$(yq eval ".flatline_protocol.models.secondary // \"\"" "$CONFIG_FILE" 2>/dev/null || echo "")
      m_tertiary=$(yq eval ".flatline_protocol.models.tertiary // \"\"" "$CONFIG_FILE" 2>/dev/null || echo "")
      [[ -n "$m_secondary" && "$m_secondary" != "null" ]] && fallback_chain+=("$m_secondary")
      [[ -n "$m_tertiary" && "$m_tertiary" != "null" ]] && fallback_chain+=("$m_tertiary")
    fi
  fi

  # Dedupe (preserve order)
  local -a deduped=()
  local seen=""
  for m in "${fallback_chain[@]}"; do
    if [[ ",$seen," != *",$m,"* ]]; then
      deduped+=("$m")
      seen="$seen,$m"
    fi
  done
  fallback_chain=("${deduped[@]}")

  log "Fallback chain: ${fallback_chain[*]}"

  # Invocation loop
  local raw_response="" api_exit=0 result="" final_model=""
  local -a model_attempts=()
  # cycle-109 Sprint 2 T2.5 — per-attempt verdict_quality sidecar paths.
  # Each invoke_dissenter call gets a unique path; the envelope cheval
  # writes lands there and is collected for aggregation after the loop.
  local -a vq_attempt_files=()
  local -a vq_cleanup_files=()
  local try_model status
  local _vq_tmpdir="${_ADVERSARIAL_WORKDIR:-${TMPDIR:-/tmp}}"

  for try_model in "${fallback_chain[@]}"; do
    api_exit=0
    # Allocate per-attempt sidecar path under the adversarial workdir so
    # parallel adversarial-review invocations don't collide.
    local vq_sidecar
    vq_sidecar="$_vq_tmpdir/vq-${type}-${try_model//[^A-Za-z0-9_-]/_}-$$-$RANDOM.json"
    raw_response=$(invoke_dissenter "$_ADVERSARIAL_WORKDIR/system-prompt.txt" "$_ADVERSARIAL_WORKDIR/user-prompt.txt" "$try_model" "$timeout" "$vq_sidecar" "$type") || api_exit=$?
    # Collect the per-attempt envelope (if cheval wrote one).
    if [[ -s "$vq_sidecar" ]]; then
      vq_attempt_files+=("$vq_sidecar")
      vq_cleanup_files+=("$vq_sidecar")
    fi
    result=$(process_findings "$raw_response" "$type" "$try_model" "$sprint_id" "$api_exit" "$diff_files")
    status=$(_extract_result_status "$result")
    model_attempts+=("${try_model}:${status}")

    if [[ "$status" != "malformed_response" && "$status" != "api_failure" ]]; then
      final_model="$try_model"
      break
    fi
    log "Model $try_model returned $status; trying next in fallback chain (if any)"
  done

  if [[ -z "$final_model" ]]; then
    # All models failed; final_model = last attempted (canonical for the failure record)
    final_model="${fallback_chain[-1]}"
    log "Fallback chain exhausted — all ${#fallback_chain[@]} models returned malformed_response or api_failure"
  fi

  # Annotate result with the chain that was tried + which model won.
  # Single-model behavior (one attempt, one final): metadata.model still
  # equals final_model; consumers that read .metadata.model continue to work.
  result=$(echo "$result" | jq \
    --argjson attempts "$(printf '%s\n' "${model_attempts[@]}" | jq -R . | jq -s .)" \
    --arg fm "$final_model" \
    '.metadata.model_attempts = $attempts | .metadata.final_model = $fm')

  # cycle-109 Sprint 2 T2.5 — aggregate per-attempt verdict_quality
  # envelopes via the canonical Python aggregator (SDD §5.2.1). The
  # aggregator embeds chain_health (worst-of-N), voices_dropped[] entries
  # from failed attempts, and a status that surfaces #807 / #823 / #868
  # class regressions explicitly. Fail-soft: legacy / pre-T2.3 cheval emits
  # produce empty vq_attempt_files; in that case result.verdict_quality
  # stays absent (downstream consumers handle).
  if [[ ${#vq_attempt_files[@]} -gt 0 ]]; then
    local _vq_agg
    if _vq_agg=$(_adv_aggregate_envelopes "${vq_attempt_files[@]}" 2>/dev/null); then
      if [[ -n "$_vq_agg" ]]; then
        result=$(echo "$result" | jq --argjson vq "$_vq_agg" \
          '.verdict_quality = $vq')
      fi
    else
      log "[vq-aggregate] aggregator unavailable or returned no output; result emitted without verdict_quality"
    fi
  fi
  # Clean up per-attempt sidecar tmp files
  local _vqf
  for _vqf in "${vq_cleanup_files[@]}"; do
    rm -f "$_vqf" 2>/dev/null || true
  done

  # cycle-093 T1.3 (#618): post-process hallucination filter.
  # Downgrades findings that reference `{{DOCUMENT_CONTENT}}`-family tokens
  # absent from the source diff. Bidirectional + normalization per SDD §3.7.
  # Non-fatal: on any error or missing diff, returns input unchanged.
  result=$(_apply_hallucination_filter "$result" "$diff_file")

  # Write output
  write_output "$result" "$sprint_id" "$type" "$api_exit"

  # Output to stdout
  echo "$result"
}

# cycle-109 Sprint 2 T2.5 — source-vs-exec guard. When the script is
# sourced (e.g. by a bats helper that wants to test individual functions
# in isolation), main() must NOT auto-run; the sourcing caller invokes
# it explicitly or skips it. Standard bash idiom: BASH_SOURCE[0]==$0 iff
# script was executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
