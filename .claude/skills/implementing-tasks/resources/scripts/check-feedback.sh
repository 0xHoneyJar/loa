#!/bin/bash
# Check for pending feedback files
# Usage: ./check-feedback.sh sprint-1

SPRINT_ID="$1"
A2A_DIR="grimoires/loa/a2a/${SPRINT_ID}"

# Validate input
if [[ ! "$SPRINT_ID" =~ ^sprint-[0-9]+$ ]]; then
    echo "ERROR: Invalid sprint ID format. Expected: sprint-N" >&2
    exit 1
fi

# Check audit feedback first (higher priority)
AUDIT_FILE="${A2A_DIR}/auditor-sprint-feedback.md"
if [ -f "$AUDIT_FILE" ]; then
    if grep -q "CHANGES_REQUIRED" "$AUDIT_FILE"; then
        echo "AUDIT_FEEDBACK_PENDING"
        exit 0
    fi
fi

# Check engineer feedback
FEEDBACK_FILE="${A2A_DIR}/engineer-feedback.md"
if [ -f "$FEEDBACK_FILE" ]; then
    if ! grep -q "All good" "$FEEDBACK_FILE"; then
        echo "REVIEW_FEEDBACK_PENDING"
        exit 0
    fi
fi

echo "NO_PENDING_FEEDBACK"
