#!/bin/bash
# merge-hooks.sh - Intelligently merge Loa hooks into existing settings.json
#
# Usage: merge-hooks.sh <target_settings> <loa_settings> [hivemind_path]
#
# Strategy:
# 1. Preserve existing hooks (HivemindOS first)
# 2. Append Loa hooks to SessionStart and UserPromptSubmit
# 3. Use merged status line if hivemind_path provided
# 4. Create backup before modification

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Arguments
# =============================================================================

TARGET_SETTINGS="${1:-}"
LOA_SETTINGS="${2:-}"
HIVEMIND_PATH="${3:-}"

if [[ -z "$TARGET_SETTINGS" ]] || [[ -z "$LOA_SETTINGS" ]]; then
    echo "Usage: merge-hooks.sh <target_settings> <loa_settings> [hivemind_path]"
    echo ""
    echo "Merges Loa hooks into existing settings.json without replacing."
    echo ""
    echo "Arguments:"
    echo "  target_settings  - Path to target settings.json"
    echo "  loa_settings     - Path to Loa's settings.json template"
    echo "  hivemind_path    - Optional: Path to HivemindOS (enables merged status line)"
    exit 1
fi

# =============================================================================
# ANSI Colors
# =============================================================================

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

success() {
    echo -e "${GREEN}✓${RESET} $1"
}

warn() {
    echo -e "${YELLOW}!${RESET} $1"
}

error() {
    echo -e "${RED}✗${RESET} $1" >&2
}

# =============================================================================
# Ensure jq is available
# =============================================================================

if ! command -v jq &>/dev/null; then
    error "jq is required for hook merging"
    echo ""
    echo "Install with:"
    echo "  brew install jq    # macOS"
    echo "  apt install jq     # Ubuntu/Debian"
    exit 1
fi

# =============================================================================
# Handle missing target settings
# =============================================================================

if [[ ! -f "$TARGET_SETTINGS" ]]; then
    # No existing settings - just copy Loa's
    cp "$LOA_SETTINGS" "$TARGET_SETTINGS"
    success "Created settings.json (no existing file)"
    exit 0
fi

# =============================================================================
# Create backup
# =============================================================================

BACKUP_FILE="${TARGET_SETTINGS}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$TARGET_SETTINGS" "$BACKUP_FILE"
success "Created backup: $BACKUP_FILE"

# =============================================================================
# Read Loa hooks
# =============================================================================

LOA_SESSION_START=$(jq -c '.hooks.SessionStart // []' "$LOA_SETTINGS")
LOA_USER_PROMPT=$(jq -c '.hooks.UserPromptSubmit // []' "$LOA_SETTINGS")

# =============================================================================
# Merge settings
# =============================================================================

# Determine if we're in integrated mode
INTEGRATED="false"
if [[ -n "$HIVEMIND_PATH" ]] && [[ -d "$HIVEMIND_PATH/library" ]]; then
    INTEGRATED="true"
fi

# Create merged settings using jq
jq --argjson loa_session_start "$LOA_SESSION_START" \
   --argjson loa_user_prompt "$LOA_USER_PROMPT" \
   --arg integrated "$INTEGRATED" '
    # Merge SessionStart hooks (existing first, then Loa)
    .hooks.SessionStart = ((.hooks.SessionStart // []) + $loa_session_start)

    # Add UserPromptSubmit hooks
    | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + $loa_user_prompt)

    # Keep existing Stop and SessionEnd hooks
    | .hooks.Stop = (.hooks.Stop // [])
    | .hooks.SessionEnd = (.hooks.SessionEnd // [])
' "$TARGET_SETTINGS" > "${TARGET_SETTINGS}.tmp"

# Move temp file to target
mv "${TARGET_SETTINGS}.tmp" "$TARGET_SETTINGS"

# =============================================================================
# Report results
# =============================================================================

EXISTING_SESSION_START=$(jq '.hooks.SessionStart | length' "$BACKUP_FILE")
NEW_SESSION_START=$(jq '.hooks.SessionStart | length' "$TARGET_SETTINGS")
EXISTING_USER_PROMPT=$(jq '.hooks.UserPromptSubmit | length // 0' "$BACKUP_FILE")
NEW_USER_PROMPT=$(jq '.hooks.UserPromptSubmit | length' "$TARGET_SETTINGS")

success "Merged settings.json"
echo "  SessionStart hooks: $EXISTING_SESSION_START → $NEW_SESSION_START"
echo "  UserPromptSubmit hooks: $EXISTING_USER_PROMPT → $NEW_USER_PROMPT"

if [[ "$INTEGRATED" == "true" ]]; then
    echo "  Mode: Integrated (HivemindOS detected)"
else
    echo "  Mode: Standalone"
fi

# =============================================================================
# Cleanup old backups (keep last 5)
# =============================================================================

BACKUP_DIR=$(dirname "$TARGET_SETTINGS")
BACKUP_PATTERN=$(basename "$TARGET_SETTINGS").backup.*

cd "$BACKUP_DIR"
ls -t $BACKUP_PATTERN 2>/dev/null | tail -n +6 | xargs -r rm -f
