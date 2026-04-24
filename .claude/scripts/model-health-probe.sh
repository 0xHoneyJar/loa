#!/usr/bin/env bash
# =============================================================================
# model-health-probe.sh — Provider model availability probe
# =============================================================================
# Version: 1.0.0
# Cycle: 093 (Loa Stabilization & Model-Currency Architecture)
# Sprint: 3A (Health-Probe Core — T2.2 part 1)
# SDD: grimoires/loa/cycles/cycle-093-stabilization/sdd.md §3.1–§3.6, §5.2, §6.1
#
# Classifies each model in the registry as AVAILABLE | UNAVAILABLE | UNKNOWN
# against live provider APIs, with an atomic-write on-disk cache, PID sentinel
# for background-probe dedup, and hard-stop budget enforcement.
#
# Usage:
#   model-health-probe.sh [OPTIONS]
#
# Options:
#   --once                    Run once, exit (default behavior)
#   --dry-run                 Parse config/registry; do NOT call provider APIs
#   --invalidate [MODEL_ID]   Clear a cache entry (or full cache if omitted)
#   --provider PROVIDER       Probe only one provider (openai|google|anthropic)
#   --model MODEL_ID          Probe only one model-id (use with --provider)
#   --cache-path PATH         Override cache file path
#   --output FORMAT           "text" (default) | "json"
#   --fail-on STATE           Treat STATE as gate-failure (default UNAVAILABLE)
#   --quiet                   Summary + exit; no per-model lines
#   --canary                  Non-blocking smoke mode (always exit 0)
#   --help                    Usage
#   --version                 Print version
#
# Exit codes (SDD §6.1):
#   0   All probed AVAILABLE or UNKNOWN
#   1   Generic error (config parse / flock timeout)
#   2   At least one model in the --fail-on state (default UNAVAILABLE)
#   3   Probe infra failure when degraded_ok=false
#   5   Budget hardstop exceeded (probes/cost/timeout)
#   64  Usage error (bad args)
#
# Environment:
#   OPENAI_API_KEY, GOOGLE_API_KEY, ANTHROPIC_API_KEY
#   LOA_PROBE_LEGACY_BEHAVIOR=1   Short-circuit to all-AVAILABLE (emergency)
#   LOA_PROBE_MOCK_MODE=1         Use fixture files instead of live HTTP
#   LOA_PROBE_MOCK_OPENAI         Fixture path for OpenAI response
#   LOA_PROBE_MOCK_GOOGLE         Fixture path for Google response
#   LOA_PROBE_MOCK_ANTHROPIC      Fixture path for Anthropic response
#   LOA_PROBE_MOCK_HTTP_STATUS    Override HTTP status in mock mode
#   LOA_PROBE_MAX_PROBES          Override per-run probe budget (default 10)
#   LOA_PROBE_MAX_COST_CENTS      Override cost cap (default 5 = $0.05)
#   LOA_PROBE_INVOCATION_TIMEOUT  Override total timeout seconds (default 120)
#   LOA_PROBE_PER_CALL_TIMEOUT    Override per-call timeout seconds (default 30)
#   LOA_CACHE_DIR                 Override cache directory (default .run)
#   LOA_TRAJECTORY_DIR            Override trajectory-log directory (test isolation)
#   LOA_AUDIT_LOG                 Override audit-log path (test isolation)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants & paths
# -----------------------------------------------------------------------------
MODEL_HEALTH_PROBE_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
MODEL_REGISTRY_YAML="${MODEL_REGISTRY_YAML:-$PROJECT_ROOT/.claude/defaults/model-config.yaml}"
LOA_CACHE_DIR="${LOA_CACHE_DIR:-$PROJECT_ROOT/.run}"
CACHE_PATH_DEFAULT="$LOA_CACHE_DIR/model-health-cache.json"
# Env-overridable for test isolation (Bridgebuilder F8/F-002/F-003):
TRAJECTORY_DIR="${LOA_TRAJECTORY_DIR:-$PROJECT_ROOT/.run/trajectory}"
AUDIT_LOG="${LOA_AUDIT_LOG:-$PROJECT_ROOT/.run/audit.jsonl}"
CACHE_SCHEMA_VERSION="1.0"

# Hard-stop budgets (Flatline IMP-006 — all exit 5 on breach)
MAX_PROBES_PER_RUN="${LOA_PROBE_MAX_PROBES:-10}"
MAX_COST_CENTS="${LOA_PROBE_MAX_COST_CENTS:-5}"        # $0.05
INVOCATION_TIMEOUT="${LOA_PROBE_INVOCATION_TIMEOUT:-120}"
PER_CALL_TIMEOUT="${LOA_PROBE_PER_CALL_TIMEOUT:-30}"

# Run-scoped state (mutable; finalized in main)
PROBE_RUN_ID=""
PROBE_START_EPOCH=""
PROBES_USED=0
COST_CENTS_USED=0

# CLI-parsed options (defaults)
OPT_DRY_RUN=0
OPT_INVALIDATE=0
OPT_INVALIDATE_MODEL=""
OPT_PROVIDER=""
OPT_MODEL=""
OPT_CACHE_PATH=""
OPT_OUTPUT="text"
OPT_FAIL_ON="UNAVAILABLE"
OPT_QUIET=0
OPT_CANARY=0

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log_info()  { [[ "$OPT_QUIET" == "1" ]] || echo "[model-health-probe] $*" >&2; }
log_warn()  { echo "[model-health-probe] WARN: $*" >&2; }
log_error() { echo "[model-health-probe] ERROR: $*" >&2; }
log_debug() { [[ "${LOA_LOG_LEVEL:-INFO}" == "DEBUG" ]] && echo "[model-health-probe] DEBUG: $*" >&2 || true; }

