#!/usr/bin/env bash
# =============================================================================
# scheduled-cycle-lib.sh — L3 scheduled-cycle-template (Sprint 3A)
#
# cycle-098 Sprint 3A — implementation of the L3 generic 5-phase autonomous-
# cycle template per RFC #655, PRD FR-L3 (8 ACs), SDD §1.4.2 + §5.5.
#
# Composition (does NOT reinvent):
#   - 1A audit envelope:       audit_emit (writes JSONL with prev_hash chain)
#   - 1B signing scheme:       audit_emit honors LOA_AUDIT_SIGNING_KEY_ID
#   - 1A JCS canonicalization: jcs_canonicalize for dispatch_contract_hash
#   - 1.5 trust-store check:   audit_emit auto-verifies trust-store
#   - 2  L2 budget verdict:    budget_verdict pre-read check (3C — compose-when-available)
#
# 5-phase contract dispatch (SDD §5.5):
#   reader → decider → dispatcher → awaiter → logger
#
# Each phase is a caller-supplied script invoked as:
#     <phase_path> <cycle_id> <schedule_id> <phase_index> <prior_phases_json>
#
#   stdout: arbitrary; sha256 of stdout is captured as `output_hash` (replay marker).
#   stderr: tail (last 4KB) captured as diagnostic on error/timeout.
#   exit 0: phase succeeded
#   exit non-zero: phase failed; cycle aborts with cycle.error event.
#
# Audit events (per-event-type schemas in .claude/data/trajectory-schemas/cycle-events/):
#   cycle.start         emitted post-lock + post-budget-check; one per cycle
#   cycle.phase         emitted once per phase (5 per successful cycle)
#   cycle.complete      emitted on success only (terminal); marks idempotency state
#   cycle.error         emitted on failure (pre_check halt OR phase_error/phase_timeout)
#   cycle.lock_failed   emitted by Sprint 3B when flock acquire fails
#
# Public functions:
#   cycle_invoke <schedule_yaml_path> [--cycle-id <id>] [--dry-run]
#       Fires the 5-phase loop. Returns 0 on cycle.complete; 1 on cycle.error.
#       Exits 4 on lock contention (Sprint 3B).
#
#   cycle_idempotency_check <cycle_id> [--log-path <path>]
#       Returns 0 if cycle.complete for cycle_id is present in the log (no-op needed).
#       Returns 1 if not present (cycle should run).
#
#   cycle_replay <log_path> [--cycle-id <id>]
#       Reassembles the SDD §5.5.3 CycleRecord from cycle.start + cycle.phase
#       + cycle.complete/error events. Stdout: JSON CycleRecord array (one per
#       cycle_id) or single object when --cycle-id specified.
#
#   cycle_record_phase <cycle_id> <phase> <result_json>
#       Direct emission of a cycle.phase event (advanced; usually internal).
#
#   cycle_complete <cycle_id> <final_record_json>
#       Direct emission of a cycle.complete event (advanced; usually internal).
#
# Environment variables:
#   LOA_CYCLES_LOG               audit log path (default .run/cycles.jsonl)
#   LOA_L3_PHASE_TIMEOUT_DEFAULT default per-phase timeout in seconds (default 300)
#   LOA_L3_TEST_NOW              test-only override for "now" (ISO-8601);
#                                  also propagated to LOA_AUDIT_TEST_NOW.
#   LOA_L3_CONFIG_FILE           override .loa.config.yaml path
#
# Exit codes:
#   0 = cycle.complete emitted (success)
#   1 = cycle.error emitted (phase failure or budget halt)
#   2 = invalid arguments / contract validation failure
#   3 = configuration error
#   4 = lock contention (cycle.lock_failed emitted) — Sprint 3B
# =============================================================================

set -euo pipefail

