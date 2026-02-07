#!/usr/bin/env bash
# dx-utils.sh — Shared DX utilities for Loa framework
# Issue #211: DX comparison to Vercel and other popular agent CLI tools
#
# Provides:
#   - Error code registry (LOA-EXXX) — Pattern 4: Errors That Teach (Rust RFC 1644)
#   - Formatted output helpers — Pattern 10: Sweat Every Word
#   - Next-command suggestions — Pattern 5: Suggest the Next Command
#   - TTY detection — Pattern 6: Dual-Mode Output
#   - Section rendering for consistent doctor/status output
#
# Usage:
#   source "${SCRIPT_DIR}/lib/dx-utils.sh"
#
# Design principles:
#   - Errors are educational, not punitive
#   - dx_error() NEVER calls exit — the caller decides
#   - Graceful fallback if error-codes.json missing or jq unavailable
#   - Colors respect NO_COLOR (https://no-color.org/)
#
# Dependencies: jq (for full functionality; graceful without), bash 4+
# References:
#   - https://clig.dev/
#   - https://rust-lang.github.io/rfcs/1644-default-and-expanded-rustc-errors.html

# Guard against double-sourcing
[[ -n "${_DX_UTILS_LOADED:-}" ]] && return 0
readonly _DX_UTILS_LOADED=1

# =============================================================================
# Path Resolution (via BASH_SOURCE, not PWD)
# =============================================================================
_DX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Require bash 4.0+ (associative arrays)
# shellcheck source=../bash-version-guard.sh
source "$_DX_LIB_DIR/../bash-version-guard.sh"

# =============================================================================
# TTY Detection (Pattern 6: Dual-Mode Output)
# =============================================================================
_DX_IS_TTY=false
if [[ -t 1 ]]; then
    _DX_IS_TTY=true
fi

# =============================================================================
# Colors & Icons (respect NO_COLOR — https://no-color.org/)
# =============================================================================
if [[ -z "${NO_COLOR:-}" ]] && [[ "${_DX_IS_TTY}" == "true" ]]; then
    _DX_RED='\033[0;31m'
    _DX_YELLOW='\033[1;33m'
    _DX_GREEN='\033[0;32m'
    _DX_CYAN='\033[0;36m'
    _DX_BLUE='\033[0;34m'
    _DX_DIM='\033[2m'
    _DX_BOLD='\033[1m'
    _DX_NC='\033[0m'
else
    _DX_RED=''
    _DX_YELLOW=''
    _DX_GREEN=''
    _DX_CYAN=''
    _DX_BLUE=''
    _DX_DIM=''
    _DX_BOLD=''
    _DX_NC=''
fi

# Status icons (matches constructs-lib.sh:391-394)
_DX_ICON_OK="${_DX_GREEN}✓${_DX_NC}"
_DX_ICON_WARN="${_DX_YELLOW}⚠${_DX_NC}"
_DX_ICON_ERR="${_DX_RED}✗${_DX_NC}"
_DX_ICON_INFO="${_DX_CYAN}○${_DX_NC}"
_DX_ICON_WORK="${_DX_CYAN}◉${_DX_NC}"
_DX_ICON_SKIP="${_DX_DIM}·${_DX_NC}"

# =============================================================================
# Security: Sanitize Control Characters
# =============================================================================

