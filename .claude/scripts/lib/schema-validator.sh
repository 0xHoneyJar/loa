#!/usr/bin/env bash
# schema-validator.sh - JSON schema validation utilities
# Part of Flatline-Enhanced Compound Learning (Sprint 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_DIR="${SCRIPT_DIR}/../../schemas"

# Source common utilities if available
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
fi

# Logging functions (if not already defined)
if ! declare -f log_error &>/dev/null; then
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARN] $*" >&2; }
    log_info() { echo "[INFO] $*" >&2; }
fi

# Validate JSON against a schema
# Usage: validate_against_schema <json_string_or_file> <schema_name>
# Returns: 0 if valid, 1 if invalid
validate_against_schema() {
    local json_input="$1"
    local schema_name="$2"
    local schema_file="${SCHEMA_DIR}/${schema_name}.schema.json"

    # Check if schema exists
    if [[ ! -f "$schema_file" ]]; then
        log_error "Schema not found: $schema_name (expected at $schema_file)"
        return 1
    fi

    # Get JSON content (from file or string)
    local json_content
    if [[ -f "$json_input" ]]; then
        json_content=$(cat "$json_input")
    else
        json_content="$json_input"
    fi

    # Validate JSON syntax first
    if ! echo "$json_content" | jq empty 2>/dev/null; then
        log_error "Invalid JSON syntax"
        return 1
    fi

    # Try ajv-cli if available (most complete validation)
    if command -v ajv &>/dev/null; then
        if echo "$json_content" | ajv validate -s "$schema_file" -d /dev/stdin 2>/dev/null; then
            return 0
        else
            log_error "Schema validation failed (ajv)"
            return 1
        fi
    fi

    # Fallback: Basic jq-based validation for required fields
    validate_with_jq "$json_content" "$schema_file"
}

# Basic jq-based validation (checks required fields and types)
validate_with_jq() {
    local json_content="$1"
    local schema_file="$2"

    # Extract required fields from schema
    local required_fields
    required_fields=$(jq -r '.required // [] | .[]' "$schema_file" 2>/dev/null)

    # Check each required field exists
    for field in $required_fields; do
        if ! echo "$json_content" | jq -e "has(\"$field\")" > /dev/null 2>&1; then
            log_error "Missing required field: $field"
            return 1
        fi
    done

    return 0
}

# Validate transformation response (LLM fallback output)
validate_transformation_response() {
    local response="$1"

    # Quick inline validation for transformation responses
    if ! echo "$response" | jq -e '
        (.trigger | type == "string" and length >= 10 and startswith("When ")) and
        (.solution | type == "string" and length >= 10) and
        (.confidence | type == "number" and . >= 0 and . <= 1)
    ' > /dev/null 2>&1; then
        log_error "Transformation response failed validation"
        return 1
    fi

    return 0
}

# Validate vote response (borderline validation output)
validate_vote_response() {
    local response="$1"

    # Quick inline validation for vote responses
    if ! echo "$response" | jq -e '
        (.vote | IN("approve", "reject")) and
        (.confidence | type == "number" and . >= 0 and . <= 1) and
        (.reasoning | type == "string" and length >= 5)
    ' > /dev/null 2>&1; then
        log_error "Vote response failed validation"
        return 1
    fi

    return 0
}

# Validate proposal review response
validate_proposal_review_response() {
    local response="$1"

    if ! echo "$response" | jq -e '
        (.score | type == "number" and . >= 0 and . <= 1000) and
        (.alignment | type == "boolean") and
        (.concerns | type == "array") and
        (.suggestions | type == "array")
    ' > /dev/null 2>&1; then
        log_error "Proposal review response failed validation"
        return 1
    fi

    return 0
}

# Validate learning object
validate_learning() {
    local learning="$1"

    if ! echo "$learning" | jq -e '
        (.id | type == "string") and
        (.trigger | type == "string" and length >= 10) and
        (.solution | type == "string" and length >= 10)
    ' > /dev/null 2>&1; then
        log_error "Learning object failed validation"
        return 1
    fi

    return 0
}

# Run validation and report result
# Usage: validate_and_report <json> <schema_name> [--quiet]
validate_and_report() {
    local json="$1"
    local schema_name="$2"
    local quiet="${3:-}"

    if validate_against_schema "$json" "$schema_name"; then
        [[ "$quiet" != "--quiet" ]] && echo "✓ Valid against $schema_name"
        return 0
    else
        [[ "$quiet" != "--quiet" ]] && echo "✗ Invalid against $schema_name"
        return 1
    fi
}

# CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            echo "Usage: schema-validator.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  validate <json_file> <schema_name>  Validate JSON against schema"
            echo "  list                                List available schemas"
            echo ""
            echo "Examples:"
            echo "  schema-validator.sh validate response.json validation-vote"
            echo "  echo '{...}' | schema-validator.sh validate - transformation-response"
            ;;
        validate)
            json_input="${2:--}"
            schema_name="${3:-}"
            if [[ -z "$schema_name" ]]; then
                echo "Error: schema name required" >&2
                exit 1
            fi
            if [[ "$json_input" == "-" ]]; then
                json_input=$(cat)
            fi
            validate_and_report "$json_input" "$schema_name"
            ;;
        list)
            echo "Available schemas:"
            ls -1 "$SCHEMA_DIR"/*.schema.json 2>/dev/null | xargs -I{} basename {} .schema.json
            ;;
        *)
            echo "Unknown command: ${1:-}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
fi
