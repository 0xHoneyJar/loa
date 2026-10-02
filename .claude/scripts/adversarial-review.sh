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
#   --diff-range <base>...<head>
#                             Instead of --diff-file: the script runs `git diff` on the range itself (ref names only)
#   --context-file <path>     Reviewer findings (review only; omit for audit independence)
#   --model <model>           Dissenter model (default: from config or gpt-5.3-codex)
#   --budget <cents>          Max cost in cents (default: from config or 150)
#   --timeout <seconds>       API timeout (default: from config or 60)
#   --dry-run                 Assemble context without calling API
#   --json                    Output as JSON (default)
#   --record-fallback <status> --reason <text> [--since <ISO-8601 UTC>]
#                             Write the failed-run record instead of a review (no --diff-file): status `failed` (the
#                             run aborted — never over a standing envelope, unless `--since <the run's start>` shows it
#                             older: the previous round's, moved aside) or a pre-lock refusal (`workdir_unavailable`,
#                             `nothing_to_review`, `budget_exceeded` — the previous envelope and sidecars go aside as
#                             `.prev`); under the run lock, so a live run is refused (`refused_concurrent_run`, exit 2)
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

# Repair round-trips per run (KF-004 repair loop, unenforced branch only).
readonly ADV_REPAIR_MAX_PER_RUN=5


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
DEFAULT_PRIMARY_TOKEN_BUDGET=24000    # 80% of 30k — non-Anthropic dissenters
DEFAULT_SECONDARY_TOKEN_BUDGET=12000  # 80% of 15k
MAX_ESCALATED_FILES=3                 # Per D-011
# cycle-124 FR-2/FR-3 (SDD §3.2): Anthropic dissenters take the catalog's
# 180K effective_input_ceiling minus 20K headroom (same figure BB codegen
# derives), so an Opus-class dissenter sees the whole diff instead of the
# 24K slice sized for the 2026-05 non-streaming wall.
_ANTHROPIC_DISPATCH_INPUT_BUDGET=160000
DISSENT_MAX_OUTPUT_TOKENS=16000       # bounded findings document (cheval --max-tokens)

# Resolve the primary input budget for the dissenter model's company.
# Anthropic ⇒ 160K; anything else (or an unresolvable alias) ⇒ 24K.
# Alias → provider comes from the generated bash maps (SSOT codegen of
# model-config.yaml); an explicit `anthropic:` pin short-circuits.
_adv_input_budget_for_model() {
  local model="$1"
  case "$model" in
    anthropic:*) echo "$_ANTHROPIC_DISPATCH_INPUT_BUDGET"; return 0 ;;
    *:*) echo "$DEFAULT_PRIMARY_TOKEN_BUDGET"; return 0 ;;
  esac
  # A model id is an alias or provider:id token. Anything else never reaches
  # the array lookup: bash evaluates an INDEXED array's subscript arithmetically
  # (command substitutions included), and the arrays are indexed whenever the
  # maps file fails to source — audit slice C reproduced `x[$(touch pwned)]`.
  # The arrays are pre-declared associative and a source failure is fatal to
  # the lookup (default budget), never silently indexed.
  [[ "$model" =~ ^[A-Za-z0-9._:/-]+$ ]] || { echo "$DEFAULT_PRIMARY_TOKEN_BUDGET"; return 0; }
  local maps="$SCRIPT_DIR/generated-model-maps.sh"
  if [[ -f "$maps" ]]; then
    local provider
    provider=$(bash -c 'declare -A MODEL_IDS=() MODEL_PROVIDERS=(); source "$1" >/dev/null 2>&1 || exit 3; id="${MODEL_IDS[$2]:-$2}"; printf "%s" "${MODEL_PROVIDERS[$id]:-}"' _ "$maps" "$model" 2>/dev/null || true)
    if [[ "$provider" == "anthropic" ]]; then
      echo "$_ANTHROPIC_DISPATCH_INPUT_BUDGET"; return 0
    fi
  fi
  echo "$DEFAULT_PRIMARY_TOKEN_BUDGET"
}

# =============================================================================
# Logging
# =============================================================================

log() { echo "[adversarial-review] $*" >&2; }
error() { echo "ERROR: $*" >&2; }

# =============================================================================
# Configuration
# =============================================================================

_conf_uint() {  # <key (for the message)> <raw> <default> [floor] → a whole number without a leading zero and at least the floor, else the default (said)
  local key="$1" raw="$2" def="$3" floor="${4:-0}"
  # at most fifteen digits: a longer value wraps in shell arithmetic past 2^63 (twenty-third run, a1 DISS-C-002)
  if [[ "$raw" =~ ^(0|[1-9][0-9]{0,14})$ ]] && (( raw >= floor )); then echo "$raw"; return 0; fi
  log "WARN: ${key}='${raw}' is not a whole number of at least ${floor} — ${def} applies"
  echo "$def"
}

load_adversarial_config() {
  local type="$1"

  # Defaults
  CONF_ENABLED="false"
  CONF_MODEL="gpt-5.3-codex"
  CONF_TIMEOUT=60
  CONF_BUDGET_CENTS=150
  CONF_COMPANION_VOICE="true"   # cycle-126 FR-2.1: the second, other-family chain (opt-out per block)
  CONF_COMPANION_CHAIN_ANTHROPIC=""  # review sprint-248 C-011: optional operator chains (space-separated)
  CONF_COMPANION_CHAIN_OPENAI=""
  CONF_ESCALATION_ENABLED="true"
  CONF_SECONDARY_BUDGET=$DEFAULT_SECONDARY_TOKEN_BUDGET
  CONF_MAX_FILE_LINES=500
  CONF_MAX_FILE_BYTES=51200
  CONF_SECRET_SCANNING="true"
  CONF_SECRET_ALLOWLIST=()  # Patterns that should NOT be redacted
  # cycle-124 FR-7: the KF-004 repair loop has no flag any more — it always
  # runs on the UNENFORCED branch and never on a schema-enforced payload.

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
  # fourteenth run, a1 C-003 / fifteenth run, a1 C-001: every arithmetic and --argjson consumer downstream sees a whole
  # number without a leading zero and at least the floor — a `60s`, a `0` (GNU `timeout 0` is no limit; a zero budget
  # pre-empts every repair) or an `060` (octal to $(( )), rejected by --argjson) would surface far from the config line
  CONF_TIMEOUT=$(_conf_uint "flatline_protocol.${config_key}.timeout_seconds" "$CONF_TIMEOUT" 60 1)
  CONF_BUDGET_CENTS=$(yq eval ".flatline_protocol.${config_key}.budget_cents // 150" "$CONFIG_FILE" 2>/dev/null || echo "150")
  CONF_BUDGET_CENTS=$(_conf_uint "flatline_protocol.${config_key}.budget_cents" "$CONF_BUDGET_CENTS" 0 0)   # (a malformed spend cap fails CLOSED: 0 cents — sixteenth run, a1 C-004)
  # `false // true` is true in jq/yq semantics — read the raw value and default only when absent
  local _cv _cvl
  _cv=$(yq eval ".flatline_protocol.${config_key}.companion_voice" "$CONFIG_FILE" 2>/dev/null || echo "null")
  # eleventh run, a1 C-001: yq echoes the scalar's source spelling — the YAML boolean spellings match in any
  # case, and a value that is none of them is SAID, not silently read as "on"
  _cvl=$(printf '%s' "$_cv" | tr '[:upper:]' '[:lower:]')
  case "$_cvl" in
    false|no|off|0) CONF_COMPANION_VOICE="false" ;;
    true|yes|on|1|null|"") CONF_COMPANION_VOICE="true" ;;
    *) log "WARN: flatline_protocol.${config_key}.companion_voice='${_cv}' is not a boolean — the companion voice stays on (write false / no / off / 0 to opt out)"
       CONF_COMPANION_VOICE="true" ;;
  esac
  # (|| true: a yq failure yields an empty chain and the default applies — the siblings' `|| echo` convention)
  # twenty-second run, a1 DISS-C-001: a shape that is not a list is SAID (the default chain then applies), never silently
  # taken as an empty operator chain; only a list is read — `[]?` would read a map as its values (twenty-third run, a1 DISS-C-001)
  local _cct _ccf
  _cct=$(yq eval ".flatline_protocol.${config_key}.companion_chain | tag" "$CONFIG_FILE" 2>/dev/null || true)
  if [[ -n "$_cct" && "$_cct" != "!!null" && "$_cct" != "!!map" ]]; then
    log "WARN: flatline_protocol.${config_key}.companion_chain is a ${_cct}, not a map of family lists — ignored, the default chains apply"
  elif [[ "$_cct" == "!!map" ]]; then
    for _ccf in anthropic openai; do
      _cct=$(yq eval ".flatline_protocol.${config_key}.companion_chain.${_ccf} | tag" "$CONFIG_FILE" 2>/dev/null || true)
      [[ -z "$_cct" || "$_cct" == "!!null" || "$_cct" == "!!seq" ]] \
        || log "WARN: flatline_protocol.${config_key}.companion_chain.${_ccf} is a ${_cct}, not a list — ignored, the default ${_ccf} chain applies"
    done
  fi
  CONF_COMPANION_CHAIN_ANTHROPIC=$(_adv_conf_chain_hops "$config_key" anthropic)
  CONF_COMPANION_CHAIN_OPENAI=$(_adv_conf_chain_hops "$config_key" openai)
  CONF_ESCALATION_ENABLED=$(yq eval ".flatline_protocol.context_escalation.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")
  CONF_SECONDARY_BUDGET=$(yq eval ".flatline_protocol.context_escalation.secondary_token_budget // $DEFAULT_SECONDARY_TOKEN_BUDGET" "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_SECONDARY_TOKEN_BUDGET")
  CONF_MAX_FILE_LINES=$(yq eval ".flatline_protocol.context_escalation.max_file_lines // 500" "$CONFIG_FILE" 2>/dev/null || echo "500")
  CONF_MAX_FILE_BYTES=$(yq eval ".flatline_protocol.context_escalation.max_file_bytes // 51200" "$CONFIG_FILE" 2>/dev/null || echo "51200")
  CONF_SECONDARY_BUDGET=$(_conf_uint "flatline_protocol.context_escalation.secondary_token_budget" "$CONF_SECONDARY_BUDGET" "$DEFAULT_SECONDARY_TOKEN_BUDGET" 1)
  CONF_MAX_FILE_LINES=$(_conf_uint "flatline_protocol.context_escalation.max_file_lines" "$CONF_MAX_FILE_LINES" 500 1)
  CONF_MAX_FILE_BYTES=$(_conf_uint "flatline_protocol.context_escalation.max_file_bytes" "$CONF_MAX_FILE_BYTES" 51200 1)
  CONF_SECRET_SCANNING=$(yq eval ".flatline_protocol.secret_scanning.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")

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

  # wire-enums:validate:start — tests/unit/wire-schemas-api-safe.bats reads the
  # enums between these markers: the wire schemas' severity enums must EQUAL
  # these per type and their category enums must be a SUBSET of this list
  # (the prompt advertises the per-type subset a model is asked for; the
  # validator stays wide so an unenforced voice's broader tag is not rejected).
  local valid_severities
  if [[ "$type" == "review" ]]; then
    valid_severities='["BLOCKING","ADVISORY"]'
  else
    valid_severities='["CRITICAL","HIGH","MEDIUM","LOW"]'
  fi

  local valid_categories='["injection","authz","data-loss","null-safety","concurrency","type-error","resource-leak","error-handling","spec-violation","performance","secrets","xss","ssrf","deserialization","crypto","info-disclosure","rate-limiting","input-validation","config","other"]'
  # wire-enums:validate:end

  echo "$finding" | jq -e --argjson sevs "$valid_severities" --argjson cats "$valid_categories" '
    (.id | type) == "string" and
    (.severity | IN($sevs[])) and
    (.category | IN($cats[])) and
    (.description | type) == "string" and (.description | gsub("\\s"; "") | length) > 0 and
    (.failure_mode | type) == "string" and (.failure_mode | gsub("\\s"; "") | length) > 0
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
    elif (.description // null) == null or (.description | type) != "string" or (.description | gsub("\\s"; "") | length) == 0 then
      "missing-or-empty-description"
    elif (.failure_mode // null) == null or (.failure_mode | type) != "string" or (.failure_mode | gsub("\\s"; "") | length) == 0 then
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
# repair_attempted / repair_succeeded ("true"/"false"); empty ⇒ key omitted.
# cycle-124 FR-7: three more OPTIONAL trailing args — schema_enforced,
# parse_path, stop_reason — so a rejected payload records which parse
# path produced it (enforced payloads should never land here; when one
# does, that is a wire-schema/prompt drift signal, not a model slip).
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
  local schema_enforced="${10:-}"
  local parse_path="${11:-}"
  local stop_reason="${12:-}"

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
    --arg se "$schema_enforced" \
    --arg pp "$parse_path" \
    --arg sr "$stop_reason" \
    '{ts_utc: $ts, sprint_id: $sid, type: $t, model: $m, index: $idx, reject_reason: $r, payload: $f}
     + (if $ra == "" then {} else {repair_attempted: ($ra == "true")} end)
     + (if $rs == "" then {} else {repair_succeeded: ($rs == "true")} end)
     + (if $se == "" then {} else {schema_enforced: ($se == "true")} end)
     + (if $pp == "" then {} else {parse_path: $pp} end)
     + (if $sr == "" then {} else {stop_reason: $sr} end)' \
    >> "$sidecar_path" 2>/dev/null || true
}

# =============================================================================
# KF-004 Repair Loop (cycle-119 C14) — always on for UNENFORCED voices
# =============================================================================
# cycle-124 FR-7 removed the repair-loop flag: on the unenforced branch
# (the hop could not enforce the wire schema) a finding that fails
# validate_finding gets ONE bounded repair round-trip to the SAME model
# before being rejected; the schema-enforced branch never enters it (a
# schema-valid payload has nothing to repair, an invalid one is
# malformed_response). Retirement is keyed to the measured schema_enforced
# ratio (follow-up bead). Four safety constraints (adversarial
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
  local index="${2:-}"
  echo "$finding" | jq '
    (if has("severity") and (.severity | type) == "string"
     then .severity |= (gsub("^\\s+|\\s+$"; "") | ascii_upcase)
     else . end)
    | (if has("category") and (.category | type) == "string"
       then .category |= (gsub("^\\s+|\\s+$"; "") | ascii_downcase)
       else . end)
  ' 2>/dev/null | _derive_failure_mode "$index"
}

