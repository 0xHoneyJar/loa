#!/usr/bin/env bash
# =============================================================================
# portable-realpath.sh — GNU/BSD portable path resolver (Issue #660)
# =============================================================================
# BSD `realpath` (macOS default) does NOT support `-m` (resolve missing
# components). Calling `realpath -m` on macOS errors with `illegal option
# -- m` and exits non-zero. mount-submodule.sh swallowed this error via
# `2>/dev/null || echo ""`, leaving every macOS operator with silently-
# skipped symlink reconcile and a final summary lying about `fixed=0`.
#
# This lib detects the available realpath flavor once at source time and
# exposes a `resolve_path_portable` function that uses `-m` when available
# or falls back to plain `realpath` (which on BSD requires the path to
# exist — adequate when callers gate on existence checks).
#
# Usage:
#   source portable-realpath.sh
#   resolved=$(resolve_path_portable "$target")
#
# Output:
#   - On success: canonical resolved path on stdout
#   - On failure: empty string, exit 1 (caller decides how to handle)
#
# When called from a directory using `cd "$dir" && resolve_path_portable
# "$rel"`, relative paths are resolved against $dir (same as `realpath`).
# =============================================================================

# Probe once at source time. This is a per-process check; bash `set -u`
# safe via parameter default.
if [[ -z "${_PORTABLE_REALPATH_HAS_M:-}" ]]; then
    if realpath -m / >/dev/null 2>&1; then
        _PORTABLE_REALPATH_HAS_M=1
    else
        _PORTABLE_REALPATH_HAS_M=0
    fi
    export _PORTABLE_REALPATH_HAS_M
fi

resolve_path_portable() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        return 1
    fi

    if [[ "$_PORTABLE_REALPATH_HAS_M" -eq 1 ]]; then
        # GNU realpath: resolves even when path doesn't exist
        realpath -m "$target" 2>/dev/null || return 1
    else
        # BSD/macOS fallback: plain realpath requires path to exist.
        # When the caller has gated on existence (-e check), this is fine.
        # When the caller wants symbolic resolution of a not-yet-created
        # path, they must compose: resolve the parent, then append basename.
        if realpath "$target" 2>/dev/null; then
            return 0
        fi

        # If plain realpath failed, attempt manual resolution: cd into
        # the parent (if it exists) and join with basename. This handles
        # the common case of a not-yet-created file in an existing dir.
        # Use bash parameter expansion (POSIX-portable, no external deps)
        # to avoid GNU-vs-BSD dirname/basename divergence on macOS.
        local parent base abs_parent
        case "$target" in
            */*)
                parent="${target%/*}"
                base="${target##*/}"
                # Empty parent (target was "/foo") → use root
                [[ -z "$parent" ]] && parent="/"
                ;;
            *)
                parent="."
                base="$target"
                ;;
        esac
        if [[ -d "$parent" ]]; then
            abs_parent=$(cd "$parent" 2>/dev/null && pwd) || return 1
            echo "${abs_parent}/${base}"
            return 0
        fi
        return 1
    fi
}

# Allow direct invocation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    resolve_path_portable "$@"
fi
