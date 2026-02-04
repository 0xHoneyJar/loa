#!/usr/bin/env bash
# dcg-packs-loader.sh - Security pack management for DCG
#
# Loads security packs from YAML files and manages pattern arrays.
# Core pack is always loaded; optional packs based on config.
#
# Usage:
#   source dcg-packs-loader.sh
#   dcg_packs_load
#   echo "${#_DCG_PATTERNS[@]} patterns loaded"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

_DCG_PACKS_VERSION="1.0.0"
_DCG_PACKS_DIR="${PROJECT_ROOT:-.}/.claude/security-packs"

# Global arrays
declare -a _DCG_PATTERNS=()
declare -a _DCG_SAFE_PATHS=()
declare -a _DCG_LOADED_PACKS=()

# =============================================================================
# Embedded Core Patterns (fallback for yq v3 or no yq)
# =============================================================================

_dcg_packs_load_embedded_core() {
    # These patterns mirror core.yaml but are hardcoded for environments without yq v4+
    _DCG_PATTERNS+=(
        '{"id":"fs_rm_rf_root","pattern":"\\brm\\s+(-[rf]+\\s+)*(/|/\\*)\\s*$","action":"BLOCK","severity":"critical","message":"Attempt to delete root filesystem"}'
        '{"id":"fs_rm_rf_root_subst","pattern":"\\$\\([^)]*rm\\s+(-[rf]+\\s+)*(/|/\\*)","action":"BLOCK","severity":"critical","message":"Attempt to delete root filesystem via command substitution"}'
        '{"id":"fs_rm_rf_root_backtick","pattern":"`[^`]*rm\\s+(-[rf]+\\s+)*(/|/\\*)","action":"BLOCK","severity":"critical","message":"Attempt to delete root filesystem via backtick substitution"}'
        '{"id":"fs_rm_rf_home","pattern":"\\brm\\s+(-[rf]+\\s+)*(~|\\$HOME|/home/[^/]+)\\s*$","action":"BLOCK","severity":"critical","message":"Attempt to delete home directory"}'
        '{"id":"fs_rm_rf_home_subst","pattern":"\\$\\([^)]*rm\\s+(-[rf]+\\s+)*(~|\\$HOME|/home/)","action":"BLOCK","severity":"critical","message":"Attempt to delete home directory via command substitution"}'
        '{"id":"fs_rm_rf_system","pattern":"\\brm\\s+(-[rf]+\\s+)*/(etc|usr|var|bin|lib|sbin|boot|root)\\b","action":"BLOCK","severity":"critical","message":"Attempt to delete system directory"}'
        '{"id":"fs_rm_rf_system_subst","pattern":"\\$\\([^)]*rm\\s+(-[rf]+\\s+)*/(etc|usr|var|bin|lib|sbin|boot|root)","action":"BLOCK","severity":"critical","message":"Attempt to delete system directory via command substitution"}'
        '{"id":"git_push_force","pattern":"\\bgit\\s+push\\s+.*--force\\b","action":"BLOCK","severity":"high","message":"Force push blocked - use git-safety flow"}'
        '{"id":"git_push_force_short","pattern":"\\bgit\\s+push\\s+.*-f\\b","action":"BLOCK","severity":"high","message":"Force push blocked - use git-safety flow"}'
        '{"id":"git_reset_hard","pattern":"\\bgit\\s+reset\\s+--hard\\b","action":"WARN","severity":"medium","message":"git reset --hard will discard uncommitted changes"}'
        '{"id":"git_clean_force","pattern":"\\bgit\\s+clean\\s+-[fdx]+","action":"WARN","severity":"medium","message":"git clean will permanently remove untracked files"}'
        '{"id":"git_checkout_dot","pattern":"\\bgit\\s+checkout\\s+\\.\\s*$","action":"WARN","severity":"medium","message":"git checkout . will discard all local changes"}'
        '{"id":"shell_eval","pattern":"\\beval\\s+[\\$\"]","action":"WARN","severity":"high","message":"eval with variable expansion detected"}'
        '{"id":"shell_dcg_bypass","pattern":"\\bDCG_SKIP=1\\b","action":"BLOCK","severity":"critical","message":"Attempt to set DCG bypass variable"}'
        '{"id":"shell_dcg_bypass_env","pattern":"\\benv\\s+.*DCG_SKIP=","action":"BLOCK","severity":"critical","message":"Attempt to set DCG bypass via env command"}'
        '{"id":"shell_dcg_bypass_export","pattern":"\\bexport\\s+DCG_SKIP=","action":"BLOCK","severity":"critical","message":"Attempt to export DCG bypass variable"}'
    )
}

