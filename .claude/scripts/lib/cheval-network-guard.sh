#!/usr/bin/env bash
# =============================================================================
# Cycle-108 sprint-2 T2.L — Network restriction guard
# =============================================================================
# SDD §20.10 ATK-A16 closure. When LOA_NETWORK_RESTRICTED=1, the curl / wget /
# nc / ftp shell functions defined here intercept invocations from inside a
# benchmark replay and refuse anything outside the LLM-provider endpoint
# allowlist. When the env var is unset (or != 1), the functions are no-ops
# and delegate transparently.
#
# Source from the benchmark harness:
#   export LOA_NETWORK_RESTRICTED=1
#   source .claude/scripts/lib/cheval-network-guard.sh
#   # replay commands run here; curl/wget/nc/ftp now filtered
#
# Allowlist (matches by host substring on canonicalized URL):
#   - api.anthropic.com
#   - api.openai.com
#   - generativelanguage.googleapis.com
#   - api.x.ai           (xAI)
#   - api.moonshot.ai
# Operators may extend via LOA_NETWORK_ALLOWLIST_EXTRA="host1,host2".
#
# Blocked invocations emit:
#   [NETWORK-GUARD-BLOCKED] <cmd>: <target> not in allowlist (see ${RUNBOOK})
# and exit 78 (EX_CONFIG).
#
# Allowed invocations delegate to the system binary via `command <cmd> "$@"`.
# =============================================================================

_LOA_NETWORK_GUARD_ALLOWLIST=(
    "api.anthropic.com"
    "api.openai.com"
    "generativelanguage.googleapis.com"
    "api.x.ai"
    "api.moonshot.ai"
)

# Augment with operator-supplied allowlist (comma-separated).
if [ -n "${LOA_NETWORK_ALLOWLIST_EXTRA:-}" ]; then
    _LOA_NETWORK_GUARD_EXTRA="$LOA_NETWORK_ALLOWLIST_EXTRA"
    while IFS=',' read -ra _extra; do
        for _h in "${_extra[@]}"; do
            _h="${_h//[[:space:]]/}"
            [ -n "$_h" ] && _LOA_NETWORK_GUARD_ALLOWLIST+=("$_h")
        done
    done <<< "$_LOA_NETWORK_GUARD_EXTRA"
    unset _LOA_NETWORK_GUARD_EXTRA
fi


_loa_network_guard_extract_host() {
    # Extract host from a URL or `host:port` argument; print to stdout.
    # Returns "" if no recognizable host present.
    local arg="$1"
    # Strip scheme://
    local stripped="${arg#http://}"
    stripped="${stripped#https://}"
    stripped="${stripped#ftp://}"
    stripped="${stripped#ftps://}"
    # Strip user@ if present
    stripped="${stripped##*@}"
    # Strip path / query
    stripped="${stripped%%/*}"
    stripped="${stripped%%\?*}"
    # Strip :port
    stripped="${stripped%%:*}"
    printf '%s' "$stripped"
}


_loa_network_guard_check_host() {
    local host="$1"
    [ -z "$host" ] && return 1
    local allowed
    for allowed in "${_LOA_NETWORK_GUARD_ALLOWLIST[@]}"; do
        if [ "$host" = "$allowed" ]; then
            return 0
        fi
    done
    return 1
}


_loa_network_guard_block() {
    local cmd="$1"
    local target="$2"
    printf '[NETWORK-GUARD-BLOCKED] %s: %s not in allowlist (see grimoires/loa/runbooks/advisor-strategy-rollback.md)\n' \
        "$cmd" "$target" >&2
    return 78
}


_loa_network_guard_should_intercept() {
    [ "${LOA_NETWORK_RESTRICTED:-}" = "1" ]
}


_loa_network_guard_check_args() {
    # Walk an argv list; for each token that looks like a URL or host, verify
    # against the allowlist. Returns 0 if all URLs allowed (or none present);
    # returns 78 if any URL is blocked. Prints block message on stderr.
    local cmd="$1"; shift
    local arg host
    for arg in "$@"; do
        case "$arg" in
            http://*|https://*|ftp://*|ftps://*)
                host="$(_loa_network_guard_extract_host "$arg")"
                if ! _loa_network_guard_check_host "$host"; then
                    _loa_network_guard_block "$cmd" "$arg"
                    return 78
                fi
                ;;
        esac
    done
    return 0
}


# -----------------------------------------------------------------------------
# Interceptor functions.
# -----------------------------------------------------------------------------
#
# Each delegates to the real binary via `command` after passing the args
# through the allowlist check. The functions ONLY intercept when
# LOA_NETWORK_RESTRICTED=1 — otherwise they're transparent passthroughs.
# -----------------------------------------------------------------------------

curl() {
    if ! _loa_network_guard_should_intercept; then
        command curl "$@"
        return $?
    fi
    if ! _loa_network_guard_check_args "curl" "$@"; then
        return 78
    fi
    command curl "$@"
}


wget() {
    if ! _loa_network_guard_should_intercept; then
        command wget "$@"
        return $?
    fi
    if ! _loa_network_guard_check_args "wget" "$@"; then
        return 78
    fi
    command wget "$@"
}


nc() {
    if ! _loa_network_guard_should_intercept; then
        command nc "$@"
        return $?
    fi
    # nc takes `host port` as positional args; walk the argv and check the
    # first non-flag token as a candidate host.
    local arg host
    for arg in "$@"; do
        case "$arg" in
            -*) ;;
            *)
                host="$arg"
                if ! _loa_network_guard_check_host "$host"; then
                    _loa_network_guard_block "nc" "$host"
                    return 78
                fi
                break
                ;;
        esac
    done
    command nc "$@"
}


ftp() {
    if ! _loa_network_guard_should_intercept; then
        command ftp "$@"
        return $?
    fi
    if ! _loa_network_guard_check_args "ftp" "$@"; then
        return 78
    fi
    command ftp "$@"
}


# Export so spawned subshells inherit. `export -f` is bash-only; on dash/sh
# the functions are inlined when this file is `source`d but won't propagate
# across subprocesses. The harness always invokes through bash explicitly.
if [ -n "${BASH_VERSION:-}" ]; then
    export -f curl wget nc ftp 2>/dev/null || true
    export -f _loa_network_guard_should_intercept 2>/dev/null || true
    export -f _loa_network_guard_check_args 2>/dev/null || true
    export -f _loa_network_guard_check_host 2>/dev/null || true
    export -f _loa_network_guard_extract_host 2>/dev/null || true
    export -f _loa_network_guard_block 2>/dev/null || true
fi
