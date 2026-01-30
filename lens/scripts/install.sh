#!/bin/bash
#
# install.sh - Install Lens pack for a project
#
# Usage:
#   ./install.sh [PROJECT_ROOT]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT_ROOT="${1:-.}"

echo "╭───────────────────────────────────────────────────────╮"
echo "│  LENS PACK INSTALLER                                  │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""

# Create grimoire structure
GRIMOIRE_DIR="$PROJECT_ROOT/grimoires/lens"
mkdir -p "$GRIMOIRE_DIR/canvas"
mkdir -p "$GRIMOIRE_DIR/journeys"

echo "✓ Created grimoire structure at $GRIMOIRE_DIR"

# Initialize state.yaml if not exists
STATE_FILE="$GRIMOIRE_DIR/state.yaml"
if [ ! -f "$STATE_FILE" ]; then
    cat > "$STATE_FILE" << 'YAML'
# Lens State
# Tracks canvas and journey status

version: 1
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Active canvases being researched
active_canvases: []

# Defined journeys
journeys: []

# Research metrics
metrics:
  total_canvases: 0
  total_journeys: 0
  gaps_identified: 0
YAML
    echo "✓ Initialized state.yaml"
else
    echo "✓ Preserved existing state.yaml"
fi

# Run context composition
if [ -f "$SCRIPT_DIR/compose-context.sh" ]; then
    echo ""
    echo "Running context composition..."
    "$SCRIPT_DIR/compose-context.sh" "$PROJECT_ROOT"
fi

echo ""
echo "╭───────────────────────────────────────────────────────╮"
echo "│  INSTALLATION COMPLETE                                │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""
echo "Available commands:"
echo "  /observe @{user} \"{quote}\"  - Capture user feedback"
echo "  /shape                        - List canvases, shape journeys"
echo "  /analyze-gap {journey}        - Compare expectations vs reality"
echo "  /file-gap {journey} {gap-id}  - Create issue from gap"
echo "  /import-research              - Migrate legacy research"
echo ""
echo "Grimoire location: $GRIMOIRE_DIR"
echo ""
