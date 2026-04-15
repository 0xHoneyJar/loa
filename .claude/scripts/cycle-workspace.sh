#!/usr/bin/env bash
# =============================================================================
# cycle-workspace.sh - Per-cycle PRD/SDD/sprint workspace manager (cycle-064)
# =============================================================================
# Version: 1.0.0
# Part of: RFC-060 (#483) autopoietic spiral infrastructure
#
# Creates and manages grimoires/loa/cycles/{cycle-id}/{prd,sdd,sprint}.md
# workspaces. Top-level grimoires/loa/prd.md etc become symlinks to the
# "active" cycle's files, preserving backward compatibility for all existing
# consumers while unblocking parallel and historical cycle work.
#
# Usage:
#   cycle-workspace.sh init <cycle-id>
#       Create cycles/<cycle-id>/ with empty prd/sdd/sprint, set active symlink,
#       wire top-level *.md symlinks. Auto-migrates pre-existing top-level
#       regular files into the new cycle dir (no data loss). Idempotent.
#
#   cycle-workspace.sh switch <cycle-id>
#       Point active symlink at an existing cycle dir. Top-level symlinks
#       follow automatically because they target cycles/active/*.
#
#   cycle-workspace.sh list
#       Print all cycle dirs (one per line).
#
#   cycle-workspace.sh active
#       Print the active cycle id (from the cycles/active symlink).
#
#   cycle-workspace.sh status
#       Print JSON status: active cycle, list of cycles, migration state.
#
# Opt-in semantics:
#   Users who never invoke this script see no behavior change — the single-slot
#   legacy layout (grimoires/loa/prd.md as a regular file) continues to work.
#   The moment `init` runs, that top-level file becomes a symlink, and all
#   future cycles can layer on top without collision.
#
# Exit codes:
#   0 - Success
#   1 - Validation error (missing args, invalid cycle id)
#   2 - State error (operation would lose data, operation not applicable)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

_GRIMOIRE_DIR=$(get_grimoire_dir)
CYCLES_DIR="$_GRIMOIRE_DIR/cycles"
ACTIVE_LINK="$CYCLES_DIR/active"

# Per-cycle artifact files that get workspace-split
ARTIFACTS=(prd.md sdd.md sprint.md)

