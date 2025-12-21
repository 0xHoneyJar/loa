#!/bin/bash
# Sync Beads state to git
# Usage: sync-to-git.sh [commit-message]
#
# Syncs beads database, stages changes, and optionally commits.
# If commit message provided, creates a commit.

set -euo pipefail

COMMIT_MSG="${1:-}"

# Check if bd is installed
if ! command -v bd &> /dev/null; then
    echo "Error: bd (beads) is not installed" >&2
    exit 1
fi

# Check if beads is initialized
if [[ ! -d ".beads" ]]; then
    echo "Error: Beads not initialized in this project" >&2
    exit 1
fi

# Sync beads
bd sync

# Stage beads database
git add .beads/beads.jsonl

# Check if there are changes to commit
if git diff --cached --quiet .beads/; then
    echo "No beads changes to commit"
    exit 0
fi

# Commit if message provided
if [[ -n "$COMMIT_MSG" ]]; then
    git commit -m "chore(beads): $COMMIT_MSG"
    echo "Committed beads changes"
else
    echo "Beads changes staged (not committed)"
fi
