#!/usr/bin/env bash
# Upgrade Health Check - Post-update validation and migration suggestions
# Part of the Loa framework update flow
#
# Usage: upgrade-health-check.sh [--fix] [--json] [--quiet]
#
# Checks:
#   1. bd → br migration status
#   2. Local settings for deprecated references (bd, old permissions)
#   3. New config options available
#   4. Recommended permission additions for new features
#
# Returns:
#   0 - All healthy
#   1 - Issues found (suggestions available)
#   2 - Critical issues (migration required)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Allow overrides for testing
CONFIG_FILE="${CONFIG_FILE:-${PROJECT_ROOT}/.loa.config.yaml}"
SETTINGS_LOCAL="${SETTINGS_LOCAL:-${PROJECT_ROOT}/.claude/settings.local.json}"
BEADS_DIR="${BEADS_DIR:-${PROJECT_ROOT}/.beads}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Options
FIX_MODE=false
JSON_MODE=false
QUIET_MODE=false

# Results
ISSUES=()
WARNINGS=()
SUGGESTIONS=()
FIXES_APPLIED=()

#######################################
# Print usage information
#######################################
usage() {
    cat << 'USAGE'
Usage: upgrade-health-check.sh [OPTIONS]

Post-update health check for Loa framework upgrades.

Options:
  --fix         Auto-fix issues where possible
  --json        Output results as JSON
  --quiet       Only output issues (no informational messages)
  --help, -h    Show this help message

Checks performed:
  - beads_rust (br) migration status
  - Deprecated 'bd' references in local settings
  - New config options available in .loa.config.yaml
  - Recommended permission additions for new features

Examples:
  upgrade-health-check.sh              # Run health check
  upgrade-health-check.sh --fix        # Auto-fix where possible
  upgrade-health-check.sh --json       # JSON output for scripting
USAGE
}

#######################################
# Print functions (respecting modes)
#######################################
print_info() {
    [[ "$QUIET_MODE" == "true" ]] && return
    [[ "$JSON_MODE" == "true" ]] && return
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    [[ "$JSON_MODE" == "true" ]] && return
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    [[ "$JSON_MODE" == "true" ]] && return
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    [[ "$JSON_MODE" == "true" ]] && return
    echo -e "${RED}✗${NC} $1"
}

print_fix() {
    [[ "$JSON_MODE" == "true" ]] && return
    echo -e "${CYAN}⚡${NC} $1"
}

#######################################
# Add issue/warning/suggestion
#######################################
add_issue() {
    ISSUES+=("$1")
}

add_warning() {
    WARNINGS+=("$1")
}

add_suggestion() {
    SUGGESTIONS+=("$1")
}

add_fix() {
    FIXES_APPLIED+=("$1")
}

#######################################
# Check 1: beads_rust migration status
#######################################
check_beads_migration() {
    print_info "Checking beads_rust (br) status..."

    # Use check-beads.sh if available
    local check_script="${SCRIPT_DIR}/beads/check-beads.sh"
    if [[ -x "$check_script" ]]; then
        local status
        status=$("$check_script" 2>/dev/null) || true

        case "$status" in
            "READY")
                print_success "beads_rust (br) is ready"
                ;;
            "NOT_INSTALLED")
                add_warning "beads_rust (br) not installed - task graph features unavailable"
                add_suggestion "Install br: .claude/scripts/beads/install-br.sh"
                ;;
            "NOT_INITIALIZED")
                add_warning "beads_rust installed but not initialized"
                add_suggestion "Initialize: br init"
                ;;
            "MIGRATION_NEEDED")
                add_issue "Legacy beads (bd) data detected - migration required"
                add_suggestion "Run migration: .claude/scripts/beads/migrate-to-br.sh"
                ;;
        esac
    else
        # Fallback: basic check
        if ! command -v br &>/dev/null; then
            add_warning "beads_rust (br) not installed"
        elif [[ -d "$BEADS_DIR" ]] && [[ -f "$BEADS_DIR/config.yaml" ]]; then
            add_issue "Legacy bd config detected in .beads/"
            add_suggestion "Run migration: .claude/scripts/beads/migrate-to-br.sh"
        fi
    fi
}

