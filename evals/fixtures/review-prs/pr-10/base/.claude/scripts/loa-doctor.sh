#!/usr/bin/env bash
# loa-doctor.sh — Comprehensive health check for Loa framework
# Issue #211: DX comparison to Vercel and other popular agent CLI tools
#
# Inspired by: flutter doctor, brew doctor, npm doctor
# Design: Read-only checks, educational output, no mutations
#
# Exit codes:
#   0 — HEALTHY: All checks pass
#   1 — UNHEALTHY: Critical issues found (missing hard dependencies, broken framework)
#   2 — DEGRADED: Warnings present but non-blocking (missing optional tools, stale state)
#
# Check categories:
#   dependencies   — Hard requirements (git, jq)
#   optional_tools — Nice-to-have tools (br, sqlite3, ajv)
#   framework      — System Zone integrity (.claude/, config, version file)
#   project_state  — Grimoire artifacts (PRD, SDD, sprint)
#   event_bus      — Event store health (directory, DLQ)
#   beads          — Beads task tracking (delegates to beads-health.sh)
#
# Usage:
#   ./loa-doctor.sh                    # Full check, text output
#   ./loa-doctor.sh --json             # Full check, JSON output
#   ./loa-doctor.sh --quick            # Fast checks only (< 5s)
#   ./loa-doctor.sh --category deps    # Single category
#   ./loa-doctor.sh --verbose          # Show passing checks too
#   ./loa-doctor.sh --timeout 10       # Per-check timeout in seconds
#
# References:
#   - https://clig.dev/
#   - https://rust-lang.github.io/rfcs/1644-default-and-expanded-rustc-errors.html

set -euo pipefail

# =============================================================================
# Bootstrap
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT
if [[ -f "${SCRIPT_DIR}/bootstrap.sh" ]]; then
    source "${SCRIPT_DIR}/bootstrap.sh"
fi
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# Source DX utilities
if [[ -f "${SCRIPT_DIR}/lib/dx-utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/dx-utils.sh"
else
    # Minimal fallback if dx-utils not available
    echo "Warning: dx-utils.sh not found. Output will be basic." >&2
fi

# Source compat-lib if available (for _COMPAT_OS)
if [[ -f "${SCRIPT_DIR}/compat-lib.sh" ]]; then
    source "${SCRIPT_DIR}/compat-lib.sh" 2>/dev/null || true
fi

# =============================================================================
# Configuration
# =============================================================================

OUTPUT_MODE="text"
VERBOSE=false
QUICK=false
CATEGORY_FILTER=""
CHECK_TIMEOUT="${LOA_DOCTOR_TIMEOUT:-30}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_MODE="json"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --quick)
            QUICK=true
            CHECK_TIMEOUT=5
            shift
            ;;
        --category)
            CATEGORY_FILTER="$2"
            shift 2
            ;;
        --timeout)
            CHECK_TIMEOUT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: loa-doctor.sh [--json] [--verbose] [--quick] [--category CATEGORY] [--timeout SECONDS]"
            echo ""
            echo "Categories: dependencies, optional_tools, framework, project_state, event_bus, beads"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# State Tracking (TD-4: Independent Check Architecture)
# =============================================================================

# Results stored as parallel arrays (portable across bash 4+)
declare -a _DOCTOR_CHECK_CATEGORIES=()
declare -a _DOCTOR_CHECK_NAMES=()
declare -a _DOCTOR_CHECK_STATUSES=()
declare -a _DOCTOR_CHECK_DETAILS=()
declare -a _DOCTOR_CHECK_VERSIONS=()

declare -a _DOCTOR_SUGGESTIONS=()
declare -i _DOCTOR_ISSUES=0
declare -i _DOCTOR_WARNINGS=0

_doctor_add_check() {
    local category="$1" name="$2" status="$3" detail="${4:-}" version="${5:-}"
    _DOCTOR_CHECK_CATEGORIES+=("$category")
    _DOCTOR_CHECK_NAMES+=("$name")
    _DOCTOR_CHECK_STATUSES+=("$status")
    _DOCTOR_CHECK_DETAILS+=("$detail")
    _DOCTOR_CHECK_VERSIONS+=("$version")
}

_doctor_add_suggestion() {
    _DOCTOR_SUGGESTIONS+=("$1")
}

