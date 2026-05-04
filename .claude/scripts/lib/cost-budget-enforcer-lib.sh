#!/usr/bin/env bash
# =============================================================================
# cost-budget-enforcer-lib.sh — L2 cost-budget-enforcer (Sprint 2A)
#
# cycle-098 Sprint 2A — implementation of the L2 daily-cap enforcer per
# RFC #654, PRD FR-L2 (10 ACs), SDD §1.4.2 + §5.4.
#
# Composition (does NOT reinvent):
#   - 1A audit envelope:       audit_emit (writes JSONL with prev_hash chain)
#   - 1B signing scheme:       audit_emit honors LOA_AUDIT_SIGNING_KEY_ID
#   - 1B protected-class:      is_protected_class("budget.cap_increase") for cap raises
#   - 1.5 trust-store check:   audit_emit auto-verifies trust-store
#
# Verdict semantics (PRD §FR-L2 state-transition table; SDD §1.5.3):
#   - allow             usage <90% AND data fresh
#   - warn-90           90% <= usage <100% AND data fresh
#   - halt-100          usage >=100% AND data fresh
#   - halt-uncertainty  one of 5 modes:
#       billing_stale            billing API >15min stale AND counter near cap (>75%)
#       counter_inconsistent     counter is negative, decreasing, or backwards
#       counter_drift            reconciliation detected drift >5%
#       clock_drift              system clock vs billing_ts diff >60s
#       provider_lag             billing-API lag >=5min when counter shows >75%
#
# Public functions:
#   budget_verdict <estimated_usd> [--provider <id>] [--cycle-id <id>]
#       Returns a verdict via stdout JSON; side-effect appends to audit log.
#       Exit 0 = allow/warn-90 (call may proceed); exit 1 = halt-100/halt-uncertainty.
#
#   budget_get_usage [--provider <id>]
#       Read-only query of current usage state. Stdout JSON:
#         {usd_used, usd_remaining, last_billing_ts, counter_ts, freshness_seconds}
#
#   budget_record_call <actual_usd> --provider <id> [--cycle-id <id>] [--model-id <id>]
#       Post-call accounting; appends budget.record_call event to log.
#
#   budget_reconcile [--provider <id>] [--force-reason <text>]
#       Cron-invoked or operator-invoked reconciliation. Compares internal
#       counter to billing API for current UTC day; emits BLOCKER on drift.
#       Sprint 2B wires the cron registration; this function is the unit.
#
# Environment variables:
#   LOA_BUDGET_LOG                audit log path (default .run/cost-budget-events.jsonl)
#   LOA_BUDGET_DAILY_CAP_USD      override daily_cap_usd
#   LOA_BUDGET_DRIFT_THRESHOLD    override reconcile drift threshold pct (default 5.0)
#   LOA_BUDGET_FRESHNESS_SECONDS  billing-API freshness threshold (default 300 = 5min)
#   LOA_BUDGET_STALE_HALT_PCT     usage% triggering halt-uncertainty:billing_stale (default 75)
#   LOA_BUDGET_CLOCK_TOLERANCE    UTC clock tolerance vs billing_ts in seconds (default 60)
#   LOA_BUDGET_LAG_HALT_SECONDS   provider-lag threshold for halt-uncertainty:provider_lag
#                                   (default 300 = 5min)
#   LOA_BUDGET_BILLING_STALE_SECONDS  billing-stale threshold for halt-uncertainty:billing_stale
#                                       (default 900 = 15min, per PRD §FR-L2-4)
#   LOA_BUDGET_OBSERVER_CMD       caller-supplied billing-API observer command path
#                                   Invoked as: <cmd> <provider> -> stdout JSON
#                                   {"usd_used": <number>, "billing_ts": "<iso8601>"}
#   LOA_BUDGET_TEST_NOW           test-only override for "now" (ISO-8601)
#   LOA_BUDGET_CONFIG_FILE        override .loa.config.yaml path
#
# Exit codes:
#   0 = allow / warn-90 (call may proceed; warn-90 logged but not blocking)
#   1 = halt-100 or halt-uncertainty (call MUST NOT proceed)
#   2 = invalid arguments
#   3 = configuration error (e.g., missing daily_cap_usd)
# =============================================================================

set -euo pipefail