#######################################
# Check 2: Deprecated references in settings
#######################################
check_deprecated_references() {
    print_info "Checking local settings for deprecated references..."

    if [[ ! -f "$SETTINGS_LOCAL" ]]; then
        print_info "No settings.local.json found (using defaults)"
        return
    fi

    # Check for 'bd' references (should be 'br')
    if grep -q '"Bash(bd ' "$SETTINGS_LOCAL" 2>/dev/null; then
        local bd_count
        bd_count=$(grep -c '"Bash(bd ' "$SETTINGS_LOCAL" 2>/dev/null || echo 0)
        add_issue "Found $bd_count deprecated 'bd' permission(s) in settings.local.json"
        add_suggestion "Replace 'Bash(bd ' with 'Bash(br ' in $SETTINGS_LOCAL"

        if [[ "$FIX_MODE" == "true" ]]; then
            # Create backup
            cp "$SETTINGS_LOCAL" "${SETTINGS_LOCAL}.bak"
            # Replace bd with br
            sed 's/"Bash(bd /"Bash(br /g' "$SETTINGS_LOCAL" > "${SETTINGS_LOCAL}.tmp" && mv "${SETTINGS_LOCAL}.tmp" "$SETTINGS_LOCAL"
            add_fix "Replaced 'bd' with 'br' in settings.local.json (backup: ${SETTINGS_LOCAL}.bak)"
        fi
    else
        print_success "No deprecated 'bd' references found"
    fi

    # Check for old daemon-related permissions
    if grep -q 'bd daemon\|bd.sock' "$SETTINGS_LOCAL" 2>/dev/null; then
        add_warning "Found old bd daemon references - bd daemon is deprecated"
        add_suggestion "Remove bd daemon permissions from settings.local.json"
    fi
}

