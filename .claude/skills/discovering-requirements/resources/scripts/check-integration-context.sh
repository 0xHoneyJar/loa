#!/bin/bash
# Check for integration context file
# Usage: ./check-integration-context.sh

CONTEXT_FILE="grimoires/loa/a2a/integration-context.md"

if [ -f "$CONTEXT_FILE" ]; then
    echo "EXISTS"
    exit 0
else
    echo "MISSING"
    exit 1
fi
