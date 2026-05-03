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
_L3_PHASES=(reader decider dispatcher awaiter logger)

# shellcheck source=../audit-envelope.sh
source "${_L3_AUDIT_ENVELOPE}"

_l3_log() { echo "[scheduled-cycle] $*" >&2; }

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

    # Resolve L2 lib path. LOA_L3_L2_LIB_OVERRIDE lets tests inject a missing
    # path to exercise the graceful-skip branch.
    local l2_lib="${LOA_L3_L2_LIB_OVERRIDE:-${_L3_REPO_ROOT}/.claude/scripts/lib/cost-budget-enforcer-lib.sh}"
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
# Mirrors the conservative subset used by L2 (anthropic_api_key etc.). Full
# multi-pattern redaction lives in secret-redaction.sh; this is a stub that
# at minimum prevents long stack traces from blowing past the schema cap.
# -----------------------------------------------------------------------------
_l3_redact_diagnostic() {
    local text="$1"
    # Truncate (4096 chars). Use head -c bytes first; if multibyte tail is cut
    # mid-codepoint, Python json.dumps still escapes safely.
    local truncated
    truncated="$(printf '%s' "$text" | head -c 4096)"
    # Basic redactions: api keys, tokens. Caller-supplied phase scripts are
    # responsible for their own scrubbing; this is defense-in-depth.
    truncated="$(printf '%s' "$truncated" | sed -E \
        -e 's/(sk-[A-Za-z0-9_-]{20,})/[REDACTED]/g' \
        -e 's/(ghp_[A-Za-z0-9]{20,})/[REDACTED]/g' \
        -e 's/(eyJ[A-Za-z0-9._-]{40,})/[REDACTED]/g')"
    printf '%s' "$truncated"
}

