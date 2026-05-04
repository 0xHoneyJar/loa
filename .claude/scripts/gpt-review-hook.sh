#!/usr/bin/env bash
# PostToolUse Hook - GPT Review checkpoint for ALL Edit/Write operations
#
# Closes #711 (zkSoju feedback): the prior hook fired unconditionally on
# every Edit/Write when gpt_review.enabled=true. Trivial frontmatter
# version bumps and writes to temp-dir context files (expertise.md,
# context.md) all triggered the checkpoint, demanding new review temp
# dirs and consuming ~30 min of session time on review-cycle navigation.
#
# Two surgical fixes implemented in-hook:
#   1. PATH ALLOWLIST — only fire for review-scope paths:
#        grimoires/loa/(prd|sdd|sprint).md (any cycle subdir)
#        src/, lib/, app/ (project code paths)
#      Out-of-scope paths exit 0 silently (gpt-review temp dirs included).
#      Note: .claude/ (System Zone) is deliberately EXCLUDED from default
#      scope — System Zone changes are gated upstream via cycle-level
#      authorization, not via the gpt-review checkpoint.
#   2. TRIVIAL-EDIT DETECT — for Edit tool only:
#        if old_string + new_string are entirely within YAML frontmatter
#        delimiters (`---\n...\n---`), exit 0 silently.
#
# Conservative default: when classification is ambiguous (empty file_path,
# malformed input), SKIP rather than fire. Better to under-trigger than
# spam the agent on every keystroke (the original bug).
#
# Reads phase toggles from config and tells Claude exactly which review
# types are enabled/disabled, so it doesn't waste tokens preparing
# context files for disabled review types.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../.loa.config.yaml"

# Read stdin JSON input (hooks receive JSON with tool_input)
INPUT=$(cat)

# Silent exit if jq missing.
if ! command -v jq &>/dev/null; then
  exit 0
fi
# Silent exit if input is not parseable JSON.
if ! echo "$INPUT" | jq empty 2>/dev/null; then
  exit 0
fi

# Extract file path + tool name + old_string + new_string from JSON input.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty' 2>/dev/null)
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null)

# Silent exit if yq missing (config can't be read).
if ! command -v yq &>/dev/null; then
  exit 0
fi

# Silent exit if config missing.
if [[ ! -f "$CONFIG_FILE" ]]; then
  exit 0
fi

# Master toggle.
master_enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
if [[ "$master_enabled" != "true" ]]; then
  exit 0
fi

# -----------------------------------------------------------------------------
# Fix 1 — Path allowlist (#711 zkSoju feedback)
# -----------------------------------------------------------------------------
# Conservative: empty file_path → SKIP (cannot classify).
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Read scope patterns from config (one per line) or use defaults.
SCOPE_PATTERNS=$(yq eval '.gpt_review.review_scope_paths[]? // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
if [[ -z "$SCOPE_PATTERNS" ]]; then
  # Defaults: grimoires/loa md+yaml, plus standard project code dirs.
  SCOPE_PATTERNS=$'grimoires/loa/.*\\.(md|yaml)$\nsrc/\nlib/\napp/'
fi

# Path matches if it contains any of the scope patterns.
in_scope=0
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  if echo "$FILE_PATH" | grep -qE "$pattern"; then
    in_scope=1
    break
  fi
done <<< "$SCOPE_PATTERNS"

if [[ "$in_scope" != "1" ]]; then
  # Out-of-scope (e.g., /tmp/gpt-review-XXX/expertise.md, scratch files).
  exit 0
fi

# -----------------------------------------------------------------------------
# Fix 2 — Trivial-edit detection (#711 zkSoju feedback)
# -----------------------------------------------------------------------------
# For Edit tool only, when old_string + new_string are both ENTIRELY WITHIN
# YAML frontmatter delimiters (`---\n…\n---`), exit 0 silently.

is_frontmatter_only() {
  local s="$1"
  # Iter-1 review MEDIUM (argv-cliff): pass via stdin (not argv) so very
  # large frontmatter-only edits (>128KB ARG_MAX) don't silently fail.
  # Bridgebuilder iter-1 MEDIUM (CRLF brittleness): the prior regex was
  # LF-only; Windows editors emit CRLF + trailing whitespace + missing
  # final newline. Now: normalize line endings + tolerate trailing ws.
  printf '%s' "$s" | python3 - 2>/dev/null <<'PY'
import sys, re
s = sys.stdin.read()
# Normalize CRLF / CR → LF so subsequent matching is uniform.
s = s.replace("\r\n", "\n").replace("\r", "\n")
# Strip optional UTF-8 BOM.
if s.startswith("﻿"):
    s = s[1:]
# Frontmatter is `---` (with optional surrounding whitespace) on a line
# of its own, then YAML body, then a closing `---` line. Trailing newline
# is OPTIONAL (some editors strip it).
m = re.match(r'\A\s*---[ \t]*\n.*?\n---[ \t]*(?:\n|$)', s, re.S)
if not m:
    sys.exit(1)
remainder = s[m.end():]
# Frontmatter-only iff the remainder is empty or whitespace.
if remainder.strip() == "":
    sys.exit(0)
sys.exit(1)
PY
  return $?
}

if [[ "$TOOL_NAME" == "Edit" ]] && [[ -n "$OLD_STRING" ]] && [[ -n "$NEW_STRING" ]]; then
  if is_frontmatter_only "$OLD_STRING" && is_frontmatter_only "$NEW_STRING"; then
    # Frontmatter-only edit (e.g., version: 1.1.0 → 1.2.0). SKIP silently.
    exit 0
  fi
fi

# -----------------------------------------------------------------------------
# Fall through to existing checkpoint emission.
# -----------------------------------------------------------------------------

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
