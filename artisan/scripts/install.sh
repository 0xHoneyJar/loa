#!/bin/bash
#
# install.sh - Install Artisan pack for a project
#
# Usage:
#   ./install.sh [PROJECT_ROOT]
#

set -e

PROJECT_ROOT="${1:-.}"

echo "╭───────────────────────────────────────────────────────╮"
echo "│  ARTISAN PACK INSTALLER                               │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""

# Create grimoire structure
GRIMOIRE_DIR="$PROJECT_ROOT/grimoires/artisan"
mkdir -p "$GRIMOIRE_DIR/physics"
mkdir -p "$GRIMOIRE_DIR/taste"
mkdir -p "$GRIMOIRE_DIR/observations"

echo "✓ Created grimoire structure at $GRIMOIRE_DIR"

echo ""
echo "╭───────────────────────────────────────────────────────╮"
echo "│  INSTALLATION COMPLETE                                │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""
echo "Available commands:"
echo "  /survey                  - Discover UI patterns"
echo "  /inscribe                - Apply brand taste"
echo "  /craft                   - Create physics animations"
echo "  /validate-physics        - Validate physics implementation"
echo "  /animate                 - Design motion patterns"
echo "  /behavior                - Apply interaction behaviors"
echo "  /distill                 - Extract components"
echo "  /style                   - Apply Material styling"
echo "  /synthesize-taste        - Synthesize brand taste"
echo "  /web3-test               - Web3 testing utilities"
echo ""
echo "Grimoire location: $GRIMOIRE_DIR"
echo ""
