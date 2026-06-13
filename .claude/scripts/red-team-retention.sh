#!/usr/bin/env bash
# =============================================================================
# red-team-retention.sh — Report lifecycle management
# =============================================================================
# Purge expired red team reports based on classification and retention policy.
#
# Usage:
#   red-team-retention.sh [--dry-run] [--verbose]
#
# Retention periods (from .loa.config.yaml):
#   RESTRICTED: 30 days (red_team.safety.retention_days_restricted)
#   INTERNAL:   90 days (red_team.safety.retention_days_internal)
#
# Exit codes:
#   0 - Success (or nothing to purge)
#   1 - Configuration error
#   3 - Completed with conservative dispositions (sprint-bug-210 / #1025):
#       one or more result files were unparseable or lacked a usable
#       timestamp; they were aged by file mtime under the most-restrictive
#       (RESTRICTED) policy — purged when expired, retained with a loud
#       WARN when young. Quarantine was rejected (it just relocates the
#       indefinite retention this fixes).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
RED_TEAM_DIR="$PROJECT_ROOT/.run/red-team"
AUDIT_LOG="$PROJECT_ROOT/.run/red-team-audit.log"

# sprint-bug-210 (#1025): jq_strict (fail-loud jq) from compat-lib.
# shellcheck source=compat-lib.sh
source "$SCRIPT_DIR/compat-lib.sh" 2>/dev/null || true

# Conservative dispositions applied this run (parse failures + missing/
# unparseable timestamps). Non-zero → main exits 3.
CONSERVATIVE_COUNT=0

# Portable file mtime (GNU stat -c, BSD stat -f).
_file_mtime_epoch() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

# DISS-001 (review iter-3): a MISSING dependency must abort loudly, never be
# treated like a corrupt data file. compat-lib is soft-sourced (|| true); if
# it failed, jq_strict/_date_to_epoch are undefined and every result file
# would hit the conservative path → mass-purge of valid reports. Hard-require
# the deletion-path dependencies before any purge decision (the sha256_portable
# exit-127 principle: missing tool = loud abort, not destructive degrade).
_require_deps() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    declare -F jq_strict >/dev/null 2>&1 || missing+=("jq_strict (compat-lib.sh)")
    declare -F _date_to_epoch >/dev/null 2>&1 || missing+=("_date_to_epoch (compat-lib.sh)")
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "FATAL: required dependencies unavailable: ${missing[*]}"
        log "Refusing to make deletion decisions without them — a missing helper must not"
        log "mass-purge valid reports as conservative (#1025 / DISS-001)."
        exit 2
    fi
}

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[retention] $*" >&2
}

audit() {
    local msg="$1"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "${timestamp} ${msg}" >> "$AUDIT_LOG"
    log "$msg"
}

# =============================================================================
# Configuration
# =============================================================================

get_retention_days() {
    local classification="$1"
    local default_restricted=30
    local default_internal=90

    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        case "$classification" in
            RESTRICTED)
                yq ".red_team.safety.retention_days_restricted // $default_restricted" "$CONFIG_FILE" 2>/dev/null || echo "$default_restricted"
                ;;
            *)
                yq ".red_team.safety.retention_days_internal // $default_internal" "$CONFIG_FILE" 2>/dev/null || echo "$default_internal"
                ;;
        esac
    else
        case "$classification" in
            RESTRICTED) echo "$default_restricted" ;;
            *)          echo "$default_internal" ;;
        esac
    fi
}

# =============================================================================
# Purge logic
# =============================================================================

