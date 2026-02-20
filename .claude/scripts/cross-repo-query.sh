#!/usr/bin/env bash
# cross-repo-query.sh — Cross-repository pattern matching for bridge reviews (FR-1)
#
# Extracts patterns from a PR diff, resolves ecosystem sibling repos,
# queries their reality files, and outputs structured JSON matches.
#
# Usage:
#   cross-repo-query.sh --diff <diff-file> [--ecosystem <repos>] [--output <file>]
#                       [--budget <tokens>] [--max-repos <n>] [--timeout <seconds>]
#
# Resolution order: sibling directory → config override → REMOTE: GitHub API fallback
#
# Exit codes:
#   0 - Success (matches or empty)
#   1 - Error
#   2 - Invalid arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

# =============================================================================
# Defaults
# =============================================================================

DIFF_FILE=""
ECOSYSTEM_OVERRIDE=""
OUTPUT_FILE=""
BUDGET=2000
MAX_REPOS=5
PER_REPO_TIMEOUT=5
TOTAL_TIMEOUT=15

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --diff)
            DIFF_FILE="${2:-}"
            shift 2 ;;
        --ecosystem)
            ECOSYSTEM_OVERRIDE="${2:-}"
            shift 2 ;;
        --output)
            OUTPUT_FILE="${2:-}"
            shift 2 ;;
        --budget)
            BUDGET="${2:-2000}"
            shift 2 ;;
        --max-repos)
            MAX_REPOS="${2:-5}"
            shift 2 ;;
        --timeout)
            TOTAL_TIMEOUT="${2:-15}"
            shift 2 ;;
        -h|--help)
            echo "Usage: cross-repo-query.sh --diff <file> [--ecosystem <repos>] [--output <file>]"
            echo "       [--budget <tokens>] [--max-repos <n>] [--timeout <seconds>]"
            exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2 ;;
    esac
done

if [[ -z "$DIFF_FILE" ]]; then
    echo "ERROR: --diff is required" >&2
    exit 2
fi

if [[ ! -f "$DIFF_FILE" ]]; then
    echo "ERROR: Diff file not found: $DIFF_FILE" >&2
    exit 2
fi

# =============================================================================
# Pattern Extraction from Diff
# =============================================================================

