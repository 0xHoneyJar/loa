#!/usr/bin/env bash
# PostToolUse Hook - GPT Review checkpoint for ALL Edit/Write operations
#
# Reads phase toggles from config and tells Claude exactly which review
# types are enabled/disabled, so it doesn't waste tokens preparing
# context files for disabled review types.

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

# Check if GPT review is enabled (master toggle)
master_enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
if [[ "$master_enabled" != "true" ]]; then
  exit 0
fi

# Read phase toggles
prd_enabled=$(yq eval '.gpt_review.phases.prd // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
sdd_enabled=$(yq eval '.gpt_review.phases.sdd // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
sprint_enabled=$(yq eval '.gpt_review.phases.sprint // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
impl_enabled=$(yq eval '.gpt_review.phases.implementation // true' "$CONFIG_FILE" 2>/dev/null || echo "true")

# Build enabled/disabled lists
enabled_types=""
disabled_types=""

if [[ "$prd_enabled" == "true" ]]; then
  enabled_types+="prd, "
else
  disabled_types+="prd, "
fi

if [[ "$sdd_enabled" == "true" ]]; then
  enabled_types+="sdd, "
else
  disabled_types+="sdd, "
fi

if [[ "$sprint_enabled" == "true" ]]; then
  enabled_types+="sprint, "
else
  disabled_types+="sprint, "
fi

if [[ "$impl_enabled" == "true" ]]; then
  enabled_types+="code, "
else
  disabled_types+="code, "
fi

# Trim trailing comma and space
enabled_types="${enabled_types%, }"
disabled_types="${disabled_types%, }"

# Build the message
if [[ -n "$disabled_types" ]]; then
  phase_info="ENABLED: ${enabled_types}. DISABLED: ${disabled_types}. If file relates to DISABLED type, skip review entirely (no context files needed)."
else
  phase_info="ALL TYPES ENABLED: ${enabled_types}."
fi

# Generate secure temp directory path using TMPDIR with session isolation
SECURE_TMP="${TMPDIR:-/tmp}/gpt-review-$$"

# Output checkpoint message with phase-specific guidance
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "STOP. GPT Review Checkpoint. Modified: ${FILE_PATH:-a file}. ${phase_info} REVIEW RULES: (1) Design docs (prd.md, sdd.md, sprint.md) - review if type enabled, (2) Backend/API/security/business logic - review if code enabled, (3) Trivial changes (typos, comments, logs) - always skip. TO REVIEW: Create dir ${SECURE_TMP} (chmod 700), write expertise.md + context.md there, then invoke Skill: gpt-review with Args (prd|sdd|sprint|code <file>). Do NOT proceed until APPROVED or SKIPPED verdict."
  }
}
EOF

exit 0