_dcg_packs_load_embedded_database() {
    # Database patterns for environments without yq v4+
    _DCG_PATTERNS+=(
        '{"id":"sql_drop_table","pattern":"\\bDROP\\s+TABLE\\s+(?:IF\\s+EXISTS\\s+)?\\w+","action":"BLOCK","severity":"critical","message":"DROP TABLE will permanently delete table and all data"}'
        '{"id":"sql_drop_database","pattern":"\\bDROP\\s+DATABASE\\s+(?:IF\\s+EXISTS\\s+)?\\w+","action":"BLOCK","severity":"critical","message":"DROP DATABASE will permanently delete entire database"}'
        '{"id":"sql_truncate","pattern":"\\bTRUNCATE\\s+(?:TABLE\\s+)?\\w+","action":"WARN","severity":"high","message":"TRUNCATE will delete all rows without logging"}'
        '{"id":"sql_delete_all","pattern":"\\bDELETE\\s+FROM\\s+\\w+\\s*(?:;|$)","action":"BLOCK","severity":"critical","message":"DELETE without WHERE will delete all rows"}'
        '{"id":"mongo_drop_database","pattern":"\\b(db\\.dropDatabase|dropDatabase)\\(\\)","action":"BLOCK","severity":"critical","message":"MongoDB dropDatabase() will delete entire database"}'
        '{"id":"mongo_drop_collection","pattern":"\\bdb\\.[\\w]+\\.drop\\(\\)","action":"WARN","severity":"high","message":"MongoDB drop() will delete collection"}'
        '{"id":"mongo_remove_all","pattern":"\\bdb\\.[\\w]+\\.(remove|deleteMany)\\(\\{\\}\\)","action":"BLOCK","severity":"critical","message":"MongoDB remove/deleteMany with empty query deletes all"}'
        '{"id":"redis_flushall","pattern":"\\bFLUSHALL\\b","action":"BLOCK","severity":"critical","message":"FLUSHALL will delete all Redis data"}'
        '{"id":"redis_flushdb","pattern":"\\bFLUSHDB\\b","action":"BLOCK","severity":"critical","message":"FLUSHDB will delete current Redis database"}'
        '{"id":"mysql_drop","pattern":"\\bmysql\\b.*(-e|--execute)\\s+['"'"'\"]?.*DROP\\s+(TABLE|DATABASE)","action":"BLOCK","severity":"critical","message":"MySQL CLI DROP command"}'
        '{"id":"psql_drop","pattern":"\\bpsql\\b.*(-c|--command)\\s+['"'"'\"]?.*DROP\\s+(TABLE|DATABASE)","action":"BLOCK","severity":"critical","message":"PostgreSQL CLI DROP command"}'
    )
}

