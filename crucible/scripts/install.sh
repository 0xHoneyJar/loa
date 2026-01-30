#!/bin/bash
#
# install.sh - Install Crucible pack for a project
#
# Usage:
#   ./install.sh [PROJECT_ROOT]
#

set -e

PROJECT_ROOT="${1:-.}"

echo "╭───────────────────────────────────────────────────────╮"
echo "│  CRUCIBLE PACK INSTALLER                              │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""

# Create grimoire structure
GRIMOIRE_DIR="$PROJECT_ROOT/grimoires/crucible"
mkdir -p "$GRIMOIRE_DIR/diagrams"
mkdir -p "$GRIMOIRE_DIR/reality"
mkdir -p "$GRIMOIRE_DIR/gaps"
mkdir -p "$GRIMOIRE_DIR/tests"
mkdir -p "$GRIMOIRE_DIR/walkthroughs"
mkdir -p "$GRIMOIRE_DIR/results"

echo "✓ Created grimoire structure at $GRIMOIRE_DIR"

echo ""
echo "╭───────────────────────────────────────────────────────╮"
echo "│  INSTALLATION COMPLETE                                │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""
echo "Available commands:"
echo "  /ground {component}        - Extract code reality"
echo "  /diagram {journey-id}      - Generate state diagrams"
echo "  /validate {journey-id}     - Generate/run Playwright tests"
echo "  /walkthrough {journey-id}  - Interactive browser walkthrough"
echo "  /iterate {journey-id}      - Update artifacts from results"
echo ""
echo "Grimoire location: $GRIMOIRE_DIR"
echo ""
