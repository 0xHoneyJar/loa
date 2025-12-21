#!/bin/bash
# Assess context size for parallel splitting decision
# Usage: ./assess-context.sh [threshold]

THRESHOLD=${1:-3000}

TOTAL=$(wc -l loa-grimoire/prd.md loa-grimoire/sdd.md \
        loa-grimoire/sprint.md loa-grimoire/a2a/*.md 2>/dev/null | \
        tail -1 | awk '{print $1}')

if [ -z "$TOTAL" ] || [ "$TOTAL" -eq 0 ]; then
    echo "SMALL"
    exit 0
fi

if [ "$TOTAL" -lt "$THRESHOLD" ]; then
    echo "SMALL"
elif [ "$TOTAL" -lt $((THRESHOLD * 2 + 2000)) ]; then
    echo "MEDIUM"
else
    echo "LARGE"
fi
