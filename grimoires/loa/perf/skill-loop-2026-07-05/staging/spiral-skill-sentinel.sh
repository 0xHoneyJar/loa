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
# Registered in settings.hooks.json as PreToolUse matcher: "Skill"
# Part of Spiral Mechanical Enforcement (cycle-072)
# =============================================================================

skill=$(jq -r '.tool_input.skill // empty' 2>/dev/null) || true

# Strip namespace prefix if present
skill="${skill##*:}"

if [[ "$skill" == "spiraling" ]]; then
    sentinel="${LOA_PROJECT_ROOT:-.}/.run/spiral-dispatch-active"
    mkdir -p "${sentinel%/*}" 2>/dev/null || true
    TZ=UTC0 printf '%(%Y-%m-%dT%H:%M:%SZ)T hook=spiral-skill-sentinel\n' -1 > "$sentinel"
fi

# Always allow — this hook only creates the sentinel, never blocks
exit 0
