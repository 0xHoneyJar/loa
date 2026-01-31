#!/usr/bin/env bash
# license-validator.sh - JWT license validation for Loa Constructs
#
# Usage:
#   license-validator.sh validate <license-file>    - Full validation flow
#   license-validator.sh verify-signature <jwt>     - Signature verification only
#   license-validator.sh decode <jwt>               - Extract JWT payload
#   license-validator.sh get-public-key <key-id>    - Fetch/cache public key
#   license-validator.sh check-expiry <license-file> - Check expiration status
#
# Exit Codes:
#   0 = Valid license
#   1 = Expired but in grace period
#   2 = Expired beyond grace period
#   3 = Missing license file
#   4 = Invalid signature
#   5 = Other error (missing deps, network, etc.)
#
# Environment Variables:
#   LOA_CACHE_DIR      - Override cache directory (default: ~/.loa/cache)
#   LOA_REGISTRY_URL   - Override registry URL
#   LOA_OFFLINE        - Set to 1 for offline-only mode

set -euo pipefail

# Get script directory for sourcing constructs-lib
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [[ -f "$SCRIPT_DIR/constructs-lib.sh" ]]; then
    source "$SCRIPT_DIR/constructs-lib.sh"
else
    echo "ERROR: constructs-lib.sh not found" >&2
    exit 5
fi

# =============================================================================
# Constants
# =============================================================================

EXIT_VALID=0
EXIT_GRACE=1
EXIT_EXPIRED=2
EXIT_MISSING=3
EXIT_INVALID_SIG=4
EXIT_ERROR=5

# =============================================================================
# Cache Directory Management
# =============================================================================

get_cache_directory() {
    local cache_dir="${LOA_CACHE_DIR:-$HOME/.loa/cache}"
    echo "$cache_dir"
}

get_public_keys_cache_directory() {
    local cache_dir
    cache_dir=$(get_cache_directory)
    echo "$cache_dir/public-keys"
}

ensure_cache_directories() {
    local keys_dir
    keys_dir=$(get_public_keys_cache_directory)
    mkdir -p "$keys_dir"
}

# =============================================================================
# Base64URL Encoding/Decoding
# =============================================================================

