#!/usr/bin/env bash
# yq-safe.sh - Safe yq output handling library
# Provides validated, injection-safe YAML value extraction
#
# Usage: source this file and use safe_yq_* functions
# See Issue #100 for security rationale

set -euo pipefail

# Color codes (if not already defined)
readonly YQ_RED="${RED:-\033[0;31m}"
readonly YQ_NC="${NC:-\033[0m}"

# Maximum length for extracted values (prevent DoS)
readonly YQ_MAX_VALUE_LENGTH="${YQ_MAX_VALUE_LENGTH:-10000}"

# Log error to stderr
_yq_err() {
    echo -e "${YQ_RED}ERROR: $*${YQ_NC}" >&2
}

# Check if yq is available and determine variant
_yq_check() {
    if ! command -v yq &>/dev/null; then
        _yq_err "yq is required but not installed"
        return 1
    fi
    return 0
}

# Detect yq variant (mikefarah vs python)
# Returns: "mikefarah" or "python" or "unknown"
yq_variant() {
    local version_output
    version_output=$(yq --version 2>&1 || echo "")

    if echo "$version_output" | grep -qE "mikefarah|version v?[0-9]+\.[0-9]+"; then
        echo "mikefarah"
    elif echo "$version_output" | grep -qE "yq|jq"; then
        echo "python"
    else
        echo "unknown"
    fi
}