# cycle-126 FR-2.2 (SDD D-2.2, KF-004): `failure_mode` is derivable, not
# required. A finding that carries everything but it gets the first sentence
# of its `description` (≤ 200 chars) as `failure_mode` and is marked
# `failure_mode_derived: true`; a missing `id` (the models emit `title`, not
# `id`) is filled from the position (`DISS-NNN`, `id_derived: true`). Severity,
# category and description are never touched, so a derived finding is gated
# exactly like a stated one. Only the unenforced path reaches this (the call
# site skips normalisation for schema-enforced payloads). stdin → stdout.
_derive_failure_mode() {
  local index="${1:-}"
  # bats-gated seam (seventh run, chunk c2 C-004): the repair-path suites skip ONLY the failure_mode
  # derivation and keep the production id derivation — one switch, no private re-implementation
  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && "${LOA_ADVERSARIAL_NO_FM_DERIVATION:-}" == "1" ]]; then
    jq --arg idx "$index" '
      if ((.id | type) != "string" or (.id | length) == 0) and ($idx | length) > 0
      then .id = ("DISS-" + (($idx | tonumber) + 1 | tostring | if length < 3 then ("000" + .)[-3:] else . end)) | .id_derived = true
      else . end' 2>/dev/null
    return
  fi
  jq --arg idx "$index" '
    (if ((.id | type) != "string" or (.id | length) == 0) and ($idx | length) > 0
     then .id = ("DISS-" + (($idx | tonumber) + 1 | tostring | if length < 3 then ("000" + .)[-3:] else . end))
          | .id_derived = true
     else . end)
    # a non-string id or failure_mode is missing, so derivable (twenty-third run, a1 DISS-C-003)
    | if ((.failure_mode | type) != "string" or (.failure_mode | gsub("\\s"; "") | length) == 0)
         and (.description | type) == "string" and (.description | gsub("\\s"; "") | length) > 0
      then
        (.description | gsub("\\s+"; " ")) as $d
        | ($d | (capture("^(?<s>.*?[.!?])(\\s|$)").s // .)) as $s
        # eighth run, a1 C-003: "e.g." / "1." / "Approx." are not sentences — below 20 characters use the head
        | (if ($s | length) < 20 then $d else $s end | .[0:200]) as $fm
        | .failure_mode = $fm | .failure_mode_derived = true
      else . end
  ' 2>/dev/null
}

# cycle-126 FR-2.4 (SDD D-2.4): the repair model — `tiny` when an Anthropic
# credential is PRESENT (env → .env.local → .env; the value is never read
# out), else the `claude-headless` hop; LOA_ADVERSARIAL_REPAIR_MODEL pins it.
_adv_cred_aliases() {  # <provider> → the credential variable names the probe consults, space-separated ("" for an unknown provider)
  case "$1" in
    openai) echo "OPENAI_API_KEY" ;;
    anthropic) echo "ANTHROPIC_API_KEY" ;;
    google) echo "GOOGLE_API_KEY GEMINI_API_KEY" ;;
    *) echo "" ;;
  esac
}
_adv_cred_present() {  # <provider> → 0 when a credential is present (presence only)
  local -a vars
  # (sixteenth run, c1a C-002: the alias table is _adv_cred_aliases — the suites unset from the same list)
  read -r -a vars <<<"$(_adv_cred_aliases "$1")"
  (( ${#vars[@]} > 0 )) || return 1
  local v f root="$PROJECT_ROOT"
  # bats-gated seam: point the dotenv lookup at a fixture directory
  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_ADVERSARIAL_ENV_DIR:-}" ]]; then root="$LOA_ADVERSARIAL_ENV_DIR"; fi
  # seventh run, chunk c2 C-003: no expansion of the value — an xtrace'd `[[ -n "${!v}" ]]` prints it;
  # printenv shows only the name and grep -q only the verdict (an exported empty value is not present)
  # eighth run, chunk c2 C-002 / tenth run, chunk c2 C-001: resolved PER ALIAS, the way cheval's credential
  # chain and a dotenv loader read variables — independently, with override precedence (env → .env.local →
  # .env: the first source that ASSIGNS a variable decides it; an empty assignment disables that alias, it does
  # not fall through); the provider is present when ANY alias resolves non-empty, so an empty GOOGLE_API_KEY
  # override never hides a GEMINI_API_KEY assigned lower down
  for v in "${vars[@]}"; do
    if printenv "$v" >/dev/null 2>&1; then printenv "$v" | grep -q . && return 0; continue; fi
    for f in "$root/.env.local" "$root/.env"; do
      [[ -f "$f" ]] || continue
      # review sprint-248 C-008: presence is a grep on the shape through a pipe — no variable ever holds
      # the value, so an xtrace'd run cannot echo it (same rule as loa-status / run-preflight P3);
      # the LAST assignment in the file wins, as a dotenv loader would read it; the value shape is anchored
      # on the assignment itself (tenth run, a1 C-003): an `=` inside a trailing comment is not a value
      if grep -Eq "^[[:space:]]*(export[[:space:]]+)?${v}=" "$f" 2>/dev/null; then
        grep -E "^[[:space:]]*(export[[:space:]]+)?${v}=" "$f" 2>/dev/null | tail -1 | grep -Eq "^[[:space:]]*(export[[:space:]]+)?${v}=[\"']?[^\"'[:space:]#]" && return 0
        break   # assigned empty at its deciding source: this alias is disabled; the next alias may still be present
      fi
    done
  done
  return 1
}

_repair_model() {  # <voice that answered> → the FIRST hop of the repair chain — a helper for the tests and for
                   # operator display only; the repair call site iterates _repair_model_chain, never this
  _repair_model_chain "$1" | cut -d' ' -f1
}
_repair_chain_base() {  # <voice that answered> → the repair chain before the companion / retirement filters
  # eighth run, a1 C-001: tiny only with an Anthropic credential, claude-headless only with the binary on
  # PATH, and the voice that answered ALWAYS last — an OpenAI-only host without `claude` repairs through
  # its own primary (the cycle-119 C14 behaviour) instead of failing every KF-004 payload deterministically.
  # An operator pin (LOA_ADVERSARIAL_REPAIR_MODEL) is the whole chain.
  if [[ -n "${LOA_ADVERSARIAL_REPAIR_MODEL:-}" ]]; then echo "$LOA_ADVERSARIAL_REPAIR_MODEL"; return 0; fi
  local chain=""
  _adv_cred_present anthropic && chain="tiny"
  _adv_cli_present anthropic && chain="${chain:+$chain }claude-headless"
  # (sixteenth run, a1 C-002: the answering voice is appended once, by canonical name — a prefixed spelling of a hop
  # already in the chain would run the same binary twice)
  if [[ -n "$1" ]]; then
    local _h _dup="false"
    for _h in $chain; do [[ "$(_adv_hop_canon "$_h")" == "$(_adv_hop_canon "$1")" ]] && { _dup="true"; break; }; done
    [[ "$_dup" == "true" ]] || chain="${chain:+$chain }$1"
  fi
  echo "${chain:-$1}"
}
_repair_model_chain() {  # <voice that answered> → the repair chain, one bounded attempt per hop (the base chain, filtered)
  local chain; chain=$(_repair_chain_base "$1")
  if [[ -n "${LOA_ADVERSARIAL_REPAIR_MODEL:-}" ]]; then
    # twentieth run, a1 DISS-C-002: a pin is the whole chain, but a pinned hop retired this run is not paid for again — an
    # entirely retired pin is an empty chain (the payload is then repair_skipped_no_hop), never the answering voice
    local _ph _pk=""
    for _ph in $chain; do [[ " ${_ADV_REPAIR_DEAD_HOPS:-} " == *" $_ph "* ]] || _pk="${_pk:+$_pk }$_ph"; done
    echo "$_pk"; return 0
  fi
  # twelfth run, a1 C-002 / thirteenth run, a1 C-002: like the main walk, hop-aware — a repair never queues behind the
  # live companion on the hop it is ON right now (companion.current, phase queue / hop); a companion busy elsewhere
  # leaves the hop in the chain (the bounded _ADV_LOCK_WAIT_CLI covers a later overlap); every skip is named on the envelope
  # (fourteenth run, a1 C-001: decided from the companion's CURRENT hop against this chain's own hops — never from whether
  # the PRIMARY chain shares one; an OpenAI-primary host with `claude` installed queued every repair otherwise).
  # Seventeenth run, a1 C-003: the rule is ONE predicate, applied here and again right before each hop starts
  local _s _left=""
  for _s in $chain; do
    if _adv_repair_hop_shared_now "$_s" "$1"; then continue; fi
    _left="${_left:+$_left }$_s"
  done
  chain="$_left"
  # eleventh run, a1 C-003: a hop that failed this run with an explicit auth / quota code is not paid for again by
  # the next repair (_adv_repair_retire_hop); the voice that answered stays terminal whatever happened
  if [[ -n "${_ADV_REPAIR_DEAD_HOPS:-}" ]]; then
    local _h _kept=""
    for _h in $chain; do
      [[ "$(_adv_hop_canon "$_h")" != "$(_adv_hop_canon "$1")" && " $_ADV_REPAIR_DEAD_HOPS " == *" $_h "* ]] && continue   # (canonical — a1 C-002)
      _kept="${_kept:+$_kept }$_h"
    done
    chain="$_kept"
  fi
  echo "${chain:-$1}"
}
_adv_repair_hop_shared_now() {  # <hop> <voice that answered> → 0 when the LIVE companion is on this hop right now (phase queue /
                                # hop); the <hop>:shared_with_companion row is written once. The chain is computed once per
                                # repair but the companion moves — so the caller asks again right before each hop starts
                                # (seventeenth run, a1 C-003). Canonical names on both sides (fifteenth run, a1 C-002).
  [[ "$(_adv_hop_canon "$1")" != "$(_adv_hop_canon "$2")" ]] || return 1   # (canonical: the answering voice, however spelled, is never skipped — eighteenth run, a1 C-002)
  [[ -n "${companion_workdir:-}" ]] && _adv_companion_alive || return 1
  # (twenty-first run, a1 DISS-C-001: the walker writes current, then phase — current is read again after phase, and a pair that
  # moved under the read is read again, so one hop's name is never paired with the next hop's phase; past three tries, not shared)
  local _ccur _cph _ccur2 _try
  for _try in 1 2 3; do
    _ccur=$(cat "$companion_workdir/companion.current" 2>/dev/null || true); _cph=$(cat "$companion_workdir/companion.phase" 2>/dev/null || true)
    _ccur2=$(cat "$companion_workdir/companion.current" 2>/dev/null || true)
    [[ "$_ccur" == "$_ccur2" ]] && break
    _ccur=""
  done
  [[ -n "$_ccur" && "$(_adv_hop_canon "$_ccur")" == "$(_adv_hop_canon "$1")" && ( "$_cph" == "queue" || "$_cph" == "hop" ) ]] || return 1
  if [[ -n "${_ADV_REPAIR_SKIP_FILE:-}" ]] && ! grep -qxF "${1}:shared_with_companion" "$_ADV_REPAIR_SKIP_FILE" 2>/dev/null; then
    echo "${1}:shared_with_companion" >> "$_ADV_REPAIR_SKIP_FILE"
  fi
  return 0
}
_adv_conf_chain_hops() {  # <config key> <family> → the family list's hop names, space-separated; any other element is said and
  # dropped (twenty-fourth run, a1 DISS-C-001: a map, list or null element printed as YAML and split into hop tokens such as `{a:`,
  # `1}` or `null`) — the value is never echoed, only its index and tag
  local n i tg v out=""
  # (an absent or non-list value is the default chain, said by the loader; a list read short is said here — twenty-fifth
  # run, a1 DISS-C-003: over 999 entries, or a length yq could not report, fell back to the default with no line)
  tg=$(yq eval ".flatline_protocol.${1}.companion_chain.${2} | tag" "$CONFIG_FILE" 2>/dev/null || true)
  [[ "$tg" == "!!seq" ]] || return 0
  n=$(yq eval ".flatline_protocol.${1}.companion_chain.${2} | length" "$CONFIG_FILE" 2>/dev/null || true)
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    log "WARN: flatline_protocol.${1}.companion_chain.${2} could not be read — the default ${2} chain applies"; return 0
  elif [[ ! "$n" =~ ^[0-9]{1,3}$ ]]; then
    log "WARN: flatline_protocol.${1}.companion_chain.${2} has ${n} entries (at most 999 are read) — the default ${2} chain applies"; return 0
  fi
  for (( i = 0; i < n; i++ )); do
    tg=$(yq eval ".flatline_protocol.${1}.companion_chain.${2}[$i] | tag" "$CONFIG_FILE" 2>/dev/null || true)
    v=$(yq eval ".flatline_protocol.${1}.companion_chain.${2}[$i]" "$CONFIG_FILE" 2>/dev/null || true)
    if [[ "$tg" == "!!str" && "$v" =~ ^[A-Za-z0-9._/:-]{1,128}$ ]]; then out+="$v "
    else log "WARN: flatline_protocol.${1}.companion_chain.${2}[$i] is not a hop name (${tg:-unreadable}) — dropped"; fi
  done
  printf '%s' "${out% }"
}
_adv_repair_now() { date +%s; }   # the repair budget's clock — one reader, so a suite can drive the budget on its own clock (run 23, c2b DISS-C-001)
_ADV_REPAIR_LAST_SECS=""   # "hop=secs hop=secs …" — the last observed duration per repair hop, this process (a flat map: bash 3 has no -A)
_adv_repair_last_secs() {  # <hop> → seconds, or ""
  local _e; for _e in $_ADV_REPAIR_LAST_SECS; do [[ "${_e%%=*}" == "$1" ]] && { echo "${_e#*=}"; return 0; }; done; echo ""
}
_adv_repair_note_secs() {  # <hop> <secs>
  local _e _out=""; for _e in $_ADV_REPAIR_LAST_SECS; do [[ "${_e%%=*}" == "$1" ]] || _out="${_out:+$_out }$_e"; done
  _ADV_REPAIR_LAST_SECS="${_out:+$_out }$1=$2"
}
_adv_repair_retire_hop() {  # <hop> <exit code> — remember a repair hop this run must not try again
  case " ${_ADV_REPAIR_DEAD_HOPS:-} " in
    *" $1 "*) ;;
    *) _ADV_REPAIR_DEAD_HOPS="${_ADV_REPAIR_DEAD_HOPS:+$_ADV_REPAIR_DEAD_HOPS }$1"
       log "Repair hop $1 failed (rc $2) — retired for this run's remaining repairs" ;;
  esac
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

  # eighth run, a1 C-002: the derivation markers are the normaliser's, not the model's — a reply that
  # omits them (or a repair schema that forbids them) is still a repair of the violated field only
  jq -e -n --argjson orig "$original" --argjson rep "$repaired" --arg af "$allowed_field" '
    ($orig | del(.[$af], .id_derived, .failure_mode_derived)) == ($rep | del(.[$af], .id_derived, .failure_mode_derived))
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
# is only exercised in a live run on an unenforced voice.
_repair_finding_via_model() {
  local finding_json="$1"
  local type="$2"
  local violated_clause="$3"
  local model="$4"
  local timeout="${5:-60}"

  local workdir
  # Under the EXIT-trapped adversarial workdir when one exists, so a kill
  # mid-repair leaves nothing behind in $TMPDIR (late Sprint 2 review).
  workdir=$(mktemp -d "${_ADVERSARIAL_WORKDIR:-${TMPDIR:-/tmp}}/adv-repair.XXXXXX") || return 1
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
  # the hop's own exit code for the repair loop's retirement decision (the lock wrapper runs a CLI hop in a
  # subshell, so a variable would not carry it out) — eleventh run, a1 C-003
  [[ -n "${_ADV_REPAIR_RC_FILE:-}" ]] && printf '%s' "$rc" > "$_ADV_REPAIR_RC_FILE" 2>/dev/null
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
  # cycle-124 FR-2: primary budget follows the dissenter's company
  # (_adv_input_budget_for_model); callers that omit it keep the 24K default.
  local primary_budget="${4:-$DEFAULT_PRIMARY_TOKEN_BUDGET}"

  local diff_content
  diff_content=$(cat "$diff_file")

  # file_priority() and prepare_content() are provided by lib-content.sh
  # No eval+sed hack needed. See: Bridgebuilder Review Finding #1

  # Primary content: priority-sorted diff with 80% budget
  # prepare_content is guaranteed available from lib-content.sh
  local prepared_diff
  prepared_diff=$(prepare_content "$diff_content" "$primary_budget")

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
  # cycle-124 FR-2: the 160K Anthropic budget makes the prepared diff far
  # larger than the kernel's single-argument cap (MAX_ARG_STRLEN 128 KiB), so
  # `jq --arg` fails with "Argument list too long" above ~32K tokens. Feed
  # the prompts through files instead — byte-identical JSON to `--arg`.
  local ctx_tmp
  # Under the EXIT-trapped workdir when one exists, so a kill between the
  # write and the rm never leaves the full diff in $TMPDIR (audit, slice C).
  ctx_tmp=$(mktemp -d "${_ADVERSARIAL_WORKDIR:-${TMPDIR:-/tmp}}/adv-ctx.XXXXXX") || return 1
  printf '%s' "$system_prompt" > "$ctx_tmp/system"
  printf '%s' "$user_prompt" > "$ctx_tmp/user"
  local jq_rc=0
  jq -n \
    --rawfile system "$ctx_tmp/system" \
    --rawfile user "$ctx_tmp/user" \
    --argjson escalated "$( [[ "$escalation_used" == "true" ]] && echo true || echo false )" \
    --argjson empty "$( [[ "$prepared_diff" =~ [^[:space:]] || "$escalated_content" =~ [^[:space:]] ]] && echo false || echo true )" \
    '{system_prompt: $system, user_prompt: $user, context_escalated: $escalated, nothing_to_review: $empty}' || jq_rc=$?
  rm -f "$ctx_tmp/system" "$ctx_tmp/user"
  rmdir "$ctx_tmp" 2>/dev/null || true
  return $jq_rc
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
  # cycle-124 FR-7: wire schema forwarded as --json-schema; cheval enforces
  # it where the hop can (Anthropic structured_json entries, claude-headless)
  # and the translated envelope reports schema_enforced either way.
  local schema_file="${7:-}"
  local -a schema_args=()
  if [[ -n "$schema_file" && -f "$schema_file" ]]; then
    schema_args=(--json-schema "$schema_file")
  elif [[ -n "$schema_file" ]]; then
    # A named schema that is not on disk means every voice runs unenforced
    # and the schema_enforced ratio is silently skewed — say so.
    log "WARN: wire schema not found, dispatching unenforced: $schema_file"
  fi

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

  # cycle-124 FR-2 (SDD §3.2): a dissent verdict is a bounded findings
  # document — pass the budget explicitly so cheval's per-model default
  # (Anthropic 64K) never meets the dissenter timeout.
  if [[ -n "$vq_sidecar" ]]; then
    LOA_VERDICT_QUALITY_SIDECAR="$vq_sidecar" \
      "$SCRIPT_DIR/model-adapter.sh" \
      --model "$model" \
      --mode dissent \
      --input "$user_prompt_file" \
      --context "$system_prompt_file" \
      --timeout "$timeout" \
      --max-tokens "$DISSENT_MAX_OUTPUT_TOKENS" \
      ${skill_args[@]+"${skill_args[@]}"} \
      ${schema_args[@]+"${schema_args[@]}"}
  else
    "$SCRIPT_DIR/model-adapter.sh" \
      --model "$model" \
      --mode dissent \
      --input "$user_prompt_file" \
      --context "$system_prompt_file" \
      --timeout "$timeout" \
      --max-tokens "$DISSENT_MAX_OUTPUT_TOKENS" \
      ${skill_args[@]+"${skill_args[@]}"} \
      ${schema_args[@]+"${schema_args[@]}"}
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

  # cycle-124 FR-7 (SDD §3): two parse paths, chosen by what the hop reports.
  #   schema_enforced == true  → strict parse ONLY (jq_strict on the raw
  #     content: no fence strip, no raw_decode rescue, no repair); a failure
  #     or a max_tokens stop is malformed_response (the chain walks).
  #   otherwise                → today's tolerant path (fence strip +
  #     raw_decode + normalization + one repair round-trip), byte-for-byte.
  local schema_enforced parse_path resp_stop_reason parsed
  schema_enforced=$(echo "$raw_response" | jq -r 'if .schema_enforced == true then "true" else "false" end' 2>/dev/null) || schema_enforced="false"
  resp_stop_reason=$(echo "$raw_response" | jq -r '.stop_reason // empty' 2>/dev/null) || resp_stop_reason=""
  if [[ "$schema_enforced" == "true" ]]; then
    parse_path="schema_enforced"
    local _enforced_err=""
    if [[ "$resp_stop_reason" == "max_tokens" ]]; then
      _enforced_err="schema-enforced payload truncated (stop_reason=max_tokens) — raise DISSENT_MAX_OUTPUT_TOKENS"
    elif ! parsed=$(printf '%s' "$content" | JQ_STRICT_CTX="adversarial-review:enforced-parse" \
                     jq_strict -ces 'if length == 1 and (.[0] | type) == "object" then .[0] else error("enforced content must be exactly one JSON object") end'); then
      # -s: a multi-object stream is not an enforced object (a two-object
      # stream used to read as clean-zero — late Sprint 2 review, slice B)
      _enforced_err="schema-enforced content is not valid JSON as exactly one object (no fence strip or repair on the enforced branch)"
    fi
    if [[ -n "$_enforced_err" ]]; then
      log "Enforced branch: $_enforced_err — emitting malformed_response"
      jq -n \
        --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
        --arg ts "$timestamp" --arg err "$_enforced_err" \
        '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
          timestamp: $ts, status: "malformed_response", degraded: false,
          schema_enforced: true, parse_path: "schema_enforced", error: $err}}'
      return 0
    fi
  else
    parse_path="normalized"
  # Try to parse as JSON (handle markdown ```json wrapping)
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
      --arg ts "$timestamp" --arg se "$schema_enforced" --arg pp "$parse_path" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "malformed_response", degraded: false,
        schema_enforced: ($se == "true"), parse_path: $pp}}'
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
      --arg ts "$timestamp" --arg se "$schema_enforced" --arg pp "$parse_path" \
      --arg err "finding-count extraction failed (.findings | length)" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "malformed_response", degraded: false, error: $err,
        schema_enforced: ($se == "true"), parse_path: $pp}}'
    return 0
  fi
  if [[ "$finding_count" == "0" ]]; then
    # bug-809: keep status "clean" for backward compat, but qualify it —
    # zero findings means nothing met the BLOCKING/ADVISORY bar, NOT an
    # affirmative approval of the reviewed surface. verdict_quality covers
    # the degraded axis; status_note covers the high-bar-lens axis.
    jq -n \
      --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
      --arg ts "$timestamp" --arg se "$schema_enforced" --arg pp "$parse_path" \
      '{findings: [], metadata: {type: $type, model: $model, sprint_id: $sid,
        timestamp: $ts, status: "clean",
        status_note: "no findings met the BLOCKING/ADVISORY bar — not an approval of unreviewed surface",
        degraded: false, schema_enforced: ($se == "true"), parse_path: $pp}}'
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
    # fifth run, C-004: LOA_ADVERSARIAL_RUN_TAG scopes the sidecar names to this run (a chunk driver passes
    # its chunk key instead of renaming files afterwards): adversarial-rejected-<type>[-companion][-<tag>].jsonl
    _adv_resolve_run_tag; local _run_tag="$_ADV_RUN_TAG"
    rejected_sidecar="$rej_dir/adversarial-rejected-${type}${_ADV_SIDECAR_TAG:+-$_ADV_SIDECAR_TAG}${_run_tag:+-$_run_tag}.jsonl"
    : > "$rejected_sidecar" 2>/dev/null || rejected_sidecar=""
  fi

  local validated_findings="[]"
  local rejected_summary="[]"  # cycle-126 FR-2.2: every payload that still fails, summarised in the envelope
  local i=0
  local rejected_count=0
  # cycle-119 C14 (KF-004 repair loop); always reported since cycle-124.
  local repaired_count=0
  # Each repair is a serial live model call bounded only by CONF_TIMEOUT; a
  # voice that returns thirty out-of-enum findings would otherwise cost thirty
  # calls per review. At most ADV_REPAIR_MAX_PER_RUN repairs per run; the rest
  # are rejected unrepaired and counted in repair_budget_exhausted.
  local repairs_used=0 repair_budget_exhausted=0 repair_skipped_no_hop=0
  # twelfth run, a1 C-002: the run's repairs share a WALL-CLOCK budget too — up to three hops per payload, each bounded
  # by its own timeout or lock wait, no longer bounded the review's latency by ADV_REPAIR_MAX_PER_RUN alone
  local _repair_wall_started _repair_wall_budget _repair_wall_used=0 _rh _rb _rmax=0 _rmaxh=""
  _repair_wall_budget=$(( ADV_REPAIR_MAX_PER_RUN * ${CONF_TIMEOUT:-60} * 2 ))
  # fourteenth run, a1 C-002: a CLI repair hop is bounded by cheval (headless_timeout_seconds + connect), not by the call
  # timeout — the default budget always fits one full CLI repair plus a timeout, and (below) a hop whose bound exceeds
  # what is left is not started
  # twenty-third run, a2 DISS-C-002: each hop is charged once per run ("<hop> <seconds>" lines) — a charge costs several catalog
  # reads, which a per-payload recharge spent against the wall budget again for every rejected payload
  local _hb_memo=""
  for _rh in $(_repair_chain_base "$model"); do
    _rb=$(_adv_hop_charge "$_rh" "${CONF_TIMEOUT:-60}")   # (twentieth run, a1 DISS-C-001: an HTTP hop that reaches a CLI is charged that CLI)
    _hb_memo+="$_rh $_rb"$'\n'
    (( _rb > _rmax )) && { _rmax=$_rb; _rmaxh="$_rh"; }
  done
  # nineteenth run, a1 C-001: TWO full CLI repairs plus a timeout — with no duration noted for a failed hop (eighteenth run, a1
  # C-003) one repair plus a timeout admitted a CLI hop only while under a minute had been spent: a one-repair cliff
  (( _rmax * 2 + ${CONF_TIMEOUT:-60} > _repair_wall_budget )) && _repair_wall_budget=$(( _rmax * 2 + ${CONF_TIMEOUT:-60} ))
  # (thirteenth run, a1 C-001: the operator knob is validated where it is read — a value that is not a whole number
  # would break the arithmetic and then the envelope's --argjson; it is said once and the default applies)
  [[ -n "${LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS:-}" ]] && _repair_wall_budget=$(_conf_uint "LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS" "$LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS" "$_repair_wall_budget" 1)   # (fifteenth run, a2 C-004: no leading zero — octal to bash)
  # twenty-first run, a1 DISS-C-002: a pin below a hop's charge never admits that hop before it is observed — and a hop that is
  # never started is never observed — so it is said once, here, naming the heaviest hop (the per-hop line below is once per hop)
  if [[ -n "${LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS:-}" && -n "$_rmaxh" ]] && (( _repair_wall_budget < _rmax )) \
     && [[ "${_ADV_REPAIR_PIN_SAID:-}" != "$_repair_wall_budget:$_rmaxh" ]]; then
    _ADV_REPAIR_PIN_SAID="$_repair_wall_budget:$_rmaxh"
    log "WARN: LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=$_repair_wall_budget is below the charge of repair hop $_rmaxh (${_rmax}s): that hop is never started by this run's repairs — raise the pin to at least ${_rmax}s, or unset it"
  fi
  # the repair hops this attempt skipped because the companion was on them (named on the envelope) — a file, because
  # _repair_model_chain runs inside a command substitution where a global would be lost
  _ADV_REPAIR_SKIP_FILE=$(mktemp "${_ADVERSARIAL_WORKDIR:-${TMPDIR:-/tmp}}/adv-repair-skipped.XXXXXX" 2>/dev/null) || _ADV_REPAIR_SKIP_FILE=""
  _repair_wall_started=$(_adv_repair_now)
  # fourth run, chunk c C-005: a positional id may not collide with an id the model supplied (or one
  # already used) — a colliding derived id becomes max(explicit numeric id) + 1
  local explicit_ids used_ids="" max_id_num
  # (twenty-second run, a1 DISS-C-003: only a safe token is an explicit id — one with whitespace or a control character would split
  # into, or forge, ids in these space-joined sets; it is renumbered below and never logged raw)
  # (twenty-fourth run, a1 DISS-C-003: DISS-C- is the companion fold's namespace — such an id is renumbered, never explicit)
  explicit_ids=$(echo "$parsed" | jq -r '[.findings[]? | .id? | select(type == "string" and test("\\A[A-Za-z0-9._:-]{1,64}\\z") and (startswith("DISS-C-") | not))] | join(" ")' 2>/dev/null || true)
  # (no `?` after capture — that is a jq syntax error, and it silently zeroed this value until NRM-15 pinned it;
  # a jq failure here is LOGGED, never folded into 0 — tenth run, a1 C-002)
  if ! max_id_num=$(echo "$parsed" | jq -r '[.findings[]? | .id? | select(type == "string") | capture("^DISS-(?<n>[0-9]{1,15})$").n | tonumber] | max // 0' 2>/dev/null); then   # (≤ 15 digits: jq 1.7 keeps a longer one whole and shell arithmetic wraps it — twenty-fourth run, a1 DISS-C-002)
    log "WARN: the explicit-id scan failed (jq) — derived ids are checked against the used set only"
    max_id_num=0
  fi
  [[ "$max_id_num" =~ ^[0-9]+$ ]] || max_id_num=0
  (( max_id_num < finding_count )) && max_id_num=$finding_count
  while [[ $i -lt $finding_count ]]; do
    local finding
    finding=$(echo "$parsed" | jq ".findings[$i]")

    # Constraint 1: normalization pre-pass BEFORE validate_finding —
    # case-fold + trim ONLY. Unenforced branch only (cycle-124 FR-7): an
    # enforced payload's enums are exact by construction, and normalizing
    # one would hide a wire-schema/prompt drift.
    local candidate="$finding"
    if [[ "$schema_enforced" != "true" ]]; then
      candidate=$(_normalize_finding_for_validation "$finding" "$i")
      local _cid
      _cid=$(echo "$candidate" | jq -r '.id // ""' 2>/dev/null || true)
      if [[ "$(echo "$candidate" | jq -r '.id_derived // false' 2>/dev/null)" == "true" && -n "$_cid" ]] \
         && { [[ " $explicit_ids " == *" $_cid "* ]] || [[ " $used_ids " == *" $_cid "* ]]; }; then
        # self-verifying (tenth run, a1 C-002): step until the id is free of BOTH sets, whatever max_id_num holds
        while [[ " $explicit_ids " == *" $_cid "* || " $used_ids " == *" $_cid "* ]]; do
          max_id_num=$((max_id_num + 1))
          _cid=$(printf 'DISS-%03d' "$max_id_num")
        done
        candidate=$(echo "$candidate" | jq --arg id "$_cid" '.id = $id')
      fi
    fi
    # twenty-first run, a1 DISS-C-003: an explicit id the model supplied twice keeps it on its first use only — the second is
    # renumbered past every id in use and marked id_derived (the script, not the model, named it), whatever the branch
    # — and an id that is not a safe token is renumbered the same way, never logged raw (twenty-second run, a1 DISS-C-003)
    local _xid="" _xunsafe=0
    _xid=$(echo "$candidate" | jq -r '.id | strings | if test("\\A[A-Za-z0-9._:-]{1,64}\\z") then (if startswith("DISS-C-") then "\u0002" else . end) else "\u0001" end' 2>/dev/null || true)
    [[ "$_xid" == $'\001' || "$_xid" == $'\002' ]] && _xunsafe=1
    if [[ -n "$_xid" ]] && { (( _xunsafe )) || [[ " $used_ids " == *" $_xid "* ]]; }; then
      local _xnew="$_xid"
      while (( _xunsafe )) || [[ " $explicit_ids " == *" $_xnew "* || " $used_ids " == *" $_xnew "* ]]; do
        _xunsafe=0
        max_id_num=$((max_id_num + 1))
        _xnew=$(printf 'DISS-%03d' "$max_id_num")
      done
      if [[ "$_xid" == $'\001' ]]; then log "Finding $i: an explicit id that is not a safe token ([A-Za-z0-9._:-], 1-64) — renumbered $_xnew"
      elif [[ "$_xid" == $'\002' ]]; then log "Finding $i: an explicit id in the companion's DISS-C- namespace — renumbered $_xnew"
      else log "Finding $i: duplicate explicit id $_xid — renumbered $_xnew"; fi
      candidate=$(echo "$candidate" | jq --arg id "$_xnew" '.id = $id | .id_derived = true')
      _xid="$_xnew"
    fi
    [[ -n "$_xid" ]] && used_ids="$used_ids $_xid"

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

      _repair_wall_used=$(( $(_adv_repair_now) - _repair_wall_started ))
      if [[ "$schema_enforced" != "true" ]] && { (( repairs_used >= ADV_REPAIR_MAX_PER_RUN )) || (( _repair_wall_used >= _repair_wall_budget )); }; then
        repair_budget_exhausted=$((repair_budget_exhausted + 1))
        (( _repair_wall_used >= _repair_wall_budget )) && log "Repair budget: ${_repair_wall_used}s of ${_repair_wall_budget}s used — payload $i is rejected unrepaired"
      elif [[ "$schema_enforced" != "true" ]]; then
        repair_attempted="true"
        repairs_used=$((repairs_used + 1))
        local violated_field
        violated_field=$(_repair_violated_field "$reject_reason")
        local repaired="" _rm _repair_ok="false" _rcf="" _hrc=""
        # fourth run, chunk c C-008: tiny first when a credential is present, claude-headless when it is not
        # or when tiny fails — one attempt per hop, the round-trip stays bounded
        _rcf=$(mktemp "${_ADVERSARIAL_WORKDIR:-${TMPDIR:-/tmp}}/adv-repair-rc.XXXXXX" 2>/dev/null) || _rcf=""
        local _any_hop_started="false" _budget_skip="false"
        for _rm in $(_repair_model_chain "$model"); do
          # fourteenth run, a1 C-002: a hop whose real bound exceeds what is left of the wall budget is not started —
          # named on the envelope as <hop>:over_budget, so a stall never hides behind "budget policy"
          local _hb="" _est _last _mh _mv
          while read -r _mh _mv; do [[ "$_mh" == "$_rm" ]] && { _hb="$_mv"; break; }; done <<<"$_hb_memo"
          if [[ -z "$_hb" ]]; then   # (twentieth run, a1 DISS-C-001: the charge the post budget uses)
            _hb=$(_adv_hop_charge "$_rm" "${CONF_TIMEOUT:-60}"); _hb_memo+="$_rm $_hb"$'\n'
          fi
          # sixteenth run, a1 C-001: the estimate is the hop's LAST observed duration, doubled — at least the call timeout,
          # at most the bound; before any observation the bound. A keyless host's second payload is repaired too, instead
          # of every later payload being pre-empted against a 910 s worst case the first repair never approached
          _last=$(_adv_repair_last_secs "$_rm")
          if [[ "$_last" =~ ^[0-9]+$ ]]; then
            _est=$(( _last * 2 )); (( _est < ${CONF_TIMEOUT:-60} )) && _est=${CONF_TIMEOUT:-60}; (( _est > _hb )) && _est=$_hb
          else _est=$_hb; fi
          _repair_wall_used=$(( $(_adv_repair_now) - _repair_wall_started ))
          if (( _repair_wall_budget - _repair_wall_used < _est )); then
            # (once per hop, like the shared row — nineteenth run, a1 C-003; the log line too — twenty-first run, a1 DISS-C-002)
            if [[ -z "${_ADV_REPAIR_SKIP_FILE:-}" ]] || ! grep -qxF "${_rm}:over_budget" "$_ADV_REPAIR_SKIP_FILE" 2>/dev/null; then
              [[ -n "${_ADV_REPAIR_SKIP_FILE:-}" ]] && echo "${_rm}:over_budget" >> "$_ADV_REPAIR_SKIP_FILE"
              log "Repair hop $_rm needs up to ${_est}s and $(( _repair_wall_budget - _repair_wall_used ))s of the repair budget remain — not started"
            fi
            _budget_skip="true"; continue
          fi
          # seventeenth run, a1 C-003: the shared-hop rule is asked again right BEFORE this hop starts — the chain was
          # computed once, and the companion may have moved onto this hop while an earlier hop ran; a skipped hop is named
          # and never counts as an attempt
          if _adv_repair_hop_shared_now "$_rm" "$model"; then continue; fi
          [[ -n "$_rcf" ]] && : > "$_rcf"
          [[ -n "$_rcf" ]] && command rm -f -- "$_rcf.lockwait" 2>/dev/null
          _any_hop_started="true"
          local _hop_started; _hop_started=$(_adv_repair_now)
          if repaired=$(_ADV_REPAIR_RC_FILE="$_rcf" _ADV_LOCK_EXPIRED_FILE="${_rcf:+$_rcf.lockwait}" _ADV_LOCK_WAIT="${CONF_TIMEOUT:-60}" _ADV_LOCK_WAIT_CLI="${CONF_TIMEOUT:-60}" _adv_with_cli_lock "$_rm" _repair_finding_via_model "$candidate" "$type" "$reject_reason" "$_rm" "${CONF_TIMEOUT:-60}") \
             && [[ -n "$repaired" ]] && echo "$repaired" | jq empty >/dev/null 2>&1; then _adv_repair_note_secs "$_rm" $(( $(_adv_repair_now) - _hop_started )); _repair_ok="true"; break; fi
          repaired=""
          # seventeenth run, a1 C-002 / eighteenth run, a1 C-003: a duration is noted only for a hop that produced a usable
          # reply (the success branch above) — a hop that never RAN (its CLI lock was not acquired within the wait) or that
          # failed fast says nothing about how long a completed attempt takes, and a short note would let the wall-budget
          # guard admit a hop it cannot afford
          if [[ -n "$_rcf" && -e "$_rcf.lockwait" ]]; then
            command rm -f -- "$_rcf.lockwait" 2>/dev/null
            log "Repair hop $_rm never ran (its CLI lock was not acquired within ${CONF_TIMEOUT:-60}s) — no duration noted"
          fi
          # eleventh run, a1 C-003: the hop's own exit code (empty when the lock timed out or the reply was unusable
          # — neither retires a hop); an EXPLICIT auth / quota failure does, for this run's remaining repairs.
          # twelfth run, a1 C-001: exit 1 does not — it also covers a CLI-hop timeout and a transient HTTP failure,
          # whose provider line this round-trip does not keep; one slow hop must not cost every later repair
          _hrc=$(cat "$_rcf" 2>/dev/null || true)
          if [[ "$_hrc" =~ ^[0-9]+$ ]]; then
            case "$(_companion_failure_class "" "$_hrc")" in auth|quota) _adv_repair_retire_hop "$_rm" "$_hrc" ;; esac
          fi
        done
        [[ -n "$_rcf" ]] && command rm -f -- "$_rcf" 2>/dev/null
        # fifteenth run, a2 C-001: every hop pre-empted → no model was asked: a budget exhaustion, not an attempt, and
        # no ADV_REPAIR_MAX_PER_RUN slot spent
        # (twentieth run, a1 DISS-C-002: only a hop pre-empted by the budget makes it an exhaustion — a chain that was empty or
        # whose every hop the companion held is repair_skipped_no_hop)
        if [[ "$_any_hop_started" != "true" ]]; then
          repair_attempted="false"; repairs_used=$((repairs_used - 1))
          if [[ "$_budget_skip" == "true" ]]; then repair_budget_exhausted=$((repair_budget_exhausted + 1)); else repair_skipped_no_hop=$((repair_skipped_no_hop + 1)); fi
        fi
        if [[ "$_repair_ok" == "true" ]]; then
          if _repair_diff_ok "$candidate" "$repaired" "$violated_field"; then
            # ninth run, a1 C-003: the derivation markers are provenance — an accepted repair carries the
            # original's markers whatever the model echoed back
            repaired=$(jq -n --argjson o "$candidate" --argjson r "$repaired" \
              '$r | del(.id_derived, .failure_mode_derived) + ($o | {id_derived, failure_mode_derived} | with_entries(select(.value == true)))' 2>/dev/null || echo "$repaired")
            # nineteenth run, a1 C-002: a repaired DESCRIPTION supplies the failure_mode the original could not (a whitespace-only
            # description derives nothing) — re-derived here, so the repair is not spent on a payload that stays empty
            if [[ "$violated_field" == "description" ]]; then
              local _rd=""; _rd=$(printf '%s' "$repaired" | _derive_failure_mode "$i" 2>/dev/null) || _rd=""
              [[ -n "$_rd" ]] && repaired="$_rd"
            fi
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
        _write_rejected_sidecar "$rejected_sidecar" "$finding" "$sidecar_reject_reason" "$i" "$sprint_id" "$type" "$model" \
          "$repair_attempted" "$repair_succeeded" "$schema_enforced" "$parse_path" "$resp_stop_reason"
        rejected_count=$((rejected_count + 1))
        # twelfth run, a1 C-003: the entry names the sidecar ROW — its index, and the raw payload's own title (the
        # normaliser's positional id only when the payload had none, marked title_derived) — so one triage bullet
        # maps to one row
        rejected_summary=$(echo "$rejected_summary" | jq --arg fraw "${candidate:-$finding}" --arg raw "$finding" --argjson idx "$i" --arg r "${sidecar_reject_reason:-unknown-reason}" '
          (($fraw | try fromjson catch $fraw) | if type == "object" then . else {description: tojson} end) as $f
          | (($raw | try fromjson catch $raw) | if type == "object" then . else {} end) as $o
          | def nz: if . == "" then null else . end;
          . + [{
          index: $idx,
          severity: ($f.severity // null),
          title: (($o.title | nz) // ($o.id | nz) // ($f.title | nz) // ($f.id | nz) // null),
          title_derived: (((($o.title | nz) // ($o.id | nz) // null) == null) and ((($f.title | nz) // ($f.id | nz) // null) != null)),
          anchor: (if ($f.anchor // null) != null then $f.anchor
                   elif ($f.location | type) == "object" then "\($f.location.file // "")#\($f.location.anchor // "")"
                   elif ($f.location // null) != null then $f.location
                   else ($f.stable_anchor // null) end),
          reason: $r,
          description_head: (($f.description // "") | tostring | .[0:160])
        }]' 2>/dev/null || echo "$rejected_summary")
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

  # cycle-124 FR-7: repaired_count is always reported (0 on the enforced
  # branch, which never repairs) beside the parse path that produced the
  # findings and whether the hop enforced the wire schema.
  local repair_metadata_json
  repair_metadata_json=$(jq -nc --argjson rc "$repaired_count" --arg se "$schema_enforced" --arg pp "$parse_path" \
    --argjson rbe "$repair_budget_exhausted" --argjson rsn "$repair_skipped_no_hop" \
    --argjson rws "$(( $(_adv_repair_now) - _repair_wall_started ))" --argjson rwb "$_repair_wall_budget" --arg rhs "$( [[ -n "${_ADV_REPAIR_SKIP_FILE:-}" && -s "$_ADV_REPAIR_SKIP_FILE" ]] && sort -u "$_ADV_REPAIR_SKIP_FILE" | tr '\n' ' ' | sed 's/ $//' )" \
    '{repaired_count: $rc, schema_enforced: ($se == "true"), parse_path: $pp, repair_budget_exhausted: $rbe, repair_skipped_no_hop: $rsn, repair_wall_seconds: $rws, repair_wall_budget_seconds: $rwb,
      repair_hops_skipped: (if $rhs == "" then [] else ($rhs | split(" ") | unique) end)}')
  [[ -n "${_ADV_REPAIR_SKIP_FILE:-}" ]] && command rm -f -- "$_ADV_REPAIR_SKIP_FILE" 2>/dev/null; _ADV_REPAIR_SKIP_FILE=""

  jq -n \
    --argjson findings "$validated_findings" \
    --arg type "$type" --arg model "$model" --arg sid "$sprint_id" \
    --arg ts "$timestamp" \
    --argjson ti "$tokens_in" --argjson to "$tokens_out" \
    --argjson cost "$cost" --argjson lat "$latency" \
    --argjson rejc "$rejected_count" \
    --arg rejs "$rejected_sidecar_rel" \
    --argjson rejsum "$rejected_summary" \
    --argjson repairmeta "$repair_metadata_json" \
    '{findings: $findings, metadata: ({type: $type, model: $model, sprint_id: $sid,
      timestamp: $ts, tokens_input: $ti, tokens_output: $to, cost_usd: $cost,
      latency_ms: $lat, status: "reviewed", degraded: false,
      rejected_count: $rejc,
      rejected_summary: $rejsum,
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
  # this run's envelope stands: the previous run's envelope and sidecars (moved aside at start — a4 C-001, b2 C-001) are dropped
  _ADV_ENVELOPE_WRITTEN="true"
  _adv_prev_files_drop
  # …and any `.prev` an EARLIER abort left (that run never wrote an envelope, so it never dropped them): a standing envelope
  # supersedes every previous round's aside files
  command rm -f -- "$output_path.prev" "$output_dir"/adversarial-rejected-"${type}"*.jsonl.prev 2>/dev/null || true

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

  _emit_rejection_degraded "$result_json" "$type" "$sprint_id"
}

# cycle-119 C14 (KF-004 repair loop, #1177-D wiring), unconditional since
# cycle-124 FR-7: rejected+repaired counts feed the SAME uniform
# degraded-trajectory channel so "N findings silently eaten" is visible
# without opening the sidecar — on BOTH parse paths (an enforced payload
# that still fails validate_finding is a wire-schema/prompt drift signal).
# Distinct gate suffix so it never collides with the api_failure /
# verdict_quality record.
_emit_rejection_degraded() {
  local result_json="$1" type="$2" sprint_id="$3"
  declare -F degraded_verdict_maybe_emit >/dev/null 2>&1 || return 0
  local _c14_rejected _c14_repaired _c14_pp
  _c14_rejected=$(echo "$result_json" | jq -r '.metadata.rejected_count // 0' 2>/dev/null) || _c14_rejected=0
  _c14_repaired=$(echo "$result_json" | jq -r '.metadata.repaired_count // 0' 2>/dev/null) || _c14_repaired=0
  _c14_pp=$(echo "$result_json" | jq -r '.metadata.parse_path // "normalized"' 2>/dev/null) || _c14_pp="normalized"
  local _c14_rbe _c14_rbe_note=""
  _c14_rbe=$(echo "$result_json" | jq -r '.metadata.repair_budget_exhausted // 0' 2>/dev/null) || _c14_rbe=0
  if [[ "$_c14_rbe" =~ ^[0-9]+$ ]] && [[ "$_c14_rbe" -gt 0 ]]; then
    _c14_rbe_note="; ${_c14_rbe} past the ${ADV_REPAIR_MAX_PER_RUN}-repair budget"
  fi
  if [[ "$_c14_rejected" =~ ^[0-9]+$ ]] && [[ "$_c14_rejected" -gt 0 ]]; then
    degraded_verdict_maybe_emit "adversarial-review:${type}:repair-loop" "DEGRADED" \
      "kf-004-repair-loop: ${_c14_rejected} rejected finding(s) survived repair (${_c14_repaired} repaired${_c14_rbe_note}; parse_path=${_c14_pp})" \
      "$sprint_id" "-"
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

# =============================================================================
# cycle-126 FR-2.1 (SDD D-2.1): the companion voice. A second, independent
# chain from the OTHER provider family runs in parallel with the primary chain
# and the two completed envelopes are aggregated (`voices_planned` 2). The
# family is decided from the configured primary model; credential PRESENCE
# (env → .env.local → .env, value never read) decides only where the
# companion chain STARTS (an HTTP voice with no key is skipped straight to the
# CLI hop); the companion's outcome is its actual completion. A companion whose
# whole chain fails is a dropped voice (degraded, never blocking a review;
# audit keeps its degraded rules) with a named failure class. Its rejected
# payloads land in their own sidecar (`-companion` suffix), never the primary's.
# =============================================================================
_adv_family_of() {  # <model alias or id> → anthropic | openai | google | unknown
  local m="$1" prov=""
  if ! declare -p MODEL_PROVIDERS >/dev/null 2>&1; then
    # shellcheck source=generated-model-maps.sh
    [[ -f "$SCRIPT_DIR/generated-model-maps.sh" ]] && source "$SCRIPT_DIR/generated-model-maps.sh" 2>/dev/null || true
  fi
  if declare -p MODEL_PROVIDERS >/dev/null 2>&1; then prov="${MODEL_PROVIDERS[$m]:-}"; fi
  if [[ -z "$prov" ]]; then
    case "$m" in
      anthropic:*|claude*|opus*|sonnet*|haiku*|fable*|tiny|cheap) prov="anthropic" ;;
      openai:*|gpt-*|codex*|o[0-9]*) prov="openai" ;;
      google:*|gemini*|agy*) prov="google" ;;
      *) prov="unknown" ;;
    esac
  fi
  echo "$prov"
}

_companion_family() {  # <primary family> → the other family (google/unknown primaries get the Anthropic chain)
  case "$1" in
    anthropic) echo "openai" ;;
    *) echo "anthropic" ;;
  esac
}

_adv_cli_present() {  # <family> → 0 when the family's CLI hop binary is on PATH (bats seam: LOA_ADVERSARIAL_CLI_PROBE)
  local fam="$1" bin=""
  case "$fam" in anthropic) bin=claude ;; openai) bin=codex ;; google) bin=agy ;; *) return 1 ;; esac
  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_ADVERSARIAL_CLI_PROBE:-}" ]]; then
    case "$LOA_ADVERSARIAL_CLI_PROBE" in both|"$bin") return 0 ;; *) return 1 ;; esac
  fi
  command -v "$bin" >/dev/null 2>&1
}

