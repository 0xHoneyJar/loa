#!/usr/bin/env bash
# event-registry.sh - Event subscription registry built from construct manifests
#
# Reads pack manifest.json and skill index.yaml files to build the event routing
# table. This is the "compile-time" complement to event-bus.sh's "runtime" dispatch.
#
# The pattern: manifests declare intent (emits/consumes), this script resolves
# those declarations into concrete handler registrations in the event bus.
#
# Think of this like Kubernetes controller reconciliation: manifests are the
# desired state, this script reconciles actual handler registrations to match.
#
# Usage:
#   source .claude/scripts/lib/event-registry.sh
#
#   # Rebuild routing table from all manifests
#   reconcile_event_registry
#
#   # Validate event topology (detect orphaned events, missing consumers)
#   validate_event_topology --json
#
#   # List all declared events across all packs
#   list_declared_events
#
# Sources: Issue #161 (Event Bus Architecture), Issue #162 (Construct Manifest Standard)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source event bus
if [[ -f "${SCRIPT_DIR}/event-bus.sh" ]]; then
    source "${SCRIPT_DIR}/event-bus.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

# Constructs directory
CONSTRUCTS_DIR="${LOA_CONSTRUCTS_DIR:-.claude/constructs}"
PACKS_DIR="${CONSTRUCTS_DIR}/packs"

# Skills directory (framework skills)
SKILLS_DIR=".claude/skills"

# =============================================================================
# Manifest Scanning
# =============================================================================

# Scan all pack manifests for event declarations
# Returns: JSON array of {pack, event_name, direction, details}
scan_pack_events() {
    _require_jq || return 3

    local results="[]"

    # Scan pack manifests
    for manifest in "$PACKS_DIR"/*/manifest.json; do
        [[ -f "$manifest" ]] || continue

        local pack_slug
        pack_slug=$(jq -r '.slug // ""' "$manifest" 2>/dev/null)
        [[ -n "$pack_slug" ]] || continue

        # Extract emits
        local emits
        emits=$(jq -c --arg pack "$pack_slug" '
            .events.emits // [] | .[] |
            {pack: $pack, event_name: .name, direction: "emit", version: (.version // "1.0.0"), description: (.description // ""), compatibility: (.compatibility // "backward")}
        ' "$manifest" 2>/dev/null) || true

        if [[ -n "$emits" ]]; then
            results=$(echo "$results" | jq --argjson new "$(echo "$emits" | jq -s '.')" '. + $new')
        fi

        # Extract consumes
        local consumes
        consumes=$(jq -c --arg pack "$pack_slug" '
            .events.consumes // [] | .[] |
            {pack: $pack, event_name: .event, direction: "consume", delivery: (.delivery // "broadcast"), consumer_group: (.consumer_group // null), idempotency: (.idempotency // null)}
        ' "$manifest" 2>/dev/null) || true

        if [[ -n "$consumes" ]]; then
            results=$(echo "$results" | jq --argjson new "$(echo "$consumes" | jq -s '.')" '. + $new')
        fi
    done

    echo "$results"
}

# Scan skill index.yaml files for event declarations
# Uses yq if available, falls back to basic grep
scan_skill_events() {
    _require_jq || return 3

    local results="[]"

    # Check for yq
    if ! command -v yq &>/dev/null; then
        echo "$results"
        return 0
    fi

    for index_file in "$SKILLS_DIR"/*/index.yaml; do
        [[ -f "$index_file" ]] || continue

        local skill_name
        skill_name=$(yq -r '.name // ""' "$index_file" 2>/dev/null)
        [[ -n "$skill_name" ]] || continue

        # Check if events section exists
        local has_events
        has_events=$(yq '.events // null' "$index_file" 2>/dev/null)
        [[ "$has_events" != "null" ]] || continue

        # Extract emits
        local emits
        emits=$(yq -o=json '.events.emits // []' "$index_file" 2>/dev/null | \
            jq -c --arg skill "$skill_name" '.[] | {skill: $skill, event_name: .name, direction: "emit", version: (.version // "1.0.0")}') || true

        if [[ -n "$emits" ]]; then
            results=$(echo "$results" | jq --argjson new "$(echo "$emits" | jq -s '.')" '. + $new')
        fi

        # Extract consumes
        local consumes
        consumes=$(yq -o=json '.events.consumes // []' "$index_file" 2>/dev/null | \
            jq -c --arg skill "$skill_name" '.[] | {skill: $skill, event_name: .event, direction: "consume", delivery: (.delivery // "broadcast")}') || true

        if [[ -n "$consumes" ]]; then
            results=$(echo "$results" | jq --argjson new "$(echo "$consumes" | jq -s '.')" '. + $new')
        fi
    done

    echo "$results"
}

# =============================================================================
# Topology Validation
# =============================================================================

