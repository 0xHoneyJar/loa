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
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
RED_TEAM_DIR="$PROJECT_ROOT/.run/red-team"
AUDIT_LOG="$PROJECT_ROOT/.run/red-team-audit.log"

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

        run_id=$(jq -r '.run_id // "unknown"' "$result_file" 2>/dev/null || echo "unknown")
        timestamp=$(jq -r '.timestamp // ""' "$result_file" 2>/dev/null || echo "")
        classification=$(jq -r '.classification // "INTERNAL"' "$result_file" 2>/dev/null || echo "INTERNAL")

        if [[ -z "$timestamp" ]]; then
            [[ "$verbose" == "true" ]] && log "Skipping $result_file (no timestamp)"
            continue
        fi

        # Parse timestamp to epoch
        created=$(date -d "$timestamp" +%s 2>/dev/null || echo "0")
        if [[ "$created" == "0" ]]; then
            [[ "$verbose" == "true" ]] && log "Skipping $result_file (unparseable timestamp: $timestamp)"
            continue
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
            [[ "$verbose" == "true" ]] && log "RETAIN: $run_id ($classification, ${age_days}d/${max_age_days}d)"
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

    mkdir -p "$(dirname "$AUDIT_LOG")"
    purge_expired "$dry_run" "$verbose"
}

main "$@"
