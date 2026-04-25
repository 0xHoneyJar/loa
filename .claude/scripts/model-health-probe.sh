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
# SCRIPT_DIR resolution: in real runs BASH_SOURCE[0] points to this file; under
# the sed-based bats source pattern (eval), BASH_SOURCE[0] points to the test
# file instead, which gives a wrong SCRIPT_DIR. Validate by looking for the
# probe script itself, and fall back to $PROJECT_ROOT/.claude/scripts otherwise.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
if [[ ! -f "$SCRIPT_DIR/model-health-probe.sh" && -n "${PROJECT_ROOT:-}" && -d "$PROJECT_ROOT/.claude/scripts" ]]; then
    SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
fi
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

# Centralized scrubber — Flatline sprint-review SKP-005 closure.
# All log/audit paths route through `_redact_secrets` from the shared library so
# regex updates land in one place. The library is idempotent-source-safe.
# shellcheck source=lib/secret-redaction.sh
source "$SCRIPT_DIR/lib/secret-redaction.sh"

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

# Cached capability detection for `flock -E <code>` (util-linux 2.26+).
# Returns 0 if `-E` is supported, 1 otherwise. Result memoized in
# _LOA_FLOCK_HAS_E so the help-grep only runs once per process.
# (cycle-094 review iter-4, DISS-202 fix.)
_flock_supports_dash_e() {
    if [[ -z "${_LOA_FLOCK_HAS_E:-}" ]]; then
        if flock --help 2>&1 | grep -q -- '--conflict-exit-code'; then
            _LOA_FLOCK_HAS_E=1
        else
            _LOA_FLOCK_HAS_E=0
        fi
    fi
    [[ "$_LOA_FLOCK_HAS_E" == "1" ]]
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
# Sprint 3B: extended with optional webhook fan-out (Flatline sprint-review SKP-003)
# and routes the entry through `_redact_secrets` as defense-in-depth.
_emit_audit_log() {
    local action="$1"
    local detail_json="$2"
    mkdir -p "$(dirname "$AUDIT_LOG")"
    local entry
    entry=$(jq -n \
        --arg ts "$(_iso_timestamp)" \
        --arg actor "${USER:-${GITHUB_ACTOR:-unknown}}" \
        --arg run_id "$PROBE_RUN_ID" \
        --arg action "$action" \
        --argjson detail "$detail_json" \
        '{timestamp: $ts, actor: $actor, run_id: $run_id, action: $action, detail: $detail}')
    # Redact ONCE — both the audit log and the webhook get the same scrubbed
    # payload (review iter-2 B-3 — defense-in-depth gap fix; previously the
    # webhook received the raw entry while the audit log got the redacted one).
    local redacted
    redacted="$(_redact_secrets "$entry")"
    printf '%s\n' "$redacted" >> "$AUDIT_LOG"

    # Optional webhook (Flatline sprint-review SKP-003 — alert fan-out).
    # Fire-and-forget; never block the probe on webhook latency.
    local webhook
    webhook="$(_config_get '.model_health_probe.alert_webhook_url' '')"
    if [[ -n "$webhook" ]]; then
        ( curl -sS -X POST -H "Content-Type: application/json" --data "$redacted" \
              --max-time 5 "$webhook" >/dev/null 2>&1 || true ) &
        disown 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Resilience layer (Sprint 3B — SDD §4.1, closes Flatline SKP-003/004 + SDD §3.5)
# -----------------------------------------------------------------------------
LOA_CONFIG="${LOA_CONFIG:-$PROJECT_ROOT/.loa.config.yaml}"
LOA_PROBE_BYPASS_TTL_HOURS="${LOA_PROBE_BYPASS_TTL_HOURS:-24}"
CIRCUIT_FAILURE_THRESHOLD=5
CIRCUIT_RESET_SECONDS=300

# _config_get KEY [DEFAULT] — read a value from .loa.config.yaml via yq.
# Returns DEFAULT (or empty) if config missing, key absent, or value null.
_config_get() {
    local key="$1" default="${2-}"
    if [[ -f "$LOA_CONFIG" ]] && command -v yq >/dev/null 2>&1; then
        local val
        val="$(yq eval "$key" "$LOA_CONFIG" 2>/dev/null)"
        if [[ -n "$val" && "$val" != "null" ]]; then
            printf '%s' "$val"
            return 0
        fi
    fi
    printf '%s' "$default"
}

# Feature flag (master switch). Default ON.
_probe_enabled() {
    local v
    v="$(_config_get '.model_health_probe.enabled' 'true')"
    [[ "$v" == "true" ]]
}

# degraded_ok behavior. Default ON — proceed with last-known-good when probe
# infra fails. When false, probe-infra failure with no usable cache is fatal.
_degraded_ok() {
    local v
    v="$(_config_get '.model_health_probe.degraded_ok' 'true')"
    [[ "$v" == "true" ]]
}

# Bypass governance: LOA_PROBE_BYPASS=1 with mandatory reason + 24h TTL.
# Returns:
#   0 — bypass active and valid; probe should be skipped
#   1 — no bypass requested; probe proceeds normally
#   2 — bypass requested but invalid (no reason); caller should error
_check_bypass() {
    [[ "${LOA_PROBE_BYPASS:-0}" == "1" ]] || return 1

    local reason="${LOA_PROBE_BYPASS_REASON:-}"
    if [[ -z "$reason" ]]; then
        log_error "LOA_PROBE_BYPASS=1 set without LOA_PROBE_BYPASS_REASON. Bypass denied; aborting."
        _emit_audit_log "probe_bypass_denied" "$(jq -n '{reason:"missing LOA_PROBE_BYPASS_REASON"}')"
        return 2
    fi

    local sentinel="$LOA_CACHE_DIR/probe-bypass.stamp"
    local now_epoch ttl_sec set_epoch
    now_epoch="$(date +%s)"
    ttl_sec=$(( LOA_PROBE_BYPASS_TTL_HOURS * 3600 ))

    if [[ -f "$sentinel" ]]; then
        set_epoch="$(head -n1 "$sentinel" 2>/dev/null || echo 0)"
        # Reject non-numeric content (review iter-2 S-1 — tamper resistance).
        [[ "$set_epoch" =~ ^[0-9]+$ ]] || set_epoch=0
        if [[ "$set_epoch" -gt 0 ]] && (( now_epoch - set_epoch < ttl_sec )); then
            local age=$(( now_epoch - set_epoch ))
            _emit_audit_log "probe_bypass_active" \
                "$(jq -n --arg reason "$reason" --argjson age "$age" \
                    '{reason:$reason, age_seconds:$age, ttl_hours:'"$LOA_PROBE_BYPASS_TTL_HOURS"'}')"
            return 0
        fi
        # TTL expired — clear and re-engage probe.
        log_warn "LOA_PROBE_BYPASS expired (>${LOA_PROBE_BYPASS_TTL_HOURS}h); re-engaging probe."
        rm -f "$sentinel"
        _emit_audit_log "probe_bypass_expired" \
            "$(jq -n --argjson age $((now_epoch - set_epoch)) '{age_seconds:$age}')"
        return 1
    fi

    # First time bypass requested in this TTL window — record stamp.
    mkdir -p "$LOA_CACHE_DIR"
    printf '%s\n' "$now_epoch" > "$sentinel"
    _emit_audit_log "probe_bypass_set" \
        "$(jq -n --arg reason "$reason" \
            '{reason:$reason, ttl_hours:'"$LOA_PROBE_BYPASS_TTL_HOURS"'}')"
    return 0
}

# _circuit_open_for PROVIDER — true if the circuit is OPEN (skip probe).
# Reads provider_circuit_state from cache; respects open_until ISO timestamp.
_circuit_open_for() {
    local provider="$1"
    local cache; cache="$(_cache_read 2>/dev/null)" || return 1
    local open_until
    open_until="$(printf '%s' "$cache" | jq -r --arg p "$provider" '.provider_circuit_state[$p].open_until // empty' 2>/dev/null)"
    [[ -z "$open_until" ]] && return 1
    local now ts
    now="$(date +%s)"
    ts="$(date -u -d "$open_until" +%s 2>/dev/null || \
         date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$open_until" +%s 2>/dev/null || \
         echo 0)"
    [[ "$ts" -eq 0 ]] && return 1
    (( now < ts ))
}

# Update circuit state in cache (read-modify-write under flock).
# DELTA: "failure" | "success"
_circuit_update() {
    local provider="$1" delta="$2"
    local cache_file; cache_file="$(_cache_path)"
    [[ -f "$cache_file" ]] || return 0

    _require_flock || return 1
    local lock="${cache_file}.lock"

    # bash-3.2 portability: macOS default bash does not support the named-fd
    # variable assignment form for the exec/redirect builtin. Use a subshell
    # with a hardcoded fd 9 instead (sprint-3B iter-4 — closes the
    # macos-latest CI matrix failure; cycle-094 G-2 sweep).
    (
        flock -w 5 9 || exit 1

        local now_iso updated tmp
        now_iso="$(_iso_timestamp)"
        if [[ "$delta" == "failure" ]]; then
            updated=$(jq --arg p "$provider" \
                --argjson threshold "$CIRCUIT_FAILURE_THRESHOLD" \
                --argjson reset "$CIRCUIT_RESET_SECONDS" \
                --arg now "$now_iso" '
                .provider_circuit_state //= {} |
                .provider_circuit_state[$p] //= {consecutive_failures:0, open_until:null} |
                .provider_circuit_state[$p].consecutive_failures += 1 |
                if .provider_circuit_state[$p].consecutive_failures >= $threshold then
                    .provider_circuit_state[$p].open_until =
                        (($now | fromdateiso8601) + $reset | todateiso8601)
                else . end' "$cache_file" 2>/dev/null) || exit 1
        else
            updated=$(jq --arg p "$provider" '
                .provider_circuit_state //= {} |
                .provider_circuit_state[$p] = {consecutive_failures:0, open_until:null}
            ' "$cache_file" 2>/dev/null) || exit 1
        fi
        tmp="$(mktemp "${cache_file}.tmp.XXXXXX")"
        printf '%s\n' "$updated" > "$tmp"
        sync "$tmp" 2>/dev/null || true
        mv -f "$tmp" "$cache_file"
    ) 9>"$lock"
}

# Staleness cutoff per SDD §3.5.
# Returns 0 if entry usable; 2 if past max_stale_hours AND !degraded_ok.
# Always emits audit alert at alert_on_stale_hours threshold.
_check_staleness() {
    local probed_at_iso="$1" model_id="${2:-unknown}"
    [[ -z "$probed_at_iso" || "$probed_at_iso" == "null" ]] && return 0

    local max_h alert_h
    max_h="$(_config_get '.model_health_probe.max_stale_hours' '72')"
    alert_h="$(_config_get '.model_health_probe.alert_on_stale_hours' '24')"

    local probed_epoch now age_h
    probed_epoch="$(date -u -d "$probed_at_iso" +%s 2>/dev/null || \
                   date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$probed_at_iso" +%s 2>/dev/null || \
                   echo 0)"
    [[ "$probed_epoch" -eq 0 ]] && return 0
    now="$(date +%s)"
    age_h=$(( (now - probed_epoch) / 3600 ))

    if (( age_h >= max_h )); then
        _emit_audit_log "cache_stale_cutoff" \
            "$(jq -n --arg model "$model_id" --argjson age "$age_h" --argjson cutoff "$max_h" \
                '{model_id:$model, age_hours:$age, cutoff_hours:$cutoff}')"
        _degraded_ok || return 2
    elif (( age_h >= alert_h )); then
        _emit_audit_log "cache_stale_alert" \
            "$(jq -n --arg model "$model_id" --argjson age "$age_h" --argjson alert "$alert_h" \
                '{model_id:$model, age_hours:$age, alert_hours:$alert}')"
    fi
    return 0
}

# Retry with exponential backoff + ±25% jitter (SDD §6.4).
# Usage: _retry_with_backoff <max_attempts> <command> [args...]
_retry_with_backoff() {
    local max_attempts="${1:-3}"; shift
    local attempt=0 delay=1 max_delay=16
    local rc=0
    while (( attempt < max_attempts )); do
        "$@" && return 0
        rc=$?
        attempt=$((attempt + 1))
        (( attempt >= max_attempts )) && return "$rc"
        # ±25% jitter computed in ms.
        local jitter_ms=$(( (RANDOM % (delay * 500 + 1)) - (delay * 250) ))
        local sleep_ms=$(( delay * 1000 + jitter_ms ))
        (( sleep_ms < 0 )) && sleep_ms=0
        local sleep_s
        sleep_s="$(awk -v ms="$sleep_ms" 'BEGIN{printf "%.3f", ms/1000}')"
        sleep "$sleep_s"
        delay=$(( delay * 2 ))
        (( delay > max_delay )) && delay=$max_delay
    done
    return "$rc"
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
    local cache_dir
    cache_dir="$(dirname "$cache")"

    # Pre-flight: ensure cache directory exists and is writable. Without this
    # check, the subshell `9>"$lockfile"` redirect below fails with a confusing
    # diagnostic (e.g. "_lock_fd: unbound variable" on bash variants that
    # promote the failed redirect into the named-fd context). Surface the
    # actionable cause directly. (cycle-094 G-3, closes #626.)
    if ! mkdir -p "$cache_dir" 2>/dev/null; then
        log_error "cache directory not writable: $cache_dir"
        return 1
    fi
    if [[ ! -w "$cache_dir" ]]; then
        log_error "cache directory not writable: $cache_dir"
        return 1
    fi

    _require_flock || return 2

    # bash-3.2 portability: macOS default bash does not support the named-fd
    # variable assignment form for the exec/redirect builtin. Use a subshell
    # with a hardcoded fd 9 instead (sprint-3B iter-4 — closes the
    # macos-latest CI matrix failure; cycle-094 G-2 sweep).
    # Compute -E args once outside the subshell so the capability check is
    # cached across the whole probe invocation, not re-checked per cache write.
    local flock_e_args=""
    if _flock_supports_dash_e; then
        flock_e_args="-E 1"
    fi

    local rc=0
    (
        # `-E 1` (when supported): exit 1 only on timeout. Other flock failures
        # preserve their own exit code so callers can distinguish them from a
        # true timeout signal. On flock without -E (very old / non-util-linux
        # builds; gated by _flock_supports_dash_e), behavior matches pre-iter-3
        # — any flock failure exits 1, which is the existing caller contract
        # for cache-write failure. (cycle-094 review iter-4, DISS-202 fix
        # builds on iter-3 DISS-002 fix.)
        # shellcheck disable=SC2086  # intentional word-split on flock_e_args
        flock $flock_e_args -w "$timeout" 9 2>/dev/null
        local frc=$?
        if [[ "$frc" -eq 1 ]]; then
            log_error "cache lock timeout after ${timeout}s"
            exit 1
        elif [[ "$frc" -ne 0 ]]; then
            log_error "cache lock acquisition failed (flock rc=$frc; not a timeout)"
            exit "$frc"
        fi

        local tmpfile
        tmpfile="$(mktemp "${cache}.tmp.XXXXXX")"
        cat "$payload_file" > "$tmpfile"
        sync "$tmpfile" 2>/dev/null || true   # best-effort fsync via coreutils sync
        if ! mv -f "$tmpfile" "$cache"; then
            log_error "atomic rename failed; discarding write"
            rm -f "$tmpfile"
            exit 2
        fi
    ) 9>"$lockfile"
    rc=$?
    return "$rc"
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

    # Stale-sentinel cleanup (Sprint 3B Task 3B.concurrency_stress).
    # If the recorded PID is dead, remove the sentinel so the atomic-create
    # below can claim the slot. Sentinels older than 10 minutes are also
    # considered stale even if the PID is somehow alive (defensive cleanup).
    if [[ -f "$sentinel" ]]; then
        local existing_pid age_s
        existing_pid="$(cat "$sentinel" 2>/dev/null || echo "")"
        age_s=$(( $(date +%s) - $(stat -c %Y "$sentinel" 2>/dev/null || stat -f %m "$sentinel" 2>/dev/null || echo 0) ))
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null && (( age_s < 600 )); then
            log_debug "bg probe for $provider already running (pid=$existing_pid, age=${age_s}s); skipping"
            return 0
        fi
        log_debug "stale sentinel for $provider (pid=$existing_pid, age=${age_s}s); cleaning"
        rm -f "$sentinel"
    fi

    # Atomic claim — `set -C` (noclobber) makes `>` fail if the file exists
    # already, closing the TOCTOU race when multiple callers reach this point
    # simultaneously. Only the first caller wins; the rest dedup silently.
    if ! ( set -C; echo "$$" > "$sentinel" ) 2>/dev/null; then
        log_debug "lost race to claim sentinel for $provider; another caller is starting the probe"
        return 0
    fi

    (
        # The first writer (above) is this caller's PID; replace with the
        # subshell's PID so kill -0 inside the dedup check correctly reports
        # whether the probe child is alive.
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
# _curl_json  url  auth_type  api_key  [method]  [body_file]
# auth_type: "bearer" | "x-api-key" | "x-goog-api-key"
# Sets globals: HTTP_STATUS, RESPONSE_BODY
# Callers read the globals directly (do NOT use $() — that would fork a subshell
# and drop the global updates).
# In mock mode, reads fixture and status from LOA_PROBE_MOCK_* env vars.
HTTP_STATUS=0
RESPONSE_BODY=""
_curl_json() {
    local url="$1"
    local auth_type="$2"
    local api_key="$3"
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

    # Build secure curl config file via lib-security. The header construction
    # and write_curl_auth_config call MUST be on the same logical line so the
    # shell-compat-lint allowlist matches (raw curl auth is a lint error; the
    # secure helper pattern is allowlisted).
    if [[ ! -f "$SCRIPT_DIR/lib-security.sh" ]]; then
        log_error "lib-security.sh not found — refusing to proceed without secure auth helper"
        return 1
    fi
    # shellcheck source=./lib-security.sh
    source "$SCRIPT_DIR/lib-security.sh"
    local cfg
    case "$auth_type" in
        bearer)
            cfg=$(write_curl_auth_config "Authorization" "Bearer $api_key") || return 1
            ;;
        x-api-key)
            cfg=$(write_curl_auth_config "x-api-key" "$api_key") || return 1
            # Anthropic /v1/messages requires anthropic-version on every call.
            # Audit L-1 / Bridgebuilder iter-3 BLOCKING fix; tempfile is 0600.
            printf 'header = "anthropic-version: 2023-06-01"\n' >> "$cfg"
            ;;
        x-goog-api-key)
            cfg=$(write_curl_auth_config "x-goog-api-key" "$api_key") || return 1
            ;;
        *)
            log_error "unknown auth_type: $auth_type"
            return 1
            ;;
    esac

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
    _curl_json "https://api.openai.com/v1/models" "bearer" "$OPENAI_API_KEY"
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
    # Audit M-1 remediation: header-only auth (drops ?key= query string that leaked via ps aux)
    _curl_json "https://generativelanguage.googleapis.com/v1beta/models" "x-goog-api-key" "$GOOGLE_API_KEY"
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
    # _curl_json adds the anthropic-version: 2023-06-01 header automatically
    # for the x-api-key auth_type (closes Audit L-1 / Bridgebuilder iter-3 BLOCKING).
    _curl_json "https://api.anthropic.com/v1/messages" "x-api-key" "$ANTHROPIC_API_KEY" POST "$body_file"
    local resp="$RESPONSE_BODY"
    t1=$(date +%s%3N 2>/dev/null || date +%s000)
    PROBE_LATENCY_MS=$((t1 - t0))
    PROBE_HTTP="$HTTP_STATUS"
    rm -f "$body_file"

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

    # Skip cost increment when the probe never made an HTTP call. The no-API-key
    # path returns from `_probe_<provider>` after only setting PROBE_ERROR_CLASS=auth
    # with PROBE_HTTP empty (cleared by _reset_probe_result). Real auth failures
    # carry PROBE_HTTP=401/403 and still consume budget. Without this guard, fork
    # PRs (no secrets) trip the cost hardstop after 5 unmade probes. (G-1, cycle-094)
    if [[ "$PROBE_ERROR_CLASS" != "auth" ]] || [[ -n "$PROBE_HTTP" && "$PROBE_HTTP" != "0" ]]; then
        PROBES_USED=$((PROBES_USED + 1))
        # Each probe charges a nominal 1 cent estimate (conservative). Real cost-tracking
        # would need token-accurate metering; this is a coarse cap gate.
        COST_CENTS_USED=$((COST_CENTS_USED + 1))
    fi

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

        # Circuit breaker (Sprint 3B Task 3B.1) — short-circuit OPEN providers.
        if _circuit_open_for "$provider"; then
            PROBE_RESULTS+=("$provider|$model_id|UNKNOWN|circuit_breaker_open")
            _emit_trajectory "circuit_breaker_skipped" \
                "$(jq -n --arg provider "$provider" --arg model "$model_id" \
                    '{provider:$provider, model:$model}')"
            continue
        fi

        _probe_one_model "$provider" "$model_id"
        PROBE_RESULTS+=("$provider|$model_id|$PROBE_STATE|$PROBE_REASON")

        # Update circuit breaker based on probe outcome.
        case "$PROBE_ERROR_CLASS" in
            ok|hard_404|listing_miss) _circuit_update "$provider" success ;;
            transient|auth)           _circuit_update "$provider" failure ;;
        esac
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
    # cycle-094 G-1 (AC1 literal): emit `summary.skipped: true` when no probe
    # made an HTTP call AND the result set is non-empty all-UNKNOWN. This is the
    # fork-PR / no-keys signal — distinct from "0 entries probed" (registry
    # filter excluded everything) and from "some unknown" (partial keys).
    local skipped="false"
    if [[ "$PROBES_USED" -eq 0 ]] && \
       [[ "$summary_unknown" -gt 0 ]] && \
       [[ "$summary_available" -eq 0 ]] && \
       [[ "$summary_unavailable" -eq 0 ]]; then
        skipped="true"
    fi

    jq -n \
        --arg schema "$CACHE_SCHEMA_VERSION" \
        --arg ts "$(_iso_timestamp)" \
        --argjson entries "$entries_json" \
        --argjson avail "$summary_available" \
        --argjson unavail "$summary_unavailable" \
        --argjson unknown "$summary_unknown" \
        --argjson skipped "$skipped" \
        --argjson exit_code "$1" \
        '{schema_version:$schema, probed_at:$ts,
          summary:{available:$avail, unavailable:$unavail, unknown:$unknown, skipped:$skipped},
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

    # Feature flag (Sprint 3B Task 3B.1) — operator master switch.
    if ! _probe_enabled; then
        log_info "model_health_probe.enabled=false; skipping probe (feature flag)"
        _emit_audit_log "probe_disabled" "$(jq -n '{reason:"model_health_probe.enabled=false"}')"
        exit 0
    fi

    # Bypass governance (Sprint 3B Task 3B.bypass_governance) — LOA_PROBE_BYPASS w/ TTL+reason.
    # Use explicit rc capture so `set -e` does not exit on the "no bypass requested" branch (rc=1).
    local _bypass_rc=0
    _check_bypass || _bypass_rc=$?
    case "$_bypass_rc" in
        0)  log_info "LOA_PROBE_BYPASS active; probe skipped (reason: ${LOA_PROBE_BYPASS_REASON})"
            exit 0
            ;;
        2)  exit 64 ;;
        # 1: no bypass — proceed normally.
    esac

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