log() {
    echo "[cycle-workspace] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

usage() {
    sed -n '/^# Usage:/,/^# Opt-in/p' "${BASH_SOURCE[0]}" \
        | sed -e '/^# Opt-in/d' -e 's/^# \{0,1\}//'
}

# Validate cycle-id matches allowed pattern — prevents path traversal and
# symlink games. Allows cycle-NNN, cycle-YYYYMMDD-HEXHEX, cycle-bug-*, etc.
validate_cycle_id() {
    local id="$1"
    if [[ -z "$id" ]]; then
        error "cycle-id cannot be empty"
        return 1
    fi
    if [[ ! "$id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        error "cycle-id must match [A-Za-z0-9_-]+ (got: $id)"
        return 1
    fi
    # Reserved names
    case "$id" in
        active|archive|.|..)
            error "cycle-id '$id' is reserved"
            return 1
            ;;
    esac
    return 0
}

# Returns the currently active cycle id, or empty string if no active symlink.
# Uses plain `readlink` (without the fully-resolve flag) so we just read the
# link target, not the resolved path — the target is the cycle-id relative
# to CYCLES_DIR.
get_active_cycle() {
    if [[ ! -L "$ACTIVE_LINK" ]]; then
        echo ""
        return 0
    fi
    basename "$(readlink "$ACTIVE_LINK")"
}

# Create a single cycle directory with empty artifact files. Idempotent.
ensure_cycle_dir() {
    local id="$1"
    local cycle_dir="$CYCLES_DIR/$id"

    mkdir -p "$cycle_dir"

    local artifact
    for artifact in "${ARTIFACTS[@]}"; do
        local target="$cycle_dir/$artifact"
        if [[ ! -f "$target" ]]; then
            # Create an empty stub; the workflow (/simstim etc) will populate.
            : > "$target"
        fi
    done
}

# Point the active symlink at <id>. Replaces any existing symlink atomically.
#
# Note on atomicity: `ln -sfn target link` is the canonical Linux idiom. When
# `link` is already a symlink, `-f` removes it and `-n` prevents `ln` from
# dereferencing it and trying to create a link inside the pointed-to dir.
# Together they give atomic symlink replacement.
set_active_cycle() {
    local id="$1"
    local cycle_dir="$CYCLES_DIR/$id"

    if [[ ! -d "$cycle_dir" ]]; then
        error "Cycle dir does not exist: $cycle_dir"
        return 1
    fi

    ln -sfn "$id" "$ACTIVE_LINK"
}

# Replace a top-level artifact with a symlink pointing into cycles/active/.
# If the top-level file is currently a regular file with content, move that
# content into the active cycle's artifact slot first (no data loss).
wire_top_level_symlink() {
    local artifact="$1"
    local top_level="$_GRIMOIRE_DIR/$artifact"
    local active_target="$CYCLES_DIR/active/$artifact"

    if [[ -L "$top_level" ]]; then
        # Already a symlink — check whether it points at the right place.
        local current_target
        current_target=$(readlink "$top_level")
        local desired_rel="cycles/active/$artifact"
        if [[ "$current_target" != "$desired_rel" ]]; then
            # Repoint it.
            rm -f "$top_level"
            ( cd "$_GRIMOIRE_DIR" && ln -s "$desired_rel" "$artifact" )
        fi
        return 0
    fi

    if [[ -f "$top_level" ]]; then
        # Migrate: move existing content into active cycle's artifact slot,
        # but only if the active slot is empty (avoid clobbering real work).
        if [[ -s "$active_target" ]]; then
            error "Cannot migrate $artifact: active cycle's slot already has content"
            error "Resolve manually: compare $top_level vs $active_target"
            return 2
        fi
        mv "$top_level" "$active_target"
    fi

    # Create the symlink, using a relative path for git/portability.
    ( cd "$_GRIMOIRE_DIR" && ln -s "cycles/active/$artifact" "$artifact" )
}

# =============================================================================
# Commands
# =============================================================================

cmd_init() {
    local id="${1:-}"
    validate_cycle_id "$id" || return 1

    mkdir -p "$CYCLES_DIR"
    ensure_cycle_dir "$id"

    # Pre-flight validation: verify every top-level artifact migration is
    # safe before we mutate anything (review feedback — partial-failure
    # atomicity). If ANY artifact would collide with the active cycle's
    # slot, refuse the whole operation up-front.
    #
    # Temporarily point active at the target cycle so -s checks inside
    # wire_top_level_symlink's precheck resolve through the symlink chain.
    local prior_active
    prior_active=$(get_active_cycle)
    set_active_cycle "$id"

    local artifact
    for artifact in "${ARTIFACTS[@]}"; do
        if ! precheck_top_level_symlink "$artifact"; then
            # Roll back active symlink so user isn't left with a half-
            # switched workspace.
            if [[ -n "$prior_active" ]]; then
                set_active_cycle "$prior_active"
            else
                rm -f "$ACTIVE_LINK"
            fi
            return 2
        fi
    done

    # All migrations validated — apply them.
    for artifact in "${ARTIFACTS[@]}"; do
        wire_top_level_symlink "$artifact" || return $?
    done

    jq -n \
        --arg id "$id" \
        --arg cycle_dir "$CYCLES_DIR/$id" \
        '{initialized: true, cycle_id: $id, cycle_dir: $cycle_dir}'
}

# Returns 0 if wire_top_level_symlink would succeed, non-zero otherwise.
# Used by cmd_init to validate the full migration plan before mutating.
precheck_top_level_symlink() {
    local artifact="$1"
    local top_level="$_GRIMOIRE_DIR/$artifact"
    local active_target="$CYCLES_DIR/active/$artifact"

    if [[ -L "$top_level" ]]; then
        return 0 # Already a symlink, nothing to migrate
    fi

    if [[ -f "$top_level" ]] && [[ -s "$active_target" ]]; then
        # Collision: top-level is a real file AND active slot has content.
        error "Cannot migrate $artifact: active cycle's slot already has content"
        error "Resolve manually: compare $top_level vs $active_target"
        return 2
    fi

    return 0
}

cmd_switch() {
    local id="${1:-}"
    validate_cycle_id "$id" || return 1

    if [[ ! -d "$CYCLES_DIR/$id" ]]; then
        error "Cycle '$id' does not exist. Run: cycle-workspace.sh init $id"
        return 2
    fi

    local prior
    prior=$(get_active_cycle)
    set_active_cycle "$id"

    jq -n \
        --arg from "$prior" \
        --arg to "$id" \
        '{switched: true, from: (if $from == "" then null else $from end), to: $to}'
}

cmd_list() {
    if [[ ! -d "$CYCLES_DIR" ]]; then
        echo "[]"
        return 0
    fi

    # POSIX-portable: `find -printf '%f'` is GNU-only. Use `basename` via
    # -exec for BSD/macOS compatibility (review feedback).
    find "$CYCLES_DIR" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null \
        | sort \
        | jq -R . \
        | jq -s .
}

cmd_active() {
    get_active_cycle
}

cmd_status() {
    local active
    active=$(get_active_cycle)

    local cycles_json
    cycles_json=$(cmd_list)

    # Top-level artifact state: linked | regular | missing
    local artifacts_json='{}'
    local artifact
    for artifact in "${ARTIFACTS[@]}"; do
        local top="$_GRIMOIRE_DIR/$artifact"
        local state
        if [[ -L "$top" ]]; then
            state="linked"
        elif [[ -f "$top" ]]; then
            state="regular"
        else
            state="missing"
        fi
        artifacts_json=$(echo "$artifacts_json" | jq --arg a "$artifact" --arg s "$state" '. + {($a): $s}')
    done

    jq -n \
        --arg active "$active" \
        --argjson cycles "$cycles_json" \
        --argjson artifacts "$artifacts_json" \
        '{
            active: (if $active == "" then null else $active end),
            cycles: $cycles,
            top_level_artifacts: $artifacts
        }'
}

# =============================================================================
# CLI dispatch
# =============================================================================

main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        init)
            cmd_init "$@"
            ;;
        switch)
            cmd_switch "$@"
            ;;
        list)
            cmd_list
            ;;
        active)
            cmd_active
            ;;
        status)
            cmd_status
            ;;
        -h|--help|help|"")
            usage
            [[ -z "$cmd" ]] && exit 1 || exit 0
            ;;
        *)
            error "Unknown command: $cmd"
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
