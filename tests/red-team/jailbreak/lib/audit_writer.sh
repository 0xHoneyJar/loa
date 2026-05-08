#!/usr/bin/env bash
# tests/red-team/jailbreak/lib/audit_writer.sh — cycle-100 T1.3
#
# Append-only structured run log writer (FR-7).
#
#   audit_writer_init [<run_id>]  → set log path; create dir 0700 + file 0600
#   audit_emit_run_entry <vector_id> <category> <defense_layer> <status> <reason>
#   audit_writer_summary          → "Active: N | Superseded: M | Suppressed: K (...)"
#
# Defenses:
#   - jq -c with --arg / --argjson for every value (NEVER interpolated; cycle-099 PR #215)
#   - flock on <log>.lock for the entire compute → append sequence
#   - mode 0600 file in mode 0700 dir
#   - reason is truncated to 500 chars and run through _audit_redact_secrets
#     before write (NFR-Sec3); _audit_redact_secrets reuses cycle-098
#     _SECRET_PATTERNS if available, falls back to a minimal in-lib pattern set
#
# Path resolution: derive once at source time.
_AUDIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_AUDIT_REPO_ROOT="$(cd "${_AUDIT_LIB_DIR}/../../../.." && pwd)"

# Test-mode gate (cycle-098 L4/L6/L7 dual-condition pattern). LOA_*
# overrides are honored ONLY when both LOA_JAILBREAK_TEST_MODE=1 and a
# bats / pytest marker are present. Production paths emit a stderr WARNING
# and use the default. This prevents drive-by env-var injection from
# subverting the audit log destination.
_audit_test_mode_active() {
    [[ "${LOA_JAILBREAK_TEST_MODE:-0}" != "1" ]] && return 1
    [[ -n "${BATS_TEST_FILENAME:-}" || -n "${BATS_VERSION:-}" || -n "${PYTEST_CURRENT_TEST:-}" ]]
}
_audit_resolve_override() {
    local var_name="$1" default_value="$2" override="${3:-}"
    if [[ -z "$override" ]]; then
        printf '%s' "$default_value"
        return
    fi
    if _audit_test_mode_active; then
        printf '%s' "$override"
        return
    fi
    echo "audit_writer: WARNING: ${var_name} ignored outside test mode (set LOA_JAILBREAK_TEST_MODE=1 + bats/pytest marker)" >&2
    printf '%s' "$default_value"
}

_AUDIT_LOG_DIR="$(_audit_resolve_override "LOA_JAILBREAK_AUDIT_DIR" "${_AUDIT_REPO_ROOT}/.run" "${LOA_JAILBREAK_AUDIT_DIR:-}")"
# Preserve already-initialized state across re-source. The runner sources
# this lib once in setup_file and again lazily inside per-vector subshells;
# resetting these to "" each time would force each test to compute its own
# run_id, breaking FR-7 "all entries from the same run share the same id".
_AUDIT_RUN_ID="${_AUDIT_RUN_ID:-}"
_AUDIT_LOG_PATH="${_AUDIT_LOG_PATH:-}"

_audit_iso_today() { date -u +"%Y-%m-%d"; }
_audit_iso_now()   { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

_audit_compute_run_id() {
    # First 16 hex chars of SHA-256 over canonical run-context.
    local ctx
    if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
        ctx="gh-${GITHUB_RUN_ID}"
    else
        ctx="manual-$(_audit_iso_now)"
    fi
    printf '%s' "$ctx" | sha256sum | awk '{print $1}' | cut -c1-16
}

_audit_host_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "darwin" ;;
        *)       echo "linux" ;; # default to linux for the schema enum
    esac
}

# Strip cycle-098-style API key patterns. We keep a minimal pattern set in
# this lib so the writer is standalone; if cycle-098's secret-patterns.sh
# arrives later, we'll source it. Cycle-100 deliberately does NOT introduce
# a new secret-pattern registry.
_audit_redact_secrets() {
    local text="$1"
    # Common provider tokens (Anthropic, OpenAI, Google, GitHub, AWS).
    local pats=(
        's/sk-ant-[A-Za-z0-9_-]{20,}/[REDACTED_API_KEY]/g'
        's/sk-[A-Za-z0-9_-]{20,}/[REDACTED_API_KEY]/g'
        's/AIza[0-9A-Za-z_-]{35}/[REDACTED_API_KEY]/g'
        's/ghp_[A-Za-z0-9]{36}/[REDACTED_API_KEY]/g'
        's/AKIA[0-9A-Z]{16}/[REDACTED_API_KEY]/g'
        's/eyJ[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}/[REDACTED_JWT]/g'
        's/-----BEGIN [A-Z ]*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g'
    )
    local out="$text"
    local p
    for p in "${pats[@]}"; do
        out="$(printf '%s' "$out" | sed -E "$p")"
    done
    printf '%s' "$out"
}

