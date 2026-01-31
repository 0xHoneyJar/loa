#!/usr/bin/env bash
# Manage GPT review context file based on config
# Called by gpt-review-toggle.sh after toggling the config setting
#
# SIMPLIFIED ARCHITECTURE (v2.0):
# - PostToolUse hooks provide automatic reminders after each Edit/Write
# - Commands load context file via context_files (when it exists)
# - No more skill/command file injection (fragile and redundant)
#
# The hooks are comprehensive enough to guide Claude through the review process.
# The context file provides detailed instructions when loaded at command start.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.loa.config.yaml"
CONTEXT_DIR="$ROOT_DIR/.claude/context"
CONTEXT_FILE="$CONTEXT_DIR/gpt-review-active.md"
TEMPLATE_FILE="$ROOT_DIR/.claude/templates/gpt-review-instructions.md.template"

# Check if yq is available
if ! command -v yq &>/dev/null; then
  exit 0
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  # No config - remove context file
  rm -f "$CONTEXT_FILE"
  exit 0
fi

# Check if GPT review is enabled
enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")

if [[ "$enabled" == "true" ]]; then
  # Create context file from template (loaded by commands via context_files)
  mkdir -p "$CONTEXT_DIR"
  if [[ -f "$TEMPLATE_FILE" ]]; then
    cp "$TEMPLATE_FILE" "$CONTEXT_FILE"
    echo "GPT review enabled: context file created at $CONTEXT_FILE"
  else
    echo "Warning: Template file not found at $TEMPLATE_FILE"
  fi
else
  # Remove context file
  rm -f "$CONTEXT_FILE"
  echo "GPT review disabled: context file removed"
fi

exit 0
