#!/usr/bin/env bash
# Analytics helper functions for Loa framework
# These functions are designed to work cross-platform and fail gracefully

set -euo pipefail

# Source path-lib if available (analytics can run early in bootstrap)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
    _ANALYTICS_DIR=$(get_analytics_dir)
else
    # Fallback for pre-bootstrap scenarios
    _ANALYTICS_DIR="grimoires/loa/analytics"
fi

# Get framework version from package.json or CHANGELOG.md
get_framework_version() {
    if [ -f "package.json" ]; then
        grep -o '"version": *"[^"]*"' package.json | head -1 | cut -d'"' -f4
    elif [ -f "CHANGELOG.md" ]; then
        grep -o '\[[0-9]\+\.[0-9]\+\.[0-9]\+\]' CHANGELOG.md | head -1 | tr -d '[]'
    else
        echo "0.0.0"
    fi
}

# Get git user identity
get_git_user() {
    local name=$(git config user.name 2>/dev/null || echo "Unknown")
    local email=$(git config user.email 2>/dev/null || echo "unknown@unknown")
    echo "${name}|${email}"
}

# Get project name from git remote or directory
get_project_name() {
    local remote=$(git remote get-url origin 2>/dev/null)
    if [ -n "$remote" ]; then
        basename -s .git "$remote"
    else
        basename "$(pwd)"
    fi
}

# Get current timestamp in ISO-8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Check which MCP servers are configured
get_configured_mcp_servers() {
    local settings=".claude/settings.local.json"
    if [ -f "$settings" ]; then
        grep -o '"[^"]*"' "$settings" | grep -v "enabledMcpjsonServers" | tr -d '"' | tr '\n' ','
    else
        echo "none"
    fi
}

# Initialize analytics file if missing
init_analytics() {
    local analytics_file="${_ANALYTICS_DIR}/usage.json"
    local analytics_dir="$_ANALYTICS_DIR"

    mkdir -p "$analytics_dir"

    if [ ! -f "$analytics_file" ]; then
        cat > "$analytics_file" << 'EOF'
{
  "schema_version": "1.0.0",
  "framework_version": null,
  "project_name": null,
  "developer": {"git_user_name": null, "git_user_email": null},
  "setup": {"completed_at": null, "mcp_servers_configured": []},
  "phases": {},
  "sprints": [],
  "reviews": [],
  "audits": [],
  "deployments": [],
  "feedback_submissions": [],
  "totals": {"commands_executed": 0, "phases_completed": 0}
}
EOF
    fi
}

# Update a field in the analytics JSON (requires jq)
update_analytics_field() {
    local field="$1"
    local value="$2"
    local file="${_ANALYTICS_DIR}/usage.json"

    if command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp) || { return 1; }
        chmod 600 "$tmp"  # CRITICAL-001 FIX: Restrict permissions
        trap "rm -f '$tmp'" EXIT
        jq "$field = $value" "$file" > "$tmp" && mv "$tmp" "$file"
        trap - EXIT  # Clear trap after successful move
    fi
}

# Source constructs-lib for is_thj_member() function
# This is the canonical source for THJ membership detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/constructs-lib.sh" ]]; then
    source "${SCRIPT_DIR}/constructs-lib.sh"
fi

# Get user type based on API key presence
# Returns "thj" if LOA_CONSTRUCTS_API_KEY is set, "oss" otherwise
get_user_type() {
    if is_thj_member 2>/dev/null; then
        echo "thj"
    else
        echo "oss"
    fi
}

# Check if analytics should be tracked (THJ users only)
# Uses API key presence as the detection mechanism
should_track_analytics() {
    is_thj_member 2>/dev/null
}
