#!/usr/bin/env bash
# sync-constructs.sh — Sync construct pack skills with .constructs-meta.json
# Version: 1.0.0
#
# Ensures all skills declared in installed pack manifests are registered
# in the constructs metadata file. Idempotent — running twice produces
# no output on second run.
#
# Usage:
#   sync-constructs.sh          # Sync all packs
#   sync-constructs.sh --dry-run  # Show what would be synced

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

PACKS_DIR="${PROJECT_ROOT}/.claude/constructs/packs"
META_FILE="${PROJECT_ROOT}/.claude/constructs/.constructs-meta.json"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

warn() { echo "WARNING: $*" >&2; }
info() { echo "$*"; }

sync_pack() {
    local pack_dir="$1"
    local manifest="${pack_dir}/manifest.json"

    [[ -f "$manifest" ]] || return 0

    # Validate manifest is valid JSON
    if ! jq empty "$manifest" 2>/dev/null; then
        warn "Malformed manifest.json in $(basename "$pack_dir") — skipping"
        return 0
    fi

    local pack_name
    pack_name=$(jq -r '.slug // .name // "unknown"' "$manifest")

    # Get declared skills from manifest
    local declared_skills
    declared_skills=$(jq -r '.skills[]? | .slug // .name // empty' "$manifest" 2>/dev/null)

    [[ -z "$declared_skills" ]] && return 0

    local added=0
    while IFS= read -r skill_slug; do
        [[ -z "$skill_slug" ]] && continue
        local skill_path=".claude/skills/${skill_slug}"

        # Check if skill directory exists
        if [[ ! -d "${PROJECT_ROOT}/${skill_path}" ]]; then
            warn "Skill '${skill_slug}' declared in ${pack_name} manifest but directory not found"
            continue
        fi

        # Check if already registered in meta
        local registered
        registered=$(jq -r --arg path "$skill_path" '.installed_skills[$path] // empty' "$META_FILE" 2>/dev/null)

        if [[ -z "$registered" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[dry-run] Would sync: ${skill_slug} (from ${pack_name})"
            else
                # Register the skill
                local now
                now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                local tmp="${META_FILE}.tmp.$$"
                # Version "synced" is a sentinel indicating the skill was
                # discovered via pack manifest sync rather than explicit install.
                # Actual version tracking requires the pack manifest to declare
                # per-skill versions (not yet supported in pack schema v1).
                if jq --arg path "$skill_path" \
                       --arg pack "$pack_name" \
                       --arg now "$now" \
                       '.installed_skills[$path] = {
                           "version": "synced",
                           "installed_at": $now,
                           "updated_at": $now,
                           "registry": "local",
                           "from_pack": $pack
                       }' "$META_FILE" > "$tmp" 2>/dev/null; then
                    mv "$tmp" "$META_FILE"
                    info "Synced: ${skill_slug} (from ${pack_name})"
                else
                    rm -f "$tmp"
                    warn "Failed to register ${skill_slug}"
                fi
            fi
            ((added++))
        fi
    done <<< "$declared_skills"
}

main() {
    if [[ ! -d "$PACKS_DIR" ]]; then
        # No packs directory — nothing to sync
        exit 0
    fi

    if [[ ! -f "$META_FILE" ]]; then
        warn "No constructs meta file found at $META_FILE"
        exit 0
    fi

    local synced=0
    for pack_dir in "$PACKS_DIR"/*/; do
        [[ -d "$pack_dir" ]] && sync_pack "$pack_dir"
    done
}

main "$@"
