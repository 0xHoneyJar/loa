#!/usr/bin/env bash
# butterfreezone-mesh.sh — Cross-repo capability graph aggregation
#
# Reads ecosystem entries from local BUTTERFREEZONE.md AGENT-CONTEXT,
# fetches linked repositories' BUTTERFREEZONE.md via GitHub API,
# and outputs a unified capability index as JSON or Markdown.
#
# Usage:
#   butterfreezone-mesh.sh [OPTIONS]
#
# Options:
#   --output FILE     Write output to FILE (default: stdout)
#   --format FORMAT   Output format: json (default) or markdown
#   --help            Show this help message
#
# Dependencies: gh (GitHub CLI), jq, sed, awk
#
# Part of the Loa Framework — Cross-Repo Agent Legibility (cycle-017)

set -euo pipefail

SCRIPT_VERSION="1.0.0"
FORMAT="json"
OUTPUT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        --format) FORMAT="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# //;s/^#//' | head -20
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Validate dependencies
for cmd in gh jq sed awk; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: Required command '$cmd' not found" >&2
        exit 1
    fi
done

# Check gh auth
if ! gh auth status &>/dev/null 2>&1; then
    echo "ERROR: gh not authenticated. Run 'gh auth login' first." >&2
    exit 1
fi

# Find BUTTERFREEZONE.md
BFZ="BUTTERFREEZONE.md"
if [[ ! -f "$BFZ" ]]; then
    echo "ERROR: $BFZ not found in current directory" >&2
    exit 1
fi

# Parse local AGENT-CONTEXT
parse_agent_context() {
    local file="$1"
    sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$file" 2>/dev/null | \
        grep -v '^\s*<!--' | grep -v '^\s*-->' | grep -v '^\s*$'
}

# Extract simple field from AGENT-CONTEXT block
get_field() {
    local block="$1"
    local field="$2"
    echo "$block" | grep "^${field}:" | sed "s/^${field}: *//" | head -1
}

# Parse ecosystem entries from AGENT-CONTEXT
parse_ecosystem() {
    local block="$1"
    local in_eco=false
    local entries=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^ecosystem: ]]; then
            in_eco=true
            continue
        fi
        if [[ "$in_eco" == true ]]; then
            # Exit on next top-level field
            if [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            entries="${entries}${line}"$'\n'
        fi
    done <<< "$block"

    echo "$entries"
}

# Fetch remote BUTTERFREEZONE.md content
fetch_remote_bfz() {
    local repo="$1"
    local content
    content=$(gh api "repos/${repo}/contents/BUTTERFREEZONE.md" --jq '.content' 2>/dev/null) || true

    if [[ -z "$content" || "$content" == "null" ]]; then
        echo "" >&2
        echo "WARN: No BUTTERFREEZONE.md found in ${repo}" >&2
        return 0
    fi

    # GitHub API returns base64 content
    echo "$content" | base64 -d 2>/dev/null || true
}

# Build mesh
local_block=$(parse_agent_context "$BFZ")
local_name=$(get_field "$local_block" "name")
local_type=$(get_field "$local_block" "type")
local_purpose=$(get_field "$local_block" "purpose")
local_version=$(get_field "$local_block" "version")
local_interfaces=$(get_field "$local_block" "interfaces")

# Get repo slug from git remote
local_repo=$(git remote get-url origin 2>/dev/null | sed 's|.*github\.com[:/]||;s|\.git$||') || local_repo="unknown"

eco_entries=$(parse_ecosystem "$local_block")

# Build nodes array starting with local
nodes_json="[$(jq -n \
    --arg repo "$local_repo" \
    --arg name "$local_name" \
    --arg type "$local_type" \
    --arg purpose "$local_purpose" \
    --arg version "$local_version" \
    --arg interfaces "$local_interfaces" \
    '{repo: $repo, name: $name, type: $type, purpose: $purpose, version: $version, interfaces: $interfaces}'
)]"

edges_json="[]"