# =============================================================================
# Check Functions (all read-only, no mutations)
# =============================================================================

check_dependencies() {
    # git — hard requirement
    if command -v git &>/dev/null; then
        local git_ver
        git_ver=$(git --version 2>&1 | head -1 | sed 's/git version //')
        _doctor_add_check "dependencies" "git" "ok" "Version control" "$git_ver"
    else
        _doctor_add_check "dependencies" "git" "issue" "Not installed"
        _doctor_add_suggestion "Install git: $(type -f _dx_install_hint &>/dev/null && _dx_install_hint git || echo 'See https://git-scm.com/')"
        _DOCTOR_ISSUES=$(( _DOCTOR_ISSUES + 1 ))
    fi

    # jq — hard requirement (error registry, JSON output, event bus)
    if command -v jq &>/dev/null; then
        local jq_ver
        jq_ver=$(jq --version 2>&1 | head -1)
        _doctor_add_check "dependencies" "jq" "ok" "JSON processor" "$jq_ver"
    else
        _doctor_add_check "dependencies" "jq" "issue" "Not installed — error registry, JSON output, and event bus require jq"
        if type -t _dx_install_hint &>/dev/null; then
            _doctor_add_suggestion "Install jq: $(_dx_install_hint jq)"
        else
            _doctor_add_suggestion "Install jq: brew install jq (macOS) or apt install jq (Linux)"
        fi
        _DOCTOR_ISSUES=$(( _DOCTOR_ISSUES + 1 ))
    fi

    # yq — soft requirement (config parsing)
    if command -v yq &>/dev/null; then
        local yq_ver
        yq_ver=$(yq --version 2>&1 | head -1)
        _doctor_add_check "dependencies" "yq" "ok" "YAML processor" "$yq_ver"
    else
        _doctor_add_check "dependencies" "yq" "warning" "Not installed — config parsing uses defaults without yq"
        if type -t _dx_install_hint &>/dev/null; then
            _doctor_add_suggestion "Install yq: $(_dx_install_hint yq)"
        else
            _doctor_add_suggestion "Install yq: brew install yq (macOS) or snap install yq (Linux)"
        fi
        _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
    fi

    # flock — soft requirement (atomic writes for event bus)
    if command -v flock &>/dev/null; then
        _doctor_add_check "dependencies" "flock" "ok" "File locking for atomic writes"
    else
        _doctor_add_check "dependencies" "flock" "warning" "Not installed — event bus uses flock for atomic writes"
        if type -t _dx_install_hint &>/dev/null; then
            _doctor_add_suggestion "Install flock: $(_dx_install_hint flock)"
        else
            _doctor_add_suggestion "Install flock: brew install flock (macOS) or apt install util-linux (Linux)"
        fi
        _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
    fi
}

check_optional_tools() {
    # br (beads_rust) — optional task tracking
    if command -v br &>/dev/null; then
        local br_ver
        br_ver=$(br --version 2>&1 | head -1 || echo "unknown")
        _doctor_add_check "optional_tools" "br" "ok" "Beads task tracking" "$br_ver"
    else
        _doctor_add_check "optional_tools" "br" "info" "Not installed — enables sprint task tracking"
    fi

    # sqlite3 — optional (used by beads)
    if command -v sqlite3 &>/dev/null; then
        local sqlite_ver
        sqlite_ver=$(sqlite3 --version 2>&1 | head -1 | awk '{print $1}')
        _doctor_add_check "optional_tools" "sqlite3" "ok" "Database engine" "$sqlite_ver"
    else
        _doctor_add_check "optional_tools" "sqlite3" "info" "Not installed — used by beads for task database"
    fi

    # ajv — optional (full JSON Schema validation)
    if command -v ajv &>/dev/null; then
        local ajv_ver
        ajv_ver=$(ajv --version 2>&1 | head -1 || echo "unknown")
        _doctor_add_check "optional_tools" "ajv" "ok" "JSON Schema validator" "$ajv_ver"
    else
        _doctor_add_check "optional_tools" "ajv" "info" "Not installed — enables full JSON Schema validation"
    fi
}

