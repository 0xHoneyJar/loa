#!/usr/bin/env bash
# =============================================================================
# update-loa-bump-version.sh — Refresh framework version markers post-merge
# =============================================================================
# Part of Phase 5.6 of /update-loa (Issue #554).
#
# When /update-loa merges upstream, the merge resolver keeps the LOCAL
# `.loa-version.json` and `CLAUDE.loa.md` header (classified as
# project-owned). But these are framework-managed markers that MUST move
# with the framework. Result: downstream reports stale version, update_available
# nag fires every session, issue triage quotes wrong version.
#
# This script idempotently writes the target release tag into:
#   - `.loa-version.json.framework_version` + `.last_sync`
#   - `.claude/loa/CLAUDE.loa.md:1` header `version:` field (hash preserved)
#
# Invoked BY update-loa.md Phase 5.6 between Phase 5.5 (revert protected)
# and Phase 5.7 (commit). Also callable standalone for one-shot bumps.
#
# Usage:
#   update-loa-bump-version.sh [--target <version>] [--dry-run]
#
# With no --target, extracts target from FETCH_HEAD (tag → upstream
# .loa-version.json → short SHA fallback).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
VERSION_FILE="${VERSION_FILE:-$PROJECT_ROOT/.loa-version.json}"
CLAUDE_LOA_FILE="${CLAUDE_LOA_FILE:-$PROJECT_ROOT/.claude/loa/CLAUDE.loa.md}"

TARGET_VERSION=""
DRY_RUN=false
VERBOSE="${LOA_BUMP_VERBOSE:-false}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET_VERSION="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --verbose) VERBOSE=true; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

_log() {
    [[ "$VERBOSE" == "true" ]] && echo "[update-loa-bump] $*" >&2 || true
}

# -----------------------------------------------------------------------------
# resolve_target_version — extract target version from FETCH_HEAD fallback chain
# -----------------------------------------------------------------------------
# Fallback order:
#   1. Annotated tag containing FETCH_HEAD (prefer v-prefixed: strip leading 'v')
#   2. `.loa-version.json.framework_version` from the FETCH_HEAD tree
#   3. `git rev-parse --short FETCH_HEAD` (short SHA as last resort)
#
# Returns the resolved version on stdout, or exits 1 if no FETCH_HEAD exists.
# -----------------------------------------------------------------------------
resolve_target_version() {
    local target=""

    if ! git rev-parse --verify FETCH_HEAD >/dev/null 2>&1; then
        _log "FETCH_HEAD not set — caller must supply --target"
        return 1
    fi

    target=$(git tag --points-at FETCH_HEAD 2>/dev/null | grep -E '^v[0-9]+\.' | head -1 | sed 's/^v//' || true)
    if [[ -n "$target" ]]; then
        _log "Target resolved from tag: $target"
        echo "$target"
        return 0
    fi

    if git show "FETCH_HEAD:.loa-version.json" >/dev/null 2>&1; then
        target=$(git show "FETCH_HEAD:.loa-version.json" 2>/dev/null | jq -r '.framework_version // ""' 2>/dev/null || true)
        if [[ -n "$target" && "$target" != "null" ]]; then
            _log "Target resolved from upstream .loa-version.json: $target"
            echo "$target"
            return 0
        fi
    fi

    target=$(git rev-parse --short FETCH_HEAD 2>/dev/null)
    if [[ -n "$target" ]]; then
        _log "Target resolved from short SHA fallback: $target"
        echo "$target"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# bump_version_json — update .loa-version.json.framework_version + last_sync
# -----------------------------------------------------------------------------
# Idempotent: no-op if framework_version already matches target.
# Preserves all other fields (migrations_applied, integrity, dependencies, zones).
# Atomic write via tmp + mv.
# -----------------------------------------------------------------------------
bump_version_json() {
    local target="$1"
    local file="${2:-$VERSION_FILE}"

    [[ -f "$file" ]] || { _log "Skip: $file does not exist"; return 0; }

    local current
    current=$(jq -r '.framework_version // ""' "$file" 2>/dev/null || echo "")

    if [[ "$current" == "$target" ]]; then
        _log "No-op: $file already at $target"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        _log "DRY-RUN: would bump $file: $current → $target"
        return 0
    fi

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local tmp="${file}.tmp.$$"
    jq --arg v "$target" --arg t "$now" \
        '.framework_version = $v | .last_sync = $t' \
        "$file" > "$tmp"
    mv "$tmp" "$file"
    _log "Bumped $file: $current → $target"
}

# -----------------------------------------------------------------------------
# bump_claude_loa_header — update CLAUDE.loa.md:1 header version stamp
# -----------------------------------------------------------------------------
# Header format:
#   <!-- @loa-managed: true | version: X.Y.Z | hash: <hash>PLACEHOLDER -->
#
# Idempotent: no-op if version already matches target. Preserves the hash
# segment (and its PLACEHOLDER suffix) untouched.
# -----------------------------------------------------------------------------
bump_claude_loa_header() {
    local target="$1"
    local file="${2:-$CLAUDE_LOA_FILE}"

    [[ -f "$file" ]] || { _log "Skip: $file does not exist"; return 0; }

    local current_header
    current_header=$(head -n 1 "$file")

    if [[ "$current_header" != *"@loa-managed: true"* ]]; then
        _log "Skip: $file line 1 is not a @loa-managed header"
        return 0
    fi

    local current_version
    current_version=$(echo "$current_header" | sed -nE 's/.*version:[[:space:]]*([^[:space:]|]+).*/\1/p')

    if [[ "$current_version" == "$target" ]]; then
        _log "No-op: $file header already at $target"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        _log "DRY-RUN: would bump $file header: $current_version → $target"
        return 0
    fi

    local tmp="${file}.tmp.$$"
    awk -v target="$target" 'NR==1 {
        sub(/version:[[:space:]]*[^[:space:]|]+/, "version: " target)
    } { print }' "$file" > "$tmp"
    mv "$tmp" "$file"
    _log "Bumped $file header version: $current_version → $target"
}

# -----------------------------------------------------------------------------
# main — when run as a script (not sourced)
# -----------------------------------------------------------------------------
main() {
    if [[ -z "$TARGET_VERSION" ]]; then
        TARGET_VERSION=$(resolve_target_version) || {
            echo "ERROR: Could not resolve target version (no --target, no FETCH_HEAD)" >&2
            exit 1
        }
    fi

    bump_version_json "$TARGET_VERSION"
    bump_claude_loa_header "$TARGET_VERSION"
}

# Only run main when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