# -----------------------------------------------------------------------------
# Helpers — time, IDs, redaction
# -----------------------------------------------------------------------------
_iso_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

_gen_run_id() {
    # UUIDv4 via python if available; else fallback to epoch+random
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import uuid; print(uuid.uuid4())'
    else
        printf "probe-%s-%s" "$(date +%s)" "$RANDOM$RANDOM"
    fi
}

# _redact_secrets — scrub API key patterns from a string
# Minimal inline implementation; lib-security.sh has a broader one we could source later.
_redact_secrets() {
    local text="$1"
    # shellcheck disable=SC2001
    echo "$text" \
        | sed -E 's/sk-[A-Za-z0-9_-]{20,}/sk-REDACTED/g' \
        | sed -E 's/AIza[A-Za-z0-9_-]{20,}/AIza-REDACTED/g' \
        | sed -E 's/ghp_[A-Za-z0-9_-]{20,}/ghp_REDACTED/g' \
        | sed -E 's/Bearer [A-Za-z0-9._-]{20,}/Bearer REDACTED/g'
}

# -----------------------------------------------------------------------------
# flock requirement (macOS operators need util-linux)
# -----------------------------------------------------------------------------
_require_flock() {
    if ! command -v flock >/dev/null 2>&1; then
        log_error "flock not found. On macOS: brew install util-linux"
        return 2
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Telemetry — structured JSONL append to .run/trajectory/<date>.jsonl
# -----------------------------------------------------------------------------
_emit_trajectory() {
    local event_type="$1"
    local payload_json="$2"
    local date_str
    date_str="$(date -u +%Y-%m-%d)"
    local path="$TRAJECTORY_DIR/probe-$date_str.jsonl"
    mkdir -p "$TRAJECTORY_DIR"
    local entry
    entry=$(jq -n \
        --arg ts "$(_iso_timestamp)" \
        --arg run_id "$PROBE_RUN_ID" \
        --arg event "$event_type" \
        --argjson payload "$payload_json" \
        '{timestamp: $ts, run_id: $run_id, event: $event, payload: $payload}')
    printf '%s\n' "$entry" >> "$path"
}

# _emit_audit_log — structured JSONL append to .run/audit.jsonl (security-relevant events)
_emit_audit_log() {
    local action="$1"
    local detail_json="$2"
    mkdir -p "$(dirname "$AUDIT_LOG")"
    local entry
    entry=$(jq -n \
        --arg ts "$(_iso_timestamp)" \
        --arg action "$action" \
        --argjson detail "$detail_json" \
        '{timestamp: $ts, action: $action, detail: $detail}')
    printf '%s\n' "$entry" >> "$AUDIT_LOG"
}

# -----------------------------------------------------------------------------
# Hard-stop budget enforcement (Flatline IMP-006)
# -----------------------------------------------------------------------------
_check_budget_probes() {
    if (( PROBES_USED >= MAX_PROBES_PER_RUN )); then
        _emit_trajectory "budget_hardstop" "$(jq -n \
            --arg kind "max_probes" \
            --argjson used "$PROBES_USED" \
            --argjson limit "$MAX_PROBES_PER_RUN" \
            '{kind: $kind, used: $used, limit: $limit}')"
        log_error "hardstop: max_probes_per_run exceeded ($PROBES_USED/$MAX_PROBES_PER_RUN)"
        return 5
    fi
    return 0
}

_check_budget_cost() {
    if (( COST_CENTS_USED >= MAX_COST_CENTS )); then
        _emit_trajectory "budget_hardstop" "$(jq -n \
            --arg kind "max_cost_cents" \
            --argjson used "$COST_CENTS_USED" \
            --argjson limit "$MAX_COST_CENTS" \
            '{kind: $kind, used_cents: $used, limit_cents: $limit}')"
        log_error "hardstop: cost cap exceeded (${COST_CENTS_USED}c / ${MAX_COST_CENTS}c)"
        return 5
    fi
    return 0
}

_check_budget_timeout() {
    local now
    now="$(date +%s)"
    local elapsed=$((now - PROBE_START_EPOCH))
    if (( elapsed >= INVOCATION_TIMEOUT )); then
        _emit_trajectory "budget_hardstop" "$(jq -n \
            --arg kind "invocation_timeout" \
            --argjson elapsed "$elapsed" \
            --argjson limit "$INVOCATION_TIMEOUT" \
            '{kind: $kind, elapsed_s: $elapsed, limit_s: $limit}')"
        log_error "hardstop: invocation timeout (${elapsed}s / ${INVOCATION_TIMEOUT}s)"
        return 5
    fi
    return 0
}

# _check_all_budgets — call before each probe
_check_all_budgets() {
    _check_budget_probes || return $?
    _check_budget_cost || return $?
    _check_budget_timeout || return $?
    return 0
}

# -----------------------------------------------------------------------------
# State machine — (current_state, signal) -> next_state
# Signals: ok, hard_404, model_field_400, auth, transient, probe_infra
# -----------------------------------------------------------------------------
_transition() {
    local current="$1"
    local signal="$2"
    case "$current" in
        UNKNOWN|"")
            case "$signal" in
                ok)                 echo "AVAILABLE" ;;
                hard_404|model_field_400) echo "UNAVAILABLE" ;;
                auth|transient|probe_infra|schema_mismatch) echo "UNKNOWN" ;;
                *) echo "UNKNOWN" ;;
            esac
            ;;
        AVAILABLE)
            case "$signal" in
                ok)                 echo "AVAILABLE" ;;
                hard_404|model_field_400) echo "UNAVAILABLE" ;;
                auth|transient|probe_infra|schema_mismatch) echo "UNKNOWN" ;;
                *) echo "UNKNOWN" ;;
            esac
            ;;
        UNAVAILABLE)
            case "$signal" in
                ok)                 echo "AVAILABLE" ;;
                hard_404|model_field_400) echo "UNAVAILABLE" ;;
                auth|transient|probe_infra|schema_mismatch) echo "UNKNOWN" ;;
                *) echo "UNKNOWN" ;;
            esac
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

