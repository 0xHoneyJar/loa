#!/usr/bin/env bash
# =============================================================================
# PostToolUse:Bash Audit Logger — Log Mutating Commands
# =============================================================================
# Appends JSONL entries for mutating shell commands to .run/audit.jsonl.
# Non-blocking: always exits 0. Failures are silently ignored.
#
# WHY JSONL not structured JSON: JSONL (one JSON object per line) supports
# append-only writes without needing to maintain array structure. This is
# critical for a PostToolUse hook that fires on every command — we can't
# afford to read-modify-write a JSON array on every invocation. JSONL also
# enables simple `tail -f` monitoring and `grep` filtering. The format is
# standard for log pipelines (Elasticsearch, Datadog, CloudWatch Logs).
#
# WHY 10MB rotation threshold: Prevents unbounded log growth during long
# autonomous runs (overnight /run sprint-plan). 10MB holds ~50K entries at
# ~200 bytes per entry, which covers ~24hrs of active agent use. The tail
# -n 1000 rotation keeps the most recent entries for post-mortem analysis.
# (cf. logrotate size-based rotation)
#
# WHY these specific commands: The grep pattern matches commands that modify
# state (git, npm, rm, mv, etc.) and skips read-only commands (cat, ls, grep).
# Logging every command would create noise; logging only mutations creates
# an actionable audit trail. The sudo/env/command prefix detection ensures
# we catch mutations regardless of how they're invoked.
# (Source: bridge-20260213-c011he iter-1 MEDIUM-2 fix)
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
  # Note: jq -c ensures single-line output; --arg escapes newlines as \n in strings
  # Extended schema includes Hounfour-ready fields (empty string when not set).
  # Populated from environment variables if present:
  #   LOA_CURRENT_MODEL, LOA_CURRENT_PROVIDER, LOA_TRACE_ID
  #   LOA_TEAM_ID, LOA_TEAM_MEMBER (Agent Teams identity, v1.39.0)
  # This follows the OpenTelemetry principle: define the trace schema before
  # the instrumentation exists.
  jq -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg cmd "$command" \
    --arg exit_code "$exit_code" \
    --arg cwd "$(pwd)" \
    --arg model "${LOA_CURRENT_MODEL:-}" \
    --arg provider "${LOA_CURRENT_PROVIDER:-}" \
    --arg trace_id "${LOA_TRACE_ID:-}" \
    --arg team_id "${LOA_TEAM_ID:-}" \
    --arg team_member "${LOA_TEAM_MEMBER:-}" \
    '{ts: $ts, tool: "Bash", command: $cmd, exit_code: ($exit_code | tonumber), cwd: $cwd, model: $model, provider: $provider, trace_id: $trace_id, team_id: $team_id, team_member: $team_member}' \
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
