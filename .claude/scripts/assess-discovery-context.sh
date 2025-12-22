#!/bin/bash
# assess-discovery-context.sh
# Purpose: Assess available context files for PRD discovery
# Usage: ./assess-discovery-context.sh [context_dir]
# Returns: JSON summary of available context
# Note: Complements context-check.sh with discovery-specific logic
# Exit codes: 0=success

set -euo pipefail

CONTEXT_DIR="${1:-loa-grimoire/context}"

# Check if directory exists
if [ ! -d "$CONTEXT_DIR" ]; then
    echo '{"status":"NO_CONTEXT_DIR","files":[],"total_lines":0,"file_count":0}'
    exit 0
fi

# Count markdown files (excluding README.md)
MD_FILES=$(find "$CONTEXT_DIR" -name "*.md" -type f 2>/dev/null | grep -v README.md || true)

# Handle empty result
if [ -z "$MD_FILES" ]; then
    echo '{"status":"EMPTY","files":[],"total_lines":0,"file_count":0}'
    exit 0
fi

FILE_COUNT=$(echo "$MD_FILES" | wc -l)

if [ "$FILE_COUNT" -eq "0" ]; then
    echo '{"status":"EMPTY","files":[],"total_lines":0,"file_count":0}'
    exit 0
fi

# Calculate total lines
TOTAL_LINES=0
while IFS= read -r f; do
    if [ -f "$f" ]; then
        lines=$(wc -l < "$f")
        TOTAL_LINES=$((TOTAL_LINES + lines))
    fi
done <<< "$MD_FILES"

# Determine size category
if [ "$TOTAL_LINES" -lt 500 ]; then
    SIZE="SMALL"
elif [ "$TOTAL_LINES" -lt 2000 ]; then
    SIZE="MEDIUM"
else
    SIZE="LARGE"
fi

# Build files JSON array
FILES_JSON=""
while IFS= read -r f; do
    if [ -f "$f" ]; then
        lines=$(wc -l < "$f")
        name=$(basename "$f")
        if [ -n "$FILES_JSON" ]; then
            FILES_JSON="$FILES_JSON,"
        fi
        FILES_JSON="$FILES_JSON{\"name\":\"$name\",\"path\":\"$f\",\"lines\":$lines}"
    fi
done <<< "$MD_FILES"

echo "{\"status\":\"$SIZE\",\"file_count\":$FILE_COUNT,\"total_lines\":$TOTAL_LINES,\"files\":[$FILES_JSON]}"