_companion_chain() {  # <family> → space-separated chain, credential presence deciding the start; "" = no route
  local fam="$1" configured=""
  case "$fam" in
    anthropic) configured="${CONF_COMPANION_CHAIN_ANTHROPIC:-}" ;;
    openai)    configured="${CONF_COMPANION_CHAIN_OPENAI:-}" ;;
  esac
  if [[ -n "$configured" ]]; then echo "$configured"; return 0; fi   # review sprint-248 C-011: the operator's list as given
  local http="" hop=""
  case "$fam" in
    anthropic) http="opus"; hop="claude-headless" ;;
    # round 1 (third run, C-007): gpt-5.5-pro returns empty content on review prompts (KF-002,
    # recurrence 5) — the default starts at gpt-5.5; companion_chain.openai can still name it
    openai)    http="gpt-5.5"; hop="codex-headless" ;;
    *) echo ""; return 0 ;;
  esac
  local chain=""
  _adv_cred_present "$fam" && chain="$http"
  # review sprint-248 C-007: the CLI hop is planned only when its binary exists — a single-family
  # host must not see every dissent plan a companion that cannot succeed
  _adv_cli_present "$fam" && chain="${chain:+$chain }$hop"
  echo "$chain"
}

# round 1 (third run, C-003; fourth run): a *-headless hop is bounded by cheval's CLI adapter —
# connect 10 s + max(600 s, the catalog's per-model headless_timeout_seconds) — not by the block's
# timeout_seconds. The wait cap sums each hop's own bound, plus slack.
_ADV_RUN_TAG=""; _ADV_RUN_TAG_RAW_SEEN=""
_adv_resolve_run_tag() {  # sets _ADV_RUN_TAG for LOA_ADVERSARIAL_RUN_TAG: the tag itself when it is [A-Za-z0-9_-]{1,64}, a short hash of
                          # the raw value otherwise (said once per value — resolved into a global, never captured in a subshell
                          # where a said-once flag would be lost; thirteenth run, a2 C-006), "" when unset. Eleventh run, a1 C-002:
                          # stripping the odd characters collapsed distinct tags (`c.1`, `c1`) onto one file — which the next
                          # statement truncated.
  local _rt="${LOA_ADVERSARIAL_RUN_TAG:-}" _h=""
  [[ "${_ADV_RUN_TAG_RAW_SEEN:-}" == "set:$_rt" ]] && return 0   # (a default: -u-safe wherever the function is copied — sixteenth run, c2a C-002)
  _ADV_RUN_TAG_RAW_SEEN="set:$_rt"
  if [[ -z "$_rt" ]]; then _ADV_RUN_TAG=""; return 0; fi
  if [[ "$_rt" =~ ^[A-Za-z0-9_-]{1,64}$ ]]; then _ADV_RUN_TAG="$_rt"; return 0; fi
  _h=$(printf '%s' "$_rt" | sha256sum 2>/dev/null | cut -c1-12) || _h=""
  [[ -n "$_h" ]] || _h=$(printf '%s' "$_rt" | shasum -a 256 2>/dev/null | cut -c1-12) || _h=""   # (macOS: no sha256sum, KF-012; `|| _h=""`: errexit-safe — fifteenth run, a2 C-003)
  if [[ -z "$_h" ]]; then   # no digest tool: the raw tag hex-encoded, whole up to 100 bytes and its byte length beyond (twelfth run, c2 C-003;
                            # eighteenth run, a2 C-004: a 40-hex cut shared a name for tags that differed only after byte 20)
    _h=$(printf '%s' "$_rt" | od -An -v -tx1 2>/dev/null | tr -d ' \n') || _h=""   # (-v: od folds repeated lines into `*` — a run of sixteen equal bytes vanished)
    if [[ -n "$_h" && ${#_h} -gt 200 ]]; then _h="${_h:0:200}-$(( ${#_h} / 2 ))"; fi
  fi
  [[ -n "$_h" ]] || _h="invalid"
  log "WARN: LOA_ADVERSARIAL_RUN_TAG is not [A-Za-z0-9_-]{1,64} — this run's sidecars carry the tag h${_h} instead (distinct raw tags never share a file)"
  _ADV_RUN_TAG="h${_h}"
}
_adv_run_tag() { _adv_resolve_run_tag; printf '%s' "$_ADV_RUN_TAG"; }   # (the tests' stdout form)
_adv_refuse_json() {  # <status> [key value]… → the envelope a --json caller gets when the run cannot start (it fails closed —
                      # twelfth run a3 C-004, thirteenth run a3 C-005); type / sprint_id are main's
  local st="$1"; shift
  local -a kv=(); while (( $# >= 2 )); do kv+=(--arg "$1" "$2"); shift 2; done
  jq -n --arg t "${type:-}" --arg sid "${sprint_id:-}" --arg st "$st" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ${kv[@]+"${kv[@]}"} \
    '{findings: [], metadata: ({type: $t, sprint_id: $sid, timestamp: $ts, status: $st, model: null, cost_usd: 0} + ($ARGS.named | del(.t, .sid, .st, .ts)))}'
}
_adv_record_fallback() {  # <type> <sprint id> <status> <reason> [since] → the failed-run record the review / audit skill writes, done by the
                          # script under its run lock (twenty-third run, b2 DISS-C-001: the skills' allowlists hold no `mv`, and a
                          # Write-tool fallback can neither move the previous round's files aside nor see a live run)
  local t="$1" sid="$2" st="$3" why="$4" since="${5:-}" dir env sc ets displaced="null"
  case "$st" in
    failed|workdir_unavailable|nothing_to_review|budget_exceeded) ;;
    refused_concurrent_run) error "--record-fallback: refused_concurrent_run is not recorded — wait until the holding run has exited and run the review again"; return 2 ;;
    *) error "--record-fallback: unknown status '$st' (failed | workdir_unavailable | nothing_to_review | budget_exceeded)"; return 2 ;;
  esac
  [[ -n "$why" ]] || { error "--record-fallback needs --reason <what happened>"; return 2; }
  if [[ -n "$since" ]]; then
    [[ "$st" == "failed" ]] || { error "--since applies to --record-fallback failed only"; return 2; }
    [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { error "--since: expected YYYY-MM-DDTHH:MM:SSZ (UTC)"; return 2; }
  fi
  [[ "$sid" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ && "$sid" != *..* ]] || { error "--record-fallback: invalid --sprint-id"; return 2; }
  dir="$PROJECT_ROOT/grimoires/loa/a2a/${sid}"; env="$dir/adversarial-${t}.json"
  mkdir -p "$dir" || { error "cannot create $dir"; return 2; }
  trap '_adv_release_run_lock || true' EXIT
  if ! _adv_take_run_lock "$dir" "$t"; then
    error "a live run holds the $t run lock for $sid — wait until it has exited, then record"
    _adv_refuse_json refused_concurrent_run
    return 2
  fi
  # (twenty-fourth run, b2 DISS-C-002: the record says what it moves aside — a regular envelope is moved on every path that
  # gets past the refusals below — so a reviewer and verdict-derive can read what the fallback replaced)
  if [[ -f "$env" && ! -L "$env" ]]; then
    displaced=$(jq -c '{status: (.metadata.status? // null), timestamp: (.metadata.timestamp? // null),
      findings: (.findings? | if type == "array" then length else null end),
      rejected: (.metadata.rejected_summary? | if type == "array" then length else null end)}' -- "$env" 2>/dev/null) || displaced=""
    [[ -n "$displaced" ]] || displaced='{"status":null,"timestamp":null,"findings":null,"rejected":null,"unreadable":true}'
  fi
  if [[ "$st" == "failed" ]]; then
    # an aborted run left no envelope; one that stands was written by a run that took the lock — it is never overwritten, and
    # this run's own sidecars stay where verdict-derive counts them
    # (twenty-fourth run, a2 DISS-C-001: a run that died BEFORE its lock wrote no status and moved nothing aside — the envelope
    # that stands is the previous round's; `--since <the run's start>` shows it: a metadata.timestamp older than that, or none)
    if [[ -e "$env" || -L "$env" ]]; then
      local older="false"
      if [[ -n "$since" && -f "$env" && ! -L "$env" ]] && ets=$(jq -r '.metadata.timestamp? // "" | strings' -- "$env" 2>/dev/null); then
        if [[ -z "$ets" ]] || [[ "$ets" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ && "$ets" < "$since" ]]; then older="true"; fi
      fi
      if [[ "$older" != "true" ]]; then
        error "an envelope stands at $env — a run wrote it; nothing is recorded over it (a run that died before its lock left the previous round's: pass --since <that run's start, UTC> to move an older one aside)"
        return 2
      fi
      for sc in "$env" "$dir"/adversarial-rejected-"${t}"*.jsonl; do
        [[ -f "$sc" && ! -L "$sc" ]] || continue
        mv -f -- "$sc" "$sc.prev" || { error "cannot move $sc aside"; return 2; }
      done
    fi
  else
    # a pre-lock refusal moved nothing aside: whatever is at the path is the PREVIOUS round's, as a run's start would treat it
    for sc in "$env" "$dir"/adversarial-rejected-"${t}"*.jsonl; do
      [[ -f "$sc" && ! -L "$sc" ]] || continue
      mv -f -- "$sc" "$sc.prev" || { error "cannot move $sc aside"; return 2; }
    done
  fi
  jq -n --arg t "$t" --arg sid "$sid" --arg st "$st" --arg r "$why" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson d "$displaced" \
    '{findings: [], metadata: {type: $t, sprint_id: $sid, timestamp: $ts, status: $st, reason: $r, recorded_by: "record-fallback",
      displaced: $d, rejected_summary: [], rejected_sidecars: []}}' > "$env.tmp.$$" && mv -f -- "$env.tmp.$$" "$env" \
    || { command rm -f -- "$env.tmp.$$"; error "cannot write $env"; return 2; }
  log "Recorded the $t fallback ($st) at $env"
  return 0
}
_ADV_RUN_LOCK_DIR=""; _ADV_RUN_LOCK_OWNER=""
_adv_proc_start() {  # <pid> → an environment-independent start token ("" when unknown): /proc starttime ticks, else a UTC/C lstart
  # (thirteenth run, a2 C-002: `ps -o lstart=` renders in the caller's TZ and locale — two runs launched from different
  # environments would compare different strings for the same live pid and one would demote the other's lock)
  local st
  if [[ -r "/proc/$1/stat" ]]; then
    st=$(awk '{ n = split($0, a, ")"); split(a[n], f, " "); print f[20] }' "/proc/$1/stat" 2>/dev/null)   # field 22 of stat: starttime
    [[ "$st" =~ ^[0-9]+$ ]] && { echo "t$st"; return 0; }
  fi
  _adv_lstart_token "$1"
}
_adv_lstart_token() {  # <pid> → the UTC/C lstart as ONE word (twenty-first run, a3 DISS-C-002: "Wed Oct  1 …" split a pid=token map
                       # entry into words, and the reaper's same-process check then compared "Wed" with the whole string)
  TZ=UTC LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/_/g' || true
}
_adv_tok_word() { local _t="${1:-}"; _t="${_t#"${_t%%[![:space:]]*}"}"; _t="${_t%"${_t##*[![:space:]]}"}"; printf '%s' "${_t//[[:space:]]/_}" | tr -s '_'; }   # <token> → one word (a3 DISS-C-002)
_adv_take_run_lock() {  # <sprint dir> <gate> → 0 with this run's key locked (the EXIT trap releases it); 1 when a LIVE run holds it
  # eleventh run, a2 DISS-001: the envelope adversarial-<gate>.json and the two sidecars are single-writer per (sprint,
  # gate) — the tag scopes the sidecar NAMES only, the envelope path is shared (twelfth run, a2 C-003) — so a second live
  # run for the same sprint and gate is refused before anything is removed. mkdir + a pid token, not flock: no fd for a
  # child to inherit. The token is pid + process start time (a reused pid is not the holder); an absent token is a
  # holder in flight for five seconds (LOA_ADVERSARIAL_RUN_LOCK_GRACE_SECONDS) and a dead one after (twelfth run, a2 C-002).
  local key="" dir pidf other ostart cur _try _w lockdir _g
  # (twentieth run, c1b C-005: the in-flight grace is a validated knob, so a test can hold a token-less lock live past it)
  _g=$(_conf_uint "LOA_ADVERSARIAL_RUN_LOCK_GRACE_SECONDS" "${LOA_ADVERSARIAL_RUN_LOCK_GRACE_SECONDS:-5}" 5 0) || _g=5
  key=$(printf '%s|%s' "$1" "$2" | sha256sum 2>/dev/null | cut -c1-16) || key=""
  [[ -n "$key" ]] || key=$(printf '%s|%s' "$1" "$2" | shasum -a 256 2>/dev/null | cut -c1-16) || key=""
  # twenty-first run, a2 DISS-C-001 / c1b DISS-C-004: every fail-open path below runs unguarded — never a refusal — and says so,
  # once (this is called once per run), as the per-binary lock's _adv_run_unlocked does. The lock lives in the per-user runtime
  # directory: two launchers that resolve XDG_RUNTIME_DIR differently, or two users of one checkout, do not see each other's lock
  [[ -n "$key" ]] || { _adv_run_lock_unguarded "no sha256sum or shasum to name the lock"; return 0; }
  lockdir=$(_adv_cli_lock_dir)
  [[ -d "$lockdir" ]] || mkdir -m 700 "$lockdir" 2>/dev/null || { _adv_run_lock_unguarded "the lock directory $lockdir cannot be created"; return 0; }
  [[ -L "$lockdir" || ! -O "$lockdir" ]] && { _adv_run_lock_unguarded "the lock directory $lockdir is a symlink or not owned by this user"; return 0; }   # (not ours: the CLI lock declines it too)
  command -v "${_ADV_FLOCK_BIN:-flock}" >/dev/null 2>&1 \
    || log "WARN: flock is not installed — the run lock's stale-lock takeover runs unserialised (two takers of a dead run's lock may race)"
  dir="$lockdir/run-${key}.lock.d"; pidf="$dir/pid"
  local _mkerr=""
  # (twenty-fifth run, a2 C-001: a fourth round only makes the mkdir — a takeover or a release in round three frees the key for it)
  for _try in 1 2 3 4; do
    if _mkerr=$(LC_ALL=C mkdir "$dir" 2>&1); then
      # (fifteenth run, a2 C-002: the owner is the acquiring BASHPID — a subshell of this run inherits $$ but never this;
      # sixteenth run, a2 C-001: the pid and its token are taken HERE — `$BASHPID` inside a $(...) is the substitution's
      # own pid, whose start time made every live holder look recycled)
      local me="$BASHPID" tok=""; tok=$(_adv_proc_start "$me") || tok=""
      printf '%s\n%s\n' "$me" "$tok" > "$pidf"
      _ADV_RUN_LOCK_DIR="$dir"; _ADV_RUN_LOCK_OWNER="$me"; return 0
    fi
    # twenty-fourth run, a2 C-002: only contention (EEXIST) is a holder to judge — a lock that cannot be made (EACCES, ENOSPC, EROFS)
    # runs unguarded at once with mkdir's reason, never three rounds of a race that is not there
    if [[ ! -d "$dir" && "$_mkerr" != *"File exists"* ]]; then
      _adv_run_lock_unguarded "the run lock $dir cannot be created: ${_mkerr##*: }"; return 0
    fi
    (( _try == 4 )) && break
    # the verdict on the holder and the takeover itself are ONE critical section per key (eighteenth run, a2 C-001: rm + rmdir
    # let two takers each believe they held the key; the round-1s dry run then showed a taker that had judged the holder dead
    # from the OLD pid file renaming a LIVE lock re-created a moment earlier — so the decision and the rename are serialised
    # under a per-key flock, and the loop's mkdir decides). Without flock the section runs unserialised, as before.
    local _tl="$lockdir/run-${key}.takeover.lock" _verdict=""
    _verdict=$(
      # twenty-second run, a2 DISS-C-001: a section that cannot be entered (another taker holds it past the wait) still judges the
      # holder — a LIVE one refuses this run, as it would inside — but takes nothing over without the flock: the loop retries, and a section still busy after the last round refuses
      _unser=0
      if command -v "${_ADV_FLOCK_BIN:-flock}" >/dev/null 2>&1; then   # (the same resolved binary as the per-binary lock — a2 C-005)
        if ! { exec 7>>"$_tl"; } 2>/dev/null; then _unser=2   # (twenty-fourth run, a2 C-002: an unopenable section is no taker — never busy)
        elif ! "${_ADV_FLOCK_BIN:-flock}" -w 5 7; then _unser=1; fi
      fi
      _w=0
      while [[ -d "$dir" && ! -s "$pidf" ]] && (( _w < 10 )) && (( $(date +%s) - $(_adv_mtime "$dir") < _g )); do sleep 0.2; _w=$((_w + 1)); done
      [[ -d "$dir" ]] || { echo retry; exit 0; }   # (thirteenth run, a2 C-005: the holder released between our mkdir and the read — retry, never a false refusal)
      other=$(sed -n 1p "$pidf" 2>/dev/null || true); ostart=$(sed -n 2p "$pidf" 2>/dev/null || true)
      ostart=$(_adv_tok_word "$ostart")   # (a3 DISS-C-002: a holder that wrote a spaced lstart is compared as one word, like the reader's own)
      if [[ "$other" =~ ^[0-9]+$ ]] && _adv_pid_alive "$other"; then   # (nineteenth run, a2 C-002: a zombie answers kill -0 and keeps its start time — it is dead, as the reaper knows)
        cur=$(_adv_proc_start "$other" 2>/dev/null || true)
        if [[ -z "$ostart" || -z "$cur" || "$ostart" == "$cur" ]]; then
          error "another adversarial-review run for ${1##*/}/$2 is in progress (pid $other) — its envelope adversarial-$2.json and sidecars are single-writer; wait for it to finish"
          echo refuse; exit 0
        fi
        # the pid was reused by an unrelated process: the holder is gone
      elif [[ -d "$dir" && ! -s "$pidf" ]] && (( $(date +%s) - $(_adv_mtime "$dir") < _g )); then
        error "another adversarial-review run for ${1##*/}/$2 is starting (its lock is seconds old) — wait for it to finish"
        echo refuse; exit 0
      fi
      (( _unser == 2 )) && { echo unopenable; exit 0; }
      (( _unser )) && { echo busy; exit 0; }
      # a dead run's lock: renamed away (atomic), then removed; the loop's mkdir takes the key
      _stale="$dir.stale.$BASHPID.$RANDOM"
      if mv -- "$dir" "$_stale" 2>/dev/null; then command rm -rf -- "$_stale" 2>/dev/null || true; fi
      echo takeover
    ) || _verdict="retry"
    [[ "$_verdict" == "refuse" ]] && return 1
    [[ "$_verdict" == "unopenable" ]] && { _adv_run_lock_unguarded "the takeover lock $_tl cannot be opened (a dead run's lock is not taken over unserialised)"; return 0; }
  done
  # twenty-third run, c1c DISS-C-004: a section still held after the last round is another taker inside the takeover — about to
  # become the live holder, never an absence — so the run is refused, not run unguarded beside it (flock frees the section on exit)
  if [[ "$_verdict" == "busy" ]]; then
    error "another taker holds the takeover of a dead run's lock for ${1##*/}/$2 — it is becoming the holder; wait for it to finish"
    return 1
  fi
  _adv_run_lock_unguarded "a takeover of a dead run's lock did not settle in three rounds"
  return 0   # (a take-over race that would not settle: run unguarded rather than refuse)
}
_adv_run_lock_unguarded() {  # <reason> — the run lock is not held: said once per process, never a refusal (twenty-first run, a2 DISS-C-001)
  [[ "${_ADV_RUN_LOCK_WARNED:-}" == "1" ]] && return 0
  _ADV_RUN_LOCK_WARNED=1
  log "WARN: the (sprint, gate) run lock is not taken — $1; this run is NOT guarded against a concurrent run for the same sprint and gate (its envelope and sidecars are single-writer)"
  return 0
}
_adv_release_run_lock() {
  [[ -n "${_ADV_RUN_LOCK_DIR:-}" && -d "$_ADV_RUN_LOCK_DIR" ]] || { _ADV_RUN_LOCK_DIR=""; return 0; }
  # (thirteenth run, a3 C-006: only the run whose pid the token names releases it — belt and braces over the
  # variable, which a refused run never sets)
  [[ "${_ADV_RUN_LOCK_OWNER:-}" == "$BASHPID" && "$(sed -n 1p "$_ADV_RUN_LOCK_DIR/pid" 2>/dev/null)" == "$BASHPID" ]] || return 0   # (a subshell never releases the parent's lock)
  command rm -f -- "$_ADV_RUN_LOCK_DIR/pid" 2>/dev/null; rmdir "$_ADV_RUN_LOCK_DIR" 2>/dev/null || true
  _ADV_RUN_LOCK_DIR=""
}
# nineteenth run, a2 C-005: the test seams are honoured under the bats marker only — `_ADV_FLOCK_BIN=true` in a production
# environment would turn every per-binary lock into a no-op success without a word
if [[ -z "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" ]]; then unset _ADV_FLOCK_BIN _ADV_PGREP_BIN _ADV_REDACTOR_BIN _ADV_LOCK_WAIT _ADV_LOCK_WAIT_CLI _ADV_REPAIR_RC_FILE _ADV_REPAIR_SKIP_FILE _ADV_LOCK_EXPIRED_FILE; fi
_ADV_CLI_HOP_CEILING=3600   # mirrors HEADLESS_TIMEOUT_CEILING_SECONDS (loa_cheval/types.py): cheval clamps the catalog value there at load; NRM-18 pins the two equal
_adv_cli_hop_timeout_load() {  # LOA_ADVERSARIAL_CLI_HOP_TIMEOUT → _ADV_CLI_HOP_TIMEOUT: the fallback bound for a hop no catalog lists (a listed hop is
                               # bound by cheval's formula) — a whole number of at least 1, else 610 said once; never above the ceiling
                               # (eighteenth run, a2 C-003: the one numeric knob that bypassed _conf_uint, used in arithmetic and as flock -w)
  _ADV_CLI_HOP_TIMEOUT=$(_conf_uint "LOA_ADVERSARIAL_CLI_HOP_TIMEOUT" "${LOA_ADVERSARIAL_CLI_HOP_TIMEOUT:-610}" 610 1)
  if (( _ADV_CLI_HOP_TIMEOUT > _ADV_CLI_HOP_CEILING )); then
    log "WARN: LOA_ADVERSARIAL_CLI_HOP_TIMEOUT='${_ADV_CLI_HOP_TIMEOUT}' exceeds the CLI hop ceiling — ${_ADV_CLI_HOP_CEILING} applies"
    _ADV_CLI_HOP_TIMEOUT=$_ADV_CLI_HOP_CEILING
  fi
  return 0
}
_adv_cli_hop_timeout_load
_adv_cli_hop_bound() {  # <hop> → seconds the CLI adapter allows this hop: max(connect,10) + max(read,600,headless_timeout_seconds)
  local hop cat="${LOA_MODEL_CONFIG:-$PROJECT_ROOT/.claude/defaults/model-config.yaml}" v="" ct="" rt=""
  hop=$(_adv_hop_canon "$1")   # (thirteenth run, a2 C-001: the catalog is read under the canonical id)
  local from_catalog="false"
  if command -v yq >/dev/null 2>&1 && [[ -f "$cat" ]]; then
    # the hop must be LISTED by a provider (has(), never a `// default`: yq's alternative operator fires on an empty stream,
    # so the `// 10` below would read as catalog data for a hop no provider lists — round-1q dry run, CMP-22)
    [[ "$(yq eval "[.providers[] | (.models // {}) | has(\"$hop\")] | any" "$cat" 2>/dev/null)" == "true" ]] && from_catalog="true"
  fi
  if [[ "$from_catalog" == "true" ]]; then
    v=$(yq eval "[.providers[].models.\"$hop\".headless_timeout_seconds | select(. != null)] | .[0]" "$cat" 2>/dev/null)
    # seventh run, chunk d C-002: the provider block's own timeouts are part of cheval's formula too
    ct=$(yq eval "[.providers | to_entries[] | select(.value.models.\"$hop\" != null) | (.value.connect_timeout // 10)] | .[0]" "$cat" 2>/dev/null)
    rt=$(yq eval "[.providers | to_entries[] | select(.value.models.\"$hop\" != null) | (.value.read_timeout // 120)] | .[0]" "$cat" 2>/dev/null)
  fi
  [[ "$ct" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ct=10; ct=${ct%.*}; (( ct < 10 )) && ct=10
  [[ "$rt" =~ ^[0-9]+(\.[0-9]+)?$ ]] || rt=120; rt=${rt%.*}; (( rt < 600 )) && rt=600
  if [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    local r=${v%.*}; (( r > _ADV_CLI_HOP_CEILING )) && r=$_ADV_CLI_HOP_CEILING; (( r > rt )) && rt=$r
  fi
  # cheval's whole formula — max(connect, 10) + max(read, 600, headless_timeout_seconds) — whenever the catalog was read
  # (sixteenth run, a2 C-003: a connect_timeout above 10 s counts even under a 600 s read floor); the operator fallback
  # for a hop no catalog lists, or without a catalog
  if [[ "$from_catalog" == "true" ]]; then echo $(( ct + rt )); else echo "$_ADV_CLI_HOP_TIMEOUT"; fi
}
_adv_cli_inner_bound() {  # <HTTP hop> → the CLI bound its catalog fallback_chain can reach inside ONE cheval call, 0 when none
                          # (eighteenth run, a2 C-002: _adv_cli_bin_for already serialises such a hop for that reason — the wait cap
                          # and the post budget count the same possibility: the hop's own timeout, then the CLI adapter's bound)
  local bin; bin=$(_adv_cli_bin_for "$1")
  if [[ -n "$bin" ]]; then _adv_cli_hop_bound "${bin}-headless"; else echo 0; fi
}
_adv_hop_charge() {  # <hop> <timeout_seconds> → the seconds ONE call on this hop can take: a *-headless hop its lock wait (the
                     # repair waits up to the timeout for the CLI lock — twenty-third run, a2 DISS-C-001) then its CLI bound; an HTTP
                     # hop whose catalog chain reaches a CLI binary its lock wait, its own timeout, then that CLI's bound; else
                     # the timeout (twentieth run, a1 DISS-C-001: one rule for the repair budget and the post budget; a3 DISS-C-003:
                     # a bound that is not a whole number is the adapter's default, never 0 or an arithmetic error)
  local t="$2" bin b
  case "$(_adv_hop_canon "$1")" in
    *-headless) echo $(( t + $(_adv_num_or "$(_adv_cli_hop_bound "$1")" 610) )) ;;
    *) bin=$(_adv_cli_bin_for "$1")
       if [[ -n "$bin" ]]; then b=$(_adv_num_or "$(_adv_cli_hop_bound "${bin}-headless")" 610); echo $(( t + t + b )); else echo "$t"; fi ;;
  esac
}
_companion_queue_allowance() {  # <hop>... → seconds: the global ceiling's allowance for the queue phases — each *-headless hop's queue at the
                                # bound its own queue phase is given (twenty-first run, a4 DISS-C-001). An HTTP hop whose catalog chain
                                # reaches a CLI adds nothing here: its lock wait is already the first t of its t + t + b wait-cap share
                                # (twenty-second run, a2 DISS-C-002 — counting it again over-granted the ceiling)
  local h a=0
  for h in "$@"; do
    case "$(_adv_hop_canon "$h")" in
      *-headless) a=$(( a + $(_adv_num_or "$(_adv_cli_hop_bound "$h")" 610) + 30 )) ;;
    esac
  done
  echo "$a"
}
_companion_wait_cap() {  # <timeout_seconds> <hop>... → seconds
  local t="$1" cap=0 h b; shift
  for h in "$@"; do
    case "$(_adv_hop_canon "$h")" in   # (canonical: a prefixed or aliased CLI hop counts its CLI bound — thirteenth run, a2 C-001)
      *-headless) b=$(_adv_cli_hop_bound "$h"); cap=$(( cap + (t > b ? t : b) )) ;;
      *)          b=$(_adv_cli_inner_bound "$h"); if (( b > 0 )); then cap=$(( cap + t + t + b )); else cap=$(( cap + t )); fi ;;   # (eighteenth run, a2 C-002 / nineteenth run, a2 C-001: the lock wait, its own timeout, then the CLI its chain can reach)
    esac
  done
  echo $(( cap + 30 ))
}

# fourth run, chunk c C-003: two *-headless hops must not overlap — the primary walking onto
# claude-headless while the companion's claude -p is still running is the KF-037 contention shape,
# now reachable from one dissent. A per-binary flock serialises CLI invocations across the walks
# (and across concurrent dissents on the host); a lock that cannot be had within the hop's own
# bound is not waited for any longer than that.
_adv_cli_lock_dir() { echo "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/loa-headless-locks-$(id -u 2>/dev/null || echo 0)"; }
_adv_hop_canon() {  # <model> → the catalog id: provider prefix stripped, alias resolved (thirteenth run, a2 C-001 — every
                    # reader of a hop's CLI nature and bound goes through this, so `anthropic:claude-headless` IS claude-headless)
  local m="$1" cat="${LOA_MODEL_CONFIG:-$PROJECT_ROOT/.claude/defaults/model-config.yaml}" target
  # (twenty-fifth run, a3 C-001: ANY provider prefix — `bedrock:`, `xai:` as well as the three companion families — so a prefixed
  # and a bare spelling of one hop share one bound and one lock; a provider token has no dot, so a bedrock id's `-v1:0` stays)
  [[ "$m" =~ ^[A-Za-z0-9_-]+:(.+)$ ]] && m="${BASH_REMATCH[1]}"
  if command -v yq >/dev/null 2>&1 && [[ -f "$cat" ]]; then
    target=$(yq eval ".aliases.\"$m\"" "$cat" 2>/dev/null); [[ -n "$target" && "$target" != "null" ]] && m="${target#*:}"
  fi
  echo "$m"
}
_adv_cli_bin_for() {  # <model> → the CLI binary this hop can end up exec'ing ("" when none): the hop itself, or the first
                      # *-headless entry of its catalog fallback_chain (eighth run, a2 C-002 — cheval walks that chain inside one call)
  local m cat="${LOA_MODEL_CONFIG:-$PROJECT_ROOT/.claude/defaults/model-config.yaml}" hop=""
  m=$(_adv_hop_canon "$1")   # twelfth run, a2 C-001: normalised BEFORE the *-headless test
  case "$m" in *-headless) echo "${m%-headless}"; return 0 ;; esac
  command -v yq >/dev/null 2>&1 && [[ -f "$cat" ]] || { echo ""; return 0; }
  hop=$(yq eval "[.providers[].models.\"$m\".fallback_chain // [] | .[] | select(test(\"-headless$\"))] | .[0]" "$cat" 2>/dev/null)
  [[ -n "$hop" && "$hop" != "null" ]] || { echo ""; return 0; }
  hop="${hop#*:}"; echo "${hop%-headless}"
}
_adv_run_unlocked() {  # <reason> <cmd…> — run a CLI hop WITHOUT the per-binary lock: the reason is said once per run (a marker
                       # file the capture subshells share — a variable set inside $(...) is lost: fifteenth run, a3 C-002) and the
                       # hop's phase still starts, so the wait loop charges the hop, not the queue (a3 C-001)
  local why="$1"; shift
  # nineteenth run, a2 C-004: the marker lives in the run's own workdir (shared by its capture subshells); without a workdir an
  # in-process flag — never a predictable name in a shared tmp that a symlink could point elsewhere or a reused pid could inherit
  local marker="" said="false"
  if [[ -n "${_ADVERSARIAL_WORKDIR:-}" && -d "${_ADVERSARIAL_WORKDIR:-}" ]]; then
    marker="$_ADVERSARIAL_WORKDIR/.adv-unlocked-warned"
    [[ -e "$marker" ]] && said="true"; : > "$marker" 2>/dev/null || true
  else
    [[ "${_ADV_UNLOCKED_WARNED:-}" == "1" ]] && said="true"; _ADV_UNLOCKED_WARNED=1
  fi
  if [[ "$said" != "true" ]]; then
    log "WARN: a *-headless hop runs unserialised — ${why} — two claude -p / codex calls may overlap on this host (KF-037)"
  fi
  [[ -n "${_ADV_PHASE_FILE:-}" ]] && _adv_put_state "$_ADV_PHASE_FILE" hop
  "$@"
}
_adv_with_cli_lock() {  # <model> <cmd…> — run cmd; a *-headless model runs under its binary's lock (fifth run: a lock
                        # not acquired within the hop's bound FAILS the hop as a timeout, rc 124 — never unserialised)
  local model="$1"; shift
  local bin; bin=$(_adv_cli_bin_for "$model")
  case "${bin:+cli}" in
    cli)
      local lockdir lock wait_s
      lockdir=$(_adv_cli_lock_dir)
      # tenth run, a2 C-001: a *-headless hop waits up to its own CLI bound; a model that merely RESOLVES to a
      # CLI hop (an HTTP alias, the repair's `tiny`) waits only as long as its own call timeout
      # (twelfth run, a1 C-002: a REPAIR through a CLI hop waits only its own timeout — _ADV_LOCK_WAIT_CLI — never a dissent hop's bound)
      case "$(_adv_hop_canon "$model")" in *-headless) wait_s="${_ADV_LOCK_WAIT_CLI:-$(_adv_cli_hop_bound "$model")}" ;; *) wait_s="${_ADV_LOCK_WAIT:-${CONF_TIMEOUT:-60}}" ;; esac
      # sixth run, C-003: the directory is ours (0700, not a symlink) or we do not lock on it at all
      # twelfth run, a2 C-006: without flock the serialisation is OFF — said once, never silently (macOS ships none)
      if ! command -v "${_ADV_FLOCK_BIN:-flock}" >/dev/null 2>&1; then
        _adv_run_unlocked "flock is not installed (install util-linux flock, or run one dissent at a time)" "$@"; return $?
      fi
      [[ -d "$lockdir" ]] || mkdir -m 700 "$lockdir" 2>/dev/null || true
      if [[ ! -d "$lockdir" || -L "$lockdir" || ! -O "$lockdir" ]]; then _adv_run_unlocked "the lock directory $lockdir is not ours" "$@"; return $?; fi
      lock="$lockdir/${bin//[^A-Za-z0-9_-]/_}.lock"
      if [[ -L "$lock" || ( -e "$lock" && ! -O "$lock" ) ]]; then _adv_run_unlocked "the lock file $lock is not ours" "$@"; return $?; fi
      (
        # (a brace group: `exec 9>>… 2>/dev/null` would redirect the subshell's stderr for good)
        if ! { exec 9>>"$lock"; } 2>/dev/null; then _adv_run_unlocked "the lock file $lock could not be opened" "$@"; exit $?; fi
        if ! "${_ADV_FLOCK_BIN:-flock}" -w "$wait_s" 9; then
          echo "[adversarial-review] CLI lock for $bin not acquired within ${wait_s}s — hop $model fails as a timeout (rc 124)" >&2
          [[ -n "${_ADV_LOCK_EXPIRED_FILE:-}" ]] && : > "$_ADV_LOCK_EXPIRED_FILE" 2>/dev/null   # (the repair loop: this hop never ran — seventeenth run, a1 C-002)
          exit 124
        fi
        # sixth run, C-002: the hop's clock starts now, not while it queued for the lock
        [[ -n "${_ADV_PHASE_FILE:-}" ]] && _adv_put_state "$_ADV_PHASE_FILE" hop
        "$@" 9>&-   # the child never inherits the lock fd: a lingering helper cannot keep the lock
      )
      ;;
    *) "$@" ;;
  esac
}
_adv_invoke_hop() { local model="$1"; shift; _adv_with_cli_lock "$model" invoke_dissenter "$@"; }

