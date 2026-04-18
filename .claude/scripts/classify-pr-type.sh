#!/usr/bin/env bash
# =============================================================================
# classify-pr-type.sh — shared classifier for post-merge pipeline routing
# =============================================================================
# Part of Issue #550 fix. Previously, two separate sites embedded the same
# classifier logic and drifted:
#   - .github/workflows/post-merge.yml  (narrow regex, missed feat(models):…)
#   - .claude/scripts/post-merge-orchestrator.sh  (added `feat:` catch-all,
#     false-positive on any feature PR)
#
# This helper is the single source of truth. Both sites now source it.
#
# Usage (sourced):
#   source .claude/scripts/classify-pr-type.sh
#   pr_type=$(classify_pr_type "$TITLE" "$LABELS")
#
# Usage (standalone, for scripts that can't source):
#   .claude/scripts/classify-pr-type.sh --title "<title>" --labels "<labels>"
#
# Output: one of "cycle", "bugfix", "other" (on stdout).
# =============================================================================

# classify_pr_type — classify a PR by title and labels
#
# Returns one of:
#   cycle  — PR represents a full cycle (CHANGELOG, GT, RTFM, Release run)
#   bugfix — PR is a bugfix (tag + simple release only)
#   other  — PR doesn't match either (tag only)
#
# Rules (in precedence order):
#   1. Label contains "cycle" (case-insensitive) → cycle
#   2. Title matches cycle-NNN anywhere → cycle
#   3. Title starts with one of the cycle prefixes
#      (Run Mode, Sprint Plan, feat(sprint, feat(cycle) → cycle
#   4. Title starts with "fix" → bugfix
#   5. Otherwise → other
#
# NOTE: `^feat:` (bare) is deliberately NOT treated as cycle — that was a
# pre-existing false-positive in post-merge-orchestrator.sh that classified
# every feat: PR (even small features) as a full cycle. Use `feat(cycle-NNN):`
# or `feat(sprint-NNN):` for cycle-scoped PRs.
classify_pr_type() {
    local title="${1:-}"
    local labels="${2:-}"

    if echo "$labels" | grep -qi "cycle"; then
        echo "cycle"
        return 0
    fi

    if echo "$title" | grep -qE '\bcycle-[0-9]+\b'; then
        echo "cycle"
        return 0
    fi

    if echo "$title" | grep -qE "^(Run Mode|Sprint Plan|feat\(sprint|feat\(cycle)"; then
        echo "cycle"
        return 0
    fi

    if echo "$title" | grep -qE "^fix"; then
        echo "bugfix"
        return 0
    fi

    echo "other"
}

# When executed directly (not sourced), parse flags and invoke
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    TITLE=""
    LABELS=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title)
                if [[ $# -lt 2 ]]; then echo "ERROR: --title requires a value" >&2; exit 2; fi
                TITLE="$2"; shift 2 ;;
            --labels)
                if [[ $# -lt 2 ]]; then echo "ERROR: --labels requires a value" >&2; exit 2; fi
                LABELS="$2"; shift 2 ;;
            -h|--help)
                echo "Usage: classify-pr-type.sh --title <title> [--labels <labels>]"
                exit 0 ;;
            *)
                echo "Unknown arg: $1" >&2; exit 2 ;;
        esac
    done
    classify_pr_type "$TITLE" "$LABELS"
fi
