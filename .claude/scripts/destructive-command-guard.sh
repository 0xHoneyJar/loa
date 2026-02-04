#!/usr/bin/env bash
# destructive-command-guard.sh - Core DCG validation engine
#
# Provides command validation against security packs with pattern matching,
# context awareness, and safe path handling.
#
# Usage:
#   source destructive-command-guard.sh
#   result=$(dcg_validate "rm -rf /tmp/cache")
#   echo "$result" | jq '.action'  # ALLOW, WARN, or BLOCK
#
# Dependencies:
#   - dcg-parser.sh    - Command parsing
#   - dcg-matcher.sh   - Pattern matching
#   - dcg-packs-loader.sh - Pack management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

# Source sub-modules (only if they exist)
[[ -f "$SCRIPT_DIR/dcg-parser.sh" ]] && source "$SCRIPT_DIR/dcg-parser.sh"
[[ -f "$SCRIPT_DIR/dcg-matcher.sh" ]] && source "$SCRIPT_DIR/dcg-matcher.sh"
[[ -f "$SCRIPT_DIR/dcg-packs-loader.sh" ]] && source "$SCRIPT_DIR/dcg-packs-loader.sh"

# =============================================================================
# Configuration
# =============================================================================

_DCG_VERSION="1.0.0"
_DCG_TIMEOUT_MS="${DCG_TIMEOUT_MS:-100}"

# Initialization flag
_dcg_engine_initialized=false

# =============================================================================
# Initialization
# =============================================================================