# Truncate to N codepoints (NOT bytes). Locale-independent: delegates to
# python so the budget is codepoint-counted regardless of caller LC_ALL.
# Matches JSON Schema's `maxLength` semantics (codepoint count). For multi-
# byte UTF-8 input the resulting byte count may exceed N codepoints — that
# is acceptable because the run-entry schema's reason field is also
# codepoint-budgeted.
#
# Bash `${#s}` is byte-count under LC_ALL=C and codepoint-count under
# UTF-8 locales — pinning to python eliminates that ambiguity. F4 closure.
_audit_truncate_codepoints() {
    local s="$1" max="${2:-500}"
    LOA_TR_S="$s" LOA_TR_MAX="$max" python3 -c '
import os, sys
s = os.environ["LOA_TR_S"]
m = int(os.environ["LOA_TR_MAX"])
sys.stdout.write(s[:m])
'
}

audit_writer_init() {
    local run_id="${1:-}"
    if [[ -z "$run_id" ]]; then
        run_id="$(_audit_compute_run_id)"
    fi
    # Validate run_id matches schema regex; if caller passes something weird,
    # fail fast.
    if ! [[ "$run_id" =~ ^[a-f0-9]{16}$ ]]; then
        echo "audit_writer: invalid run_id (expected 16 hex chars): $run_id" >&2
        return 2
    fi
    _AUDIT_RUN_ID="$run_id"
    local date_str
    date_str="$(_audit_iso_today)"
    _AUDIT_LOG_PATH="${_AUDIT_LOG_DIR}/jailbreak-run-${date_str}.jsonl"

    # Create dir mode 0700 (idempotent).
    if [[ ! -d "$_AUDIT_LOG_DIR" ]]; then
        mkdir -p "$_AUDIT_LOG_DIR"
    fi
    chmod 0700 "$_AUDIT_LOG_DIR" 2>/dev/null || true

    # Create file mode 0600 (idempotent).
    if [[ ! -f "$_AUDIT_LOG_PATH" ]]; then
        : > "$_AUDIT_LOG_PATH"
    fi
    chmod 0600 "$_AUDIT_LOG_PATH" 2>/dev/null || true
}

# Internal: hold flock across canonicalize+append.
_audit_locked_append() {
    local line="$1"
    local lock="${_AUDIT_LOG_PATH}.lock"
    if command -v flock >/dev/null 2>&1; then
        (
            flock -x 200
            printf '%s\n' "$line" >> "$_AUDIT_LOG_PATH"
        ) 200>"$lock"
    else
        # macOS without util-linux flock: fall back to a best-effort mkdir-lock.
        # The fallback matches cycle-098 _audit_with_lock pattern.
        local lockdir="${_AUDIT_LOG_PATH}.mkdir-lock"
        local tries=0
        while ! mkdir "$lockdir" 2>/dev/null; do
            tries=$((tries + 1))
            if [[ $tries -gt 200 ]]; then
                echo "audit_writer: lock timeout for $_AUDIT_LOG_PATH" >&2
                return 1
            fi
            sleep 0.05
        done
        printf '%s\n' "$line" >> "$_AUDIT_LOG_PATH"
        rmdir "$lockdir"
    fi
}

