#!/usr/bin/env bash
# =============================================================================
# classify-merge-pr.sh — workflow-level merge classifier (Issue #668)
# =============================================================================
# Wraps classify-pr-type.sh with merge-context handling so the post-merge
# pipeline classifies cycle PRs correctly even when `gh pr view` returns
# empty title/labels in the GitHub Actions runner. The merge commit subject
# is in-tree state and never empty by the time post-merge runs, so it is the
# PRIMARY signal. `gh pr view` labels are SECONDARY enrichment — when gh
# fails, the failure is surfaced loudly to stderr (no silent swallow) and
# the wrapper falls through to subject-only classification.
#
# Usage:
#   classify-merge-pr.sh --merge-sha <sha> [--pr-number <n>]
#   classify-merge-pr.sh --merge-msg "<commit subject>" [--pr-number <n>]
#
# Output (stdout):
#   pr_type=<cycle|bugfix|other>
#   pr_number=<n|empty>
#
# When $GITHUB_OUTPUT is set, the same key=value lines are appended there.
#
# Exit codes:
#   0 — classified successfully
#   2 — bad arguments
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MERGE_SHA=""
MERGE_MSG=""
PR_NUMBER=""
MERGE_MSG_SET=0

usage() {
    cat <<EOF
Usage: classify-merge-pr.sh --merge-sha <sha> [--pr-number <n>]
       classify-merge-pr.sh --merge-msg "<subject>" [--pr-number <n>]

Classifies a merged PR by inspecting the merge commit subject (PRIMARY) and
optionally enriching with gh pr view labels (SECONDARY). Output:
  pr_type=<cycle|bugfix|other>
  pr_number=<n|empty>
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --merge-sha)
            [[ $# -ge 2 ]] || { echo "ERROR: --merge-sha requires a value" >&2; exit 2; }
            MERGE_SHA="$2"; shift 2 ;;
        --merge-msg)
            [[ $# -ge 2 ]] || { echo "ERROR: --merge-msg requires a value" >&2; exit 2; }
            MERGE_MSG="$2"; MERGE_MSG_SET=1; shift 2 ;;
        --pr-number)
            [[ $# -ge 2 ]] || { echo "ERROR: --pr-number requires a value" >&2; exit 2; }
            PR_NUMBER="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2 ;;
    esac
done

# Must have either --merge-sha or --merge-msg (an empty --merge-msg is valid;
# the classifier returns "other" for empty subjects — graceful path).
if [[ -z "$MERGE_SHA" && "$MERGE_MSG_SET" -eq 0 ]]; then
    echo "ERROR: one of --merge-sha or --merge-msg is required" >&2
    usage >&2
    exit 2
fi

# Resolve subject from SHA if --merge-sha was passed and --merge-msg was not
if [[ -z "$MERGE_MSG" && -n "$MERGE_SHA" ]]; then
    if MERGE_MSG=$(git log -1 --format='%s' "$MERGE_SHA" 2>/dev/null); then
        :  # got it
    else
        echo "[classify-merge-pr] WARN: failed to resolve subject from sha=$MERGE_SHA" >&2
        MERGE_MSG=""
    fi
fi

# Extract PR number from merge message if not provided
if [[ -z "$PR_NUMBER" && -n "$MERGE_MSG" ]]; then
    # Match (#NNN) or trailing #NNN
    PR_NUMBER=$(echo "$MERGE_MSG" | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true)
fi

# Source the shared rules engine
CLASSIFIER="${SCRIPT_DIR}/classify-pr-type.sh"
if [[ ! -f "$CLASSIFIER" ]]; then
    echo "[classify-merge-pr] ERROR: classify-pr-type.sh not found at $CLASSIFIER" >&2
    exit 2
fi
# shellcheck source=classify-pr-type.sh
source "$CLASSIFIER"

# PRIMARY: classify by merge subject alone (in-tree state, never empty)
PR_TYPE_PRIMARY=$(classify_pr_type "$MERGE_MSG" "")

# SECONDARY: try gh pr view for label enrichment. If it fails, log loud
# but continue with PRIMARY result. Capture stderr to a temp file so the
# real failure surfaces in the workflow log.
LABELS=""
GH_FAILED=0
if [[ -n "$PR_NUMBER" ]] && command -v gh >/dev/null 2>&1; then
    gh_stderr=$(mktemp)
    if gh_json=$(gh pr view "$PR_NUMBER" --json title,labels 2>"$gh_stderr"); then
        # Successful gh call — extract labels (jq '.labels[].name')
        LABELS=$(echo "$gh_json" | jq -r '[.labels[]?.name] | join(",")' 2>/dev/null || echo "")
    else
        GH_FAILED=1
        # Surface the failure loudly. Caller can grep for [classify-merge-pr] in logs.
        echo "[classify-merge-pr] WARN: gh pr view failed for PR #${PR_NUMBER}; falling through to subject-only classification" >&2
        if [[ -s "$gh_stderr" ]]; then
            echo "[classify-merge-pr] gh stderr: $(cat "$gh_stderr")" >&2
        fi
    fi
    rm -f "$gh_stderr"
elif [[ -n "$PR_NUMBER" ]]; then
    echo "[classify-merge-pr] WARN: gh CLI not available; skipping label enrichment for PR #${PR_NUMBER}" >&2
fi

# If enrichment succeeded AND labels imply cycle, override PRIMARY
if [[ -n "$LABELS" ]] && echo "$LABELS" | grep -qi "cycle"; then
    PR_TYPE="cycle"
else
    PR_TYPE="$PR_TYPE_PRIMARY"
fi

# Emit result
echo "pr_type=${PR_TYPE}"
echo "pr_number=${PR_NUMBER}"

# Also append to $GITHUB_OUTPUT for GitHub Actions consumers
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "pr_type=${PR_TYPE}"
        echo "pr_number=${PR_NUMBER}"
    } >>"$GITHUB_OUTPUT"
fi

exit 0