# The model-adapter shim runs cheval with its stderr discarded, so the provider's own failure line
# ("claude -p timed out after 610s") reaches only the MODELINV ledger row cheval writes for the call.
# fourth run, chunk c C-004: what travels into the tracked envelope as last_error is an allowlisted
# summary of the diagnostic — cheval's error tokens, "timed out after Ns", HTTP / exit codes —
# never the provider's raw line (request ids, account ids, echoed headers). The raw line, redacted,
# goes to stderr and stays in the /tmp workdir.
_adv_put_state() {  # <file> <value> — the companion's state files are published whole: a temp file renamed over the target, so a
                    # reader polling once a second never sees the truncated file between open and write (twenty-third run, a3 DISS-C-001)
  # best-effort (twenty-fourth run, a3 DISS-C-001): the walker runs under errexit, so a failed write or rename never ends
  # it — the state file only steers the reaper and the deadline; a failed rename leaves no temp behind
  if ! { printf '%s' "$2" > "$1.tmp" && mv -f -- "$1.tmp" "$1"; } 2>/dev/null; then rm -f -- "$1.tmp" 2>/dev/null; fi
  return 0
}
_adv_error_summary() {  # <redacted diagnostic line> → allowlisted summary (may be empty)
  local line="$1" out=""
  # (nineteenth run, d C-002: the adapter's note on a catalog bound not applied as written travels too — up to the closing paren)
  # (twenty-third run, a3 DISS-C-002: an errno name — E2BIG — and Python's `[Errno N] <words>` travel too; a digit is admitted only
  # in a short E-prefixed token, so a long upper-case key shape never does)
  out=$(printf '%s\n' "$line" | grep -oE '\b[A-Z][A-Z_]{4,}\b|\bE[A-Z0-9]{2,7}\b|\[Errno [0-9]{1,4}\] [A-Za-z ]{1,60}[A-Za-z]|timed out after [0-9]+s|HTTP [0-9]{3}|status [0-9]{3}|exit code [0-9]+|catalog headless_timeout_seconds [^()]{1,100}' \
        | grep -vE '^REDACTED' | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/ *$//' | cut -c1-200) || out=""   # (no token: empty, never a pipefail abort — twentieth run, a2 DISS-001)
  printf '%s' "$out"
}

_companion_ledger_message() {  # <model> <since iso-8601> [until iso-8601] → the last message_redacted for that model in the window, or ""
  local m="$1" since="$2" until="${3:-9999-12-31T23:59:59Z}" ledger="${LOA_MODELINV_LOG_PATH:-$PROJECT_ROOT/.run/model-invoke.jsonl}"
  [[ -s "$ledger" ]] || { echo ""; return 0; }
  # (tenth run, c1 C-005: bounded by the companion's END too — a concurrent dissent's later row is not ours)
  # (twentieth run, a2 DISS-C-002: line by line — a torn append from a concurrent writer is skipped, never the end of the parse;
  # fractional seconds are dropped before the window test — "…:05.123Z" sorts before "…:05Z" as a string)
  tail -n 400 -- "$ledger" 2>/dev/null | jq -R -r --arg m "$m" --arg since "$since" --arg until "$until" '
      fromjson? | ((.ts_utc? // "") | if type == "string" then sub("\\.[0-9]+"; "") else "" end) as $ts
      | select(type == "object" and (.event_type // "") == "model.invoke.complete" and ($ts >= $since) and ($ts <= $until)
             and ((.payload.calling_primitive // "adversarial-review") == "adversarial-review")
             and (((.payload.models_requested // []) | if type == "array" then map(strings | (. == $m or endswith(":" + $m))) | any else false end)))
      | (.payload.models_failed // []) | if type == "array" then .[] else empty end | objects | .message_redacted // empty | strings' 2>/dev/null | tail -1 | cut -c1-300 || true
  # (twenty-first run, a2 DISS-C-002: the row's SHAPE is checked too — a non-string models_requested element or a non-object
  # models_failed element from another writer of the shared ledger is skipped; a jq exit 5 never becomes this function's status)
}

_companion_failure_class() {  # <last status> <last exit code> [diagnostic text] → auth|model_unavailable|quota|timeout|malformed|lock_wait
  local status="$1" rc="$2" diag="${3:-}"
  case "$status" in malformed_response) echo "malformed"; return 0 ;; wait_timeout) echo "timeout"; return 0 ;; lock_wait) echo "lock_wait"; return 0 ;; esac
  case "$rc" in
    4) echo "auth" ;;
    6) echo "quota" ;;
    3|124) echo "timeout" ;;
    5) echo "malformed" ;;
    *)
      # round 1 (live re-run): cheval reports its own CLI-hop timeout ("claude -p timed out after
      # 610s") as PROVIDER_UNAVAILABLE / exit 1 — the diagnostic decides between the two classes
      if printf '%s' "$diag" | grep -qiE 'timed out|timeout'; then echo "timeout"
      elif printf '%s' "$diag" | grep -qiE 'rate.?limit|RATE_LIMITED|429|quota'; then echo "quota"
      else echo "model_unavailable"; fi ;;
  esac
}

_companion_drop_reason() {  # <failure class> → verdict-quality drop-reason enum
  case "$1" in
    quota) echo "RateLimited" ;;
    auth|model_unavailable) echo "ProviderUnavailable" ;;
    malformed) echo "EmptyContent" ;;
    *) echo "Other" ;;
  esac
}

