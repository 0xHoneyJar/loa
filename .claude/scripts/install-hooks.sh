#!/bin/bash
# Install Loa Hooks into Target Project
# Usage: install-hooks.sh <target_dir> [--integrated]
#
# Copies:
# - statusline.sh → .claude/statusline.sh (or merged version if --integrated)
# - hooks/detect-frame.sh → .claude/hooks/detect-frame.sh
# - hooks/session-init.sh → .claude/hooks/session-init.sh
# - Merges settings.json hooks (uses merge-hooks.sh)

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# =============================================================================
# Arguments
# =============================================================================

TARGET_DIR="${1:-}"
INTEGRATED_FLAG="${2:-}"

if [ -z "$TARGET_DIR" ]; then
  echo "Usage: install-hooks.sh <target_dir> [--integrated]"
  echo ""
  echo "Installs Loa frame hooks into the target project."
  echo ""
  echo "Arguments:"
  echo "  target_dir    - Target project directory"
  echo "  --integrated  - Use merged status line (HivemindOS integration)"
  echo ""
  echo "Files installed:"
  echo "  - .claude/statusline.sh"
  echo "  - .claude/hooks/detect-frame.sh"
  echo "  - .claude/hooks/session-init.sh"
  echo "  - .claude/settings.json (merged)"
  exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: Target directory does not exist: $TARGET_DIR"
  exit 1
fi

# Detect integration mode
INTEGRATED="false"
if [ "$INTEGRATED_FLAG" = "--integrated" ]; then
  INTEGRATED="true"
elif [ -n "${HIVEMIND_PATH:-}" ] && [ -d "${HIVEMIND_PATH}/library" ]; then
  INTEGRATED="true"
fi

# =============================================================================
# ANSI Colors
# =============================================================================

GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

success() {
  echo -e "${GREEN}✓${RESET} $1"
}

warn() {
  echo -e "${YELLOW}!${RESET} $1"
}

# =============================================================================
# Create Directories
# =============================================================================

mkdir -p "$TARGET_DIR/.claude/hooks"
mkdir -p "$TARGET_DIR/.loa"

# =============================================================================
# Copy Hooks
# =============================================================================

cp "$LOA_DIR/hooks/detect-frame.sh" "$TARGET_DIR/.claude/hooks/"
chmod +x "$TARGET_DIR/.claude/hooks/detect-frame.sh"
success "Installed hooks/detect-frame.sh"

cp "$LOA_DIR/hooks/session-init.sh" "$TARGET_DIR/.claude/hooks/"
chmod +x "$TARGET_DIR/.claude/hooks/session-init.sh"
success "Installed hooks/session-init.sh"

# =============================================================================
# Copy Status Line
# =============================================================================

if [ "$INTEGRATED" = "true" ] && [ -n "${HIVEMIND_PATH:-}" ]; then
  # Use HivemindOS merged status line (it reads from both session files)
  if [ -f "${HIVEMIND_PATH}/.claude/statusline.sh" ]; then
    cp "${HIVEMIND_PATH}/.claude/statusline.sh" "$TARGET_DIR/.claude/"
    chmod +x "$TARGET_DIR/.claude/statusline.sh"
    success "Installed merged statusline.sh (HivemindOS integrated)"
  else
    # Fallback to Loa status line
    cp "$LOA_DIR/statusline.sh" "$TARGET_DIR/.claude/"
    chmod +x "$TARGET_DIR/.claude/statusline.sh"
    warn "HivemindOS statusline.sh not found, using Loa statusline"
  fi
else
  # Standalone mode - use Loa status line
  cp "$LOA_DIR/statusline.sh" "$TARGET_DIR/.claude/"
  chmod +x "$TARGET_DIR/.claude/statusline.sh"
  success "Installed statusline.sh"
fi

# =============================================================================
# Merge Settings.json
# =============================================================================

TARGET_SETTINGS="$TARGET_DIR/.claude/settings.json"
LOA_SETTINGS="$LOA_DIR/settings.json"

# Use merge-hooks.sh if available, otherwise fall back to inline logic
if [ -f "$SCRIPT_DIR/merge-hooks.sh" ]; then
  # Use dedicated merge script
  if [ "$INTEGRATED" = "true" ]; then
    "$SCRIPT_DIR/merge-hooks.sh" "$TARGET_SETTINGS" "$LOA_SETTINGS" "${HIVEMIND_PATH:-}"
  else
    "$SCRIPT_DIR/merge-hooks.sh" "$TARGET_SETTINGS" "$LOA_SETTINGS"
  fi
elif [ -f "$TARGET_SETTINGS" ]; then
  # Fallback: Merge settings using jq
  if command -v jq &> /dev/null; then
    # Create merged settings
    # Loa statusLine takes precedence
    # Hooks are merged (Loa hooks added to existing)
    jq -s '
      .[0] as $existing |
      .[1] as $loa |
      $existing * {
        statusLine: $loa.statusLine,
        hooks: {
          SessionStart: (($existing.hooks.SessionStart // []) + ($loa.hooks.SessionStart // [])),
          UserPromptSubmit: (($existing.hooks.UserPromptSubmit // []) + ($loa.hooks.UserPromptSubmit // [])),
          Stop: ($existing.hooks.Stop // []),
          SessionEnd: ($existing.hooks.SessionEnd // [])
        }
      }
    ' "$TARGET_SETTINGS" "$LOA_SETTINGS" > "${TARGET_SETTINGS}.tmp"

    mv "${TARGET_SETTINGS}.tmp" "$TARGET_SETTINGS"
    success "Merged settings.json (preserved existing hooks)"
  else
    warn "jq not found - overwriting settings.json"
    cp "$LOA_SETTINGS" "$TARGET_SETTINGS"
    success "Installed settings.json"
  fi
else
  # No existing settings, just copy
  cp "$LOA_SETTINGS" "$TARGET_SETTINGS"
  success "Installed settings.json"
fi

# =============================================================================
# Create .loa directory structure
# =============================================================================

touch "$TARGET_DIR/.loa/.gitkeep"
success "Created .loa/ directory"

# =============================================================================
# Add to .gitignore
# =============================================================================

GITIGNORE="$TARGET_DIR/.gitignore"

if [ -f "$GITIGNORE" ]; then
  if ! grep -q ".loa/.session" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# Loa session state (transient)" >> "$GITIGNORE"
    echo ".loa/.session" >> "$GITIGNORE"
    success "Added .loa/.session to .gitignore"
  else
    success ".loa/.session already in .gitignore"
  fi
else
  echo "# Loa session state (transient)" > "$GITIGNORE"
  echo ".loa/.session" >> "$GITIGNORE"
  success "Created .gitignore with .loa/.session"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "Loa hooks installed successfully!"
echo ""
echo "Files installed:"
echo "  - .claude/statusline.sh"
echo "  - .claude/hooks/detect-frame.sh"
echo "  - .claude/hooks/session-init.sh"
echo "  - .claude/settings.json"
echo "  - .loa/.gitkeep"
echo ""
echo "Start a new Claude Code session to activate."
