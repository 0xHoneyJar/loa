#!/bin/bash
# Assess context size for parallel splitting decision
# Usage: ./assess-context.sh [mode] [threshold]
# mode: deployment | integration
# threshold: line count (default: 2000)

MODE=${1:-deployment}
THRESHOLD=${2:-2000}

case "$MODE" in
    "deployment")
        TOTAL=$(cat grimoires/loa/prd.md grimoires/loa/sdd.md grimoires/loa/sprint.md grimoires/loa/a2a/*.md 2>/dev/null | wc -l)
        ;;
    "integration")
        TOTAL=$(cat grimoires/loa/integration-architecture.md grimoires/loa/tool-setup.md grimoires/loa/a2a/*.md 2>/dev/null | wc -l)
        ;;
    *)
        echo "ERROR: Unknown mode. Use: deployment, integration"
        exit 1
        ;;
esac

# Also count existing infrastructure code
INFRA_LINES=$(find . -name "*.tf" -o -name "*.yaml" -o -name "Dockerfile*" 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
INFRA_LINES=${INFRA_LINES:-0}

TOTAL=$((TOTAL + INFRA_LINES))

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