if [[ "${_LOA_L2_LIB_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_L2_LIB_SOURCED=1

_L2_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_L2_REPO_ROOT="$(cd "${_L2_DIR}/../../.." && pwd)"
_L2_AUDIT_ENVELOPE="${_L2_REPO_ROOT}/.claude/scripts/audit-envelope.sh"
_L2_PROTECTED_ROUTER="${_L2_REPO_ROOT}/.claude/scripts/lib/protected-class-router.sh"
_L2_SCHEMA_DIR="${_L2_REPO_ROOT}/.claude/data/trajectory-schemas/budget-events"

# Source dependencies (idempotent — guards against double-source).
# shellcheck source=../audit-envelope.sh
source "${_L2_AUDIT_ENVELOPE}"
# shellcheck source=protected-class-router.sh
source "${_L2_PROTECTED_ROUTER}"

_l2_log() { echo "[cost-budget-enforcer] $*" >&2; }

# -----------------------------------------------------------------------------
# Defaults (overridable via env vars or .loa.config.yaml).
# -----------------------------------------------------------------------------
_L2_DEFAULT_LOG=".run/cost-budget-events.jsonl"
_L2_DEFAULT_DRIFT_THRESHOLD="5.0"
_L2_DEFAULT_FRESHNESS_SECONDS="300"
_L2_DEFAULT_STALE_HALT_PCT="75"
_L2_DEFAULT_CLOCK_TOLERANCE="60"
_L2_DEFAULT_LAG_HALT_SECONDS="300"
_L2_DEFAULT_BILLING_STALE_SECONDS="900"

# Numeric / provider input validation regexes (review HIGH-3 / audit F1 + F2).
# All numerics passed to python3 -c interpolation MUST match _L2_NUMERIC_RE.
# All providers (free-form caller input) MUST match _L2_PROVIDER_RE.
_L2_NUMERIC_RE='^[0-9]+(\.[0-9]+)?$'
_L2_INT_RE='^[0-9]+$'
_L2_PROVIDER_RE='^[a-z][a-z0-9_-]{0,63}$'

# -----------------------------------------------------------------------------
# _l2_validate_numeric <value> <field_name> [int|decimal]
# Returns 0 valid; 1 invalid (and logs an error).
# -----------------------------------------------------------------------------
_l2_validate_numeric() {
    local value="$1"
    local field="$2"
    local kind="${3:-decimal}"
    local re
    if [[ "$kind" == "int" ]]; then
        re="$_L2_INT_RE"
    else
        re="$_L2_NUMERIC_RE"
    fi
    if [[ -z "$value" ]] || ! [[ "$value" =~ $re ]]; then
        _l2_log "ERROR: invalid numeric value for $field: '$value' (expected $kind matching $re)"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# _l2_config_path — return resolved .loa.config.yaml path.
# -----------------------------------------------------------------------------
_l2_config_path() {
    echo "${LOA_BUDGET_CONFIG_FILE:-${_L2_REPO_ROOT}/.loa.config.yaml}"
}

# -----------------------------------------------------------------------------
# _l2_config_get <yaml_path> [default]
# Read a value from .loa.config.yaml using yq if available, else PyYAML.
# Returns the value on stdout; default on missing.
# -----------------------------------------------------------------------------
_l2_config_get() {
    local yq_path="$1"
    local default="${2:-}"
    local config
    config="$(_l2_config_path)"
    [[ -f "$config" ]] || { echo "$default"; return 0; }
    if command -v yq >/dev/null 2>&1; then
        local result
        result="$(yq -r "${yq_path} // \"\"" "$config" 2>/dev/null || true)"
        if [[ -z "$result" || "$result" == "null" ]]; then
            echo "$default"
        else
            echo "$result"
        fi
        return 0
    fi
    # Python fallback. Path is dotted (e.g., "cost_budget_enforcer.daily_cap_usd").
    local clean_path="${yq_path#.}"
    python3 - "$config" "$clean_path" "$default" <<'PY' 2>/dev/null || echo "$default"
import sys
try:
    import yaml
except ImportError:
    print(sys.argv[3])
    sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print(sys.argv[3])
    sys.exit(0)
parts = sys.argv[2].split('.')
node = doc
for p in parts:
    if isinstance(node, dict) and p in node:
        node = node[p]
    else:
        print(sys.argv[3])
        sys.exit(0)
if node is None or node == "":
    print(sys.argv[3])
else:
    print(node)
PY
}

# -----------------------------------------------------------------------------
# _l2_get_daily_cap — resolve daily cap. Env > config > error.
# -----------------------------------------------------------------------------
_l2_get_daily_cap() {
    local cap
    if [[ -n "${LOA_BUDGET_DAILY_CAP_USD:-}" ]]; then
        cap="$LOA_BUDGET_DAILY_CAP_USD"
    else
        cap="$(_l2_config_get '.cost_budget_enforcer.daily_cap_usd' '')"
    fi
    if [[ -z "$cap" ]]; then
        _l2_log "ERROR: daily_cap_usd not configured (set LOA_BUDGET_DAILY_CAP_USD or .loa.config.yaml::cost_budget_enforcer.daily_cap_usd)"
        return 3
    fi
    if ! _l2_validate_numeric "$cap" "daily_cap_usd"; then
        return 3
    fi
    echo "$cap"
}

_l2_get_drift_threshold() {
    local v
    v="${LOA_BUDGET_DRIFT_THRESHOLD:-$(_l2_config_get '.cost_budget_enforcer.reconciliation.drift_threshold_pct' "$_L2_DEFAULT_DRIFT_THRESHOLD")}"
    _l2_validate_numeric "$v" "drift_threshold_pct" || { echo "$_L2_DEFAULT_DRIFT_THRESHOLD"; return 0; }
    echo "$v"
}

_l2_get_freshness_seconds() {
    local v
    v="${LOA_BUDGET_FRESHNESS_SECONDS:-$(_l2_config_get '.cost_budget_enforcer.freshness_threshold_seconds' "$_L2_DEFAULT_FRESHNESS_SECONDS")}"
    _l2_validate_numeric "$v" "freshness_threshold_seconds" int || { echo "$_L2_DEFAULT_FRESHNESS_SECONDS"; return 0; }
    echo "$v"
}

_l2_get_stale_halt_pct() {
    local v
    v="${LOA_BUDGET_STALE_HALT_PCT:-$(_l2_config_get '.cost_budget_enforcer.stale_halt_pct' "$_L2_DEFAULT_STALE_HALT_PCT")}"
    _l2_validate_numeric "$v" "stale_halt_pct" || { echo "$_L2_DEFAULT_STALE_HALT_PCT"; return 0; }
    echo "$v"
}

_l2_get_clock_tolerance() {
    local v
    v="${LOA_BUDGET_CLOCK_TOLERANCE:-$(_l2_config_get '.cost_budget_enforcer.clock_tolerance_seconds' "$_L2_DEFAULT_CLOCK_TOLERANCE")}"
    _l2_validate_numeric "$v" "clock_tolerance_seconds" int || { echo "$_L2_DEFAULT_CLOCK_TOLERANCE"; return 0; }
    echo "$v"
}

_l2_get_lag_halt_seconds() {
    local v
    v="${LOA_BUDGET_LAG_HALT_SECONDS:-$(_l2_config_get '.cost_budget_enforcer.provider_lag_halt_seconds' "$_L2_DEFAULT_LAG_HALT_SECONDS")}"
    _l2_validate_numeric "$v" "provider_lag_halt_seconds" int || { echo "$_L2_DEFAULT_LAG_HALT_SECONDS"; return 0; }
    echo "$v"
}

_l2_get_billing_stale_seconds() {
    local v
    v="${LOA_BUDGET_BILLING_STALE_SECONDS:-$(_l2_config_get '.cost_budget_enforcer.billing_stale_halt_seconds' "$_L2_DEFAULT_BILLING_STALE_SECONDS")}"
    _l2_validate_numeric "$v" "billing_stale_halt_seconds" int || { echo "$_L2_DEFAULT_BILLING_STALE_SECONDS"; return 0; }
    echo "$v"
}

_l2_get_observer_cmd() {
    echo "${LOA_BUDGET_OBSERVER_CMD:-$(_l2_config_get '.cost_budget_enforcer.billing_observer_cmd' '')}"
}

# Default allowlist for billing-observer command paths. Caller-supplied
# observer commands resolved outside these prefixes are rejected. Operators
# can override via .cost_budget_enforcer.allowed_observer_paths (yaml array)
# or LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES (colon-separated env).
# Source: cycle-098 H2 closure of #708 F-005 (audit hardening — observer
# trust model). Mirrors the L3 phase-path-allowlist pattern from Sprint 3
# remediation.
_L2_DEFAULT_OBSERVER_ALLOWLIST=(
    ".claude/scripts/observers"
    ".run/observers"
)

# -----------------------------------------------------------------------------
# _l2_get_observer_allowlist — emit one prefix per line (canonicalized to
# absolute paths). Sources: env override → yaml override → defaults.
# -----------------------------------------------------------------------------
_l2_get_observer_allowlist() {
    if [[ -n "${LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES:-}" ]]; then
        local prefix
        local IFS=":"
        for prefix in $LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES; do
            if [[ "$prefix" = /* ]]; then echo "$prefix"
            else echo "${_L2_REPO_ROOT}/${prefix}"
            fi
        done
        return 0
    fi
    local yaml_list
    yaml_list="$(_l2_config_get '.cost_budget_enforcer.allowed_observer_paths' '')"
    if [[ -n "$yaml_list" && "$yaml_list" != "null" ]]; then
        local p
        while IFS= read -r p; do
            p="${p#- }"; p="${p#\"}"; p="${p%\"}"; p="${p//\'/}"
            [[ -z "$p" ]] && continue
            if [[ "$p" = /* ]]; then echo "$p"
            else echo "${_L2_REPO_ROOT}/${p}"
            fi
        done <<<"$yaml_list"
        return 0
    fi
    local default_p
    for default_p in "${_L2_DEFAULT_OBSERVER_ALLOWLIST[@]}"; do
        echo "${_L2_REPO_ROOT}/${default_p}"
    done
}

# -----------------------------------------------------------------------------
# _l2_validate_observer_path <raw_path>
#
# Canonicalize raw_path (resolving .., absolute-vs-relative, symlinks) and
# verify it lives under one of the allowed prefixes. Returns 0 + canonical
# path on stdout; 1 on policy violation. Closes #708 F-005.
# -----------------------------------------------------------------------------
_l2_validate_observer_path() {
    local raw="$1"
    if [[ -z "$raw" ]]; then return 1; fi
    local resolved
    if [[ "$raw" = /* ]]; then resolved="$raw"
    else resolved="${_L2_REPO_ROOT}/${raw}"
    fi
    local canon=""
    if command -v realpath >/dev/null 2>&1; then
        canon="$(realpath -m "$resolved" 2>/dev/null || true)"
    fi
    if [[ -z "$canon" ]] && command -v python3 >/dev/null 2>&1; then
        canon="$(python3 -c "import os, sys; print(os.path.normpath(sys.argv[1]))" "$resolved" 2>/dev/null || true)"
    fi
    [[ -n "$canon" ]] || return 1
    [[ "$canon" == *"/.."* || "$canon" == *"/../"* ]] && return 1
    local prefix prefix_canon
    while IFS= read -r prefix; do
        if command -v realpath >/dev/null 2>&1; then
            prefix_canon="$(realpath -m "$prefix" 2>/dev/null || echo "$prefix")"
        else
            prefix_canon="$prefix"
        fi
        prefix_canon="${prefix_canon%/}"
        if [[ "$canon" == "$prefix_canon"/* ]]; then
            echo "$canon"
            return 0
        fi
    done < <(_l2_get_observer_allowlist)
    return 1
}

_l2_get_log_path() {
    if [[ -n "${LOA_BUDGET_LOG:-}" ]]; then
        echo "$LOA_BUDGET_LOG"
        return 0
    fi
    local relpath
    relpath="$(_l2_config_get '.cost_budget_enforcer.audit_log' "$_L2_DEFAULT_LOG")"
    if [[ "$relpath" = /* ]]; then
        echo "$relpath"
    else
        echo "${_L2_REPO_ROOT}/${relpath}"
    fi
}

# -----------------------------------------------------------------------------
# _l2_propagate_test_now — when LOA_BUDGET_TEST_NOW is set, also propagate to
# LOA_AUDIT_TEST_NOW so audit-envelope writes the same simulated ts_utc.
# Call at the top of every public L2 entry function (must be in caller's
# scope, not a subshell — command substitutions cannot propagate exports).
# -----------------------------------------------------------------------------
_l2_propagate_test_now() {
    if [[ -n "${LOA_BUDGET_TEST_NOW:-}" ]]; then
        export LOA_AUDIT_TEST_NOW="$LOA_BUDGET_TEST_NOW"
    fi
}

# -----------------------------------------------------------------------------
# _l2_now_iso8601 — wraps _audit_now_iso8601, honoring LOA_BUDGET_TEST_NOW.
# -----------------------------------------------------------------------------
_l2_now_iso8601() {
    if [[ -n "${LOA_BUDGET_TEST_NOW:-}" ]]; then
        echo "$LOA_BUDGET_TEST_NOW"
    else
        _audit_now_iso8601
    fi
}

# -----------------------------------------------------------------------------
# _l2_now_utc_day — current UTC day as YYYY-MM-DD.
# -----------------------------------------------------------------------------
_l2_now_utc_day() {
    local now
    now="$(_l2_now_iso8601)"
    echo "${now:0:10}"
}

# -----------------------------------------------------------------------------
# _l2_iso_to_epoch <iso8601> — convert ISO-8601 timestamp to Unix epoch seconds.
# Returns "" on parse failure.
# -----------------------------------------------------------------------------
_l2_iso_to_epoch() {
    local ts="$1"
    [[ -z "$ts" ]] && return 0
    python3 -c "
from datetime import datetime
import sys
try:
    s = sys.argv[1]
    if s.endswith('Z'):
        s = s[:-1] + '+00:00'
    print(int(datetime.fromisoformat(s).timestamp()))
except Exception:
    pass
" "$ts" 2>/dev/null
}

# -----------------------------------------------------------------------------
# _l2_provider_normalize <provider> — default to "aggregate" if empty.
# Validates against _L2_PROVIDER_RE to prevent yq path-expression injection
# (audit F2). Returns non-zero (and a sanitized fallback "aggregate") on
# invalid input — caller's burden to check exit code.
# -----------------------------------------------------------------------------
_l2_provider_normalize() {
    local provider="${1:-}"
    if [[ -z "$provider" ]]; then
        echo "aggregate"
        return 0
    fi
    if ! [[ "$provider" =~ $_L2_PROVIDER_RE ]]; then
        _l2_log "ERROR: invalid provider id '$provider' (expected $_L2_PROVIDER_RE)"
        echo "aggregate"
        return 1
    fi
    echo "$provider"
}

# -----------------------------------------------------------------------------
# _l2_recent_drift_blocker <provider> <utc_day>
#
# Scan the audit log for budget.reconcile events for <utc_day> + <provider>.
# Returns the diagnostic JSON of the most-recent BLOCKER if one exists AND
# is not yet cleared by a subsequent force-reconcile event. Otherwise empty.
# A force-reconcile (force_reconcile=true) "clears" prior BLOCKERs because
# the operator has explicitly reviewed the drift and decided to proceed
# (counter NOT auto-corrected — but the operator-decision is auditable).
#
# Used by budget_verdict to honor MED-3 (counter_drift reachability): a
# verdict made after an unresolved drift BLOCKER should halt-uncertainty.
# -----------------------------------------------------------------------------
_l2_recent_drift_blocker() {
    local provider="$1"
    local utc_day="$2"
    local log_path
    log_path="$(_l2_get_log_path)"
    if [[ ! -f "$log_path" ]]; then
        return 0
    fi
    python3 - "$log_path" "$provider" "$utc_day" <<'PY'
import json, sys
log_path, target_provider, target_day = sys.argv[1], sys.argv[2], sys.argv[3]
last_blocker = None
try:
    with open(log_path, 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('['):
                continue
            try:
                envelope = json.loads(line)
            except json.JSONDecodeError:
                continue
            if envelope.get('event_type') != 'budget.reconcile':
                continue
            payload = envelope.get('payload') or {}
            if payload.get('utc_day') != target_day:
                continue
            ev_provider = payload.get('provider', 'aggregate')
            if target_provider != 'aggregate' and ev_provider != target_provider:
                continue
            if payload.get('force_reconcile') is True:
                # Operator explicit override clears prior blockers.
                last_blocker = None
                continue
            if payload.get('blocker') is True:
                last_blocker = {
                    'drift_pct': payload.get('drift_pct'),
                    'counter_usd': payload.get('counter_usd'),
                    'billing_usd': payload.get('billing_usd'),
                    'reconcile_ts': envelope.get('ts_utc'),
                }
            else:
                # blocker=false reconcile clears the prior blocker too.
                last_blocker = None
except FileNotFoundError:
    pass
if last_blocker:
    print(json.dumps(last_blocker))
PY
}

# -----------------------------------------------------------------------------
# _l2_compute_counter <provider> <utc_day>
#
# Tail-scan the audit log for budget.record_call events matching <provider>
# (or aggregate across all providers if provider="aggregate") for <utc_day>.
# Returns JSON: {"counter_usd": <number>, "counter_ts": "<iso8601 or null>",
#                "consistency": "ok" | "negative" | "decreasing" | "backwards"}
#
# Consistency semantics:
#   - negative:   any actual_usd < 0 detected
#   - decreasing: usd_used_post in a later entry < earlier entry (counter went down)
#   - backwards:  ts_utc not monotonic (out-of-order entries)
# -----------------------------------------------------------------------------
_l2_compute_counter() {
    local provider="$1"
    local utc_day="$2"
    local log_path
    log_path="$(_l2_get_log_path)"
    if [[ ! -f "$log_path" ]]; then
        printf '{"counter_usd":0,"counter_ts":null,"consistency":"ok"}\n'
        return 0
    fi

    python3 - "$log_path" "$provider" "$utc_day" <<'PY'
import json
import sys

log_path = sys.argv[1]
target_provider = sys.argv[2]
target_day = sys.argv[3]

counter = 0.0
last_ts = None
consistency = "ok"
prev_post = -1.0
prev_ts = None

try:
    with open(log_path, 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('['):
                continue
            try:
                envelope = json.loads(line)
            except json.JSONDecodeError:
                continue
            if envelope.get('event_type') != 'budget.record_call':
                continue
            payload = envelope.get('payload') or {}
            if payload.get('utc_day') != target_day:
                continue
            ev_provider = payload.get('provider', 'aggregate')
            if target_provider != 'aggregate' and ev_provider != target_provider:
                continue
            try:
                actual = float(payload.get('actual_usd', 0))
                post = float(payload.get('usd_used_post', 0))
            except (TypeError, ValueError):
                consistency = "negative"  # malformed treated as inconsistent
                continue
            if actual < 0:
                consistency = "negative"
            ts = envelope.get('ts_utc')
            if prev_ts is not None and ts is not None and ts < prev_ts:
                consistency = "backwards"
            if prev_post >= 0 and post < prev_post and consistency == "ok":
                consistency = "decreasing"
            prev_post = post
            prev_ts = ts
            counter += actual
            last_ts = ts
except FileNotFoundError:
    pass

print(json.dumps({
    "counter_usd": round(counter, 6),
    "counter_ts": last_ts,
    "consistency": consistency,
}))
PY
}

# -----------------------------------------------------------------------------
# _l2_invoke_observer <provider>
#
# Invoke caller-supplied billing-observer command. Output expected on stdout:
#   {"usd_used": <number>, "billing_ts": "<iso8601>"}
# Returns: same JSON on success; '{"_unreachable": true}' on failure.
# -----------------------------------------------------------------------------
_l2_invoke_observer() {
    local provider="$1"
    local cmd
    cmd="$(_l2_get_observer_cmd)"
    if [[ -z "$cmd" ]]; then
        printf '{"_unreachable":true,"_reason":"no_observer_configured"}\n'
        return 0
    fi
    if [[ ! -x "$cmd" && ! -f "$cmd" ]]; then
        printf '{"_unreachable":true,"_reason":"observer_not_found"}\n'
        return 0
    fi
    # Sprint H2 closure of #708 F-005 (observer trust model): require the
    # observer command path to live under one of the allowlist prefixes.
    # Defense against arbitrary-execution via env-var or yaml-key injection.
    local cmd_canonical
    if ! cmd_canonical="$(_l2_validate_observer_path "$cmd")"; then
        printf '{"_unreachable":true,"_reason":"observer_path_outside_allowlist"}\n'
        _l2_log "ERROR: observer command path '$cmd' is outside the configured allowlist"
        _l2_log "  Configure additional prefixes via .cost_budget_enforcer.allowed_observer_paths or LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES"
        _l2_log "  Allowed prefixes:"
        _l2_get_observer_allowlist | sed 's/^/    /' >&2
        return 0
    fi
    local out
    if ! out="$(timeout 30 "$cmd_canonical" "$provider" 2>/dev/null)"; then
        printf '{"_unreachable":true,"_reason":"observer_error_or_timeout"}\n'
        return 0
    fi
    if ! printf '%s' "$out" | jq -e 'type == "object"' >/dev/null 2>&1; then
        printf '{"_unreachable":true,"_reason":"observer_invalid_json"}\n'
        return 0
    fi
    printf '%s\n' "$out"
}

# -----------------------------------------------------------------------------
# _l2_validate_payload <event_type> <payload_json>
#
# Validate payload against per-event-type schema. event_type "budget.allow" →
# schema "budget-allow.payload.schema.json". Tries ajv first, then python.
# Returns 0 valid; 1 invalid.
# -----------------------------------------------------------------------------
_l2_validate_payload() {
    local event_type="$1"
    local payload_json="$2"
    local basename
    basename="${event_type#budget.}"
    basename="${basename//_/-}"
    local schema_path="${_L2_SCHEMA_DIR}/budget-${basename}.payload.schema.json"
    if [[ ! -f "$schema_path" ]]; then
        _l2_log "ERROR: per-event schema missing for $event_type at $schema_path"
        return 1
    fi
    if command -v ajv >/dev/null 2>&1; then
        local tmp_data
        tmp_data="$(mktemp)"
        chmod 600 "$tmp_data"
        # shellcheck disable=SC2064
        trap "rm -f '$tmp_data'" RETURN
        printf '%s' "$payload_json" > "$tmp_data"
        if ajv validate -s "$schema_path" -d "$tmp_data" --spec=draft2020 >/dev/null 2>&1; then
            return 0
        fi
        return 1
    fi
    python3 - "$schema_path" "$payload_json" <<'PY' 2>/dev/null
import json, sys
try:
    import jsonschema
except ImportError:
    sys.exit(0)  # No validator → permissive (envelope schema still validates the wrapper)
with open(sys.argv[1]) as f:
    schema = json.load(f)
try:
    payload = json.loads(sys.argv[2])
except json.JSONDecodeError:
    sys.exit(1)
try:
    jsonschema.validate(payload, schema)
except jsonschema.ValidationError:
    sys.exit(1)
PY
}

# -----------------------------------------------------------------------------
# _l2_audit_emit_event <event_type> <payload_json>
#
# Validate payload via per-event-type schema, then call audit_emit (which
# validates envelope, signs, and writes atomically under flock).
# Returns 0 on success; non-zero on failure.
# -----------------------------------------------------------------------------
_l2_audit_emit_event() {
    local event_type="$1"
    local payload_json="$2"
    local log_path
    log_path="$(_l2_get_log_path)"

    if ! _l2_validate_payload "$event_type" "$payload_json"; then
        _l2_log "payload schema validation failed for $event_type"
        return 1
    fi
    audit_emit "L2" "$event_type" "$payload_json" "$log_path"
}

# -----------------------------------------------------------------------------
# _l2_check_clock_drift <billing_ts>
#
# Returns 0 if system clock and billing_ts agree within tolerance; 1 if drift
# exceeds tolerance (caller halts with halt-uncertainty:clock_drift); 2 on
# parse failure (treated as no-clock-check possible).
# Stdout: delta_seconds (signed) on success or drift case; empty on parse fail.
# -----------------------------------------------------------------------------
_l2_check_clock_drift() {
    local billing_ts="$1"
    [[ -z "$billing_ts" || "$billing_ts" == "null" ]] && return 2
    local sys_epoch billing_epoch
    sys_epoch="$(_l2_iso_to_epoch "$(_l2_now_iso8601)")"
    billing_epoch="$(_l2_iso_to_epoch "$billing_ts")"
    [[ -z "$sys_epoch" || -z "$billing_epoch" ]] && return 2
    local delta
    delta=$(( sys_epoch - billing_epoch ))
    local abs_delta=${delta#-}
    local tolerance
    tolerance="$(_l2_get_clock_tolerance)"
    echo "$delta"
    if (( abs_delta > tolerance )); then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# _l2_compute_age_seconds <ts> — seconds between now and ts.
# -----------------------------------------------------------------------------
_l2_compute_age_seconds() {
    local ts="$1"
    [[ -z "$ts" || "$ts" == "null" ]] && { echo "null"; return 0; }
    local sys_epoch ts_epoch
    sys_epoch="$(_l2_iso_to_epoch "$(_l2_now_iso8601)")"
    ts_epoch="$(_l2_iso_to_epoch "$ts")"
    [[ -z "$sys_epoch" || -z "$ts_epoch" ]] && { echo "null"; return 0; }
    local age=$(( sys_epoch - ts_epoch ))
    if (( age < 0 )); then
        age=0
    fi
    echo "$age"
}

# -----------------------------------------------------------------------------
# budget_get_usage [--provider <id>]
#
# Stdout JSON:
#   {usd_used, usd_remaining, daily_cap_usd, last_billing_ts, counter_ts,
#    freshness_seconds, provider, utc_day}
# -----------------------------------------------------------------------------
budget_get_usage() {
    _l2_propagate_test_now
    local provider=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider) provider="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    if ! provider="$(_l2_provider_normalize "$provider")"; then return 2; fi

    local cap
    if ! cap="$(_l2_get_daily_cap)"; then
        return 3
    fi

    local utc_day
    utc_day="$(_l2_now_utc_day)"

    local counter_json counter_usd counter_ts
    counter_json="$(_l2_compute_counter "$provider" "$utc_day")"
    counter_usd="$(printf '%s' "$counter_json" | jq -r '.counter_usd')"
    counter_ts="$(printf '%s' "$counter_json" | jq -r '.counter_ts')"

    local observer_json billing_usd billing_ts freshness
    observer_json="$(_l2_invoke_observer "$provider")"
    billing_usd="$(printf '%s' "$observer_json" | jq -r '.usd_used // null')"
    billing_ts="$(printf '%s' "$observer_json" | jq -r '.billing_ts // null')"
    freshness="$(_l2_compute_age_seconds "$billing_ts")"

    # Authoritative usd_used: prefer billing API (when fresh), fall back to counter.
    local usd_used="$counter_usd"
    if [[ "$billing_usd" != "null" ]]; then
        local fresh_threshold
        fresh_threshold="$(_l2_get_freshness_seconds)"
        if [[ "$freshness" != "null" ]] && (( freshness <= fresh_threshold )); then
            usd_used="$billing_usd"
        fi
    fi

    local remaining
    remaining="$(python3 -c "print(round(${cap} - ${usd_used}, 6))")"

    jq -nc \
        --argjson used "$usd_used" \
        --argjson remaining "$remaining" \
        --argjson cap "$cap" \
        --argjson freshness "${freshness:-null}" \
        --arg billing_ts "${billing_ts:-}" \
        --arg counter_ts "${counter_ts:-}" \
        --arg provider "$provider" \
        --arg utc_day "$utc_day" \
        '{
            usd_used: $used,
            usd_remaining: $remaining,
            daily_cap_usd: $cap,
            last_billing_ts: ($billing_ts | select(length>0) // null),
            counter_ts: ($counter_ts | select(length>0 and . != "null") // null),
            freshness_seconds: $freshness,
            provider: $provider,
            utc_day: $utc_day
        }'
}

# -----------------------------------------------------------------------------
# budget_record_call <actual_usd> --provider <id> [--cycle-id <id>]
#                                 [--model-id <id>] [--verdict-ref <hash>]
#
# Append a budget.record_call event. Computes usd_used_post from prior
# tail-scan + this actual_usd.
# -----------------------------------------------------------------------------
budget_record_call() {
    _l2_propagate_test_now
    local actual_usd="${1:-}"
    if [[ -z "$actual_usd" ]]; then
        _l2_log "budget_record_call: actual_usd required"
        return 2
    fi
    shift || true

    local provider="" cycle_id="" model_id="" verdict_ref=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider) provider="$2"; shift 2 ;;
            --cycle-id) cycle_id="$2"; shift 2 ;;
            --model-id) model_id="$2"; shift 2 ;;
            --verdict-ref) verdict_ref="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    if ! provider="$(_l2_provider_normalize "$provider")"; then return 2; fi

    if ! [[ "$actual_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _l2_log "budget_record_call: actual_usd must be a non-negative decimal"
        return 2
    fi

    local utc_day
    utc_day="$(_l2_now_utc_day)"

    local prior counter_usd
    prior="$(_l2_compute_counter "$provider" "$utc_day")"
    counter_usd="$(printf '%s' "$prior" | jq -r '.counter_usd')"
    local post
    post="$(python3 -c "print(round(${counter_usd} + ${actual_usd}, 6))")"

    local payload
    payload="$(jq -nc \
        --argjson actual "$actual_usd" \
        --argjson post "$post" \
        --arg provider "$provider" \
        --arg utc_day "$utc_day" \
        --arg cycle_id "$cycle_id" \
        --arg model_id "$model_id" \
        --arg verdict_ref "$verdict_ref" \
        '{
            actual_usd: $actual,
            usd_used_post: $post,
            provider: $provider,
            utc_day: $utc_day
        }
        | if $cycle_id != "" then . + {cycle_id: $cycle_id} else . + {cycle_id: null} end
        | if $model_id != "" then . + {model_id: $model_id} else . + {model_id: null} end
        | if $verdict_ref != "" then . + {verdict_ref: $verdict_ref} else . + {verdict_ref: null} end')"

    _l2_audit_emit_event "budget.record_call" "$payload"
}

# -----------------------------------------------------------------------------
# _l2_render_verdict <verdict> <usd_used> <cap> <estimated> <provider>
#                    <utc_day> <billing_age> <counter_age> <observer_used>
#                    [<uncertainty_reason> [<diagnostic_json>]]
#
# Build the payload JSON for a verdict event. usage_pct is computed for
# warn-90 / halt-100 only.
# -----------------------------------------------------------------------------
_l2_render_verdict() {
    local verdict="$1"
    local usd_used="$2"
    local cap="$3"
    local estimated="$4"
    local provider="$5"
    local utc_day="$6"
    local billing_age="$7"
    local counter_age="$8"
    local observer_used="$9"
    local cycle_id="${10:-}"
    local uncertainty_reason="${11:-}"
    local diagnostic="${12:-}"

    local remaining
    remaining="$(python3 -c "print(round(${cap} - ${usd_used}, 6))")"
    # usage_pct: for warn-90/halt-100, this is the PROJECTED post-call usage %
    # (used + estimated). For other verdicts, it's the current usage %.
    # Schemas warn-90.usage_pct (>=90) and halt-100.usage_pct (>=100) are
    # interpreted against the projected percentage, since the verdict trigger
    # is based on projection.
    local usage_pct
    if [[ "$verdict" == "warn-90" || "$verdict" == "halt-100" ]]; then
        usage_pct="$(python3 -c "
cap = float('${cap}')
used = float('${usd_used}')
est = float('${estimated}')
print(0 if cap == 0 else round(100 * (used + est) / cap, 6))
")"
    else
        usage_pct="$(python3 -c "
cap = float('${cap}')
used = float('${usd_used}')
print(0 if cap == 0 else round(100 * used / cap, 6))
")"
    fi

    local payload
    payload="$(jq -nc \
        --arg verdict "$verdict" \
        --argjson usd_used "$usd_used" \
        --argjson remaining "$remaining" \
        --argjson cap "$cap" \
        --argjson estimated "$estimated" \
        --argjson billing_age "${billing_age:-null}" \
        --argjson counter_age "$counter_age" \
        --argjson usage_pct "$usage_pct" \
        --arg provider "$provider" \
        --arg utc_day "$utc_day" \
        --arg cycle_id "$cycle_id" \
        --arg observer_used "$observer_used" \
        '{
            verdict: $verdict,
            usd_used: $usd_used,
            usd_remaining: $remaining,
            daily_cap_usd: $cap,
            estimated_usd_for_call: $estimated,
            billing_api_age_seconds: $billing_age,
            counter_age_seconds: $counter_age,
            provider: $provider,
            utc_day: $utc_day,
            billing_observer_used: ($observer_used == "true")
        }
        | if $cycle_id != "" then . + {cycle_id: $cycle_id} else . + {cycle_id: null} end')"

    # Add usage_pct only for warn-90 and halt-100 (their schemas include it).
    if [[ "$verdict" == "warn-90" || "$verdict" == "halt-100" ]]; then
        payload="$(printf '%s' "$payload" | jq -c --argjson up "$usage_pct" '. + {usage_pct: $up}')"
    fi

    if [[ "$verdict" == "halt-uncertainty" && -n "$uncertainty_reason" ]]; then
        payload="$(printf '%s' "$payload" | jq -c --arg r "$uncertainty_reason" '. + {uncertainty_reason: $r}')"
        if [[ -n "$diagnostic" ]]; then
            payload="$(printf '%s' "$payload" | jq -c --argjson d "$diagnostic" '. + {diagnostic: $d}')"
        fi
    fi
    echo "$payload"
}

# -----------------------------------------------------------------------------
# _l2_emit_and_return <event_type> <verdict_payload>
# Emit the event and return verdict-appropriate exit code.
# -----------------------------------------------------------------------------
_l2_emit_and_return() {
    local event_type="$1"
    local payload="$2"
    if ! _l2_audit_emit_event "$event_type" "$payload"; then
        _l2_log "audit emit failed for $event_type"
        return 1
    fi
    printf '%s\n' "$payload"
    case "$event_type" in
        budget.allow|budget.warn_90) return 0 ;;
        budget.halt_100|budget.halt_uncertainty) return 1 ;;
        *) return 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# budget_verdict <estimated_usd> [--provider <id>] [--cycle-id <id>]
#
# Main entry. Returns verdict via stdout JSON; appends to audit log; exits 0
# for allow/warn-90, exits 1 for halt-100/halt-uncertainty.
# -----------------------------------------------------------------------------
budget_verdict() {
    _l2_propagate_test_now
    local estimated_usd="${1:-}"
    if [[ -z "$estimated_usd" ]]; then
        _l2_log "budget_verdict: estimated_usd required"
        return 2
    fi
    if ! [[ "$estimated_usd" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        _l2_log "budget_verdict: estimated_usd must be a non-negative decimal"
        return 2
    fi
    shift || true

    local provider="" cycle_id=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider) provider="$2"; shift 2 ;;
            --cycle-id) cycle_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    if ! provider="$(_l2_provider_normalize "$provider")"; then return 2; fi

    local cap
    if ! cap="$(_l2_get_daily_cap)"; then
        return 3
    fi

    local utc_day
    utc_day="$(_l2_now_utc_day)"

    # Per-provider sub-cap (optional). When provider is specified and a sub-cap
    # is configured, the sub-cap overrides the aggregate cap for verdict math.
    # provider has already been validated against _L2_PROVIDER_RE in
    # _l2_provider_normalize, but defense-in-depth: we still validate the
    # resulting sub_cap with _l2_validate_numeric before using it.
    if [[ "$provider" != "aggregate" ]]; then
        local sub_cap
        sub_cap="$(_l2_config_get ".cost_budget_enforcer.per_provider_caps.${provider}" "")"
        if [[ -n "$sub_cap" ]]; then
            if _l2_validate_numeric "$sub_cap" "per_provider_caps.${provider}"; then
                cap="$sub_cap"
            fi
        fi
    fi

    # Read counter (tail-scan for current UTC day + provider).
    local counter_json counter_usd counter_ts consistency
    counter_json="$(_l2_compute_counter "$provider" "$utc_day")"
    counter_usd="$(printf '%s' "$counter_json" | jq -r '.counter_usd')"
    counter_ts="$(printf '%s' "$counter_json" | jq -r '.counter_ts // empty')"
    consistency="$(printf '%s' "$counter_json" | jq -r '.consistency')"

    # Read billing API.
    local observer_json billing_usd billing_ts billing_age observer_used
    observer_json="$(_l2_invoke_observer "$provider")"
    if printf '%s' "$observer_json" | jq -e '._unreachable == true' >/dev/null 2>&1; then
        billing_usd=""
        billing_ts=""
        billing_age="null"
        observer_used="false"
    else
        billing_usd="$(printf '%s' "$observer_json" | jq -r '.usd_used // empty')"
        billing_ts="$(printf '%s' "$observer_json" | jq -r '.billing_ts // empty')"
        billing_age="$(_l2_compute_age_seconds "$billing_ts")"
        observer_used="true"
    fi

    local counter_age
    counter_age="$(_l2_compute_age_seconds "$counter_ts")"
    if [[ "$counter_age" == "null" ]]; then
        counter_age="0"
    fi

    # Authoritative usd_used. Default = counter; override with billing if fresh.
    local usd_used="$counter_usd"
    local fresh_threshold
    fresh_threshold="$(_l2_get_freshness_seconds)"
    local data_fresh="false"
    if [[ "$observer_used" == "true" && "$billing_age" != "null" ]] && (( billing_age <= fresh_threshold )); then
        usd_used="$billing_usd"
        data_fresh="true"
    fi
    # Counter-only freshness: counter is "fresh" if counter_age <= 5 min and
    # consistency is ok (no halt-uncertainty:counter_inconsistent).
    if [[ "$data_fresh" == "false" && "$consistency" == "ok" ]] && (( counter_age <= fresh_threshold )); then
        data_fresh="true"
    fi

    # ----- Uncertainty checks (PRD §FR-L2 + SDD §1.5.3 ordering) -----
    # Order: most-severe first.
    # 1. counter_inconsistent — counter is corrupt regardless of billing state
    # 2. counter_drift       — prior reconcile BLOCKER not yet operator-cleared
    # 3. billing_stale — billing API >billing_stale_threshold AND counter >cap_threshold
    # 4. provider_lag — billing API lag in [lag_threshold, billing_stale_threshold) AND counter >cap_threshold
    # 5. clock_drift — only when billing data is FRESH (billing_age <= freshness)
    # 6. counter_stale — no fresh signal at all (no observer + counter older than freshness)
    # 7. halt-100 / warn-90 / allow

    # 1. counter_inconsistent (always halt-uncertainty regardless of usage)
    if [[ "$consistency" != "ok" ]]; then
        local diag_inc
        diag_inc="$(jq -nc --arg c "$consistency" '{counter_state: $c}')"
        local payload
        payload="$(_l2_render_verdict "halt-uncertainty" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id" "counter_inconsistent" "$diag_inc")"
        _l2_emit_and_return "budget.halt_uncertainty" "$payload"
        return $?
    fi

    # 2. counter_drift — prior reconcile BLOCKER must be cleared by operator
    #    via force-reconcile before allowing further verdicts (MED-3 review).
    local drift_blocker
    drift_blocker="$(_l2_recent_drift_blocker "$provider" "$utc_day")"
    if [[ -n "$drift_blocker" ]]; then
        local payload
        payload="$(_l2_render_verdict "halt-uncertainty" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id" "counter_drift" "$drift_blocker")"
        _l2_emit_and_return "budget.halt_uncertainty" "$payload"
        return $?
    fi

    local stale_halt_pct
    stale_halt_pct="$(_l2_get_stale_halt_pct)"

    # Compute counter_pct (used by 2,3 below).
    local counter_pct
    counter_pct="$(python3 -c "
cap = float('${cap}')
counter = float('${counter_usd}')
print(0 if cap == 0 else round(100 * counter / cap, 6))
")"

    # 3. billing_stale (billing API >= billing_stale threshold AND counter > stale_halt_pct)
    if [[ "$observer_used" == "true" && "$billing_age" != "null" ]]; then
        local billing_stale_threshold
        billing_stale_threshold="$(_l2_get_billing_stale_seconds)"
        if (( billing_age >= billing_stale_threshold )); then
            if python3 -c "import sys; sys.exit(0 if float('$counter_pct') > float('$stale_halt_pct') else 1)"; then
                local diag_stale
                diag_stale="$(jq -nc \
                    --argjson billing_age "$billing_age" \
                    --argjson stale_threshold "$billing_stale_threshold" \
                    --argjson counter_pct "$counter_pct" \
                    --argjson stale_halt_pct "$stale_halt_pct" \
                    '{billing_age_seconds: $billing_age, stale_threshold_seconds: $stale_threshold, counter_pct: $counter_pct, stale_halt_pct: $stale_halt_pct}')"
                local payload
                payload="$(_l2_render_verdict "halt-uncertainty" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id" "billing_stale" "$diag_stale")"
                _l2_emit_and_return "budget.halt_uncertainty" "$payload"
                return $?
            fi
        fi
    fi

    # 4. provider_lag (billing API lag >= lag_halt_seconds AND counter > stale_halt_pct)
    #    Comes AFTER billing_stale so billing_stale wins for very-stale data.
    if [[ "$observer_used" == "true" && "$billing_age" != "null" ]]; then
        local lag_threshold
        lag_threshold="$(_l2_get_lag_halt_seconds)"
        if (( billing_age >= lag_threshold )); then
            if python3 -c "import sys; sys.exit(0 if float('$counter_pct') > float('$stale_halt_pct') else 1)"; then
                local diag_lag
                diag_lag="$(jq -nc \
                    --argjson lag "$billing_age" \
                    --argjson lag_threshold "$lag_threshold" \
                    --argjson counter_pct "$counter_pct" \
                    --argjson stale_halt_pct "$stale_halt_pct" \
                    '{lag_seconds: $lag, threshold_seconds: $lag_threshold, counter_pct: $counter_pct, stale_halt_pct: $stale_halt_pct}')"
                local payload
                payload="$(_l2_render_verdict "halt-uncertainty" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id" "provider_lag" "$diag_lag")"
                _l2_emit_and_return "budget.halt_uncertainty" "$payload"
                return $?
            fi
        fi
    fi

    # 5. clock_drift — ONLY when billing data is fresh (billing_age <= freshness).
    #    Stale billing_ts will naturally appear "drifted" from system clock; that
    #    is not a clock-drift signal, it's a staleness signal (handled above).
    if [[ "$observer_used" == "true" && -n "$billing_ts" && "$billing_age" != "null" ]]; then
        if (( billing_age <= fresh_threshold )); then
            local drift_delta drift_rc
            drift_delta="$(_l2_check_clock_drift "$billing_ts" || true)"
            if _l2_check_clock_drift "$billing_ts" >/dev/null; then
                drift_rc=0
            else
                drift_rc=$?
            fi
            if (( drift_rc == 1 )); then
                local sys_ts tolerance diag_clk
                sys_ts="$(_l2_now_iso8601)"
                tolerance="$(_l2_get_clock_tolerance)"
                diag_clk="$(jq -nc \
                    --arg sys_ts "$sys_ts" \
                    --arg billing_ts "$billing_ts" \
                    --argjson delta "$drift_delta" \
                    --argjson tol "$tolerance" \
                    '{system_ts: $sys_ts, billing_ts: $billing_ts, delta_seconds: $delta, tolerance_seconds: $tol}')"
                local payload
                payload="$(_l2_render_verdict "halt-uncertainty" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id" "clock_drift" "$diag_clk")"
                _l2_emit_and_return "budget.halt_uncertainty" "$payload"
                return $?
            fi
        fi
    fi

    # 6. counter_stale — no observer + counter is stale OR has positive value
    #    but no fresh signal at all. Closes review HIGH-1 fail-open hole.
    #    The check applies when observer_used=false AND data_fresh=false. When
    #    no entries exist for today (counter_usd=0, counter_ts=null →
    #    counter_age=0), data_fresh was set true above; allow proceeds.
    if [[ "$data_fresh" != "true" ]]; then
        local diag_cs
        diag_cs="$(jq -nc \
            --argjson counter_age "$counter_age" \
            --argjson freshness_threshold "$fresh_threshold" \
            --argjson counter_usd "$counter_usd" \
            --arg observer_used "$observer_used" \
            '{counter_age_seconds: $counter_age, freshness_threshold_seconds: $freshness_threshold, counter_usd: $counter_usd, observer_used: ($observer_used == "true")}')"
        local payload
        payload="$(_l2_render_verdict "halt-uncertainty" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id" "counter_stale" "$diag_cs")"
        _l2_emit_and_return "budget.halt_uncertainty" "$payload"
        return $?
    fi

    # ----- Threshold checks (data is fresh; cleanly bucket) -----
    # Compute usage% projected (post-call, for halt-100 / warn-90 transition)
    local projected_pct
    projected_pct="$(python3 -c "
cap = float('${cap}')
used = float('${usd_used}')
est = float('${estimated_usd}')
print(0 if cap == 0 else round(100 * (used + est) / cap, 6))
")"

    # halt-100: post-call usage would be >= 100%
    if python3 -c "import sys; sys.exit(0 if float('$projected_pct') >= 100 else 1)"; then
        local payload
        payload="$(_l2_render_verdict "halt-100" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id")"
        _l2_emit_and_return "budget.halt_100" "$payload"
        return $?
    fi

    # warn-90: post-call usage would be >= 90% (still fresh, still below 100%)
    if python3 -c "import sys; sys.exit(0 if float('$projected_pct') >= 90 else 1)"; then
        local payload
        payload="$(_l2_render_verdict "warn-90" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id")"
        _l2_emit_and_return "budget.warn_90" "$payload"
        return $?
    fi

    # default: allow. Fail-closed safety: when no observer AND no fresh counter,
    # we treated counter_age==0 (no entries today) as fresh; this is correct
    # because zero-usage is unambiguous.
    local payload
    payload="$(_l2_render_verdict "allow" "$usd_used" "$cap" "$estimated_usd" "$provider" "$utc_day" "$billing_age" "$counter_age" "$observer_used" "$cycle_id")"
    _l2_emit_and_return "budget.allow" "$payload"
}

# -----------------------------------------------------------------------------
# budget_reconcile [--provider <id>] [--force-reason <text>]
#
# Compare counter to billing API for current UTC day; emit budget.reconcile
# event with drift_pct + blocker flag. Counter NOT auto-corrected.
# Sprint 2A: function unit. Sprint 2B: cron registration via /schedule.
# -----------------------------------------------------------------------------
budget_reconcile() {
    _l2_propagate_test_now
    local provider="" force_reason=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider) provider="$2"; shift 2 ;;
            --force-reason) force_reason="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    if ! provider="$(_l2_provider_normalize "$provider")"; then return 2; fi

    local utc_day
    utc_day="$(_l2_now_utc_day)"

    local counter_json counter_usd
    counter_json="$(_l2_compute_counter "$provider" "$utc_day")"
    counter_usd="$(printf '%s' "$counter_json" | jq -r '.counter_usd')"

    local observer_json billing_usd billing_unreachable
    observer_json="$(_l2_invoke_observer "$provider")"
    # Sprint 2B: observer may signal {"_defer": true, "_reason": "rate_limited"}
    # to indicate transient failure; in that case we skip silently and let the
    # next cron interval retry. Audit log is NOT touched.
    if printf '%s' "$observer_json" | jq -e '._defer == true' >/dev/null 2>&1; then
        local reason
        reason="$(printf '%s' "$observer_json" | jq -r '._reason // "unspecified"')"
        _l2_log "budget_reconcile: observer requested defer (provider=$provider reason=$reason)"
        return 2
    fi
    if printf '%s' "$observer_json" | jq -e '._unreachable == true' >/dev/null 2>&1; then
        billing_usd="null"
        billing_unreachable="true"
    else
        billing_usd="$(printf '%s' "$observer_json" | jq -r '.usd_used // null')"
        billing_unreachable="false"
    fi

    local drift_threshold
    drift_threshold="$(_l2_get_drift_threshold)"

    local drift_pct blocker
    if [[ "$billing_unreachable" == "true" ]]; then
        drift_pct="null"
        # blocker iff counter > stale_halt_pct (defer-to-next-interval policy).
        local stale_halt_pct cap counter_pct
        stale_halt_pct="$(_l2_get_stale_halt_pct)"
        if cap="$(_l2_get_daily_cap 2>/dev/null)"; then
            counter_pct="$(python3 -c "
cap = float('${cap}')
counter = float('${counter_usd}')
print(0 if cap == 0 else round(100 * counter / cap, 6))
")"
            if python3 -c "import sys; sys.exit(0 if float('$counter_pct') > float('$stale_halt_pct') else 1)"; then
                blocker="true"
            else
                blocker="false"
            fi
        else
            blocker="false"
        fi
    else
        drift_pct="$(python3 -c "
counter = float('${counter_usd}')
billing = float('${billing_usd}')
denom = max(counter, billing)
if denom == 0:
    print(0)
else:
    print(round(100 * abs(counter - billing) / denom, 6))
")"
        if python3 -c "import sys; sys.exit(0 if float('$drift_pct') > float('$drift_threshold') else 1)"; then
            blocker="true"
        else
            blocker="false"
        fi
    fi

    local payload
    payload="$(jq -nc \
        --argjson counter "$counter_usd" \
        --argjson billing "$billing_usd" \
        --argjson drift_pct "$drift_pct" \
        --argjson threshold "$drift_threshold" \
        --argjson blocker "$blocker" \
        --argjson unreach "$billing_unreachable" \
        --arg provider "$provider" \
        --arg utc_day "$utc_day" \
        --arg force_reason "$force_reason" \
        '{
            verdict: "reconcile",
            counter_usd: $counter,
            billing_usd: $billing,
            drift_pct: $drift_pct,
            drift_threshold_pct: $threshold,
            blocker: $blocker,
            provider: $provider,
            utc_day: $utc_day,
            billing_api_unreachable: $unreach,
            force_reconcile: ($force_reason != "")
        }
        | if $force_reason != "" then . + {operator_reason: $force_reason} else . + {operator_reason: null} end')"

    _l2_audit_emit_event "budget.reconcile" "$payload" || return 1
    printf '%s\n' "$payload"
    if [[ "$blocker" == "true" ]]; then
        return 1
    fi
    return 0
}
