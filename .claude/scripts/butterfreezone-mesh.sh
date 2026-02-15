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

SCRIPT_VERSION="1.1.0"
SCHEMA_VERSION="1.0"
FORMAT="json"
OUTPUT=""
NO_CACHE="false"
CACHE_TTL="3600"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -lt 2 ]] && { echo "ERROR: --output requires a value" >&2; exit 1; }
            OUTPUT="$2"; shift 2 ;;
        --format)
            [[ $# -lt 2 ]] && { echo "ERROR: --format requires a value" >&2; exit 1; }
            FORMAT="$2"; shift 2 ;;
        --no-cache)
            NO_CACHE="true"; shift ;;
        --cache-ttl)
            [[ $# -lt 2 ]] && { echo "ERROR: --cache-ttl requires a value" >&2; exit 1; }
            CACHE_TTL="$2"; shift 2 ;;
        --schema)
            cat <<'SCHEMA'
BUTTERFREEZONE Mesh Schema v1.0

Nodes: { repo, name, type, purpose, version, interfaces }
Edges: { from, to, role, interface, protocol }

Forward compatibility: consumers MUST ignore unknown fields.
Planned v1.1 additions: nodes.capabilities, nodes.trust_level, edges.trust_level
SCHEMA
            exit 0
            ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# //;s/^#//' | head -20
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Validate format
if [[ "$FORMAT" != "json" && "$FORMAT" != "markdown" && "$FORMAT" != "mermaid" ]]; then
    echo "ERROR: --format must be 'json', 'markdown', or 'mermaid'" >&2
    exit 1
fi

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

# =============================================================================
# Helper Functions
# =============================================================================

parse_agent_context() {
    local file="$1"
    sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "$file" 2>/dev/null | \
        grep -v '^\s*<!--' | grep -v '^\s*-->' | grep -v '^\s*$'
}

get_field() {
    local block="$1"
    local field="$2"
    echo "$block" | grep "^${field}:" | sed "s/^${field}: *//" | head -1
}

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
            if [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
                break
            fi
            entries="${entries}${line}"$'\n'
        fi
    done <<< "$block"

    echo "$entries"
}

# Fetch remote BUTTERFREEZONE.md content (HIGH-1 fix: check encoding field)
fetch_remote_bfz() {
    local repo="$1"

    # Validate repo slug format (owner/name)
    if [[ ! "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        echo "WARN: Invalid repo slug: ${repo}" >&2
        return 0
    fi

    local response
    response=$(gh api "repos/${repo}/contents/BUTTERFREEZONE.md" 2>/dev/null) || {
        echo "WARN: Failed to fetch from ${repo}" >&2
        return 0
    }

    if [[ -z "$response" || "$response" == "null" ]]; then
        echo "WARN: No BUTTERFREEZONE.md found in ${repo}" >&2
        return 0
    fi

    # Check encoding — GitHub returns 'base64' for files <=1MB, 'none' for larger
    local encoding
    encoding=$(echo "$response" | jq -r '.encoding // ""') || true
    if [[ "$encoding" != "base64" ]]; then
        echo "WARN: ${repo} BUTTERFREEZONE.md too large or unexpected encoding: ${encoding}" >&2
        return 0
    fi

    echo "$response" | jq -r '.content' | base64 -d 2>/dev/null || true
}

# Fetch with caching support (sprint-112, Task 7.2)
fetch_remote_bfz_cached() {
    local repo="$1"
    local cache_dir=".run/mesh-cache"
    local cache_key="${repo//\//_}.json"
    local cache_file="${cache_dir}/${cache_key}"

    mkdir -p "$cache_dir" 2>/dev/null || true

    # Check cache
    if [[ "$NO_CACHE" != "true" && -f "$cache_file" ]]; then
        local fetched_at now age
        fetched_at=$(jq -r '.fetched_at' "$cache_file" 2>/dev/null) || fetched_at=0
        now=$(date +%s)
        age=$((now - fetched_at))

        if [[ "$age" -lt "$CACHE_TTL" ]]; then
            echo "Using cached: ${repo} (${age}s old)" >&2
            jq -r '.content' "$cache_file" 2>/dev/null
            return 0
        fi
    fi

    # Fetch fresh
    local content
    content=$(fetch_remote_bfz "$repo")

    # Cache result (atomic write-then-rename to prevent concurrent corruption)
    if [[ -n "$content" ]]; then
        local tmp_file="${cache_file}.$$"
        jq -n \
            --arg content "$content" \
            --argjson fetched_at "$(date +%s)" \
            '{fetched_at: $fetched_at, content: $content}' \
            > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$cache_file" || rm -f "$tmp_file"
    fi

    echo "$content"
}

# Process a single ecosystem entry: fetch remote BFZ, add node and edge to mesh
process_ecosystem_entry() {
    local entry_repo="$1"
    local entry_role="$2"
    local entry_iface="$3"
    local entry_proto="$4"
    local from_repo="$5"

    echo "Fetching: ${entry_repo}..." >&2
    local remote_content
    remote_content=$(fetch_remote_bfz_cached "$entry_repo")

    local r_name="" r_type="" r_purpose="" r_version="" r_interfaces=""
    if [[ -n "$remote_content" ]]; then
        local remote_block
        remote_block=$(echo "$remote_content" | sed -n '/<!-- AGENT-CONTEXT/,/-->/p' | \
            grep -v '^\s*<!--' | grep -v '^\s*-->' | grep -v '^\s*$')
        r_name=$(echo "$remote_block" | grep "^name:" | sed 's/^name: *//' | head -1) || true
        r_type=$(echo "$remote_block" | grep "^type:" | sed 's/^type: *//' | head -1) || true
        r_purpose=$(echo "$remote_block" | grep "^purpose:" | sed 's/^purpose: *//' | head -1) || true
        r_version=$(echo "$remote_block" | grep "^version:" | sed 's/^version: *//' | head -1) || true
        r_interfaces=$(echo "$remote_block" | grep "^interfaces:" | sed 's/^interfaces: *//' | head -1) || true
    fi

    local node_json
    node_json=$(jq -n \
        --arg repo "$entry_repo" \
        --arg name "${r_name:-$(basename "$entry_repo")}" \
        --arg type "${r_type:-unknown}" \
        --arg purpose "${r_purpose:-}" \
        --arg version "${r_version:-unknown}" \
        --arg interfaces "${r_interfaces:-}" \
        '{repo: $repo, name: $name, type: $type, purpose: $purpose, version: $version, interfaces: $interfaces}')
    nodes_json=$(echo "$nodes_json" | jq ". + [$node_json]")

    local edge_json
    edge_json=$(jq -n \
        --arg from "$from_repo" \
        --arg to "$entry_repo" \
        --arg role "$entry_role" \
        --arg interface "$entry_iface" \
        --arg protocol "$entry_proto" \
        '{from: $from, to: $to, role: $role, interface: $interface, protocol: $protocol}')
    edges_json=$(echo "$edges_json" | jq ". + [$edge_json]")
}

# =============================================================================
# Main
# =============================================================================

main() {
    local local_block
    local_block=$(parse_agent_context "$BFZ")
    local local_name local_type local_purpose local_version local_interfaces
    local_name=$(get_field "$local_block" "name")
    local_type=$(get_field "$local_block" "type")
    local_purpose=$(get_field "$local_block" "purpose")
    local_version=$(get_field "$local_block" "version")
    local_interfaces=$(get_field "$local_block" "interfaces")

    # Get repo slug from git remote (sanitize query params)
    local local_repo
    local_repo=$(git remote get-url origin 2>/dev/null | sed 's|.*github\.com[:/]||;s|\.git.*||') || local_repo="unknown"

    local eco_entries
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

    # Process ecosystem entries (use fd 3 to prevent inner commands from consuming stdin)
    local current_repo="" current_role="" current_iface="" current_proto=""
    while IFS= read -r line <&3; do
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*repo:[[:space:]]*(.*) ]]; then
            # Process previous entry if exists
            if [[ -n "$current_repo" ]]; then
                process_ecosystem_entry "$current_repo" "$current_role" "$current_iface" "$current_proto" "$local_repo"
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
    done 3<<< "$eco_entries"

    # Process last entry
    if [[ -n "$current_repo" ]]; then
        process_ecosystem_entry "$current_repo" "$current_role" "$current_iface" "$current_proto" "$local_repo"
    fi

    local generated_at
    generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ "$FORMAT" == "json" ]]; then
        local mesh
        mesh=$(jq -n \
            --arg schema_version "$SCHEMA_VERSION" \
            --arg mesh_version "$SCRIPT_VERSION" \
            --arg generated_at "$generated_at" \
            --arg root_repo "$local_repo" \
            --arg schema_contract "Consumers MUST ignore unknown fields for forward compatibility" \
            --argjson nodes "$nodes_json" \
            --argjson edges "$edges_json" \
            '{schema_version: $schema_version, mesh_version: $mesh_version, generated_at: $generated_at, root_repo: $root_repo, schema_contract: $schema_contract, nodes: $nodes, edges: $edges}')

        if [[ -n "$OUTPUT" ]]; then
            echo "$mesh" > "$OUTPUT"
            echo "Mesh written to: $OUTPUT" >&2
        else
            echo "$mesh"
        fi
    elif [[ "$FORMAT" == "markdown" ]]; then
        local md
        md="# BUTTERFREEZONE Mesh — ${local_name}\n\n"
        md="${md}Generated: ${generated_at} | Schema: v${SCHEMA_VERSION}\n\n"
        md="${md}## Nodes\n\n"
        md="${md}| Repo | Name | Type | Version | Purpose |\n"
        md="${md}|------|------|------|---------|--------|\n"
        md="${md}$(echo "$nodes_json" | jq -r '.[] | "| \(.repo) | \(.name) | \(.type) | \(.version) | \(.purpose[:80] | gsub("\\|"; "\\\\|")) |"')\n\n"
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
    elif [[ "$FORMAT" == "mermaid" ]]; then
        local mermaid="graph LR\n"

        # Add nodes
        local node_count
        node_count=$(echo "$nodes_json" | jq 'length')
        local i
        for ((i=0; i<node_count; i++)); do
            local node_name node_type
            node_name=$(echo "$nodes_json" | jq -r ".[$i].name")
            node_type=$(echo "$nodes_json" | jq -r ".[$i].type")
            # Sanitize for Mermaid (remove special chars)
            local safe_name="${node_name//[^a-zA-Z0-9_-]/}"
            mermaid="${mermaid}    ${safe_name}[\"${node_name}<br/>${node_type}\"]\n"
        done

        # Add edges
        local edge_count
        edge_count=$(echo "$edges_json" | jq 'length')
        for ((i=0; i<edge_count; i++)); do
            local from_repo to_repo role
            from_repo=$(echo "$edges_json" | jq -r ".[$i].from")
            to_repo=$(echo "$edges_json" | jq -r ".[$i].to")
            role=$(echo "$edges_json" | jq -r ".[$i].role")
            local from_name to_name
            from_name=$(basename "$from_repo")
            to_name=$(basename "$to_repo")
            local safe_from="${from_name//[^a-zA-Z0-9_-]/}"
            local safe_to="${to_name//[^a-zA-Z0-9_-]/}"
            mermaid="${mermaid}    ${safe_from} -->|${role}| ${safe_to}\n"
        done

        if [[ -n "$OUTPUT" ]]; then
            printf '%b' "$mermaid" > "$OUTPUT"
            echo "Mermaid diagram written to: $OUTPUT" >&2
        else
            printf '%b' "$mermaid"
        fi
    fi
}

main