check_framework() {
    # .claude/ directory (System Zone)
    if [[ -d "${PROJECT_ROOT}/.claude" ]]; then
        _doctor_add_check "framework" "system_zone" "ok" ".claude/ directory exists"
    else
        _doctor_add_check "framework" "system_zone" "issue" ".claude/ directory missing — framework not mounted"
        _doctor_add_suggestion "Run /mount to initialize the Loa framework"
        _DOCTOR_ISSUES=$(( _DOCTOR_ISSUES + 1 ))
        return  # No point checking further
    fi

    # .loa.config.yaml
    local config_file="${PROJECT_ROOT}/.loa.config.yaml"
    if [[ -f "$config_file" ]]; then
        if command -v yq &>/dev/null; then
            if yq '.' "$config_file" &>/dev/null; then
                _doctor_add_check "framework" "config" "ok" ".loa.config.yaml is valid YAML"
            else
                _doctor_add_check "framework" "config" "warning" ".loa.config.yaml has syntax errors"
                _doctor_add_suggestion "Check config syntax: yq '.' .loa.config.yaml"
                _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
            fi
        else
            _doctor_add_check "framework" "config" "ok" ".loa.config.yaml exists (yq not available for validation)"
        fi
    else
        _doctor_add_check "framework" "config" "warning" ".loa.config.yaml not found — using defaults"
        _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
    fi

    # .loa-version.json
    local version_file="${PROJECT_ROOT}/.loa-version.json"
    if [[ -f "$version_file" ]]; then
        if command -v jq &>/dev/null; then
            local fw_ver
            fw_ver=$(jq -r '.framework_version // "unknown"' "$version_file" 2>/dev/null)
            _doctor_add_check "framework" "version_file" "ok" ".loa-version.json present" "$fw_ver"
        else
            _doctor_add_check "framework" "version_file" "ok" ".loa-version.json present"
        fi
    else
        _doctor_add_check "framework" "version_file" "warning" ".loa-version.json missing"
        _doctor_add_suggestion "Run /update-loa to restore the version file"
        _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
    fi

    # Error codes data file
    local codes_file="${PROJECT_ROOT}/.claude/data/error-codes.json"
    if [[ -f "$codes_file" ]]; then
        if command -v jq &>/dev/null; then
            local code_count
            code_count=$(jq 'length' "$codes_file" 2>/dev/null || echo "0")
            _doctor_add_check "framework" "error_codes" "ok" "${code_count} error codes registered"
        else
            _doctor_add_check "framework" "error_codes" "ok" "error-codes.json exists"
        fi
    else
        _doctor_add_check "framework" "error_codes" "warning" "error-codes.json missing — error messages will be generic"
        _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
    fi
}

check_project_state() {
    # Grimoire directory
    local grimoire_dir="${PROJECT_ROOT}/grimoires/loa"
    if [[ -d "$grimoire_dir" ]]; then
        _doctor_add_check "project_state" "grimoire" "ok" "grimoires/loa/ exists"
    else
        _doctor_add_check "project_state" "grimoire" "info" "No grimoire directory — run /plan-and-analyze to start"
        return
    fi

    # PRD
    if [[ -f "${grimoire_dir}/prd.md" ]]; then
        _doctor_add_check "project_state" "prd" "ok" "PRD exists"
    else
        _doctor_add_check "project_state" "prd" "info" "No PRD — run /plan-and-analyze to create"
    fi

    # SDD
    if [[ -f "${grimoire_dir}/sdd.md" ]]; then
        _doctor_add_check "project_state" "sdd" "ok" "SDD exists"
    else
        _doctor_add_check "project_state" "sdd" "info" "No SDD — run /architect after PRD"
    fi

    # Sprint Plan
    if [[ -f "${grimoire_dir}/sprint.md" ]]; then
        _doctor_add_check "project_state" "sprint" "ok" "Sprint plan exists"
    else
        _doctor_add_check "project_state" "sprint" "info" "No sprint plan — run /sprint-plan after SDD"
    fi
}

