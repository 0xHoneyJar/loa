#!/usr/bin/env bash
# =============================================================================
# PostToolUse:Write/Edit Audit Logger — Log File Modifications
# =============================================================================
# Appends JSONL entries for Write/Edit tool operations to .run/audit.jsonl.
# Non-blocking: always exits 0. Failures are silently ignored.
#
# Complements mutation-logger.sh (PostToolUse:Bash) by capturing file
# modifications made via the Write and Edit tools. Without this hook,
# teammate modifications via Write/Edit are invisible to the audit trail.
#
# WHY a separate script: Write/Edit tools have different input format from
# Bash (tool_input.file_path vs tool_input.command). Sharing mutation-logger.sh
# would require complex input dispatch logic. A separate script is cleaner.
#
# WHY no content logging: File content is not logged — only the file path.
# Content could contain secrets, and JSONL entries should stay small for
# rotation compatibility with mutation-logger.sh's 10MB threshold.
#
# Registered in settings.hooks.json as PostToolUse matcher: "Write", "Edit"
# Part of Agent Teams Compatibility (cycle-020, issue #337)
# Source: Sprint 4 — Advisory-to-Mechanical Promotion (audit gap)
# =============================================================================

# Read tool input from stdin
input=$(cat)

# Extract file path (same field for both Write and Edit tools)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# Nothing to log if we can't parse the path
if [[ -z "$file_path" ]]; then
  exit 0
fi

# Determine tool name from context (PostToolUse provides tool_name)
tool_name=$(echo "$input" | jq -r '.tool_name // "Write"' 2>/dev/null) || true

# Ensure .run/ exists
mkdir -p .run 2>/dev/null

AUDIT_FILE=".run/audit.jsonl"

# Log rotation is handled by mutation-logger.sh (PostToolUse:Bash) which fires
# more frequently and rotates at 10MB. No separate rotation needed here.

# Append JSONL entry — same format as mutation-logger.sh for compatibility
jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg tool "$tool_name" \
  --arg file_path "$file_path" \
  --arg cwd "$(pwd)" \
  --arg model "${LOA_CURRENT_MODEL:-}" \
  --arg provider "${LOA_CURRENT_PROVIDER:-}" \
  --arg trace_id "${LOA_TRACE_ID:-}" \
  --arg team_id "${LOA_TEAM_ID:-}" \
  --arg team_member "${LOA_TEAM_MEMBER:-}" \
  '{ts: $ts, tool: $tool, file_path: $file_path, cwd: $cwd, model: $model, provider: $provider, trace_id: $trace_id, team_id: $team_id, team_member: $team_member}' \
  >> "$AUDIT_FILE" 2>/dev/null

# Always exit 0 — PostToolUse hooks must never block operations
exit 0
