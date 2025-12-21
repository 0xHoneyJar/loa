#!/bin/bash
# Analytics helper functions for Loa framework
# These functions are designed to work cross-platform and fail gracefully

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
    local analytics_file="loa-grimoire/analytics/usage.json"
    local analytics_dir="loa-grimoire/analytics"

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
    local file="loa-grimoire/analytics/usage.json"

    if command -v jq &>/dev/null; then
        local tmp=$(mktemp)
        jq "$field = $value" "$file" > "$tmp" && mv "$tmp" "$file"
    fi
}

# Check user type from setup marker
get_user_type() {
    if [ -f ".loa-setup-complete" ]; then
        grep -o '"user_type": *"[^"]*"' .loa-setup-complete 2>/dev/null | cut -d'"' -f4
    else
        echo "unknown"
    fi
}

# Check if analytics should be tracked (THJ users only)
should_track_analytics() {
    local user_type=$(get_user_type)
    [ "$user_type" = "thj" ]
}
