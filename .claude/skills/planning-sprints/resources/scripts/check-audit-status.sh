#!/bin/bash
# Check for security audit feedback status
# Usage: ./check-audit-status.sh

AUDIT_FILE="loa-grimoire/a2a/auditor-sprint-feedback.md"

if [ -f "$AUDIT_FILE" ]; then
    if grep -q "CHANGES_REQUIRED" "$AUDIT_FILE"; then
        echo "CHANGES_REQUIRED"
        exit 1
    elif grep -q "APPROVED" "$AUDIT_FILE"; then
        echo "APPROVED"
        exit 0
    else
        echo "UNKNOWN_STATUS"
        exit 2
    fi
else
    echo "NO_AUDIT"
    exit 0
fi