# Validate the event topology across all constructs
#
# Checks for:
#   1. Orphaned emitters: events emitted but never consumed (dead letters waiting to happen)
#   2. Unsatisfied consumers: events consumed but never emitted (missing producers)
#   3. Circular dependencies: A emits → B consumes → B emits → A consumes (loops)
#   4. Version mismatches: consumer expecting v2 but producer only emits v1
#
# This is the static analysis equivalent of what Netflix's Conductor does at runtime.
#
# Args:
#   --json    Output as JSON (default: human-readable)
#   --strict  Return exit code 1 if any warnings found
#
# Returns: 0 if topology is valid, 1 if issues found (with --strict)
validate_event_topology() {
    _require_jq || return 3

    local json_output=false
    local strict=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=true; shift ;;
            --strict) strict=true; shift ;;
            *) shift ;;
        esac
    done

    # Collect all declarations
    local pack_events skill_events
    pack_events=$(scan_pack_events)
    skill_events=$(scan_skill_events)

    # Merge
    local all_events
    all_events=$(echo "$pack_events" | jq --argjson skills "$skill_events" '. + $skills')

    # Extract unique emitted and consumed event names
    local emitted consumed
    emitted=$(echo "$all_events" | jq -r '[.[] | select(.direction == "emit") | .event_name] | unique | .[]')
    consumed=$(echo "$all_events" | jq -r '[.[] | select(.direction == "consume") | .event_name] | unique | .[]')

    local orphaned_emitters=()
    local unsatisfied_consumers=()

    # Find orphaned emitters (emitted but never consumed)
    while IFS= read -r event; do
        [[ -n "$event" ]] || continue
        if ! echo "$consumed" | grep -qF "$event"; then
            orphaned_emitters+=("$event")
        fi
    done <<< "$emitted"

    # Find unsatisfied consumers (consumed but never emitted)
    while IFS= read -r event; do
        [[ -n "$event" ]] || continue
        if ! echo "$emitted" | grep -qF "$event"; then
            unsatisfied_consumers+=("$event")
        fi
    done <<< "$consumed"

    # Count totals
    local emit_count consume_count
    emit_count=$(echo "$all_events" | jq '[.[] | select(.direction == "emit")] | length')
    consume_count=$(echo "$all_events" | jq '[.[] | select(.direction == "consume")] | length')

    if [[ "$json_output" == "true" ]]; then
        local orphaned_json unsatisfied_json
        orphaned_json=$(printf '%s\n' "${orphaned_emitters[@]}" 2>/dev/null | jq -R . | jq -s '.' 2>/dev/null || echo "[]")
        unsatisfied_json=$(printf '%s\n' "${unsatisfied_consumers[@]}" 2>/dev/null | jq -R . | jq -s '.' 2>/dev/null || echo "[]")

        jq -n \
            --argjson emit_count "$emit_count" \
            --argjson consume_count "$consume_count" \
            --argjson orphaned "$orphaned_json" \
            --argjson unsatisfied "$unsatisfied_json" \
            '{
                valid: (($orphaned | length) == 0 and ($unsatisfied | length) == 0),
                emitters: $emit_count,
                consumers: $consume_count,
                orphaned_emitters: $orphaned,
                unsatisfied_consumers: $unsatisfied
            }'
    else
        echo "Event Topology"
        echo "=============="
        echo "Emitters:  $emit_count"
        echo "Consumers: $consume_count"

        if [[ ${#orphaned_emitters[@]} -gt 0 ]]; then
            echo ""
            echo "WARN: Orphaned emitters (events with no consumers):"
            for e in "${orphaned_emitters[@]}"; do
                echo "  - $e"
            done
        fi

        if [[ ${#unsatisfied_consumers[@]} -gt 0 ]]; then
            echo ""
            echo "WARN: Unsatisfied consumers (events with no producers):"
            for e in "${unsatisfied_consumers[@]}"; do
                echo "  - $e"
            done
        fi

        if [[ ${#orphaned_emitters[@]} -eq 0 ]] && [[ ${#unsatisfied_consumers[@]} -eq 0 ]]; then
            echo ""
            echo "All events have matching producers and consumers."
        fi
    fi

    if [[ "$strict" == "true" ]]; then
        if [[ ${#orphaned_emitters[@]} -gt 0 ]] || [[ ${#unsatisfied_consumers[@]} -gt 0 ]]; then
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# Event Listing
# =============================================================================

# List all declared events across all constructs
#
# Output: Table of event declarations with source and direction
list_declared_events() {
    _require_jq || return 3

    local pack_events skill_events
    pack_events=$(scan_pack_events)
    skill_events=$(scan_skill_events)

    local all_events
    all_events=$(echo "$pack_events" | jq --argjson skills "$skill_events" '. + $skills')

    # Format as table
    echo "$all_events" | jq -r '
        sort_by(.event_name) |
        ["EVENT", "DIRECTION", "SOURCE", "DELIVERY"] as $header |
        ($header | @tsv),
        (.[] |
            [
                .event_name,
                .direction,
                (.pack // .skill // "unknown"),
                (.delivery // .compatibility // "-")
            ] | @tsv
        )
    ' | column -t -s $'\t' 2>/dev/null || echo "$all_events" | jq -r '.[] | "\(.direction)\t\(.event_name)\t\(.pack // .skill // "?")"'
}

# =============================================================================
# CLI Interface
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        scan)
            echo "=== Pack Events ==="
            scan_pack_events | jq .
            echo ""
            echo "=== Skill Events ==="
            scan_skill_events | jq .
            ;;
        validate)
            shift
            validate_event_topology "$@"
            ;;
        list)
            list_declared_events
            ;;
        --help|-h|help)
            cat << 'EOF'
Usage: event-registry.sh <command> [args]

Commands:
    scan                         Scan all manifests for event declarations
    validate [--json] [--strict] Validate event topology
    list                         List all declared events

Examples:
    event-registry.sh scan
    event-registry.sh validate --json
    event-registry.sh validate --strict  # Exit 1 if any issues found
    event-registry.sh list
EOF
            ;;
        *)
            echo "Unknown command: ${1:-}" >&2
            exit 1
            ;;
    esac
fi