# Process ecosystem entries
current_repo="" current_role="" current_iface="" current_proto=""
while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*repo:[[:space:]]*(.*) ]]; then
        # Save previous entry
        if [[ -n "$current_repo" ]]; then
            # Fetch remote BUTTERFREEZONE
            echo "Fetching: ${current_repo}..." >&2
            remote_content=$(fetch_remote_bfz "$current_repo")
            remote_name="" remote_type="" remote_purpose="" remote_version="" remote_interfaces=""
            if [[ -n "$remote_content" ]]; then
                remote_block=$(echo "$remote_content" | sed -n '/<!-- AGENT-CONTEXT/,/-->/p' | \
                    grep -v '^\s*<!--' | grep -v '^\s*-->' | grep -v '^\s*$')
                remote_name=$(echo "$remote_block" | grep "^name:" | sed 's/^name: *//' | head -1)
                remote_type=$(echo "$remote_block" | grep "^type:" | sed 's/^type: *//' | head -1)
                remote_purpose=$(echo "$remote_block" | grep "^purpose:" | sed 's/^purpose: *//' | head -1)
                remote_version=$(echo "$remote_block" | grep "^version:" | sed 's/^version: *//' | head -1)
                remote_interfaces=$(echo "$remote_block" | grep "^interfaces:" | sed 's/^interfaces: *//' | head -1)
            fi

            node_json=$(jq -n \
                --arg repo "$current_repo" \
                --arg name "${remote_name:-$(basename "$current_repo")}" \
                --arg type "${remote_type:-unknown}" \
                --arg purpose "${remote_purpose:-}" \
                --arg version "${remote_version:-unknown}" \
                --arg interfaces "${remote_interfaces:-}" \
                '{repo: $repo, name: $name, type: $type, purpose: $purpose, version: $version, interfaces: $interfaces}')
            nodes_json=$(echo "$nodes_json" | jq ". + [$node_json]")

            edge_json=$(jq -n \
                --arg from "$local_repo" \
                --arg to "$current_repo" \
                --arg role "$current_role" \
                --arg interface "$current_iface" \
                --arg protocol "$current_proto" \
                '{from: $from, to: $to, role: $role, interface: $interface, protocol: $protocol}')
            edges_json=$(echo "$edges_json" | jq ". + [$edge_json]")
        fi

        current_repo="${BASH_REMATCH[1]}"
        current_role="" current_iface="" current_proto=""
    elif [[ "$line" =~ ^[[:space:]]*role:[[:space:]]*(.*) ]]; then
        current_role="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*interface:[[:space:]]*(.*) ]]; then
        current_iface="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^[[:space:]]*protocol:[[:space:]]*(.*) ]]; then
        current_proto="${BASH_REMATCH[1]}"
    fi
done <<< "$eco_entries"

# Process last entry
if [[ -n "$current_repo" ]]; then
    echo "Fetching: ${current_repo}..." >&2
    remote_content=$(fetch_remote_bfz "$current_repo")
    remote_name="" remote_type="" remote_purpose="" remote_version="" remote_interfaces=""
    if [[ -n "$remote_content" ]]; then
        remote_block=$(echo "$remote_content" | sed -n '/<!-- AGENT-CONTEXT/,/-->/p' | \
            grep -v '^\s*<!--' | grep -v '^\s*-->' | grep -v '^\s*$')
        remote_name=$(echo "$remote_block" | grep "^name:" | sed 's/^name: *//' | head -1)
        remote_type=$(echo "$remote_block" | grep "^type:" | sed 's/^type: *//' | head -1)
        remote_purpose=$(echo "$remote_block" | grep "^purpose:" | sed 's/^purpose: *//' | head -1)
        remote_version=$(echo "$remote_block" | grep "^version:" | sed 's/^version: *//' | head -1)
        remote_interfaces=$(echo "$remote_block" | grep "^interfaces:" | sed 's/^interfaces: *//' | head -1)
    fi

    node_json=$(jq -n \
        --arg repo "$current_repo" \
        --arg name "${remote_name:-$(basename "$current_repo")}" \
        --arg type "${remote_type:-unknown}" \
        --arg purpose "${remote_purpose:-}" \
        --arg version "${remote_version:-unknown}" \
        --arg interfaces "${remote_interfaces:-}" \
        '{repo: $repo, name: $name, type: $type, purpose: $purpose, version: $version, interfaces: $interfaces}')
    nodes_json=$(echo "$nodes_json" | jq ". + [$node_json]")

    edge_json=$(jq -n \
        --arg from "$local_repo" \
        --arg to "$current_repo" \
        --arg role "$current_role" \
        --arg interface "$current_iface" \
        --arg protocol "$current_proto" \
        '{from: $from, to: $to, role: $role, interface: $interface, protocol: $protocol}')
    edges_json=$(echo "$edges_json" | jq ". + [$edge_json]")
fi

generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [[ "$FORMAT" == "json" ]]; then
    mesh=$(jq -n \
        --arg version "$SCRIPT_VERSION" \
        --arg generated_at "$generated_at" \
        --arg root_repo "$local_repo" \
        --argjson nodes "$nodes_json" \
        --argjson edges "$edges_json" \
        '{mesh_version: $version, generated_at: $generated_at, root_repo: $root_repo, nodes: $nodes, edges: $edges}')

    if [[ -n "$OUTPUT" ]]; then
        echo "$mesh" > "$OUTPUT"
        echo "Mesh written to: $OUTPUT" >&2
    else
        echo "$mesh"
    fi
elif [[ "$FORMAT" == "markdown" ]]; then
    md="# BUTTERFREEZONE Mesh — ${local_name}\n\n"
    md="${md}Generated: ${generated_at}\n\n"
    md="${md}## Nodes\n\n"
    md="${md}| Repo | Name | Type | Version | Purpose |\n"
    md="${md}|------|------|------|---------|--------|\n"
    md="${md}$(echo "$nodes_json" | jq -r '.[] | "| \(.repo) | \(.name) | \(.type) | \(.version) | \(.purpose[:80]) |"')\n\n"
    md="${md}## Edges\n\n"
    md="${md}| From | To | Role | Interface | Protocol |\n"
    md="${md}|------|-----|------|-----------|----------|\n"
    md="${md}$(echo "$edges_json" | jq -r '.[] | "| \(.from) | \(.to) | \(.role) | \(.interface) | \(.protocol) |"')\n"

    if [[ -n "$OUTPUT" ]]; then
        printf '%b' "$md" > "$OUTPUT"
        echo "Mesh written to: $OUTPUT" >&2
    else
        printf '%b' "$md"
    fi
fi