# -----------------------------------------------------------------------------
# _l3_phase_script_path <dispatch_contract_json> <phase_name>
#
# Resolve the phase script path from the dispatch_contract block; if it is a
# relative path, resolve relative to repo root.
# -----------------------------------------------------------------------------
_l3_phase_script_path() {
    local dc_json="$1"
    local phase="$2"
    local raw
    raw="$(printf '%s' "$dc_json" | jq -r --arg p "$phase" '.[$p] // ""')"
    if [[ -z "$raw" ]]; then
        return 1
    fi
    if [[ "$raw" = /* ]]; then
        echo "$raw"
    else
        echo "${_L3_REPO_ROOT}/${raw}"
    fi
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
    started_epoch="$(date -u +%s)"

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
    local _l3_timeout_bin=""
    if command -v timeout >/dev/null 2>&1; then
        _l3_timeout_bin="timeout"
    elif command -v gtimeout >/dev/null 2>&1; then
        # macOS via coreutils brew package.
        _l3_timeout_bin="gtimeout"
    fi
    local _l3_kill_grace="${LOA_L3_KILL_GRACE_SECONDS:-${_L3_DEFAULT_KILL_GRACE_SECONDS}}"

    if [[ -n "$_l3_timeout_bin" && -n "${timeout_s}" && "$timeout_s" =~ $_L3_INT_RE ]]; then
        if [[ -x "$script_path" ]]; then
            if "$_l3_timeout_bin" --kill-after="${_l3_kill_grace}s" "${timeout_s}s" \
                    "$script_path" "$cycle_id" "$schedule_id" "$phase_index" "$prior_arg" \
                    >"$stdout_file" 2>"$stderr_file"; then
                rc=0
            else
                rc=$?
            fi
        else
            if "$_l3_timeout_bin" --kill-after="${_l3_kill_grace}s" "${timeout_s}s" \
                    bash "$script_path" "$cycle_id" "$schedule_id" "$phase_index" "$prior_arg" \
                    >"$stdout_file" 2>"$stderr_file"; then
                rc=0
            else
                rc=$?
            fi
        fi
    else
        # Fallback (no `timeout` available): unwrapped invocation. Records
        # timeout_seconds in payload but does not enforce.
        if [[ -x "$script_path" ]]; then
            if "$script_path" "$cycle_id" "$schedule_id" "$phase_index" "$prior_arg" \
                    >"$stdout_file" 2>"$stderr_file"; then
                rc=0
            else
                rc=$?
            fi
        else
            if bash "$script_path" "$cycle_id" "$schedule_id" "$phase_index" "$prior_arg" \
                    >"$stdout_file" 2>"$stderr_file"; then
                rc=0
            else
                rc=$?
            fi
        fi
    fi

    completed_at="$(_l3_now_iso8601)"
    local completed_epoch
    completed_epoch="$(date -u +%s)"
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
    # Look for cycle.complete with matching cycle_id.
    if jq -e --arg cid "$cycle_id" '
        select(.event_type == "cycle.complete") |
        select(.payload.cycle_id == $cid)
    ' "$log_path" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# cycle_record_phase <cycle_id> <phase> <phase_record_json>
#
# Direct emission of a cycle.phase event. phase_record_json must include
# phase_index, started_at, completed_at, duration_seconds, outcome.
# Used both by cycle_invoke (internal) and by phase scripts that want to add
# custom diagnostics.
# -----------------------------------------------------------------------------
cycle_record_phase() {
    _l3_propagate_test_now
    local cycle_id="$1"
    local phase="$2"
    local rec="$3"
    if ! _l3_validate_cycle_id "$cycle_id"; then return 2; fi
    # Caller is expected to supply schedule_id; allow injection here via env.
    local schedule_id="${LOA_L3_CURRENT_SCHEDULE_ID:-}"
    if [[ -z "$schedule_id" ]]; then
        _l3_log "ERROR: cycle_record_phase requires LOA_L3_CURRENT_SCHEDULE_ID env (set by cycle_invoke)"
        return 2
    fi
    local payload
    payload="$(printf '%s' "$rec" | jq -c \
        --arg cid "$cycle_id" \
        --arg sid "$schedule_id" \
        --arg phase "$phase" \
        '. + {cycle_id:$cid, schedule_id:$sid, phase:$phase}')"
    _l3_audit_emit_event "cycle.phase" "$payload"
}

# -----------------------------------------------------------------------------
# cycle_complete <cycle_id> <final_record_json>
#
# Direct emission of a cycle.complete event.
# -----------------------------------------------------------------------------
cycle_complete() {
    _l3_propagate_test_now
    local cycle_id="$1"
    local rec="$2"
    if ! _l3_validate_cycle_id "$cycle_id"; then return 2; fi
    local schedule_id="${LOA_L3_CURRENT_SCHEDULE_ID:-}"
    if [[ -z "$schedule_id" ]]; then
        _l3_log "ERROR: cycle_complete requires LOA_L3_CURRENT_SCHEDULE_ID env"
        return 2
    fi
    local payload
    payload="$(printf '%s' "$rec" | jq -c \
        --arg cid "$cycle_id" \
        --arg sid "$schedule_id" \
        '. + {cycle_id:$cid, schedule_id:$sid, outcome:"success"}')"
    _l3_audit_emit_event "cycle.complete" "$payload"
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

# Fill outcome=null cycles as 'in_progress'.
for cid, rec in records.items():
    if rec["outcome"] is None:
        rec["outcome"] = "in_progress"

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
    : > "$lock_file" 2>/dev/null || touch "$lock_file"
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

        export LOA_L3_CURRENT_SCHEDULE_ID="$schedule_id"
        _l3_cycle_invoke_inner \
            "$schedule_id" "$schedule_cron" "$dc_json" "$dc_hash" \
            "$cycle_id" "$timeout_s" "$budget_estimate" "$dry_run"
        local _inner_rc=$?
        unset LOA_L3_CURRENT_SCHEDULE_ID
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
    started_epoch="$(date -u -d "$started_at" +%s 2>/dev/null || python3 -c "
import sys
from datetime import datetime
s=sys.argv[1].rstrip('Z')
print(int(datetime.fromisoformat(s).timestamp()))" "$started_at" 2>/dev/null || echo 0)"
    ended_epoch="$(date -u -d "$errored_at" +%s 2>/dev/null || python3 -c "
import sys
from datetime import datetime
s=sys.argv[1].rstrip('Z')
print(int(datetime.fromisoformat(s).timestamp()))" "$errored_at" 2>/dev/null || echo 0)"
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

    # All 5 phases succeeded — emit cycle.complete.
    local complete_payload
    complete_payload="$(jq -n \
        --arg cid "$cycle_id" \
        --arg sid "$schedule_id" \
        --arg started "$started_at" \
        --arg completed "$errored_at" \
        --argjson dur "$duration_s" \
        '{cycle_id:$cid, schedule_id:$sid, started_at:$started,
          completed_at:$completed, duration_seconds:$dur,
          phases_completed:["reader","decider","dispatcher","awaiter","logger"],
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
        idempotency-check)   cycle_idempotency_check "$@" ;;
        replay)              cycle_replay "$@" ;;
        record-phase)        cycle_record_phase "$@" ;;
        complete)            cycle_complete "$@" ;;
        ""|--help|-h)
            cat <<USAGE
scheduled-cycle-lib.sh — L3 scheduled-cycle-template (cycle-098 Sprint 3)

Subcommands:
  invoke <schedule_yaml> [--cycle-id <id>] [--dry-run]
  idempotency-check <cycle_id> [--log-path <path>]
  replay [<log_path>] [--cycle-id <id>]
  record-phase <cycle_id> <phase> <record_json>   (advanced)
  complete <cycle_id> <record_json>               (advanced)
USAGE
            ;;
        *) _l3_log "ERROR: unknown subcommand: $cmd"; exit 2 ;;
    esac
fi