#######################################
# Check 3: New config options
#######################################
check_new_config_options() {
    print_info "Checking for new configuration options..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        add_warning "No .loa.config.yaml found"
        add_suggestion "Run /setup to create configuration"
        return
    fi

    # Check if yq is available
    if ! command -v yq &>/dev/null; then
        print_info "yq not available - skipping config analysis"
        return
    fi

    # Check for missing top-level sections (v1.3.0+ features)
    local missing_sections=()

    # recursive_jit (v0.20.0 / v1.3.0)
    if ! yq -e '.recursive_jit' "$CONFIG_FILE" &>/dev/null; then
        missing_sections+=("recursive_jit")
    fi

    # recursive_jit.continuous_synthesis (v1.3.1)
    if ! yq -e '.recursive_jit.continuous_synthesis' "$CONFIG_FILE" &>/dev/null; then
        if yq -e '.recursive_jit' "$CONFIG_FILE" &>/dev/null; then
            missing_sections+=("recursive_jit.continuous_synthesis")
        fi
    fi

    # continuous_learning (v0.17.0)
    if ! yq -e '.continuous_learning' "$CONFIG_FILE" &>/dev/null; then
        missing_sections+=("continuous_learning")
    fi

    # run_mode (v0.18.0)
    if ! yq -e '.run_mode' "$CONFIG_FILE" &>/dev/null; then
        missing_sections+=("run_mode")
    fi

    if [[ ${#missing_sections[@]} -gt 0 ]]; then
        add_warning "New config sections available: ${missing_sections[*]}"
        add_suggestion "Update .loa.config.yaml with new sections or re-run /setup"
    else
        print_success "Configuration includes all current sections"
    fi
}

#######################################
# Check 4: Recommended permissions
#######################################
check_recommended_permissions() {
    print_info "Checking recommended permissions for new features..."

    if [[ ! -f "$SETTINGS_LOCAL" ]]; then
        return
    fi

    local recommended=()

    # br sync (for beads_rust)
    if command -v br &>/dev/null; then
        if ! grep -q '"Bash(br sync' "$SETTINGS_LOCAL" 2>/dev/null; then
            recommended+=('Bash(br sync:*)')
        fi
        if ! grep -q '"Bash(br init' "$SETTINGS_LOCAL" 2>/dev/null; then
            recommended+=('Bash(br init:*)')
        fi
        if ! grep -q '"Bash(br list' "$SETTINGS_LOCAL" 2>/dev/null; then
            recommended+=('Bash(br list:*)')
        fi
    fi

    # synthesize-to-ledger.sh (for continuous synthesis)
    if [[ -x "${SCRIPT_DIR}/synthesize-to-ledger.sh" ]]; then
        if ! grep -q 'synthesize-to-ledger' "$SETTINGS_LOCAL" 2>/dev/null; then
            recommended+=('Bash(.claude/scripts/synthesize-to-ledger.sh:*)')
        fi
    fi

    # cache-manager.sh (for semantic cache)
    if [[ -x "${SCRIPT_DIR}/cache-manager.sh" ]]; then
        if ! grep -q 'cache-manager' "$SETTINGS_LOCAL" 2>/dev/null; then
            recommended+=('Bash(.claude/scripts/cache-manager.sh:*)')
        fi
    fi

    # condense.sh (for condensation)
    if [[ -x "${SCRIPT_DIR}/condense.sh" ]]; then
        if ! grep -q 'condense.sh' "$SETTINGS_LOCAL" 2>/dev/null; then
            recommended+=('Bash(.claude/scripts/condense.sh:*)')
        fi
    fi

    # early-exit.sh (for parallel subagent coordination)
    if [[ -x "${SCRIPT_DIR}/early-exit.sh" ]]; then
        if ! grep -q 'early-exit' "$SETTINGS_LOCAL" 2>/dev/null; then
            recommended+=('Bash(.claude/scripts/early-exit.sh:*)')
        fi
    fi

    if [[ ${#recommended[@]} -gt 0 ]]; then
        add_suggestion "Consider adding these permissions to settings.local.json for smoother operation:"
        for perm in "${recommended[@]}"; do
            add_suggestion "  - \"$perm\""
        done
    else
        print_success "All recommended permissions present"
    fi
}

#######################################
# Output results
#######################################
output_results() {
    if [[ "$JSON_MODE" == "true" ]]; then
        # JSON output
        local issues_json="[]"
        local warnings_json="[]"
        local suggestions_json="[]"
        local fixes_json="[]"

        if [[ ${#ISSUES[@]} -gt 0 ]]; then
            issues_json=$(printf '%s\n' "${ISSUES[@]}" | jq -R . | jq -s .)
        fi
        if [[ ${#WARNINGS[@]} -gt 0 ]]; then
            warnings_json=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .)
        fi
        if [[ ${#SUGGESTIONS[@]} -gt 0 ]]; then
            suggestions_json=$(printf '%s\n' "${SUGGESTIONS[@]}" | jq -R . | jq -s .)
        fi
        if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
            fixes_json=$(printf '%s\n' "${FIXES_APPLIED[@]}" | jq -R . | jq -s .)
        fi

        local status="healthy"
        local exit_code=0
        if [[ ${#ISSUES[@]} -gt 0 ]]; then
            status="critical"
            exit_code=2
        elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
            status="warnings"
            exit_code=1
        fi

        jq -n \
            --arg status "$status" \
            --argjson issues "$issues_json" \
            --argjson warnings "$warnings_json" \
            --argjson suggestions "$suggestions_json" \
            --argjson fixes "$fixes_json" \
            '{
                status: $status,
                issues: $issues,
                warnings: $warnings,
                suggestions: $suggestions,
                fixes_applied: $fixes
            }'

        return $exit_code
    fi

    # Human-readable output
    echo ""

    if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
        echo -e "${CYAN}═══ Fixes Applied ═══${NC}"
        for fix in "${FIXES_APPLIED[@]}"; do
            print_fix "$fix"
        done
        echo ""
    fi

    if [[ ${#ISSUES[@]} -gt 0 ]]; then
        echo -e "${RED}═══ Issues (Action Required) ═══${NC}"
        for issue in "${ISSUES[@]}"; do
            print_error "$issue"
        done
        echo ""
    fi

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}═══ Warnings ═══${NC}"
        for warning in "${WARNINGS[@]}"; do
            print_warning "$warning"
        done
        echo ""
    fi

    if [[ ${#SUGGESTIONS[@]} -gt 0 ]]; then
        echo -e "${BLUE}═══ Suggestions ═══${NC}"
        for suggestion in "${SUGGESTIONS[@]}"; do
            echo -e "  ${suggestion}"
        done
        echo ""
    fi

    # Summary
    if [[ ${#ISSUES[@]} -eq 0 ]] && [[ ${#WARNINGS[@]} -eq 0 ]]; then
        echo -e "${GREEN}═══ Health Check Passed ═══${NC}"
        echo "Your Loa installation is up to date and healthy."
        return 0
    elif [[ ${#ISSUES[@]} -gt 0 ]]; then
        echo -e "${RED}═══ Health Check: Issues Found ═══${NC}"
        echo "Please address the issues above before continuing."
        echo "Run with --fix to auto-fix where possible."
        return 2
    else
        echo -e "${YELLOW}═══ Health Check: Warnings ═══${NC}"
        echo "No critical issues, but consider the suggestions above."
        return 1
    fi
}

#######################################
# Main entry point
#######################################
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fix)
                FIX_MODE=true
                shift
                ;;
            --json)
                JSON_MODE=true
                shift
                ;;
            --quiet)
                QUIET_MODE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    [[ "$JSON_MODE" != "true" ]] && echo -e "${CYAN}═══ Loa Upgrade Health Check ═══${NC}"
    [[ "$JSON_MODE" != "true" ]] && echo ""

    # Run all checks
    check_beads_migration
    check_deprecated_references
    check_new_config_options
    check_recommended_permissions

    # Output results
    output_results
}

main "$@"
