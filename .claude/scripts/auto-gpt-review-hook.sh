#!/usr/bin/env bash
# Auto GPT Review Hook - Outputs reminder after code changes
# Only outputs if GPT review is enabled in config

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../.loa.config.yaml"

# Check if GPT review is enabled - exit silently if not
if ! command -v yq &>/dev/null; then
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
if [[ "$enabled" != "true" ]]; then
  exit 0
fi

# GPT review is enabled - output reminder
echo ""
echo ">> GPT Review: Run .claude/scripts/gpt-review-api.sh code <file> on changed files"
echo "   For re-reviews after fixes, use: --iteration N --previous /tmp/gpt-review-findings-{N-1}.json"
echo ""

exit 0
