#!/usr/bin/env bash
# =============================================================================
# archetype-resolver.sh — Operator OS mode activation and ambient greeting
# =============================================================================
# Manages personal workflow modes (archetypes) defined in .loa.config.yaml
# under operator_os.modes. Each mode bundles constructs with merged gates
# and a single entry point command.
#
# Subcommands:
#   activate <mode> [--config PATH] [--index PATH]
#   deactivate
#   status [--json]
#   greeting [--config PATH] [--index PATH]
#
# Exit Codes:
#   0 = success
#   1 = mode not defined in config
#   2 = construct not installed (missing from index)
#   3 = construct index missing
#   4 = config file missing
#
# Sources: cycle-051, Sprint 105
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source shared libraries
if [[ -f "$SCRIPT_DIR/compat-lib.sh" ]]; then
    source "$SCRIPT_DIR/compat-lib.sh"
    # compat-lib probes lazily; _date_to_epoch runs inside $(...) per thread line below, so probe once here.
    _compat_need_os
fi

if [[ -f "$SCRIPT_DIR/yq-safe.sh" ]]; then
    source "$SCRIPT_DIR/yq-safe.sh"
fi

# =============================================================================
# Default paths
# =============================================================================

DEFAULT_CONFIG="$PROJECT_ROOT/.loa.config.yaml"
DEFAULT_INDEX="$PROJECT_ROOT/.run/construct-index.yaml"
ARCHETYPE_FILE="${ARCHETYPE_FILE:-$PROJECT_ROOT/.run/archetype.yaml}"
THREADS_FILE="${THREADS_FILE:-$PROJECT_ROOT/.run/open-threads.jsonl}"

# =============================================================================
# Helpers
# =============================================================================

_err() {
    echo "ERROR: $*" >&2
}

_info() {
    echo "$@" >&2
}

# Resolve construct index — accepts YAML or JSON
# Args: $1 = index path
# Returns: JSON on stdout
_read_index_as_json() {
    local index_path="$1"
    if [[ ! -f "$index_path" ]]; then
        return 1
    fi

    # Try JSON first
    if jq empty "$index_path" 2>/dev/null; then
        jq '.' "$index_path"
        return 0
    fi

    # Try YAML → JSON
    if command -v yq &>/dev/null; then
        yq eval -o=json '.' "$index_path" 2>/dev/null
        return 0
    fi

    return 1
}

# =============================================================================
# activate <mode> [--config PATH] [--index PATH]
# =============================================================================

