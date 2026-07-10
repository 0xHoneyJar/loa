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
# perf pass-3 (2026-07-05, skill-loop): jq single-pass consolidation. Was:
# $(cat) + jq x2 field extractions + jq -cn builder + date on EVERY
# Write/Edit. Now: ONE jq reads stdin directly, extracts file_path AND
# pre-builds the audit JSONL line. Same encoding contract as
# mutation-logger.sh pass-3:
#   - NUL-delimited fields ("[0] | implode" builds the NUL string; no escape
#     literal appears in this file). File paths can contain tabs/newlines —
#     @tsv would rewrite those bytes and is unusable here.
#   - JSON NUL escapes (backslash-u-0000) in values are stripped via string
#     division AND trailing newlines are stripped (scap) — byte-identical to
#     the old $() command-substitution behavior (minus bash's cosmetic
#     "ignored null byte" stderr warning). The strip is decision-relevant:
#     a file_path rendering to only-newlines must stay "empty" (no append),
#     exactly like the old $()-stripped emptiness test.
#   - Non-string file_path/tool_name values (out of hook contract) render
#     via tojson (compact) where the old jq -r rendered containers
#     pretty-printed; scalars are byte-identical.
#   - `now | todate` replaces the `date -u` spawn (byte-identical format).
#   - $(pwd) -> $PWD (pass-2 precedent).
#   - The pre-built line is byte-identical to the old jq -cn output: same
#     key order, same string encoder (tojson == jq -c rendering).
#
# perf pass-4 (2026-07-05, skill-loop): `mkdir -p .run` guarded by a builtin
# [[ -d ]] test — the spawn only happens when .run is actually missing.
#
# Registered in settings.hooks.json as PostToolUse matcher: "Write", "Edit"
# Part of Agent Teams Compatibility (cycle-020, issue #337)
# Source: Sprint 4 — Advisory-to-Mechanical Promotion (audit gap)
# =============================================================================

# ONE jq: parse stdin, emit <file_path> NUL <prebuilt-jsonl> NUL.
# Parse/eval failures produce 0 fields -> treated exactly like the old
# unparseable-path case (exit 0, no side effects).
mapfile -d '' -t _wml_fields < <(
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
      (map(.tool_input.file_path // empty | if type == "string" then . else tojson end) | join("\n") | scap($z)) as $fp |
      (map(.tool_name // "Write" | if type == "string" then . else tojson end) | join("\n") | scap($z)) as $tool |
      ({ts: (now | todate), tool: $tool, file_path: $fp, cwd: $cwd,
        model: $model, provider: $provider, trace_id: $trace_id,
        team_id: $team_id, team_member: $team_member} | tojson) as $line |
      ($fp + $z + $line + $z)
    ) catch ""
  ' 2>/dev/null
)
file_path="${_wml_fields[0]-}"
audit_line="${_wml_fields[1]-}"

# Nothing to log if we can't parse the path
if [[ -z "$file_path" ]]; then
  exit 0
fi

# Ensure .run/ exists (perf pass-4: [[ -d ]] guard skips the mkdir spawn in
# the steady state where .run already exists)
[[ -d .run ]] || mkdir -p .run 2>/dev/null

AUDIT_FILE=".run/audit.jsonl"

# Log rotation is handled by mutation-logger.sh (PostToolUse:Bash) which fires
# more frequently and rotates at 10MB. No separate rotation needed here.

# Append JSONL entry — same format as mutation-logger.sh for compatibility
if [[ -n "$audit_line" ]]; then
  printf '%s\n' "$audit_line" >> "$AUDIT_FILE" 2>/dev/null
fi

# Always exit 0 — PostToolUse hooks must never block operations
exit 0