check_event_bus() {
    # Event store directory
    local event_store="${LOA_EVENT_STORE_DIR:-${PROJECT_ROOT}/grimoires/loa/a2a/events}"
    if [[ -d "$event_store" ]]; then
        if [[ -w "$event_store" ]]; then
            _doctor_add_check "event_bus" "store_dir" "ok" "Event store exists and writable"
        else
            _doctor_add_check "event_bus" "store_dir" "issue" "Event store exists but not writable: ${event_store}"
            _DOCTOR_ISSUES=$(( _DOCTOR_ISSUES + 1 ))
        fi
    else
        _doctor_add_check "event_bus" "store_dir" "info" "Event store not initialized — created on first event emit"
    fi

    # Dead letter queue
    local dlq_file="${event_store}/dead-letter.events.jsonl"
    if [[ -f "$dlq_file" ]]; then
        local dlq_count
        dlq_count=$(wc -l < "$dlq_file" 2>/dev/null | tr -d ' ')
        if [[ "${dlq_count:-0}" -gt 0 ]]; then
            _doctor_add_check "event_bus" "dlq" "warning" "${dlq_count} entries in dead letter queue"
            _doctor_add_suggestion "Review DLQ: jq '.' ${dlq_file}"
            _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
        else
            _doctor_add_check "event_bus" "dlq" "ok" "Dead letter queue empty"
        fi
    else
        _doctor_add_check "event_bus" "dlq" "ok" "No dead letter queue file (clean)"
    fi
}

check_beads() {
    local beads_health="${PROJECT_ROOT}/.claude/scripts/beads/beads-health.sh"

    if [[ ! -f "$beads_health" ]]; then
        _doctor_add_check "beads" "health_script" "info" "beads-health.sh not found"
        return
    fi

    local beads_result=""
    if [[ "${QUICK}" == "true" ]]; then
        beads_result=$("$beads_health" --quick --json 2>/dev/null) || true
    else
        beads_result=$("$beads_health" --json 2>/dev/null) || true
    fi

    if [[ -z "$beads_result" ]]; then
        _doctor_add_check "beads" "status" "info" "beads-health.sh returned no output"
        return
    fi

    if ! command -v jq &>/dev/null; then
        _doctor_add_check "beads" "status" "info" "Cannot parse beads health (jq unavailable)"
        return
    fi

    local beads_status
    beads_status=$(echo "$beads_result" | jq -r '.status // "UNKNOWN"' 2>/dev/null)
    local beads_version
    beads_version=$(echo "$beads_result" | jq -r '.version // "unknown"' 2>/dev/null)

    case "$beads_status" in
        HEALTHY)
            _doctor_add_check "beads" "status" "ok" "Beads healthy" "$beads_version"
            ;;
        NOT_INSTALLED)
            _doctor_add_check "beads" "status" "info" "beads_rust not installed — optional task tracking"
            _doctor_add_suggestion "Install beads: cargo install beads_rust && br init"
            ;;
        NOT_INITIALIZED)
            _doctor_add_check "beads" "status" "warning" "beads_rust installed but not initialized"
            _doctor_add_suggestion "Initialize beads: br init"
            _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
            ;;
        DEGRADED)
            _doctor_add_check "beads" "status" "warning" "Beads degraded — partial functionality"
            _doctor_add_suggestion "Run: br doctor for details"
            _DOCTOR_WARNINGS=$(( _DOCTOR_WARNINGS + 1 ))
            ;;
        UNHEALTHY|MIGRATION_NEEDED)
            _doctor_add_check "beads" "status" "issue" "Beads ${beads_status,,} — needs attention"
            _doctor_add_suggestion "Run: br doctor for details"
            _DOCTOR_ISSUES=$(( _DOCTOR_ISSUES + 1 ))
            ;;
        *)
            _doctor_add_check "beads" "status" "info" "Beads status: $beads_status"
            ;;
    esac
}

# =============================================================================
# Status Determination (SDD: Status Aggregation Algorithm)
# =============================================================================

determine_status() {
    if [[ $_DOCTOR_ISSUES -gt 0 ]]; then
        echo "UNHEALTHY"
        return 1
    elif [[ $_DOCTOR_WARNINGS -gt 0 ]]; then
        echo "DEGRADED"
        return 2
    else
        echo "HEALTHY"
        return 0
    fi
}

# =============================================================================
# Output: Text Mode
# =============================================================================