# Extract meaningful patterns from a diff file for cross-repo search.
# Returns newline-separated list of search terms.
extract_patterns() {
    local diff_file="$1"
    local patterns=()

    # 1. Extract function/method names from added lines
    local func_names
    func_names=$(grep '^+' "$diff_file" 2>/dev/null | \
        grep -oE '(function|def|fn|func)\s+[a-zA-Z_][a-zA-Z0-9_]*' 2>/dev/null | \
        sed 's/^.*\s//' | sort -u | head -20) || true

    # 2. Extract architectural keywords from diff context
    local arch_keywords
    arch_keywords=$(grep -oiE '(orchestrat|bridge|flatline|cascade|convergence|invariant|constraint|pipeline|middleware|adapter|provider|factory|singleton|observer|strategy)' \
        "$diff_file" 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u | head -10) || true

    # 3. Extract protocol/config references
    local protocol_refs
    protocol_refs=$(grep -oE '\.(protocol|config|schema|spec)\b' "$diff_file" 2>/dev/null | \
        sed 's/^\.//' | sort -u) || true

    # 4. Extract file path components (architectural signals)
    local path_keywords
    path_keywords=$(grep '^diff --git' "$diff_file" 2>/dev/null | \
        sed 's|diff --git a/||;s| b/.*||' | \
        tr '/' '\n' | grep -vE '^(\.|src|lib|scripts|tests|index|utils)$' | \
        sort -u | head -10) || true

    # Stop-words: common short names that match everywhere
    local stop_words="init main run get set test log new add del put err cmd ctx buf src dst tmp fmt cfg env req res msg val key len idx num str var arg opt max min"

    # Combine all patterns, filter noise
    {
        echo "$func_names"
        echo "$arch_keywords"
        echo "$protocol_refs"
        echo "$path_keywords"
    } | grep -v '^$' | sort -u | while IFS= read -r pat; do
        # Skip patterns shorter than 4 characters
        [[ ${#pat} -lt 4 ]] && continue
        # Skip stop-words
        local is_stop=false
        for sw in $stop_words; do
            if [[ "$pat" == "$sw" ]]; then
                is_stop=true
                break
            fi
        done
        [[ "$is_stop" == "true" ]] && continue
        echo "$pat"
    done | head -30
}

# =============================================================================
# Ecosystem Repo Resolution
# =============================================================================

# Resolve ecosystem repos from multiple sources.
# Priority: CLI override → config → sibling directories
# Returns: newline-separated list of repo paths or REMOTE:<owner/repo> markers
resolve_repos() {
    local repos=()

    # Priority 1: CLI override (comma-separated)
    if [[ -n "$ECOSYSTEM_OVERRIDE" ]]; then
        echo "$ECOSYSTEM_OVERRIDE" | tr ',' '\n'
        return
    fi

    # Priority 2: Config file
    if command -v yq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
        local config_repos
        config_repos=$(yq '.run_bridge.cross_repo_query.ecosystem[]? // empty' "$CONFIG_FILE" 2>/dev/null) || true
        if [[ -n "$config_repos" ]]; then
            echo "$config_repos"
            return
        fi
    fi

    # Priority 3: Sibling directories with BUTTERFREEZONE.md or .loa.config.yaml
    local parent_dir
    parent_dir=$(dirname "$PROJECT_ROOT")
    local current_name
    current_name=$(basename "$PROJECT_ROOT")

    for sibling in "$parent_dir"/*/; do
        [[ -d "$sibling" ]] || continue
        local sib_name
        sib_name=$(basename "$sibling")
        [[ "$sib_name" == "$current_name" ]] && continue

        # Check if it's a Loa-managed repo
        if [[ -f "$sibling/BUTTERFREEZONE.md" ]] || [[ -f "$sibling/.loa.config.yaml" ]]; then
            echo "$sibling"
        fi
    done
}

# =============================================================================
# Query Execution
# =============================================================================

# Query a single local repo's reality files for pattern matches.
# Args: $1=repo_path, $2=patterns (newline-separated), $3=budget
query_local_repo() {
    local repo_path="$1"
    local patterns="$2"
    local budget="${3:-500}"

    local repo_name
    repo_name=$(basename "$repo_path")
    local matches="[]"

    # Check for qmd-context-query.sh in the repo
    local qmd_script="$repo_path/.claude/scripts/qmd-context-query.sh"
    local reality_dir="$repo_path/grimoires"

    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue

        local result=""

        # Strategy 1: qmd-context-query.sh (if available)
        if [[ -x "$qmd_script" ]]; then
            result=$(timeout "$PER_REPO_TIMEOUT" "$qmd_script" \
                --query "$pattern" --scope reality --budget "$budget" --format json \
                2>/dev/null) || true
        fi

        # Strategy 2: grep through reality files
        if [[ -z "$result" || "$result" == "[]" ]] && [[ -d "$reality_dir" ]]; then
            local grep_hits
            grep_hits=$(grep -rlF "$pattern" "$reality_dir" 2>/dev/null | head -3) || true
            if [[ -n "$grep_hits" ]]; then
                local hit_json="[]"
                while IFS= read -r hit_file; do
                    [[ -z "$hit_file" ]] && continue
                    local context
                    context=$(grep -m2 -A2 -F "$pattern" "$hit_file" 2>/dev/null | head -5) || true
                    hit_json=$(echo "$hit_json" | jq --arg src "$hit_file" --arg ctx "$context" --arg pat "$pattern" \
                        '. + [{"source": $src, "pattern": $pat, "context": $ctx, "tier": "grep"}]')
                done <<< "$grep_hits"
                result="$hit_json"
            fi
        fi

        # Accumulate matches
        if [[ -n "$result" && "$result" != "[]" && "$result" != "null" ]]; then
            matches=$(echo "$matches" | jq --argjson new "$result" '. + (if ($new | type) == "array" then $new else [$new] end)')
        fi
    done <<< "$patterns"

    # Wrap in repo envelope
    if [[ "$matches" != "[]" ]]; then
        echo "$matches" | jq --arg repo "$repo_name" --arg path "$repo_path" \
            '{repo: $repo, path: $path, matches: ., match_count: (. | length)}'
    fi
}

# Query a remote repo via GitHub API (BUTTERFREEZONE.md AGENT-CONTEXT extraction).
# Args: $1=owner/repo, $2=patterns
query_remote_repo() {
    local remote_ref="$1"
    local patterns="$2"

    # Strip REMOTE: prefix if present
    remote_ref="${remote_ref#REMOTE:}"

    if ! command -v gh &>/dev/null; then
        echo "WARNING: gh CLI not available for remote query: $remote_ref" >&2
        return
    fi

    # Fetch BUTTERFREEZONE.md from the repo
    local bfz_content
    bfz_content=$(timeout "$PER_REPO_TIMEOUT" gh api \
        "repos/${remote_ref}/contents/BUTTERFREEZONE.md" \
        --jq '.content' 2>/dev/null | base64 -d 2>/dev/null) || true

    if [[ -z "$bfz_content" ]]; then
        return
    fi

    # Search AGENT-CONTEXT section for pattern matches
    local agent_context
    agent_context=$(echo "$bfz_content" | sed -n '/<!-- AGENT-CONTEXT/,/<!-- \/AGENT-CONTEXT/p' 2>/dev/null) || true

    if [[ -z "$agent_context" ]]; then
        agent_context="$bfz_content"
    fi

    local matches="[]"
    while IFS= read -r pattern; do
        [[ -z "$pattern" ]] && continue
        if echo "$agent_context" | grep -qiF "$pattern" 2>/dev/null; then
            local context
            context=$(echo "$agent_context" | grep -m2 -B1 -A1 -iF "$pattern" 2>/dev/null | head -5) || true
            matches=$(echo "$matches" | jq --arg pat "$pattern" --arg ctx "$context" \
                '. + [{"pattern": $pat, "context": $ctx, "tier": "remote-butterfreezone"}]')
        fi
    done <<< "$patterns"

    if [[ "$matches" != "[]" ]]; then
        echo "$matches" | jq --arg repo "$remote_ref" \
            '{repo: $repo, path: ("REMOTE:" + $repo), matches: ., match_count: (. | length)}'
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    local start_time=$SECONDS

    # Extract patterns from diff
    local patterns
    patterns=$(extract_patterns "$DIFF_FILE") || true

    if [[ -z "$patterns" ]]; then
        echo '{"repos_queried": 0, "total_matches": 0, "results": []}' | \
            if [[ -n "$OUTPUT_FILE" ]]; then cat > "$OUTPUT_FILE"; else cat; fi
        exit 0
    fi

    local pattern_count
    pattern_count=$(echo "$patterns" | wc -l)

    # Resolve ecosystem repos
    local repos
    repos=$(resolve_repos)

    if [[ -z "$repos" ]]; then
        echo '{"repos_queried": 0, "total_matches": 0, "patterns_extracted": '"$pattern_count"', "results": []}' | \
            if [[ -n "$OUTPUT_FILE" ]]; then cat > "$OUTPUT_FILE"; else cat; fi
        exit 0
    fi

    # Query each repo (bounded by max-repos and total timeout)
    local results="[]"
    local repos_queried=0
    local total_matches=0

    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        [[ $repos_queried -ge $MAX_REPOS ]] && break

        # Check total timeout
        local elapsed=$((SECONDS - start_time))
        if [[ $elapsed -ge $TOTAL_TIMEOUT ]]; then
            echo "WARNING: Total timeout ($TOTAL_TIMEOUT s) exceeded after $repos_queried repos" >&2
            break
        fi

        local result=""
        if [[ "$repo" == REMOTE:* ]]; then
            result=$(query_remote_repo "$repo" "$patterns") || true
        elif [[ -d "$repo" ]]; then
            result=$(query_local_repo "$repo" "$patterns" "$BUDGET") || true
        else
            echo "WARNING: Repo not accessible: $repo" >&2
            continue
        fi

        if [[ -n "$result" && "$result" != "null" ]]; then
            local match_count
            match_count=$(echo "$result" | jq '.match_count // 0') || match_count=0
            total_matches=$((total_matches + match_count))
            results=$(echo "$results" | jq --argjson r "$result" '. + [$r]')
        fi

        repos_queried=$((repos_queried + 1))
    done <<< "$repos"

    local elapsed=$((SECONDS - start_time))

    # Output
    local output
    output=$(jq -n \
        --argjson repos_queried "$repos_queried" \
        --argjson total_matches "$total_matches" \
        --argjson patterns_extracted "$pattern_count" \
        --argjson elapsed_seconds "$elapsed" \
        --argjson results "$results" \
        '{
            repos_queried: $repos_queried,
            total_matches: $total_matches,
            patterns_extracted: $patterns_extracted,
            elapsed_seconds: $elapsed_seconds,
            results: $results
        }')

    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$output" > "$OUTPUT_FILE"
    else
        echo "$output"
    fi
}

main
