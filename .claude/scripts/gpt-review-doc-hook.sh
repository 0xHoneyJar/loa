#!/usr/bin/env bash
# PostToolUse Hook for document files - Outputs JSON reminder for GPT review
# Triggers when PRD, SDD, or sprint documents are created/modified
#
# IMPORTANT: Hook must consume stdin to avoid hanging (hooks receive JSON input)
# The matcher is now just "Edit|Write" so we filter by file path here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../.loa.config.yaml"

# Read stdin JSON input (contains tool_input.file_path)
INPUT=$(cat)

# Extract file path from JSON input
FILE_PATH=""
if command -v jq &>/dev/null; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
fi

# Determine document type from file path
DOC_TYPE=""
if [[ "$FILE_PATH" =~ prd\.md$ ]]; then
  DOC_TYPE="prd"
elif [[ "$FILE_PATH" =~ sdd\.md$ ]]; then
  DOC_TYPE="sdd"
elif [[ "$FILE_PATH" =~ sprint\.md$ ]]; then
  DOC_TYPE="sprint"
fi

# Skip if not a design document
if [[ -z "$DOC_TYPE" ]]; then
  exit 0
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

# GPT review is enabled - output JSON that Claude will see
# Uses STOP language like audit-sprint to make it a hard gate
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "STOP. You modified ${FILE_PATH}. GPT cross-model review is MANDATORY before proceeding. Do NOT declare this phase complete. Do NOT suggest the next command. Do NOT say 'ready for /architect' or similar. FIRST: (1) Write /tmp/gpt-review-expertise.md with domain expertise from the PRD, (2) Write /tmp/gpt-review-context.md with product context and what to verify, (3) Invoke: Skill: gpt-review, Args: ${DOC_TYPE}. ONLY after receiving APPROVED or SKIPPED verdict may you proceed. If CHANGES_REQUIRED, fix issues and re-invoke."
  }
}
EOF

exit 0
