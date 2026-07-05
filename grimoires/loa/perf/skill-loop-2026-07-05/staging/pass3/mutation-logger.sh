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
# perf pass-3 (2026-07-05, skill-loop): jq single-pass consolidation. Was:
# $(cat) + jq x2 field extractions + (mutating path) jq -cn builder + date.
# Now: ONE jq reads stdin directly, extracts the command AND pre-builds the
# audit JSONL line; bash decides (same grep filter) whether to append it.
# Encoding + isomorphism notes:
#   - Output fields are NUL-delimited. Command strings are untrusted and can
#     contain tabs/newlines/quotes/backslashes; jq @tsv would REWRITE those
#     bytes (escaping tabs/newlines), so it is unusable here. NUL is the one
#     byte that never survives into the fields themselves: JSON NUL escapes
#     (backslash-u-0000) decoded by jq are STRIPPED from values via string
#     division (`. / $z | join("")`), then trailing newlines are stripped
#     (`sub` in scap) — together byte-identical to what the old
#     `command=$(...)` command substitution did (bash drops NUL bytes from
#     $() output and strips trailing newlines). The NUL string itself is
#     built with `[0] | implode` — no escape literal appears in this file
#     (authoring-tool constraint).
#   - The old code's bash "ignored null byte" stderr warning for such
#     payloads disappears (cosmetic; decisions and logged bytes identical).
#   - Non-string .command values (out of hook contract) render via tojson
#     (compact) where the old jq -r rendered containers pretty-printed;
#     scalars are byte-identical. The grep decision on a container command
#     therefore tests compact instead of pretty bytes — both are garbage
#     inputs Claude Code cannot produce.
#   - Timestamp: `now | todate` emits %Y-%m-%dT%H:%M:%SZ UTC — byte-identical
#     to the old `date -u +%Y-%m-%dT%H:%M:%SZ` spawn (verified on host).
#   - exit_code keeps the old tonumber semantics: a non-numeric exit_code
#     makes the BUILDER fail (empty line -> nothing appended) while the
#     grep filter and rotation still run — exactly the old
#     `jq -cn ... || true` behavior.
#   - $(pwd) -> $PWD (pass-2 precedent), removing a subshell fork.
#   - Multi-document stdin (not producible by Claude Code hooks, which send
#     exactly one JSON object) that errors mid-stream used to log a
#     truncated prefix; the consolidated parse skips logging instead.
#     Single-document payloads — including every malformed shape — are
#     byte-identical.
#
# Registered in settings.hooks.json as PostToolUse matcher: "Bash"
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: Trail of Bits PostToolUse audit pattern
# =============================================================================

# ONE jq: parse stdin, emit <command> NUL <prebuilt-jsonl-or-empty> NUL.
# Parse/eval failures produce 0 fields -> handled exactly like the old
# empty-command case (exit 0, no side effects).
mapfile -d '' -t _ml_fields < <(
  jq -sj \
    --arg cwd "$PWD" \
    --arg model "${LOA_CURRENT_MODEL:-}" \
    --arg provider "${LOA_CURRENT_PROVIDER:-}" \
    --arg trace_id "${LOA_TRACE_ID:-}" \
    --arg team_id "${LOA_TEAM_ID:-}" \
    --arg team_member "${LOA_TEAM_MEMBER:-}" '
    def denul($z): . / $z | join("");
    def scap($z): denul($z) | sub("\n+$"; "");
    ([0] | implode) as $z |
    try (
      (map(.tool_input.command // empty | if type == "string" then . else tojson end) | join("\n") | scap($z)) as $cmd |
      (try (map(.tool_result.exit_code // 0) | join("\n") | scap($z)) catch "") as $ec |
      (try ({ts: (now | todate), tool: "Bash", command: $cmd,
             exit_code: ($ec | tonumber), cwd: $cwd, model: $model,
             provider: $provider, trace_id: $trace_id, team_id: $team_id,
             team_member: $team_member} | tojson)
       catch "") as $line |
      ($cmd + $z + $line + $z)
    ) catch ""
  ' 2>/dev/null
)
command="${_ml_fields[0]-}"
audit_line="${_ml_fields[1]-}"

# If we can't parse, skip silently
if [[ -z "$command" ]]; then
  exit 0
fi

# Only log mutating commands (skip read-only operations)
# Handles: direct commands, prefixed (sudo, env, command), and chained (&&, ;, |)
if echo "$command" | grep -qEi '(^|&&|;|\|)\s*(sudo\s+)?(env\s+[^ ]+\s+)?(command\s+)?(git|npm|pip|cargo|rm|mv|cp|mkdir|chmod|chown|docker|kubectl|make|yarn|pnpm|npx)\s'; then
  # Create .run directory if needed
  mkdir -p .run 2>/dev/null || true

  # Append the pre-built JSONL entry (compact, one JSON object per line).
  # Extended schema includes Hounfour-ready fields (empty string when not set).
  # Populated from environment variables if present:
  #   LOA_CURRENT_MODEL, LOA_CURRENT_PROVIDER, LOA_TRACE_ID
  #   LOA_TEAM_ID, LOA_TEAM_MEMBER (Agent Teams identity, v1.39.0)
  # This follows the OpenTelemetry principle: define the trace schema before
  # the instrumentation exists.
  if [[ -n "$audit_line" ]]; then
    printf '%s\n' "$audit_line" >> .run/audit.jsonl 2>/dev/null || true
  else
    # Builder failed (e.g. non-numeric exit_code): the old `jq -cn ... >>
    # .run/audit.jsonl || true` still OPENED the log via the redirection even
    # when jq emitted nothing — preserve that file-creation side effect.
    : >> .run/audit.jsonl 2>/dev/null || true
  fi

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
