#!/usr/bin/env bash
# PostToolUse Hook for document files - Outputs JSON reminder for GPT review
# Triggers when PRD, SDD, or sprint documents are created/modified
#
# IMPORTANT: Hook must consume stdin to avoid hanging (hooks receive JSON input)

# Consume stdin immediately
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

# Determine document type from the tool invocation path
# The matcher captures the filename in the path
DOC_TYPE=""
if [[ "${CLAUDE_TOOL_ARG:-}" =~ prd\.md ]]; then
  DOC_TYPE="prd"
elif [[ "${CLAUDE_TOOL_ARG:-}" =~ sdd\.md ]]; then
  DOC_TYPE="sdd"
elif [[ "${CLAUDE_TOOL_ARG:-}" =~ sprint\.md ]]; then
  DOC_TYPE="sprint"
fi

# GPT review is enabled - output JSON that Claude will see
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "IMPORTANT: You just created/modified a design document. GPT cross-model review is ENABLED. Before marking this phase complete, you MUST run: /gpt-review ${DOC_TYPE:-document}. This is a mandatory step in your workflow - check your success criteria."
  }
}
EOF

exit 0
