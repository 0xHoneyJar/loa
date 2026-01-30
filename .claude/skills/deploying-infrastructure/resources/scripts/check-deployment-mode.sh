#!/bin/bash
# Determine deployment mode based on available files
# Usage: ./check-deployment-mode.sh

# Check for integration mode files
INTEGRATION_ARCH="grimoires/loa/integration-architecture.md"
TOOL_SETUP="grimoires/loa/tool-setup.md"

# Check for deployment mode files
PRD="grimoires/loa/prd.md"
SDD="grimoires/loa/sdd.md"
SPRINT="grimoires/loa/sprint.md"

# Check integration context (applies to both modes)
INTEGRATION_CONTEXT="grimoires/loa/a2a/integration-context.md"

if [ -f "$INTEGRATION_ARCH" ] && [ -f "$TOOL_SETUP" ]; then
    echo "INTEGRATION"
    echo "Found: $INTEGRATION_ARCH, $TOOL_SETUP"
    if [ -f "$INTEGRATION_CONTEXT" ]; then
        echo "Integration context available: $INTEGRATION_CONTEXT"
    fi
elif [ -f "$PRD" ] && [ -f "$SDD" ]; then
    echo "DEPLOYMENT"
    echo "Found: $PRD, $SDD"
    if [ -f "$SPRINT" ]; then
        echo "Sprint plan available: $SPRINT"
    fi
    if [ -f "$INTEGRATION_CONTEXT" ]; then
        echo "Integration context available: $INTEGRATION_CONTEXT"
    fi
else
    echo "ERROR: Missing required files"
    echo ""
    echo "For INTEGRATION mode, need:"
    echo "  - $INTEGRATION_ARCH"
    echo "  - $TOOL_SETUP"
    echo ""
    echo "For DEPLOYMENT mode, need:"
    echo "  - $PRD"
    echo "  - $SDD"
    exit 1
fi
