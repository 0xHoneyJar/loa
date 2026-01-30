#!/bin/bash
#
# pull-from-rune.sh - Sync Sigil skills from 0xHoneyJar/rune repository
#
# Usage:
#   ./pull-from-rune.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$PACK_DIR/skills"
TEMP_DIR=$(mktemp -d)

# Skills to pull from rune
SIGIL_SKILLS=(
  animating-motion
  applying-behavior
  crafting-physics
  distilling-components
  inscribing-taste
  styling-material
  surveying-patterns
  synthesizing-taste
  validating-physics
  web3-testing
)

echo "╭───────────────────────────────────────────────────────╮"
echo "│  SIGIL SKILL PULLER                                   │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""

# Clone rune repo (shallow)
echo "Cloning 0xHoneyJar/rune (shallow)..."
if ! git clone --depth 1 https://github.com/0xHoneyJar/rune "$TEMP_DIR/rune" 2>/dev/null; then
    echo "ERROR: Failed to clone rune repository"
    echo "Make sure you have access to 0xHoneyJar/rune"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo ""

# Copy each skill
COPIED=0
MISSING=0

for skill in "${SIGIL_SKILLS[@]}"; do
    src="$TEMP_DIR/rune/.claude/skills/$skill"
    dst="$SKILLS_DIR/$skill"
    
    if [ -d "$src" ]; then
        echo "✓ Copying: $skill"
        cp -r "$src" "$dst"
        ((COPIED++))
    else
        echo "⚠ Missing: $skill (not found in rune)"
        ((MISSING++))
    fi
done

# Copy taste context if exists
if [ -d "$TEMP_DIR/rune/grimoires/rune/taste" ]; then
    echo ""
    echo "Copying taste context..."
    cp -r "$TEMP_DIR/rune/grimoires/rune/taste"/* "$PACK_DIR/contexts/taste/" 2>/dev/null || true
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "╭───────────────────────────────────────────────────────╮"
echo "│  PULL COMPLETE                                        │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""
echo "Copied: $COPIED skills"
echo "Missing: $MISSING skills"
echo ""
echo "Skills directory: $SKILLS_DIR"
echo ""
