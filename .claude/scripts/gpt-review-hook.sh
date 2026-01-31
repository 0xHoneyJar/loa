#!/usr/bin/env bash
# PostToolUse Hook - GPT Review checkpoint for ALL Edit/Write operations
# Claude decides whether review is needed based on what was modified
#
# No file extension or path matching - just outputs the policy and lets
# Claude evaluate whether the change requires GPT review.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../.loa.config.yaml"

# Read stdin JSON input (hooks receive JSON with tool_input)
INPUT=$(cat)

# Extract file path from JSON input
FILE_PATH=""
if command -v jq &>/dev/null; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
fi

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

# GPT review is enabled - output checkpoint message
# Claude evaluates whether this specific edit needs review
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "STOP. GPT Review Checkpoint. You modified: ${FILE_PATH:-a file}. Evaluate: Does this change require GPT cross-model review? REQUIRES REVIEW: (1) Design docs (prd.md, sdd.md, sprint.md) - ALWAYS review before declaring phase complete, (2) Backend/API/security/business logic code - ALWAYS review, (3) New files or major refactors - ALWAYS review. SKIP REVIEW: Trivial changes (typos, comments, log messages, import reordering, .gitignore, config formatting). If review needed: Write /tmp/gpt-review-expertise.md + /tmp/gpt-review-context.md, then invoke Skill: gpt-review with appropriate Args (prd|sdd|sprint|code <file>). Do NOT proceed to next task or declare phase complete until APPROVED or SKIPPED verdict received."
  }
}
EOF

exit 0
