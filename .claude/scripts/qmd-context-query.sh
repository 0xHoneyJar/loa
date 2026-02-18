#!/usr/bin/env bash
# .claude/scripts/qmd-context-query.sh
#
# Unified Context Query Interface for Loa Skills
# Three-tier fallback: QMD → CK → grep
#
# Usage:
#   qmd-context-query.sh --query "search text" --scope grimoires [--budget 2000] [--format json|text] [--timeout 5]
#
# Scopes: grimoires, skills, notes, reality, all
#
# Output:
#   JSON array of {source, score, content, tier} objects (default)
#   or plain text with headers (--format text)
#
# SDD Reference: grimoires/loa/sdd.md §4 Component Design
# Cycle: cycle-027 | Source: #364

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
QMD_SYNC="${PROJECT_ROOT}/.claude/scripts/qmd-sync.sh"

# Defaults
QUERY=""
SCOPE="grimoires"
BUDGET=2000
FORMAT="json"
TIMEOUT=5
ENABLED=true

# Resolved scope paths (populated by resolve_scope)
QMD_COLLECTION=""
CK_PATH=""
GREP_PATHS=""

# =============================================================================
# Argument Parsing
# =============================================================================

show_help() {
    cat <<'HELPEOF'
qmd-context-query.sh — Unified Context Query Interface

USAGE:
    qmd-context-query.sh --query "search text" --scope <scope> [OPTIONS]

SCOPES:
    grimoires   Search grimoire documents (NOTES, sprint plans, PRD/SDD)
    skills      Search skill definitions (.claude/skills/)
    notes       Search NOTES.md specifically
    reality     Search reality files (grimoires/loa/reality/)
    all         Search all scopes

OPTIONS:
    --query TEXT      Search query (required)
    --scope SCOPE     Search scope (default: grimoires)
    --budget N        Token budget limit (default: 2000)
    --format FORMAT   Output format: json or text (default: json)
    --timeout N       Per-tier timeout in seconds (default: 5)
    --help            Show this help

EXAMPLES:
    qmd-context-query.sh --query "authentication flow" --scope grimoires
    qmd-context-query.sh --query "NOTES blocker" --scope notes --budget 1000
    qmd-context-query.sh --query "adapter pattern" --scope all --format text
HELPEOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --query|-q)
                QUERY="$2"
                shift 2
                ;;
            --scope|-s)
                SCOPE="$2"
                shift 2
                ;;
            --budget|-b)
                BUDGET="$2"
                shift 2
                ;;
            --format|-f)
                FORMAT="$2"
                shift 2
                ;;
            --timeout|-t)
                TIMEOUT="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage" >&2
                exit 1
                ;;
        esac
    done

    # Validate required args
    if [[ -z "$QUERY" ]]; then
        echo "[]"
        exit 0
    fi

    # Validate scope
    case "$SCOPE" in
        grimoires|skills|notes|reality|all) ;;
        *)
            echo "Invalid scope: $SCOPE" >&2
            echo "[]"
            exit 0
            ;;
    esac

    # Validate budget is positive integer
    if ! [[ "$BUDGET" =~ ^[0-9]+$ ]] || [[ "$BUDGET" -le 0 ]]; then
        echo "[]"
        exit 0
    fi

    # Validate format
    case "$FORMAT" in
        json|text) ;;
        *)
            FORMAT="json"
            ;;
    esac
}

