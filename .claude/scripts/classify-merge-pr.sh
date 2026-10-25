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
# PR number (KF-063, cycle-134 C-8): taken only from GitHub's own subject
# forms — the squash trailer `(#NNN)` at the END of the subject, else the
# merge-commit prefix `Merge pull request #NNN` — and validated as a positive
# decimal (no leading zero, > 0); anything else (an issue reference such as
# `closes #12`, `(#0)`, `(#12a)`) yields no number. With no number and no
# explicit --pr-number the commit is a push, not a merge: pr_type=other and
# one stderr note `[classify-merge-pr] no associated PR: a push, not a merge`
# (the post-merge jobs both require a PR number, so neither runs). An
# explicit --pr-number is honoured as given.
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

# Extract the PR number from the subject if not provided (KF-063): the
# trailing squash form `(#NNN)`, else the merge-commit prefix, as a positive
# decimal; never the first `#NNN` anywhere (an issue reference is not a PR).
if [[ -z "$PR_NUMBER" && -n "$MERGE_MSG" ]]; then
    # the subject is the first line: a squash message carries a body after `<title> (#NNN)` and bash's `$` anchors the
    # end of the whole string (Bridgebuilder round 2 on PR #1296, HIGH: a body would hide the trailer)
    _pr_subject="${MERGE_MSG%%$'\n'*}"
    _pr_re_trailer='\(#([0-9]+)\)[[:space:]]*$'
    _pr_re_merge='^Merge pull request #([0-9]+)([[:space:]:]|$)'
    if [[ "$_pr_subject" =~ $_pr_re_trailer ]] || [[ "$_pr_subject" =~ $_pr_re_merge ]]; then
        PR_NUMBER="${BASH_REMATCH[1]}"
    fi
    [[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]] || PR_NUMBER=""
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

# KF-063: no PR number means a push, not a merge (e.g. the publisher's
# `chore(ledger): archive <cycle> after merge` fast-forward) — never cycle.
if [[ -z "$PR_NUMBER" ]]; then
    PR_TYPE="other"
    echo "[classify-merge-pr] no associated PR: a push, not a merge" >&2
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
