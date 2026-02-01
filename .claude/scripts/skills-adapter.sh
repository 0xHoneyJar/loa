#!/usr/bin/env bash
# skills-adapter.sh
# Purpose: Transform Loa skills to Claude Agent Skills format at runtime
# Usage: ./skills-adapter.sh <command> [args]
#
# Part of Loa v0.11.0 Claude Platform Integration
#
# Commands:
#   generate <skill>    - Generate Claude Agent Skills format for a skill
#   list               - List all skills with compatibility status
#   upload <skill>     - Upload skill to Claude API workspace (stub)
#   sync               - Sync all skills with Claude API (stub)
#
# The adapter transforms Loa's index.yaml + SKILL.md format into
# Claude Agent Skills format with YAML frontmatter at runtime,
# without requiring migration of existing skills.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${SCRIPT_DIR}/../skills"
CONFIG_FILE="${SCRIPT_DIR}/../../.loa.config.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for required dependencies
check_dependencies() {
    local missing=()

    if ! command -v yq &> /dev/null; then
        missing+=("yq")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}ERROR: Missing required dependencies: ${missing[*]}${NC}" >&2
        echo "" >&2
        echo "Install missing dependencies:" >&2
        for dep in "${missing[@]}"; do
            case "$dep" in
                yq)
                    echo "  yq:  brew install yq / apt install yq" >&2
                    ;;
                jq)
                    echo "  jq:  brew install jq / apt install jq" >&2
                    ;;
            esac
        done
        exit 1
    fi
}

# Read configuration value with default
get_config() {
    local key="$1"
    local default="${2:-}"

    if [ -f "$CONFIG_FILE" ]; then
        local value
        value=$(yq -r "$key // \"$default\"" "$CONFIG_FILE" 2>/dev/null)
        if [ "$value" = "null" ] || [ -z "$value" ]; then
            echo "$default"
        else
            echo "$value"
        fi
    else
        echo "$default"
    fi
}

# Check if agent_skills is enabled
is_enabled() {
    local enabled
    enabled=$(get_config '.agent_skills.enabled' 'true')
    [ "$enabled" = "true" ]
}

# Validate skill exists and has required files
validate_skill() {
    local skill_name="$1"
    local skill_dir="${SKILLS_DIR}/${skill_name}"

    if [ ! -d "$skill_dir" ]; then
        echo -e "${RED}ERROR: Skill '$skill_name' not found at $skill_dir${NC}" >&2
        return 1
    fi

    if [ ! -f "${skill_dir}/index.yaml" ]; then
        echo -e "${RED}ERROR: Missing index.yaml for skill '$skill_name'${NC}" >&2
        return 1
    fi

    if [ ! -f "${skill_dir}/SKILL.md" ]; then
        echo -e "${RED}ERROR: Missing SKILL.md for skill '$skill_name'${NC}" >&2
        return 1
    fi

    return 0
}

# Check if skill has required fields for Agent Skills format
check_compatibility() {
    local skill_name="$1"
    local index_yaml="${SKILLS_DIR}/${skill_name}/index.yaml"

    local name description triggers
    name=$(yq -r '.name // ""' "$index_yaml")
    description=$(yq -r '.description // ""' "$index_yaml")
    triggers=$(yq -r '.triggers // [] | length' "$index_yaml")

    if [ -z "$name" ]; then
        echo "missing_name"
        return 1
    fi

    if [ -z "$description" ]; then
        echo "missing_description"
        return 1
    fi

    if [ "$triggers" -eq 0 ]; then
        echo "missing_triggers"
        return 1
    fi

    echo "compatible"
    return 0
}