# =============================================================================
# Configuration Loading
# =============================================================================

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]] || ! command -v yq &>/dev/null; then
        return
    fi

    local cfg_enabled
    cfg_enabled=$(yq -r '.qmd_context.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
    if [[ "$cfg_enabled" == "false" ]]; then
        ENABLED=false
        return
    fi

    local cfg_budget
    cfg_budget=$(yq -r '.qmd_context.default_budget // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$cfg_budget" && "$cfg_budget" != "null" ]]; then
        # Only override if user didn't pass --budget explicitly
        # (we use 2000 as sentinel — if it's still 2000, apply config default)
        if [[ "$BUDGET" -eq 2000 ]]; then
            BUDGET="$cfg_budget"
        fi
    fi

    local cfg_timeout
    cfg_timeout=$(yq -r '.qmd_context.timeout_seconds // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$cfg_timeout" && "$cfg_timeout" != "null" && "$TIMEOUT" -eq 5 ]]; then
        TIMEOUT="$cfg_timeout"
    fi
}

# =============================================================================
# Scope Resolution
# =============================================================================

resolve_scope() {
    local scope="$1"

    # Try config first
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local cfg_qmd cfg_ck cfg_grep
        cfg_qmd=$(yq -r ".qmd_context.scopes.${scope}.qmd_collection // \"\"" "$CONFIG_FILE" 2>/dev/null || echo "")
        cfg_ck=$(yq -r ".qmd_context.scopes.${scope}.ck_path // \"\"" "$CONFIG_FILE" 2>/dev/null || echo "")
        cfg_grep=$(yq -r ".qmd_context.scopes.${scope}.grep_paths // [] | .[]" "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' || echo "")

        [[ -n "$cfg_qmd" && "$cfg_qmd" != "null" ]] && QMD_COLLECTION="$cfg_qmd"
        [[ -n "$cfg_ck" && "$cfg_ck" != "null" ]] && CK_PATH="$cfg_ck"
        [[ -n "$cfg_grep" ]] && GREP_PATHS="$cfg_grep"
    fi

    # Apply defaults for anything not set by config
    if [[ -z "$QMD_COLLECTION" ]]; then
        case "$scope" in
            grimoires|notes) QMD_COLLECTION="loa-grimoire" ;;
            skills)          QMD_COLLECTION="loa-skills" ;;
            reality)         QMD_COLLECTION="loa-reality" ;;
            all)             QMD_COLLECTION="all" ;;
        esac
    fi

    if [[ -z "$CK_PATH" ]]; then
        case "$scope" in
            grimoires|notes) CK_PATH="${PROJECT_ROOT}/.ck/loa-grimoire/" ;;
            skills)          CK_PATH="${PROJECT_ROOT}/.ck/skills/" ;;
            reality)         CK_PATH="${PROJECT_ROOT}/.ck/reality/" ;;
            all)             CK_PATH="${PROJECT_ROOT}/.ck/" ;;
        esac
    fi

    if [[ -z "$GREP_PATHS" ]]; then
        case "$scope" in
            grimoires) GREP_PATHS="${PROJECT_ROOT}/grimoires/loa/" ;;
            skills)    GREP_PATHS="${PROJECT_ROOT}/.claude/skills/" ;;
            notes)     GREP_PATHS="${PROJECT_ROOT}/grimoires/loa/NOTES.md" ;;
            reality)   GREP_PATHS="${PROJECT_ROOT}/grimoires/loa/reality/" ;;
            all)       GREP_PATHS="${PROJECT_ROOT}/grimoires/loa/ ${PROJECT_ROOT}/.claude/skills/ ${PROJECT_ROOT}/grimoires/loa/reality/" ;;
        esac
    fi
}

# =============================================================================
# Tier 1: QMD Search
# =============================================================================