# Decode base64url to raw bytes
base64url_decode() {
    local input="$1"

    # Replace URL-safe characters with standard base64
    local b64="${input//-/+}"
    b64="${b64//_//}"

    # Add padding if necessary
    local pad=$((4 - ${#b64} % 4))
    if [[ $pad -ne 4 ]]; then
        b64="${b64}$(printf '=%.0s' $(seq 1 $pad))"
    fi

    # Decode
    echo "$b64" | base64 -d 2>/dev/null
}

# =============================================================================
# JWT Parsing
# =============================================================================

# Extract JWT header (first part)
jwt_get_header() {
    local jwt="$1"
    local header="${jwt%%.*}"
    base64url_decode "$header"
}

# Extract JWT payload (second part)
jwt_get_payload() {
    local jwt="$1"
    local rest="${jwt#*.}"
    local payload="${rest%%.*}"
    base64url_decode "$payload"
}

# Extract JWT signature (third part) as raw bytes
jwt_get_signature() {
    local jwt="$1"
    local rest="${jwt#*.}"
    rest="${rest#*.}"
    base64url_decode "$rest"
}

# Get the signing input (header.payload)
jwt_get_signing_input() {
    local jwt="$1"
    local rest="${jwt#*.}"
    local payload_b64="${rest%%.*}"
    local header_b64="${jwt%%.*}"
    echo -n "${header_b64}.${payload_b64}"
}

# Extract key ID from JWT header
jwt_get_key_id() {
    local jwt="$1"
    local header
    header=$(jwt_get_header "$jwt")
    echo "$header" | jq -r '.kid // "default"'
}

# =============================================================================
# Public Key Management
# =============================================================================

# Check if cached key is still valid
is_key_cache_valid() {
    local key_id="$1"
    local keys_dir
    keys_dir=$(get_public_keys_cache_directory)

    local key_file="$keys_dir/${key_id}.pem"
    local meta_file="$keys_dir/${key_id}.meta.json"

    # Check files exist
    [[ -f "$key_file" ]] || return 1
    [[ -f "$meta_file" ]] || return 1

    # SECURITY (MED-004): Reduced default cache from 24h to 4h
    # Shorter cache reduces window for compromised key injection
    local cache_hours
    cache_hours=$(get_registry_config "public_key_cache_hours" "4")

    # Parse fetched_at from metadata
    local fetched_at
    fetched_at=$(jq -r '.fetched_at // ""' "$meta_file")
    [[ -n "$fetched_at" ]] || return 1

    # Calculate if cache is still valid
    local fetched_ts
    fetched_ts=$(parse_iso_date "$fetched_at")
    local now_ts
    now_ts=$(now_timestamp)
    local age_hours=$(( (now_ts - fetched_ts) / 3600 ))

    [[ $age_hours -lt $cache_hours ]]
}

# Get public key (from cache or fetch)
do_get_public_key() {
    local key_id="$1"
    local force_refresh="${2:-false}"
    local offline_only="${3:-false}"

    ensure_cache_directories

    local keys_dir
    keys_dir=$(get_public_keys_cache_directory)
    local key_file="$keys_dir/${key_id}.pem"
    local meta_file="$keys_dir/${key_id}.meta.json"

    # Check if we should use cache
    if [[ "$force_refresh" != "true" ]] && is_key_cache_valid "$key_id"; then
        cat "$key_file"
        return 0
    fi

    # Offline mode - can only use cache
    if [[ "${LOA_OFFLINE:-0}" == "1" ]] || [[ "$offline_only" == "true" ]]; then
        if [[ -f "$key_file" ]]; then
            # Use expired cache in offline mode
            cat "$key_file"
            return 0
        else
            echo "ERROR: No cached key and offline mode enabled" >&2
            return 1
        fi
    fi

    # Fetch from registry
    local registry_url
    registry_url=$(get_registry_url)

    if ! command -v curl &>/dev/null; then
        echo "ERROR: curl required for key fetch" >&2
        return 1
    fi

    local response
    # HIGH-002 FIX: Enforce HTTPS and TLS 1.2+
    response=$(curl -sf --proto =https --tlsv1.2 "${registry_url}/public-keys/${key_id}" 2>/dev/null) || {
        # Network error - try to use stale cache
        if [[ -f "$key_file" ]]; then
            echo "WARNING: Using stale cached key (network error)" >&2
            cat "$key_file"
            return 0
        fi
        echo "ERROR: Failed to fetch public key" >&2
        return 1
    }

    # Extract and save public key
    local public_key
    public_key=$(echo "$response" | jq -r '.public_key')

    if [[ -z "$public_key" ]] || [[ "$public_key" == "null" ]]; then
        echo "ERROR: Invalid key response" >&2
        return 1
    fi

    # Save key
    echo "$public_key" > "$key_file"

    # Save metadata
    cat > "$meta_file" << EOF
{
    "key_id": "$key_id",
    "algorithm": "RS256",
    "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "expires_at": "$(echo "$response" | jq -r '.expires_at // "2030-01-01T00:00:00Z"')"
}
EOF

    cat "$key_file"
}

# =============================================================================
# RS256 Signature Verification
# =============================================================================

# Verify RS256 signature using OpenSSL
verify_signature_openssl() {
    local jwt="$1"
    local public_key="$2"

    # Get signing input and signature
    local signing_input
    signing_input=$(jwt_get_signing_input "$jwt")

    local signature_file
    signature_file=$(mktemp) || { echo "mktemp failed" >&2; return 1; }
    chmod 600 "$signature_file"  # CRITICAL-001 FIX
    local input_file
    input_file=$(mktemp) || { rm -f "$signature_file"; echo "mktemp failed" >&2; return 1; }
    chmod 600 "$input_file"  # CRITICAL-001 FIX
    local key_file
    key_file=$(mktemp) || { rm -f "$signature_file" "$input_file"; echo "mktemp failed" >&2; return 1; }
    chmod 600 "$key_file"  # CRITICAL-001 FIX

    # Clean up on exit
    trap "rm -f '$signature_file' '$input_file' '$key_file'" EXIT

    # Write signature (raw bytes)
    jwt_get_signature "$jwt" > "$signature_file"

    # Write signing input
    echo -n "$signing_input" > "$input_file"

    # Write public key
    echo "$public_key" > "$key_file"

    # Verify with OpenSSL
    if openssl dgst -sha256 -verify "$key_file" -signature "$signature_file" "$input_file" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Verify signature with jwt-cli fallback
verify_signature_jwt_cli() {
    local jwt="$1"
    local public_key_file="$2"

    if ! command -v jwt &>/dev/null; then
        return 1
    fi

    # jwt-cli verify
    jwt decode --secret=@"$public_key_file" --alg=RS256 "$jwt" >/dev/null 2>&1
}

# Main signature verification
do_verify_signature() {
    local jwt="$1"

    # Validate JWT format (three parts separated by dots)
    if [[ -z "$jwt" ]] || [[ ! "$jwt" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR: Invalid JWT format" >&2
        return 1
    fi

    # Get key ID from header
    local key_id
    key_id=$(jwt_get_key_id "$jwt")

    # Get public key
    local public_key
    public_key=$(do_get_public_key "$key_id") || {
        echo "ERROR: Failed to get public key" >&2
        return 1
    }

    # Try OpenSSL first
    if verify_signature_openssl "$jwt" "$public_key"; then
        return 0
    fi

    # Fallback to jwt-cli if available
    local keys_dir
    keys_dir=$(get_public_keys_cache_directory)
    local key_file="$keys_dir/${key_id}.pem"

    if [[ -f "$key_file" ]] && verify_signature_jwt_cli "$jwt" "$key_file"; then
        return 0
    fi

    echo "ERROR: Signature verification failed" >&2
    return 1
}

# =============================================================================
# License Validation
# =============================================================================

# Check expiration status of a license
do_check_expiry() {
    local license_file="$1"

    if [[ ! -f "$license_file" ]]; then
        echo "ERROR: License file not found: $license_file" >&2
        return $EXIT_MISSING
    fi

    # Extract token from license file
    local token
    token=$(jq -r '.token // ""' "$license_file" 2>/dev/null) || {
        echo "ERROR: Failed to parse license file" >&2
        return $EXIT_ERROR
    }

    if [[ -z "$token" ]] || [[ "$token" == "null" ]]; then
        echo "ERROR: No token in license file" >&2
        return $EXIT_ERROR
    fi

    # Decode payload
    local payload
    payload=$(jwt_get_payload "$token") || {
        echo "ERROR: Failed to decode JWT" >&2
        return $EXIT_ERROR
    }

    # Get expiration timestamp
    local exp_ts
    exp_ts=$(echo "$payload" | jq -r '.exp')

    if [[ -z "$exp_ts" ]] || [[ "$exp_ts" == "null" ]]; then
        echo "ERROR: No expiration in token" >&2
        return $EXIT_ERROR
    fi

    # Get current timestamp
    local now_ts
    now_ts=$(now_timestamp)

    # Get tier for grace period calculation
    local tier
    tier=$(echo "$payload" | jq -r '.tier // "free"')

    # Get grace hours for this tier
    local grace_hours
    grace_hours=$(get_grace_hours "$tier")
    local grace_seconds=$((grace_hours * 3600))

    # Calculate grace period end
    local grace_end_ts=$((exp_ts + grace_seconds))

    # Get skill name for output
    local skill
    skill=$(echo "$payload" | jq -r '.skill // "unknown"')

    if [[ $now_ts -lt $exp_ts ]]; then
        # Valid - not expired
        local remaining=$((exp_ts - now_ts))
        local remaining_human
        remaining_human=$(humanize_duration "$remaining")
        echo "VALID: $skill expires in $remaining_human"
        return $EXIT_VALID
    elif [[ $now_ts -lt $grace_end_ts ]]; then
        # In grace period
        local remaining=$((grace_end_ts - now_ts))
        local remaining_human
        remaining_human=$(humanize_duration "$remaining")
        echo "WARNING: $skill in grace period, $remaining_human remaining"
        return $EXIT_GRACE
    else
        # Expired beyond grace
        local expired_ago=$((now_ts - grace_end_ts))
        local expired_human
        expired_human=$(humanize_duration "$expired_ago")
        echo "ERROR: $skill expired $expired_human ago"
        return $EXIT_EXPIRED
    fi
}

# Full validation flow
do_validate() {
    local license_file="$1"

    # Check file exists
    if [[ ! -f "$license_file" ]]; then
        echo "ERROR: License file not found: $license_file" >&2
        return $EXIT_MISSING
    fi

    # Parse license file
    local token
    token=$(jq -r '.token // ""' "$license_file" 2>/dev/null) || {
        echo "ERROR: Failed to parse license file" >&2
        return $EXIT_ERROR
    }

    if [[ -z "$token" ]] || [[ "$token" == "null" ]]; then
        echo "ERROR: No token in license file" >&2
        return $EXIT_ERROR
    fi

    # SECURITY (MED-006): Verify signature with proper error propagation
    # Don't swallow signature errors - they should not be masked by expiry status
    local sig_result=0
    do_verify_signature "$token" 2>/dev/null || sig_result=$?

    if [[ $sig_result -ne 0 ]]; then
        echo "ERROR: Invalid signature (code: $sig_result)" >&2
        return $EXIT_INVALID_SIG
    fi

    # Check expiration (only after signature is verified)
    # This ensures we never return "grace period" for an invalid signature
    local expiry_result=0
    do_check_expiry "$license_file" || expiry_result=$?

    return $expiry_result
}

# Decode JWT payload and output as JSON
do_decode() {
    local jwt="$1"

    # Validate JWT format
    if [[ -z "$jwt" ]] || [[ ! "$jwt" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR: Invalid JWT format" >&2
        return 1
    fi

    local payload
    payload=$(jwt_get_payload "$jwt") || {
        echo "ERROR: Failed to decode JWT" >&2
        return 1
    }

    # Validate it's valid JSON
    if ! echo "$payload" | jq . >/dev/null 2>&1; then
        echo "ERROR: Invalid JWT payload" >&2
        return 1
    fi

    echo "$payload"
}

# =============================================================================
# Command Line Interface
# =============================================================================

show_usage() {
    cat << 'EOF'
Usage: license-validator.sh <command> [arguments]

Commands:
    validate <license-file>      Full validation (signature + expiry)
    verify-signature <jwt>       Verify JWT signature only
    decode <jwt>                 Extract and display JWT payload
    get-public-key <key-id>      Fetch/display public key
    check-expiry <license-file>  Check license expiration status

Exit Codes:
    0 = Valid license
    1 = Expired but in grace period
    2 = Expired beyond grace period
    3 = Missing license file
    4 = Invalid signature
    5 = Other error

Environment Variables:
    LOA_CACHE_DIR      Override cache directory (~/.loa/cache)
    LOA_REGISTRY_URL   Override registry URL
    LOA_OFFLINE        Set to 1 for offline-only mode

Examples:
    license-validator.sh validate .claude/constructs/skills/vendor/skill/.license.json
    license-validator.sh decode "eyJhbGciOiJSUzI1NiI..."
    license-validator.sh get-public-key test-key-01
EOF
}

main() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        show_usage
        exit $EXIT_ERROR
    fi

    case "$command" in
        validate)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing license file argument" >&2; exit $EXIT_ERROR; }
            do_validate "$2"
            ;;
        verify-signature)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing JWT argument" >&2; exit $EXIT_ERROR; }
            do_verify_signature "$2"
            ;;
        decode)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing JWT argument" >&2; exit $EXIT_ERROR; }
            do_decode "$2"
            ;;
        get-public-key)
            local key_id="${2:-default}"
            local force_refresh="false"
            local offline="false"

            shift 2 2>/dev/null || shift 1 2>/dev/null || true

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --refresh) force_refresh="true" ;;
                    --offline) offline="true" ;;
                    --check-expiry)
                        if ! is_key_cache_valid "$key_id"; then
                            echo "Cache expired or missing for key: $key_id"
                            exit 1
                        fi
                        do_get_public_key "$key_id" "false" "$offline"
                        exit $?
                        ;;
                esac
                shift
            done

            do_get_public_key "$key_id" "$force_refresh" "$offline"
            ;;
        check-expiry)
            [[ -n "${2:-}" ]] || { echo "ERROR: Missing license file argument" >&2; exit $EXIT_ERROR; }
            do_check_expiry "$2"
            ;;
        -h|--help|help)
            show_usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown command: $command" >&2
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
