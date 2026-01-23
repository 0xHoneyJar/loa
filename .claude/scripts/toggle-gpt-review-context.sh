#!/usr/bin/env bash
# Toggle GPT review context file based on config
# Called by SessionStart hook to conditionally load GPT review instructions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.loa.config.yaml"
TEMPLATE_FILE="$ROOT_DIR/.claude/templates/gpt-review-instructions.md.template"
CONTEXT_FILE="$ROOT_DIR/.claude/context/gpt-review-active.md"

# Check if yq is available
if ! command -v yq &>/dev/null; then
  # Can't check config without yq, skip silently
  exit 0
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  # No config, remove context file if exists
  rm -f "$CONTEXT_FILE"
  exit 0
fi

# Check if GPT review is enabled
enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")

if [[ "$enabled" == "true" ]]; then
  # GPT review is enabled - create context file from template
  if [[ -f "$TEMPLATE_FILE" ]]; then
    cp "$TEMPLATE_FILE" "$CONTEXT_FILE"
  fi
else
  # GPT review is disabled - remove context file if exists
  rm -f "$CONTEXT_FILE"
fi

exit 0