# Walk the companion chain (runs in a background subshell). Writes into
# $workdir: companion.result.json, companion.final, companion.rc,
# companion.status, companion.attempts (one per line), companion.vq (paths of
# the attempts' verdict-quality sidecars).
_walk_companion_chain() {  # <workdir (companion sub-dir)> <prompt_dir> <type> <sprint_id> <timeout> <diff_files> <model>...
  local workdir="$1" prompt_dir="$2" type="$3" sprint_id="$4" timeout="$5" diff_files="$6"; shift 6
  local m raw rc res status final="" last_status="" last_rc=0
  mkdir -p "$workdir"
  : > "$workdir/companion.attempts"; : > "$workdir/companion.vq"
  export _ADV_SIDECAR_TAG="companion"
  for m in "$@"; do
    rc=0
    local vq="$workdir/vq-companion-${m//[^A-Za-z0-9_-]/_}-$$-$RANDOM.json"
    _adv_put_state "$workdir/companion.current" "$m"   # the hop in flight (sixth run, C-001: the reap path names it)
    # main's deadline follows the phase (fifth run, C-001): `queue` while waiting for the CLI lock, `hop`
    # once it is held (the lock helper writes it), `post` after the model answered
    # (nineteenth run, a2 C-001: an HTTP hop whose catalog chain reaches a CLI binary takes that binary's lock BEFORE its
    # request — it queues too, so main's deadline charges the lock wait to the queue, never to the hop)
    if [[ -n "$(_adv_cli_bin_for "$m")" ]]; then _adv_put_state "$workdir/companion.phase" queue; else _adv_put_state "$workdir/companion.phase" hop; fi
    date -u +%Y-%m-%dT%H:%M:%SZ > "$workdir/companion.hop_started_iso" 2>/dev/null || true   # (the MODELINV lookup window is this hop, not the companion's lifetime — sixteenth run, a3 C-004)
    command rm -f -- "$workdir/companion.lockwait" "$workdir/companion.hop_ended_iso" 2>/dev/null   # (twenty-first run, a3 DISS-C-001: a hop starts with no end time — the previous hop's would invert the fold's MODELINV window and hide a mid-hop reap)
    raw=$(_ADV_PHASE_FILE="$workdir/companion.phase" _ADV_LOCK_EXPIRED_FILE="$workdir/companion.lockwait" _adv_invoke_hop "$m" "$prompt_dir/system-prompt.txt" "$prompt_dir/user-prompt.txt" "$m" "$timeout" "$vq" "$type" "$SCRIPT_DIR/../schemas/wire/dissent-${type}.wire.json") || rc=$?
    date -u +%Y-%m-%dT%H:%M:%SZ > "$workdir/companion.hop_ended_iso" 2>/dev/null || true
    [[ -s "$vq" ]] && echo "$vq" >> "$workdir/companion.vq"
    _adv_put_state "$workdir/companion.phase" post   # the model answered: validation and repair round-trips get their own budget
    # twentieth run, a2 DISS-C-001: the walker runs as a background job, where errexit is live — a failing post-hop helper is
    # an unusable answer for this hop, never the end of the walk with no record
    res=$(process_findings "$raw" "$type" "$m" "$sprint_id" "$rc" "$diff_files") || res=""
    status=""; [[ -n "$res" ]] && { status=$(_extract_result_status "$res") || status=""; }
    [[ -n "$status" ]] || status="malformed_response"
    # twentieth run, a2 DISS-C-003: a hop whose CLI lock was never acquired never sent its request — its own class, not a timeout
    # (twenty-first run, a3 DISS-C-005: decided BEFORE the attempts row, so the row and the failure class agree, on every hop)
    local row_status="$status"
    if [[ -e "$workdir/companion.lockwait" ]]; then
      [[ "$status" == "malformed_response" || "$status" == "api_failure" ]] && row_status="lock_wait"
      command rm -f -- "$workdir/companion.lockwait" 2>/dev/null
    fi
    echo "${m}:${row_status}" >> "$workdir/companion.attempts"
    last_status="$row_status"; last_rc="$rc"
    if [[ "$status" != "malformed_response" && "$status" != "api_failure" ]]; then
      final="$m"
      printf '%s' "$res" > "$workdir/companion.result.json"
      break
    fi
  done
  printf '%s' "${final:-${m:-}}" > "$workdir/companion.final"
  printf '%s' "$last_rc" > "$workdir/companion.rc"
  printf '%s' "$last_status" > "$workdir/companion.status"
  _adv_put_state "$workdir/companion.phase" done
  [[ -n "$final" ]]
}

# The companion's post-hop budget: every repair round-trip may cost a CLI hop's bound (the repair's
# --timeout never reaches the adapter either), ADV_REPAIR_MAX_PER_RUN times, plus slack.
_companion_post_budget() {  # <primary model> <timeout_seconds> → seconds
  local t="$2" h b sum=0
  for h in $(_repair_model_chain "$1"); do
    b=$(_adv_hop_charge "$h" "$t")   # (a2 C-002; nineteenth run, a2 C-001: the lock wait too; twentieth run, a3 DISS-C-003: validated)
    sum=$(( sum + b ))
  done
  echo $(( sum * $(_adv_num_or "${ADV_REPAIR_MAX_PER_RUN:-5}" 5) + 60 ))
}
_adv_vq_dropped_matching() {  # <envelope> <space-separated ids> → the envelope's dropped voices (as recorded, one per line) that
                              # canonicalise to one of the ids; status 1 when none (twentieth run, a3 DISS-C-005: the pre-check
                              # and the rewrite share it)
  local _i _v _cids=" " _out=""
  for _i in $2; do _cids+="$(_adv_hop_canon "$_i") "; done
  while IFS= read -r _v; do
    [[ -n "$_v" && "$_cids" == *" $(_adv_hop_canon "$_v") "* ]] && _out+="${_out:+$'\n'}$_v"
  done < <(jq -r '(.voices_dropped // [])[]? | .voice? // empty | strings' "$1" 2>/dev/null)
  [[ -n "$_out" ]] || return 1
  printf '%s' "$_out"
}
_adv_inv5_rewrite() {  # <envelope> <space-separated ids> <out> — the envelope without the dropped entries naming those ids,
                       # voices_planned decremented by as many (INV-6: dropped == planned − succeeded holds); 1 when unusable
  # twentieth run, a3 DISS-C-005: canonical names on both sides — the dropped voices that canonicalise to one of the ids are
  # resolved here and matched byte for byte below
  local _drop; _drop=$(_adv_vq_dropped_matching "$1" "$2") || _drop=""
  jq --arg ids "$_drop" '(($ids | split("\n")) as $c | (.voices_dropped // []) as $d
      | ($d | map(select(.voice as $v | ($c | index($v)) != null)) | length) as $gone
      | .voices_dropped = ($d | map(select(.voice as $v | ($c | index($v)) == null)))
      | .voices_planned = (((.voices_planned // 0) - $gone) | if . < 0 then 0 else . end)
      | .single_voice_call = (.voices_planned == 1))' "$1" > "$3" 2>/dev/null && [[ -s "$3" ]] && jq -e 'type == "object"' "$3" >/dev/null 2>&1   # (the aggregator's invariant: a one-voice envelope says so)
}
_adv_mtime() { [[ -e "$1" ]] || { echo 0; return 0; }; stat -c %Y -- "$1" 2>/dev/null || stat -f %m -- "$1" 2>/dev/null || date +%s; }   # (0 for a missing path — thirteenth run, a2 C-005)
_adv_companion_alive() {  # → 0 while the companion's pid is alive AND still the process forked at the launch (sixteenth run, a1 C-003:
                          # one liveness rule — the reaper's — for the repair skip and the shared-hop verdict too)
  # (twenty-first run, a3 DISS-C-003: _adv_pid_alive, not kill -0 — a walker that died un-waited is a zombie, which kill -0 answers
  # for; the shared-hop wait would sleep on it until its phase budget ran out)
  [[ -n "${_ADV_COMPANION_PID:-}" ]] && _adv_pid_alive "$_ADV_COMPANION_PID" || return 1
  # (a4 C-001: a token that could not be read — at the fork or now — falls back to the pid alone: treating it as dead would let
  # main skip its deadline loop and block in `wait` on a hung child, the sixth run's eight-hour hang)
  local _now; _now=$(_adv_proc_start "$_ADV_COMPANION_PID" 2>/dev/null) || _now=""
  [[ -z "${_ADV_COMPANION_START:-}" || -z "$_now" || "$_now" == "$_ADV_COMPANION_START" ]]
}
_adv_num_or() { if [[ "${1:-}" =~ ^[0-9]+$ ]]; then echo "$1"; else echo "$2"; fi; }   # a whole number, or the fallback (twelfth run, a3 C-003)
_ADV_QB_HOP=""; _ADV_QB_VAL=0   # the queue phase's lock bound, computed once per hop (eighth run, a2 C-003: not three yq calls a second)
_companion_deadline_why() {  # <workdir> <started> <wait cap> <post budget> <queue allowance> → the reason once the companion's deadline has
                             # passed, "" while it has not. ONE model for the primary's shared-hop wait and main's post-walk wait
                             # (eighteenth run, a4 C-002): a phase-relative budget — queue: the CLI lock's own bound; hop: the wait cap;
                             # post / done: the post budget (a model that answered is never reaped mid-processing, fifth run C-001) —
                             # under a global ceiling from the fork (twelfth run, a3 C-002). Every operand is a validated whole number
                             # (a3 C-003: a vanished phase file or a yq hiccup never aborts main or reaps a healthy companion).
  # nineteenth run, a3 C-001: with a sixth argument the verdict is written INTO that variable (printf -v) — both callers run
  # the helper in their own shell, so the queue-bound cache below holds (one yq per hop, not one a second)
  local wd="$1" started="$2" cap="$3" post="$4" qallow="$5" outvar="${6:-}" phase pstart budget cur now _dl_why=""   # (its own name: a caller passing `_why` must not be shadowed)
  now=$(date +%s)
  phase=$(cat "$wd/companion.phase" 2>/dev/null || echo hop)
  if [[ -f "$wd/companion.phase" ]]; then pstart=$(_adv_num_or "$(_adv_mtime "$wd/companion.phase")" "$started"); else pstart=$started; fi
  (( pstart < started )) && pstart=$started
  case "$phase" in
    post|done) budget=$post ;;
    queue)
      cur=$(cat "$wd/companion.current" 2>/dev/null || echo x-headless)
      [[ -n "$cur" ]] || cur=x-headless   # (twenty-fifth run, a3 C-002: an empty file is the missing one's fallback bound — never the cache's initial key and a 0 s budget)
      if [[ "$cur" != "$_ADV_QB_HOP" ]]; then _ADV_QB_HOP="$cur"; _ADV_QB_VAL=$(( $(_adv_num_or "$(_adv_cli_hop_bound "$cur")" 610) + 30 )); fi
      budget=$_ADV_QB_VAL ;;
    *) budget=$cap ;;
  esac
  if (( now - pstart >= budget )); then _dl_why="phase '$phase' deadline: ${budget}s from the phase start"
  elif (( now >= started + cap + qallow + post )); then _dl_why="global ceiling: $(( cap + qallow + post ))s from the fork"; fi
  if [[ -n "$outvar" ]]; then printf -v "$outvar" '%s' "$_dl_why"; else printf '%s' "$_dl_why"; fi
  return 0
}
_adv_shared_hop_verdict() {  # <hop> <companion workdir> <companion start epoch> <wait cap> [post budget] [queue allowance] → "<skip|run>\t<token>\t<prose>"
  # twelfth run, a3 C-001 / thirteenth run, a2 C-003: a shared hop is never ceded on sight. The primary waits for the
  # companion to settle (bounded by the wait cap) and skips the hop only when the companion ANSWERED with it — a companion
  # that failed it, or never reached it, leaves the primary's last resort to the primary. Past the cap, a companion still
  # ON the hop (queue / hop) is reaped by the caller and the primary runs the hop (`run`, token past_wait_cap); a companion that
  # already answered and is finishing (phase post / done, or a result on disk) is left to the post budget (fifteenth run,
  # a4 C-002). The decision travels as a stable token, the prose only for the log (a4 C-003; a3 C-006: a captured helper
  # cannot set a global).
  local hop wd="$2" started="$3" cap="$4" post="${5:-60}" qallow="${6:-0}" fin phase cur hop_re why
  hop=$(_adv_hop_canon "$1")
  while _adv_companion_alive; do
    phase=$(cat "$wd/companion.phase" 2>/dev/null || true)
    case "$phase" in
      done) break ;;   # settled: decided below from the record it left
      post)
        # eighteenth run, a3 DISS-001 / C-001 / C-002: a companion in `post` has an answer from `companion.current` that is
        # still being validated / repaired — it may yet fail that hop and walk on, and the post-budget reaper may remove
        # its result — so it is NEVER ceded to here. On another hop the shared hop is free: the primary runs it at once and
        # the companion is left to the post budget; on OUR hop the primary waits for the settled record, bounded by the
        # same deadline main applies (past it the caller reaps and runs)
        cur=$(cat "$wd/companion.current" 2>/dev/null || true)
        # (twentieth run, a3 DISS-C-002: the hop's answer may have come from the shared hop under another outer hop — the
        # answering id of the last vq sidecar counts too, as below the loop)
        local _pvq="" _paid=""
        [[ -s "$wd/companion.vq" ]] && _pvq=$(tail -1 "$wd/companion.vq" 2>/dev/null || true)
        [[ -n "$_pvq" && -s "$_pvq" ]] && _paid=$(jq -r '(.voices_succeeded_ids // []) | if length > 0 then .[-1] else empty end' "$_pvq" 2>/dev/null || true)
        # (twenty-third run, a3 DISS-C-001: an unreadable hop name is not "another hop" — it is waited for, under the same deadline)
        if [[ -n "$cur" && "$(_adv_hop_canon "$cur")" != "$hop" && ( -z "$_paid" || "$(_adv_hop_canon "$_paid")" != "$hop" ) ]]; then printf 'run\tcompanion_on_other_hop\tis finishing on another hop (the post budget governs it)'; return 0; fi
        _companion_deadline_why "$wd" "$started" "$cap" "$post" "$qallow" why
        if [[ -n "$why" ]]; then printf 'run\tpost_budget_expired\tis still finishing on it past its deadline (%s)' "$why"; return 0; fi
        sleep 1; continue ;;
    esac
    # queue / hop: the one deadline model (a4 C-002) — a companion queued behind another claude holder keeps its lock bound
    _companion_deadline_why "$wd" "$started" "$cap" "$post" "$qallow" why
    if [[ -n "$why" ]]; then printf 'run\tpast_wait_cap\tis still running past its deadline (%s)' "$why"; return 0; fi   # (the caller reaps it, then the primary runs the hop)
    sleep 1
  done
  fin=$(cat "$wd/companion.final" 2>/dev/null || true)
  # nineteenth run, a3 C-004: cheval's inner chain may have answered from the shared hop under another outer hop — the answering
  # id is the last vq sidecar's succeeded id, as the fold reads it; the outer hop is only the fallback
  local _lastvq="" _aid=""
  [[ -s "$wd/companion.vq" ]] && _lastvq=$(tail -1 "$wd/companion.vq" 2>/dev/null || true)
  [[ -n "$_lastvq" && -s "$_lastvq" ]] && _aid=$(jq -r '(.voices_succeeded_ids // []) | if length > 0 then .[-1] else empty end' "$_lastvq" 2>/dev/null || true)
  [[ -n "$_aid" ]] || _aid="$fin"
  # answered WITH it: a non-empty, valid result and the answering hop is this one (a3 C-001: a result on disk alone is not an answer)
  if [[ -s "$wd/companion.result.json" && "$(_adv_hop_canon "$_aid")" == "$hop" ]] && jq empty "$wd/companion.result.json" >/dev/null 2>&1; then printf 'skip\tanswered_with_it\tanswered with it'; return 0; fi
  # (a3 C-005: ERE with the hop escaped — GNU BRE `\|` is a literal to ugrep, and a dot in gpt-5.5 is a dot)
  hop_re=$(printf '%s' "$hop" | sed 's/[][\.*^$+?(){}|\\]/\\&/g')
  if grep -Eq "^([a-z]+:)?${hop_re}:" "$wd/companion.attempts" 2>/dev/null; then printf 'run\tfailed_it\tfailed it'; return 0; fi
  printf 'run\tfinished_without_it\tfinished without it'
}