# Strip control characters and truncate to limit
# Args: $1 = text, $2 = max bytes (default 4096)
_dx_sanitize() {
    local text="${1:-}"
    local max_bytes="${2:-4096}"
    # Strip control chars including newlines (prevents fake "Fix:" injection via
    # multiline context). Preserves tabs only. Strips C0 (0x00-0x1F except HT),
    # DEL (0x7F), and C1 control range (0x80-0x9F) for terminal safety.
    text=$(printf '%s' "$text" | tr -d '\000-\010\012-\014\016-\037\177')
    # Truncate
    if [[ ${#text} -gt ${max_bytes} ]]; then
        text="${text:0:${max_bytes}}... (truncated)"
    fi
    printf '%s' "$text"
}

# =============================================================================
# Error Code Registry (Pattern 4: Errors That Teach)
# =============================================================================
# Loaded from .claude/data/error-codes.json at source time.
# Falls back gracefully if JSON file missing or jq unavailable.

declare -A _DX_ERROR_REGISTRY
_DX_REGISTRY_LOADED=false

_dx_load_registry() {
    local codes_file="${_DX_LIB_DIR}/../../data/error-codes.json"
    if [[ -f "${codes_file}" ]] && command -v jq &>/dev/null; then
        while IFS=$'\t' read -r code name what fix; do
            [[ -n "${code}" ]] && _DX_ERROR_REGISTRY["${code}"]="${name}\t${what}\t${fix}"
        done < <(jq -r '.[] | [.code, .name, .what, .fix] | @tsv' "${codes_file}" 2>/dev/null)
        _DX_REGISTRY_LOADED=true
    fi
}
_dx_load_registry

# Render a Rust-style error message to stderr
# Args: $1 = error code (e.g., "E001" or "LOA-E001"), $@ = optional context
# Returns: 0 for known codes, 1 for unknown codes (NEVER calls exit)
dx_error() {
    local code="$1"
    shift
    local context="${*:-}"

    # Strip LOA- prefix if present
    code="${code#LOA-}"

    local entry="${_DX_ERROR_REGISTRY[${code}]:-}"
    if [[ -z "${entry}" ]]; then
        # Graceful fallback for unknown code or unloaded registry
        printf "%bLOA-%s%b: Unknown error code\n" "${_DX_RED}" "${code}" "${_DX_NC}" >&2
        if [[ "${_DX_REGISTRY_LOADED}" == "false" ]]; then
            printf "  Error registry not loaded. Run /loa doctor to check your installation.\n" >&2
        fi
        return 1
    fi

    local name what fix
    IFS=$'\t' read -r name what fix <<< "${entry}"

    # Sanitize context
    if [[ -n "${context}" ]]; then
        context=$(_dx_sanitize "${context}" 1024)
    fi

    # Rust-style format: code + what + context + fix
    printf "\n%bLOA-%s%b: %s\n" "${_DX_RED}" "${code}" "${_DX_NC}" "${name}" >&2
    printf "\n  %s\n" "${what}" >&2

    if [[ -n "${context}" ]]; then
        printf "  %b─→%b %s\n" "${_DX_DIM}" "${_DX_NC}" "${context}" >&2
    fi

    printf "\n  %bFix:%b %s\n\n" "${_DX_BOLD}" "${_DX_NC}" "${fix}" >&2
    return 0
}

# Expanded documentation for an error code
# Args: $1 = error code
dx_explain() {
    local code="$1"
    code="${code#LOA-}"

    local entry="${_DX_ERROR_REGISTRY[${code}]:-}"
    if [[ -z "${entry}" ]]; then
        printf "Unknown error code: LOA-%s\n" "${code}" >&2
        return 1
    fi

    local name what fix
    IFS=$'\t' read -r name what fix <<< "${entry}"

    # Determine category from code
    local category
    case "${code:1:1}" in
        0) category="Framework & Environment" ;;
        1) category="Workflow & Lifecycle" ;;
        2) category="Beads & Task Tracking" ;;
        3) category="Events & Bus" ;;
        4) category="Security & Guardrails" ;;
        5) category="Constructs & Packs" ;;
        *) category="Unknown" ;;
    esac

    printf "\n%bLOA-%s%b: %s\n" "${_DX_BOLD}" "${code}" "${_DX_NC}" "${name}"
    printf "Category: %s\n\n" "${category}"
    printf "  %bWhat:%b %s\n" "${_DX_BOLD}" "${_DX_NC}" "${what}"
    printf "  %bFix:%b  %s\n" "${_DX_BOLD}" "${_DX_NC}" "${fix}"

    # Show related errors in same category
    local prefix="${code:0:2}"
    local related=()
    for k in "${!_DX_ERROR_REGISTRY[@]}"; do
        if [[ "${k}" != "${code}" ]] && [[ "${k:0:2}" == "${prefix}" ]]; then
            related+=("${k}")
        fi
    done

    if [[ ${#related[@]} -gt 0 ]]; then
        printf "\n  %bRelated:%b\n" "${_DX_BOLD}" "${_DX_NC}"
        for r in $(printf '%s\n' "${related[@]}" | sort); do
            local r_entry="${_DX_ERROR_REGISTRY[${r}]}"
            local r_name
            IFS=$'\t' read -r r_name _ _ <<< "${r_entry}"
            printf "    LOA-%s  %s\n" "${r}" "${r_name}"
        done
    fi
    printf "\n"
}

# List all error codes (text mode, grouped by category)
dx_list_errors() {
    printf "\n%bLoa Error Code Registry%b\n" "${_DX_BOLD}" "${_DX_NC}"

    local current_category=""
    for code in $(printf '%s\n' "${!_DX_ERROR_REGISTRY[@]}" | sort); do
        local category
        case "${code:1:1}" in
            0) category="Framework & Environment (E0xx)" ;;
            1) category="Workflow & Lifecycle (E1xx)" ;;
            2) category="Beads & Task Tracking (E2xx)" ;;
            3) category="Events & Bus (E3xx)" ;;
            4) category="Security & Guardrails (E4xx)" ;;
            5) category="Constructs & Packs (E5xx)" ;;
            *) category="Unknown" ;;
        esac

        if [[ "${category}" != "${current_category}" ]]; then
            current_category="${category}"
            printf "\n  %b%s%b\n" "${_DX_BOLD}" "${category}" "${_DX_NC}"
        fi

        local entry="${_DX_ERROR_REGISTRY[${code}]}"
        local name
        IFS=$'\t' read -r name _ _ <<< "${entry}"
        printf "    LOA-%s  %s\n" "${code}" "${name}"
    done
    printf "\n"
}

# List error codes as JSON (via jq, safe construction)
dx_list_errors_json() {
    local codes_file="${_DX_LIB_DIR}/../../data/error-codes.json"
    if [[ -f "${codes_file}" ]] && command -v jq &>/dev/null; then
        jq '.' "${codes_file}"
    else
        echo "[]"
    fi
}

