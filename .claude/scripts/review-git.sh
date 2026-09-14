#!/usr/bin/env bash
# Fixed stdout-only Git queries for review/audit skills. Persist output through
# the State-restricted Write tool; callers cannot supply Git options or paths.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: review-git.sh diff|log (no additional arguments)" >&2
    exit 2
fi

case "$1" in
    diff)
        exec git --no-pager diff --no-ext-diff --no-textconv main...HEAD -- ;;
    log)
        exec git --no-pager log --no-decorate --no-show-signature --format=oneline main..HEAD -- ;;
    *)
        echo "Usage: review-git.sh diff|log (no additional arguments)" >&2
        exit 2 ;;
esac
