#!/usr/bin/env bash
# .claude/scripts/mermaid-url.sh
#
# Generate Beautiful Mermaid preview URL from Mermaid source
#
# Usage:
#   mermaid-url.sh <mermaid-file> [--theme <theme>]
#   echo "graph TD; A-->B" | mermaid-url.sh --stdin [--theme <theme>]
#
# Options:
#   --theme <name>   Theme name (default: github)
#   --stdin          Read Mermaid from stdin
#   --help           Show this help
#
# Examples:
#   # From file
#   mermaid-url.sh diagram.mmd
#
#   # From stdin
#   echo 'graph TD; A-->B' | mermaid-url.sh --stdin
#
#   # With custom theme
#   echo 'graph TD; A-->B' | mermaid-url.sh --stdin --theme dracula

set -euo pipefail

# Configuration
readonly DEFAULT_THEME="github"
readonly DEFAULT_SERVICE_URL="https://agents.craft.do/mermaid"
readonly MAX_DIAGRAM_CHARS=1500

# Valid themes (allowlist for security)
readonly VALID_THEMES="github dracula nord tokyo-night solarized-light solarized-dark catppuccin"

# Find project root (look for .loa.config.yaml)
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.loa.config.yaml" ]]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    printf '%s' "$PWD"
}

# Validate theme against allowlist (CRITICAL-2 fix: injection prevention)
validate_theme() {
    local theme="$1"
    local valid_theme
    for valid_theme in $VALID_THEMES; do
        if [[ "$theme" == "$valid_theme" ]]; then
            return 0
        fi
    done
    return 1
}

# Safe YAML value extraction using yq if available, with fallback
# CRITICAL-2 fix: Use yq for safe YAML parsing
read_yaml_value() {
    local config="$1"
    local path="$2"
    local default="${3:-}"

    # Try yq first (safe YAML parsing)
    if command -v yq &>/dev/null; then
        local value
        value=$(yq eval "$path // \"\"" "$config" 2>/dev/null) || true
        if [[ -n "$value" && "$value" != "null" ]]; then
            printf '%s' "$value"
            return 0
        fi
    fi

    # Fallback: grep with strict validation (no shell metacharacters allowed)
    # Only allow alphanumeric, dash, underscore, dot, colon, slash
    if [[ -f "$config" ]]; then
        local raw_value
        # Extract the specific key we're looking for
        case "$path" in
            ".visual_communication.theme")
                raw_value=$(grep -A10 "^visual_communication:" "$config" 2>/dev/null | \
                           grep "^  theme:" | \
                           sed 's/.*theme: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/' | \
                           head -1) || true
                ;;
            ".visual_communication.enabled")
                raw_value=$(grep -A10 "^visual_communication:" "$config" 2>/dev/null | \
                           grep "^  enabled:" | \
                           sed 's/.*enabled: *\(.*\)/\1/' | \
                           head -1) || true
                ;;
            ".visual_communication.include_preview_urls")
                raw_value=$(grep -A10 "^visual_communication:" "$config" 2>/dev/null | \
                           grep "^  include_preview_urls:" | \
                           sed 's/.*include_preview_urls: *\(.*\)/\1/' | \
                           head -1) || true
                ;;
            ".visual_communication.service")
                raw_value=$(grep -A10 "^visual_communication:" "$config" 2>/dev/null | \
                           grep "^  service:" | \
                           sed 's/.*service: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/' | \
                           head -1) || true
                ;;
            *)
                raw_value=""
                ;;
        esac

        # Validate: only allow safe characters (alphanumeric, dash, underscore, dot, colon, slash)
        if [[ -n "$raw_value" && "$raw_value" =~ ^[a-zA-Z0-9_./:@-]+$ ]]; then
            printf '%s' "$raw_value"
            return 0
        fi
    fi

    printf '%s' "$default"
}

# Read theme from config if available
read_config_theme() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    local theme
    theme=$(read_yaml_value "$config" ".visual_communication.theme" "$DEFAULT_THEME")

    # Validate against allowlist
    if validate_theme "$theme"; then
        printf '%s' "$theme"
    else
        echo "Warning: Invalid theme '$theme' in config, using default" >&2
        printf '%s' "$DEFAULT_THEME"
    fi
}

# Read service URL from config (HIGH-3 fix: make configurable)
read_service_url() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    # Allow environment variable override
    if [[ -n "${LOA_MERMAID_SERVICE:-}" ]]; then
        printf '%s' "$LOA_MERMAID_SERVICE"
        return 0
    fi

    local service_url
    service_url=$(read_yaml_value "$config" ".visual_communication.service" "$DEFAULT_SERVICE_URL")

    # Basic URL validation
    if [[ "$service_url" =~ ^https?:// ]]; then
        printf '%s' "$service_url"
    else
        printf '%s' "$DEFAULT_SERVICE_URL"
    fi
}

# Check if visual communication is enabled
is_enabled() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    local enabled
    enabled=$(read_yaml_value "$config" ".visual_communication.enabled" "true")

    [[ "$enabled" != "false" ]]
}

# Check if preview URLs should be included
include_preview_urls() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    local include
    include=$(read_yaml_value "$config" ".visual_communication.include_preview_urls" "true")

    [[ "$include" != "false" ]]
}