cmd_activate() {
    local mode=""
    local config_path="$DEFAULT_CONFIG"
    local index_path="$DEFAULT_INDEX"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config_path="$2"; shift 2 ;;
            --index) index_path="$2"; shift 2 ;;
            -*) _err "Unknown flag: $1"; return 1 ;;
            *) mode="$1"; shift ;;
        esac
    done

    if [[ -z "$mode" ]]; then
        _err "Usage: archetype-resolver.sh activate <mode> [--config PATH] [--index PATH]"
        return 1
    fi

    # Check config exists
    if [[ ! -f "$config_path" ]]; then
        _err "Config file not found: $config_path"
        return 4
    fi

    # Check index exists
    if [[ ! -f "$index_path" ]]; then
        _err "Construct index not found: $index_path"
        _err "Run: construct-index-gen.sh to generate it"
        return 3
    fi

    # Read mode definition from config
    local mode_exists
    mode_exists=$(yq eval ".operator_os.modes.$mode // \"\"" "$config_path" 2>/dev/null || echo "")

    if [[ -z "$mode_exists" || "$mode_exists" == "null" ]]; then
        _err "Mode '$mode' not defined in operator_os.modes"
        return 1
    fi

    # Extract constructs list
    local constructs_yaml
    constructs_yaml=$(yq eval -o=json ".operator_os.modes.$mode.constructs // []" "$config_path" 2>/dev/null || echo "[]")

    local construct_count
    construct_count=$(echo "$constructs_yaml" | jq 'length')

    if [[ "$construct_count" -eq 0 ]]; then
        _err "Mode '$mode' has no constructs defined"
        return 1
    fi

    # Extract entry_point
    local entry_point
    entry_point=$(yq eval ".operator_os.modes.$mode.entry_point // \"\"" "$config_path" 2>/dev/null || echo "")

    # Read index as JSON
    local index_json
    index_json=$(_read_index_as_json "$index_path") || {
        _err "Failed to parse construct index"
        return 3
    }

    # Verify each construct is installed and collect metadata
    local active_constructs="[]"
    local merged_review="__unset__"
    local merged_audit="__unset__"

    local i=0
    while [[ $i -lt $construct_count ]]; do
        local slug
        slug=$(echo "$constructs_yaml" | jq -r ".[$i]")

        # Look up construct in index
        local found
        found=$(echo "$index_json" | jq -r --arg slug "$slug" '.constructs[] | select(.slug == $slug) | .slug')

        if [[ -z "$found" ]]; then
            _err "Construct '$slug' not installed. Run: /constructs install $slug"
            return 2
        fi

        # Get version
        local version
        version=$(echo "$index_json" | jq -r --arg slug "$slug" '.constructs[] | select(.slug == $slug) | .version // "0.0.0"')

        # Add to active constructs
        active_constructs=$(echo "$active_constructs" | jq --arg slug "$slug" --arg version "$version" \
            '. + [{"slug": $slug, "version": $version}]')

        # Merge gates: most-restrictive-wins (any true → merged is true, null treated as no-gate)
        local gate_review gate_audit
        gate_review=$(echo "$index_json" | jq -r --arg slug "$slug" \
            '.constructs[] | select(.slug == $slug) | .gates.review // "null"')
        gate_audit=$(echo "$index_json" | jq -r --arg slug "$slug" \
            '.constructs[] | select(.slug == $slug) | .gates.audit // "null"')

        # Most-restrictive merge for review
        if [[ "$gate_review" == "true" || "$gate_review" == "required" ]]; then
            merged_review="true"
        elif [[ "$merged_review" == "__unset__" && "$gate_review" != "null" ]]; then
            merged_review="$gate_review"
        elif [[ "$merged_review" == "__unset__" ]]; then
            : # keep unset
        fi

        # Most-restrictive merge for audit
        if [[ "$gate_audit" == "true" || "$gate_audit" == "required" ]]; then
            merged_audit="true"
        elif [[ "$merged_audit" == "__unset__" && "$gate_audit" != "null" ]]; then
            merged_audit="$gate_audit"
        elif [[ "$merged_audit" == "__unset__" ]]; then
            : # keep unset
        fi

        i=$((i + 1))
    done

    # Resolve final gate values: unset → false
    [[ "$merged_review" == "__unset__" ]] && merged_review="false"
    [[ "$merged_audit" == "__unset__" ]] && merged_audit="false"

    # Write archetype.yaml
    local activated_at
    activated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    mkdir -p "$(dirname "$ARCHETYPE_FILE")"

    local archetype_json
    archetype_json=$(jq -n \
        --arg active_mode "$mode" \
        --argjson active_constructs "$active_constructs" \
        --argjson review "$merged_review" \
        --argjson audit "$merged_audit" \
        --arg entry_point "$entry_point" \
        --arg activated_at "$activated_at" \
        '{
            active_mode: $active_mode,
            active_constructs: $active_constructs,
            merged_gates: {
                review: $review,
                audit: $audit
            },
            entry_point: $entry_point,
            activated_at: $activated_at
        }')

    if command -v yq &>/dev/null; then
        echo "$archetype_json" | yq eval -P '.' > "$ARCHETYPE_FILE"
    else
        echo "$archetype_json" > "$ARCHETYPE_FILE"
    fi

    _info "Activated mode: $mode"
    return 0
}

# =============================================================================
# deactivate
# =============================================================================

cmd_deactivate() {
    if [[ -f "$ARCHETYPE_FILE" ]]; then
        rm -f "$ARCHETYPE_FILE"
        _info "Deactivated archetype mode"
    else
        _info "No active mode to deactivate"
    fi
    return 0
}

# =============================================================================
# status [--json]
# =============================================================================