# Fold the finished companion into the primary result: findings (re-numbered
# DISS-C-NNN, tagged with their voice), rejected_summary, verdict-quality
# inputs (a synthetic FAILED single-voice envelope when the companion did not
# complete), and metadata.companion_voice.
_fold_companion() {  # <result json> <companion workdir> <family> <chain csv> <primary final model> [primary succeeded id] [shared hops csv] [primary succeeded ids csv] → result json
  local result="$1" workdir="$2" family="$3" chain="$4" primary_final="$5" shared_hops="${7:-}" primary_ids="${8:-}" ceded="${9:-}"
  # an EMPTY sixth argument means "the primary never answered" (fifth run, C-003) — only an absent one defaults to the outer hop
  local primary_succeeded; if (( $# >= 6 )); then primary_succeeded="$6"; else primary_succeeded="$5"; fi
  local final status rc cls="" comp_status="failed" cost_cents="null" attempts_json="[]" last_error="" sidecar="null"
  final=$(cat "$workdir/companion.final" 2>/dev/null || true)
  # third run, C-002: the companion's own succeeded id (cheval's inner chain may have answered from
  # another model) — its last sidecar's voices_succeeded_ids, else the outer hop
  local companion_answered="$final" _lastvq=""
  [[ -s "$workdir/companion.vq" ]] && _lastvq=$(tail -1 "$workdir/companion.vq")
  if [[ -n "$_lastvq" && -s "$_lastvq" ]]; then
    local _cid
    _cid=$(jq -r '(.voices_succeeded_ids // []) | if length > 0 then .[-1] else empty end' "$_lastvq" 2>/dev/null || true)
    [[ -n "$_cid" ]] && companion_answered="$_cid"
  fi
  status=$(cat "$workdir/companion.status" 2>/dev/null || true)
  rc=$(cat "$workdir/companion.rc" 2>/dev/null || echo 1)
  [[ "$rc" =~ ^[0-9]+$ ]] || rc=1
  [[ -s "$workdir/companion.attempts" ]] && attempts_json=$(jq -R . < "$workdir/companion.attempts" | jq -s .)
  rm -f "$workdir/vq-companion-synthetic.json" "$workdir/companion.duplicate"
  if [[ -s "$workdir/companion.result.json" ]] && jq empty < "$workdir/companion.result.json" 2>/dev/null; then
    comp_status="succeeded"
    local cres; cres=$(cat "$workdir/companion.result.json")
    cost_cents=$(echo "$cres" | jq -r '((.metadata.cost_usd // 0) * 10000 | round) / 100')
    # review sprint-248 C-010 (round 1b): the companion's own sidecar is named only when a payload
    # landed in it; an empty one is removed so the a2a directory carries no vacuous file
    sidecar=$(echo "$cres" | jq -c 'if (.metadata.rejected_count // 0) > 0 then (.metadata.rejected_sidecar // null) else null end')
    if [[ "$sidecar" == "null" ]]; then
      local _sc_rel _sc_abs
      _sc_rel=$(echo "$cres" | jq -r '.metadata.rejected_sidecar // empty')
      if [[ -n "$_sc_rel" ]]; then
        [[ "$_sc_rel" == /* ]] && _sc_abs="$_sc_rel" || _sc_abs="$PROJECT_ROOT/$_sc_rel"
        [[ -f "$_sc_abs" && ! -s "$_sc_abs" ]] && command rm -f -- "$_sc_abs"
        # (twelfth run, a2 C-004: a file that holds rows is named whatever the last hop counted — belt and braces)
        [[ -s "$_sc_abs" ]] && sidecar=$(jq -cn --arg p "$_sc_rel" '$p')
      fi
    fi
    # review sprint-248 C-004 (spend summed into the envelope, per-voice kept under companion_voice),
    # C-006 (a primary chain that exhausted does not bury the companion's completed voice:
    # the envelope is promoted to reviewed + degraded and the primary is recorded as failed).
    # chunk c C-003 (round 2): `voice` is the outer hop (it matches final_model / model_attempts);
    # `answered_by` is the model that actually produced the finding (cheval's inner chain may differ)
    # (fifteenth run, a3 C-006: both envelopes travel as FILES — an argv string is capped at 128 KiB on Linux, which a
    # large primary envelope exceeds; a3 C-005: the ceded comparison is canonical, like the skip that produced it; twentieth run,
    # a3 DISS-C-001: and made on the ANSWERING id, the one the shared-hop verdict skipped on — not the outer hop)
    printf '%s' "$result" > "$workdir/fold-primary.json"; printf '%s' "$cres" > "$workdir/fold-companion.json"
    result=$(jq -n --slurpfile pf "$workdir/fold-primary.json" --slurpfile cf "$workdir/fold-companion.json" --arg pv "$primary_final" --arg cv "$final" --arg pa "$primary_succeeded" --arg ca "$companion_answered" --arg ceded "$ceded" --arg cvc "$(_adv_hop_canon "$companion_answered")" --arg cededc "$(_adv_hop_canon "$ceded")" '
      $pf[0] as $p | $cf[0] as $c |
      ($c.findings // [] | to_entries | map(.value + {id: ("DISS-C-" + ((.key + 1) | tostring | if length < 3 then ("000" + .)[-3:] else . end)), voice: $cv, answered_by: $ca})) as $cf
      | (($p.metadata.status // "") | IN("api_failure", "malformed_response")) as $primary_failed
      | $p
      | .findings = (($p.findings // []) | map(. + {voice: $pv, answered_by: $pa})) + $cf
      | .metadata.rejected_summary = (($p.metadata.rejected_summary // []) + (($c.metadata.rejected_summary // []) | map(. + {voice: $cv})))
      | .metadata.rejected_count = (($p.metadata.rejected_count // 0) + ($c.metadata.rejected_count // 0))
      | .metadata.cost_usd = (($p.metadata.cost_usd // 0) + ($c.metadata.cost_usd // 0))
      | .metadata.tokens_input = (($p.metadata.tokens_input // 0) + ($c.metadata.tokens_input // 0))
      | .metadata.tokens_output = (($p.metadata.tokens_output // 0) + ($c.metadata.tokens_output // 0))
      | if $primary_failed and $ceded != "" and $cvc == $cededc then
          # thirteenth run, a2 C-004: the primary CEDED its last hop to a companion that answered with it — the one voice
          # this run would have had without a companion; not a degraded "chain exhausted"
          .metadata.primary_voice = {status: "ceded", hop: $ceded, model: ($p.metadata.model // $pv)}
          | .metadata.status = "reviewed" | .metadata.degraded = false
          | .metadata.status_note = ("primary ceded " + $ceded + " to the companion, which answered with it; findings are the companion voice\u0027s alone")
        elif $primary_failed then
          .metadata.primary_voice = {status: "failed", model: ($p.metadata.model // $pv), error: ($p.metadata.error // $p.metadata.status)}
          | .metadata.status = "reviewed" | .metadata.degraded = true
          | .metadata.status_note = "primary chain exhausted; findings are the companion voice\u0027s alone"
        else . end')
  else
    # review sprint-248 C-003: the last diagnostic line of the companion's log travels with the class —
    # the provider's own message when there is one, the model-adapter shim's generic wrapper
    # ("ERROR: model-invoke failed with exit code N") only as the fallback
    local _diag="" _since
    # 1) the provider's own line from the MODELINV row cheval wrote for this call (the shim discards stderr)
    # the window is the companion's LAST HOP when the walker recorded one (sixteenth run, a3 C-004: a primary repair on the
    # same model during the companion's post phase is not this voice's row); the companion's lifetime otherwise
    _since=$(cat "$workdir/companion.hop_started_iso" 2>/dev/null || cat "$workdir/companion.started_iso" 2>/dev/null || echo "1970-01-01T00:00:00Z")
    local _until; _until=$(cat "$workdir/companion.hop_ended_iso" 2>/dev/null || cat "$workdir/companion.ended_iso" 2>/dev/null || echo "9999-12-31T23:59:59Z")
    [[ -s "$workdir/companion.hop_started_iso" && ! -s "$workdir/companion.hop_ended_iso" ]] && _until=$(cat "$workdir/companion.ended_iso" 2>/dev/null || echo "9999-12-31T23:59:59Z")   # (reaped mid-hop: until the reap)
    if [[ -n "$final" ]]; then _diag=$(_companion_ledger_message "$final" "$_since" "$_until") || _diag=""; fi
    # 2) else the last line of the companion's log that is not a shim banner or the generic wrapper
    if [[ -z "$_diag" && -s "$workdir/companion.log" ]]; then
      _diag=$(grep -v '^[[:space:]]*$' "$workdir/companion.log" | grep -Ev 'model-invoke failed with exit code|^\[model-adapter:shim\]' | tail -1 | cut -c1-300) || _diag=""   # -E: ugrep reads \| as a literal; `|| _diag=""`: a log of shim lines alone must not abort (sixteenth run, a3 C-003)
      [[ -n "$_diag" ]] || _diag=$(grep -v '^[[:space:]]*$' "$workdir/companion.log" | tail -1 | cut -c1-300) || _diag=""
    fi
    cls=$(_companion_failure_class "$status" "$rc" "$_diag")
    local synth="$workdir/vq-companion-synthetic.json"
    # third run, C-001 (BLOCKING): a failed companion whose id is one of the primary's succeeded voices
    # (this host: a primary that fell through to claude-headless, a claude-headless companion that timed
    # out) must not become a dropped-voice envelope — INV-5 would fail the whole aggregation
    local _dup="false" _pid_
    # (provider-prefix-free on both sides — twelfth run, a2 C-005)
    for _pid_ in ${primary_ids//,/ } "$primary_succeeded"; do [[ -n "$_pid_" && "$(_adv_hop_canon "$_pid_")" == "$(_adv_hop_canon "$final")" ]] && _dup="true"; done   # (canonical — sixteenth run, a3 C-005)
    if [[ "$_dup" == "true" ]]; then
      : > "$workdir/companion.duplicate"
      log "Companion voice: failed as $final, which is also a primary voice that answered — no dropped-voice envelope (INV-5); counted_as duplicate_voice"
    else
      jq -nc --arg v "${final:-companion}" --arg r "$(_companion_drop_reason "$cls")" --argjson e "$(( rc <= 255 ? rc : 1 ))"       '{status: "FAILED", consensus_outcome: "consensus", truncation_waiver_applied: false, voices_planned: 1, voices_succeeded: 0,
          voices_succeeded_ids: [], voices_dropped: [{voice: $v, reason: $r, exit_code: $e, blocker_risk: "unknown"}],
          chain_health: "exhausted", confidence_floor: "low", rationale: "companion chain did not complete", single_voice_call: true}' > "$synth"
    fi
    result=$(echo "$result" | jq --arg pv "$primary_final" --arg pa "$primary_succeeded" '.findings = ((.findings // []) | map(. + {voice: $pv, answered_by: $pa}))')
    if [[ -n "$_diag" ]]; then
      last_error="$_diag"
      # twenty-first run, a3 DISS-C-004: the fold runs under errexit and pipefail — a redactor that fails withholds the line (never
      # the raw text), and `sed -n 1p` reads to the end, so a redactor writing many lines takes no SIGPIPE
      local _redactor="${_ADV_REDACTOR_BIN:-$PROJECT_ROOT/.claude/scripts/lib/log-redactor.sh}"
      if [[ -x "$_redactor" ]]; then
        last_error=$(printf '%s\n' "$last_error" | "$_redactor" 2>/dev/null | sed -n 1p) || last_error="[diagnostic withheld: the redactor failed]"
      fi
      # provider API-key shapes the shared redactor (URL / AKIA / Bearer / PEM) does not cover:
      # sk-… (Anthropic, OpenAI), xai-…, gsk_… and AIza… — masked whole, boundary-anchored
      last_error=$(printf '%s\n' "$last_error" | sed -E 's/(^|[^A-Za-z0-9])(sk|xai|gsk)[-_][A-Za-z0-9_-]{12,}/\1[REDACTED-KEY]/g; s/AIza[0-9A-Za-z_-]{20,}/[REDACTED-KEY]/g' | sed -n 1p) \
        || last_error="[diagnostic withheld: the redactor failed]"
      # the redacted raw line is operator-facing (stderr); the envelope gets the allowlisted summary
      log "Companion voice diagnostic ($final): $last_error"
      last_error=$(_adv_error_summary "$last_error")
    fi
  fi
  # review sprint-248 C-005 / chunk c C-003: independence is a fact about the voices that actually
  # answered — the primary's succeeded id (cheval's inner chain may have landed on another family),
  # not its configured hop
  local indep="null" counted_as="null"
  [[ "$comp_status" == "failed" && -e "$workdir/companion.duplicate" ]] && counted_as='"duplicate_voice"'
  if [[ "$comp_status" == "succeeded" && -n "$companion_answered" && -n "$primary_succeeded" ]]; then   # (nineteenth run, a3 C-006: a failed companion has no independence to judge)
    if [[ "$(_adv_family_of "$companion_answered")" != "$(_adv_family_of "$primary_succeeded")" ]]; then indep="true"; else indep="false"; fi
    if [[ "$comp_status" == "succeeded" ]]; then
      if [[ "$indep" == "true" ]]; then
        counted_as='"independent_voice"'
      else
        # one model (or one family) answered twice: keep the companion's findings, tagged, but let it
        # contribute NO envelope to verdict quality — the aggregator counts distinct voices (its INV-5
        # forbids one id both succeeded and dropped), and one family is never cross-family consensus
        counted_as='"duplicate_voice"'
        log "Companion voice: NOT independent — the primary answered as $primary_succeeded and the companion as $companion_answered (same family); the companion is not counted as a second voice in verdict quality"
        : > "$workdir/companion.duplicate"
      fi
    fi
  elif [[ "$comp_status" == "succeeded" && -n "$companion_answered" ]]; then
    counted_as='"sole_voice"'   # the primary never answered: the companion is the run's only voice
  fi
  echo "$result" | jq --arg fam "$family" --arg chain "$chain" --arg model "$final" --arg st "$comp_status" \
      --arg cls "$cls" --argjson cost "$cost_cents" --argjson att "$attempts_json" --arg le "$last_error" \
      --argjson sc "$sidecar" --argjson indep "$indep" --arg psm "$primary_succeeded" --argjson ca "$counted_as" --arg sh "$shared_hops" --arg ab "$companion_answered" \
      '.metadata.companion_voice = {planned: true, family: $fam, family_basis: "configured_primary",
        chain: ($chain | split(",")), shared_hops: (if $sh == "" then [] else ($sh | split(",")) end),
        model: (if $model == "" then null else $model end), answered_by: (if $ab == "" or $st != "succeeded" then null else $ab end), status: $st,
        failure_class: (if $cls == "" then null else $cls end), cost_cents: $cost, attempts: $att,
        independent: $indep, counted_as: $ca, primary_succeeded_model: (if $psm == "" then null else $psm end), rejected_sidecar: $sc}
       + (if $le == "" then {} else {last_error: $le} end)'
}

# review sprint-248 C-001: the second voice is never orphaned — reaped on INT/TERM/EXIT and by
# a wait cap (chain length × per-call timeout + slack; LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS pins it).
_ADV_COMPANION_PID=""
_adv_tree_pids() {  # <pid> → the process and every descendant, one per line (collected BEFORE any signal:
                    # once the parent dies its children are re-parented and pgrep -P can no longer find them)
  local p="$1" c
  echo "$p"
  if command -v "${_ADV_PGREP_BIN:-pgrep}" >/dev/null 2>&1; then
    for c in $("${_ADV_PGREP_BIN:-pgrep}" -P "$p" 2>/dev/null); do _adv_tree_pids "$c"; done
  else
    # fifteenth run, a3 C-004: without pgrep the children come from ps — an orphaned claude -p would otherwise keep the
    # per-binary lock for its lifetime after a reap
    for c in $(ps -eo pid=,ppid= 2>/dev/null | awk -v pp="$p" '$2 == pp { print $1 }'); do _adv_tree_pids "$c"; done
  fi
}
_adv_kill_tree() {  # <pid> [signal] [tokens] — signal a process and every descendant (all frozen first so none escapes); prints the
                    # pids — or, with `tokens`, pid=token pairs taken while the whole tree is frozen (twenty-second run, a4 DISS-C-002:
                    # a pid tokenised after TERM may already be free, and another process's token then licensed its KILL)
  # sixteenth run, a3 C-006: the tree is collected again after STOP — a descendant forked between the first collection and
  # the freeze (cheval exec'ing claude -p at that instant) is signalled too, never left holding the per-binary lock
  local p="$1" sig="${2:-TERM}" pids x more toks=""
  pids=$(_adv_tree_pids "$p")
  for x in $pids; do kill -STOP "$x" 2>/dev/null || true; done
  more=$(_adv_tree_pids "$p"); pids=$(printf '%s\n%s\n' "$pids" "$more" | grep -v '^$' | sort -un)
  for x in $pids; do kill -STOP "$x" 2>/dev/null || true; done
  [[ "${3:-}" == "tokens" ]] && { toks=$(_adv_pid_tokens "$pids" 2>/dev/null) || toks=""; }
  for x in $pids; do kill "-$sig" "$x" 2>/dev/null || true; done
  for x in $pids; do kill -CONT "$x" 2>/dev/null || true; done
  if [[ "${3:-}" == "tokens" ]]; then
    for x in $pids; do [[ " $toks" == *" $x="* ]] || toks+="$x= "; done   # (a pid the token pass missed: the pid alone decides)
    printf '%s\n' $toks
  else
    printf '%s\n' $pids
  fi
}
_adv_pid_alive() {  # <pid> → 0 when the process exists and is not a zombie
  kill -0 "$1" 2>/dev/null || return 1
  [[ "$(ps -o stat= -p "$1" 2>/dev/null)" != Z* ]]
}
_adv_pid_tokens() {  # <pids> → "pid=token …": the token "" when unreadable (the pid alone then decides), "-" for a pid already gone
  local x t; for x in $1; do if _adv_pid_alive "$x"; then t=$(_adv_proc_start "$x" 2>/dev/null) || t=""; t=$(_adv_tok_word "$t"); else t="-"; fi; printf '%s=%s ' "$x" "$t"; done
}
_adv_kill_same() {  # <pid> <pid=token map> — KILL the pid only while it is still the process collected (twentieth run, a3 DISS-C-004:
                    # a descendant that exited on TERM frees its pid, and another process may take it within the grace)
  _adv_is_same "$1" "${2:-}" || return 0
  kill -KILL "$1" 2>/dev/null || true
}
_adv_is_same() {  # <pid> <pid=token map> → 0 while the pid is alive and still the process collected (a recorded "-": gone)
  local p="$1" e t="" now
  for e in ${2:-}; do [[ "${e%%=*}" == "$p" ]] && { t="${e#*=}"; break; }; done
  [[ "$t" == "-" ]] && return 1
  _adv_pid_alive "$p" || return 1
  if [[ -n "$t" ]]; then now=$(_adv_proc_start "$p" 2>/dev/null) || now=""; now=$(_adv_tok_word "$now"); [[ -z "$now" || "$now" == "$t" ]] || return 1; fi
  return 0
}
_ADV_REAP_TREE_TOKENS=""
_adv_reap_companion() {
  [[ -n "${_ADV_COMPANION_PID:-}" ]] || return 0
  # eighteenth run, a3 C-004: re-entered from the EXIT trap while a reap was under way — finish the kill of the tree already
  # collected instead of returning on a blank pid (the pid is cleared only once the tree has been signalled)
  if [[ "${_ADV_REAP_IN_PROGRESS:-false}" == "true" ]]; then
    # (twenty-third run, a4 DISS-C-002: before the tree is published the list holds the bare root — each pid still the process
    # collected takes its CURRENT tree with it, so a root KILLed in that window leaves no re-parented cheval / claude -p behind)
    local _x; for _x in ${_ADV_REAP_TREE_PIDS:-}; do
      if _adv_is_same "$_x" "${_ADV_REAP_TREE_TOKENS:-}"; then _adv_kill_tree "$_x" KILL >/dev/null 2>&1 || true; fi
    done
    _ADV_COMPANION_PID=""; _ADV_REAP_IN_PROGRESS="false"; return 0
  fi
  # (twenty-first run, a3 DISS-C-006: the bare pid and its fork-time token are published BEFORE the slow probes — a trap that
  # re-enters while they run KILLs the companion if it is still the process forked, instead of finding an empty tree)
  _ADV_REAP_TREE_PIDS="$_ADV_COMPANION_PID"; _ADV_REAP_TREE_TOKENS="$_ADV_COMPANION_PID=$(_adv_tok_word "${_ADV_COMPANION_START:-}") "
  _ADV_REAP_IN_PROGRESS="true"
  _adv_reap_companion_inner "$_ADV_COMPANION_PID" || true
  _ADV_COMPANION_PID=""; _ADV_REAP_IN_PROGRESS="false"
  return 0
}
_adv_reap_companion_inner() {  # <pid> — the reap itself; every helper is guarded (a3 C-004: the last-resort path never aborts)
  # round 1b: the hop's own children (a cheval process, a CLI, a sleep) were surviving a
  # parent-only kill — the whole tree goes. Sixth run: a CLI that ignores TERM (a claude -p stuck
  # under the account's usage limit held main for ~8 h) gets KILL after a grace period.
  local _pid="$1" _grace _i _pids _x _alive _now_start _fresh
  _grace=$(_conf_uint "LOA_ADVERSARIAL_REAP_GRACE_SECONDS" "${LOA_ADVERSARIAL_REAP_GRACE_SECONDS:-5}" 5 0) || _grace=5   # (sixteenth run, a3 C-002)
  _ADV_REAPED_LIVE_TREE="false"
  # a3 C-003: a zombie (exited, not yet collected) is not a live tree — signalling it would overwrite the walker's own record
  _adv_pid_alive "$_pid" || return 0
  # fifteenth run, a3 C-003: a pid recycled by another process is not the companion — the start token recorded at
  # the fork must still match before anything is signalled
  _now_start=$(_adv_proc_start "$_pid" 2>/dev/null) || _now_start=""
  if [[ -n "${_ADV_COMPANION_START:-}" && -n "$_now_start" && "$_now_start" != "$_ADV_COMPANION_START" ]]; then
    log "Companion voice: pid $_pid now belongs to another process (start token changed) — nothing to reap"
    return 0
  fi
  # nineteenth run, a3 C-002: the tree is published BEFORE it is frozen — an INT that cuts the freeze short re-enters the reaper
  # from the trap, and KILL reaches a stopped process
  _ADV_REAP_TREE_PIDS=$(_adv_tree_pids "$_pid" 2>/dev/null | tr '\n' ' ') || _ADV_REAP_TREE_PIDS="$_pid"
  _ADV_REAP_TREE_TOKENS=$(_adv_pid_tokens "$_ADV_REAP_TREE_PIDS") || _ADV_REAP_TREE_TOKENS=""   # (each pid's identity, before any signal)
  # (twenty-second run, a4 DISS-C-002: a pid forked before the freeze carries the token kill_tree took while it was frozen — never
  # one read after TERM; a3 C-001: the timed-out record is written only for a tree we signalled)
  local _kt _e; _kt=$(_adv_kill_tree "$_pid" TERM tokens) || _kt=""
  [[ -n "$_kt" ]] || _kt="$_pid="
  _pids=""
  for _e in $_kt; do
    [[ "${_e%%=*}" =~ ^[0-9]+$ ]] || continue
    _pids+="${_e%%=*} "
    [[ " $_ADV_REAP_TREE_TOKENS" == *" ${_e%%=*}="* ]] || _ADV_REAP_TREE_TOKENS+="$_e "
  done
  _ADV_REAP_TREE_PIDS="$_pids"; _ADV_REAPED_LIVE_TREE="true"
  for (( _i = 0; _i < _grace * 4; _i++ )); do
    _alive="false"
    for _x in $_pids; do _adv_pid_alive "$_x" && { _alive="true"; break; }; done
    [[ "$_alive" == "true" ]] || return 0
    sleep 0.25
  done
  log "Companion voice: still alive ${_grace}s after TERM — KILL"
  # (a3 C-006: re-collected before KILL — whatever the tree forked while it was being asked to leave goes with it)
  for _x in $_pids; do _adv_pid_alive "$_x" && { _fresh=$(_adv_tree_pids "$_x"); _pids=$(printf '%s\n%s\n' "$_pids" "$_fresh" | grep -v '^$' | sort -un); }; done
  for _x in $_pids; do [[ " $_ADV_REAP_TREE_TOKENS" == *" $_x="* ]] || _ADV_REAP_TREE_TOKENS+="$(_adv_pid_tokens "$_x" 2>/dev/null || true)"; done
  for _x in $_pids; do _adv_kill_same "$_x" "$_ADV_REAP_TREE_TOKENS"; done
  return 0
}
_ADV_REAPED_LIVE_TREE="false"
_ADV_PRIMARY_PID=""
_adv_run_interruptible() {  # <out file> <command…> — `out=$(command)` as a background job the run waits for: bash runs a trapped INT /
                            # TERM only once a FOREGROUND command returns, so a hop in `$(…)` kept a signalled run alive for up to its
                            # whole bound (twenty-third run, a4 DISS-C-001); `wait` returns at once and the trap reaps the job's tree
  local _out="$1" _rc=0; shift
  # (twenty-fifth run, a4 DISS-C-003: the job is the pid AND its start token, as the companion is — a pid freed by `wait` and
  # reused before it is cleared is never signalled; a signal between the fork and the publish reaps the new $!, never an older job)
  _ADV_PRIMARY_BANG="${!:-}"; _ADV_PRIMARY_FORKING=1
  ( "$@" || exit $? ) > "$_out" &   # (`||`: errexit stays off inside, as it was in the substitution)
  _ADV_PRIMARY_PID=$!; _ADV_PRIMARY_FORKING=""
  _ADV_PRIMARY_START=$(_adv_proc_start "$_ADV_PRIMARY_PID" 2>/dev/null) || _ADV_PRIMARY_START=""
  wait "$_ADV_PRIMARY_PID" || _rc=$?
  _ADV_PRIMARY_PID=""; _ADV_PRIMARY_START=""
  return "$_rc"
}
_adv_reap_primary() {  # the job _adv_run_interruptible was waiting for when a signal ended the run: TERM, the grace, then KILL
  if [[ -z "${_ADV_PRIMARY_PID:-}" && "${_ADV_PRIMARY_FORKING:-}" == "1" && -n "${!:-}" && "${!:-}" != "${_ADV_PRIMARY_BANG:-}" ]]; then
    _ADV_PRIMARY_PID="$!"; _ADV_PRIMARY_START=""   # (forked, not yet published: $! is the new job)
  fi
  _ADV_PRIMARY_FORKING=""
  [[ -n "${_ADV_PRIMARY_PID:-}" ]] || return 0
  local _p="$_ADV_PRIMARY_PID" _kt _e _pids="" _x _i _alive _grace _now_start=""
  _adv_pid_alive "$_p" || { _ADV_PRIMARY_PID=""; _ADV_PRIMARY_START=""; return 0; }
  if [[ -n "${_ADV_PRIMARY_START:-}" ]]; then
    _now_start=$(_adv_proc_start "$_p" 2>/dev/null) || _now_start=""
    if [[ -n "$_now_start" && "$_now_start" != "$_ADV_PRIMARY_START" ]]; then _ADV_PRIMARY_PID=""; _ADV_PRIMARY_START=""; return 0; fi   # (reused: not ours)
  fi
  _grace=$(_conf_uint "LOA_ADVERSARIAL_REAP_GRACE_SECONDS" "${LOA_ADVERSARIAL_REAP_GRACE_SECONDS:-5}" 5 0) || _grace=5
  _kt=$(_adv_kill_tree "$_p" TERM tokens) || _kt="$_p="
  _ADV_PRIMARY_PID=""; _ADV_PRIMARY_START=""   # (twenty-fourth run, a4 DISS-C-001: published until its tree is signalled — never cleared before)
  for _e in $_kt; do [[ "${_e%%=*}" =~ ^[0-9]+$ ]] && _pids+="${_e%%=*} "; done
  for (( _i = 0; _i < _grace * 4; _i++ )); do
    _alive="false"
    for _x in $_pids; do _adv_pid_alive "$_x" && { _alive="true"; break; }; done
    [[ "$_alive" == "true" ]] || return 0
    sleep 0.25
  done
  for _x in $_pids; do _adv_kill_same "$_x" "$_kt"; done
  return 0
}
_adv_reap_companion_timed_out() {  # <companion workdir> <chain csv> — reap the companion as a wait timeout and record it
  _adv_reap_companion
  # sixteenth run, a3 C-001: a walker that exited on its own between the caller's poll and the reap keeps its OWN status
  # and exit code (an auth / quota class at the cap boundary is not a timeout)
  # (eighteenth run, a3 C-003: whether or not a tree was signalled — a walker at `done` had finished its bookkeeping, and the
  # only thing left to signal was an exiting shell)
  if [[ -s "$1/companion.status" && "$(cat "$1/companion.phase" 2>/dev/null)" == "done" ]]; then return 0; fi
  printf 'wait_timeout' > "$1/companion.status"
  # the hop that was in flight (sixth run, C-001), else the chain's first hop
  if [[ -s "$1/companion.final" ]]; then :
  elif [[ -s "$1/companion.current" ]]; then cp -f "$1/companion.current" "$1/companion.final"
  else printf '%s' "${2%%,*}" > "$1/companion.final"; fi
  printf '124' > "$1/companion.rc"
  # (fourteenth run, a3 C-002: a walker that reached `done` had already written a complete answer — it is kept)
  [[ "$(cat "$1/companion.phase" 2>/dev/null)" == "done" ]] || command rm -f -- "$1/companion.result.json" 2>/dev/null
  return 0
}
_adv_range_diff() {  # <root> <range> → the unified diff the hunk cutter and the file-list reader parse: no external driver or textconv,
                     # and none of the operator's presentation config — no colour, a/ b/ prefixes (twenty-fifth run, a4 DISS-C-002)
  git -C "$1" diff --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ "$2" --
}
_ADV_RANGE_DIFF=""   # (the --diff-range diff, removed on every exit — twenty-fourth run, b2 DISS-C-001)
_ADV_PREV_FILES=""; _ADV_ENVELOPE_WRITTEN="false"   # (newline-delimited: a PROJECT_ROOT with a space is one path — nineteenth run, a2 C-003)
_adv_prev_files_drop() {  # the previous run's envelope and sidecars moved aside at start (`.prev`), one per line: dropped once THIS run's
                          # envelope stands — never restored (nineteenth run, b2 C-001: an aborted run leaves NO envelope at the path,
                          # so the skill can read "the script left no envelope" as a fact; the `.prev` files beside it are the previous
                          # round's evidence, already triaged in that round's feedback)
  local _ps
  while IFS= read -r _ps; do
    [[ -n "$_ps" ]] || continue
    command rm -f -- "$_ps.prev" 2>/dev/null || true
  done <<<"${_ADV_PREV_FILES:-}"
  return 0
}
_adv_cleanup_on_exit() {
  # twenty-second run, a4 DISS-C-004: a second INT / TERM while this runs would exit from inside it — the workdir and the run lock
  # left behind; the process is already exiting, so the signals are ignored until the cleanup is done
  trap '' INT TERM
  # (twenty-third run, a4 DISS-C-003: guarded like the INT / TERM sites — a trap runs under errexit, and a reaper's non-zero status
  # must never skip the workdir removal and the lock release below)
  _adv_reap_primary || true
  _adv_reap_companion || true
  [[ -n "${_ADV_RANGE_DIFF:-}" ]] && command rm -f -- "$_ADV_RANGE_DIFF" 2>/dev/null
  # (an aborted run restores nothing: the path holds no envelope, and the previous round's `.prev` files stay beside it — b2 C-001)
  # LOA_ADVERSARIAL_KEEP_WORKDIR keeps FILES for debugging, never processes: the companion tree is reaped on
  # every exit path (a background tree that outlived the run was round 1's first finding) — its partial
  # results stay in the kept workdir
  if [[ "${LOA_ADVERSARIAL_KEEP_WORKDIR:-0}" == "1" ]]; then
    if [[ -n "${_ADVERSARIAL_WORKDIR:-}" ]]; then log "Workdir kept (LOA_ADVERSARIAL_KEEP_WORKDIR=1): $_ADVERSARIAL_WORKDIR"; fi
  elif [[ -n "${_ADVERSARIAL_WORKDIR:-}" && -d "${_ADVERSARIAL_WORKDIR:-}" ]]; then
    command rm -rf -- "$_ADVERSARIAL_WORKDIR"
  fi
  _adv_release_run_lock || true   # last: the a2a directory's critical section is held until its files are settled
  return 0
}

main() {
  local type="" sprint_id="" diff_file="" diff_range="" context_file="" model="" budget="" timeout=""
  local dry_run="false" json_output="true" record_fallback="" fallback_reason="" fallback_since=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type)       type="$2"; shift 2 ;;
      --sprint-id)  sprint_id="$2"; shift 2 ;;
      --diff-file)  diff_file="$2"; shift 2 ;;
      --diff-range) diff_range="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
      --context-file) context_file="$2"; shift 2 ;;
      --model)      model="$2"; shift 2 ;;
      --budget)     budget="$2"; shift 2 ;;
      --timeout)    timeout="$2"; shift 2 ;;
      --dry-run)    dry_run="true"; shift ;;
      --json)       json_output="true"; shift ;;
      --record-fallback) record_fallback="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
      --reason)     fallback_reason="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
      --since)      fallback_since="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
      *)            error "Unknown option: $1"; exit 2 ;;
    esac
  done

  # Validate required args
  if [[ -z "$type" ]]; then error "Missing --type"; exit 2; fi
  if [[ "$type" != "review" && "$type" != "audit" ]]; then
    error "Invalid --type: $type (must be review or audit)"; exit 2
  fi
  if [[ -z "$sprint_id" ]]; then error "Missing --sprint-id"; exit 2; fi
  if [[ -n "$record_fallback" ]]; then local _rf=0; _adv_record_fallback "$type" "$sprint_id" "$record_fallback" "$fallback_reason" "$fallback_since" || _rf=$?; exit "$_rf"; fi
  if [[ -n "$fallback_since" ]]; then error "--since applies to --record-fallback failed only"; exit 2; fi
  # twenty-fourth run, a2 DISS-C-001: the skills cannot run `date` — a run that dies before it writes any record names its start
  # here, as the --since its `--record-fallback failed` needs
  log "adversarial review run started $(date -u +%Y-%m-%dT%H:%M:%SZ) (if it leaves no record: --record-fallback failed --since <this time>)"
  # twenty-fourth run, b2 DISS-C-001: the script produces the diff itself — a skill granted `git diff *` can pass --output /
  # --no-index; ref names only (never an option), no external diff driver and no textconv
  if [[ -n "$diff_range" ]]; then
    [[ -z "$diff_file" ]] || { error "--diff-file and --diff-range are exclusive"; exit 2; }
    [[ "$diff_range" =~ ^[A-Za-z0-9_][A-Za-z0-9._/~^-]*\.\.\.?[A-Za-z0-9_][A-Za-z0-9._/~^-]*$ ]] \
      || { error "--diff-range: expected <base>...<head> (ref names only)"; exit 2; }
    _ADV_RANGE_DIFF=$(mktemp "${TMPDIR:-/tmp}/adversarial-range-XXXXXX") || { error "cannot create a temp file under ${TMPDIR:-/tmp}"; exit 2; }
    trap 'command rm -f -- "$_ADV_RANGE_DIFF"' EXIT
    _adv_range_diff "$PROJECT_ROOT" "$diff_range" > "$_ADV_RANGE_DIFF" || { error "git diff $diff_range failed"; exit 2; }
    diff_file="$_ADV_RANGE_DIFF"
  fi
  if [[ -z "$diff_file" ]]; then error "Missing --diff-file"; exit 2; fi
  if [[ ! -f "$diff_file" ]]; then error "Diff file not found: $diff_file"; exit 2; fi

  # Load config
  load_adversarial_config "$type"

  # Apply argument overrides
  model="${model:-$CONF_MODEL}"
  budget=$(_conf_uint "--budget" "${budget:-$CONF_BUDGET_CENTS}" 0 0)     # (fifteenth run, a1 C-001: the overrides are held to the same shape; a malformed cap is 0 — fail closed)
  timeout=$(_conf_uint "--timeout" "${timeout:-$CONF_TIMEOUT}" "$CONF_TIMEOUT" 1)

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
  # honours TMPDIR (seventh run, c1 C-005); twelfth run, a3 C-005: mktemp -d — 0700 and unpredictable, so a pre-placed
  # symlink at a guessable `adversarial-<sprint>-<pid>` path cannot redirect the prompts and logs on a shared host
  if ! _ADVERSARIAL_WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/adversarial-${sprint_id}-XXXXXX" 2>/dev/null); then
    error "cannot create a workdir under ${TMPDIR:-/tmp}"
    [[ "$json_output" == "true" ]] && _adv_refuse_json workdir_unavailable tmpdir "${TMPDIR:-/tmp}"   # (thirteenth run, a3 C-005)
    exit 2
  fi
  # one cleanup trap for every exit path (round 1, third run, C-004): reaps a companion, removes the
  # workdir unless LOA_ADVERSARIAL_KEEP_WORKDIR=1 — registered here, not only when a companion is planned
  trap '_adv_cleanup_on_exit' EXIT
  # (twenty-first run, a4 DISS-C-002: a trap's command list runs under errexit — the reaper is guarded like every other call site,
  # so the run exits 130 / 143, never the reaper's status)
  # (twenty-fourth run, a4 DISS-C-001: bash runs a second signal's trap NESTED inside a running one — each handler first ignores
  # INT / TERM, so one reap runs to the end and the run exits with the first signal's status)
  trap "trap '' INT TERM; _adv_reap_primary || true; _adv_reap_companion || true; exit 130" INT
  trap "trap '' INT TERM; _adv_reap_primary || true; _adv_reap_companion || true; exit 143" TERM

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

  # Assemble context (cycle-124 FR-2: input budget follows the dissenter's
  # company; the estimate is logged BEFORE dispatch so a truncated diff is
  # visible in the run log, not discovered from the verdict).
  local primary_input_budget
  primary_input_budget=$(_adv_input_budget_for_model "$model")
  log "Dissenter input: model=$model estimated_input_tokens=$estimated_input_tokens primary_budget=$primary_input_budget max_output_tokens=$DISSENT_MAX_OUTPUT_TOKENS"
  local context_json
  context_json=$(assemble_dissent_context "$diff_file" "$type" "$context_file" "$primary_input_budget")
  # twentieth run, b1 C-002: a diff that prepares to nothing is refused before the run lock — no call is made and the
  # previous envelope is left where it is
  if [[ "$(jq -r '.nothing_to_review // false' <<<"$context_json" 2>/dev/null)" == "true" ]]; then
    error "Nothing to review: the diff prepared to no content — no dissent call made"
    [[ "$json_output" == "true" ]] && _adv_refuse_json nothing_to_review
    exit 1
  fi

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

  # cycle-126 FR-2.1: plan the companion voice from the configured primary's
  # family and start it now, in parallel with the primary walk.
  local companion_planned="false" companion_family="" companion_chain_csv="" companion_pid="" companion_skip_reason="" companion_shared_hops=""
  local companion_workdir="${_ADVERSARIAL_WORKDIR:-}/companion" companion_wait_cap=0 companion_started=0 companion_post_budget=60 companion_q_allow=0
  # fourth run (chunk b C-003 / chunk c C-002): one run owns the sprint directory's rejected set — both
  # canonical sidecars go before any writer starts, so a writer that does not run this time (companion
  # off, no_route) cannot leave last run's rows to be demanded as triage; the envelope lists what this
  # run produced (metadata.rejected_sidecars) and verdict-derive counts only those
  _adv_resolve_run_tag; local _run_tag="$_ADV_RUN_TAG"
  # a second live run for this sprint and gate is refused HERE, before the cleanup below removes anything (the tag
  # scopes the sidecar names only — the envelope path is shared, so a tag is not a parallel path)
  _adv_take_run_lock "$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}" "$type" || {
    # twelfth run, a3 C-004: a --json caller fails closed on a refusal too — an envelope whose status says why
    [[ "$json_output" == "true" ]] && _adv_refuse_json refused_concurrent_run
    exit 2
  }
  local -a _run_sidecars=("grimoires/loa/a2a/${sprint_id}/adversarial-rejected-${type}${_run_tag:+-$_run_tag}.jsonl"
                          "grimoires/loa/a2a/${sprint_id}/adversarial-rejected-${type}-companion${_run_tag:+-$_run_tag}.jsonl")
  if [[ -z "${LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE:-}" ]]; then
    # eighteenth run, a4 C-001: moved aside, not removed — the previous envelope lists them, and a run that aborts before
    # writing its own envelope (a session limit, an operator INT, a fail-closed exit) would leave it pointing at nothing;
    # nothing is restored: an aborted run leaves the `.prev` files beside the path, and write_output drops them once this
    # run's envelope is written (twentieth run, a4 C-003)
    local _sc; _ADV_PREV_FILES=""
    for _sc in "${_run_sidecars[@]}"; do
      if [[ -f "$PROJECT_ROOT/$_sc" ]] && mv -f -- "$PROJECT_ROOT/$_sc" "$PROJECT_ROOT/$_sc.prev" 2>/dev/null; then _ADV_PREV_FILES="${_ADV_PREV_FILES:+$_ADV_PREV_FILES$'\n'}$PROJECT_ROOT/$_sc"; fi
    done
  fi
  # nineteenth run, b2 C-001 (BLOCKING): the previous run's ENVELOPE goes aside too, so a run that aborts leaves none at the
  # path — "the script left no envelope" becomes a fact the skill can read, never a guess about whose envelope it is
  local _env_rel="grimoires/loa/a2a/${sprint_id}/adversarial-${type}.json"
  if [[ -f "$PROJECT_ROOT/$_env_rel" ]] && mv -f -- "$PROJECT_ROOT/$_env_rel" "$PROJECT_ROOT/$_env_rel.prev" 2>/dev/null; then _ADV_PREV_FILES="${_ADV_PREV_FILES:+$_ADV_PREV_FILES$'\n'}$PROJECT_ROOT/$_env_rel"; fi
  if [[ "${CONF_COMPANION_VOICE:-true}" == "true" && ( -z "${_ADVERSARIAL_WORKDIR:-}" || ! -d "${_ADVERSARIAL_WORKDIR:-}" ) ]]; then
    # round 1 (third run, C-006): the companion needs the run's workdir; without one it is not planned
    companion_skip_reason="no_workdir"; companion_family=$(_companion_family "$(_adv_family_of "$model")")
    log "Companion voice not planned ($companion_family family): no_workdir"
  elif [[ "${CONF_COMPANION_VOICE:-true}" == "true" ]]; then
    companion_family=$(_companion_family "$(_adv_family_of "$model")")
    local companion_chain_str
    companion_chain_str=$(_companion_chain "$companion_family")
    if [[ -z "$companion_chain_str" ]]; then
      companion_skip_reason="no_route"
    else
      # review sprint-248 C-005 (round 1, live re-run): a hop the primary chain also holds — typically
      # the other family's CLI as the primary's last resort — STAYS in the companion chain (a keyless
      # primary usually answers earlier, and the second voice is worth having); it is recorded under
      # companion_voice.shared_hops and independence is judged after the walk from the voices that
      # actually answered (a same-family companion counts as a dropped voice in verdict quality).
      local _cm _pm
      companion_shared_hops=""
      for _cm in $companion_chain_str; do
        # (bare names on both sides — a configured `anthropic:claude-headless` is the companion's `claude-headless`; twelfth run, a2 C-001)
        # (canonical on both sides — fourteenth run, a3 C-003: a prefixed or aliased CLI hop is the same hop)
        for _pm in "${fallback_chain[@]}"; do [[ "$(_adv_hop_canon "$_pm")" == "$(_adv_hop_canon "$_cm")" ]] && { companion_shared_hops="${companion_shared_hops:+$companion_shared_hops,}$(_adv_hop_canon "$_cm")"; break; }; done
      done
      {
        companion_planned="true"
        companion_chain_csv="${companion_chain_str// /,}"
        # shellcheck disable=SC2086
        companion_wait_cap=$(_adv_num_or "${LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS:-$(_companion_wait_cap "$timeout" $companion_chain_str)}" "$(_adv_num_or "$(_companion_wait_cap "$timeout" $companion_chain_str)" 630)")   # (a3 C-003: an operator knob is validated)
        companion_post_budget=$(_adv_num_or "$(_companion_post_budget "$model" "$timeout")" 60)
        # the queue allowance of the global ceiling (twelfth run, a3 C-002), computed once here so the primary's shared-hop wait
        # and the post-walk wait share one deadline model (eighteenth run, a4 C-002)
        # shellcheck disable=SC2086
        companion_q_allow=$(_adv_num_or "$(_companion_queue_allowance $companion_chain_str)" 0)
        log "Companion voice ($companion_family family): $companion_chain_str (wait cap ${companion_wait_cap}s)"
        # round 1 (third run, C-005): the companion reads its own copies of the prompt files — the two
        # walks share nothing mutable (the KF-011 debug capture is already keyed by model + timestamp)
        if mkdir -p "$companion_workdir" 2>/dev/null && cp -f "$_ADVERSARIAL_WORKDIR/system-prompt.txt" "$_ADVERSARIAL_WORKDIR/user-prompt.txt" "$companion_workdir/" 2>/dev/null; then   # (a4 C-001: a workdir that cannot be made is the same local failure as a prompt copy that cannot)
          # shellcheck disable=SC2086
          date -u +%Y-%m-%dT%H:%M:%SZ > "$companion_workdir/companion.started_iso" 2>/dev/null || true   # (before the launch: the window holds the first hop's first second too)
          ( _walk_companion_chain "$companion_workdir" "$companion_workdir" "$type" "$sprint_id" "$timeout" "$diff_files" $companion_chain_str >"$companion_workdir/companion.log" 2>&1 ) &
          companion_pid=$!
          _ADV_COMPANION_PID="$companion_pid"   # (twenty-second run, a4 DISS-C-001: published before the next fork — a signal in that window reaps it)
          companion_started=$(date +%s)
          _ADV_COMPANION_START=$(_adv_proc_start "$companion_pid" 2>/dev/null) || _ADV_COMPANION_START=""   # (nineteenth run, a4 C-001: a child gone in the fork window never aborts main — an unreadable token falls back to the pid alone)
        else
          # twelfth run, a3 C-006: a local setup failure is never attributed to the provider — no fork, a named reason;
          # fourteenth run, a3 C-004: nothing is shared with a companion that never started
          companion_planned="false"; companion_skip_reason="prompt_copy_failed"; companion_shared_hops=""
          rmdir "$companion_workdir" 2>/dev/null || true
        fi
      }
    fi
    [[ -n "$companion_skip_reason" ]] && log "Companion voice not planned ($companion_family family): $companion_skip_reason"
  fi
  local api_exit=0 raw_response="" vq_sidecar=""   # (nineteenth run, a4 C-003: an all-ceded chain reaches the merge without a hop ever invoked)
  for try_model in "${fallback_chain[@]}"; do
    # tenth run, a2 C-003: a hop the live companion is (or will be) running is not run twice — the primary
    # would only queue up to the hop's bound behind the companion's claude -p and then be a duplicate voice;
    # the fold's sole_voice / duplicate handling covers the outcome
    # (thirteenth run, a3 C-004: consulted whether or not the companion is still alive — a companion that already
    # answered with this hop is honoured too, so the binary never runs twice for the same prompt)
    if [[ -n "${companion_shared_hops:-}" && ",$companion_shared_hops," == *",$(_adv_hop_canon "$try_model"),"* && -n "${companion_workdir:-}" && -d "$companion_workdir" ]]; then
      _adv_companion_alive && log "Model $try_model is a hop the companion shares — the primary waits for the companion to settle before deciding"
      local _sh_verdict="" _sh_token="" _sh_reason=""
      # (twenty-fifth run, a4 DISS-C-001: the wait — up to the wait cap — is an interruptible job like the hop itself: a TERM sent
      # to main alone runs its trap at once, never after the wait returns)
      _adv_run_interruptible "$_ADVERSARIAL_WORKDIR/shared-hop.out" _adv_shared_hop_verdict "$try_model" "$companion_workdir" "$companion_started" "$companion_wait_cap" "$companion_post_budget" "$companion_q_allow" || true
      IFS=$'\t' read -r _sh_verdict _sh_token _sh_reason < "$_ADVERSARIAL_WORKDIR/shared-hop.out" || true
      if [[ "$_sh_token" == "past_wait_cap" || "$_sh_token" == "post_budget_expired" ]]; then   # (a token, never prose — fifteenth run, a4 C-003; eighteenth run, a3: a post phase past its budget too)
        # fourteenth run, a3 C-002: a companion past the wait cap and still ON the hop is reaped HERE, and the primary
        # runs its last resort itself — skipping it and reaping afterwards left a run with no voice at all
        log "Companion voice: wait cap ${companion_wait_cap}s reached while the primary waited on $try_model — reaping the second voice; the primary runs the hop"
        _adv_reap_companion_timed_out "$companion_workdir" "$companion_chain_csv" || true
        _sh_verdict="run"; _sh_reason="was reaped at the wait cap"
      fi
      if [[ "$_sh_verdict" == "skip" ]]; then
        log "Model $try_model is the companion's hop and the companion ${_sh_reason:-answered with it} — skipped on the primary chain"
        model_attempts+=("${try_model}:skipped_shared_with_companion")
        continue
      fi
      log "Model $try_model is a hop the companion shares, and the companion ${_sh_reason:-finished without it} — the primary runs it"
    fi
    # Allocate per-attempt sidecar path under the adversarial workdir so
    # parallel adversarial-review invocations don't collide.
    local vq_sidecar
    vq_sidecar="$_vq_tmpdir/vq-${type}-${try_model//[^A-Za-z0-9_-]/_}-$$-$RANDOM.json"
    api_exit=0   # (fifteenth run, a4 C-004: reset only for a hop that is actually invoked — a ceded last hop keeps the previous hop's code for the record)
    # (twenty-third run, a4 DISS-C-001: the hop and the findings pass — its repair hops — run as jobs the run waits for, so a signal
    # is handled at once)
    _adv_run_interruptible "$_ADVERSARIAL_WORKDIR/primary-hop.out" _adv_invoke_hop "$try_model" "$_ADVERSARIAL_WORKDIR/system-prompt.txt" "$_ADVERSARIAL_WORKDIR/user-prompt.txt" "$try_model" "$timeout" "$vq_sidecar" "$type" "$SCRIPT_DIR/../schemas/wire/dissent-${type}.wire.json" || api_exit=$?
    raw_response=$(cat "$_ADVERSARIAL_WORKDIR/primary-hop.out")
    # Collect the per-attempt envelope (if cheval wrote one).
    if [[ -s "$vq_sidecar" ]]; then
      vq_attempt_files+=("$vq_sidecar")
      vq_cleanup_files+=("$vq_sidecar")
    fi
    _adv_run_interruptible "$_ADVERSARIAL_WORKDIR/primary-findings.out" process_findings "$raw_response" "$type" "$try_model" "$sprint_id" "$api_exit" "$diff_files"
    result=$(cat "$_ADVERSARIAL_WORKDIR/primary-findings.out")
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
  local -a COMPANION_VQ_FILES=()
  if [[ "$companion_planned" == "true" ]]; then
    if [[ -n "$companion_pid" ]]; then
      # the deadline follows the companion's phase: a hop gets the chain's cap from the phase's start
      # (the fork, or the next hop), the post-hop work (validation, repair round-trips) its own budget —
      # a model that answered is never reaped mid-process_findings (fifth run, C-001)
      local _why=""
      # twelfth run, a3 C-002: a global ceiling beside the phase deadline — the phase clock restarts at every hop, so a
      # two-hop companion could hold an answered primary for twice the cap; the reap message names what fired.
      # a3 C-003: every operand is a validated whole number. Eighteenth run, a4 C-002: the same helper the primary's
      # shared-hop wait uses — one deadline model
      while _adv_companion_alive; do   # (sixteenth run, a4 C-001: pid + start token, never the raw pid — bash frees a reaped child's pid at once)
        _companion_deadline_why "$companion_workdir" "$companion_started" "$companion_wait_cap" "$companion_post_budget" "$companion_q_allow" _why
        [[ -n "$_why" ]] && break
        sleep 1
      done
      if _adv_companion_alive; then
        log "Companion voice: wait cap ${companion_wait_cap}s reached (${_why:-deadline}) — reaping the second voice"
        _adv_reap_companion_timed_out "$companion_workdir" "$companion_chain_csv" || true
      fi
      # bounded: a reaped tree that will not die must not hold the review (sixth run)
      local _w=0
      while [[ -n "${_ADV_COMPANION_PID:-}" ]] && _adv_companion_alive && (( _w < 40 )); do sleep 0.25; _w=$((_w + 1)); done
      if [[ -n "${_ADV_COMPANION_PID:-}" ]] && _adv_companion_alive; then _adv_kill_tree "$companion_pid" KILL >/dev/null || true; fi   # (stdout is the envelope; fifteenth run, a4 C-001: never the last command of an && list)
      wait "$companion_pid" 2>/dev/null || true
      _ADV_COMPANION_PID=""
      date -u +%Y-%m-%dT%H:%M:%SZ > "$companion_workdir/companion.ended_iso" 2>/dev/null || true
    fi
    # chunk c C-003: the primary voice that actually answered (its last sidecar's succeeded id)
    local primary_succeeded="$final_model"
    if (( ${#vq_attempt_files[@]} > 0 )); then
      local _psid
      _psid=$(jq -r '(.voices_succeeded_ids // []) | if length > 0 then .[-1] else empty end' "${vq_attempt_files[-1]}" 2>/dev/null || true)
      [[ -n "$_psid" ]] && primary_succeeded="$_psid"
    fi
    # fifth run, C-003: a primary that never answered has no succeeded voice — its last FAILED hop is not
    # a voice to judge independence against (on this host it is claude-headless, the companion's own)
    if echo "$result" | jq -e '(.metadata.status // "") | IN("api_failure", "malformed_response")' >/dev/null 2>&1; then
      primary_succeeded=""
    fi
    # review sprint-248 C-002: a fold that fails must never blank the paid-for primary envelope
    local _folded=""
    # every primary voice that answered (union of the attempts' succeeded ids) — a failed companion whose
    # dropped id is one of them may not feed a dropped-voice envelope (INV-5) (third run, C-001)
    local primary_succeeded_ids=""
    if (( ${#vq_attempt_files[@]} > 0 )); then
      primary_succeeded_ids=$(jq -rs '[.[] | (.voices_succeeded_ids // [])[]] | unique | join(",")' "${vq_attempt_files[@]}" 2>/dev/null || true)
    fi
    # the hop the primary ceded (its last attempt was a shared-hop skip), for the fold's ceded / degraded distinction
    local _primary_ceded=""
    [[ "${model_attempts[-1]:-}" == *:skipped_shared_with_companion ]] && _primary_ceded="${model_attempts[-1]%:*}"   # (the hop keeps a provider prefix: only the status suffix goes)
    _folded=$(_fold_companion "$result" "$companion_workdir" "$companion_family" "$companion_chain_csv" "$final_model" "$primary_succeeded" "$companion_shared_hops" "$primary_succeeded_ids" "$_primary_ceded" 2>>"$companion_workdir/fold.log") || _folded=""
    [[ -s "$companion_workdir/fold.log" ]] && cat "$companion_workdir/fold.log" >&2
    local _fold_ok="false"
    if [[ -n "$_folded" ]] && printf '%s' "$_folded" | jq -e '.metadata | type == "object"' >/dev/null 2>&1; then
      result="$_folded"; _fold_ok="true"
    else
      log "Companion voice: fold failed — keeping the primary envelope (companion_voice.status=fold_failed)"
      result=$(echo "$result" | jq --arg fam "$companion_family" --arg chain "$companion_chain_csv" \
        '.metadata.companion_voice = {planned: true, family: $fam, chain: ($chain | split(",")), status: "fold_failed"}')
    fi
    # the companion's verdict-quality inputs: its attempts' sidecars when it completed as an
    # independent voice; the synthetic FAILED envelope the fold wrote when it did not complete;
    # nothing when it duplicated the primary's family (a subshell cannot set this array)
    if [[ "$_fold_ok" == "true" && -s "$companion_workdir/companion.result.json" && ! -e "$companion_workdir/companion.duplicate" ]]; then
      local _cvf
      if [[ -f "$companion_workdir/companion.vq" ]]; then   # (thirteenth run, a3 C-003: never an errexit abort on a missing list)
        while IFS= read -r _cvf; do [[ -s "$_cvf" ]] && COMPANION_VQ_FILES+=("$_cvf"); done < "$companion_workdir/companion.vq"
      fi
    elif [[ "$_fold_ok" != "true" && ( -s "$companion_workdir/companion.result.json" || ( ! -s "$companion_workdir/vq-companion-synthetic.json" && ! -e "$companion_workdir/companion.duplicate" ) ) ]]; then
      # thirteenth run, a3 C-002: a fold that failed dropped the companion's findings — verdict quality says so instead of
      # counting a voice whose findings are absent: a synthetic FAILED envelope names the loss as fold_failed (unless
      # that id is also a primary voice that answered — INV-5, the fold's own duplicate rule). Twenty-first run, a4 DISS-C-003:
      # a companion that FAILED and a fold that failed too get the same envelope — the fold that writes the failed voice's
      # synthetic never completed, and verdict quality must still plan the second voice
      local _ff_final; _ff_final=$(cat "$companion_workdir/companion.final" 2>/dev/null || echo "${companion_chain_csv%%,*}")
      local _ff_why="fold_failed: the companion answered but its fold failed, so its findings are not on the envelope"
      [[ -s "$companion_workdir/companion.result.json" ]] || _ff_why="fold_failed: the companion did not complete and its fold failed"
      if [[ ",${primary_succeeded_ids}," != *",${_ff_final},"* && "$primary_succeeded" != "$_ff_final" ]]; then
        jq -nc --arg v "$_ff_final" --arg why "$_ff_why" '{status:"FAILED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:0,voices_succeeded_ids:[],voices_dropped:[{voice:$v,reason:"Other",exit_code:1,blocker_risk:"unknown"}],chain_health:"exhausted",confidence_floor:"low",rationale:$why,single_voice_call:true}' \
          > "$companion_workdir/vq-companion-foldfailed.json" 2>/dev/null && COMPANION_VQ_FILES+=("$companion_workdir/vq-companion-foldfailed.json")
      fi
    elif [[ -s "$companion_workdir/vq-companion-synthetic.json" ]]; then
      COMPANION_VQ_FILES+=("$companion_workdir/vq-companion-synthetic.json")
    fi
    log "Companion voice: $(echo "$result" | jq -r '.metadata.companion_voice | "\(.model // "-") \(.status)\(if .failure_class then " (" + .failure_class + ")" else "" end)"')"
  elif [[ -n "$companion_skip_reason" ]]; then
    result=$(echo "$result" | jq --arg r "$companion_skip_reason" --arg fam "$companion_family" '.metadata.companion_voice = {planned: false, reason: $r, family: $fam}')
  else
    result=$(echo "$result" | jq '.metadata.companion_voice = {planned: false}')
  fi
  # the rejected sidecars THIS run produced (paths relative to the project root)
  local _sc _sidecars_json="[]"
  if [[ -z "${LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE:-}" ]]; then   # sixth run, C-004: disabled → nothing of ours to list
    for _sc in "${_run_sidecars[@]}"; do
      [[ -f "$PROJECT_ROOT/$_sc" ]] && _sidecars_json=$(echo "$_sidecars_json" | jq --arg p "$_sc" '. + [$p]')
    done
  fi
  result=$(echo "$result" | jq --argjson sc "$_sidecars_json" '.metadata.rejected_sidecars = $sc')

  # cycle-109 Sprint 2 T2.5 — aggregate per-attempt verdict_quality
  # envelopes via the canonical Python aggregator (SDD §5.2.1). The
  # aggregator embeds chain_health (worst-of-N), voices_dropped[] entries
  # from failed attempts, and a status that surfaces #807 / #823 / #868
  # class regressions explicitly. Fail-soft: legacy / pre-T2.3 cheval emits
  # produce empty vq_attempt_files; in that case result.verdict_quality
  # stays absent (downstream consumers handle).
  # fifth run, C-003: when the companion answered as X and a primary attempt DROPPED X (a shared hop the
  # primary fell through), that attempt's envelope cannot sit beside the companion's (INV-5: one id may
  # not be both succeeded and dropped) — it is excluded from aggregation and named on the envelope
  if (( ${#COMPANION_VQ_FILES[@]} > 0 && ${#vq_attempt_files[@]} > 0 )); then
    local _cx _kept_vq=() _excluded_vq=() _cid_x _rewritten_vq=0
    _cid_x=$(jq -rs '[.[] | (.voices_succeeded_ids // [])[]] | unique | join(" ")' "${COMPANION_VQ_FILES[@]}" 2>/dev/null </dev/null || true)
    for _cx in "${vq_attempt_files[@]}"; do
      if [[ -n "$_cid_x" ]] && _adv_vq_dropped_matching "$_cx" "$_cid_x" >/dev/null; then   # (canonical — twentieth run, a3 DISS-C-005)
        if jq -e '(.voices_succeeded_ids // []) | length == 0' "$_cx" >/dev/null 2>&1; then
          _excluded_vq+=("$(jq -r '[(.voices_dropped // [])[].voice] | join(",")' "$_cx" 2>/dev/null || true)")   # (a4 C-003: never the last command of the assignment)
        elif _adv_inv5_rewrite "$_cx" "$_cid_x" "$_cx.inv5.json"; then
          # twelfth run, a3 C-007: a MIXED envelope (cheval's inner walk dropped the companion's voice AND answered with
          # another) keeps its own succeeded voice — a copy without the conflicting dropped entries is aggregated
          _kept_vq+=("$_cx.inv5.json"); _rewritten_vq=$((_rewritten_vq + 1))
        else
          _excluded_vq+=("$(jq -r '[(.voices_dropped // [])[].voice] | join(",")' "$_cx" 2>/dev/null || true)")   # (a4 C-003: never the last command of the assignment)
        fi
      else
        _kept_vq+=("$_cx")
      fi
    done
    if (( _rewritten_vq > 0 )); then
      log "Companion voice: $_rewritten_vq primary attempt envelope(s) that also dropped the companion's own voice rewritten without that entry (INV-5; the primary's own voice kept)"
      result=$(echo "$result" | jq --arg n "$_rewritten_vq" '.metadata.companion_voice.primary_attempts_rewritten = ($n | tonumber)')
      vq_attempt_files=(${_kept_vq[@]+"${_kept_vq[@]}"})
    fi
    if (( ${#_excluded_vq[@]} > 0 )); then
      log "Companion voice: ${#_excluded_vq[@]} primary attempt envelope(s) dropping the companion's own voice (${_excluded_vq[*]}) excluded from verdict quality (INV-5)"
      result=$(echo "$result" | jq --arg n "${#_excluded_vq[@]}" '.metadata.companion_voice.primary_attempts_excluded = ($n | tonumber)')
      vq_attempt_files=(${_kept_vq[@]+"${_kept_vq[@]}"})   # (guarded: bash < 4.4 under set -u — thirteenth run, a3 C-007)
    fi
    # …and the mirror (eighth run, a2 C-004): a companion attempt that DROPPED a voice the primary answered with
    local _pid_x="" _kept_cvq=() _excluded_cvq=()
    # (tenth run, a2 C-002: the first pass may have emptied the primary set — an empty operand list would make
    # `jq -rs` read stdin; the pass is skipped and every companion envelope kept)
    if (( ${#vq_attempt_files[@]} > 0 )); then
      _pid_x=$(jq -rs '[.[] | (.voices_succeeded_ids // [])[]] | unique | join(" ")' "${vq_attempt_files[@]}" 2>/dev/null </dev/null || true)
    fi
    local _rewritten_cvq=0
    for _cx in "${COMPANION_VQ_FILES[@]}"; do
      if [[ -n "$_pid_x" ]] && _adv_vq_dropped_matching "$_cx" "$_pid_x" >/dev/null; then   # (canonical — twentieth run, a3 DISS-C-005)
        if jq -e '(.voices_succeeded_ids // []) | length == 0' "$_cx" >/dev/null 2>&1; then
          _excluded_cvq+=("$(jq -r '[(.voices_dropped // [])[].voice] | join(",")' "$_cx" 2>/dev/null || true)")   # (a4 C-003)
        elif _adv_inv5_rewrite "$_cx" "$_pid_x" "$_cx.inv5.json"; then
          _kept_cvq+=("$_cx.inv5.json"); _rewritten_cvq=$((_rewritten_cvq + 1))
        else
          _excluded_cvq+=("$(jq -r '[(.voices_dropped // [])[].voice] | join(",")' "$_cx" 2>/dev/null || true)")   # (a4 C-003)
        fi
      else
        _kept_cvq+=("$_cx")
      fi
    done
    if (( _rewritten_cvq > 0 )); then
      log "Companion voice: $_rewritten_cvq companion attempt envelope(s) that also dropped a voice the primary answered with rewritten without that entry (INV-5; the companion's own voice kept)"
      result=$(echo "$result" | jq --arg n "$_rewritten_cvq" '.metadata.companion_voice.companion_attempts_rewritten = ($n | tonumber)')
      COMPANION_VQ_FILES=(${_kept_cvq[@]+"${_kept_cvq[@]}"})
    fi
    if (( ${#_excluded_cvq[@]} > 0 )); then
      log "Companion voice: ${#_excluded_cvq[@]} companion attempt envelope(s) dropping a voice the primary answered with (${_excluded_cvq[*]}) excluded from verdict quality (INV-5)"
      result=$(echo "$result" | jq --arg n "${#_excluded_cvq[@]}" '.metadata.companion_voice.companion_attempts_excluded = ($n | tonumber)')
      COMPANION_VQ_FILES=(${_kept_cvq[@]+"${_kept_cvq[@]}"})
    fi
  fi
  if [[ ${#vq_attempt_files[@]} -gt 0 || ${#COMPANION_VQ_FILES[@]} -gt 0 ]]; then
    local _vq_agg
    local _vq_err_file="${_ADVERSARIAL_WORKDIR:-${TMPDIR:-/tmp}}/vq-aggregate-$$.err"
    if _vq_agg=$(_adv_aggregate_envelopes ${vq_attempt_files[@]+"${vq_attempt_files[@]}"} ${COMPANION_VQ_FILES[@]+"${COMPANION_VQ_FILES[@]}"} 2>"$_vq_err_file"); then
      if [[ -n "$_vq_agg" ]]; then
        result=$(echo "$result" | jq --argjson vq "$_vq_agg" \
          '.verdict_quality = $vq')
      fi
    else
      # eighth run, a2 C-004: the aggregator's own reason is named on the envelope, never discarded
      local _vq_err; _vq_err=$(grep -v '^[[:space:]]*$' "$_vq_err_file" 2>/dev/null | tail -1 | cut -c1-240) || _vq_err=""   # (fourteenth run, a3 C-001: an aggregator that failed silently must not abort the fail-soft branch)
      log "[vq-aggregate] aggregator unavailable or returned no output; result emitted without verdict_quality${_vq_err:+ — $_vq_err}"
      result=$(echo "$result" | jq --arg e "${_vq_err:-aggregator returned no output}" '.metadata.verdict_quality_error = $e')
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