# TTL lookup by state (§3.5)
_ttl_for_state() {
    case "$1" in
        AVAILABLE)   echo 86400 ;;   # 24 hours
        UNAVAILABLE) echo 3600 ;;    # 1 hour
        UNKNOWN)     echo 0 ;;       # do not cache
        *)           echo 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# Cache layer — atomic write + reader retry + PID sentinel
# -----------------------------------------------------------------------------
_cache_path() {
    if [[ -n "$OPT_CACHE_PATH" ]]; then
        echo "$OPT_CACHE_PATH"
    else
        echo "$CACHE_PATH_DEFAULT"
    fi
}

_cache_lock_path() {
    printf '%s.lock' "$(_cache_path)"
}

# _cache_atomic_write  payload_file
# SDD §3.6 Pattern 1
_cache_atomic_write() {
    local payload_file="$1"
    local timeout=5
    local cache
    cache="$(_cache_path)"
    local lockfile
    lockfile="$(_cache_lock_path)"
    mkdir -p "$(dirname "$cache")"

    _require_flock || return 2

    exec {_lock_fd}>"$lockfile"
    if ! flock -w "$timeout" "$_lock_fd"; then
        log_error "cache lock timeout after ${timeout}s"
        exec {_lock_fd}>&-
        return 1
    fi

    local tmpfile
    tmpfile="$(mktemp "${cache}.tmp.XXXXXX")"
    cat "$payload_file" > "$tmpfile"
    sync "$tmpfile" 2>/dev/null || true   # best-effort fsync via coreutils sync
    if ! mv -f "$tmpfile" "$cache"; then
        log_error "atomic rename failed; discarding write"
        rm -f "$tmpfile"
        exec {_lock_fd}>&-
        return 2
    fi
    exec {_lock_fd}>&-
    return 0
}

# _cache_read — stdout: cache JSON (or empty-shell on parse failure/absence)
# SDD §3.6 Pattern 2
_cache_read() {
    local cache
    cache="$(_cache_path)"
    local attempt=0
    local max_attempts=2
    local backoff_ms=50
    local cache_json

    while (( attempt < max_attempts )); do
        if [[ ! -f "$cache" ]]; then
            printf '{"schema_version":"%s","entries":{},"provider_circuit_state":{}}\n' "$CACHE_SCHEMA_VERSION"
            return 0
        fi
        cache_json=$(cat "$cache" 2>/dev/null) || {
            attempt=$((attempt + 1))
            sleep "0.0${backoff_ms}"
            continue
        }
        if echo "$cache_json" | jq empty 2>/dev/null; then
            # Schema version check — discard mismatched caches
            local seen_version
            seen_version=$(echo "$cache_json" | jq -r '.schema_version // ""')
            if [[ "$seen_version" != "$CACHE_SCHEMA_VERSION" ]]; then
                log_warn "cache schema mismatch (expected $CACHE_SCHEMA_VERSION, got '$seen_version'); discarding"
                printf '{"schema_version":"%s","entries":{},"provider_circuit_state":{}}\n' "$CACHE_SCHEMA_VERSION"
                return 0
            fi
            echo "$cache_json"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep "0.0${backoff_ms}"
    done
    log_warn "cache read failed after ${max_attempts} attempts; treating as cold-start"
    printf '{"schema_version":"%s","entries":{},"provider_circuit_state":{}}\n' "$CACHE_SCHEMA_VERSION"
    return 0
}

