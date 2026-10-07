#!/usr/bin/env bash
# =============================================================================
# detect-platform-features.sh — Report Claude Code platform capabilities
# =============================================================================
# Reports whether a harness-set skill signal exists for the implement gate.
#
# cycle-126 D-4.4: the PreToolUse payload has no harness-set skill field
# (https://code.claude.com/docs/en/hooks), and tool_input is model-authored,
# so this script never reports `active_skill_available: true` on its own. It
# carries forward the evidence implement-gate.sh records (active_skill_seen_at,
# active_skill_source) and states that it is not a harness signal.
#
# The refresh carries active_skill_seen_at forward only as an ISO-8601 UTC
# timestamp and active_skill_source only as a value the recorder writes
# ("tool_input"); anything else is dropped (sprint-250 audit n24).
#
# Outputs: .run/platform-features.json
#   { "active_skill_available": false, "harness_signal": false,
#     "active_skill_seen_at": "ISO8601"|null, "active_skill_source": str|null,
#     "detected_at": "ISO8601", "schema_version": 2 }
#
# Usage: detect-platform-features.sh          refresh the file (cached for 1 hour)
#        detect-platform-features.sh --line   print the /loa evidence line; writes nothing
#
# IMPORTANT: No set -euo pipefail — must never crash-block.
# Part of cycle-050: Upstream Platform Alignment (sprint-108, T4.3)
# =============================================================================

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
RUN_DIR="${RUN_DIR:-$PROJECT_ROOT/.run}"
FEATURES_FILE="$RUN_DIR/platform-features.json"

if [[ "${1:-}" == "--line" ]]; then
    label="heuristic ("
    if command -v yq &>/dev/null && [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
        configured=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured=""
        [[ "${configured//\"/}" == "authoritative" ]] && label="authoritative (opt-in; "
    fi
    evidence=$(jq -r 'if (.active_skill_seen_at // "") != "" then "seen \(.active_skill_seen_at) via \(.active_skill_source // "unknown")" else empty end' \
        "$FEATURES_FILE" 2>/dev/null | LC_ALL=C tr -cd '[:print:]' | cut -c1-120)   # printable ASCII only: drops U+202E/U+200B too (sprint-250 audit n24)
    echo "Implement gate: ${label}active_skill evidence: ${evidence:-none}; no harness skill signal)"
    exit 0
fi

mkdir -p "$RUN_DIR" 2>/dev/null || true

# Cache check: reuse an existing file if less than 1 hour old
if [[ -f "$FEATURES_FILE" ]]; then
    local_mtime=""
    if stat -c %Y "$FEATURES_FILE" &>/dev/null 2>&1; then
        local_mtime=$(stat -c %Y "$FEATURES_FILE" 2>/dev/null) || local_mtime=""
    elif stat -f %m "$FEATURES_FILE" &>/dev/null 2>&1; then
        local_mtime=$(stat -f %m "$FEATURES_FILE" 2>/dev/null) || local_mtime=""
    fi
    if [[ -n "$local_mtime" ]]; then
        now=$(date +%s 2>/dev/null) || now=0
        if [[ $now -gt 0 && $local_mtime -gt 0 && $((now - local_mtime)) -lt 3600 ]]; then
            exit 0
        fi
    fi
fi

command -v jq &>/dev/null || exit 0

detected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || detected_at="unknown"
base=$(jq -c 'select(type == "object") | {active_skill_seen_at, active_skill_source}' "$FEATURES_FILE" 2>/dev/null | tail -n 1)
tmp=$(mktemp "$RUN_DIR/.platform-features.XXXXXX" 2>/dev/null) || exit 0
jq -n --argjson b "${base:-{\}}" --arg detected "$detected_at" \
    '{active_skill_available: false, harness_signal: false,
      active_skill_seen_at: ($b.active_skill_seen_at | if type == "string" and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z") then . else null end),
      active_skill_source: ($b.active_skill_source | if . == "tool_input" then . else null end),
      detected_at: $detected, schema_version: 2}' > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$FEATURES_FILE" 2>/dev/null
rm -f "$tmp" 2>/dev/null

exit 0
