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
DEFAULT_THEME="github"
SERVICE_URL="https://agents.craft.do/mermaid"

# Find project root (look for .loa.config.yaml)
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.loa.config.yaml" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "$PWD"
}

# Read theme from config if available
read_config_theme() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    if [[ -f "$config" ]]; then
        # Extract theme from visual_communication section
        local theme
        theme=$(grep -A10 "^visual_communication:" "$config" 2>/dev/null | \
                grep "^  theme:" | \
                sed 's/.*theme: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/' | \
                head -1)
        if [[ -n "$theme" ]]; then
            echo "$theme"
            return 0
        fi
    fi
    echo "$DEFAULT_THEME"
}

# Check if visual communication is enabled
is_enabled() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    if [[ -f "$config" ]]; then
        local enabled
        enabled=$(grep -A10 "^visual_communication:" "$config" 2>/dev/null | \
                  grep "^  enabled:" | \
                  sed 's/.*enabled: *\(.*\)/\1/' | \
                  head -1)
        if [[ "$enabled" == "false" ]]; then
            return 1
        fi
    fi
    return 0
}

# Check if preview URLs should be included
include_preview_urls() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    if [[ -f "$config" ]]; then
        local include
        include=$(grep -A10 "^visual_communication:" "$config" 2>/dev/null | \
                  grep "^  include_preview_urls:" | \
                  sed 's/.*include_preview_urls: *\(.*\)/\1/' | \
                  head -1)
        if [[ "$include" == "false" ]]; then
            return 1
        fi
    fi
    return 0
}

# Generate URL from Mermaid source
generate_url() {
    local mermaid="$1"
    local theme="${2:-$(read_config_theme)}"

    # Check if preview URLs are enabled
    if ! include_preview_urls; then
        echo "Preview URLs disabled in config" >&2
        return 1
    fi

    # Check diagram size (warn if > 1500 chars)
    local char_count=${#mermaid}
    if [[ $char_count -gt 1500 ]]; then
        echo "Warning: Diagram is $char_count chars (>1500). URL may be too long for some browsers." >&2
    fi

    # Base64 encode (URL-safe: replace +/ with -_, strip =)
    local encoded
    encoded=$(echo -n "$mermaid" | base64 -w0 | tr '+/' '-_' | tr -d '=')

    echo "${SERVICE_URL}?code=${encoded}&theme=${theme}"
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
  --help           Show this help

Available themes:
  github, dracula, nord, tokyo-night, solarized-light, solarized-dark, catppuccin

Examples:
  # From file
  mermaid-url.sh diagram.mmd

  # From stdin
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin

  # With custom theme
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin --theme dracula

  # Check configuration
  mermaid-url.sh --check
EOF
}

# Main
main() {
    local theme=""
    local stdin=false
    local input=""
    local check=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --theme)
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
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1" >&2
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
            echo "Preview URLs: $(include_preview_urls && echo 'enabled' || echo 'disabled')"
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

    # Generate URL
    generate_url "$mermaid" "${theme:-}"
}

main "$@"
