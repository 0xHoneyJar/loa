#!/bin/bash
# Check audit prerequisites
# Usage: ./check-audit-prerequisites.sh sprint-1

AUDIT_TYPE="$1"
SPRINT_ID="$2"

case "$AUDIT_TYPE" in
    "sprint")
        if [[ ! "$SPRINT_ID" =~ ^sprint-[0-9]+$ ]]; then
            echo "ERROR: Invalid sprint ID format"
            exit 1
        fi

        FEEDBACK_FILE="grimoires/loa/a2a/${SPRINT_ID}/engineer-feedback.md"
        if [ ! -f "$FEEDBACK_FILE" ]; then
            echo "ERROR: No engineer feedback file - sprint must be reviewed first"
            exit 1
        fi

        if ! grep -q "All good" "$FEEDBACK_FILE"; then
            echo "ERROR: Sprint not approved by senior lead"
            exit 1
        fi

        echo "PREREQUISITES_MET"
        ;;

    "deployment")
        if [ ! -d "grimoires/loa/deployment" ]; then
            echo "ERROR: No deployment directory found"
            exit 1
        fi

        echo "PREREQUISITES_MET"
        ;;

    "codebase")
        echo "PREREQUISITES_MET"
        ;;

    *)
        echo "ERROR: Unknown audit type. Use: sprint, deployment, codebase"
        exit 1
        ;;
esac