cmd_status() {
    local json_output=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output=true; shift ;;
            *) _err "Unknown flag: $1"; return 1 ;;
        esac
    done

    if [[ ! -f "$ARCHETYPE_FILE" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"active": false}'
        else
            echo "No active mode."
        fi
        return 0
    fi

    if [[ "$json_output" == "true" ]]; then
        local content
        if jq empty "$ARCHETYPE_FILE" 2>/dev/null; then
            content=$(jq '.' "$ARCHETYPE_FILE")
        elif command -v yq &>/dev/null; then
            content=$(yq eval -o=json '.' "$ARCHETYPE_FILE")
        else
            _err "Cannot read archetype file"
            return 1
        fi
        echo "$content" | jq '. + {"active": true}'
    else
        local active_mode
        if command -v yq &>/dev/null; then
            active_mode=$(yq eval '.active_mode' "$ARCHETYPE_FILE" 2>/dev/null || echo "unknown")
        else
            active_mode=$(jq -r '.active_mode' "$ARCHETYPE_FILE" 2>/dev/null || echo "unknown")
        fi
        echo "Active mode: $active_mode"

        # Print constructs
        local constructs
        if command -v yq &>/dev/null; then
            constructs=$(yq eval -o=json '.active_constructs // []' "$ARCHETYPE_FILE" 2>/dev/null || echo "[]")
        else
            constructs=$(jq -c '.active_constructs // []' "$ARCHETYPE_FILE" 2>/dev/null || echo "[]")
        fi

        local count
        count=$(echo "$constructs" | jq 'length')
        local idx=0
        while [[ $idx -lt $count ]]; do
            local s v
            s=$(echo "$constructs" | jq -r ".[$idx].slug")
            v=$(echo "$constructs" | jq -r ".[$idx].version")
            echo "  - $s (v$v)"
            idx=$((idx + 1))
        done
    fi

    return 0
}

# =============================================================================
# greeting [--config PATH] [--index PATH]
# =============================================================================

