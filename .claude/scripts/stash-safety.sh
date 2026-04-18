#!/usr/bin/env bash
# =============================================================================
# stash-safety.sh — Defensive wrapper for git stash operations
# =============================================================================
# Issue #555. A downstream operator lost 4 unstaged edits when a
# pre-commit-adjacent operation used this pattern:
#
#   git stash push -k -m "..." 2>&1 | tail -3 && \
#     <op triggering pre-commit> && \
#     git stash pop 2>&1 | tail -3 || true
#
# The `| tail -N` swallowed CONFLICT markers; the `|| true` swallowed
# non-zero exits; pre-commit's internal stash shifted indexes, so the
# outer `pop` landed on the wrong entry. "Dropped refs/stash@{0}" looked
# like success but the worktree did not receive the expected content.
#
# This helper provides:
#   - `stash_with_guard`: runs a callback between push and pop with:
#       * full stdout+stderr preserved (no `| tail`, no `||true`)
#       * pre/post count delta enforced (N → N+1 on push, N+1 → N on pop)
#       * STASH_SAFETY_VIOLATION diagnostic on mismatch (with recovery hint)
#   - `_stash_count`: helper to count stash entries (sourced for tests)
#
# Intended to be sourced by any Loa script that needs stash semantics.
# =============================================================================

# Idempotent source guard — avoid re-declaring functions if already sourced.
if [[ -n "${_STASH_SAFETY_SH_SOURCED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_STASH_SAFETY_SH_SOURCED=1

# -----------------------------------------------------------------------------
# _stash_count — count entries in `git stash list`
# -----------------------------------------------------------------------------
# Returns the numeric count on stdout. Defaults to "0" on any failure
# (outside a git worktree, stash command unavailable, etc.) so callers
# under `set -euo pipefail` don't blow up on pre-check.
# -----------------------------------------------------------------------------
_stash_count() {
    # If/else instead of `|| echo 0` to avoid accumulating "0\n0" under
    # pipefail when the underlying pipeline also emits "0" from wc.
    local out
    if out=$(git stash list 2>/dev/null | wc -l | tr -d ' '); then
        echo "${out:-0}"
    else
        echo "0"
    fi
}

# -----------------------------------------------------------------------------
# _stash_top_message — read message of the topmost stash entry (stash@{0})
# -----------------------------------------------------------------------------
# Empty string if no stash or error. Used to verify the top stash is the
# one our caller just pushed (mid-flight intruder detection).
# -----------------------------------------------------------------------------
_stash_top_message() {
    git stash list -n 1 --format='%s' 2>/dev/null || echo ""
}

# -----------------------------------------------------------------------------
# stash_with_guard — run a callback between stash push and pop, with integrity guard
# -----------------------------------------------------------------------------
# Usage:
#   stash_with_guard <stash_message> -- <callback> [callback_args...]
#
# Example:
#   stash_with_guard "pre-check" -- run_linter src/
#
# Behavior:
#   1. Record stash count N_before
#   2. `git stash push -m "<msg>" --include-untracked` (errors surfaced)
#   3. If count did not advance to N_before+1: emit STASH_SAFETY_VIOLATION, exit 10
#   4. Run callback
#   5. Capture callback's exit status (preserved and returned)
#   6. `git stash pop` (errors surfaced; stdout+stderr fully captured)
#   7. If count did not return to N_before: emit STASH_SAFETY_VIOLATION, exit 11
#   8. Return callback's exit status (not pop's)
#
# Exit codes:
#   0-N — callback's exit status (on clean push/pop)
#   10  — push did not produce the expected count delta (pre-existing shift
#         OR stash push silently no-op'd because worktree was clean)
#   11  — pop did not restore the expected count (conflict, shifted index,
#         or pre-commit internal stash collision)
#   12  — usage error (missing callback)
#
# Recovery hint: on exit 11, orphan stashes remain in git object DB —
# run `git fsck --unreachable | grep commit` to find them, then
# `git cat-file -p <sha>` to inspect.
# -----------------------------------------------------------------------------
stash_with_guard() {
    local stash_msg="${1:-loa-stash-$(date +%s)}"

    # Validate delimiter + callback
    if [[ "${2:-}" != "--" ]]; then
        echo "STASH_SAFETY_VIOLATION: stash_with_guard requires '--' between message and callback" >&2
        return 12
    fi
    shift 2  # discard msg + --

    if [[ $# -eq 0 ]]; then
        echo "STASH_SAFETY_VIOLATION: stash_with_guard requires a callback" >&2
        return 12
    fi

    local n_before n_after_push n_after_pop
    n_before=$(_stash_count)

    # Push — surface all output (no `2>/dev/null`, no `| tail`)
    if ! git stash push -m "$stash_msg" --include-untracked; then
        echo "STASH_SAFETY_VIOLATION: stash push failed (see output above)" >&2
        return 10
    fi

    n_after_push=$(_stash_count)
    if [[ "$n_after_push" -ne "$((n_before + 1))" ]]; then
        echo "STASH_SAFETY_VIOLATION: expected stash count $((n_before + 1)) after push, got $n_after_push" >&2
        echo "Recovery: git stash list" >&2
        return 10
    fi

    # Run callback — preserve exit status
    local cb_status=0
    "$@" || cb_status=$?

    # Before popping, verify the top stash is still ours (DISS-002 defense
    # against another process pushing a stash between our push and pop).
    # Count-delta catches the wrong-slot case too, but verifying the
    # message makes the check redundant in a good way — a second independent
    # signal for the same class of failure.
    local top_msg
    top_msg=$(_stash_top_message)
    if [[ "$top_msg" != *"$stash_msg"* ]]; then
        echo "STASH_SAFETY_VIOLATION: top stash is not ours (expected message to contain '$stash_msg', got '$top_msg')" >&2
        echo "Recovery: git stash list  # to locate our stash by message" >&2
        return 11
    fi

    # Pop with --index so staged content is restored to the index (not just
    # the worktree). Without --index, files that were staged before our push
    # become unstaged on pop — silently mutating the user's staging state.
    # Surface all output; preserve exit via explicit `|| status=$?` to avoid
    # the `if !` trap (where $? inside then-branch reflects the inverted test).
    local pop_status=0
    git stash pop --index || pop_status=$?
    if [[ "$pop_status" -ne 0 ]]; then
        echo "STASH_SAFETY_VIOLATION: stash pop failed (exit $pop_status; see output above)" >&2
        # Do NOT return here — still check count and emit recovery hint
    fi

    n_after_pop=$(_stash_count)
    if [[ "$n_after_pop" -ne "$n_before" ]]; then
        echo "STASH_SAFETY_VIOLATION: expected stash count $n_before after pop, got $n_after_pop" >&2
        echo "Recovery: inspect 'git stash list' and 'git fsck --unreachable | grep commit' for orphaned content" >&2
        return 11
    fi

    if [[ "$pop_status" -ne 0 ]]; then
        return 11
    fi

    return "$cb_status"
}