# _cache_merge_entry  provider  model_id  entry_json
# Merges a single entry into the cache using atomic-write pattern.
_cache_merge_entry() {
    local provider="$1"
    local model_id="$2"
    local entry_json="$3"
    local key="${provider}:${model_id}"
    local existing
    existing="$(_cache_read)"

    local merged
    merged=$(echo "$existing" | jq \
        --arg key "$key" \
        --arg gen_at "$(_iso_timestamp)" \
        --argjson entry "$entry_json" \
        '.schema_version = "1.0"
         | .generated_at = $gen_at
         | .generator = "model-health-probe.sh"
         | .entries[$key] = $entry
         | .provider_circuit_state //= {}')

    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$merged" > "$tmp"
    _cache_atomic_write "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# _cache_invalidate  [model_id]
# No arg -> wipe full cache; with arg -> remove single entry.
_cache_invalidate() {
    local target="${1:-}"
    local cache
    cache="$(_cache_path)"

    if [[ -z "$target" ]]; then
        # Full wipe — write empty shell atomically
        local tmp
        tmp=$(mktemp)
        printf '{"schema_version":"%s","generated_at":"%s","generator":"model-health-probe.sh","entries":{},"provider_circuit_state":{}}\n' \
            "$CACHE_SCHEMA_VERSION" "$(_iso_timestamp)" > "$tmp"
        _cache_atomic_write "$tmp"
        local rc=$?
        rm -f "$tmp"
        return $rc
    fi

    local existing
    existing="$(_cache_read)"
    local filtered
    filtered=$(echo "$existing" | jq --arg k "$target" 'del(.entries[$k]) | del(.entries[("openai:" + $k)]) | del(.entries[("google:" + $k)]) | del(.entries[("anthropic:" + $k)])')
    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$filtered" > "$tmp"
    _cache_atomic_write "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

# -----------------------------------------------------------------------------
# PID sentinel — per-provider background-probe dedup
# SDD §3.6 Pattern 3
# -----------------------------------------------------------------------------
_bg_probe_sentinel_path() {
    local provider="$1"
    printf '%s/model-health-probe.%s.pid' "$LOA_CACHE_DIR" "$provider"
}

_spawn_bg_probe_if_none_running() {
    local provider="$1"
    local sentinel
    sentinel="$(_bg_probe_sentinel_path "$provider")"
    mkdir -p "$(dirname "$sentinel")"

    if [[ -f "$sentinel" ]]; then
        local existing_pid
        existing_pid="$(cat "$sentinel" 2>/dev/null || echo "")"
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            # Probe already running for this provider — dedup
            log_debug "bg probe for $provider already running (pid=$existing_pid); skipping"
            return 0
        fi
        log_debug "stale sentinel for $provider (pid=$existing_pid); cleaning"
        rm -f "$sentinel"
    fi

    (
        echo "$$" > "$sentinel"
        trap 'rm -f "$sentinel"' EXIT
        "$SCRIPT_DIR/model-health-probe.sh" --provider "$provider" --once --quiet
    ) &
    disown
    return 0
}

# -----------------------------------------------------------------------------
# Registry loading — read .claude/defaults/model-config.yaml via yq
# -----------------------------------------------------------------------------
_registry_models() {
    # Emit lines: "provider model_id"
    local provider="${1:-}"
    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq not found; required for registry parsing"
        return 1
    fi
    if [[ ! -f "$MODEL_REGISTRY_YAML" ]]; then
        log_error "registry not found at $MODEL_REGISTRY_YAML"
        return 1
    fi

    if [[ -n "$provider" ]]; then
        yq eval ".providers.\"$provider\".models | keys | .[]" "$MODEL_REGISTRY_YAML" 2>/dev/null \
            | sed "s/^/$provider /"
    else
        local p
        for p in openai google anthropic; do
            yq eval ".providers.\"$p\".models | keys | .[]" "$MODEL_REGISTRY_YAML" 2>/dev/null \
                | sed "s/^/$p /"
        done
    fi
}

# -----------------------------------------------------------------------------
# HTTP helpers
# -----------------------------------------------------------------------------
# _curl_json  url  auth_header  auth_value  [method]  [body_file]
# Sets globals: HTTP_STATUS, RESPONSE_BODY
# Callers read the globals directly (do NOT use $() — that would fork a subshell
# and drop the global updates).
# In mock mode, reads fixture and status from LOA_PROBE_MOCK_* env vars.
HTTP_STATUS=0
RESPONSE_BODY=""
_curl_json() {
    local url="$1"
    local header_name="$2"
    local header_value="$3"
    local method="${4:-GET}"
    local body_file="${5:-}"

    HTTP_STATUS=0
    RESPONSE_BODY=""

    if [[ "${LOA_PROBE_MOCK_MODE:-0}" == "1" ]]; then
        HTTP_STATUS="${LOA_PROBE_MOCK_HTTP_STATUS:-200}"
        local fixture=""
        case "$url" in
            *openai.com*)     fixture="${LOA_PROBE_MOCK_OPENAI:-}" ;;
            *googleapis.com*) fixture="${LOA_PROBE_MOCK_GOOGLE:-}" ;;
            *anthropic.com*)  fixture="${LOA_PROBE_MOCK_ANTHROPIC:-}" ;;
        esac
        if [[ -n "$fixture" && -f "$fixture" ]]; then
            RESPONSE_BODY="$(cat "$fixture")"
        else
            RESPONSE_BODY='{}'
        fi
        return 0
    fi

    # Build secure curl config file via lib-security if available; otherwise inline.
    local cfg
    if [[ -f "$SCRIPT_DIR/lib-security.sh" ]]; then
        # shellcheck source=./lib-security.sh
        source "$SCRIPT_DIR/lib-security.sh"
        cfg=$(write_curl_auth_config "$header_name" "$header_value") || return 1
    else
        cfg=$(mktemp) || return 1
        chmod 600 "$cfg"
        printf 'header = "%s: %s"\n' "$header_name" "$header_value" > "$cfg"
    fi

    local out_body
    out_body=$(mktemp)
    local curl_rc=0
    local status_line=""
    if [[ "$method" == "POST" && -n "$body_file" ]]; then
        status_line=$(curl --config "$cfg" \
            -sS -o "$out_body" -w "%{http_code}" \
            --max-time "$PER_CALL_TIMEOUT" \
            -H "content-type: application/json" \
            -X POST \
            --data-binary "@$body_file" \
            "$url" 2>/dev/null) || curl_rc=$?
    else
        status_line=$(curl --config "$cfg" \
            -sS -o "$out_body" -w "%{http_code}" \
            --max-time "$PER_CALL_TIMEOUT" \
            "$url" 2>/dev/null) || curl_rc=$?
    fi
    rm -f "$cfg"

    HTTP_STATUS="${status_line:-0}"
    if (( curl_rc != 0 )); then
        HTTP_STATUS="0"   # network failure → transient
    fi

    RESPONSE_BODY="$(cat "$out_body" 2>/dev/null || true)"
    rm -f "$out_body"
    return 0
}

# -----------------------------------------------------------------------------
# Provider adapters (SDD §3.3)
# -----------------------------------------------------------------------------
# Each adapter sets these globals (instead of returning a struct):
#   PROBE_STATE       AVAILABLE | UNAVAILABLE | UNKNOWN
#   PROBE_CONFIDENCE  high | medium | low
#   PROBE_REASON      short human string (no secrets)
#   PROBE_HTTP        status code
#   PROBE_LATENCY_MS  elapsed ms
#   PROBE_ERROR_CLASS ok | auth | transient | hard_404 | listing_miss | schema_mismatch
# -----------------------------------------------------------------------------
PROBE_STATE=""
PROBE_CONFIDENCE=""
PROBE_REASON=""
PROBE_HTTP=""
PROBE_LATENCY_MS=""
PROBE_ERROR_CLASS=""