_dcg_packs_load_embedded_docker() {
    # Docker patterns for environments without yq v4+
    _DCG_PATTERNS+=(
        '{"id":"docker_rm_all","pattern":"\\bdocker\\s+rm\\s+.*\\$\\(docker\\s+ps","action":"BLOCK","severity":"critical","message":"Will remove all matching containers"}'
        '{"id":"docker_rm_force_all","pattern":"\\bdocker\\s+rm\\s+-f\\s+\\$\\(","action":"BLOCK","severity":"critical","message":"Force removing containers via subshell"}'
        '{"id":"docker_rmi_all","pattern":"\\bdocker\\s+rmi\\s+.*\\$\\(docker\\s+images","action":"BLOCK","severity":"critical","message":"Will remove all matching images"}'
        '{"id":"docker_volume_rm_all","pattern":"\\bdocker\\s+volume\\s+rm\\s+\\$\\(docker\\s+volume","action":"BLOCK","severity":"critical","message":"Will remove all volumes"}'
        '{"id":"docker_kill_all","pattern":"\\bdocker\\s+kill\\s+\\$\\(docker\\s+ps","action":"BLOCK","severity":"critical","message":"Will kill all containers"}'
        '{"id":"docker_system_prune_all","pattern":"\\bdocker\\s+system\\s+prune\\s+-a","action":"BLOCK","severity":"critical","message":"docker system prune -a removes all unused data"}'
        '{"id":"docker_system_prune_force","pattern":"\\bdocker\\s+system\\s+prune\\s+-f","action":"WARN","severity":"high","message":"docker system prune removes unused data"}'
        '{"id":"docker_volume_prune","pattern":"\\bdocker\\s+volume\\s+prune\\s+-f","action":"WARN","severity":"high","message":"Will remove all unused volumes"}'
        '{"id":"compose_down_volumes","pattern":"\\bdocker[-\\s]compose\\s+down\\s+.*-v","action":"WARN","severity":"high","message":"docker-compose down -v removes volumes"}'
    )
}

# =============================================================================
# Pack Loading
# =============================================================================

dcg_packs_load() {
    _DCG_PATTERNS=()
    _DCG_LOADED_PACKS=()

    # Always load core pack first
    if ! _dcg_load_pack "core"; then
        echo "ERROR: Failed to load core security pack" >&2
        return 1
    fi

    # Load optional packs based on config
    if command -v yq &>/dev/null && [[ -f "${PROJECT_ROOT:-.}/.loa.config.yaml" ]]; then
        local packs_config
        packs_config=$(yq e '.destructive_command_guard.packs // {}' "${PROJECT_ROOT:-.}/.loa.config.yaml" 2>/dev/null) || packs_config="{}"

        for pack in database docker kubernetes cloud-aws cloud-gcp cloud-azure terraform; do
            local enabled
            enabled=$(echo "$packs_config" | yq e ".$pack // false" - 2>/dev/null) || enabled="false"

            if [[ "$enabled" == "true" ]]; then
                _dcg_load_pack "$pack" || {
                    echo "WARNING: Failed to load $pack pack, continuing" >&2
                }
            fi
        done
    fi

    # Expand safe paths
    _dcg_packs_expand_safe_paths

    return 0
}

_dcg_load_pack() {
    local pack_name="$1"
    local pack_file="$_DCG_PACKS_DIR/${pack_name}.yaml"

    # Check if pack file exists
    if [[ ! -f "$pack_file" ]]; then
        # Try alternative naming
        pack_file="$_DCG_PACKS_DIR/${pack_name//-/_}.yaml"
        if [[ ! -f "$pack_file" ]]; then
            return 1
        fi
    fi

    # Check yq version - need v4 (mikefarah/yq)
    local yq_version=""
    if command -v yq &>/dev/null; then
        yq_version=$(yq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || yq_version=""
    fi

    local yq_major="${yq_version%%.*}"

    # yq v4+ (mikefarah/yq) uses different syntax
    if [[ -n "$yq_major" && "$yq_major" -ge 4 ]]; then
        # Validate YAML
        if ! yq e '.' "$pack_file" >/dev/null 2>&1; then
            echo "ERROR: Invalid YAML in $pack_file" >&2
            return 1
        fi

        # Load patterns using yq v4 syntax
        local patterns
        patterns=$(yq e '.patterns[] | @json' "$pack_file" 2>/dev/null) || return 1

        while IFS= read -r pattern_json; do
            [[ -n "$pattern_json" ]] && _DCG_PATTERNS+=("$pattern_json")
        done <<< "$patterns"

        _DCG_LOADED_PACKS+=("$pack_name")
    else
        # Fallback: use embedded patterns (no yq or yq v3)
        case "$pack_name" in
            core)
                _dcg_packs_load_embedded_core
                _DCG_LOADED_PACKS+=("core (embedded)")
                return 0
                ;;
            database)
                _dcg_packs_load_embedded_database
                _DCG_LOADED_PACKS+=("database (embedded)")
                return 0
                ;;
            docker)
                _dcg_packs_load_embedded_docker
                _DCG_LOADED_PACKS+=("docker (embedded)")
                return 0
                ;;
            *)
                echo "WARNING: yq v4+ required for $pack_name pack, no embedded fallback" >&2
                return 1
                ;;
        esac
    fi

    return 0
}