# Validate Mermaid syntax (HIGH-4 fix: basic syntax validation)
validate_mermaid() {
    local mermaid="$1"

    # Check for diagram type declaration
    if ! echo "$mermaid" | grep -qE '^[[:space:]]*(graph|flowchart|sequenceDiagram|classDiagram|stateDiagram|stateDiagram-v2|erDiagram|journey|gantt|pie|quadrantChart|requirementDiagram|gitGraph|mindmap|timeline|zenuml|sankey|xychart|block)'; then
        echo "Error: Invalid Mermaid syntax - must start with a valid diagram type" >&2
        echo "Valid types: graph, flowchart, sequenceDiagram, classDiagram, stateDiagram, erDiagram, etc." >&2
        return 1
    fi

    return 0
}

# Generate URL from Mermaid source
generate_url() {
    local mermaid="$1"
    local theme="${2:-}"

    # Check if preview URLs are enabled
    if ! include_preview_urls; then
        echo "Error: Preview URLs disabled in config" >&2
        return 1
    fi

    # Get theme (with validation)
    if [[ -z "$theme" ]]; then
        theme=$(read_config_theme)
    else
        # Validate user-provided theme (CRITICAL-2 fix)
        if ! validate_theme "$theme"; then
            echo "Error: Invalid theme '$theme'. Valid themes: $VALID_THEMES" >&2
            return 1
        fi
    fi

    # Check diagram size (HIGH-1, HIGH-2 fix: abort for large diagrams per protocol)
    local char_count=${#mermaid}
    if [[ $char_count -gt $MAX_DIAGRAM_CHARS ]]; then
        echo "Error: Diagram is $char_count chars (exceeds $MAX_DIAGRAM_CHARS limit)" >&2
        echo "Note: Per protocol, diagrams >$MAX_DIAGRAM_CHARS chars should not have preview URLs." >&2
        echo "Render locally using VS Code Mermaid extension or GitHub markdown preview." >&2
        return 1
    fi

    # Validate Mermaid syntax (HIGH-4 fix)
    if ! validate_mermaid "$mermaid"; then
        return 1
    fi

    # Get service URL (HIGH-3 fix: configurable)
    local service_url
    service_url=$(read_service_url)

    # Base64 encode (URL-safe: replace +/ with -_, strip =)
    local encoded
    encoded=$(printf '%s' "$mermaid" | base64 -w0 | tr '+/' '-_' | tr -d '=')

    # Output URL (CRITICAL-1 fix: use printf for safe output)
    printf '%s?code=%s&theme=%s\n' "$service_url" "$encoded" "$theme"
}

# Show usage
usage() {
    cat <<EOF
Usage: mermaid-url.sh [OPTIONS] [FILE]

Generate Beautiful Mermaid preview URL from Mermaid source.

Options:
  --theme <name>   Theme name (default: from config or github)
  --stdin          Read Mermaid from stdin
  --check          Check if visual communication is enabled
  --validate       Validate Mermaid syntax without generating URL
  --help           Show this help

Available themes (default: github):
  github, dracula, nord, tokyo-night, solarized-light, solarized-dark, catppuccin

Environment Variables:
  LOA_MERMAID_SERVICE  Override service URL (default: https://agents.craft.do/mermaid)

Limits:
  Maximum diagram size: $MAX_DIAGRAM_CHARS characters
  Diagrams exceeding this limit will not generate preview URLs per protocol.

Examples:
  # From file
  mermaid-url.sh diagram.mmd

  # From stdin
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin

  # With custom theme
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin --theme dracula

  # Check configuration
  mermaid-url.sh --check

  # Validate syntax only
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin --validate
EOF
}

# Main
main() {
    local theme=""
    local stdin=false
    local input=""
    local check=false
    local validate_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --theme)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --theme requires an argument" >&2
                    exit 1
                fi
                theme="$2"
                shift 2
                ;;
            --stdin)
                stdin=true
                shift
                ;;
            --check)
                check=true
                shift
                ;;
            --validate)
                validate_only=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                input="$1"
                shift
                ;;
        esac
    done

    # Check mode
    if [[ "$check" == true ]]; then
        if is_enabled; then
            echo "Visual communication: enabled"
            echo "Theme: $(read_config_theme)"
            echo "Service URL: $(read_service_url)"
            echo "Preview URLs: $(include_preview_urls && echo 'enabled' || echo 'disabled')"
            echo "Max diagram size: $MAX_DIAGRAM_CHARS chars"
            exit 0
        else
            echo "Visual communication: disabled"
            exit 1
        fi
    fi

    # Get Mermaid source
    local mermaid
    if [[ "$stdin" == true ]]; then
        mermaid=$(cat)
    elif [[ -n "$input" ]] && [[ -f "$input" ]]; then
        mermaid=$(cat "$input")
    else
        echo "Error: Provide Mermaid file or use --stdin" >&2
        usage >&2
        exit 1
    fi

    # Validate we have content
    if [[ -z "$mermaid" ]]; then
        echo "Error: Empty Mermaid source" >&2
        exit 1
    fi

    # Validate only mode
    if [[ "$validate_only" == true ]]; then
        if validate_mermaid "$mermaid"; then
            echo "Mermaid syntax: valid"
            echo "Diagram size: ${#mermaid} chars"
            if [[ ${#mermaid} -gt $MAX_DIAGRAM_CHARS ]]; then
                echo "Warning: Exceeds $MAX_DIAGRAM_CHARS char limit for preview URLs"
            fi
            exit 0
        else
            exit 1
        fi
    fi

    # Generate URL
    generate_url "$mermaid" "$theme"
}

main "$@"
