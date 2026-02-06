#!/usr/bin/env bash
# =============================================================================
# Loa Constructs - Authentication Management
# =============================================================================
# Manage API key authentication for the Loa Constructs Registry.
#
# Usage:
#   constructs-auth.sh status           # Check authentication status
#   constructs-auth.sh setup <key>      # Set up API key
#   constructs-auth.sh validate         # Validate current key with registry
#   constructs-auth.sh clear            # Remove stored credentials
#
# Exit Codes:
#   0 = success / authenticated
#   1 = not authenticated
#   2 = invalid key
#   3 = network error
#
# Sources: GitHub Issue #77
# =============================================================================

set -euo pipefail

# Get script directory for sourcing dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [[ -f "$SCRIPT_DIR/constructs-lib.sh" ]]; then
    source "$SCRIPT_DIR/constructs-lib.sh"
else
    echo "ERROR: constructs-lib.sh not found" >&2
    exit 1
fi

# =============================================================================
# Configuration
# =============================================================================

CREDS_FILE="${HOME}/.loa/credentials.json"

# =============================================================================
# Status Check
# =============================================================================

cmd_status() {
    local api_key
    api_key=$(get_api_key 2>/dev/null || echo "")
    
    echo ""
    echo "╭───────────────────────────────────────────────────────────────╮"
    echo "│  CONSTRUCTS AUTHENTICATION STATUS                             │"
    echo "╰───────────────────────────────────────────────────────────────╯"
    echo ""
    
    if [[ -n "$api_key" ]]; then
        # Mask key for display
        local masked_key="${api_key:0:8}...${api_key: -4}"
        echo "  Status: ✅ Authenticated"
        echo "  Key:    $masked_key"
        
        # Check source
        if [[ -n "${LOA_CONSTRUCTS_API_KEY:-}" ]]; then
            echo "  Source: Environment variable (LOA_CONSTRUCTS_API_KEY)"
        elif [[ -f "$CREDS_FILE" ]]; then
            echo "  Source: Credentials file ($CREDS_FILE)"
        fi
        echo ""
        return 0
    else
        echo "  Status: ❌ Not authenticated"
        echo ""
        echo "  Free packs are available without authentication."
        echo "  Premium packs require an API key."
        echo ""
        echo "  To authenticate:"
        echo "    1. Get your API key from https://www.constructs.network/account"
        echo "    2. Run: /constructs auth setup"
        echo "    3. Or set: export LOA_CONSTRUCTS_API_KEY=sk_your_key"
        echo ""
        return 1
    fi
}

# =============================================================================
# Setup
# =============================================================================

cmd_setup() {
    local api_key="${1:-}"
    
    if [[ -z "$api_key" ]]; then
        echo "ERROR: API key required" >&2
        echo "" >&2
        echo "Usage: constructs-auth.sh setup <api_key>" >&2
        echo "" >&2
        echo "Get your API key from: https://www.constructs.network/account" >&2
        return 1
    fi
    
    # Validate key format
    if [[ ! "$api_key" =~ ^sk_ ]]; then
        echo "WARNING: API key should start with 'sk_'" >&2
    fi
    
    # Create credentials directory with restrictive permissions
    mkdir -p "$(dirname "$CREDS_FILE")"

    # Write credentials file with secure permissions (SHELL-004: umask before creation)
    # SHELL-012: Use jq for safe JSON construction instead of heredoc interpolation
    (
        umask 077
        jq -n --arg key "$api_key" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '{api_key: $key, created_at: $date}' > "$CREDS_FILE"
    )
    
    echo ""
    echo "✅ API key saved to $CREDS_FILE"
    echo ""
    
    # Validate with registry
    echo "Validating with registry..."
    if cmd_validate; then
        echo ""
        echo "You now have access to premium packs."
        echo "Run /constructs to browse available packs."
        return 0
    else
        echo ""
        echo "WARNING: Key saved but validation failed."
        echo "The key may be invalid or the registry may be unavailable."
        return 2
    fi
}

# =============================================================================
# Validate
# =============================================================================

cmd_validate() {
    local api_key
    api_key=$(get_api_key 2>/dev/null || echo "")
    
    if [[ -z "$api_key" ]]; then
        echo "❌ No API key configured" >&2
        return 1
    fi
    
    local registry_url
    registry_url=$(get_registry_url)
    
    # Try to access authenticated endpoint
    local response
    local http_code
    
    # SHELL-002: Use curl config file to avoid exposing API key in process list
    local curl_config
    curl_config=$(mktemp)
    chmod 600 "$curl_config"
    echo "header = \"Authorization: Bearer ${api_key}\"" > "$curl_config"

    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --config "$curl_config" \
        "${registry_url}/auth/validate" 2>/dev/null || echo "000")
    rm -f "$curl_config"
    
    case "$http_code" in
        200|204)
            echo "✅ API key is valid"
            return 0
            ;;
        401|403)
            echo "❌ API key is invalid or expired" >&2
            return 2
            ;;
        000)
            echo "❌ Could not reach registry (network error)" >&2
            return 3
            ;;
        *)
            echo "❌ Unexpected response: HTTP $http_code" >&2
            return 3
            ;;
    esac
}

# =============================================================================
# Clear
# =============================================================================

cmd_clear() {
    if [[ -f "$CREDS_FILE" ]]; then
        rm -f "$CREDS_FILE"
        echo "✅ Credentials removed from $CREDS_FILE"
    else
        echo "No credentials file found."
    fi
    
    if [[ -n "${LOA_CONSTRUCTS_API_KEY:-}" ]]; then
        echo ""
        echo "NOTE: LOA_CONSTRUCTS_API_KEY environment variable is still set."
        echo "Run: unset LOA_CONSTRUCTS_API_KEY"
    fi
    
    return 0
}

# =============================================================================
# JSON Output (for UI integration)
# =============================================================================

cmd_status_json() {
    local api_key
    api_key=$(get_api_key 2>/dev/null || echo "")
    
    if [[ -n "$api_key" ]]; then
        local source="unknown"
        if [[ -n "${LOA_CONSTRUCTS_API_KEY:-}" ]]; then
            source="env"
        elif [[ -f "$CREDS_FILE" ]]; then
            source="file"
        fi
        
        cat << EOF
{
  "authenticated": true,
  "source": "$source",
  "key_preview": "${api_key:0:8}...${api_key: -4}"
}
EOF
    else
        cat << EOF
{
  "authenticated": false,
  "source": null,
  "key_preview": null
}
EOF
    fi
}

# =============================================================================
# Main
# =============================================================================

show_help() {
    cat << 'HELP'
Loa Constructs Authentication

Usage:
  constructs-auth.sh status           Check authentication status
  constructs-auth.sh setup <key>      Set up API key
  constructs-auth.sh validate         Validate current key
  constructs-auth.sh clear            Remove stored credentials
  constructs-auth.sh status --json    Status as JSON (for UI)

Get your API key:
  https://www.constructs.network/account

Examples:
  constructs-auth.sh status
  constructs-auth.sh setup sk_live_xxxxxxxxxxxx
  constructs-auth.sh validate
HELP
}

main() {
    local cmd="${1:-status}"
    shift || true
    
    case "$cmd" in
        status)
            if [[ "${1:-}" == "--json" ]]; then
                cmd_status_json
            else
                cmd_status
            fi
            ;;
        setup)
            cmd_setup "$@"
            ;;
        validate)
            cmd_validate
            ;;
        clear)
            cmd_clear
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            show_help >&2
            exit 1
            ;;
    esac
}

main "$@"