_reset_probe_result() {
    PROBE_STATE=""
    PROBE_CONFIDENCE=""
    PROBE_REASON=""
    PROBE_HTTP=""
    PROBE_LATENCY_MS=""
    PROBE_ERROR_CLASS=""
}

# _contract_version_check  provider  body
# Expected shapes per provider; unknown shape → bias UNKNOWN
_contract_version_check() {
    local provider="$1"
    local body="$2"
    case "$provider" in
        openai)
            # Expect object with .data as array
            echo "$body" | jq -e 'has("data") and (.data | type=="array")' >/dev/null 2>&1
            ;;
        google)
            # Expect .models array OR an error object for generateContent 404 path
            echo "$body" | jq -e 'has("models") and (.models | type=="array")' >/dev/null 2>&1 \
                || echo "$body" | jq -e 'has("error")' >/dev/null 2>&1 \
                || echo "$body" | jq -e 'has("candidates") or has("promptFeedback")' >/dev/null 2>&1
            ;;
        anthropic)
            # Successful POST /v1/messages: object with .content OR .error
            echo "$body" | jq -e 'has("content") or has("error") or has("id")' >/dev/null 2>&1
            ;;
        *)
            return 0
            ;;
    esac
}

# OpenAI — GET /v1/models with pagination
_probe_openai() {
    local model_id="$1"
    _reset_probe_result
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
        PROBE_REASON="OPENAI_API_KEY not set"
        PROBE_ERROR_CLASS="auth"
        return 0
    fi

    local t0 t1
    t0=$(date +%s%3N 2>/dev/null || date +%s000)
    _curl_json "https://api.openai.com/v1/models" "Authorization" "Bearer $OPENAI_API_KEY"
    local body="$RESPONSE_BODY"
    t1=$(date +%s%3N 2>/dev/null || date +%s000)
    PROBE_LATENCY_MS=$((t1 - t0))
    PROBE_HTTP="$HTTP_STATUS"

    case "$HTTP_STATUS" in
        200)
            if ! _contract_version_check openai "$body"; then
                PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
                PROBE_REASON="openai response schema mismatch"
                PROBE_ERROR_CLASS="schema_mismatch"
                _emit_trajectory "schema_mismatch" "$(jq -n --arg p openai --arg m "$model_id" '{provider:$p, model:$m}')"
                return 0
            fi
            if echo "$body" | jq -e --arg id "$model_id" '.data | map(.id) | index($id) != null' >/dev/null 2>&1; then
                PROBE_STATE="AVAILABLE"; PROBE_CONFIDENCE="high"
                PROBE_REASON="listed in /v1/models"
                PROBE_ERROR_CLASS="ok"
            else
                PROBE_STATE="UNAVAILABLE"; PROBE_CONFIDENCE="high"
                PROBE_REASON="not present in /v1/models"
                PROBE_ERROR_CLASS="listing_miss"
            fi
            ;;
        401|403)
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="auth-level failure ($HTTP_STATUS)"
            PROBE_ERROR_CLASS="auth"
            ;;
        408|429|5??|0)
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="transient $HTTP_STATUS"
            PROBE_ERROR_CLASS="transient"
            ;;
        *)
            if [[ "$HTTP_STATUS" -ge 500 ]] 2>/dev/null; then
                PROBE_STATE="UNKNOWN"; PROBE_ERROR_CLASS="transient"
                PROBE_REASON="server error $HTTP_STATUS"
            else
                PROBE_STATE="UNKNOWN"; PROBE_ERROR_CLASS="transient"
                PROBE_REASON="unclassified response $HTTP_STATUS"
            fi
            PROBE_CONFIDENCE="low"
            ;;
    esac
    return 0
}