# =============================================================================
# Safe Paths
# =============================================================================

_dcg_packs_expand_safe_paths() {
    _DCG_SAFE_PATHS=()

    # Default safe paths
    local default_paths=(
        "/tmp"
        "/var/tmp"
        "${TMPDIR:-/tmp}"
    )

    # Add project-relative paths
    local project_root="${PROJECT_ROOT:-$(pwd)}"
    default_paths+=(
        "$project_root/node_modules"
        "$project_root/.venv"
        "$project_root/venv"
        "$project_root/dist"
        "$project_root/build"
        "$project_root/target"
        "$project_root/__pycache__"
        "$project_root/.pytest_cache"
        "$project_root/.mypy_cache"
        "$project_root/.tox"
        "$project_root/.coverage"
    )

    # Load from config if available (yq v4+ only)
    local yq_major=""
    if command -v yq &>/dev/null; then
        local yq_version
        yq_version=$(yq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || true
        yq_major="${yq_version%%.*}"
    fi

    if [[ -n "$yq_major" && "$yq_major" -ge 4 ]] && [[ -f "${PROJECT_ROOT:-.}/.loa.config.yaml" ]]; then
        while IFS= read -r path; do
            [[ -n "$path" && "$path" != "null" ]] && default_paths+=("$path")
        done < <(yq e '.destructive_command_guard.safe_paths[]' "${PROJECT_ROOT:-.}/.loa.config.yaml" 2>/dev/null || true)
    fi

    # Expand and canonicalize paths
    for path in "${default_paths[@]}"; do
        # CRITICAL-001 FIX: Use safe path expansion instead of eval
        local expanded
        expanded=$(_dcg_packs_expand_path_safe "$path")

        # Skip relative paths (security requirement per Flatline SKP-004)
        if [[ ! "$expanded" =~ ^/ ]]; then
            continue
        fi

        # Canonicalize path (resolve symlinks)
        local canonical
        canonical=$(realpath -m "$expanded" 2>/dev/null) || canonical="$expanded"

        # Avoid duplicates
        local exists=false
        for existing in "${_DCG_SAFE_PATHS[@]:-}"; do
            [[ "$existing" == "$canonical" ]] && exists=true && break
        done

        [[ "$exists" == "false" ]] && _DCG_SAFE_PATHS+=("$canonical")
    done
}

# CRITICAL-001 FIX: Safe path expansion without eval
_dcg_packs_expand_path_safe() {
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
# Pack Info
# =============================================================================

dcg_packs_list() {
    echo "Loaded packs: ${_DCG_LOADED_PACKS[*]:-none}"
    echo "Total patterns: ${#_DCG_PATTERNS[@]}"
    echo "Safe paths: ${#_DCG_SAFE_PATHS[@]}"
}

dcg_packs_info() {
    local pack_name="$1"
    local pack_file="$_DCG_PACKS_DIR/${pack_name}.yaml"

    if [[ ! -f "$pack_file" ]]; then
        echo "Pack not found: $pack_name"
        return 1
    fi

    if command -v yq &>/dev/null; then
        echo "Pack: $pack_name"
        echo "Version: $(yq e '.version // "unknown"' "$pack_file")"
        echo "Description: $(yq e '.description // "No description"' "$pack_file")"
        echo "Patterns: $(yq e '.patterns | length' "$pack_file")"
    else
        echo "Pack: $pack_name (yq required for details)"
    fi
}

# =============================================================================
# Utility
# =============================================================================

dcg_packs_version() {
    echo "$_DCG_PACKS_VERSION"
}
