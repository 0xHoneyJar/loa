#!/usr/bin/env bash
# security-validators.sh - Security validation utilities for Loa scripts
#
# Usage:
#   source .claude/scripts/security-validators.sh
#
# Functions:
#   validate_safe_path <path> <allowed_prefix>    - Validate path doesn't escape boundary
#   validate_numeric <value> [min] [max]          - Validate numeric value with optional bounds
#   validate_boolean <value>                      - Validate boolean value
#   validate_repo_url <url>                       - Validate GitHub repo URL format
#   validate_config_path <path>                   - Validate config-provided path (no traversal)
#   safe_rm_rf <path> <boundary>                  - Safe rm -rf with path validation
#
# SECURITY NOTES:
#   - All validators return 0 on success, 1 on failure
#   - Use these in place of direct interpolation of yq/jq output
#   - Always validate config values before use in paths or commands

set -euo pipefail

# =============================================================================
# Path Validation
# =============================================================================

# Validate that a path doesn't escape a boundary directory
# Usage: validate_safe_path "/some/path" "/allowed/prefix"
# Returns: 0 if safe, 1 if unsafe (traversal detected)
validate_safe_path() {
    local path="$1"
    local boundary="$2"

    # Check for obvious traversal patterns
    if [[ "$path" == *".."* ]]; then
        echo "SECURITY: Path contains traversal sequence: $path" >&2
        return 1
    fi

    # Don't allow absolute paths from config unless they match boundary
    if [[ "$path" == /* && "$path" != "$boundary"* ]]; then
        echo "SECURITY: Absolute path doesn't start with boundary: $path" >&2
        return 1
    fi

    # Resolve to real path and verify still within boundary
    local real_path real_boundary

    # If path exists, resolve it
    if [[ -e "$path" ]]; then
        real_path=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path") || {
            echo "SECURITY: Cannot resolve path: $path" >&2
            return 1
        }
    else
        # For non-existent paths, just check for traversal
        real_path="$path"
    fi

    # Resolve boundary
    if [[ -d "$boundary" ]]; then
        real_boundary=$(cd "$boundary" 2>/dev/null && pwd -P) || {
            echo "SECURITY: Cannot resolve boundary: $boundary" >&2
            return 1
        }
    else
        real_boundary="$boundary"
    fi

    # Check path starts with boundary
    if [[ "$real_path" != "$real_boundary"* ]]; then
        echo "SECURITY: Path escapes boundary: $path -> $real_path (boundary: $real_boundary)" >&2
        return 1
    fi

    return 0
}

# Validate a config-provided path doesn't contain traversal sequences
# Usage: validate_config_path ".loa/qmd"
# Returns: 0 if safe, 1 if unsafe
validate_config_path() {
    local path="$1"

    # Check for traversal patterns
    if [[ "$path" == *".."* ]]; then
        echo "SECURITY: Config path contains traversal: $path" >&2
        return 1
    fi

    # Check for absolute paths (config should use relative)
    if [[ "$path" == /* ]]; then
        echo "SECURITY: Config path should be relative, not absolute: $path" >&2
        return 1
    fi

    # Check for shell metacharacters
    if [[ "$path" =~ [\$\`\|\;\&\<\>] ]]; then
        echo "SECURITY: Config path contains shell metacharacters: $path" >&2
        return 1
    fi

    return 0
}

# Safe rm -rf with boundary validation and symlink resolution
# Usage: safe_rm_rf "/path/to/delete" "/boundary/directory" ["pattern"]
# Returns: 0 on success, 1 on validation failure
safe_rm_rf() {
    local target="$1"
    local boundary="$2"
    local pattern="${3:-}"  # Optional pattern (e.g., "cycle-*")

    # Basic sanity checks
    if [[ -z "$target" ]]; then
        echo "SECURITY: Empty path passed to safe_rm_rf" >&2
        return 1
    fi

    if [[ "$target" == "/" || "$target" == "$HOME" || "$target" == "$HOME/"* && ${#target} -lt $((${#HOME} + 5)) ]]; then
        echo "SECURITY: Refusing to delete critical path: $target" >&2
        return 1
    fi

    # Check for traversal
    if [[ "$target" == *".."* ]]; then
        echo "SECURITY: Path contains traversal: $target" >&2
        return 1
    fi

    # Verify path starts with boundary (before resolution)
    if [[ "$target" != "$boundary"* && "$target" != "$boundary/"* ]]; then
        echo "SECURITY: Path doesn't match boundary prefix: $target (boundary: $boundary)" >&2
        return 1
    fi

    # If pattern specified, verify it matches
    if [[ -n "$pattern" && "$(basename "$target")" != $pattern ]]; then
        # Use bash pattern matching
        local basename_target
        basename_target=$(basename "$target")
        case "$basename_target" in
            $pattern) ;;  # Match
            *)
                echo "SECURITY: Path doesn't match required pattern: $target (pattern: $pattern)" >&2
                return 1
                ;;
        esac
    fi

    # If target exists, resolve symlinks and verify boundary
    if [[ -e "$target" ]]; then
        local real_target real_boundary

        # Resolve target
        if [[ -d "$target" ]]; then
            real_target=$(cd "$target" 2>/dev/null && pwd -P) || {
                echo "SECURITY: Cannot resolve target: $target" >&2
                return 1
            }
        else
            real_target=$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$(basename "$target") || {
                echo "SECURITY: Cannot resolve target: $target" >&2
                return 1
            }
        fi

        # Resolve boundary
        real_boundary=$(cd "$boundary" 2>/dev/null && pwd -P) || {
            echo "SECURITY: Cannot resolve boundary: $boundary" >&2
            return 1
        }

        # Final check: resolved path still within boundary
        if [[ "$real_target" != "$real_boundary"* && "$real_target" != "$real_boundary/"* ]]; then
            echo "SECURITY: Resolved path escapes boundary (possible symlink attack): $target -> $real_target" >&2
            return 1
        fi

        # All checks passed, safe to delete
        rm -rf "$real_target"
    else
        # Target doesn't exist, nothing to delete
        :
    fi

    return 0
}

# =============================================================================
# Numeric Validation
# =============================================================================

# Validate a value is numeric with optional bounds
# Usage: validate_numeric "$value" [min] [max]
# Returns: 0 if valid, 1 if invalid
# Echoes: The validated value (or default if invalid)
validate_numeric() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"
    local default="${4:-0}"

    # Check if it's a valid integer
    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "$default"
        return 1
    fi

    # Check minimum bound
    if [[ -n "$min" && "$value" -lt "$min" ]]; then
        echo "$min"
        return 1
    fi

    # Check maximum bound
    if [[ -n "$max" && "$value" -gt "$max" ]]; then
        echo "$max"
        return 1
    fi

    echo "$value"
    return 0
}

# Validate a floating point value with optional bounds
# Usage: validate_float "$value" [min] [max] [default]
# Returns: 0 if valid, 1 if invalid
validate_float() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"
    local default="${4:-0.0}"

    # Check if it's a valid float/integer
    if ! [[ "$value" =~ ^-?[0-9]*\.?[0-9]+$ ]]; then
        echo "$default"
        return 1
    fi

    # Check bounds using bc
    if [[ -n "$min" ]] && (( $(echo "$value < $min" | bc -l 2>/dev/null || echo "0") )); then
        echo "$min"
        return 1
    fi

    if [[ -n "$max" ]] && (( $(echo "$value > $max" | bc -l 2>/dev/null || echo "0") )); then
        echo "$max"
        return 1
    fi

    echo "$value"
    return 0
}

# =============================================================================
# Boolean Validation
# =============================================================================

# Validate and normalize a boolean value
# Usage: validate_boolean "$value" [default]
# Returns: 0 if valid, 1 if invalid
# Echoes: "true" or "false"
validate_boolean() {
    local value="$1"
    local default="${2:-false}"

    case "${value,,}" in  # Convert to lowercase
        true|yes|1|on)
            echo "true"
            return 0
            ;;
        false|no|0|off|"")
            echo "false"
            return 0
            ;;
        *)
            echo "$default"
            return 1
            ;;
    esac
}

# =============================================================================
# Repository URL Validation
# =============================================================================

# Validate GitHub repository URL format
# Usage: validate_repo_url "owner/repo"
# Returns: 0 if valid, 1 if invalid
validate_repo_url() {
    local repo="$1"

    # Check basic format: owner/repo
    if [[ ! "$repo" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*/[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        echo "SECURITY: Invalid repo format: $repo" >&2
        return 1
    fi

    # Additional checks for suspicious patterns
    if [[ "$repo" == *".."* ]]; then
        echo "SECURITY: Repo contains traversal sequence: $repo" >&2
        return 1
    fi

    return 0
}

# Validate that a repo URL matches expected patterns (for config integrity)
# Usage: validate_trusted_repo "owner/repo" "expected_owner"
# Returns: 0 if trusted, 1 if untrusted
validate_trusted_repo() {
    local repo="$1"
    local expected_owner="$2"

    # First validate format
    if ! validate_repo_url "$repo"; then
        return 1
    fi

    # Extract owner
    local owner="${repo%%/*}"

    # Check owner matches expected
    if [[ "$owner" != "$expected_owner" ]]; then
        echo "WARNING: Repo owner '$owner' doesn't match expected '$expected_owner'" >&2
        return 1
    fi

    return 0
}

# =============================================================================
# Safe Config Value Extraction
# =============================================================================

# Safely extract and validate a numeric config value
# Usage: safe_config_numeric ".path.to.value" "$config_file" [default] [min] [max]
safe_config_numeric() {
    local path="$1"
    local config_file="$2"
    local default="${3:-0}"
    local min="${4:-}"
    local max="${5:-}"

    local raw_value
    raw_value=$(yq eval "$path // $default" "$config_file" 2>/dev/null || echo "$default")

    validate_numeric "$raw_value" "$min" "$max" "$default"
}

# Safely extract and validate a boolean config value
# Usage: safe_config_boolean ".path.to.value" "$config_file" [default]
safe_config_boolean() {
    local path="$1"
    local config_file="$2"
    local default="${3:-false}"

    local raw_value
    raw_value=$(yq eval "$path // \"$default\"" "$config_file" 2>/dev/null || echo "$default")

    validate_boolean "$raw_value" "$default"
}

# Safely extract and validate a path config value
# Usage: safe_config_path ".path.to.value" "$config_file" [default]
safe_config_path() {
    local path="$1"
    local config_file="$2"
    local default="${3:-}"

    local raw_value
    raw_value=$(yq eval "$path // \"$default\"" "$config_file" 2>/dev/null || echo "$default")

    if validate_config_path "$raw_value"; then
        echo "$raw_value"
        return 0
    else
        echo "$default"
        return 1
    fi
}

# =============================================================================
# Test Mode (for validation)
# =============================================================================

if [[ "${1:-}" == "--test" ]]; then
    echo "Running security-validators.sh self-tests..."

    # Test validate_config_path
    echo -n "Test 1: Config path with traversal... "
    if validate_config_path "../../../etc/passwd" 2>/dev/null; then
        echo "FAIL (should have rejected)"
        exit 1
    else
        echo "PASS"
    fi

    echo -n "Test 2: Valid config path... "
    if validate_config_path ".loa/qmd" 2>/dev/null; then
        echo "PASS"
    else
        echo "FAIL"
        exit 1
    fi

    echo -n "Test 3: Numeric validation (valid)... "
    result=$(validate_numeric "42" 0 100)
    if [[ "$result" == "42" ]]; then
        echo "PASS"
    else
        echo "FAIL: got '$result'"
        exit 1
    fi

    echo -n "Test 4: Numeric validation (invalid)... "
    result=$(validate_numeric "abc" "" "" "50" || true)
    if [[ "$result" == "50" ]]; then
        echo "PASS"
    else
        echo "FAIL: got '$result'"
        exit 1
    fi

    echo -n "Test 5: Boolean validation... "
    result=$(validate_boolean "yes")
    if [[ "$result" == "true" ]]; then
        echo "PASS"
    else
        echo "FAIL: got '$result'"
        exit 1
    fi

    echo -n "Test 6: Repo URL validation (valid)... "
    if validate_repo_url "0xHoneyJar/loa" 2>/dev/null; then
        echo "PASS"
    else
        echo "FAIL"
        exit 1
    fi

    echo -n "Test 7: Repo URL validation (invalid)... "
    if validate_repo_url "../evil/repo" 2>/dev/null; then
        echo "FAIL (should have rejected)"
        exit 1
    else
        echo "PASS"
    fi

    echo ""
    echo "All tests passed!"
fi
