#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Skill — Spiral Sentinel Activation
# =============================================================================
# When /spiraling is invoked, automatically creates the dispatch sentinel
# that activates the Write/Edit guard (spiral-dispatch-guard.sh).
#
# This closes the last mechanical enforcement gap: the agent doesn't need
# to remember to create the sentinel. The hook does it automatically at
# the platform level before the skill even loads.
#
# Exit 0 = allow (always — this hook never blocks, only creates sentinel).
#
# perf pass-2 (2026-07-05, skill-loop): jq reads stdin directly (no cat
# spawn / echo-pipe); the sentinel's dirname is a parameter expansion (the
# sentinel path always contains "/.run/", so ${p%/*} ≡ dirname); the
# timestamp is bash strftime (printf %(…)T, TZ-scoped UTC) — the written
# sentinel line is byte-identical to the old `echo "$(date -u …) hook=…"`.
#
# perf pass-9 (2026-07-05, skill-loop): raw-payload literal fast gate — the
# jq spawn is skipped on every Skill invocation except /spiraling itself.
# Soundness argument (all-inputs isomorphism):
#   The hook's ONLY effect is creating the sentinel when the decoded
#   .tool_input.skill (after the ##*: namespace strip) equals "spiraling";
#   every other input — unparseable payloads included — exits 0 silently
#   with no side effects. A decoded JSON string can contain the letters
#   s,p,i,r,a,l,i,n,g only as literal payload bytes or via \uXXXX escapes
#   (every other JSON escape decodes to a non-letter, and adjacent decoded
#   characters come from adjacent raw representations, so a fully-literal
#   "spiraling" is contiguous in the raw bytes). Therefore when the raw
#   payload contains neither the substring "spiraling" nor the two bytes
#   "\u" (JSON's \u is lowercase-only), skill can never equal "spiraling"
#   and the old code exited 0 with nothing to observe — exactly what the
#   fast gate does. Any payload containing either token falls through to
#   the SAME jq program fed the SAME bytes via printf '%s' (adv-gate
#   precedent). Raw-NUL caveat: the read builtin truncates at a NUL where
#   jq previously saw the full stream — outcome-identical, because jq can
#   only have extracted skill=="spiraling" from a document that parses
#   BEFORE the NUL (raw NUL is invalid inside JSON), and that document
#   survives the truncation intact; documents after the NUL were never
#   reached by the old capture either (jq stops at the parse error).
#   Pinned by the pass-9 differential corpus.
#
# Registered in settings.hooks.json as PreToolUse matcher: "Skill"
# Part of Spiral Mechanical Enforcement (cycle-072)
# =============================================================================

input=""
IFS= read -rd '' input || true

# perf pass-9 fast gate (see header note): no "spiraling" and no "\u" in the
# raw payload ⇒ the decoded skill cannot be "spiraling" ⇒ silent exit 0.
if [[ "$input" != *spiraling* && "$input" != *'\u'* ]]; then
  exit 0
fi

skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null) || true

# Strip namespace prefix if present
skill="${skill##*:}"

if [[ "$skill" == "spiraling" ]]; then
    sentinel="${LOA_PROJECT_ROOT:-.}/.run/spiral-dispatch-active"
    mkdir -p "${sentinel%/*}" 2>/dev/null || true
    TZ=UTC0 printf '%(%Y-%m-%dT%H:%M:%SZ)T hook=spiral-skill-sentinel\n' -1 > "$sentinel"
fi

# Always allow — this hook only creates the sentinel, never blocks
exit 0