try_qmd() {
    local query="$1"
    local collection="$2"
    local tier_timeout="$3"

    # Check if QMD sync script exists
    if [[ ! -f "$QMD_SYNC" ]]; then
        echo "[]"
        return
    fi

    # Check if qmd binary is available (quick check)
    if ! command -v qmd &>/dev/null; then
        echo "[]"
        return
    fi

    local result
    if [[ "$collection" == "all" ]]; then
        result=$(timeout "${tier_timeout}s" \
            "$QMD_SYNC" query "$query" 2>/dev/null) || { echo "[]"; return; }
    else
        result=$(timeout "${tier_timeout}s" \
            "$QMD_SYNC" query "$query" \
            --collection "$collection" 2>/dev/null) || { echo "[]"; return; }
    fi

    # Validate JSON
    if echo "$result" | jq empty 2>/dev/null; then
        # Normalize to our format: ensure source, score, content fields
        echo "$result" | jq '[.[] | {
            source: (.file // .source // "unknown"),
            score: (.score // 0.5),
            content: (.snippet // .content // .text // "")
        }]' 2>/dev/null || echo "[]"
    else
        echo "[]"
    fi
}

# =============================================================================
# Tier 2: CK Search
# =============================================================================

try_ck() {
    local query="$1"
    local ck_path="$2"
    local tier_timeout="$3"

    # Check if ck binary is available
    if ! command -v ck &>/dev/null; then
        echo "[]"
        return
    fi

    # Check if CK path exists
    if [[ ! -e "$ck_path" ]]; then
        echo "[]"
        return
    fi

    local raw
    raw=$(timeout "${tier_timeout}s" \
        ck --hybrid "$query" \
        --limit 10 \
        --threshold 0.5 \
        --jsonl "$ck_path" 2>/dev/null) || { echo "[]"; return; }

    if [[ -z "$raw" ]]; then
        echo "[]"
        return
    fi

    # Transform JSONL to our JSON array format
    echo "$raw" | jq -s '[.[] | {
        source: (.file // "unknown"),
        score: (.score // 0.5),
        content: (.snippet // .text // "")
    }]' 2>/dev/null || echo "[]"
}

# =============================================================================
# Tier 3: Grep Search (terminal fallback — must always succeed)
# =============================================================================

try_grep() {
    local query="$1"
    local paths="$2"

    # Extract keywords (max 5, lowercase)
    local keywords
    keywords=$(echo "$query" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | grep -v '^$' | head -5)

    if [[ -z "$keywords" ]]; then
        echo "[]"
        return
    fi

    # Build grep OR pattern from keywords
    local pattern=""
    while IFS= read -r word; do
        [[ -z "$word" ]] && continue
        if [[ -z "$pattern" ]]; then
            pattern="$word"
        else
            pattern="${pattern}\\|${word}"
        fi
    done <<< "$keywords"

    if [[ -z "$pattern" ]]; then
        echo "[]"
        return
    fi

    local results=()

    # shellcheck disable=SC2086
    for path in $paths; do
        # Validate path exists and is within PROJECT_ROOT
        [[ -e "$path" ]] || continue

        local real_path
        real_path=$(realpath "$path" 2>/dev/null) || continue
        if [[ ! "$real_path" =~ ^"$PROJECT_ROOT" ]]; then
            continue
        fi

        # Search for matching files
        local matching_files
        matching_files=$(grep -r -l -i "$pattern" "$path" 2>/dev/null | head -10) || true

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            [[ -f "$file" ]] || continue

            local snippet
            snippet=$(grep -i -m1 "$pattern" "$file" 2>/dev/null | head -c 200 || echo "")
            # JSON-escape the snippet
            snippet=$(printf '%s' "$snippet" | jq -Rs '.' 2>/dev/null || echo '""')
            # Strip outer quotes for embedding
            snippet=${snippet#\"}
            snippet=${snippet%\"}

            # Make source path relative to PROJECT_ROOT
            local rel_path="${file#"$PROJECT_ROOT"/}"

            results+=("{\"source\":\"${rel_path}\",\"score\":0.5,\"content\":\"${snippet}\"}")
        done <<< "$matching_files"
    done

    if [[ ${#results[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${results[@]}" | jq -s '.' 2>/dev/null || echo "[]"
    fi
}

# =============================================================================
# Tier Annotation
# =============================================================================

annotate_tier() {
    local results="$1"
    local tier="$2"

    if [[ "$results" == "[]" || -z "$results" ]]; then
        echo "[]"
        return
    fi

    echo "$results" | jq --arg tier "$tier" '[.[] | . + {tier: $tier}]' 2>/dev/null || echo "$results"
}

# =============================================================================
# Token Budget Enforcement
# =============================================================================

apply_token_budget() {
    local results="$1"
    local budget="$2"

    if [[ "$results" == "[]" || -z "$results" || "$budget" -le 0 ]]; then
        echo "[]"
        return
    fi

    # Sort by score descending, then accumulate within budget
    # Token estimate: word_count × 1.3
    echo "$results" | jq --argjson budget "$budget" '
        sort_by(-.score) |
        reduce .[] as $item (
            {items: [], tokens: 0};
            ($item.content | split(" ") | length) as $words |
            (($words * 13 + 9) / 10 | floor) as $item_tokens |
            if (.tokens + $item_tokens) <= $budget then
                .items += [$item] |
                .tokens += $item_tokens
            else
                .
            end
        ) |
        .items
    ' 2>/dev/null || echo "$results"
}

# =============================================================================
# Three-Tier Fallback
# =============================================================================

try_tiers() {
    local results=""

    # Tier 1: QMD
    if [[ -n "$QMD_COLLECTION" ]]; then
        results=$(try_qmd "$QUERY" "$QMD_COLLECTION" "$TIMEOUT")
        if [[ -n "$results" && "$results" != "[]" ]]; then
            annotate_tier "$results" "qmd"
            return
        fi
    fi

    # Tier 2: CK
    if [[ -n "$CK_PATH" ]]; then
        results=$(try_ck "$QUERY" "$CK_PATH" "$TIMEOUT")
        if [[ -n "$results" && "$results" != "[]" ]]; then
            annotate_tier "$results" "ck"
            return
        fi
    fi

    # Tier 3: grep (always available)
    results=$(try_grep "$QUERY" "$GREP_PATHS")
    annotate_tier "$results" "grep"
}

# =============================================================================
# Output Formatting
# =============================================================================

format_text() {
    local results="$1"

    if [[ "$results" == "[]" || -z "$results" ]]; then
        return
    fi

    echo "$results" | jq -r '.[] | "--- \(.source) (score: \(.score), tier: \(.tier // "unknown")) ---\n\(.content)\n"' 2>/dev/null
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    load_config

    # Early exit if disabled
    if [[ "$ENABLED" == "false" ]]; then
        echo "[]"
        exit 0
    fi

    resolve_scope "$SCOPE"

    local results
    results=$(try_tiers)

    # Apply token budget
    results=$(apply_token_budget "$results" "$BUDGET")

    # Output in requested format
    if [[ "$FORMAT" == "text" ]]; then
        format_text "$results"
    else
        echo "$results"
    fi
}

main "$@"
