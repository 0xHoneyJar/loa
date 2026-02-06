#!/usr/bin/env bash
# .claude/scripts/mermaid-url.sh
#
# Visual Communication v2.0 - Multi-mode Mermaid rendering
#
# Modes:
#   --github (default)  Output GitHub-native Mermaid code block
#   --render            Generate local SVG/PNG via beautiful-mermaid
#   --url               Generate preview URL (legacy mode)
#
# Usage:
#   mermaid-url.sh <mermaid-file> [--github|--render|--url] [options]
#   echo "graph TD; A-->B" | mermaid-url.sh --stdin [--github|--render|--url] [options]
#
# Options:
#   --theme <name>      Theme name (default: github)
#   --stdin             Read Mermaid from stdin
#   --format <type>     Output format for --render: svg (default) or png
#   --output-dir <dir>  Output directory for --render (default: grimoires/loa/diagrams/)
#   --check             Check current configuration
#   --validate          Validate Mermaid syntax only
#   --help              Show this help
#
# Examples:
#   # GitHub native (default) - outputs ```mermaid code block
#   echo 'graph TD; A-->B' | mermaid-url.sh --stdin
#
#   # Local SVG render
#   echo 'graph TD; A-->B' | mermaid-url.sh --stdin --render
#
#   # Local PNG render
#   echo 'graph TD; A-->B' | mermaid-url.sh --stdin --render --format png
#
#   # Legacy URL mode
#   echo 'graph TD; A-->B' | mermaid-url.sh --stdin --url

set -euo pipefail

# Configuration
readonly DEFAULT_THEME="github"
readonly DEFAULT_SERVICE_URL="https://agents.craft.do/mermaid"
readonly DEFAULT_MODE="github"
readonly DEFAULT_OUTPUT_FORMAT="svg"
readonly DEFAULT_OUTPUT_DIR="grimoires/loa/diagrams"
readonly MAX_DIAGRAM_CHARS=1500

# Valid themes (allowlist for security)
readonly VALID_THEMES="github dracula nord tokyo-night solarized-light solarized-dark catppuccin"

# Valid output formats
readonly VALID_FORMATS="svg png"

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

# Validate output format
validate_format() {
    local format="$1"
    local valid_format
    for valid_format in $VALID_FORMATS; do
        if [[ "$format" == "$valid_format" ]]; then
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
            ".visual_communication.mode")
                raw_value=$(grep -A10 "^visual_communication:" "$config" 2>/dev/null | \
                           grep "^  mode:" | \
                           sed 's/.*mode: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/' | \
                           head -1) || true
                ;;
            ".visual_communication.local_render.output_format")
                raw_value=$(grep -A20 "^visual_communication:" "$config" 2>/dev/null | \
                           grep -A5 "local_render:" | \
                           grep "output_format:" | \
                           sed 's/.*output_format: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/' | \
                           head -1) || true
                ;;
            ".visual_communication.local_render.output_dir")
                raw_value=$(grep -A20 "^visual_communication:" "$config" 2>/dev/null | \
                           grep -A5 "local_render:" | \
                           grep "output_dir:" | \
                           sed 's/.*output_dir: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/' | \
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

# Read mode from config (v2.0)
read_config_mode() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    local mode
    mode=$(read_yaml_value "$config" ".visual_communication.mode" "$DEFAULT_MODE")

    # Validate mode
    case "$mode" in
        github|render|url)
            printf '%s' "$mode"
            ;;
        *)
            printf '%s' "$DEFAULT_MODE"
            ;;
    esac
}