# Generate Claude Agent Skills frontmatter from index.yaml
generate_frontmatter() {
    local skill_name="$1"
    local skill_dir="${SKILLS_DIR}/${skill_name}"
    local index_yaml="${skill_dir}/index.yaml"
    local skill_md="${skill_dir}/SKILL.md"

    # Validate skill exists
    if ! validate_skill "$skill_name"; then
        return 1
    fi

    # Extract fields from index.yaml
    local name version description triggers
    name=$(yq -r '.name' "$index_yaml")
    version=$(yq -r '.version // "1.0.0"' "$index_yaml")
    # Get first line of description for single-line format
    description=$(yq -r '.description' "$index_yaml" | head -1 | sed 's/^[[:space:]]*//')

    # Generate YAML frontmatter
    echo "---"
    echo "name: \"${name}\""
    echo "description: \"${description}\""
    echo "version: \"${version}\""

    # Generate triggers array
    echo "triggers:"
    yq -r '.triggers[]' "$index_yaml" 2>/dev/null | while read -r trigger; do
        echo "  - \"${trigger}\""
    done

    echo "---"
    echo ""

    # Append SKILL.md content, stripping any existing YAML frontmatter
    # SKILL.md files may have their own frontmatter (parallel_threshold, etc.)
    # We strip it to avoid double frontmatter in output
    if head -1 "$skill_md" | grep -q '^---$'; then
        # Has frontmatter - skip lines until second ---
        awk 'BEGIN{in_fm=0; count=0}
             /^---$/{count++; if(count==2){in_fm=0; next} else {in_fm=1; next}}
             !in_fm{print}' "$skill_md"
    else
        # No frontmatter - output as-is
        cat "$skill_md"
    fi
}

# List all skills with status
list_skills() {
    local json_output="${1:-false}"
    local skills=()

    # Find all skill directories
    for skill_dir in "${SKILLS_DIR}"/*/; do
        if [ -d "$skill_dir" ]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            skills+=("$skill_name")
        fi
    done

    if [ "$json_output" = "true" ]; then
        # JSON output
        echo "["
        local first=true
        for skill_name in "${skills[@]}"; do
            local index_yaml="${SKILLS_DIR}/${skill_name}/index.yaml"

            if [ ! -f "$index_yaml" ]; then
                continue
            fi

            local name version status
            name=$(yq -r '.name // ""' "$index_yaml")
            version=$(yq -r '.version // "1.0.0"' "$index_yaml")
            status=$(check_compatibility "$skill_name" 2>/dev/null || echo "error")

            if [ "$first" = "true" ]; then
                first=false
            else
                echo ","
            fi

            echo -n "  {\"name\": \"${name}\", \"version\": \"${version}\", \"status\": \"${status}\"}"
        done
        echo ""
        echo "]"
    else
        # Table output
        echo -e "${BLUE}Loa Skills - Claude Agent Skills Compatibility${NC}"
        echo ""
        printf "%-30s %-10s %-15s\n" "SKILL" "VERSION" "STATUS"
        printf "%-30s %-10s %-15s\n" "-----" "-------" "------"

        for skill_name in "${skills[@]}"; do
            local index_yaml="${SKILLS_DIR}/${skill_name}/index.yaml"

            if [ ! -f "$index_yaml" ]; then
                printf "%-30s %-10s ${YELLOW}%-15s${NC}\n" "$skill_name" "-" "no index.yaml"
                continue
            fi

            local name version status status_color
            name=$(yq -r '.name // ""' "$index_yaml")
            version=$(yq -r '.version // "1.0.0"' "$index_yaml")
            status=$(check_compatibility "$skill_name" 2>/dev/null || echo "error")

            case "$status" in
                compatible)
                    status_color="${GREEN}"
                    ;;
                missing_*)
                    status_color="${YELLOW}"
                    ;;
                *)
                    status_color="${RED}"
                    ;;
            esac

            printf "%-30s %-10s ${status_color}%-15s${NC}\n" "$name" "$version" "$status"
        done

        echo ""
        echo -e "Total: ${#skills[@]} skills"
    fi
}

# Upload skill to Claude API (stub)
upload_skill() {
    local skill_name="$1"

    # Validate skill exists
    if ! validate_skill "$skill_name"; then
        return 1
    fi

    # Check for API key
    local api_key="${CLAUDE_API_KEY:-}"
    if [ -z "$api_key" ]; then
        echo -e "${YELLOW}WARNING: CLAUDE_API_KEY not set${NC}" >&2
        echo "" >&2
        echo "To upload skills to Claude API workspace, set your API key:" >&2
        echo "  export CLAUDE_API_KEY='your-api-key'" >&2
        echo "" >&2
    fi

    # Check compatibility
    local status
    status=$(check_compatibility "$skill_name")
    if [ "$status" != "compatible" ]; then
        echo -e "${RED}ERROR: Skill '$skill_name' is not compatible: $status${NC}" >&2
        return 1
    fi

    # Generate frontmatter to verify it works
    echo -e "${BLUE}Validating skill '$skill_name'...${NC}"
    if generate_frontmatter "$skill_name" > /dev/null 2>&1; then
        echo -e "${GREEN}Validation successful${NC}"
    else
        echo -e "${RED}Validation failed${NC}" >&2
        return 1
    fi

    echo ""
    echo -e "${YELLOW}API upload ready for future implementation${NC}"
    echo "Skill '$skill_name' is ready to be uploaded when Claude Skills API is available."

    return 0
}

# Sync all skills with Claude API (stub)
sync_skills() {
    echo -e "${BLUE}Checking skills for sync...${NC}"
    echo ""

    local compatible_count=0
    local total_count=0

    for skill_dir in "${SKILLS_DIR}"/*/; do
        if [ -d "$skill_dir" ]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            total_count=$((total_count + 1))

            if [ -f "${skill_dir}/index.yaml" ]; then
                local status
                status=$(check_compatibility "$skill_name" 2>/dev/null || echo "error")
                if [ "$status" = "compatible" ]; then
                    compatible_count=$((compatible_count + 1))
                    echo -e "  ${GREEN}✓${NC} $skill_name"
                else
                    echo -e "  ${YELLOW}!${NC} $skill_name ($status)"
                fi
            else
                echo -e "  ${RED}✗${NC} $skill_name (no index.yaml)"
            fi
        fi
    done

    echo ""
    echo -e "Ready for sync: ${GREEN}${compatible_count}${NC}/${total_count} skills"
    echo ""
    echo -e "${YELLOW}API sync ready for future implementation${NC}"
    echo "All compatible skills are ready to sync when Claude Skills API is available."

    return 0
}