# Validate that a value is safe for shell use
# Args: $1 = value, $2 = allowed_pattern (optional, default: printable non-shell-meta)
# Returns: 0 if safe, 1 if unsafe
_yq_validate_value() {
    local value="$1"
    local pattern="${2:-}"

    # Check length
    if [[ ${#value} -gt $YQ_MAX_VALUE_LENGTH ]]; then
        _yq_err "Value exceeds maximum length ($YQ_MAX_VALUE_LENGTH)"
        return 1
    fi

    # Check for null/empty
    if [[ -z "$value" || "$value" == "null" ]]; then
        return 0  # Empty/null is safe
    fi

    # If custom pattern provided, use it
    if [[ -n "$pattern" ]]; then
        if [[ ! "$value" =~ $pattern ]]; then
            _yq_err "Value does not match required pattern"
            return 1
        fi
        return 0
    fi

    # Default: reject dangerous shell metacharacters
    # Allow: alphanumeric, space, underscore, dash, dot, slash, colon, comma, @, #
    # Reject: backticks, $, |, ;, &, <, >, (, ), {, }, [, ], !, newlines in suspicious contexts
    if [[ "$value" =~ [\`\$\|\;\&\<\>] ]]; then
        _yq_err "Value contains potentially dangerous shell metacharacters"
        return 1
    fi

    return 0
}

# Sanitize a value for safe shell use (escape special chars)
# Args: $1 = value
# Returns: sanitized value via stdout
_yq_sanitize() {
    local value="$1"

    # Replace dangerous characters with safe alternatives
    # This is a last-resort sanitization - prefer validation
    printf '%s' "$value" | sed -e "s/'/'\\\\''/g"
}

# Safe yq extraction with validation
# Args: $1 = query, $2 = file, $3 = default (optional), $4 = pattern (optional)
# Returns: extracted value via stdout, or default if not found/invalid
safe_yq() {
    local query="$1"
    local file="$2"
    local default="${3:-}"
    local pattern="${4:-}"
    local value
    local variant

    if ! _yq_check; then
        echo "$default"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        _yq_err "File not found: $file"
        echo "$default"
        return 1
    fi

    variant=$(yq_variant)

    # Extract value based on yq variant
    case "$variant" in
        mikefarah)
            value=$(yq eval "$query // \"$default\"" "$file" 2>/dev/null) || value="$default"
            ;;
        python)
            value=$(yq "$query // \"$default\"" "$file" 2>/dev/null) || value="$default"
            ;;
        *)
            _yq_err "Unknown yq variant"
            echo "$default"
            return 1
            ;;
    esac

    # Strip surrounding quotes if present (yq sometimes adds them)
    value="${value#\"}"
    value="${value%\"}"

    # Validate the extracted value
    if ! _yq_validate_value "$value" "$pattern"; then
        _yq_err "Validation failed for query: $query"
        echo "$default"
        return 1
    fi

    echo "$value"
}

# Safe yq extraction for identifiers (strict alphanumeric + dash + underscore)
# Args: $1 = query, $2 = file, $3 = default (optional)
safe_yq_identifier() {
    local query="$1"
    local file="$2"
    local default="${3:-}"

    safe_yq "$query" "$file" "$default" '^[a-zA-Z0-9_-]*$'
}

# Safe yq extraction for version strings (semver-like)
# Args: $1 = query, $2 = file, $3 = default (optional)
safe_yq_version() {
    local query="$1"
    local file="$2"
    local default="${3:-0.0.0}"

    safe_yq "$query" "$file" "$default" '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'
}

# Safe yq extraction for paths (restricted characters)
# Args: $1 = query, $2 = file, $3 = default (optional)
safe_yq_path() {
    local query="$1"
    local file="$2"
    local default="${3:-}"

    safe_yq "$query" "$file" "$default" '^[a-zA-Z0-9_./-]*$'
}

# Safe yq extraction for URLs
# Args: $1 = query, $2 = file, $3 = default (optional)
safe_yq_url() {
    local query="$1"
    local file="$2"
    local default="${3:-}"

    safe_yq "$query" "$file" "$default" '^https?://[a-zA-Z0-9._/?&=%-]+$'
}

# Safe yq extraction for enums (must match one of provided values)
# Args: $1 = query, $2 = file, $3 = default, $4+ = allowed values
safe_yq_enum() {
    local query="$1"
    local file="$2"
    local default="$3"
    shift 3
    local allowed=("$@")

    local value
    value=$(safe_yq "$query" "$file" "$default" '^[a-zA-Z0-9_-]+$')

    # Check if value is in allowed list
    local is_allowed=false
    for allowed_val in "${allowed[@]}"; do
        if [[ "$value" == "$allowed_val" ]]; then
            is_allowed=true
            break
        fi
    done

    if [[ "$is_allowed" == "false" ]]; then
        _yq_err "Value '$value' not in allowed values: ${allowed[*]}"
        echo "$default"
        return 1
    fi

    echo "$value"
}

# Convert YAML to JSON safely (for use with jq)
# Args: $1 = file or - for stdin
# Returns: JSON via stdout
safe_yq_to_json() {
    local input="$1"
    local content
    local variant

    if ! _yq_check; then
        return 1
    fi

    variant=$(yq_variant)

    if [[ "$input" == "-" ]]; then
        content=$(cat)
    elif [[ -f "$input" ]]; then
        content=$(cat "$input")
    else
        _yq_err "Invalid input: $input"
        return 1
    fi

    # Check content length
    if [[ ${#content} -gt $YQ_MAX_VALUE_LENGTH ]]; then
        _yq_err "Content exceeds maximum length"
        return 1
    fi

    case "$variant" in
        mikefarah)
            echo "$content" | yq -o=json '.' 2>/dev/null
            ;;
        python)
            echo "$content" | yq '.' 2>/dev/null
            ;;
        *)
            _yq_err "Unknown yq variant"
            return 1
            ;;
    esac
}

# Safe boolean extraction
# Args: $1 = query, $2 = file, $3 = default (true/false)
safe_yq_bool() {
    local query="$1"
    local file="$2"
    local default="${3:-false}"

    local value
    value=$(safe_yq "$query" "$file" "$default" '^(true|false|yes|no|on|off|1|0)$')

    # Normalize to true/false
    case "$value" in
        true|yes|on|1) echo "true" ;;
        false|no|off|0|"") echo "false" ;;
        *) echo "$default" ;;
    esac
}

# Safe integer extraction
# Args: $1 = query, $2 = file, $3 = default
safe_yq_int() {
    local query="$1"
    local file="$2"
    local default="${3:-0}"

    safe_yq "$query" "$file" "$default" '^-?[0-9]+$'
}

# Export functions for subshells
export -f safe_yq safe_yq_identifier safe_yq_version safe_yq_path safe_yq_url
export -f safe_yq_enum safe_yq_to_json safe_yq_bool safe_yq_int
export -f yq_variant _yq_check _yq_validate_value _yq_sanitize _yq_err
