#!/usr/bin/env bash
# Toggle GPT review enabled/disabled in .loa.config.yaml
# Usage: gpt-review-toggle.sh
#
# This script:
# 1. Toggles gpt_review.enabled in config
# 2. Runs inject-gpt-review-gates.sh to update all skills/commands/CLAUDE.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.loa.config.yaml"

# Check if yq is available
if ! command -v yq &>/dev/null; then
  echo "Error: yq is required but not installed" >&2
  exit 1
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found at $CONFIG_FILE" >&2
  exit 1
fi

# Get current state
current=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")

# Toggle it
if [[ "$current" == "true" ]]; then
  yq eval -i '.gpt_review.enabled = false' "$CONFIG_FILE"
  echo "GPT Review: DISABLED"
else
  yq eval -i '.gpt_review.enabled = true' "$CONFIG_FILE"
  echo "GPT Review: ENABLED"
fi

# Run injection script to update all files
"$SCRIPT_DIR/inject-gpt-review-gates.sh"

echo ""
echo "Restart your Claude session for changes to take effect."

exit 0