cmd_greeting() {
    local config_path="$DEFAULT_CONFIG"
    local index_path="$DEFAULT_INDEX"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config) config_path="$2"; shift 2 ;;
            --index) index_path="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Check config exists — if not, silent exit (no greeting)
    if [[ ! -f "$config_path" ]]; then
        return 0
    fi

    # Check ambient_greeting setting
    local ambient_greeting
    ambient_greeting=$(yq eval '.constructs.ambient_greeting // false' "$config_path" 2>/dev/null || echo "false")

    if [[ "$ambient_greeting" != "true" ]]; then
        return 0
    fi

    # Check index exists
    if [[ ! -f "$index_path" ]]; then
        return 0
    fi

    # Read index
    local index_json
    index_json=$(_read_index_as_json "$index_path") || return 0

    local construct_count
    construct_count=$(echo "$index_json" | jq '.constructs | length')

    # No constructs installed → silent exit
    if [[ "$construct_count" -eq 0 ]]; then
        return 0
    fi

    # Build "Active:" line with names and versions
    local active_line=""
    local i=0
    while [[ $i -lt $construct_count ]]; do
        local slug version
        slug=$(echo "$index_json" | jq -r ".constructs[$i].slug")
        version=$(echo "$index_json" | jq -r ".constructs[$i].version // \"0.0.0\"")

        if [[ -n "$active_line" ]]; then
            active_line="$active_line, $slug (v$version)"
        else
            active_line="$slug (v$version)"
        fi
        i=$((i + 1))
    done

    echo "Active: $active_line"

    # Build "Compositions:" line from composes_with
    local compositions=""
    i=0
    while [[ $i -lt $construct_count ]]; do
        local slug
        slug=$(echo "$index_json" | jq -r ".constructs[$i].slug")

        local comp_count
        comp_count=$(echo "$index_json" | jq ".constructs[$i].composes_with | length")

        if [[ "$comp_count" -gt 0 ]]; then
            local j=0
            while [[ $j -lt $comp_count ]]; do
                local target
                target=$(echo "$index_json" | jq -r ".constructs[$i].composes_with[$j]")

                # Get quick_start or first command for description
                local slug_qs target_qs
                slug_qs=$(echo "$index_json" | jq -r ".constructs[$i].quick_start // .constructs[$i].slug")
                target_qs=$(echo "$index_json" | jq -r --arg t "$target" \
                    '[.constructs[] | select(.slug == $t)][0] | .quick_start // .slug')

                local comp_entry="$slug -> $target ($slug_qs -> $target_qs)"
                if [[ -n "$compositions" ]]; then
                    compositions="$compositions, $comp_entry"
                else
                    compositions="$comp_entry"
                fi
                j=$((j + 1))
            done
        fi
        i=$((i + 1))
    done

    if [[ -n "$compositions" ]]; then
        echo "Compositions: $compositions"
    fi

    # Build "Entry:" line — collect entry points from commands + active mode
    local entries=""
    i=0
    while [[ $i -lt $construct_count ]]; do
        local cmd_count
        cmd_count=$(echo "$index_json" | jq ".constructs[$i].commands | length")

        local j=0
        while [[ $j -lt $cmd_count ]]; do
            local cmd_name
            cmd_name=$(echo "$index_json" | jq -r ".constructs[$i].commands[$j].name // empty")
            if [[ -n "$cmd_name" ]]; then
                # Add / prefix if not present
                [[ "$cmd_name" == /* ]] || cmd_name="/$cmd_name"
                if [[ -z "$entries" ]]; then
                    entries="$cmd_name"
                elif [[ "$entries" != *"$cmd_name"* ]]; then
                    entries="$entries | $cmd_name"
                fi
            fi
            j=$((j + 1))
        done
        i=$((i + 1))
    done

    # Add active mode entry point
    if [[ -f "$ARCHETYPE_FILE" ]]; then
        local mode_entry
        if command -v yq &>/dev/null; then
            mode_entry=$(yq eval '.entry_point // ""' "$ARCHETYPE_FILE" 2>/dev/null || echo "")
        else
            mode_entry=$(jq -r '.entry_point // ""' "$ARCHETYPE_FILE" 2>/dev/null || echo "")
        fi

        if [[ -n "$mode_entry" && "$mode_entry" != "null" ]]; then
            if [[ -z "$entries" ]]; then
                entries="$mode_entry"
            elif [[ "$entries" != *"$mode_entry"* ]]; then
                entries="$entries | $mode_entry"
            fi
        fi
    fi

    if [[ -n "$entries" ]]; then
        echo "Entry: $entries"
    fi

    # Count open threads and auto-archive stale ones
    local threads_file="${THREADS_FILE}"
    if [[ -f "$threads_file" ]]; then
        local archive_days
        archive_days=$(yq eval '.constructs.thread_archive_days // 30' "$config_path" 2>/dev/null || echo "30")

        local now_epoch
        now_epoch=$(date +%s)

        local archive_threshold
        archive_threshold=$((now_epoch - archive_days * 86400))

        # Auto-archive stale threads
        local tmp_threads
        tmp_threads=$(mktemp)
        local archived_count=0

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local thread_status created_at_str
            thread_status=$(echo "$line" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
            created_at_str=$(echo "$line" | jq -r '.created_at // ""' 2>/dev/null || echo "")

            if [[ "$thread_status" == "open" && -n "$created_at_str" ]]; then
                local created_epoch
                created_epoch=$(_date_to_epoch "$created_at_str" 2>/dev/null || echo "0")

                if [[ -n "$created_epoch" && "$created_epoch" -gt 0 && "$created_epoch" -lt "$archive_threshold" ]]; then
                    # Archive this thread
                    echo "$line" | jq -c '.status = "archived"' >> "$tmp_threads"
                    archived_count=$((archived_count + 1))
                    continue
                fi
            fi
            echo "$line" >> "$tmp_threads"
        done < "$threads_file"

        # Replace threads file if any archived
        if [[ $archived_count -gt 0 ]]; then
            mv "$tmp_threads" "$threads_file"
        else
            rm -f "$tmp_threads"
        fi

        # Count remaining open threads
        local open_count=0
        if [[ -f "$threads_file" ]]; then
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local ts
                ts=$(echo "$line" | jq -r '.status // ""' 2>/dev/null || echo "")
                if [[ "$ts" == "open" ]]; then
                    open_count=$((open_count + 1))
                fi
            done < "$threads_file"
        fi

        if [[ $open_count -gt 0 ]]; then
            echo "Beads: $open_count open threads from previous sessions"
        fi
    fi

    return 0
}

# =============================================================================
# Main dispatcher
# =============================================================================

main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: archetype-resolver.sh <activate|deactivate|status|greeting> [args...]"
        echo "Subcommands:"
        echo "  activate <mode> [--config PATH] [--index PATH]"
        echo "  deactivate"
        echo "  status [--json]"
        echo "  greeting [--config PATH] [--index PATH]"
        return 1
    fi

    local subcmd="$1"
    shift

    case "$subcmd" in
        activate)   cmd_activate "$@" ;;
        deactivate) cmd_deactivate "$@" ;;
        status)     cmd_status "$@" ;;
        greeting)   cmd_greeting "$@" ;;
        -h|--help)
            echo "Usage: archetype-resolver.sh <activate|deactivate|status|greeting> [args...]"
            return 0
            ;;
        *)
            _err "Unknown subcommand: $subcmd"
            return 1
            ;;
    esac
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
