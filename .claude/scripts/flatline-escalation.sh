#!/usr/bin/env bash
# =============================================================================
# flatline-escalation.sh - Escalation report generator for Flatline Protocol
# =============================================================================
# Version: 1.0.0
# Part of: Autonomous Flatline Integration v1.22.0
#
# Generates escalation reports when autonomous Flatline execution halts due to
# BLOCKER items, disputed threshold exceeded, or fatal errors.
#
# Usage:
#   flatline-escalation.sh create --run-id <id> --phase <type> --reason <reason>
#   flatline-escalation.sh get --run-id <id>
#   flatline-escalation.sh list
#
# Exit codes:
#   0 - Success
#   1 - Report creation failed
#   2 - Report not found
#   3 - Invalid arguments
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

ESCALATION_DIR=$(get_flatline_dir)
RUNS_DIR="$PROJECT_ROOT/.flatline/runs"
SNAPSHOT_DIR="$PROJECT_ROOT/.flatline/snapshots"
TRAJECTORY_DIR=$(get_trajectory_dir)

# Component scripts
MANIFEST_SCRIPT="$SCRIPT_DIR/flatline-manifest.sh"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline-escalation] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

warn() {
    echo "WARNING: $*" >&2
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-escalation-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_escalation" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Report Generation
# =============================================================================

create_escalation_report() {
    local run_id="$1"
    local phase="$2"
    local reason="$3"
    local document="${4:-}"
    local blockers_json="${5:-[]}"
    local disputed_json="${6:-[]}"

    # Ensure directory exists
    mkdir -p "$ESCALATION_DIR"

    local date_str
    date_str=$(date +%Y%m%d_%H%M%S)
    local report_file="$ESCALATION_DIR/escalation-${date_str}.md"
    local report_json="$ESCALATION_DIR/escalation-${date_str}.json"

    # Get manifest if exists
    local manifest="{}"
    if [[ -x "$MANIFEST_SCRIPT" ]]; then
        manifest=$("$MANIFEST_SCRIPT" get "$run_id" 2>/dev/null) || manifest="{}"
    fi

    # Extract data from manifest
    local integrations
    integrations=$(echo "$manifest" | jq '.integrations // []')

    local snapshots
    snapshots=$(echo "$manifest" | jq '.snapshots // []')

    # Generate markdown report
    cat > "$report_file" <<EOF
# Flatline Protocol Escalation Report

**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Run ID:** \`$run_id\`
**Phase:** $phase
**Status:** HALTED

## Halt Reason

$reason

## Document

$(if [[ -n "$document" ]]; then echo "\`$document\`"; else echo "N/A"; fi)

## Blockers

$(if echo "$blockers_json" | jq -e 'length > 0' >/dev/null 2>&1; then
    echo "$blockers_json" | jq -r '.[] | "### " + (.id // .item_id // "Blocker") + "\n\n**Severity:** " + (.severity // "unknown") + "\n\n**Description:** " + (.description // .text // "No description") + "\n\n**Source:** " + (.source // "unknown") + "\n\n**Recommendation:** " + (.recommendation // "Review and address") + "\n"'
else
    echo "_No blockers recorded_"
fi)

## Disputed Items

$(if echo "$disputed_json" | jq -e 'length > 0' >/dev/null 2>&1; then
    echo "$disputed_json" | jq -r '.[] | "- **" + (.id // .item_id // "Disputed") + "**: " + (.description // .text // "No description")'
else
    echo "_No disputed items recorded_"
fi)

## Prior Integrations

$(if echo "$integrations" | jq -e 'length > 0' >/dev/null 2>&1; then
    echo "| Integration ID | Type | Status |"
    echo "|----------------|------|--------|"
    echo "$integrations" | jq -r '.[] | "| \(.integration_id) | \(.type) | \(.status) |"'
else
    echo "_No integrations were made before halt_"
fi)

## Rollback Instructions

To rollback all integrations from this run:

\`\`\`bash
# Preview rollback
.claude/scripts/flatline-rollback.sh run --run-id $run_id --dry-run

# Execute rollback
.claude/scripts/flatline-rollback.sh run --run-id $run_id

# Or rollback individual integration
.claude/scripts/flatline-rollback.sh single --integration-id <id> --run-id $run_id
\`\`\`

## Context

| Context | Path |
|---------|------|
| Manifest | \`.flatline/runs/${run_id}.json\` |
| Trajectory | \`grimoires/loa/a2a/trajectory/flatline-*.jsonl\` |
$(echo "$snapshots" | jq -r '.[] | "| Snapshot | `.flatline/snapshots/" + . + ".snapshot` |"' 2>/dev/null || true)

## Next Steps

1. Review the blockers and disputed items above
2. Address the concerns in the document
3. Decide on rollback if needed
4. Resume with \`/autonomous --resume\` or re-run Flatline review

---

_This report was generated automatically by Flatline Protocol v1.22.0_
EOF

    # Generate JSON report
    jq -n \
        --arg run_id "$run_id" \
        --arg phase "$phase" \
        --arg reason "$reason" \
        --arg document "${document:-}" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg report_path "$report_file" \
        --argjson blockers "$blockers_json" \
        --argjson disputed "$disputed_json" \
        --argjson integrations "$integrations" \
        --argjson snapshots "$snapshots" \
        '{
            run_id: $run_id,
            phase: $phase,
            reason: $reason,
            document: (if $document == "" then null else $document end),
            timestamp: $timestamp,
            report_path: $report_path,
            blockers: $blockers,
            disputed: $disputed,
            integrations: $integrations,
            snapshots: $snapshots,
            status: "halted"
        }' > "$report_json"

    log "Created escalation report: $report_file"
    log_trajectory "escalation_created" "$(cat "$report_json")"

    # Update manifest status
    if [[ -x "$MANIFEST_SCRIPT" ]]; then
        "$MANIFEST_SCRIPT" update "$run_id" --field status --value "escalated" 2>/dev/null || true
    fi

    echo "$report_file"
}

get_escalation_report() {
    local run_id="$1"

    # Find report by run_id
    local report_json
    report_json=$(find "$ESCALATION_DIR" -name "escalation-*.json" -type f -exec grep -l "\"run_id\": \"$run_id\"" {} \; 2>/dev/null | head -1)

    if [[ -z "$report_json" || ! -f "$report_json" ]]; then
        error "Escalation report not found for run: $run_id"
        return 2
    fi

    cat "$report_json"
}

list_escalation_reports() {
    if [[ ! -d "$ESCALATION_DIR" ]]; then
        echo "[]"
        return 0
    fi

    local reports=()

    while IFS= read -r -d '' report_json; do
        local summary
        summary=$(jq '{run_id: .run_id, phase: .phase, reason: .reason, timestamp: .timestamp, report_path: .report_path}' "$report_json" 2>/dev/null)
        if [[ -n "$summary" ]]; then
            reports+=("$summary")
        fi
    done < <(find "$ESCALATION_DIR" -name "escalation-*.json" -type f -print0 2>/dev/null)

    if [[ ${#reports[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${reports[@]}" | jq -s '.'
    fi
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-escalation.sh <command> [options]

Commands:
  create                   Create escalation report
    --run-id <id>          Run ID (required)
    --phase <type>         Phase: prd, sdd, sprint (required)
    --reason <text>        Halt reason (required)
    --document <path>      Document path (optional)
    --blockers <json>      Blockers JSON array (optional)
    --disputed <json>      Disputed items JSON array (optional)

  get                      Get escalation report
    --run-id <id>          Run ID (required)

  list                     List all escalation reports

Examples:
  flatline-escalation.sh create --run-id flatline-run-abc123 --phase prd \\
      --reason "BLOCKER: Missing security requirements"

  flatline-escalation.sh get --run-id flatline-run-abc123

  flatline-escalation.sh list

Exit codes:
  0 - Success
  1 - Report creation failed
  2 - Report not found
  3 - Invalid arguments
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 3
    fi

    local command="$1"
    shift

    case "$command" in
        create)
            local run_id=""
            local phase=""
            local reason=""
            local document=""
            local blockers="[]"
            local disputed="[]"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --run-id)
                        run_id="$2"
                        shift 2
                        ;;
                    --phase)
                        phase="$2"
                        shift 2
                        ;;
                    --reason)
                        reason="$2"
                        shift 2
                        ;;
                    --document)
                        document="$2"
                        shift 2
                        ;;
                    --blockers)
                        blockers="$2"
                        shift 2
                        ;;
                    --disputed)
                        disputed="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        error "Unexpected argument: $1"
                        exit 3
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "--run-id required"
                exit 3
            fi
            if [[ -z "$phase" ]]; then
                error "--phase required"
                exit 3
            fi
            if [[ -z "$reason" ]]; then
                error "--reason required"
                exit 3
            fi

            create_escalation_report "$run_id" "$phase" "$reason" "$document" "$blockers" "$disputed"
            ;;

        get)
            local run_id=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --run-id)
                        run_id="$2"
                        shift 2
                        ;;
                    -*)
                        error "Unknown option: $1"
                        exit 3
                        ;;
                    *)
                        error "Unexpected argument: $1"
                        exit 3
                        ;;
                esac
            done

            if [[ -z "$run_id" ]]; then
                error "--run-id required"
                exit 3
            fi

            get_escalation_report "$run_id"
            ;;

        list)
            list_escalation_reports
            ;;

        -h|--help|help)
            usage
            exit 0
            ;;

        *)
            error "Unknown command: $command"
            usage
            exit 3
            ;;
    esac
}

main "$@"
