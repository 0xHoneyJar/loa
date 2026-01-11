#!/usr/bin/env bash
# Schema Validator - Validate files against Loa JSON schemas
# Part of the Loa framework's Structured Outputs integration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_DIR="$(dirname "$SCRIPT_DIR")/schemas"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default validation mode
VALIDATION_MODE="warn"

#######################################
# Print usage information
#######################################
usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  validate <file>     Validate a file against its schema
  list                List available schemas

Options:
  --schema <name>     Override schema auto-detection (prd, sdd, sprint, trajectory)
  --mode <mode>       Validation mode: strict, warn, disabled (default: warn)
  --json              Output results as JSON
  --help              Show this help message

Auto-Detection:
  Files are matched to schemas based on path patterns:
    - grimoires/loa/prd.md           -> prd.schema.json
    - grimoires/loa/sdd.md           -> sdd.schema.json
    - grimoires/loa/sprint.md        -> sprint.schema.json
    - **/trajectory/*.jsonl         -> trajectory-entry.schema.json

Examples:
  $(basename "$0") validate grimoires/loa/prd.md
  $(basename "$0") validate output.json --schema prd
  $(basename "$0") validate file.md --mode strict
  $(basename "$0") list
EOF
}

#######################################
# Print colored output
#######################################
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

#######################################
# List available schemas
#######################################
list_schemas() {
    local json_output="${1:-false}"

    if [[ "$json_output" == "true" ]]; then
        echo "{"
        echo "  \"schemas\": ["
        local first=true
        for schema_file in "$SCHEMA_DIR"/*.schema.json; do
            if [[ -f "$schema_file" ]]; then
                local name
                name=$(basename "$schema_file" .schema.json)
                local title
                title=$(jq -r '.title // "Unknown"' "$schema_file" 2>/dev/null || echo "Unknown")

                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                printf '    {"name": "%s", "title": "%s", "path": "%s"}' "$name" "$title" "$schema_file"
            fi
        done
        echo ""
        echo "  ]"
        echo "}"
    else
        echo "Available Schemas:"
        echo ""
        printf "%-20s %-35s %s\n" "NAME" "TITLE" "PATH"
        printf "%-20s %-35s %s\n" "----" "-----" "----"

        for schema_file in "$SCHEMA_DIR"/*.schema.json; do
            if [[ -f "$schema_file" ]]; then
                local name
                name=$(basename "$schema_file" .schema.json)
                local title
                title=$(jq -r '.title // "Unknown"' "$schema_file" 2>/dev/null || echo "Unknown")
                printf "%-20s %-35s %s\n" "$name" "$title" "$schema_file"
            fi
        done
    fi
}

#######################################
# Auto-detect schema based on file path
#######################################
detect_schema() {
    local file_path="$1"
    local basename
    basename=$(basename "$file_path")

    # Check trajectory pattern first (most specific)
    if [[ "$file_path" == *"/trajectory/"* ]] && [[ "$basename" == *.jsonl ]]; then
        echo "trajectory-entry"
        return 0
    fi

    # Check grimoire patterns
    case "$basename" in
        prd.md|*-prd.md)
            echo "prd"
            return 0
            ;;
        sdd.md|*-sdd.md)
            echo "sdd"
            return 0
            ;;
        sprint.md|*-sprint.md)
            echo "sprint"
            return 0
            ;;
    esac

    # Check path patterns
    if [[ "$file_path" == *"grimoires/loa/prd"* ]]; then
        echo "prd"
        return 0
    elif [[ "$file_path" == *"grimoires/loa/sdd"* ]]; then
        echo "sdd"
        return 0
    elif [[ "$file_path" == *"grimoires/loa/sprint"* ]]; then
        echo "sprint"
        return 0
    fi

    # No match
    return 1
}

#######################################
# Get schema file path
#######################################
get_schema_path() {
    local schema_name="$1"
    local schema_path="$SCHEMA_DIR/${schema_name}.schema.json"

    if [[ -f "$schema_path" ]]; then
        echo "$schema_path"
        return 0
    fi

    return 1
}

#######################################
# Extract JSON/YAML frontmatter from markdown
#######################################
extract_frontmatter() {
    local file_path="$1"
    local content

    # Check if file starts with frontmatter
    if ! head -1 "$file_path" | grep -q '^---$'; then
        # Try to find JSON directly
        if head -1 "$file_path" | grep -q '^{'; then
            cat "$file_path"
            return 0
        fi
        return 1
    fi

    # Extract YAML frontmatter between --- delimiters
    content=$(awk '
        BEGIN { in_fm=0; started=0 }
        /^---$/ {
            if (!started) { started=1; in_fm=1; next }
            else if (in_fm) { in_fm=0; exit }
        }
        in_fm { print }
    ' "$file_path")

    if [[ -z "$content" ]]; then
        return 1
    fi

    # Convert YAML to JSON using yq if available, otherwise try python
    if command -v yq &>/dev/null; then
        echo "$content" | yq -o=json '.'
    elif command -v python3 &>/dev/null; then
        echo "$content" | python3 -c "
import sys, yaml, json
try:
    data = yaml.safe_load(sys.stdin.read())
    print(json.dumps(data))
except Exception as e:
    sys.exit(1)
"
    else
        print_error "No YAML parser available (need yq or python3 with PyYAML)"
        return 1
    fi
}

#######################################
# Validate JSON against schema using jq (basic)
# This is a fallback when ajv-cli is not available
#######################################
validate_with_jq() {
    local json_data="$1"
    local schema_path="$2"
    local errors=()

    # Get required fields from schema
    local required_fields
    required_fields=$(jq -r '.required // [] | .[]' "$schema_path" 2>/dev/null)

    # Check required fields
    for field in $required_fields; do
        if ! echo "$json_data" | jq -e "has(\"$field\")" &>/dev/null; then
            errors+=("Missing required field: $field")
        fi
    done

    # Check version pattern if present
    local version_pattern
    version_pattern=$(jq -r '.properties.version.pattern // empty' "$schema_path" 2>/dev/null)
    if [[ -n "$version_pattern" ]]; then
        local version_value
        version_value=$(echo "$json_data" | jq -r '.version // empty' 2>/dev/null)
        if [[ -n "$version_value" ]]; then
            # Simple semver check
            if ! [[ "$version_value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                errors+=("Invalid version format: $version_value (expected semver)")
            fi
        fi
    fi

    # Check status enum if present
    local status_enum
    status_enum=$(jq -r '.properties.status.enum // empty | @json' "$schema_path" 2>/dev/null)
    if [[ -n "$status_enum" && "$status_enum" != "null" ]]; then
        local status_value
        status_value=$(echo "$json_data" | jq -r '.status // empty' 2>/dev/null)
        if [[ -n "$status_value" ]]; then
            if ! echo "$status_enum" | jq -e "index(\"$status_value\")" &>/dev/null; then
                errors+=("Invalid status value: $status_value")
            fi
        fi
    fi

    # Return results
    if [[ ${#errors[@]} -eq 0 ]]; then
        return 0
    else
        printf '%s\n' "${errors[@]}"
        return 1
    fi
}

#######################################
# Validate JSON against schema using ajv-cli
#######################################
validate_with_ajv() {
    local json_file="$1"
    local schema_path="$2"

    ajv validate -s "$schema_path" -d "$json_file" --spec=draft7 2>&1
}

#######################################
# Main validation function
#######################################
validate_file() {
    local file_path="$1"
    local schema_override="${2:-}"
    local mode="${3:-warn}"
    local json_output="${4:-false}"

    # Check if validation is disabled
    if [[ "$mode" == "disabled" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"status": "skipped", "message": "Validation disabled"}'
        else
            print_info "Validation disabled, skipping"
        fi
        return 0
    fi

    # Check file exists
    if [[ ! -f "$file_path" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"status": "error", "message": "File not found"}'
        else
            print_error "File not found: $file_path"
        fi
        return 1
    fi

    # Determine schema
    local schema_name
    if [[ -n "$schema_override" ]]; then
        schema_name="$schema_override"
    else
        if ! schema_name=$(detect_schema "$file_path"); then
            if [[ "$json_output" == "true" ]]; then
                echo '{"status": "error", "message": "Could not auto-detect schema"}'
            else
                print_error "Could not auto-detect schema for: $file_path"
                print_info "Use --schema <name> to specify manually"
            fi
            return 1
        fi
    fi

    # Get schema path
    local schema_path
    if ! schema_path=$(get_schema_path "$schema_name"); then
        if [[ "$json_output" == "true" ]]; then
            echo "{\"status\": \"error\", \"message\": \"Schema not found: $schema_name\"}"
        else
            print_error "Schema not found: $schema_name"
        fi
        return 1
    fi

    # Extract JSON data
    local json_data
    local temp_json
    temp_json=$(mktemp)
    trap "rm -f '$temp_json'" EXIT

    # Handle different file types
    case "$file_path" in
        *.json)
            cp "$file_path" "$temp_json"
            ;;
        *.jsonl)
            # Validate first line for trajectory entries
            head -1 "$file_path" > "$temp_json"
            ;;
        *.md)
            if ! extract_frontmatter "$file_path" > "$temp_json"; then
                if [[ "$json_output" == "true" ]]; then
                    echo '{"status": "error", "message": "Could not extract frontmatter"}'
                else
                    print_error "Could not extract JSON/YAML frontmatter from: $file_path"
                fi
                return 1
            fi
            ;;
        *)
            # Try direct JSON extraction
            if ! extract_frontmatter "$file_path" > "$temp_json"; then
                cp "$file_path" "$temp_json"
            fi
            ;;
    esac

    # Validate JSON syntax
    if ! jq empty "$temp_json" 2>/dev/null; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"status": "error", "message": "Invalid JSON"}'
        else
            print_error "Invalid JSON in: $file_path"
        fi
        return 1
    fi

    json_data=$(cat "$temp_json")

    # Perform validation
    local validation_result
    local validation_errors=""
    local validation_status=0

    if command -v ajv &>/dev/null; then
        # Use ajv-cli for full validation
        if ! validation_result=$(validate_with_ajv "$temp_json" "$schema_path" 2>&1); then
            validation_errors="$validation_result"
            validation_status=1
        fi
    else
        # Fall back to basic jq validation
        if ! validation_errors=$(validate_with_jq "$json_data" "$schema_path"); then
            validation_status=1
        fi
    fi

    # Output results
    if [[ "$json_output" == "true" ]]; then
        if [[ $validation_status -eq 0 ]]; then
            echo "{\"status\": \"valid\", \"schema\": \"$schema_name\", \"file\": \"$file_path\"}"
        else
            local escaped_errors
            escaped_errors=$(echo "$validation_errors" | jq -Rs '.')
            echo "{\"status\": \"invalid\", \"schema\": \"$schema_name\", \"file\": \"$file_path\", \"errors\": $escaped_errors}"
        fi
    else
        if [[ $validation_status -eq 0 ]]; then
            print_success "Valid: $file_path (schema: $schema_name)"
        else
            if [[ "$mode" == "strict" ]]; then
                print_error "Invalid: $file_path (schema: $schema_name)"
                echo "$validation_errors" | while read -r line; do
                    echo "  $line"
                done
                return 1
            else
                print_warning "Invalid: $file_path (schema: $schema_name)"
                echo "$validation_errors" | while read -r line; do
                    echo "  $line"
                done
            fi
        fi
    fi

    if [[ "$mode" == "strict" ]]; then
        return $validation_status
    fi
    return 0
}

#######################################
# Main entry point
#######################################
main() {
    local command=""
    local file_path=""
    local schema_override=""
    local mode="warn"
    local json_output="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            validate|list)
                command="$1"
                shift
                ;;
            --schema)
                schema_override="$2"
                shift 2
                ;;
            --mode)
                mode="$2"
                shift 2
                ;;
            --json)
                json_output="true"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                # First non-option argument could be a command or file_path
                if [[ -z "$command" && -z "$file_path" ]]; then
                    # Check if it looks like a command
                    case "$1" in
                        validate|list)
                            command="$1"
                            ;;
                        *)
                            # Unknown command if it doesn't look like a file path
                            if [[ ! -e "$1" && ! "$1" == *"/"* && ! "$1" == *"."* ]]; then
                                print_error "Unknown command: $1"
                                usage
                                exit 1
                            fi
                            file_path="$1"
                            ;;
                    esac
                elif [[ -z "$file_path" ]]; then
                    file_path="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate mode
    case "$mode" in
        strict|warn|disabled)
            ;;
        *)
            print_error "Invalid mode: $mode (must be strict, warn, or disabled)"
            exit 1
            ;;
    esac

    # Execute command
    case "$command" in
        validate)
            if [[ -z "$file_path" ]]; then
                print_error "No file specified"
                usage
                exit 1
            fi
            validate_file "$file_path" "$schema_override" "$mode" "$json_output"
            ;;
        list)
            list_schemas "$json_output"
            ;;
        "")
            print_error "No command specified"
            usage
            exit 1
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
