#!/usr/bin/env bash
# PostToolUse Hook - Outputs JSON reminder for GPT review
# Claude sees additionalContext; plain echo is invisible to Claude
#
# IMPORTANT: Hook must consume stdin to avoid hanging (hooks receive JSON input)
# The matcher is now just "Edit|Write" so we filter by file extension here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../.loa.config.yaml"

# Read stdin JSON input (contains tool_input.file_path)
INPUT=$(cat)

# Extract file path from JSON input
FILE_PATH=""
if command -v jq &>/dev/null; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
fi

# Check if file matches code patterns (skip non-code files)
if [[ -n "$FILE_PATH" ]]; then
  if [[ ! "$FILE_PATH" =~ \.(ts|tsx|js|jsx|py|go|rs|java|c|cpp|rb|php|swift|kt|sh)$ ]]; then
    exit 0  # Not a code file, skip silently
  fi
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
# The additionalContext field is injected into Claude's conversation context
#
# This hook provides a comprehensive but concise reminder that includes:
# 1. The core principle (ONE-SHOTTING > VELOCITY)
# 2. Clear criteria for when to review vs skip
# 3. Exact invocation syntax
# 4. Context file preparation steps
#
# Fixed: 2026-01-29 - Matcher changed from regex to "Edit|Write", script filters by extension
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "GPT REVIEW CHECKPOINT: You modified ${FILE_PATH:-code}. Before proceeding to next task: (1) Write /tmp/gpt-review-expertise.md with domain expertise from PRD, (2) Write /tmp/gpt-review-context.md with product context + what this code does + acceptance criteria, (3) Use Skill tool: gpt-review, Args: code ${FILE_PATH:-<file>}. SKIP ONLY IF truly trivial (typo, log message, comment, import reorder). Backend/API/security/business logic = ALWAYS review. When uncertain, review."
  }
}
EOF

exit 0