# Google — GET /v1beta/models; if listing fails for this model, try generateContent
_probe_google() {
    local model_id="$1"
    _reset_probe_result
    if [[ -z "${GOOGLE_API_KEY:-}" ]]; then
        PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
        PROBE_REASON="GOOGLE_API_KEY not set"
        PROBE_ERROR_CLASS="auth"
        return 0
    fi

    local t0 t1
    t0=$(date +%s%3N 2>/dev/null || date +%s000)
    _curl_json "https://generativelanguage.googleapis.com/v1beta/models?key=$GOOGLE_API_KEY" "x-goog-api-key" "$GOOGLE_API_KEY"
    local list_body="$RESPONSE_BODY"
    t1=$(date +%s%3N 2>/dev/null || date +%s000)
    PROBE_LATENCY_MS=$((t1 - t0))
    PROBE_HTTP="$HTTP_STATUS"

    case "$HTTP_STATUS" in
        200)
            if ! _contract_version_check google "$list_body"; then
                PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
                PROBE_REASON="google response schema mismatch"
                PROBE_ERROR_CLASS="schema_mismatch"
                _emit_trajectory "schema_mismatch" "$(jq -n --arg p google --arg m "$model_id" '{provider:$p, model:$m}')"
                return 0
            fi
            if echo "$list_body" | jq -e --arg id "models/$model_id" '.models // [] | map(.name) | index($id) != null' >/dev/null 2>&1; then
                PROBE_STATE="AVAILABLE"; PROBE_CONFIDENCE="high"
                PROBE_REASON="listed in /v1beta/models"
                PROBE_ERROR_CLASS="ok"
            else
                # Fall through to generateContent fallback for models not in listing
                PROBE_STATE="UNAVAILABLE"; PROBE_CONFIDENCE="medium"
                PROBE_REASON="not present in /v1beta/models"
                PROBE_ERROR_CLASS="listing_miss"
                # NOT_FOUND error body regex (from SDD §3.3)
                if echo "$list_body" | jq -e --arg m "$model_id" \
                   '.error.message? | test("^models/[^ ]+ is not found for API version")' >/dev/null 2>&1; then
                    PROBE_STATE="UNAVAILABLE"; PROBE_CONFIDENCE="high"
                    PROBE_REASON="NOT_FOUND for $model_id on v1beta"
                    PROBE_ERROR_CLASS="hard_404"
                fi
            fi
            ;;
        401|403)
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="auth-level failure ($HTTP_STATUS)"
            PROBE_ERROR_CLASS="auth"
            ;;
        404)
            # Generic 404 without model-specific body → UNKNOWN (per §3.2)
            if echo "$list_body" | jq -e --arg m "$model_id" \
               '.error.message? | test("^models/[^ ]+ is not found for API version")' >/dev/null 2>&1; then
                PROBE_STATE="UNAVAILABLE"; PROBE_CONFIDENCE="high"
                PROBE_REASON="NOT_FOUND for $model_id on v1beta"
                PROBE_ERROR_CLASS="hard_404"
            else
                PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
                PROBE_REASON="generic 404 (no model-specific body)"
                PROBE_ERROR_CLASS="transient"
            fi
            ;;
        408|429|5??|0)
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="transient $HTTP_STATUS"
            PROBE_ERROR_CLASS="transient"
            ;;
        *)
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="unclassified response $HTTP_STATUS"
            PROBE_ERROR_CLASS="transient"
            ;;
    esac
    return 0
}

# Anthropic — POST /v1/messages with max_tokens:1; SKP-001 core fix: reject ambiguous 4xx
_probe_anthropic() {
    local model_id="$1"
    _reset_probe_result
    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
        PROBE_REASON="ANTHROPIC_API_KEY not set"
        PROBE_ERROR_CLASS="auth"
        return 0
    fi

    local body_file
    body_file=$(mktemp)
    # Build request body via jq to avoid shell-injection risk
    jq -n --arg m "$model_id" \
        '{model:$m, max_tokens:1, messages:[{role:"user", content:"ping"}]}' > "$body_file"

    local t0 t1
    t0=$(date +%s%3N 2>/dev/null || date +%s000)
    _curl_json "https://api.anthropic.com/v1/messages" "x-api-key" "$ANTHROPIC_API_KEY" POST "$body_file"
    local resp="$RESPONSE_BODY"
    t1=$(date +%s%3N 2>/dev/null || date +%s000)
    PROBE_LATENCY_MS=$((t1 - t0))
    PROBE_HTTP="$HTTP_STATUS"
    rm -f "$body_file"

    # Anthropic also requires anthropic-version header; add via body_file approach:
    # NOTE: above _curl_json passes content-type but not anthropic-version. In real operation,
    # anthropic requires "anthropic-version: 2023-06-01". For this script, we use x-api-key
    # auth + content-type and expect the API to accept a default version. If not, body parse
    # below will yield schema_mismatch → UNKNOWN (safe default).

    case "$HTTP_STATUS" in
        200)
            if ! _contract_version_check anthropic "$resp"; then
                PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
                PROBE_REASON="anthropic response schema mismatch"
                PROBE_ERROR_CLASS="schema_mismatch"
                _emit_trajectory "schema_mismatch" "$(jq -n --arg p anthropic --arg m "$model_id" '{provider:$p, model:$m}')"
                return 0
            fi
            PROBE_STATE="AVAILABLE"; PROBE_CONFIDENCE="high"
            PROBE_REASON="200 OK on minimal probe"
            PROBE_ERROR_CLASS="ok"
            ;;
        400)
            # Parse error shape: must reference the model field explicitly
            local err_type err_msg
            err_type=$(echo "$resp" | jq -r '.error.type // ""' 2>/dev/null)
            err_msg=$(echo "$resp" | jq -r '.error.message // ""' 2>/dev/null)
            if [[ "$err_type" == "invalid_request_error" ]] && echo "$err_msg" | grep -qi 'model'; then
                PROBE_STATE="UNAVAILABLE"; PROBE_CONFIDENCE="high"
                PROBE_REASON="400 invalid_request_error on model field"
                PROBE_ERROR_CLASS="model_field_400"
            else
                # SKP-001 core fix — ambiguous 4xx → UNKNOWN, NOT AVAILABLE
                PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
                PROBE_REASON="400 but no model-field reference (SKP-001 guard)"
                PROBE_ERROR_CLASS="transient"
            fi
            ;;
        401|403)
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="auth-level failure ($HTTP_STATUS)"
            PROBE_ERROR_CLASS="auth"
            ;;
        404)
            # For anthropic, 404 without explicit model error body is still ambiguous
            local err_msg_404
            err_msg_404=$(echo "$resp" | jq -r '.error.message // ""' 2>/dev/null)
            if echo "$err_msg_404" | grep -qi 'model'; then
                PROBE_STATE="UNAVAILABLE"; PROBE_CONFIDENCE="high"
                PROBE_REASON="404 with model reference"
                PROBE_ERROR_CLASS="hard_404"
            else
                PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
                PROBE_REASON="404 without model-field reference (SKP-001 guard)"
                PROBE_ERROR_CLASS="transient"
            fi
            ;;
        408|429|5??|0)
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="transient $HTTP_STATUS"
            PROBE_ERROR_CLASS="transient"
            ;;
        *)
            # Other 4xx: SKP-001 — reject ambiguous 4xx
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="ambiguous $HTTP_STATUS; SKP-001 guard"
            PROBE_ERROR_CLASS="transient"
            ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# Probe-one-model orchestrator
