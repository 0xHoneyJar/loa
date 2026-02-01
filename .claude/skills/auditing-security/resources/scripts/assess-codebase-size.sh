#!/bin/bash
# Assess codebase size for parallel splitting decision
# Usage: ./assess-codebase-size.sh [threshold]

THRESHOLD=${1:-2000}

TOTAL=$(find . -name "*.ts" -o -name "*.js" -o -name "*.tf" -o -name "*.py" 2>/dev/null | \
        xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')

if [ -z "$TOTAL" ] || [ "$TOTAL" -eq 0 ]; then
    echo "SMALL"
    exit 0
fi

if [ "$TOTAL" -lt "$THRESHOLD" ]; then
    echo "SMALL"
elif [ "$TOTAL" -lt 5000 ]; then
    echo "MEDIUM"
else
    echo "LARGE"
fi