dcg_init() {
    # Check if already initialized AND patterns are loaded
    # The pattern check handles subshell boundaries where the flag may be set
    # but arrays are not inherited
    local pattern_count=0
    local core_count=0

    # Use nounset-safe array length check
    if [[ -v _DCG_PATTERNS ]] && [[ ${#_DCG_PATTERNS[@]} -gt 0 ]]; then
        pattern_count=${#_DCG_PATTERNS[@]}
    fi
    if [[ -v _DCG_CORE_PATTERNS ]] && [[ ${#_DCG_CORE_PATTERNS[@]} -gt 0 ]]; then
        core_count=${#_DCG_CORE_PATTERNS[@]}
    fi

    if [[ "$_dcg_engine_initialized" == "true" ]] && \
       [[ $pattern_count -gt 0 || $core_count -gt 0 ]]; then
        return 0
    fi

    # Load configuration
    _dcg_load_config || {
        echo "WARNING: DCG config load failed, using defaults" >&2
        _dcg_use_defaults
    }

    # Load security packs
    if type dcg_packs_load &>/dev/null; then
        dcg_packs_load || {
            echo "WARNING: DCG pack load failed, core patterns only" >&2
            _dcg_load_core_patterns
        }
    else
        _dcg_load_core_patterns
    fi

    # Expand safe paths at init time (Flatline SKP-004)
    _dcg_expand_safe_paths

    _dcg_engine_initialized=true
}

_dcg_load_config() {
    # Load from .loa.config.yaml if available (yq v4+ only)
    local yq_major=""
    if command -v yq &>/dev/null; then
        local yq_version
        yq_version=$(yq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || true
        yq_major="${yq_version%%.*}"
    fi

    if [[ -n "$yq_major" && "$yq_major" -ge 4 ]] && [[ -f "${PROJECT_ROOT:-.}/.loa.config.yaml" ]]; then
        _DCG_TIMEOUT_MS=$(yq e '.destructive_command_guard.timeout_ms // 100' "${PROJECT_ROOT:-.}/.loa.config.yaml" 2>/dev/null) || _DCG_TIMEOUT_MS=100
        return 0
    fi

    # Fallback to defaults
    _dcg_use_defaults
    return 0
}

_dcg_use_defaults() {
    _DCG_TIMEOUT_MS=100
}

# =============================================================================
# Core Patterns (fallback if packs not loaded)
# =============================================================================

declare -a _DCG_CORE_PATTERNS=()

_dcg_load_core_patterns() {
    _DCG_CORE_PATTERNS=(
        '{"id":"fs_rm_rf_root","pattern":"\\brm\\s+(-[rf]+\\s+)*(/|/\\*)\\s*$","action":"BLOCK","severity":"critical","message":"Attempt to delete root filesystem"}'
        '{"id":"fs_rm_rf_root_subst","pattern":"\\$\\([^)]*rm\\s+(-[rf]+\\s+)*(/|/\\*)","action":"BLOCK","severity":"critical","message":"Attempt to delete root filesystem via command substitution"}'
        '{"id":"fs_rm_rf_root_backtick","pattern":"`[^`]*rm\\s+(-[rf]+\\s+)*(/|/\\*)","action":"BLOCK","severity":"critical","message":"Attempt to delete root filesystem via backtick substitution"}'
        '{"id":"fs_rm_rf_home","pattern":"\\brm\\s+(-[rf]+\\s+)*(~|\\$HOME|/home/[^/]+)\\s*$","action":"BLOCK","severity":"critical","message":"Attempt to delete home directory"}'
        '{"id":"fs_rm_rf_home_subst","pattern":"\\$\\([^)]*rm\\s+(-[rf]+\\s+)*(~|\\$HOME|/home/)","action":"BLOCK","severity":"critical","message":"Attempt to delete home directory via command substitution"}'
        '{"id":"fs_rm_rf_system","pattern":"\\brm\\s+(-[rf]+\\s+)*/(etc|usr|var|bin|lib|sbin|boot|root)\\b","action":"BLOCK","severity":"critical","message":"Attempt to delete system directory"}'
        '{"id":"fs_rm_rf_system_subst","pattern":"\\$\\([^)]*rm\\s+(-[rf]+\\s+)*/(etc|usr|var|bin|lib|sbin|boot|root)","action":"BLOCK","severity":"critical","message":"Attempt to delete system directory via command substitution"}'
        '{"id":"git_push_force","pattern":"\\bgit\\s+push\\s+.*--force\\b","action":"BLOCK","severity":"high","message":"Force push blocked - use git-safety flow"}'
        '{"id":"git_reset_hard","pattern":"\\bgit\\s+reset\\s+--hard\\b","action":"WARN","severity":"medium","message":"git reset --hard will discard uncommitted changes"}'
        '{"id":"git_clean_force","pattern":"\\bgit\\s+clean\\s+-[fdx]+","action":"WARN","severity":"medium","message":"git clean will permanently remove untracked files"}'
        '{"id":"shell_eval","pattern":"\\beval\\s+[\\$\"]","action":"WARN","severity":"high","message":"eval with variable expansion detected"}'
        '{"id":"shell_dcg_bypass","pattern":"\\bDCG_SKIP=1\\b","action":"BLOCK","severity":"critical","message":"Attempt to set DCG bypass variable"}'
        '{"id":"shell_dcg_bypass_env","pattern":"\\benv\\s+.*DCG_SKIP=","action":"BLOCK","severity":"critical","message":"Attempt to set DCG bypass via env command"}'
        '{"id":"shell_dcg_bypass_export","pattern":"\\bexport\\s+DCG_SKIP=","action":"BLOCK","severity":"critical","message":"Attempt to export DCG bypass variable"}'
    )
}

# =============================================================================
# Safe Paths
# =============================================================================

declare -a _DCG_SAFE_PATHS=()

_dcg_expand_safe_paths() {
    _DCG_SAFE_PATHS=()

    # Default safe paths
    local default_paths=(
        "/tmp"
        "/var/tmp"
        "${TMPDIR:-/tmp}"
        "${PROJECT_ROOT:-$(pwd)}/node_modules"
        "${PROJECT_ROOT:-$(pwd)}/.venv"
        "${PROJECT_ROOT:-$(pwd)}/dist"
        "${PROJECT_ROOT:-$(pwd)}/build"
        "${PROJECT_ROOT:-$(pwd)}/__pycache__"
        "${PROJECT_ROOT:-$(pwd)}/.pytest_cache"
    )

    # Load from config if available
    if command -v yq &>/dev/null && [[ -f "${PROJECT_ROOT:-.}/.loa.config.yaml" ]]; then
        while IFS= read -r path; do
            [[ -n "$path" && "$path" != "null" ]] && default_paths+=("$path")
        done < <(yq e '.destructive_command_guard.safe_paths[]' "${PROJECT_ROOT:-.}/.loa.config.yaml" 2>/dev/null || true)
    fi

    # Expand and canonicalize paths
    for path in "${default_paths[@]}"; do
        # CRITICAL-001 FIX: Use safe path expansion instead of eval
        local expanded
        expanded=$(_dcg_expand_path_safe "$path")

        # Skip relative paths (security requirement)
        if [[ ! "$expanded" =~ ^/ ]]; then
            continue
        fi

        # Canonicalize path (resolve symlinks)
        local canonical
        canonical=$(realpath -m "$expanded" 2>/dev/null) || canonical="$expanded"

        _DCG_SAFE_PATHS+=("$canonical")
    done
}

# CRITICAL-001 FIX: Safe path expansion without eval
_dcg_expand_path_safe() {
    local path="$1"

    # Only expand known safe variables via parameter substitution
    path="${path//\~/$HOME}"
    path="${path//\$HOME/$HOME}"
    path="${path//\${HOME\}/$HOME}"
    path="${path//\$TMPDIR/${TMPDIR:-/tmp}}"
    path="${path//\${TMPDIR\}/${TMPDIR:-/tmp}}"
    path="${path//\$PROJECT_ROOT/${PROJECT_ROOT:-.}}"
    path="${path//\${PROJECT_ROOT\}/${PROJECT_ROOT:-.}}"
    path="${path//\$PWD/${PWD:-.}}"
    path="${path//\${PWD\}/${PWD:-.}}"
    path="${path//\$USER/${USER:-unknown}}"
    path="${path//\${USER\}/${USER:-unknown}}"

    echo "$path"
}

# =============================================================================
# Main Validation Function
# =============================================================================

dcg_validate() {
    local command="$1"
    local context="${DCG_CONTEXT:-unknown}"

    # Initialize if needed
    dcg_init

    # Parse command
    local parsed
    if type dcg_parse &>/dev/null; then
        parsed=$(dcg_parse "$command") || {
            # Parse error: fail-open
            echo '{"action":"ALLOW","reason":"parse_error"}'
            return 0
        }
    else
        # Fallback: simple segment split
        parsed=$(_dcg_simple_parse "$command")
    fi

    # Match against patterns
    local match
    if type dcg_match &>/dev/null; then
        match=$(dcg_match "$parsed" "$context")
    else
        match=$(_dcg_simple_match "$parsed" "$context")
    fi

    # Generate response
    if [[ -n "$match" && "$match" != "null" ]]; then
        local action severity message pattern_id
        action=$(echo "$match" | jq -r '.action // "WARN"')
        severity=$(echo "$match" | jq -r '.severity // "medium"')
        message=$(echo "$match" | jq -r '.message // "Pattern matched"')
        pattern_id=$(echo "$match" | jq -r '.id // "unknown"')

        echo "{\"action\":\"$action\",\"severity\":\"$severity\",\"message\":\"$message\",\"pattern\":\"$pattern_id\"}"
    else
        echo '{"action":"ALLOW","reason":"no_match"}'
    fi
}

# =============================================================================
# Fallback Functions (when sub-modules not loaded)
# =============================================================================

_dcg_simple_parse() {
    local command="$1"

    # Simple split by && || ; |
    local segments=()
    local IFS=$'\n'

    while IFS= read -r segment; do
        segment=$(echo "$segment" | xargs 2>/dev/null || echo "$segment")
        [[ -n "$segment" ]] && segments+=("$segment")
    done < <(echo "$command" | sed -E 's/(\s*&&\s*|\s*\|\|\s*|\s*;\s*|\s*\|\s*)/\n/g')

    # Output as JSON
    printf '{"type":"simple","segments":['
    local first=true
    for seg in "${segments[@]}"; do
        [[ "$first" == "true" ]] || printf ','
        printf '"%s"' "$(echo "$seg" | sed 's/"/\\"/g')"
        first=false
    done
    printf ']}'
}

_dcg_simple_match() {
    local parsed="$1"
    local context="$2"

    # Get segments
    local segments
    segments=$(echo "$parsed" | jq -r '.segments[]' 2>/dev/null) || return

    # Check each segment
    while IFS= read -r segment; do
        [[ -z "$segment" ]] && continue

        # Check safe context (grep, echo, cat)
        if _dcg_is_safe_context "$segment"; then
            continue
        fi

        # Get patterns to check
        local patterns=()
        if [[ ${#_DCG_PATTERNS[@]} -gt 0 ]]; then
            patterns=("${_DCG_PATTERNS[@]}")
        else
            patterns=("${_DCG_CORE_PATTERNS[@]}")
        fi

        # Match against patterns
        for pattern_json in "${patterns[@]}"; do
            local pattern
            pattern=$(echo "$pattern_json" | jq -r '.pattern' 2>/dev/null) || continue

            if echo "$segment" | grep -qE "$pattern" 2>/dev/null; then
                # Check safe path for filesystem patterns
                local pattern_id
                pattern_id=$(echo "$pattern_json" | jq -r '.id' 2>/dev/null)

                if [[ "$pattern_id" =~ ^fs_ ]] && _dcg_in_safe_path "$segment"; then
                    continue
                fi

                echo "$pattern_json"
                return 0
            fi
        done
    done <<< "$segments"

    # No match
    return 0
}

_dcg_is_safe_context() {
    local segment="$1"

    # CRITICAL-003 FIX: Check for embedded execution FIRST
    if _dcg_has_embedded_exec "$segment"; then
        return 1  # NOT safe - has embedded execution
    fi

    # Data reference patterns
    [[ "$segment" =~ ^grep[[:space:]] ]] && return 0
    [[ "$segment" =~ ^echo[[:space:]] ]] && return 0
    [[ "$segment" =~ ^cat[[:space:]] ]] && return 0
    [[ "$segment" =~ ^printf[[:space:]] ]] && return 0

    # HIGH-008 FIX: Check flags properly (not in strings/comments)
    if _dcg_has_real_safe_flag "$segment"; then
        return 0
    fi

    return 1
}

# CRITICAL-003 FIX: Detect embedded command execution
_dcg_has_embedded_exec() {
    local segment="$1"

    # Command substitution
    [[ "$segment" =~ \$\( ]] && return 0
    [[ "$segment" =~ \` ]] && return 0

    # Process substitution
    [[ "$segment" =~ '<(' ]] && return 0
    [[ "$segment" =~ '>(' ]] && return 0

    # Pipe to interpreter
    [[ "$segment" =~ \|[[:space:]]*(bash|sh|zsh|python|perl|ruby|node|eval) ]] && return 0

    # -exec flag
    [[ "$segment" =~ [[:space:]]-exec[[:space:]] ]] && return 0

    return 1
}

# HIGH-008 FIX: Detect real flags (not in strings/comments)
_dcg_has_real_safe_flag() {
    local segment="$1"

    # Remove quoted strings
    local clean
    clean=$(echo "$segment" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
    # Remove comments
    clean=$(echo "$clean" | sed 's/#.*//')

    [[ "$clean" =~ [[:space:]]--help([[:space:]]|$) ]] && return 0
    [[ "$clean" =~ [[:space:]]--dry-run([[:space:]]|$) ]] && return 0
    [[ "$clean" =~ [[:space:]]--version([[:space:]]|$) ]] && return 0

    return 1
}

_dcg_in_safe_path() {
    local segment="$1"

    # Extract path from rm command
    local path
    path=$(echo "$segment" | grep -oP '(?:rm\s+(?:-[rf]+\s+)*)\K[^\s]+' | head -1) || return 1
    [[ -z "$path" ]] && return 1

    # CRITICAL-001 FIX: Use safe path expansion instead of eval
    local expanded
    expanded=$(_dcg_expand_path_safe "$path")

    # Canonicalize
    local canonical
    canonical=$(realpath -m "$expanded" 2>/dev/null) || return 1

    # Check against safe paths
    for safe_path in "${_DCG_SAFE_PATHS[@]}"; do
        if [[ "$canonical" == "$safe_path"* ]]; then
            return 0
        fi
    done

    return 1
}

# =============================================================================
# Utility Functions
# =============================================================================

dcg_version() {
    echo "$_DCG_VERSION"
}

dcg_is_enabled() {
    local enabled
    if command -v yq &>/dev/null && [[ -f "${PROJECT_ROOT:-.}/.loa.config.yaml" ]]; then
        enabled=$(yq e '.destructive_command_guard.enabled // false' "${PROJECT_ROOT:-.}/.loa.config.yaml" 2>/dev/null) || enabled="false"
    else
        enabled="false"
    fi
    [[ "$enabled" == "true" ]]
}
