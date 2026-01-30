#!/bin/bash
#
# compose-context.sh - Merge base cultural context with overlays
#
# Usage:
#   ./compose-context.sh [PROJECT_ROOT]
#   ./compose-context.sh . --overlays "berachain,defi"
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACK_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT_ROOT="${1:-.}"
OVERLAYS="${2:-berachain,defi}"

# Paths
BASE_CONTEXT="$PACK_DIR/contexts/base/crypto-base.md"
OVERLAYS_DIR="$PACK_DIR/contexts/overlays"
OUTPUT_DIR="$PACK_DIR/contexts/composed"
OUTPUT_FILE="$OUTPUT_DIR/cultural-context.md"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

echo "╭───────────────────────────────────────────────────────╮"
echo "│  LENS CONTEXT COMPOSER                                │"
echo "╰───────────────────────────────────────────────────────╯"
echo ""

# Check base context exists
if [ ! -f "$BASE_CONTEXT" ]; then
    echo "ERROR: Base context not found at $BASE_CONTEXT"
    exit 1
fi

echo "Base context: $BASE_CONTEXT"

# Start with base context
cp "$BASE_CONTEXT" "$OUTPUT_FILE"

# Process overlays
IFS=',' read -ra OVERLAY_ARRAY <<< "$OVERLAYS"
for overlay_name in "${OVERLAY_ARRAY[@]}"; do
    overlay_name=$(echo "$overlay_name" | xargs)  # trim whitespace
    overlay_file="$OVERLAYS_DIR/${overlay_name}-overlay.md"
    
    if [ -f "$overlay_file" ]; then
        echo "Merging overlay: $overlay_name"
        
        # Extract tables from overlay and append to base
        # Look for content between @table markers
        
        # Low-signal patterns
        low_signal=$(awk '/<!-- @table:low-signal-patterns \[merge-mode:append\] -->/{flag=1; next} /<!-- @table:low-signal-patterns:end -->/{flag=0} flag' "$overlay_file" | grep "^|" | grep -v "Pattern.*Meaning" || true)
        
        if [ -n "$low_signal" ]; then
            # Insert before the :end marker in output
            sed -i.bak '/<!-- @table:low-signal-patterns:end -->/i\
'"$low_signal"'
' "$OUTPUT_FILE" 2>/dev/null || \
            sed -i '' '/<!-- @table:low-signal-patterns:end -->/i\
'"$low_signal"'
' "$OUTPUT_FILE"
        fi
        
        # High-signal patterns
        high_signal=$(awk '/<!-- @table:high-signal-patterns \[merge-mode:append\] -->/{flag=1; next} /<!-- @table:high-signal-patterns:end -->/{flag=0} flag' "$overlay_file" | grep "^|" | grep -v "Pattern.*indicates" || true)
        
        if [ -n "$high_signal" ]; then
            sed -i.bak '/<!-- @table:high-signal-patterns:end -->/i\
'"$high_signal"'
' "$OUTPUT_FILE" 2>/dev/null || \
            sed -i '' '/<!-- @table:high-signal-patterns:end -->/i\
'"$high_signal"'
' "$OUTPUT_FILE"
        fi
    else
        echo "Warning: Overlay not found: $overlay_file (skipping)"
    fi
done

# Clean up backup files
rm -f "$OUTPUT_FILE.bak"

echo ""
echo "✓ Composed context written to: $OUTPUT_FILE"
echo ""
