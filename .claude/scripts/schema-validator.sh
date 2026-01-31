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
  assert <file>       Run programmatic assertions on a file
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

Assertions (v0.14.0):
  The assert command runs schema-specific programmatic checks:
  - PRD: version (semver), title, status (draft|in_review|approved|implemented), stakeholders
  - SDD: version (semver), title, components
  - Sprint: version (semver), status (pending|in_progress|completed|archived), sprints
  - Trajectory: timestamp (ISO), agent, action

Examples:
  $(basename "$0") validate grimoires/loa/prd.md
  $(basename "$0") validate output.json --schema prd
  $(basename "$0") validate file.md --mode strict
  $(basename "$0") assert grimoires/loa/prd.md
  $(basename "$0") assert file.json --schema sdd --json
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

    # HIGH-001 fix: Limit content size to prevent DoS
    local max_content_size="${MAX_YAML_SIZE:-100000}"  # 100KB default
    if [[ ${#content} -gt $max_content_size ]]; then
        print_error "YAML content exceeds maximum size ($max_content_size bytes)"
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
# ASSERTION FUNCTIONS (v0.14.0)
#######################################

#######################################
# Assert that a field exists in JSON data
# Arguments:
#   $1 - JSON data string
#   $2 - Field path (supports dot notation: "a.b.c")
# Returns:
#   0 if field exists, 1 if missing
#######################################
assert_field_exists() {
    local json_data="$1"
    local field_path="$2"

    # Convert dot notation to jq path
    local jq_path
    jq_path=$(echo "$field_path" | sed 's/\./"]["]/g' | sed 's/^/["/' | sed 's/$/"]/')

    # Check if field exists (not null or missing)
    local result
    result=$(echo "$json_data" | jq -e "getpath($jq_path) != null" 2>/dev/null)

    if [[ "$result" == "true" ]]; then
        return 0
    else
        echo "ASSERTION_FAILED: Field '$field_path' does not exist"
        return 1
    fi
}

#######################################
# Assert that a field value matches a regex pattern
# Arguments:
#   $1 - JSON data string
#   $2 - Field path (supports dot notation)
#   $3 - Regex pattern to match
# Returns:
#   0 if matches, 1 if not
#######################################
assert_field_matches() {
    local json_data="$1"
    local field_path="$2"
    local pattern="$3"

    # Convert dot notation to jq path
    local jq_path
    jq_path=$(echo "$field_path" | sed 's/\./"]["]/g' | sed 's/^/["/' | sed 's/$/"]/')

    # Get field value
    local value
    value=$(echo "$json_data" | jq -r "getpath($jq_path) // empty" 2>/dev/null)

    if [[ -z "$value" ]]; then
        echo "ASSERTION_FAILED: Field '$field_path' does not exist"
        return 1
    fi

    # Check if value matches pattern
    if [[ "$value" =~ $pattern ]]; then
        return 0
    else
        echo "ASSERTION_FAILED: Field '$field_path' value '$value' does not match pattern '$pattern'"
        return 1
    fi
}

#######################################
# Assert that an array field is not empty
# Arguments:
#   $1 - JSON data string
#   $2 - Field path (supports dot notation)
# Returns:
#   0 if array has elements, 1 if empty
#######################################
assert_array_not_empty() {
    local json_data="$1"
    local field_path="$2"

    # Convert dot notation to jq path
    local jq_path
    jq_path=$(echo "$field_path" | sed 's/\./"]["]/g' | sed 's/^/["/' | sed 's/$/"]/')

    # Get array length
    local length
    length=$(echo "$json_data" | jq -r "getpath($jq_path) | if type == \"array\" then length else 0 end" 2>/dev/null)

    if [[ -z "$length" || "$length" == "null" ]]; then
        length=0
    fi

    if [[ "$length" -gt 0 ]]; then
        return 0
    else
        echo "ASSERTION_FAILED: Array '$field_path' is empty"
        return 1
    fi
}

#######################################
# Common regex patterns for assertions
#######################################
PATTERN_SEMVER='^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'
PATTERN_DATE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
PATTERN_DATETIME='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'
PATTERN_STATUS_PRD='^(draft|in_review|approved|implemented)$'
PATTERN_STATUS_SPRINT='^(pending|in_progress|completed|archived)$'

#######################################
# Run schema-specific assertions on JSON data
# Arguments:
#   $1 - JSON data string
#   $2 - Schema name (prd, sdd, sprint, trajectory-entry)
# Returns:
#   0 if all assertions pass, 1 if any fail
#   Outputs list of failed assertions
#######################################
validate_with_assertions() {
    local json_data="$1"
    local schema_name="$2"
    local failures=()
    local result

    case "$schema_name" in
        prd)
            # PRD assertions
            if ! result=$(assert_field_exists "$json_data" "version"); then
                failures+=("$result")
            fi
            if ! result=$(assert_field_exists "$json_data" "title"); then
                failures+=("$result")
            fi
            if ! result=$(assert_field_exists "$json_data" "status"); then
                failures+=("$result")
            fi
            # Version must be semver
            if ! result=$(assert_field_matches "$json_data" "version" "$PATTERN_SEMVER"); then
                failures+=("$result")
            fi
            # Status must be valid enum
            if ! result=$(assert_field_matches "$json_data" "status" "$PATTERN_STATUS_PRD"); then
                failures+=("$result")
            fi
            # Stakeholders array should not be empty
            if ! result=$(assert_array_not_empty "$json_data" "stakeholders"); then
                failures+=("$result")
            fi
            ;;

        sdd)
            # SDD assertions
            if ! result=$(assert_field_exists "$json_data" "version"); then
                failures+=("$result")
            fi
            if ! result=$(assert_field_exists "$json_data" "title"); then
                failures+=("$result")
            fi
            # Version must be semver
            if ! result=$(assert_field_matches "$json_data" "version" "$PATTERN_SEMVER"); then
                failures+=("$result")
            fi
            # Components array should not be empty
            if ! result=$(assert_array_not_empty "$json_data" "components"); then
                failures+=("$result")
            fi
            ;;

        sprint)
            # Sprint assertions
            if ! result=$(assert_field_exists "$json_data" "version"); then
                failures+=("$result")
            fi
            if ! result=$(assert_field_exists "$json_data" "status"); then
                failures+=("$result")
            fi
            # Version must be semver
            if ! result=$(assert_field_matches "$json_data" "version" "$PATTERN_SEMVER"); then
                failures+=("$result")
            fi
            # Status must be valid enum
            if ! result=$(assert_field_matches "$json_data" "status" "$PATTERN_STATUS_SPRINT"); then
                failures+=("$result")
            fi
            # Sprints array should not be empty
            if ! result=$(assert_array_not_empty "$json_data" "sprints"); then
                failures+=("$result")
            fi
            ;;

        trajectory-entry)
            # Trajectory entry assertions
            if ! result=$(assert_field_exists "$json_data" "timestamp"); then
                failures+=("$result")
            fi
            if ! result=$(assert_field_exists "$json_data" "agent"); then
                failures+=("$result")
            fi
            if ! result=$(assert_field_exists "$json_data" "action"); then
                failures+=("$result")
            fi
            # Timestamp must be ISO format
            if ! result=$(assert_field_matches "$json_data" "timestamp" "$PATTERN_DATETIME"); then
                failures+=("$result")
            fi
            ;;

        *)
            # Unknown schema - no assertions
            return 0
            ;;
    esac

    # Output failures and return status
    if [[ ${#failures[@]} -eq 0 ]]; then
        return 0
    else
        printf '%s\n' "${failures[@]}"
        return 1
    fi
}

#######################################
# Assert command - run assertions on a file
# Arguments:
#   $1 - File path
#   $2 - Schema override (optional)
#   $3 - JSON output flag
# Returns:
#   0 if all assertions pass, 1 if any fail
#######################################
run_assertions() {
    local file_path="$1"
    local schema_override="${2:-}"
    local json_output="${3:-false}"

    # Check file exists
    if [[ ! -f "$file_path" ]]; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"status": "error", "message": "File not found", "assertions": []}'
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
                echo '{"status": "error", "message": "Could not auto-detect schema", "assertions": []}'
            else
                print_error "Could not auto-detect schema for: $file_path"
                print_info "Use --schema <name> to specify manually"
            fi
            return 1
        fi
    fi

    # Extract JSON data
    local json_data
    local temp_json
    temp_json=$(mktemp) || { echo '{"error":"mktemp failed"}'; return 1; }
    chmod 600 "$temp_json"  # CRITICAL-001 FIX
    trap "rm -f '$temp_json'" EXIT

    # Handle different file types
    case "$file_path" in
        *.json)
            cp "$file_path" "$temp_json"
            ;;
        *.jsonl)
            head -1 "$file_path" > "$temp_json"
            ;;
        *.md)
            if ! extract_frontmatter "$file_path" > "$temp_json"; then
                if [[ "$json_output" == "true" ]]; then
                    echo '{"status": "error", "message": "Could not extract frontmatter", "assertions": []}'
                else
                    print_error "Could not extract JSON/YAML frontmatter from: $file_path"
                fi
                return 1
            fi
            ;;
        *)
            if ! extract_frontmatter "$file_path" > "$temp_json"; then
                cp "$file_path" "$temp_json"
            fi
            ;;
    esac

    # Validate JSON syntax
    if ! jq empty "$temp_json" 2>/dev/null; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"status": "error", "message": "Invalid JSON", "assertions": []}'
        else
            print_error "Invalid JSON in: $file_path"
        fi
        return 1
    fi

    json_data=$(cat "$temp_json")

    # Run assertions
    local assertion_output
    local assertion_status=0
    assertion_output=$(validate_with_assertions "$json_data" "$schema_name" 2>&1) || assertion_status=$?

    # Output results
    if [[ "$json_output" == "true" ]]; then
        local failures_json="[]"
        if [[ -n "$assertion_output" ]]; then
            failures_json=$(echo "$assertion_output" | jq -Rs 'split("\n") | map(select(length > 0))')
        fi

        if [[ $assertion_status -eq 0 ]]; then
            echo "{\"status\": \"passed\", \"schema\": \"$schema_name\", \"file\": \"$file_path\", \"assertions\": $failures_json}"
        else
            echo "{\"status\": \"failed\", \"schema\": \"$schema_name\", \"file\": \"$file_path\", \"assertions\": $failures_json}"
        fi
    else
        if [[ $assertion_status -eq 0 ]]; then
            print_success "All assertions passed: $file_path (schema: $schema_name)"
        else
            print_error "Assertion failures: $file_path (schema: $schema_name)"
            echo "$assertion_output" | while read -r line; do
                [[ -n "$line" ]] && echo "  $line"
            done
        fi
    fi

    return $assertion_status
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
    temp_json=$(mktemp) || { echo '{"error":"mktemp failed"}'; return 1; }
    chmod 600 "$temp_json"  # CRITICAL-001 FIX
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
            validate|list|assert)
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
                        validate|list|assert)
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
        assert)
            if [[ -z "$file_path" ]]; then
                print_error "No file specified"
                usage
                exit 1
            fi
            run_assertions "$file_path" "$schema_override" "$json_output"
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