# Show help
show_help() {
    cat <<EOF
Loa Skills Adapter - Claude Agent Skills Format Generator

USAGE:
    $(basename "$0") <command> [arguments]

COMMANDS:
    generate <skill>    Generate Claude Agent Skills format for a skill
                        Outputs YAML frontmatter + SKILL.md content

    list [--json]       List all skills with compatibility status
                        Use --json for machine-readable output

    upload <skill>      Upload skill to Claude API workspace
                        Requires CLAUDE_API_KEY environment variable
                        (Currently a stub - API not yet available)

    sync                Sync all compatible skills with Claude API
                        (Currently a stub - API not yet available)

    help, --help, -h    Show this help message

CONFIGURATION:
    Configuration is read from .loa.config.yaml:

    agent_skills:
      enabled: true           # Enable/disable skills adapter
      load_mode: "dynamic"    # "dynamic" (on-demand) or "eager" (startup)
      api_upload: false       # Enable API upload features

EXAMPLES:
    # Generate frontmatter for a skill
    $(basename "$0") generate discovering-requirements

    # List all skills with status
    $(basename "$0") list

    # List skills as JSON
    $(basename "$0") list --json

    # Validate and prepare skill for upload
    $(basename "$0") upload implementing-tasks

ENVIRONMENT:
    CLAUDE_API_KEY    API key for Claude Skills API (required for upload)

For more information, see:
    https://docs.anthropic.com/en/agents-and-tools/agent-skills/overview
EOF
}

# Main command handler
main() {
    # Check if enabled
    if ! is_enabled; then
        echo -e "${YELLOW}Agent Skills adapter is disabled in configuration${NC}" >&2
        echo "Enable with: agent_skills.enabled: true in .loa.config.yaml" >&2
        exit 0
    fi

    # Check dependencies
    check_dependencies

    case "${1:-}" in
        generate)
            if [ -z "${2:-}" ]; then
                echo "Usage: $(basename "$0") generate <skill-name>" >&2
                exit 1
            fi
            generate_frontmatter "$2"
            ;;

        list)
            local json_flag="false"
            if [ "${2:-}" = "--json" ]; then
                json_flag="true"
            fi
            list_skills "$json_flag"
            ;;

        upload)
            if [ -z "${2:-}" ]; then
                echo "Usage: $(basename "$0") upload <skill-name>" >&2
                exit 1
            fi
            upload_skill "$2"
            ;;

        sync)
            sync_skills
            ;;

        help|--help|-h)
            show_help
            ;;

        "")
            show_help
            exit 1
            ;;

        *)
            echo -e "${RED}ERROR: Unknown command '$1'${NC}" >&2
            echo "" >&2
            echo "Run '$(basename "$0") --help' for usage information." >&2
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