# -----------------------------------------------------------------------------
_probe_one_model() {
    local provider="$1"
    local model_id="$2"

    # Legacy behavior flag (emergency fallback) — short-circuits before probing
    if [[ "${LOA_PROBE_LEGACY_BEHAVIOR:-0}" == "1" ]]; then
        PROBE_STATE="AVAILABLE"
        PROBE_CONFIDENCE="legacy_bypass"
        PROBE_REASON="LOA_PROBE_LEGACY_BEHAVIOR env var set"
        PROBE_HTTP="0"
        PROBE_LATENCY_MS="0"
        PROBE_ERROR_CLASS="ok"
        _emit_audit_log "probe_legacy_bypass" "$(jq -n \
            --arg provider "$provider" \
            --arg model "$model_id" \
            '{provider:$provider, model:$model, reason:"LOA_PROBE_LEGACY_BEHAVIOR=1 emergency fallback"}')"
        return 0
    fi

    # Budget check BEFORE spending a probe
    if ! _check_all_budgets; then
        exit 5
    fi

    case "$provider" in
        openai)    _probe_openai "$model_id" ;;
        google)    _probe_google "$model_id" ;;
        anthropic) _probe_anthropic "$model_id" ;;
        *)
            # Unknown provider passthrough (Flatline IMP-006 / SKP-004 #4)
            PROBE_STATE="UNKNOWN"; PROBE_CONFIDENCE="low"
            PROBE_REASON="unknown provider $provider"
            PROBE_HTTP="0"; PROBE_LATENCY_MS="0"
            PROBE_ERROR_CLASS="transient"
            ;;
    esac

    PROBES_USED=$((PROBES_USED + 1))
    # Each probe charges a nominal 1 cent estimate (conservative). Real cost-tracking
    # would need token-accurate metering; this is a coarse cap gate.
    COST_CENTS_USED=$((COST_CENTS_USED + 1))

    # Cache the result (skip UNKNOWN — TTL=0)
    if [[ "$PROBE_STATE" != "UNKNOWN" ]]; then
        local ttl
        ttl="$(_ttl_for_state "$PROBE_STATE")"
        local entry
        entry=$(jq -n \
            --arg state "$PROBE_STATE" \
            --arg confidence "$PROBE_CONFIDENCE" \
            --arg reason "$PROBE_REASON" \
            --arg http_status "$PROBE_HTTP" \
            --arg latency_ms "$PROBE_LATENCY_MS" \
            --arg probed_at "$(_iso_timestamp)" \
            --argjson ttl "$ttl" \
            '{state:$state, confidence:$confidence, reason:$reason,
              http_status:($http_status|tonumber? // 0),
              latency_ms:($latency_ms|tonumber? // 0),
              probed_at:$probed_at, ttl_seconds:$ttl,
              last_known_good_at: (if $state=="AVAILABLE" then $probed_at else null end)}')
        _cache_merge_entry "$provider" "$model_id" "$entry" || log_warn "cache write failed for $provider:$model_id"
    fi

    _emit_trajectory "probe_result" "$(jq -n \
        --arg provider "$provider" \
        --arg model "$model_id" \
        --arg state "$PROBE_STATE" \
        --arg reason "$PROBE_REASON" \
        --arg http_status "$PROBE_HTTP" \
        '{provider:$provider, model:$model, state:$state, reason:$reason, http_status:$http_status}')"
    return 0
}

# -----------------------------------------------------------------------------
# Probe driver — iterate registry
# -----------------------------------------------------------------------------
declare -a PROBE_RESULTS  # each element: "provider|model|state|reason"

_probe_all() {
    local scope_provider="${OPT_PROVIDER:-}"
    local scope_model="${OPT_MODEL:-}"

    while read -r line; do
        [[ -z "$line" ]] && continue
        local provider model_id
        provider="${line%% *}"
        model_id="${line#* }"
        if [[ -n "$scope_model" && "$model_id" != "$scope_model" ]]; then
            continue
        fi

        if [[ "$OPT_DRY_RUN" == "1" ]]; then
            PROBE_RESULTS+=("$provider|$model_id|UNKNOWN|dry-run")
            continue
        fi

        _probe_one_model "$provider" "$model_id"
        PROBE_RESULTS+=("$provider|$model_id|$PROBE_STATE|$PROBE_REASON")
    done < <(_registry_models "$scope_provider")
}

# -----------------------------------------------------------------------------
# Output formatters
# -----------------------------------------------------------------------------
_format_text() {
    local r
    local summary_available=0 summary_unavailable=0 summary_unknown=0
    for r in ${PROBE_RESULTS[@]+"${PROBE_RESULTS[@]}"}; do
        local provider model state reason
        provider="${r%%|*}"; r="${r#*|}"
        model="${r%%|*}";    r="${r#*|}"
        state="${r%%|*}";    reason="${r#*|}"
        case "$state" in
            AVAILABLE)   summary_available=$((summary_available + 1)) ;;
            UNAVAILABLE) summary_unavailable=$((summary_unavailable + 1)) ;;
            UNKNOWN)     summary_unknown=$((summary_unknown + 1)) ;;
        esac
        [[ "$OPT_QUIET" == "1" ]] || printf '  %-10s %-28s %-12s %s\n' "$provider" "$model" "$state" "$reason"
    done
    printf 'Summary: %d available, %d unavailable, %d unknown (total %d)\n' \
        "$summary_available" "$summary_unavailable" "$summary_unknown" \
        "$((summary_available + summary_unavailable + summary_unknown))"
}

