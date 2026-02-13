#!/usr/bin/env bash
# =============================================================================
# PostToolUse:Bash Audit Logger — Log Mutating Commands
# =============================================================================
# Appends JSONL entries for mutating shell commands to .run/audit.jsonl.
# Non-blocking: always exits 0. Failures are silently ignored.
#
# Registered in settings.hooks.json as PostToolUse matcher: "Bash"
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: Trail of Bits PostToolUse audit pattern
# =============================================================================

# Read tool input from stdin
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
exit_code=$(echo "$input" | jq -r '.tool_result.exit_code // 0' 2>/dev/null)

# If we can't parse, skip silently
if [[ -z "$command" ]]; then
  exit 0
fi

# Only log mutating commands (skip read-only operations)
# Handles: direct commands, prefixed (sudo, env, command), and chained (&&, ;, |)
if echo "$command" | grep -qEi '(^|&&|;|\|)\s*(sudo\s+)?(env\s+[^ ]+\s+)?(command\s+)?(git|npm|pip|cargo|rm|mv|cp|mkdir|chmod|chown|docker|kubectl|make|yarn|pnpm|npx)\s'; then
  # Create .run directory if needed
  mkdir -p .run 2>/dev/null || true

  # Append JSONL entry (compact, one JSON object per line)
  jq -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg cmd "$command" \
    --arg exit_code "$exit_code" \
    --arg cwd "$(pwd)" \
    '{ts: $ts, tool: "Bash", command: $cmd, exit_code: ($exit_code | tonumber), cwd: $cwd}' \
    >> .run/audit.jsonl 2>/dev/null || true

  # Log rotation: if file exceeds 10MB, keep last 1000 entries
  if [[ -f .run/audit.jsonl ]]; then
    size=$(stat -f%z .run/audit.jsonl 2>/dev/null || stat -c%s .run/audit.jsonl 2>/dev/null || echo "0")
    if [[ "$size" -gt 10485760 ]]; then
      tail -n 1000 .run/audit.jsonl > .run/audit.jsonl.tmp 2>/dev/null && \
        mv .run/audit.jsonl.tmp .run/audit.jsonl 2>/dev/null || true
    fi
  fi
fi

# Always exit 0 — audit logging must never block execution
exit 0