output_text() {
    local status="$1"

    if type -t dx_box_top &>/dev/null; then
        echo ""
        dx_box_top
        printf "  Loa Doctor\n"
        dx_box_bottom
    else
        echo ""
        echo "  Loa Doctor"
        echo "  ================================================"
    fi

    local current_category=""
    local i=0
    while [[ $i -lt ${#_DOCTOR_CHECK_CATEGORIES[@]} ]]; do
        local cat="${_DOCTOR_CHECK_CATEGORIES[$i]}"
        local name="${_DOCTOR_CHECK_NAMES[$i]}"
        local check_status="${_DOCTOR_CHECK_STATUSES[$i]}"
        local detail="${_DOCTOR_CHECK_DETAILS[$i]}"
        local version="${_DOCTOR_CHECK_VERSIONS[$i]}"

        # Section header on category change
        if [[ "$cat" != "$current_category" ]]; then
            current_category="$cat"
            local display_cat
            case "$cat" in
                dependencies)   display_cat="Dependencies" ;;
                optional_tools) display_cat="Optional Tools" ;;
                framework)      display_cat="Framework" ;;
                project_state)  display_cat="Project State" ;;
                event_bus)      display_cat="Event Bus" ;;
                beads)          display_cat="Beads" ;;
                *)              display_cat="$cat" ;;
            esac
            if type -t dx_header &>/dev/null; then
                dx_header "$display_cat"
            else
                printf "\n  %s\n" "$display_cat"
            fi
        fi

        # Format status icon
        local icon
        case "$check_status" in
            ok)
                if type -t dx_check &>/dev/null; then
                    icon="${_DX_ICON_OK:-✓}"
                else
                    icon="✓"
                fi
                ;;
            issue)
                if type -t dx_check &>/dev/null; then
                    icon="${_DX_ICON_ERR:-✗}"
                else
                    icon="✗"
                fi
                ;;
            warning)
                if type -t dx_check &>/dev/null; then
                    icon="${_DX_ICON_WARN:-⚠}"
                else
                    icon="⚠"
                fi
                ;;
            info)
                if type -t dx_check &>/dev/null; then
                    icon="${_DX_ICON_INFO:-○}"
                else
                    icon="○"
                fi
                ;;
            *)
                icon="·"
                ;;
        esac

        # Build display text
        local display_text="$name"
        if [[ -n "$version" ]]; then
            display_text="$name ($version)"
        fi
        if [[ -n "$detail" ]] && [[ "$check_status" != "ok" || "${VERBOSE}" == "true" ]]; then
            display_text="$name — $detail"
            if [[ -n "$version" ]]; then
                display_text="$name ($version) — $detail"
            fi
        elif [[ -n "$version" ]]; then
            display_text="$name ($version)"
        fi

        if type -t dx_check &>/dev/null; then
            dx_check "$icon" "$display_text"
        else
            printf "    %s %s\n" "$icon" "$display_text"
        fi

        i=$((i + 1))
    done

    # Suggestions
    if [[ ${#_DOCTOR_SUGGESTIONS[@]} -gt 0 ]]; then
        echo ""
        if type -t dx_header &>/dev/null; then
            dx_header "Recommendations"
        else
            printf "\n  Recommendations\n"
        fi
        for suggestion in "${_DOCTOR_SUGGESTIONS[@]}"; do
            if type -t dx_suggest &>/dev/null; then
                dx_suggest "$suggestion"
            else
                printf "      → %s\n" "$suggestion"
            fi
        done
    fi

    # Summary
    if type -t dx_summary &>/dev/null; then
        dx_summary "$_DOCTOR_ISSUES" "$_DOCTOR_WARNINGS"
    else
        echo ""
        if [[ $_DOCTOR_ISSUES -eq 0 ]] && [[ $_DOCTOR_WARNINGS -eq 0 ]]; then
            echo "  All checks passed."
        else
            echo "  ${_DOCTOR_ISSUES} issue(s), ${_DOCTOR_WARNINGS} warning(s)."
        fi
    fi

    # Next steps
    if [[ "$status" == "HEALTHY" ]]; then
        if type -t dx_next_steps &>/dev/null; then
            dx_next_steps \
                "/loa|Show workflow status" \
                "/plan-and-analyze|Start a new project"
        fi
    fi

    echo ""
}

# =============================================================================
# Output: JSON Mode (API Contract v1)
# =============================================================================

output_json() {
    local status="$1"
    local exit_code="$2"

    if ! command -v jq &>/dev/null; then
        # Minimal JSON without jq
        printf '{"status":"%s","exit_code":%d,"error":"jq not available for full JSON output"}\n' \
            "$status" "$exit_code"
        return
    fi

    # Build checks object grouped by category
    local checks_json='{}'
    local i=0
    while [[ $i -lt ${#_DOCTOR_CHECK_CATEGORIES[@]} ]]; do
        local cat="${_DOCTOR_CHECK_CATEGORIES[$i]}"
        local name="${_DOCTOR_CHECK_NAMES[$i]}"
        local check_status="${_DOCTOR_CHECK_STATUSES[$i]}"
        local detail="${_DOCTOR_CHECK_DETAILS[$i]}"
        local version="${_DOCTOR_CHECK_VERSIONS[$i]}"

        # Build the check entry
        local entry
        if [[ -n "$version" ]]; then
            entry=$(jq -nc --arg s "$check_status" --arg d "$detail" --arg v "$version" \
                '{status: $s, detail: $d, version: $v}')
        else
            entry=$(jq -nc --arg s "$check_status" --arg d "$detail" \
                '{status: $s, detail: $d}')
        fi

        # Add to the category object
        checks_json=$(echo "$checks_json" | jq --arg cat "$cat" --arg name "$name" --argjson entry "$entry" \
            '.[$cat] = ((.[$cat] // {}) + {($name): $entry})')

        i=$((i + 1))
    done

    # Build recommendations array
    local recs_json='[]'
    if [[ ${#_DOCTOR_SUGGESTIONS[@]} -gt 0 ]]; then
        recs_json=$(printf '%s\n' "${_DOCTOR_SUGGESTIONS[@]}" | jq -R . | jq -s .)
    fi

    # Get framework version
    local fw_version="unknown"
    local version_file="${PROJECT_ROOT}/.loa-version.json"
    if [[ -f "$version_file" ]]; then
        fw_version=$(jq -r '.framework_version // "unknown"' "$version_file" 2>/dev/null)
    fi

    # Assemble final JSON
    jq -nc \
        --arg status "$status" \
        --argjson exit_code "$exit_code" \
        --arg version "$fw_version" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson checks "$checks_json" \
        --argjson recommendations "$recs_json" \
        --argjson issues "$_DOCTOR_ISSUES" \
        --argjson warnings "$_DOCTOR_WARNINGS" \
        '{
            status: $status,
            exit_code: $exit_code,
            version: $version,
            timestamp: $timestamp,
            checks: $checks,
            recommendations: $recommendations,
            issues: $issues,
            warnings: $warnings
        }'
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Run selected checks
    local all_categories=("dependencies" "optional_tools" "framework" "project_state" "event_bus" "beads")

    if [[ -n "$CATEGORY_FILTER" ]]; then
        # Validate category
        local valid=false
        for cat in "${all_categories[@]}"; do
            # Accept both full name and common abbreviations
            case "$CATEGORY_FILTER" in
                "$cat"|deps|dep)
                    if [[ "$CATEGORY_FILTER" == "deps" || "$CATEGORY_FILTER" == "dep" ]]; then
                        CATEGORY_FILTER="dependencies"
                    fi
                    valid=true
                    break
                    ;;
            esac
        done
        if [[ "$valid" == "false" ]]; then
            echo "Unknown category: $CATEGORY_FILTER" >&2
            echo "Valid categories: ${all_categories[*]}" >&2
            exit 1
        fi
    fi

    for cat in "${all_categories[@]}"; do
        if [[ -n "$CATEGORY_FILTER" ]] && [[ "$cat" != "$CATEGORY_FILTER" ]]; then
            continue
        fi

        case "$cat" in
            dependencies)   check_dependencies ;;
            optional_tools) check_optional_tools ;;
            framework)      check_framework ;;
            project_state)  check_project_state ;;
            event_bus)      check_event_bus ;;
            beads)          check_beads ;;
        esac
    done

    # Determine overall status
    local status exit_code
    status=$(determine_status) && exit_code=$? || exit_code=$?

    # Output results
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        output_json "$status" "$exit_code"
    else
        output_text "$status"
    fi

    exit "$exit_code"
}

main "$@"