audit_emit_run_entry() {
    local vector_id="${1:-}" category="${2:-}" defense_layer="${3:-}" status="${4:-}" reason="${5:-}"
    if [[ -z "$_AUDIT_LOG_PATH" ]]; then
        audit_writer_init || return $?
    fi
    if [[ -z "$vector_id" || -z "$category" || -z "$defense_layer" || -z "$status" ]]; then
        echo "audit_writer: missing required fields (vector_id/category/defense_layer/status)" >&2
        return 2
    fi

    local redacted_reason truncated_reason
    redacted_reason="$(_audit_redact_secrets "$reason")"
    truncated_reason="$(_audit_truncate_codepoints "$redacted_reason" 500)"

    local ts host_os ci_run_id
    ts="$(_audit_iso_now)"
    host_os="$(_audit_host_os)"
    ci_run_id="${GITHUB_RUN_ID:-}"

    local line
    if [[ -z "$ci_run_id" ]]; then
        line="$(jq -nc \
            --arg run_id "$_AUDIT_RUN_ID" \
            --arg vector_id "$vector_id" \
            --arg category "$category" \
            --arg defense_layer "$defense_layer" \
            --arg status "$status" \
            --arg reason "$truncated_reason" \
            --arg ts "$ts" \
            --arg host_os "$host_os" \
            '{run_id: $run_id, vector_id: $vector_id, category: $category, defense_layer: $defense_layer, status: $status, reason: $reason, ts_utc: $ts, host_os: $host_os, ci_run_id: null}')"
    else
        line="$(jq -nc \
            --arg run_id "$_AUDIT_RUN_ID" \
            --arg vector_id "$vector_id" \
            --arg category "$category" \
            --arg defense_layer "$defense_layer" \
            --arg status "$status" \
            --arg reason "$truncated_reason" \
            --arg ts "$ts" \
            --arg host_os "$host_os" \
            --arg ci_run_id "$ci_run_id" \
            '{run_id: $run_id, vector_id: $vector_id, category: $category, defense_layer: $defense_layer, status: $status, reason: $reason, ts_utc: $ts, host_os: $host_os, ci_run_id: $ci_run_id}')"
    fi

    _audit_locked_append "$line"
}

# audit_writer_summary — emit a two-line summary covering BOTH:
#   1. Run-log outcomes (pass/fail/suppressed) — what happened in this run
#   2. Corpus statuses (active/superseded/suppressed) — corpus shape at time
#      of run, sourced from corpus_loader.sh::corpus_count_by_status
# Per FR-8 AC + SDD §4.6.1.
audit_writer_summary() {
    local pass=0 fail=0 sup_run=0 reasons=""
    if [[ -n "$_AUDIT_LOG_PATH" && -f "$_AUDIT_LOG_PATH" && -s "$_AUDIT_LOG_PATH" ]]; then
        pass="$(jq -s 'map(select(.status=="pass"))      | length' "$_AUDIT_LOG_PATH")"
        fail="$(jq -s 'map(select(.status=="fail"))      | length' "$_AUDIT_LOG_PATH")"
        sup_run="$(jq -s 'map(select(.status=="suppressed")) | length' "$_AUDIT_LOG_PATH")"
        reasons="$(jq -s -r 'map(select(.status=="suppressed") | .reason) | unique | map(select(length>0)) | join("; ")' "$_AUDIT_LOG_PATH")"
    fi
    if [[ -n "$reasons" ]]; then
        printf 'Run: pass=%d | fail=%d | suppressed=%d (reasons: %s)\n' \
            "$pass" "$fail" "$sup_run" "$reasons"
    else
        printf 'Run: pass=%d | fail=%d | suppressed=%d\n' "$pass" "$fail" "$sup_run"
    fi

    # Corpus statuses (source of truth: corpus_loader). The audit-writer is
    # FR-8's primary surface, so we delegate the canonical count to the
    # loader rather than re-deriving from the run log.
    local loader_path
    loader_path="${_AUDIT_LIB_DIR}/corpus_loader.sh"
    if [[ -f "$loader_path" ]]; then
        # shellcheck disable=SC1090
        ( source "$loader_path"; corpus_count_by_status ) | awk -F'\t' '
            {
                for (i=1; i<=NF; i++) {
                    n = split($i, kv, "=")
                    if (n == 2) counts[kv[1]] = kv[2]
                }
                printf "Corpus: active=%s | superseded=%s | suppressed=%s\n",
                    (counts["active"]+0), (counts["superseded"]+0), (counts["suppressed"]+0)
            }
        '
    fi
}

# CLI shim for ad-hoc use.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        init)    shift; audit_writer_init "$@" ;;
        emit)    shift; audit_writer_init && audit_emit_run_entry "$@" ;;
        summary) audit_writer_summary ;;
        *) echo "Usage: $0 {init [<run_id>]|emit <vid> <cat> <layer> <status> <reason>|summary}" >&2; exit 2 ;;
    esac
fi
