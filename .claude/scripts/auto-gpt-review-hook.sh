#!/usr/bin/env bash
# PostToolUse Hook - Outputs JSON reminder for GPT review
# Claude sees additionalContext; plain echo is invisible to Claude
#
# IMPORTANT: Hook must consume stdin to avoid hanging (hooks receive JSON input)

# Consume stdin immediately (hooks receive JSON input, ignoring it is fine)
cat > /dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../.loa.config.yaml"

# Silent exit if yq missing
if ! command -v yq &>/dev/null; then
  exit 0
fi

# Silent exit if config missing
if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

# Check if GPT review is enabled
enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
if [[ "$enabled" != "true" ]]; then
  exit 0
fi

# GPT review is enabled - output JSON that Claude will see
# The additionalContext field is injected into Claude's conversation context
#
# Policy:
# - Sprint tasks (/implement, /run): MANDATORY per task (enforced by skill gate)
# - Ad-hoc changes: Optional for trivial changes, but encouraged for substantial ones
cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "Code modified. GPT review policy: If you're executing sprint tasks, GPT review is MANDATORY after each task (see skill instructions). For ad-hoc changes, use judgment - trivial changes (styling, typos) don't need review, but substantial changes should be reviewed. If you've made several code changes without GPT review, consider running one now: Skill: gpt-review, Args: code <file>"
  }
}
EOF

exit 0