purge_expired() {
    local dry_run="$1"
    local verbose="$2"
    local purged=0

    if [[ ! -d "$RED_TEAM_DIR" ]]; then
        log "No red team reports directory found"
        return 0
    fi

    local now
    now=$(date +%s)

    for result_file in "$RED_TEAM_DIR"/rt-*-result.json; do
        [[ -f "$result_file" ]] || continue

        local timestamp classification max_age_days max_age_seconds created run_id
        local parse_ok=true conservative=false

        # sprint-bug-210 (#1025) / KF-004 guard: a corrupt result JSON must
        # never be silently SKIPPED — pre-fix, the jq swallow yielded an
        # empty timestamp and expired RESTRICTED reports were retained
        # indefinitely. Parse failure → most-restrictive disposition.
        if ! run_id=$(JQ_STRICT_CTX="red-team-retention:run_id" jq_strict -r '.run_id // "unknown"' "$result_file"); then
            parse_ok=false
            run_id="unknown"
            timestamp=""
            classification="RESTRICTED"
        else
            if ! timestamp=$(JQ_STRICT_CTX="red-team-retention:timestamp" jq_strict -r '.timestamp // ""' "$result_file"); then
                parse_ok=false
                timestamp=""
            fi
            if ! classification=$(JQ_STRICT_CTX="red-team-retention:classification" jq_strict -r '.classification // "INTERNAL"' "$result_file"); then
                parse_ok=false
                classification="RESTRICTED"
            fi
        fi

        if [[ "$parse_ok" == "false" ]]; then
            conservative=true
            classification="RESTRICTED"
            audit "PARSE-FAILURE: $result_file unparseable — conservative disposition: RESTRICTED policy, mtime age (#1025)"
        fi

        # Conservative timestamp handling: missing or unparseable timestamp
        # (even in VALID JSON) falls back to file mtime under the
        # most-restrictive classification, instead of skipping forever.
        if [[ -z "$timestamp" ]]; then
            if [[ "$conservative" != "true" ]]; then
                conservative=true
                classification="RESTRICTED"
                audit "CONSERVATIVE: $result_file has no usable timestamp — RESTRICTED policy, mtime age (#1025)"
            fi
            created=$(_file_mtime_epoch "$result_file")
        else
            # DISS-002 (review iter-1): portable parse via compat-lib
            # _date_to_epoch (GNU/BSD/perl tiers). Raw `date -d` is GNU-only —
            # on macOS it failed for EVERY valid ISO timestamp, which post-fix
            # would have mass-purged valid reports as conservative RESTRICTED.
            # Only a genuine unparseable timestamp now triggers conservative.
            created=$(_date_to_epoch "$timestamp" 2>/dev/null || echo "")
            if [[ -z "$created" || "$created" == "0" ]]; then
                conservative=true
                classification="RESTRICTED"
                audit "CONSERVATIVE: $result_file unparseable timestamp '$timestamp' — RESTRICTED policy, mtime age (#1025)"
                created=$(_file_mtime_epoch "$result_file")
            fi
        fi

        if [[ "$conservative" == "true" ]]; then
            CONSERVATIVE_COUNT=$((CONSERVATIVE_COUNT + 1))
        fi

        max_age_days=$(get_retention_days "$classification")
        max_age_seconds=$((max_age_days * 86400))

        local age=$((now - created))
        local age_days=$((age / 86400))

        if (( age > max_age_seconds )); then
            local base="${result_file%-result.json}"

            if [[ "$dry_run" == "true" ]]; then
                log "WOULD PURGE: $run_id ($classification, ${age_days}d old, limit ${max_age_days}d)"
                log "  - $result_file"
                [[ -f "${base}-report.md" ]] && log "  - ${base}-report.md"
                [[ -f "${base}-summary.md" ]] && log "  - ${base}-summary.md"
            else
                rm -f "$result_file" "${base}-report.md" "${base}-summary.md" "${base}-report.md.BLOCKED"
                audit "PURGED: $run_id ($classification, ${age_days}d old)"
                purged=$((purged + 1))
            fi
        else
            if [[ "$conservative" == "true" ]]; then
                log "WARN: RETAIN (conservative): $result_file unparseable/un-timestamped, mtime age ${age_days}d under RESTRICTED ${max_age_days}d — will purge when expired (#1025)"
            else
                [[ "$verbose" == "true" ]] && log "RETAIN: $run_id ($classification, ${age_days}d/${max_age_days}d)"
            fi
        fi
    done

    if [[ "$dry_run" == "true" ]]; then
        log "Dry run complete (no files deleted)"
    else
        log "Purged $purged expired report(s)"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    local dry_run=false
    local verbose=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)  dry_run=true; shift ;;
            --verbose)  verbose=true; shift ;;
            -h|--help)
                echo "Usage: red-team-retention.sh [--dry-run] [--verbose]"
                echo ""
                echo "Options:"
                echo "  --dry-run   Show what would be deleted without deleting"
                echo "  --verbose   Show retention status for all reports"
                exit 0
                ;;
            *)          log "Unknown option: $1"; exit 1 ;;
        esac
    done

    _require_deps
    mkdir -p "$(dirname "$AUDIT_LOG")"
    purge_expired "$dry_run" "$verbose"
    if [[ "$CONSERVATIVE_COUNT" -gt 0 ]]; then
        log "Retention DEGRADED: $CONSERVATIVE_COUNT conservative disposition(s) applied — exit 3 (#1025)"
        exit 3
    fi
}

main "$@"
