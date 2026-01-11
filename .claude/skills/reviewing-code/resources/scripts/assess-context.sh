#!/bin/bash
# Assess context size for parallel splitting decision
# Usage: ./assess-context.sh sprint-1

SPRINT_ID="$1"
THRESHOLD=${2:-3000}

TOTAL=$(wc -l grimoires/loa/prd.md grimoires/loa/sdd.md \
        grimoires/loa/sprint.md "grimoires/loa/a2a/${SPRINT_ID}/reviewer.md" 2>/dev/null | \
        tail -1 | awk '{print $1}')

if [ -z "$TOTAL" ] || [ "$TOTAL" -eq 0 ]; then
    echo "SMALL"
    exit 0
fi

if [ "$TOTAL" -lt "$THRESHOLD" ]; then
    echo "SMALL"
elif [ "$TOTAL" -lt 6000 ]; then
    echo "MEDIUM"
else
    echo "LARGE"
fi