if [[ "${_LOA_L3_LIB_SOURCED:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
_LOA_L3_LIB_SOURCED=1

_L3_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_L3_REPO_ROOT="$(cd "${_L3_DIR}/../../.." && pwd)"
_L3_AUDIT_ENVELOPE="${_L3_REPO_ROOT}/.claude/scripts/audit-envelope.sh"
_L3_SCHEMA_DIR="${_L3_REPO_ROOT}/.claude/data/trajectory-schemas/cycle-events"
_L3_DEFAULT_LOG=".run/cycles.jsonl"
_L3_DEFAULT_LOCK_DIR=".run/cycles"
_L3_DEFAULT_PHASE_TIMEOUT=300
_L3_DEFAULT_LOCK_TIMEOUT=30
_L3_DEFAULT_KILL_GRACE_SECONDS=5
# Cap on total cycle wall-clock (5 phases × per-phase budget) — defense
# against malicious schedule yamls that set timeout_seconds: 86400 to park
# the lock for days. Override via LOA_L3_MAX_CYCLE_SECONDS or
# .scheduled_cycle_template.max_cycle_seconds.
_L3_DEFAULT_MAX_CYCLE_SECONDS=14400   # 4h × 1 cycle
_L3_PHASES=(reader decider dispatcher awaiter logger)
# Default allowlist for dispatch_contract phase script paths. Phase scripts
# resolved outside these prefixes are rejected. Add deployment-specific
# directories via .scheduled_cycle_template.phase_path_allowed_prefixes (yaml
# array) or LOA_L3_PHASE_PATH_ALLOWED_PREFIXES (colon-separated env).
_L3_DEFAULT_PHASE_ALLOWLIST=(
    ".claude/skills"
    ".run/schedules"
    ".run/cycles-contracts"
)
# Default env-passthrough allowlist into phase scripts. Anything not in this
# list is stripped before phase execution. Caller can extend per-schedule via
# dispatch_contract.env_passthrough.
_L3_DEFAULT_ENV_ALLOWLIST=(
    PATH HOME USER LANG LC_ALL LC_CTYPE TZ TMPDIR TERM SHELL
    LOA_L3_CYCLE_ID LOA_L3_SCHEDULE_ID LOA_L3_PHASE_INDEX
)

# shellcheck source=../audit-envelope.sh
source "${_L3_AUDIT_ENVELOPE}"

_l3_log() { echo "[scheduled-cycle] $*" >&2; }

# -----------------------------------------------------------------------------
# _l3_test_mode — returns 0 when tests / fixtures are running. Used to gate
# escape hatches like LOA_L3_L2_LIB_OVERRIDE and (eventually) --cycle-id
# overrides off in production paths. Detection: BATS_TEST_DIRNAME set, or
# explicit LOA_L3_TEST_MODE=1.
# -----------------------------------------------------------------------------
_l3_test_mode() {
    if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then return 0; fi
    if [[ "${LOA_L3_TEST_MODE:-}" == "1" || "${LOA_L3_TEST_MODE:-}" == "true" ]]; then return 0; fi
    return 1
}

# -----------------------------------------------------------------------------
# _l3_safe_touch_lock <lock_file>
#
# Symlink-safe lock-file creation (CRITICAL audit finding). The legacy
# `: > "$lock_file"` redirect FOLLOWS symlinks; an attacker who can stage a
# symlink at <lock_dir>/<schedule_id>.lock pointing at any writable file
# weaponizes the lock-touch into a write-anywhere truncate primitive.
# This helper:
#   - rejects existing lock paths that are symlinks
#   - creates the file with mode 0600 via Python os.open(O_CREAT|O_NOFOLLOW)
#   - falls back to bash + post-creation symlink check on systems without python3
# Returns 0 on safe creation; 1 on policy violation.
# -----------------------------------------------------------------------------
_l3_safe_touch_lock() {
    local lock_file="$1"
    if [[ -L "$lock_file" ]]; then
        _l3_log "ERROR: lock path is a symlink (refusing to follow): $lock_file"
        return 1
    fi
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 - "$lock_file" <<'PY' 2>/dev/null
import os, sys
path = sys.argv[1]
flags = os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW
try:
    fd = os.open(path, flags, 0o600)
    os.close(fd)
except FileExistsError:
    # Already exists as a regular file; fine. (O_CREAT without O_EXCL.)
    pass
except OSError as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY
        then
            _l3_log "ERROR: failed to create lock file safely: $lock_file"
            return 1
        fi
    else
        # No python3 — fall back to bash with a post-creation check.
        ( umask 077 && touch "$lock_file" ) 2>/dev/null || {
            _l3_log "ERROR: cannot touch lock file: $lock_file"
            return 1
        }
        if [[ -L "$lock_file" ]]; then
            _l3_log "ERROR: lock file became a symlink during creation: $lock_file"
            return 1
        fi
    fi
    return 0
}

# -----------------------------------------------------------------------------
# _l3_get_phase_allowlist — return newline-separated absolute prefix list.
# Sources: LOA_L3_PHASE_PATH_ALLOWED_PREFIXES (colon-separated env override),
# .scheduled_cycle_template.phase_path_allowed_prefixes (yaml array),
# default _L3_DEFAULT_PHASE_ALLOWLIST.
# -----------------------------------------------------------------------------
_l3_get_phase_allowlist() {
    if [[ -n "${LOA_L3_PHASE_PATH_ALLOWED_PREFIXES:-}" ]]; then
        local prefix
        local IFS=":"
        for prefix in $LOA_L3_PHASE_PATH_ALLOWED_PREFIXES; do
            if [[ "$prefix" = /* ]]; then
                echo "$prefix"
            else
                echo "${_L3_REPO_ROOT}/${prefix}"
            fi
        done
        return 0
    fi
    # YAML list (one path per line).
    local yaml_list
    yaml_list="$(_l3_config_get '.scheduled_cycle_template.phase_path_allowed_prefixes' '')"
    if [[ -n "$yaml_list" && "$yaml_list" != "null" ]]; then
        # yq with `-r` on an array prints each element on a line; PyYAML
        # fallback prints repr-like; cope with either by stripping brackets/quotes.
        local p
        while IFS= read -r p; do
            p="${p#- }"; p="${p#\"}"; p="${p%\"}"; p="${p//\'/}"
            [[ -z "$p" ]] && continue
            if [[ "$p" = /* ]]; then echo "$p"; else echo "${_L3_REPO_ROOT}/${p}"; fi
        done <<<"$yaml_list"
        return 0
    fi
    local default_p
    for default_p in "${_L3_DEFAULT_PHASE_ALLOWLIST[@]}"; do
        echo "${_L3_REPO_ROOT}/${default_p}"
    done
}

# -----------------------------------------------------------------------------
# _l3_validate_phase_path <raw_path> <phase_name>
#
# Canonicalize raw_path (resolving .., symlinks, relative-to-repo prefix) and
# verify it lives under one of the allowed prefixes. Returns 0 + canonical
# path on stdout; 1 on policy violation. CRITICAL audit finding.
# -----------------------------------------------------------------------------
_l3_validate_phase_path() {
    local raw="$1"
    local phase="$2"
    if [[ -z "$raw" ]]; then
        _l3_log "ERROR: ${phase} phase path is empty"
        return 1
    fi
    local resolved
    if [[ "$raw" = /* ]]; then
        resolved="$raw"
    else
        resolved="${_L3_REPO_ROOT}/${raw}"
    fi
    # Canonicalize. Use realpath if available; fallback to python3.
    local canon=""
    if command -v realpath >/dev/null 2>&1; then
        canon="$(realpath -m "$resolved" 2>/dev/null || true)"
    fi
    if [[ -z "$canon" ]] && command -v python3 >/dev/null 2>&1; then
        canon="$(python3 -c "import os, sys; print(os.path.normpath(sys.argv[1]))" "$resolved" 2>/dev/null || true)"
    fi
    if [[ -z "$canon" ]]; then
        _l3_log "ERROR: cannot canonicalize ${phase} path: $raw"
        return 1
    fi
    # Reject canonical paths still containing /../ (can happen if normpath
    # fails to resolve due to missing dirs; defense in depth).
    if [[ "$canon" == *"/.."* || "$canon" == *"/../"* ]]; then
        _l3_log "ERROR: ${phase} path contains traversal after normalize: $canon"
        return 1
    fi
    # Walk allowlist; require canonical path to start with one of the
    # canonical prefixes (also normalized).
    local prefix prefix_canon
    while IFS= read -r prefix; do
        if command -v realpath >/dev/null 2>&1; then
            prefix_canon="$(realpath -m "$prefix" 2>/dev/null || echo "$prefix")"
        else
            prefix_canon="$prefix"
        fi
        # Strip trailing slash for clean prefix matching.
        prefix_canon="${prefix_canon%/}"
        if [[ "$canon" == "$prefix_canon"/* ]]; then
            echo "$canon"
            return 0
        fi
    done < <(_l3_get_phase_allowlist)
    _l3_log "ERROR: ${phase} path outside allowlist: $canon"
    _l3_log "  Allowed prefixes (configure via .scheduled_cycle_template.phase_path_allowed_prefixes):"
    _l3_get_phase_allowlist | sed 's/^/    /' >&2
    return 1
}

# -----------------------------------------------------------------------------
# _l3_get_env_passthrough — return space-separated env var names that should
# be inherited from the cycle's environment by phase scripts. Defaults to a
# minimal allowlist; caller-extendable per-schedule via dispatch_contract.
# -----------------------------------------------------------------------------
_l3_get_env_passthrough() {
    local extras="${1:-}"   # space-separated extra var names from dispatch_contract
    local v
    for v in "${_L3_DEFAULT_ENV_ALLOWLIST[@]}"; do
        echo "$v"
    done
    if [[ -n "$extras" ]]; then
        for v in $extras; do
            # Only allow [A-Z_][A-Z0-9_]* (env var name regex).
            if [[ "$v" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
                echo "$v"
            else
                _l3_log "WARN: ignoring invalid env passthrough name: $v"
            fi
        done
    fi
}

# -----------------------------------------------------------------------------
# _l3_get_max_cycle_seconds — total cycle wall-clock cap.
# -----------------------------------------------------------------------------
_l3_get_max_cycle_seconds() {
    local v
    v="${LOA_L3_MAX_CYCLE_SECONDS:-$(_l3_config_get '.scheduled_cycle_template.max_cycle_seconds' "$_L3_DEFAULT_MAX_CYCLE_SECONDS")}"
    if ! [[ "$v" =~ $_L3_INT_RE ]]; then
        v="$_L3_DEFAULT_MAX_CYCLE_SECONDS"
    fi
    echo "$v"
}

# -----------------------------------------------------------------------------
# _l3_iso_to_epoch <iso8601_ts> — parse ISO-8601 to Unix epoch. Honors
# microseconds + Z. Returns "" on parse failure (printed nothing on stdout
# means caller should fallback). Used by _l3_run_phase + _l3_cycle_invoke_inner
# to derive duration_seconds deterministically (HIGH-R3 review fix — wall-clock
# date +%s leaked through LOA_L3_TEST_NOW frozen-clock fixtures).
# -----------------------------------------------------------------------------
_l3_iso_to_epoch() {
    local ts="$1"
    [[ -z "$ts" || "$ts" == "null" ]] && return 1
    # GNU date supports ISO directly via -d.
    if date -u -d "$ts" +%s 2>/dev/null; then
        return 0
    fi
    # Python fallback (handles BSD date / macOS).
    python3 - "$ts" <<'PY' 2>/dev/null
import sys
from datetime import datetime
s = sys.argv[1]
if s.endswith("Z"):
    s = s[:-1] + "+00:00"
try:
    print(int(datetime.fromisoformat(s).timestamp()))
except Exception:
    sys.exit(1)
PY
}

# Validation regexes. schedule_id matches the per-event-schema pattern.
_L3_SCHEDULE_ID_RE='^[a-z0-9][a-z0-9_-]{0,63}$'
# cycle_id is content-addressed (sha256 hex 64 chars by default) but may be
# caller-supplied via --cycle-id. Restrict to safe chars; max 256 to match schema.
_L3_CYCLE_ID_RE='^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$'
_L3_INT_RE='^[0-9]+$'

# -----------------------------------------------------------------------------
# _l3_validate_schedule_id <id>
# Returns 0 if id matches the schema-required pattern; 1 otherwise.
# -----------------------------------------------------------------------------
_l3_validate_schedule_id() {
    local id="$1"
    if [[ -z "$id" ]] || ! [[ "$id" =~ $_L3_SCHEDULE_ID_RE ]]; then
        _l3_log "ERROR: invalid schedule_id '$id' (expected $_L3_SCHEDULE_ID_RE)"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# _l3_validate_cycle_id <id>
# -----------------------------------------------------------------------------
_l3_validate_cycle_id() {
    local id="$1"
    if [[ -z "$id" ]] || ! [[ "$id" =~ $_L3_CYCLE_ID_RE ]]; then
        _l3_log "ERROR: invalid cycle_id '$id' (expected $_L3_CYCLE_ID_RE)"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# _l3_propagate_test_now — when LOA_L3_TEST_NOW is set, also export to
# LOA_AUDIT_TEST_NOW so audit-envelope writes the matching ts_utc.
# CRITICAL: must run in caller scope before any $(...) substitution that
# reads "now" (subshell-export gotcha — see feedback_subshell_export_gotcha).
# -----------------------------------------------------------------------------
_l3_propagate_test_now() {
    if [[ -n "${LOA_L3_TEST_NOW:-}" ]]; then
        export LOA_AUDIT_TEST_NOW="$LOA_L3_TEST_NOW"
    fi
}

_l3_now_iso8601() {
    if [[ -n "${LOA_L3_TEST_NOW:-}" ]]; then
        echo "$LOA_L3_TEST_NOW"
    else
        _audit_now_iso8601
    fi
}

# -----------------------------------------------------------------------------
# _l3_get_log_path — resolved cycles.jsonl path (env > config > default).
# -----------------------------------------------------------------------------
_l3_get_log_path() {
    if [[ -n "${LOA_CYCLES_LOG:-}" ]]; then
        echo "$LOA_CYCLES_LOG"
        return 0
    fi
    local relpath
    relpath="$(_l3_config_get '.scheduled_cycle_template.audit_log' "$_L3_DEFAULT_LOG")"
    if [[ "$relpath" = /* ]]; then
        echo "$relpath"
    else
        echo "${_L3_REPO_ROOT}/${relpath}"
    fi
}

# -----------------------------------------------------------------------------
# _l3_get_lock_dir — directory holding per-schedule lock files.
# -----------------------------------------------------------------------------
_l3_get_lock_dir() {
    if [[ -n "${LOA_L3_LOCK_DIR:-}" ]]; then
        echo "$LOA_L3_LOCK_DIR"
        return 0
    fi
    local relpath
    relpath="$(_l3_config_get '.scheduled_cycle_template.lock_dir' "$_L3_DEFAULT_LOCK_DIR")"
    if [[ "$relpath" = /* ]]; then
        echo "$relpath"
    else
        echo "${_L3_REPO_ROOT}/${relpath}"
    fi
}

# -----------------------------------------------------------------------------
# _l3_get_lock_timeout — seconds to wait for flock acquisition.
# -----------------------------------------------------------------------------
_l3_get_lock_timeout() {
    local v
    v="${LOA_L3_LOCK_TIMEOUT_SECONDS:-$(_l3_config_get '.scheduled_cycle_template.lock_timeout_seconds' "$_L3_DEFAULT_LOCK_TIMEOUT")}"
    if ! [[ "$v" =~ $_L3_INT_RE ]]; then
        v="$_L3_DEFAULT_LOCK_TIMEOUT"
    fi
    echo "$v"
}

_l3_config_path() {
    echo "${LOA_L3_CONFIG_FILE:-${_L3_REPO_ROOT}/.loa.config.yaml}"
}

# -----------------------------------------------------------------------------
# _l3_config_get <yaml_path> [default]
# Read a value from .loa.config.yaml (yq if available; PyYAML fallback).
# -----------------------------------------------------------------------------
_l3_config_get() {
    local yq_path="$1"
    local default="${2:-}"
    local config
    config="$(_l3_config_path)"
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
    local clean_path="${yq_path#.}"
    python3 - "$config" "$clean_path" "$default" <<'PY' 2>/dev/null || echo "$default"
import sys
try:
    import yaml
except ImportError:
    print(sys.argv[3]); sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print(sys.argv[3]); sys.exit(0)
parts = sys.argv[2].split('.')
node = doc
for p in parts:
    if isinstance(node, dict) and p in node:
        node = node[p]
    else:
        print(sys.argv[3]); sys.exit(0)
if node is None or node == "":
    print(sys.argv[3])
else:
    print(node)
PY
}

# -----------------------------------------------------------------------------
# _l3_is_l2_enabled — returns 0 if L2 budget pre-check should run for this
# invocation. Sources of truth, in order:
#   1. LOA_L3_BUDGET_PRECHECK_ENABLED env var ("1" / "true")
#   2. .scheduled_cycle_template.budget_pre_check yaml key ("true")
# Default: false (compose-when-available; opt-in per CC-9).
# -----------------------------------------------------------------------------
_l3_is_l2_enabled() {
    if [[ -n "${LOA_L3_BUDGET_PRECHECK_ENABLED:-}" ]]; then
        local v="${LOA_L3_BUDGET_PRECHECK_ENABLED,,}"
        [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" ]]
        return $?
    fi
    local cfg
    cfg="$(_l3_config_get '.scheduled_cycle_template.budget_pre_check' 'false')"
    cfg="${cfg,,}"
    [[ "$cfg" == "true" || "$cfg" == "1" || "$cfg" == "yes" ]]
}

# -----------------------------------------------------------------------------
# _l3_run_budget_pre_check <budget_estimate_usd> <cycle_id>
#
# Compose-when-available L2 budget gate for the L3 pre-read phase (FR-L3-6 +
# CC-9). Side-effect free w.r.t. cycles.jsonl — L2 emits its own audit events
# to .run/cost-budget-events.jsonl when a verdict is computed.
#
# Stdout (always; jq-safe JSON):
#   "null"                                                — no L2 call made
#   {"verdict":"<v>","usd_estimate":<n>,"checked_at":"<ts>"}
#                                                          — L2 verdict computed
#
# Exit codes:
#   0 = proceed (allow / warn-90, OR L2 disabled / unavailable / zero estimate)
#   1 = halt (halt-100 / halt-uncertainty)
# -----------------------------------------------------------------------------
_l3_run_budget_pre_check() {
    local budget_estimate="$1"
    local cycle_id="$2"
    local checked_at
    checked_at="$(_l3_now_iso8601)"

    if ! _l3_is_l2_enabled; then
        echo "null"
        return 0
    fi
    # Skip when caller has nothing material to estimate.
    if [[ -z "$budget_estimate" || "$budget_estimate" == "0" || "$budget_estimate" == "0.0" || "$budget_estimate" == "null" ]]; then
        echo "null"
        return 0
    fi

    # Resolve L2 lib path. LOA_L3_L2_LIB_OVERRIDE is a TEST-ONLY escape hatch;
    # in production it would source attacker-controlled bash code into the
    # cycle process at top scope (HIGH-A2 audit finding). Honor only when
    # _l3_test_mode returns true (BATS_TEST_DIRNAME set or LOA_L3_TEST_MODE=1).
    local l2_lib="${_L3_REPO_ROOT}/.claude/scripts/lib/cost-budget-enforcer-lib.sh"
    if [[ -n "${LOA_L3_L2_LIB_OVERRIDE:-}" ]]; then
        if _l3_test_mode; then
            l2_lib="$LOA_L3_L2_LIB_OVERRIDE"
        else
            _l3_log "WARN: LOA_L3_L2_LIB_OVERRIDE ignored outside test mode (set LOA_L3_TEST_MODE=1 or run under bats)"
        fi
    fi
    if [[ ! -f "$l2_lib" ]]; then
        _l3_log "WARN: L2 budget pre-check requested but $l2_lib missing; cycle proceeds without gate"
        echo "null"
        return 0
    fi
    # shellcheck source=cost-budget-enforcer-lib.sh
    source "$l2_lib" || {
        _l3_log "WARN: failed to source L2 lib at $l2_lib; cycle proceeds without gate"
        echo "null"
        return 0
    }
    if ! declare -f budget_verdict >/dev/null; then
        _l3_log "WARN: L2 lib did not register budget_verdict; cycle proceeds without gate"
        echo "null"
        return 0
    fi

    local verdict_json verdict_rc=0
    verdict_json="$(budget_verdict "$budget_estimate" --cycle-id "$cycle_id" 2>/dev/null)" || verdict_rc=$?

    # budget_verdict prints multiple lines (info + final JSON on the last line).
    # Take the last non-empty line as the verdict JSON.
    local verdict_last
    verdict_last="$(printf '%s' "$verdict_json" | awk 'NF{last=$0} END{print last}')"
    if [[ -z "$verdict_last" ]] || ! printf '%s' "$verdict_last" | jq -e . >/dev/null 2>&1; then
        _l3_log "WARN: budget_verdict returned no parseable JSON (rc=${verdict_rc}); cycle proceeds without gate"
        echo "null"
        return 0
    fi

    local verdict
    verdict="$(printf '%s' "$verdict_last" | jq -r '.verdict')"
    if [[ -z "$verdict" || "$verdict" == "null" ]]; then
        _l3_log "WARN: budget_verdict missing .verdict field; cycle proceeds without gate"
        echo "null"
        return 0
    fi

    # Build cycle.start.budget_pre_check object.
    local pre_check_obj
    pre_check_obj="$(jq -nc \
        --arg v "$verdict" \
        --argjson est "$budget_estimate" \
        --arg checked "$checked_at" \
        '{verdict:$v, usd_estimate:$est, checked_at:$checked}')"
    echo "$pre_check_obj"

    case "$verdict" in
        halt-100|halt-uncertainty) return 1 ;;
        *)                          return 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# _l3_parse_schedule_yaml <path>
#
# Read a ScheduleConfig YAML and emit a JSON object with the fields:
#   schedule_id, schedule, dispatch_contract:{reader,decider,dispatcher,
#   awaiter,logger,budget_estimate_usd,timeout_seconds}
#
# Validates required fields. Does NOT validate phase script existence (that
# is a runtime check inside _l3_run_phase, so dispatch contracts authored on
# one host but invoked on another don't fail at parse time).
#
# Returns 0 + JSON on success; non-zero on parse/required-field failure.
# -----------------------------------------------------------------------------
_l3_parse_schedule_yaml() {
    local yaml_path="$1"
    if [[ ! -f "$yaml_path" ]]; then
        _l3_log "ERROR: schedule yaml not found: $yaml_path"
        return 2
    fi
    python3 - "$yaml_path" <<'PY'
import json, sys
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required to parse schedule yaml", file=sys.stderr); sys.exit(2)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception as e:
    print(f"ERROR: yaml parse failed: {e}", file=sys.stderr); sys.exit(2)
if not isinstance(doc, dict):
    print("ERROR: schedule yaml must be a mapping", file=sys.stderr); sys.exit(2)
required_top = ["schedule_id", "schedule", "dispatch_contract"]
for k in required_top:
    if k not in doc:
        print(f"ERROR: missing required field: {k}", file=sys.stderr); sys.exit(2)
dc = doc.get("dispatch_contract")
if not isinstance(dc, dict):
    print("ERROR: dispatch_contract must be a mapping", file=sys.stderr); sys.exit(2)
required_dc = ["reader", "decider", "dispatcher", "awaiter", "logger"]
for k in required_dc:
    if k not in dc:
        print(f"ERROR: missing dispatch_contract.{k}", file=sys.stderr); sys.exit(2)
out = {
    "schedule_id": doc["schedule_id"],
    "schedule": doc["schedule"],
    "dispatch_contract": {
        "reader": dc["reader"],
        "decider": dc["decider"],
        "dispatcher": dc["dispatcher"],
        "awaiter": dc["awaiter"],
        "logger": dc["logger"],
        "budget_estimate_usd": dc.get("budget_estimate_usd", 0),
        "timeout_seconds": dc.get("timeout_seconds"),
    },
}
print(json.dumps(out))
PY
}

# -----------------------------------------------------------------------------
# _l3_compute_dispatch_contract_hash <dispatch_contract_json>
#
# Compute SHA-256 hex of canonical-JSON of the dispatch_contract block
# (RFC 8785 JCS via lib/jcs.sh — same primitive as audit-envelope chain hashes).
# -----------------------------------------------------------------------------
_l3_compute_dispatch_contract_hash() {
    local dc_json="$1"
    jcs_canonicalize "$dc_json" | _audit_sha256
}

# -----------------------------------------------------------------------------
# _l3_compute_cycle_id <schedule_id> <dispatch_contract_hash> [ts_bucket]
#
# Content-addressed cycle_id: sha256(schedule_id\n + ts_bucket\n + dc_hash).
# ts_bucket defaults to UTC minute (YYYY-MM-DDTHH:MMZ); callers can override
# (e.g., in tests) for deterministic content-addressing.
# -----------------------------------------------------------------------------
_l3_compute_cycle_id() {
    local schedule_id="$1"
    local dc_hash="$2"
    local ts_bucket="${3:-}"
    if [[ -z "$ts_bucket" ]]; then
        local now
        now="$(_l3_now_iso8601)"
        ts_bucket="${now:0:16}Z"  # 'YYYY-MM-DDTHH:MM' + 'Z'
    fi
    printf '%s\n%s\n%s' "$schedule_id" "$ts_bucket" "$dc_hash" | _audit_sha256
}

# -----------------------------------------------------------------------------
# _l3_validate_payload <event_type> <payload_json>
#
# Validate payload against per-event-type schema in cycle-events/.
# -----------------------------------------------------------------------------
_l3_validate_payload() {
    local event_type="$1"
    local payload_json="$2"
    local basename
    basename="${event_type#cycle.}"
    basename="${basename//_/-}"
    local schema_path="${_L3_SCHEMA_DIR}/cycle-${basename}.payload.schema.json"
    if [[ ! -f "$schema_path" ]]; then
        _l3_log "ERROR: per-event schema missing for $event_type at $schema_path"
        return 1
    fi
    if command -v ajv >/dev/null 2>&1; then
        local tmp_data rc
        tmp_data="$(mktemp)"
        chmod 600 "$tmp_data"
        printf '%s' "$payload_json" > "$tmp_data"
        if ajv validate -s "$schema_path" -d "$tmp_data" --spec=draft2020 >/dev/null 2>&1; then
            rc=0
        else
            rc=1
        fi
        rm -f "$tmp_data"
        return "$rc"
    fi
    python3 - "$schema_path" "$payload_json" <<'PY' 2>/dev/null
import json, sys
try:
    import jsonschema
except ImportError:
    sys.exit(0)
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
# _l3_audit_emit_event <event_type> <payload_json>
#
# Validate payload + delegate to audit_emit (which validates envelope, signs,
# and writes atomically under flock).
# -----------------------------------------------------------------------------
_l3_audit_emit_event() {
    local event_type="$1"
    local payload_json="$2"
    local log_path
    log_path="$(_l3_get_log_path)"
    if ! _l3_validate_payload "$event_type" "$payload_json"; then
        _l3_log "ERROR: payload schema validation failed for $event_type"
        return 1
    fi
    audit_emit "L3" "$event_type" "$payload_json" "$log_path"
}

# -----------------------------------------------------------------------------
# _l3_redact_diagnostic <text>
#
# Truncate to 4096 chars (schema cap) and apply common secret-pattern scrubs.
# Sprint 3 remediation (MED-R4 / MED-A1 audit findings): expanded pattern set
# covering AWS/GCP/Slack/PEM/generic-key-value/Stripe in addition to the
# Anthropic/GitHub/JWT prefixes from Sprint 3A. Phase scripts are STILL
# responsible for primary scrubbing — this is defense-in-depth before payload
# lands in the audit envelope, which is durably appended. Full canonical
# redaction is centralized in secret-redaction.sh; this stub mirrors the
# minimum subset and prevents stack-trace leaks past the schema cap.
# -----------------------------------------------------------------------------
_l3_redact_diagnostic() {
    local text="$1"
    # Truncate (4096 chars).
    local truncated
    truncated="$(printf '%s' "$text" | head -c 4096)"
    # Defense-in-depth redactions. Apply with sed -E (POSIX-portable ERE).
    truncated="$(printf '%s' "$truncated" | sed -E \
        -e 's/(sk-[A-Za-z0-9_-]{15,})/[REDACTED]/g' \
        -e 's/(sk_[a-z]+_[A-Za-z0-9]{16,})/[REDACTED]/g' \
        -e 's/(ghp_[A-Za-z0-9]{15,})/[REDACTED]/g' \
        -e 's/(github_pat_[A-Za-z0-9_]{20,})/[REDACTED]/g' \
        -e 's/(gho_[A-Za-z0-9]{15,})/[REDACTED]/g' \
        -e 's/(npm_[A-Za-z0-9]{20,})/[REDACTED]/g' \
        -e 's/(eyJ[A-Za-z0-9._-]{20,})/[REDACTED]/g' \
        -e 's/(AKIA[A-Z0-9]{12,})/[REDACTED]/g' \
        -e 's/(ASIA[A-Z0-9]{12,})/[REDACTED]/g' \
        -e 's/(AIza[A-Za-z0-9_-]{30,})/[REDACTED]/g' \
        -e 's/(xox[baprs]-[A-Za-z0-9_-]{10,})/[REDACTED]/g' \
        -e 's/-----BEGIN [A-Z ]+PRIVATE KEY-----/[REDACTED-PEM-BEGIN]/g' \
        -e 's/-----END [A-Z ]+PRIVATE KEY-----/[REDACTED-PEM-END]/g' \
        -e 's/([Aa][Pp][Ii][_-]?[Kk][Ee][Yy][[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/g' \
        -e 's/([Ss][Ee][Cc][Rr][Ee][Tt][[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/g' \
        -e 's/([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/g' \
        -e 's/([Tt][Oo][Kk][Ee][Nn][[:space:]]*[:=][[:space:]]*)[A-Za-z0-9._-]{10,}/\1[REDACTED]/g')"
    printf '%s' "$truncated"
}

# -----------------------------------------------------------------------------
# _l3_phase_script_path <dispatch_contract_json> <phase_name>
#
# Resolve + VALIDATE the phase script path from the dispatch_contract block.
# Sprint 3 remediation (CRITICAL audit finding): validates against the
# allowlist via _l3_validate_phase_path; rejects absolute paths outside the
# allowlist + relative paths with `..` traversal. Returns 0 + canonical path
# on stdout; 1 on policy violation.
# -----------------------------------------------------------------------------
_l3_phase_script_path() {
    local dc_json="$1"
    local phase="$2"
    local raw
    raw="$(printf '%s' "$dc_json" | jq -r --arg p "$phase" '.[$p] // ""')"
    if [[ -z "$raw" ]]; then
        return 1
    fi
    _l3_validate_phase_path "$raw" "$phase"
}

# -----------------------------------------------------------------------------
# _l3_run_phase <phase_name> <phase_index> <script_path> <cycle_id>
#                <schedule_id> <timeout_s> <prior_phases_json>
#
# Run a single phase. Captures stdout (sha256 → output_hash), stderr (last
# 4KB → diagnostic on error), exit code, and wall-clock duration. Returns:
#   0 if phase exited 0
#   non-zero if phase exited non-zero (or timed out — Sprint 3B adds timeout
#   teeth; in Sprint 3A timeout is recorded but not enforced).
#
# Stdout: a JSON object describing the phase outcome:
#   {"phase":"...", "phase_index":N, "started_at":"...", "completed_at":"...",
#    "duration_seconds":N, "outcome":"success|error|timeout",
#    "exit_code":N|null, "diagnostic":"..."|null, "output_hash":"..."|null,
#    "timeout_seconds":N|null}
# -----------------------------------------------------------------------------
_l3_run_phase() {
    local phase="$1"
    local phase_index="$2"
    local script_path="$3"
    local cycle_id="$4"
    local schedule_id="$5"
    local timeout_s="$6"
    local prior_phases_json="$7"

    local started_at completed_at duration_s outcome exit_code diagnostic
    local stdout_file stderr_file output_hash

    started_at="$(_l3_now_iso8601)"
    local started_epoch
    # Sprint 3 remediation (HIGH-R3): derive epoch from started_at so
    # LOA_L3_TEST_NOW frozen-clock fixtures produce consistent
    # duration_seconds. Wall-clock fallback if parse fails (defense in depth).
    started_epoch="$(_l3_iso_to_epoch "$started_at" 2>/dev/null || date -u +%s)"

    if [[ ! -f "$script_path" ]]; then
        completed_at="$(_l3_now_iso8601)"
        duration_s=0
        outcome="error"
        exit_code=null
        diagnostic="$(_l3_redact_diagnostic "phase script not found: $script_path")"
        jq -n \
            --arg phase "$phase" \
            --argjson phase_index "$phase_index" \
            --arg started "$started_at" \
            --arg completed "$completed_at" \
            --argjson duration "$duration_s" \
            --arg outcome "$outcome" \
            --argjson exit_code "$exit_code" \
            --arg diagnostic "$diagnostic" \
            --argjson timeout "${timeout_s:-null}" \
            '{phase:$phase, phase_index:$phase_index, started_at:$started,
              completed_at:$completed, duration_seconds:$duration,
              outcome:$outcome, exit_code:$exit_code, diagnostic:$diagnostic,
              output_hash:null, timeout_seconds:$timeout}'
        return 127
    fi

    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    chmod 600 "$stdout_file" "$stderr_file"
    # NOTE: do NOT use `trap ... RETURN` to clean up these tmpfiles. RETURN
    # traps in bash are not function-local (without `shopt -s extdebug`); they
    # fire on every nested function return, which causes the temp files to be
    # removed before this function finishes reading from them. Explicit
    # cleanup at the end of this function (single exit path) is robust.

    local rc=0
    local prior_arg="${prior_phases_json:-[]}"

    # Run the phase script wrapped in `timeout` (Sprint 3B). Phase scripts
    # receive: $1 cycle_id, $2 schedule_id, $3 phase_index, $4 prior_phases_json
    #
    # On timeout, GNU coreutils `timeout` exits 124 (after TERM) or 137
    # (after KILL via --kill-after grace). We treat both as outcome=timeout.
    #
    # Sprint 3 remediation (HIGH-A1 audit finding): phase scripts run under
    # `env -i` with an explicit allowlist. Default allowlist is minimal;
    # caller can extend per-schedule via dispatch_contract.env_passthrough.
    local _l3_timeout_bin=""
    if command -v timeout >/dev/null 2>&1; then
        _l3_timeout_bin="timeout"
    elif command -v gtimeout >/dev/null 2>&1; then
        # macOS via coreutils brew package.
        _l3_timeout_bin="gtimeout"
    fi
    local _l3_kill_grace="${LOA_L3_KILL_GRACE_SECONDS:-${_L3_DEFAULT_KILL_GRACE_SECONDS}}"

    # Build env -i allowlist arguments. Pass through allowed vars from caller
    # env, then explicitly inject phase-context vars.
    local extra_passthrough="${LOA_L3_PHASE_ENV_PASSTHROUGH:-}"
    local env_args=()
    local var
    while IFS= read -r var; do
        if [[ -n "${!var:-}" ]]; then
            env_args+=("${var}=${!var}")
        fi
    done < <(_l3_get_env_passthrough "$extra_passthrough")
    # Phase context (always injected).
    env_args+=("LOA_L3_CYCLE_ID=${cycle_id}")
    env_args+=("LOA_L3_SCHEDULE_ID=${schedule_id}")
    env_args+=("LOA_L3_PHASE_INDEX=${phase_index}")

    local invoker
    if [[ -x "$script_path" ]]; then
        invoker=("$script_path")
    else
        invoker=(bash "$script_path")
    fi

    if [[ -n "$_l3_timeout_bin" && -n "${timeout_s}" && "$timeout_s" =~ $_L3_INT_RE ]]; then
        if env -i "${env_args[@]}" \
                "$_l3_timeout_bin" --kill-after="${_l3_kill_grace}s" "${timeout_s}s" \
                "${invoker[@]}" "$cycle_id" "$schedule_id" "$phase_index" "$prior_arg" \
                >"$stdout_file" 2>"$stderr_file"; then
            rc=0
        else
            rc=$?
        fi
    else
        # Fallback (no `timeout` available): unwrapped invocation. Records
        # timeout_seconds in payload but does not enforce.
        if env -i "${env_args[@]}" \
                "${invoker[@]}" "$cycle_id" "$schedule_id" "$phase_index" "$prior_arg" \
                >"$stdout_file" 2>"$stderr_file"; then
            rc=0
        else
            rc=$?
        fi
    fi

    completed_at="$(_l3_now_iso8601)"
    local completed_epoch
    completed_epoch="$(_l3_iso_to_epoch "$completed_at" 2>/dev/null || date -u +%s)"
    duration_s=$(( completed_epoch - started_epoch ))
    if (( duration_s < 0 )); then
        duration_s=0
    fi

    if [[ "$rc" -eq 0 ]]; then
        outcome="success"
        exit_code=0
        diagnostic=""
    elif [[ "$rc" -eq 124 || "$rc" -eq 137 ]]; then
        outcome="timeout"
        exit_code="$rc"
        local stderr_tail
        stderr_tail="$(tail -c 4096 "$stderr_file" 2>/dev/null || true)"
        diagnostic="$(_l3_redact_diagnostic "$stderr_tail")"
        if [[ -z "$diagnostic" ]]; then
            diagnostic="phase exceeded timeout=${timeout_s}s (rc=${rc})"
        fi
    else
        outcome="error"
        exit_code="$rc"
        local stderr_tail
        stderr_tail="$(tail -c 4096 "$stderr_file" 2>/dev/null || true)"
        diagnostic="$(_l3_redact_diagnostic "$stderr_tail")"
        if [[ -z "$diagnostic" ]]; then
            diagnostic="phase exited $rc with no stderr output"
        fi
    fi

    output_hash="$(_audit_sha256 < "$stdout_file" 2>/dev/null || true)"

    if [[ -n "$diagnostic" ]]; then
        jq -n \
            --arg phase "$phase" \
            --argjson phase_index "$phase_index" \
            --arg started "$started_at" \
            --arg completed "$completed_at" \
            --argjson duration "$duration_s" \
            --arg outcome "$outcome" \
            --argjson exit_code "$exit_code" \
            --arg diagnostic "$diagnostic" \
            --arg output_hash "$output_hash" \
            --argjson timeout "${timeout_s:-null}" \
            '{phase:$phase, phase_index:$phase_index, started_at:$started,
              completed_at:$completed, duration_seconds:$duration,
              outcome:$outcome, exit_code:$exit_code, diagnostic:$diagnostic,
              output_hash:$output_hash, timeout_seconds:$timeout}'
    else
        jq -n \
            --arg phase "$phase" \
            --argjson phase_index "$phase_index" \
            --arg started "$started_at" \
            --arg completed "$completed_at" \
            --argjson duration "$duration_s" \
            --arg outcome "$outcome" \
            --argjson exit_code "$exit_code" \
            --arg output_hash "$output_hash" \
            --argjson timeout "${timeout_s:-null}" \
            '{phase:$phase, phase_index:$phase_index, started_at:$started,
              completed_at:$completed, duration_seconds:$duration,
              outcome:$outcome, exit_code:$exit_code, diagnostic:null,
              output_hash:$output_hash, timeout_seconds:$timeout}'
    fi

    rm -f "$stdout_file" "$stderr_file"
    return "$rc"
}

# -----------------------------------------------------------------------------
# cycle_idempotency_check <cycle_id> [--log-path <path>]
#
# Returns 0 if cycle.complete for cycle_id is present in the log (skip).
# Returns 1 if not found (cycle should run).
# -----------------------------------------------------------------------------
cycle_idempotency_check() {
    local cycle_id=""
    local log_path=""
    while (( "$#" )); do
        case "$1" in
            --log-path)
                log_path="$2"; shift 2 ;;
            --*)
                _l3_log "ERROR: unknown flag $1"; return 2 ;;
            *)
                if [[ -z "$cycle_id" ]]; then
                    cycle_id="$1"
                else
                    _l3_log "ERROR: too many positional args"; return 2
                fi
                shift ;;
        esac
    done
    if [[ -z "$cycle_id" ]]; then
        _l3_log "ERROR: cycle_idempotency_check requires <cycle_id>"
        return 2
    fi
    if ! _l3_validate_cycle_id "$cycle_id"; then
        return 2
    fi
    if [[ -z "$log_path" ]]; then
        log_path="$(_l3_get_log_path)"
    fi
    [[ -f "$log_path" ]] || return 1
    # Sprint 3 remediation (CRITICAL audit finding): tighten the
    # idempotency-honoring filter. Without these gates a single forged line
    # `{"event_type":"cycle.complete","payload":{"cycle_id":"<predicted>"}}`
    # appended to .run/cycles.jsonl can silently kill arbitrary future
    # cycles. Defenses:
    #   (1) require envelope shape — schema_version + primitive_id "L3" +
    #       prev_hash + event_type + payload — anything else is rejected.
    #   (2) require cycle.complete payload's cycle_id matches AND has the
    #       canonical phases_completed=[reader,decider,...,logger] shape.
    #   (3) when the trust-store status is VERIFIED and the lib is in the
    #       Sprint 1B post-cutoff regime (LOA_AUDIT_VERIFY_SIGS unset/non-0),
    #       require signature + signing_key_id present. Tests using
    #       LOA_AUDIT_VERIFY_SIGS=0 retain the lax behavior.
    local require_signed=1
    if [[ "${LOA_AUDIT_VERIFY_SIGS:-1}" == "0" ]]; then
        require_signed=0
    fi
    # Determine trust-store posture; permit lax in BOOTSTRAP-PENDING.
    local trust_status=""
    if declare -f _audit_trust_store_status >/dev/null 2>&1; then
        trust_status="$(_audit_trust_store_status 2>/dev/null || echo "")"
    fi
    if [[ "$trust_status" != "VERIFIED" ]]; then
        require_signed=0
    fi

    if jq -e --arg cid "$cycle_id" --argjson require_signed "$require_signed" '
        select(type == "object") |
        select(.schema_version != null and (.schema_version | type == "string")) |
        select(.primitive_id == "L3") |
        select(.prev_hash != null and (.prev_hash | test("^[0-9a-f]{64}$|^GENESIS$"))) |
        select(.event_type == "cycle.complete") |
        select(.payload != null and (.payload | type == "object")) |
        select(.payload.cycle_id == $cid) |
        select(.payload.outcome == "success") |
        select(.payload.phases_completed != null and
               (.payload.phases_completed | type == "array") and
               (.payload.phases_completed | length == 5)) |
        if $require_signed == 1 then
            select(.signature != null and (.signature | type == "string") and
                   .signing_key_id != null and (.signing_key_id | type == "string"))
        else . end
    ' "$log_path" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# cycle_record_phase --schedule-id <id> <cycle_id> <phase> <phase_record_json>
#
# Direct emission of a cycle.phase event. phase_record_json must include
# phase_index, started_at, completed_at, duration_seconds, outcome.
# Used both by cycle_invoke (internal) and by phase scripts that want to add
# custom diagnostics.
#
# Sprint 3 remediation (MED-A2): schedule_id MUST be passed explicitly via
# --schedule-id; the prior env-var pattern (LOA_L3_CURRENT_SCHEDULE_ID) leaked
# state across invocations.
# -----------------------------------------------------------------------------
cycle_record_phase() {
    _l3_propagate_test_now
    local schedule_id="" cycle_id="" phase="" rec=""
    while (( "$#" )); do
        case "$1" in
            --schedule-id) schedule_id="$2"; shift 2 ;;
            --*) _l3_log "ERROR: unknown flag $1"; return 2 ;;
            *)
                if [[ -z "$cycle_id" ]]; then cycle_id="$1"
                elif [[ -z "$phase" ]]; then phase="$1"
                elif [[ -z "$rec" ]]; then rec="$1"
                else _l3_log "ERROR: too many positional args to cycle_record_phase"; return 2; fi
                shift ;;
        esac
    done
    if [[ -z "$cycle_id" || -z "$phase" || -z "$rec" ]]; then
        _l3_log "ERROR: cycle_record_phase requires --schedule-id <id> <cycle_id> <phase> <record_json>"
        return 2
    fi
    if [[ -z "$schedule_id" ]]; then
        _l3_log "ERROR: cycle_record_phase requires --schedule-id (env-var fallback removed in Sprint 3 hardening)"
        return 2
    fi
    if ! _l3_validate_cycle_id "$cycle_id"; then return 2; fi
    if ! _l3_validate_schedule_id "$schedule_id"; then return 2; fi
    local payload
    payload="$(printf '%s' "$rec" | jq -c \
        --arg cid "$cycle_id" \
        --arg sid "$schedule_id" \
        --arg phase "$phase" \
        '. + {cycle_id:$cid, schedule_id:$sid, phase:$phase}')"
    _l3_audit_emit_event "cycle.phase" "$payload"
}

# -----------------------------------------------------------------------------
# cycle_complete --schedule-id <id> <cycle_id> <final_record_json>
#
# Direct emission of a cycle.complete event. Sprint 3 remediation (MED-A2):
# schedule_id MUST be passed explicitly via --schedule-id.
# -----------------------------------------------------------------------------
cycle_complete() {
    _l3_propagate_test_now
    local schedule_id="" cycle_id="" rec=""
    while (( "$#" )); do
        case "$1" in
            --schedule-id) schedule_id="$2"; shift 2 ;;
            --*) _l3_log "ERROR: unknown flag $1"; return 2 ;;
            *)
                if [[ -z "$cycle_id" ]]; then cycle_id="$1"
                elif [[ -z "$rec" ]]; then rec="$1"
                else _l3_log "ERROR: too many positional args to cycle_complete"; return 2; fi
                shift ;;
        esac
    done
    if [[ -z "$cycle_id" || -z "$rec" ]]; then
        _l3_log "ERROR: cycle_complete requires --schedule-id <id> <cycle_id> <record_json>"
        return 2
    fi
    if [[ -z "$schedule_id" ]]; then
        _l3_log "ERROR: cycle_complete requires --schedule-id (env-var fallback removed in Sprint 3 hardening)"
        return 2
    fi
    if ! _l3_validate_cycle_id "$cycle_id"; then return 2; fi
    if ! _l3_validate_schedule_id "$schedule_id"; then return 2; fi
    local payload
    payload="$(printf '%s' "$rec" | jq -c \
        --arg cid "$cycle_id" \
        --arg sid "$schedule_id" \
        '. + {cycle_id:$cid, schedule_id:$sid, outcome:"success"}')"
    _l3_audit_emit_event "cycle.complete" "$payload"
}

# -----------------------------------------------------------------------------
# cycle_register <schedule_yaml_path>
#
# Sprint 3 remediation (HIGH-R1 review finding): the SDD §5.5.2 spec listed
# cycle_register as a public function but the original lib shipped only the
# *fire* half. cycle_register validates the ScheduleConfig YAML, computes its
# dispatch_contract_hash for traceability, and prints the canonical command
# operators should hand to /schedule for cron registration.
#
# Stdout (one line each): the schedule_id, the cron expression, the canonical
# invoke command, and the dispatch_contract_hash.
#
# Returns 0 on valid config; non-zero on parse/validation failure.
# -----------------------------------------------------------------------------
cycle_register() {
    local yaml_path="${1:-}"
    if [[ -z "$yaml_path" ]]; then
        _l3_log "ERROR: cycle_register requires <schedule_yaml_path>"
        return 2
    fi
    local schedule_json
    if ! schedule_json="$(_l3_parse_schedule_yaml "$yaml_path")"; then
        return 2
    fi
    local schedule_id schedule_cron dc_json dc_hash
    schedule_id="$(printf '%s' "$schedule_json" | jq -r '.schedule_id')"
    schedule_cron="$(printf '%s' "$schedule_json" | jq -r '.schedule')"
    dc_json="$(printf '%s' "$schedule_json" | jq -c '.dispatch_contract')"
    dc_hash="$(_l3_compute_dispatch_contract_hash "$dc_json")"
    if ! _l3_validate_schedule_id "$schedule_id"; then return 2; fi
    # Validate every phase path BEFORE printing — surfaces allowlist
    # violations at registration time, not at first cron firing.
    local phase
    for phase in "${_L3_PHASES[@]}"; do
        if ! _l3_phase_script_path "$dc_json" "$phase" >/dev/null; then
            return 2
        fi
    done
    local self_path
    self_path="${_L3_DIR}/scheduled-cycle-lib.sh"
    jq -nc \
        --arg sid "$schedule_id" \
        --arg cron "$schedule_cron" \
        --arg dch "$dc_hash" \
        --arg cmd "$self_path invoke $yaml_path" \
        '{schedule_id:$sid, schedule:$cron, dispatch_contract_hash:$dch,
          register_command:$cmd,
          note:"Pass register_command + schedule cron to /schedule (Claude Code skill) to wire the cron firing."}'
}

# -----------------------------------------------------------------------------
# cycle_replay <log_path> [--cycle-id <id>]
#
# Reassemble SDD §5.5.3 CycleRecord(s) from cycle.{start,phase,complete,error}
# events. With --cycle-id, returns a single object; without, returns an array
# of all cycles in the log (one record per cycle_id).
# -----------------------------------------------------------------------------
cycle_replay() {
    local log_path=""
    local cycle_id_filter=""
    while (( "$#" )); do
        case "$1" in
            --cycle-id) cycle_id_filter="$2"; shift 2 ;;
            --*) _l3_log "ERROR: unknown flag $1"; return 2 ;;
            *)  if [[ -z "$log_path" ]]; then log_path="$1"; else _l3_log "ERROR: too many positional args"; return 2; fi; shift ;;
        esac
    done
    if [[ -z "$log_path" ]]; then
        log_path="$(_l3_get_log_path)"
    fi
    if [[ ! -f "$log_path" ]]; then
        _l3_log "ERROR: log file not found: $log_path"
        return 2
    fi
    python3 - "$log_path" "$cycle_id_filter" <<'PY'
import json, sys
log_path = sys.argv[1]
filter_cid = sys.argv[2] if len(sys.argv) > 2 else ""
records = {}
with open(log_path) as f:
    for ln, line in enumerate(f, 1):
        line = line.strip()
        if not line or line.startswith("["):
            continue
        try:
            env = json.loads(line)
        except json.JSONDecodeError:
            continue
        if env.get("primitive_id") != "L3":
            continue
        et = env.get("event_type", "")
        p = env.get("payload", {})
        cid = p.get("cycle_id")
        if not cid:
            continue
        rec = records.setdefault(cid, {
            "cycle_id": cid,
            "schedule_id": p.get("schedule_id"),
            "started_at": None,
            "completed_at": None,
            "phases": [],
            "budget_pre_check": None,
            "outcome": None,
        })
        if et == "cycle.start":
            rec["started_at"] = p.get("started_at")
            if "budget_pre_check" in p and p["budget_pre_check"] is not None:
                rec["budget_pre_check"] = p["budget_pre_check"]
        elif et == "cycle.phase":
            rec["phases"].append({
                "phase": p.get("phase"),
                "phase_index": p.get("phase_index", 999),
                "started_at": p.get("started_at"),
                "completed_at": p.get("completed_at"),
                "outcome": p.get("outcome"),
                "diagnostic": p.get("diagnostic"),
            })
        elif et == "cycle.complete":
            rec["completed_at"] = p.get("completed_at")
            rec["outcome"] = "success"
        elif et == "cycle.error":
            rec["completed_at"] = p.get("errored_at")
            rec["outcome"] = p.get("outcome", "failure")

# Sprint 3 remediation (MED-R3): sort phases by phase_index so a manually-
# edited or recovered log with out-of-order events still produces the
# expected ordering. Drop phase_index from output (not in §5.5.3 schema).
for cid, rec in records.items():
    if rec["outcome"] is None:
        rec["outcome"] = "in_progress"
    rec["phases"].sort(key=lambda ph: ph.get("phase_index", 999))
    for ph in rec["phases"]:
        ph.pop("phase_index", None)

if filter_cid:
    rec = records.get(filter_cid)
    if rec is None:
        sys.exit(2)
    print(json.dumps(rec))
else:
    print(json.dumps(list(records.values())))
PY
}

# -----------------------------------------------------------------------------
# cycle_invoke <schedule_yaml_path> [--cycle-id <id>] [--dry-run]
#
# Sprint 3A: parse schedule, compute cycle_id, emit cycle.start, run 5 phases,
# emit cycle.phase per phase, emit cycle.complete on success or cycle.error
# on phase failure.
# Sprint 3B will wrap this in flock + idempotency + per-phase timeout.
# Sprint 3C will insert L2 budget pre-check between cycle.start and reader.
# -----------------------------------------------------------------------------
cycle_invoke() {
    _l3_propagate_test_now
    local schedule_yaml=""
    local cycle_id_override=""
    local dry_run=0
    while (( "$#" )); do
        case "$1" in
            --cycle-id) cycle_id_override="$2"; shift 2 ;;
            --dry-run)  dry_run=1; shift ;;
            --*) _l3_log "ERROR: unknown flag $1"; return 2 ;;
            *)  if [[ -z "$schedule_yaml" ]]; then schedule_yaml="$1"; else _l3_log "ERROR: too many positional args"; return 2; fi; shift ;;
        esac
    done
    if [[ -z "$schedule_yaml" ]]; then
        _l3_log "ERROR: cycle_invoke requires <schedule_yaml_path>"
        return 2
    fi

    local schedule_json
    if ! schedule_json="$(_l3_parse_schedule_yaml "$schedule_yaml")"; then
        _l3_log "ERROR: schedule yaml validation failed for $schedule_yaml"
        return 2
    fi

    local schedule_id schedule_cron dc_json budget_estimate timeout_s
    schedule_id="$(printf '%s' "$schedule_json" | jq -r '.schedule_id')"
    schedule_cron="$(printf '%s' "$schedule_json" | jq -r '.schedule')"
    dc_json="$(printf '%s' "$schedule_json" | jq -c '.dispatch_contract')"
    budget_estimate="$(printf '%s' "$dc_json" | jq -r '.budget_estimate_usd // 0')"
    timeout_s="$(printf '%s' "$dc_json" | jq -r '.timeout_seconds // empty')"

    if ! _l3_validate_schedule_id "$schedule_id"; then return 2; fi
    if [[ -z "$timeout_s" || "$timeout_s" == "null" ]]; then
        timeout_s="$_L3_DEFAULT_PHASE_TIMEOUT"
    fi
    if ! [[ "$timeout_s" =~ $_L3_INT_RE ]]; then
        _l3_log "ERROR: invalid timeout_seconds: $timeout_s"
        return 2
    fi
    # Sprint 3 remediation (MED-A3): cap total cycle wall-clock at
    # max_cycle_seconds. Without a cap a malicious schedule yaml with
    # timeout_seconds: 86400 + 5 sleeping phases parks the lock for 5 days.
    local _max_cycle _projected
    _max_cycle="$(_l3_get_max_cycle_seconds)"
    _projected=$(( timeout_s * 5 ))
    if (( _projected > _max_cycle )); then
        _l3_log "ERROR: projected total cycle time ${_projected}s (timeout_seconds=${timeout_s} × 5 phases) exceeds max_cycle_seconds=${_max_cycle}"
        _l3_log "  Lower dispatch_contract.timeout_seconds or raise .scheduled_cycle_template.max_cycle_seconds"
        return 2
    fi

    local dc_hash
    dc_hash="$(_l3_compute_dispatch_contract_hash "$dc_json")"

    local cycle_id
    if [[ -n "$cycle_id_override" ]]; then
        cycle_id="$cycle_id_override"
    else
        cycle_id="$(_l3_compute_cycle_id "$schedule_id" "$dc_hash")"
    fi
    if ! _l3_validate_cycle_id "$cycle_id"; then return 2; fi

    # Sprint 3B: acquire flock on .run/cycles/<schedule_id>.lock for the entire
    # cycle. Without the lock, two cron firings can overlap and race the audit
    # log + state. flock fd 9 is held via `9>"$lock_file"` for the whole group.
    if ! _audit_require_flock; then return 1; fi
    local lock_dir lock_file lock_timeout
    lock_dir="$(_l3_get_lock_dir)"
    mkdir -p "$lock_dir"
    lock_file="${lock_dir}/${schedule_id}.lock"
    # Sprint 3 remediation (CRITICAL audit finding): symlink-safe lock-file
    # creation. The legacy `: > "$lock_file"` redirect FOLLOWS symlinks; an
    # attacker who stages a symlink at <lock_dir>/<schedule_id>.lock
    # weaponizes the touch into a write-anywhere truncate primitive.
    if ! _l3_safe_touch_lock "$lock_file"; then
        return 1
    fi
    lock_timeout="$(_l3_get_lock_timeout)"

    # Brace group (NOT subshell) — `return N` inside terminates cycle_invoke.
    {
        if ! flock -w "$lock_timeout" 9; then
            local lf_payload
            lf_payload="$(jq -nc \
                --arg sid "$schedule_id" \
                --arg cid "$cycle_id" \
                --arg lock "$lock_file" \
                --argjson tmo "$lock_timeout" \
                --arg attempted "$(_l3_now_iso8601)" \
                --arg diag "Failed to acquire lock within ${lock_timeout}s" \
                '{schedule_id:$sid, cycle_id:$cid, lock_path:$lock,
                  acquire_timeout_seconds:$tmo, attempted_at:$attempted,
                  holder_pid:null, diagnostic:$diag}')"
            _l3_audit_emit_event "cycle.lock_failed" "$lf_payload" || true
            return 4
        fi

        # FR-L3-2 idempotency: if cycle.complete already in log for cycle_id,
        # treat invocation as no-op.
        local log_path
        log_path="$(_l3_get_log_path)"
        if cycle_idempotency_check "$cycle_id" --log-path "$log_path"; then
            _l3_log "cycle $cycle_id already complete; skipping (idempotent)"
            return 0
        fi

        # Sprint 3 remediation (MED-A2): no LOA_L3_CURRENT_SCHEDULE_ID export.
        # _l3_cycle_invoke_inner takes schedule_id as an explicit arg and
        # emits payloads inline; cycle_record_phase / cycle_complete (public)
        # require --schedule-id explicitly.
        _l3_cycle_invoke_inner \
            "$schedule_id" "$schedule_cron" "$dc_json" "$dc_hash" \
            "$cycle_id" "$timeout_s" "$budget_estimate" "$dry_run"
        local _inner_rc=$?
        return $_inner_rc
    } 9>"$lock_file"
}

# -----------------------------------------------------------------------------
# _l3_cycle_invoke_inner — runs the cycle.start → 5 phases → cycle.complete |
# cycle.error sequence under an already-acquired flock. Caller (cycle_invoke)
# is responsible for argument parsing, schedule_id derivation, lock
# acquisition, and idempotency check.
# -----------------------------------------------------------------------------
_l3_cycle_invoke_inner() {
    local schedule_id="$1"
    local schedule_cron="$2"
    local dc_json="$3"
    local dc_hash="$4"
    local cycle_id="$5"
    local timeout_s="$6"
    local budget_estimate="$7"
    local dry_run="$8"

    local started_at
    started_at="$(_l3_now_iso8601)"

    # FR-L3-6: L2 budget pre-check. compose-when-available — when L2 disabled
    # or budget_estimate is zero, _l3_run_budget_pre_check emits "null" and
    # returns 0. halt-100 / halt-uncertainty → exit 1; we record the verdict
    # in cycle.start AND emit cycle.error{error_phase=pre_check, kind=budget_halt}.
    local budget_pre_check_json="null"
    local budget_pre_check_rc=0
    budget_pre_check_json="$(_l3_run_budget_pre_check "$budget_estimate" "$cycle_id")" \
        || budget_pre_check_rc=$?

    # Build cycle.start payload (with budget_pre_check populated).
    local start_payload
    start_payload="$(jq -n \
        --arg cid "$cycle_id" \
        --arg sid "$schedule_id" \
        --arg dc_hash "$dc_hash" \
        --argjson timeout "$timeout_s" \
        --argjson budget_est "$budget_estimate" \
        --argjson pre_check "$budget_pre_check_json" \
        --arg started "$started_at" \
        --arg cron "$schedule_cron" \
        --argjson dry "$dry_run" \
        '{cycle_id:$cid, schedule_id:$sid, dispatch_contract_hash:$dc_hash,
          timeout_seconds:$timeout, budget_estimate_usd:$budget_est,
          budget_pre_check:$pre_check, started_at:$started, schedule_cron:$cron,
          dry_run:($dry==1)}')"

    if ! _l3_audit_emit_event "cycle.start" "$start_payload"; then
        _l3_log "ERROR: cycle.start emit failed"
        return 1
    fi

    # If budget halted, emit cycle.error{pre_check, budget_halt} and return.
    if (( budget_pre_check_rc == 1 )); then
        local errored_at
        errored_at="$(_l3_now_iso8601)"
        local verdict_str
        verdict_str="$(printf '%s' "$budget_pre_check_json" | jq -r '.verdict // "halt-100"')"
        local pc_for_err
        pc_for_err="$(jq -nc --arg v "$verdict_str" '{verdict:$v}')"
        local err_payload
        err_payload="$(jq -n \
            --arg cid "$cycle_id" \
            --arg sid "$schedule_id" \
            --arg started "$started_at" \
            --arg errored "$errored_at" \
            --argjson dur 0 \
            --arg phase "pre_check" \
            --arg kind "budget_halt" \
            --arg diag "L2 budget gate halted cycle (verdict=${verdict_str})" \
            --argjson completed "[]" \
            --arg outcome "failure" \
            --argjson pc "$pc_for_err" \
            '{cycle_id:$cid, schedule_id:$sid, started_at:$started,
              errored_at:$errored, duration_seconds:$dur,
              error_phase:$phase, error_kind:$kind, exit_code:null,
              diagnostic:$diag, phases_completed:$completed,
              outcome:$outcome, budget_pre_check:$pc}')"
        _l3_audit_emit_event "cycle.error" "$err_payload" || true
        return 1
    fi

    if (( dry_run == 1 )); then
        _l3_log "dry-run: skipping phase execution for $cycle_id"
        return 0
    fi

    local phases_completed=()
    local prior_phases_json="[]"
    local phase phase_index=0
    local phase_record rc
    local error_phase="" error_kind="" error_diag="" error_exit=null

    for phase in "${_L3_PHASES[@]}"; do
        local script_path
        if ! script_path="$(_l3_phase_script_path "$dc_json" "$phase")"; then
            error_phase="$phase"
            error_kind="phase_missing"
            error_diag="dispatch_contract.${phase} not provided"
            break
        fi
        if [[ ! -f "$script_path" ]]; then
            error_phase="$phase"
            error_kind="phase_missing"
            error_diag="phase script not found: $script_path"
            break
        fi
        # Capture phase record + exit. _l3_run_phase prints JSON record on
        # stdout regardless of success/failure; rc is phase exit code.
        rc=0
        phase_record="$(_l3_run_phase "$phase" "$phase_index" "$script_path" \
            "$cycle_id" "$schedule_id" "$timeout_s" "$prior_phases_json")" || rc=$?

        # Emit cycle.phase event with cycle_id + schedule_id injected.
        local phase_payload
        phase_payload="$(printf '%s' "$phase_record" | jq -c \
            --arg cid "$cycle_id" \
            --arg sid "$schedule_id" \
            '. + {cycle_id:$cid, schedule_id:$sid}')"
        if ! _l3_audit_emit_event "cycle.phase" "$phase_payload"; then
            _l3_log "ERROR: cycle.phase emit failed for $phase"
            error_phase="$phase"
            error_kind="internal"
            error_diag="cycle.phase audit emit failed"
            break
        fi

        if (( rc != 0 )); then
            error_phase="$phase"
            local _rec_outcome
            _rec_outcome="$(printf '%s' "$phase_record" | jq -r '.outcome // "error"')"
            if [[ "$_rec_outcome" == "timeout" ]]; then
                error_kind="phase_timeout"
            else
                error_kind="phase_error"
            fi
            error_diag="$(printf '%s' "$phase_record" | jq -r '.diagnostic // ""')"
            error_exit="$rc"
            break
        fi
        phases_completed+=("$phase")

        # Append the just-completed phase record to prior_phases for the next phase.
        prior_phases_json="$(printf '%s' "$prior_phases_json" | jq -c \
            --argjson rec "$phase_record" '. + [$rec]')"
        phase_index=$((phase_index + 1))
    done

    local errored_at
    errored_at="$(_l3_now_iso8601)"
    local started_epoch ended_epoch duration_s
    # Sprint 3 remediation (HIGH-R3): canonical _l3_iso_to_epoch helper so
    # frozen-clock fixtures + production paths use the same logic.
    started_epoch="$(_l3_iso_to_epoch "$started_at" 2>/dev/null || echo 0)"
    ended_epoch="$(_l3_iso_to_epoch "$errored_at" 2>/dev/null || echo 0)"
    duration_s=$(( ended_epoch - started_epoch ))
    if (( duration_s < 0 )); then duration_s=0; fi

    if [[ -n "$error_phase" ]]; then
        # Emit cycle.error.
        local outcome_field
        if (( ${#phases_completed[@]} == 0 )); then
            outcome_field="failure"
        else
            outcome_field="partial"
        fi
        # Build phases_completed JSON via jq --args — robust against the
        # printf-empty-array pitfall (yields `[""]` when array is empty).
        local phases_completed_json
        phases_completed_json="$(jq -nc '$ARGS.positional' --args "${phases_completed[@]+${phases_completed[@]}}")"
        local error_diag_redacted
        error_diag_redacted="$(_l3_redact_diagnostic "$error_diag")"
        if [[ -z "$error_diag_redacted" ]]; then
            error_diag_redacted="phase error (no diagnostic)"
        fi
        local error_payload
        error_payload="$(jq -n \
            --arg cid "$cycle_id" \
            --arg sid "$schedule_id" \
            --arg started "$started_at" \
            --arg errored "$errored_at" \
            --argjson dur "$duration_s" \
            --arg phase "$error_phase" \
            --arg kind "$error_kind" \
            --argjson exit_code "$error_exit" \
            --arg diag "$error_diag_redacted" \
            --argjson completed "$phases_completed_json" \
            --arg outcome "$outcome_field" \
            '{cycle_id:$cid, schedule_id:$sid, started_at:$started,
              errored_at:$errored, duration_seconds:$dur,
              error_phase:$phase, error_kind:$kind, exit_code:$exit_code,
              diagnostic:$diag, phases_completed:$completed,
              outcome:$outcome, budget_pre_check:null}')"
        _l3_audit_emit_event "cycle.error" "$error_payload" || true
        return 1
    fi

    # All 5 phases succeeded — emit cycle.complete. Sprint 3 remediation
    # (MED-R5): emit the actual phases_completed array (always all 5 here by
    # construction) instead of a hardcoded literal, so a future change that
    # introduces an early-success path doesn't silently mis-state reality.
    local phases_completed_json
    phases_completed_json="$(jq -nc '$ARGS.positional' --args \
        "${phases_completed[@]+${phases_completed[@]}}")"
    local complete_payload
    complete_payload="$(jq -n \
        --arg cid "$cycle_id" \
        --arg sid "$schedule_id" \
        --arg started "$started_at" \
        --arg completed "$errored_at" \
        --argjson dur "$duration_s" \
        --argjson phases "$phases_completed_json" \
        '{cycle_id:$cid, schedule_id:$sid, started_at:$started,
          completed_at:$completed, duration_seconds:$dur,
          phases_completed:$phases,
          outcome:"success", budget_actual_usd:null}')"
    if ! _l3_audit_emit_event "cycle.complete" "$complete_payload"; then
        _l3_log "ERROR: cycle.complete emit failed"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# CLI dispatcher (so the lib can be invoked directly:
#   .claude/scripts/lib/scheduled-cycle-lib.sh <subcommand> [args]
# Common harness pattern across cycle-098 libs.
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        invoke)              cycle_invoke "$@" ;;
        register)            cycle_register "$@" ;;
        idempotency-check)   cycle_idempotency_check "$@" ;;
        replay)              cycle_replay "$@" ;;
        record-phase)        cycle_record_phase "$@" ;;
        complete)            cycle_complete "$@" ;;
        ""|--help|-h)
            cat <<USAGE
scheduled-cycle-lib.sh — L3 scheduled-cycle-template (cycle-098 Sprint 3)

Subcommands:
  invoke <schedule_yaml> [--cycle-id <id>] [--dry-run]
  register <schedule_yaml>                          # validate + emit /schedule wiring
  idempotency-check <cycle_id> [--log-path <path>]
  replay [<log_path>] [--cycle-id <id>]
  record-phase --schedule-id <id> <cycle_id> <phase> <record_json>   (advanced)
  complete --schedule-id <id> <cycle_id> <record_json>               (advanced)
USAGE
            ;;
        *)
            _l3_log "ERROR: unknown subcommand: $cmd"
            cat <<USAGE
scheduled-cycle-lib.sh — see --help for subcommand list (invoke|register|idempotency-check|replay|record-phase|complete).
USAGE
            exit 2 ;;
    esac
fi
