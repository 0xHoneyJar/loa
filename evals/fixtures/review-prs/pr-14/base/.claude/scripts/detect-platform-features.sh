#!/usr/bin/env bash
# =============================================================================
# detect-platform-features.sh — Detect Claude Code platform capabilities
# =============================================================================
# Checks whether the Claude Code hook infrastructure exposes
# `tool_input.active_skill` in PreToolUse hook stdin.
#
# Outputs: .run/platform-features.json
#   { "active_skill_available": bool, "detected_at": "ISO8601", "schema_version": 1 }
#
# Caching: reuses existing file if less than 1 hour old.
# No assumptions from partial signals — only writes true when confirmed.
#
# IMPORTANT: No set -euo pipefail — must never crash-block.
# Part of cycle-050: Upstream Platform Alignment (sprint-108, T4.3)
# =============================================================================

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
RUN_DIR="${RUN_DIR:-$PROJECT_ROOT/.run}"

# Ensure .run directory exists
mkdir -p "$RUN_DIR" 2>/dev/null || true

FEATURES_FILE="$RUN_DIR/platform-features.json"

# ---------------------------------------------------------------------------
# Cache check: reuse existing file if less than 1 hour old (3600 seconds)
# ---------------------------------------------------------------------------
if [[ -f "$FEATURES_FILE" ]]; then
    # Portable mtime check
    local_mtime=""
    if stat -c %Y "$FEATURES_FILE" &>/dev/null 2>&1; then
        local_mtime=$(stat -c %Y "$FEATURES_FILE" 2>/dev/null) || local_mtime=""
    elif stat -f %m "$FEATURES_FILE" &>/dev/null 2>&1; then
        local_mtime=$(stat -f %m "$FEATURES_FILE" 2>/dev/null) || local_mtime=""
    fi

    if [[ -n "$local_mtime" ]]; then
        now=$(date +%s 2>/dev/null) || now=0
        if [[ $now -gt 0 && $local_mtime -gt 0 ]]; then
            age=$((now - local_mtime))
            if [[ $age -lt 3600 ]]; then
                # Cache is fresh — reuse
                exit 0
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Detection: Check if active_skill field is available in hook input
# ---------------------------------------------------------------------------
# We cannot probe the hook infrastructure directly from a standalone script.
# Detection strategy:
#   1. Check if the Claude Code version supports active_skill (env var probe)
#   2. Check if a test hook invocation received active_skill
#
# Since we can't run a hook from here, we check for the presence of the
# CLAUDE_CODE_VERSION env var and known feature flags.
# Conservative: default to false unless we have positive confirmation.

active_skill_available=false

# Method 1: Check if CLAUDE_ACTIVE_SKILL_AVAILABLE is set (future flag)
if [[ "${CLAUDE_ACTIVE_SKILL_AVAILABLE:-}" == "1" || "${CLAUDE_ACTIVE_SKILL_AVAILABLE:-}" == "true" ]]; then
    active_skill_available=true
fi

# Method 2: Check for a probe result file left by a hook that received active_skill
if [[ -f "$RUN_DIR/.active-skill-probe" ]]; then
    probe_content=$(cat "$RUN_DIR/.active-skill-probe" 2>/dev/null) || probe_content=""
    if [[ "$probe_content" == "confirmed" ]]; then
        active_skill_available=true
    fi
fi

# ---------------------------------------------------------------------------
# Write result
# ---------------------------------------------------------------------------
detected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || detected_at="unknown"

# Use jq if available for safe JSON construction, else manual
if command -v jq &>/dev/null; then
    jq -n \
        --argjson available "$active_skill_available" \
        --arg detected "$detected_at" \
        '{active_skill_available: $available, detected_at: $detected, schema_version: 1}' \
        > "$FEATURES_FILE" 2>/dev/null
else
    cat > "$FEATURES_FILE" << EJSON
{"active_skill_available":${active_skill_available},"detected_at":"${detected_at}","schema_version":1}
EJSON
fi

exit 0