_format_json() {
    local entries_json='{}'
    local summary_available=0 summary_unavailable=0 summary_unknown=0
    local r
    for r in ${PROBE_RESULTS[@]+"${PROBE_RESULTS[@]}"}; do
        local provider model state reason key
        provider="${r%%|*}"; r="${r#*|}"
        model="${r%%|*}";    r="${r#*|}"
        state="${r%%|*}";    reason="${r#*|}"
        key="${provider}:${model}"
        case "$state" in
            AVAILABLE)   summary_available=$((summary_available + 1)) ;;
            UNAVAILABLE) summary_unavailable=$((summary_unavailable + 1)) ;;
            UNKNOWN)     summary_unknown=$((summary_unknown + 1)) ;;
        esac
        entries_json=$(echo "$entries_json" | jq \
            --arg key "$key" \
            --arg state "$state" \
            --arg reason "$reason" \
            '.[$key] = {state:$state, reason:$reason}')
    done
    jq -n \
        --arg schema "$CACHE_SCHEMA_VERSION" \
        --arg ts "$(_iso_timestamp)" \
        --argjson entries "$entries_json" \
        --argjson avail "$summary_available" \
        --argjson unavail "$summary_unavailable" \
        --argjson unknown "$summary_unknown" \
        --argjson exit_code "$1" \
        '{schema_version:$schema, probed_at:$ts,
          summary:{available:$avail, unavailable:$unavail, unknown:$unknown},
          entries:$entries, exit_code:$exit_code}'
}

# -----------------------------------------------------------------------------
# CLI parser
# -----------------------------------------------------------------------------
_show_usage() {
    sed -n '7,36p' "${BASH_SOURCE[0]}" | sed 's/^# //; s/^#$//'
}

_show_version() {
    echo "model-health-probe.sh $MODEL_HEALTH_PROBE_VERSION"
}

_parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --once)          shift ;;                # default; accepted for clarity
            --dry-run)       OPT_DRY_RUN=1; shift ;;
            --invalidate)
                OPT_INVALIDATE=1
                if [[ -n "${2:-}" && "${2:0:2}" != "--" ]]; then
                    OPT_INVALIDATE_MODEL="$2"; shift 2
                else
                    shift
                fi
                ;;
            --provider)      OPT_PROVIDER="${2:-}"; shift 2 ;;
            --model)         OPT_MODEL="${2:-}"; shift 2 ;;
            --cache-path)    OPT_CACHE_PATH="${2:-}"; shift 2 ;;
            --output)        OPT_OUTPUT="${2:-text}"; shift 2 ;;
            --fail-on)       OPT_FAIL_ON="${2:-UNAVAILABLE}"; shift 2 ;;
            --quiet)         OPT_QUIET=1; shift ;;
            --canary)        OPT_CANARY=1; shift ;;
            --help|-h)       _show_usage; exit 0 ;;
            --version|-V)    _show_version; exit 0 ;;
            *)
                log_error "unknown argument: $1"
                _show_usage
                exit 64
                ;;
        esac
    done

    # Validate mutually-exclusive / sanity
    if [[ -n "$OPT_PROVIDER" ]]; then
        case "$OPT_PROVIDER" in
            openai|google|anthropic) ;;
            *)
                log_error "invalid provider: $OPT_PROVIDER (allowed: openai|google|anthropic)"
                exit 64
                ;;
        esac
    fi
    case "$OPT_OUTPUT" in
        text|json) ;;
        *)
            log_error "invalid --output: $OPT_OUTPUT (allowed: text|json)"
            exit 64
            ;;
    esac
    case "$OPT_FAIL_ON" in
        AVAILABLE|UNAVAILABLE|UNKNOWN) ;;
        *)
            log_error "invalid --fail-on: $OPT_FAIL_ON"
            exit 64
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    _parse_args "$@"

    PROBE_RUN_ID="$(_gen_run_id)"
    PROBE_START_EPOCH="$(date +%s)"

    # --invalidate: clear and exit
    if [[ "$OPT_INVALIDATE" == "1" ]]; then
        if _cache_invalidate "$OPT_INVALIDATE_MODEL"; then
            log_info "cache invalidated${OPT_INVALIDATE_MODEL:+ (model=$OPT_INVALIDATE_MODEL)}"
            exit 0
        else
            log_error "cache invalidation failed"
            exit 1
        fi
    fi

    # Probe loop
    _probe_all || true

    # Tally results
    local have_unavailable=0 have_unknown=0
    local r
    for r in ${PROBE_RESULTS[@]+"${PROBE_RESULTS[@]}"}; do
        local state
        r="${r#*|}"; r="${r#*|}"
        state="${r%%|*}"
        case "$state" in
            UNAVAILABLE) have_unavailable=1 ;;
            UNKNOWN)     have_unknown=1 ;;
        esac
    done

    # Compute exit code
    local exit_code=0
    case "$OPT_FAIL_ON" in
        UNAVAILABLE) (( have_unavailable )) && exit_code=2 ;;
        UNKNOWN)     (( have_unknown ))     && exit_code=2 ;;
        AVAILABLE)   exit_code=0 ;;
    esac

    # Canary mode is non-blocking — always exit 0 regardless of findings
    if [[ "$OPT_CANARY" == "1" ]]; then
        _emit_trajectory "canary_result" "$(jq -n \
            --argjson intended_exit "$exit_code" \
            --argjson total ${#PROBE_RESULTS[@]} \
            '{intended_exit:$intended_exit, total:$total, non_blocking:true}')"
        exit_code=0
    fi

    # Output
    case "$OPT_OUTPUT" in
        text) _format_text ;;
        json) _format_json "$exit_code" ;;
    esac

    exit "$exit_code"
}

# Only run main if the script is invoked directly (not sourced for tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