# =============================================================================
# Formatted Output Helpers (Pattern 10: Sweat Every Word)
# =============================================================================

# Section header
dx_header() {
    printf "\n  %b%s%b\n" "${_DX_BOLD}" "$1" "${_DX_NC}"
}

# Check result: "    ✓ message" or "    ✗ message"
dx_check() {
    printf "    %b %s\n" "$1" "$2"
}

# Indented detail: "      → detail"
dx_detail() {
    printf "      → %s\n" "$1"
}

# Suggestion (cyan): "      → command"
dx_suggest() {
    printf "      → %b%s%b\n" "${_DX_CYAN}" "$1" "${_DX_NC}"
}

# Horizontal separator
dx_separator() {
    printf "  ────────────────────────────────────────────────\n"
}

# Box borders
dx_box_top() {
    printf "  ════════════════════════════════════════════════\n"
}
dx_box_bottom() {
    printf "  ════════════════════════════════════════════════\n"
}

# "Next steps" block (Pattern 5: Suggest the Next Command)
# Args: "cmd|description" pairs
dx_next_steps() {
    printf "\n  %bNext:%b\n" "${_DX_BOLD}" "${_DX_NC}"
    for entry in "$@"; do
        local cmd="${entry%%|*}"
        local desc="${entry#*|}"
        printf "    %b%-30s%b %b%s%b\n" \
            "${_DX_CYAN}" "${cmd}" "${_DX_NC}" \
            "${_DX_DIM}" "${desc}" "${_DX_NC}"
    done
}

# Summary footer with issue/warning counts
dx_summary() {
    local issues="${1:-0}"
    local warnings="${2:-0}"
    printf "\n"
    if [[ "${issues}" -eq 0 ]] && [[ "${warnings}" -eq 0 ]]; then
        printf "  %bAll checks passed.%b\n" "${_DX_GREEN}" "${_DX_NC}"
    elif [[ "${issues}" -eq 0 ]]; then
        printf "  %b%d warning(s).%b Run suggested commands to resolve.\n" \
            "${_DX_YELLOW}" "${warnings}" "${_DX_NC}"
    else
        printf "  %b%d issue(s)%b, %d warning(s). Run suggested commands to resolve.\n" \
            "${_DX_RED}" "${issues}" "${_DX_NC}" "${warnings}"
    fi
}

# =============================================================================
# Dependency Check Helpers
# =============================================================================

# Check if command exists and capture version
# Args: $1 = command, $2 = version flag (default: --version)
# Sets: _DX_DEP_VERSION
# Returns: 0 if found, 1 if not found
dx_check_dep() {
    local cmd="$1"
    local version_flag="${2:---version}"
    if command -v "$cmd" &>/dev/null; then
        _DX_DEP_VERSION=$("$cmd" "$version_flag" 2>&1 | head -1 || echo "unknown")
        return 0
    else
        _DX_DEP_VERSION="not_found"
        return 1
    fi
}

# Platform-aware install recommendation
# Uses _COMPAT_OS from compat-lib.sh if available, else detects
_dx_install_hint() {
    local tool="$1"
    local os="${_COMPAT_OS:-}"
    if [[ -z "${os}" ]]; then
        case "$(uname -s 2>/dev/null)" in
            Darwin) os="darwin" ;;
            *)      os="linux" ;;
        esac
    fi

    case "${os}" in
        darwin)
            case "$tool" in
                jq)    echo "brew install jq" ;;
                yq)    echo "brew install yq" ;;
                flock) echo "brew install util-linux" ;;
                br)    echo "cargo install beads_rust" ;;
                sqlite3) echo "brew install sqlite3" ;;
                ajv)   echo "npm install -g ajv-cli" ;;
                *)     echo "See documentation for $tool" ;;
            esac
            ;;
        linux)
            case "$tool" in
                jq)    echo "apt install jq (Debian/Ubuntu) or dnf install jq (Fedora)" ;;
                yq)    echo "snap install yq or go install github.com/mikefarah/yq/v4@latest" ;;
                flock) echo "Usually pre-installed. apt install util-linux if missing" ;;
                br)    echo "cargo install beads_rust" ;;
                sqlite3) echo "apt install sqlite3 (Debian/Ubuntu) or dnf install sqlite (Fedora)" ;;
                ajv)   echo "npm install -g ajv-cli" ;;
                *)     echo "See documentation for $tool" ;;
            esac
            ;;
        *)
            echo "See documentation for $tool"
            ;;
    esac
}

# =============================================================================
# JSON Helpers (CI-013 pattern: safe construction via jq --arg)
# =============================================================================

# Build JSON object from key=value pairs
# Args: key=value pairs
dx_json_status() {
    local json='{}'
    for pair in "$@"; do
        local key="${pair%%=*}"
        local val="${pair#*=}"
        if [[ "${val}" =~ ^-?[0-9]+$ ]] || [[ "${val}" == "true" ]] || [[ "${val}" == "false" ]]; then
            json=$(echo "${json}" | jq --arg k "$key" --argjson v "$val" '. + {($k): $v}')
        else
            json=$(echo "${json}" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
        fi
    done
    echo "${json}"
}