# Read local render config
read_local_render_config() {
    local project_root
    project_root=$(find_project_root)
    local config="$project_root/.loa.config.yaml"

    local format
    format=$(read_yaml_value "$config" ".visual_communication.local_render.output_format" "$DEFAULT_OUTPUT_FORMAT")

    local output_dir
    output_dir=$(read_yaml_value "$config" ".visual_communication.local_render.output_dir" "$DEFAULT_OUTPUT_DIR")

    # Validate format
    if ! validate_format "$format"; then
        format="$DEFAULT_OUTPUT_FORMAT"
    fi

    printf '%s|%s' "$format" "$output_dir"
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

# Check if preview URLs should be included (legacy check)
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

# Output GitHub native Mermaid code block (v2.0 default)
output_github_native() {
    local mermaid="$1"
    printf '```mermaid\n%s\n```\n' "$mermaid"
}

# Render locally using beautiful-mermaid (v2.0)
render_local() {
    local mermaid="$1"
    local format="${2:-$DEFAULT_OUTPUT_FORMAT}"
    local output_dir="${3:-$DEFAULT_OUTPUT_DIR}"
    local theme="${4:-$DEFAULT_THEME}"

    # Check for npx
    if ! command -v npx &>/dev/null; then
        echo "Error: npx not found. Install Node.js 18+" >&2
        echo "  brew install node  # macOS" >&2
        echo "  apt install nodejs # Debian/Ubuntu" >&2
        return 1
    fi

    # Check for mermaid-cli (more reliable than beautiful-mermaid)
    # Try @mermaid-js/mermaid-cli first (official package)
    local renderer=""
    if npx @mermaid-js/mermaid-cli --version &>/dev/null 2>&1; then
        renderer="mermaid-cli"
    elif npx mmdc --version &>/dev/null 2>&1; then
        renderer="mmdc"
    else
        echo "Error: Mermaid CLI not available" >&2
        echo "Install: npm install -g @mermaid-js/mermaid-cli" >&2
        echo "  or: npx @mermaid-js/mermaid-cli (auto-install on first use)" >&2
        return 1
    fi

    # Create output directory
    mkdir -p "$output_dir"

    # Generate hash for unique filename
    local hash
    hash=$(printf '%s' "$mermaid" | sha256sum | cut -c1-8)
    local outfile="${output_dir}/diagram-${hash}.${format}"

    # Create temp file for input
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/loa-mermaid.XXXXXX")
    mv "$tmpfile" "${tmpfile}.mmd"
    tmpfile="${tmpfile}.mmd"
    printf '%s' "$mermaid" > "$tmpfile"

    # Render using mermaid-cli
    local render_result=0
    if [[ "$renderer" == "mermaid-cli" ]]; then
        npx @mermaid-js/mermaid-cli -i "$tmpfile" -o "$outfile" -t "$theme" 2>/dev/null || render_result=$?
    else
        npx mmdc -i "$tmpfile" -o "$outfile" -t "$theme" 2>/dev/null || render_result=$?
    fi

    # Cleanup
    rm -f "$tmpfile"

    if [[ $render_result -ne 0 ]]; then
        echo "Error: Rendering failed" >&2
        return 1
    fi

    # Output the path to rendered file
    printf '%s\n' "$outfile"
}

# Generate URL from Mermaid source (legacy mode)
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
        echo "Use --github mode or --render for local rendering instead." >&2
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

Visual Communication v2.0 - Multi-mode Mermaid rendering

Modes:
  --github (default)  Output GitHub-native Mermaid code block
  --render            Generate local SVG/PNG via mermaid-cli
  --url               Generate preview URL (legacy mode)

Options:
  --theme <name>      Theme name (default: from config or github)
  --stdin             Read Mermaid from stdin
  --format <type>     Output format for --render: svg (default) or png
  --output-dir <dir>  Output directory for --render
  --check             Check current configuration
  --validate          Validate Mermaid syntax only
  --help              Show this help

Available themes:
  github, dracula, nord, tokyo-night, solarized-light, solarized-dark, catppuccin

Environment Variables:
  LOA_MERMAID_SERVICE  Override service URL for --url mode

Examples:
  # GitHub native (default) - outputs \`\`\`mermaid code block
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin

  # Explicit GitHub mode
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin --github

  # Local SVG render
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin --render

  # Local PNG render with theme
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin --render --format png --theme dracula

  # Legacy URL mode (requires external service)
  echo 'graph TD; A-->B' | mermaid-url.sh --stdin --url

  # From file
  mermaid-url.sh diagram.mmd --render

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
    local validate_only=false
    local mode=""
    local format=""
    local output_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --github)
                mode="github"
                shift
                ;;
            --render)
                mode="render"
                shift
                ;;
            --url)
                mode="url"
                shift
                ;;
            --theme)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --theme requires an argument" >&2
                    exit 1
                fi
                theme="$2"
                shift 2
                ;;
            --format)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --format requires an argument" >&2
                    exit 1
                fi
                format="$2"
                shift 2
                ;;
            --output-dir)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --output-dir requires an argument" >&2
                    exit 1
                fi
                output_dir="$2"
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
        local config_mode
        config_mode=$(read_config_mode)
        local local_config
        local_config=$(read_local_render_config)
        local local_format="${local_config%%|*}"
        local local_dir="${local_config##*|}"

        if is_enabled; then
            echo "Visual communication: enabled"
            echo "Default mode: $config_mode"
            echo "Theme: $(read_config_theme)"
            echo "Local render format: $local_format"
            echo "Local render directory: $local_dir"
            echo "Service URL (legacy): $(read_service_url)"
            echo "Preview URLs: $(include_preview_urls && echo 'enabled' || echo 'disabled')"
            echo "Max diagram size (URL mode): $MAX_DIAGRAM_CHARS chars"
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

    # Validate syntax
    if ! validate_mermaid "$mermaid"; then
        exit 1
    fi

    # Validate only mode
    if [[ "$validate_only" == true ]]; then
        echo "Mermaid syntax: valid"
        echo "Diagram size: ${#mermaid} chars"
        if [[ ${#mermaid} -gt $MAX_DIAGRAM_CHARS ]]; then
            echo "Warning: Exceeds $MAX_DIAGRAM_CHARS char limit for URL mode"
        fi
        exit 0
    fi

    # Resolve mode (explicit flag > config > default)
    if [[ -z "$mode" ]]; then
        mode=$(read_config_mode)
    fi

    # Resolve theme
    if [[ -z "$theme" ]]; then
        theme=$(read_config_theme)
    else
        if ! validate_theme "$theme"; then
            echo "Error: Invalid theme '$theme'. Valid themes: $VALID_THEMES" >&2
            exit 1
        fi
    fi

    # Execute based on mode
    case "$mode" in
        github)
            output_github_native "$mermaid"
            ;;
        render)
            # Resolve format and output_dir from config if not specified
            if [[ -z "$format" ]] || [[ -z "$output_dir" ]]; then
                local local_config
                local_config=$(read_local_render_config)
                [[ -z "$format" ]] && format="${local_config%%|*}"
                [[ -z "$output_dir" ]] && output_dir="${local_config##*|}"
            fi

            # Validate format
            if ! validate_format "$format"; then
                echo "Error: Invalid format '$format'. Valid formats: $VALID_FORMATS" >&2
                exit 1
            fi

            render_local "$mermaid" "$format" "$output_dir" "$theme"
            ;;
        url)
            generate_url "$mermaid" "$theme"
            ;;
        *)
            echo "Error: Invalid mode '$mode'" >&2
            exit 1
            ;;
    esac
}

main "$@"
