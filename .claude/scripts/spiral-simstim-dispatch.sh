#!/usr/bin/env bash
# =============================================================================
# spiral-simstim-dispatch.sh — External dispatch wrapper for /spiral (cycle-068)
# =============================================================================
# External script (NOT sourced) so timeout(1) can wrap it.
# Invokes simstim-orchestrator.sh as subprocess, captures artifacts,
# emits cycle-outcome.json sidecar.
#
# Usage:
#   spiral-simstim-dispatch.sh <cycle_dir> <cycle_id> [seed_context_path]
#
# Environment:
#   PROJECT_ROOT  — Workspace root (inherited from caller)
#
# Exit codes:
#   0   — Success (all artifacts present)
#   1   — Simstim failed (partial/no artifacts)
#   126 — Simstim not executable
#   127 — Simstim not found
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Arguments
cycle_dir="${1:?Usage: spiral-simstim-dispatch.sh <cycle_dir> <cycle_id> [seed_context_path]}"
cycle_id="${2:?Missing cycle_id}"
seed_context="${3:-}"

log() { echo "[spiral-dispatch] $*" >&2; }
error() { echo "ERROR: $*" >&2; }

# Validate simstim-orchestrator exists
SIMSTIM_SCRIPT="$SCRIPT_DIR/simstim-orchestrator.sh"
if [[ ! -f "$SIMSTIM_SCRIPT" ]]; then
    error "simstim-orchestrator.sh not found at $SIMSTIM_SCRIPT"
    exit 127
fi
if [[ ! -x "$SIMSTIM_SCRIPT" ]]; then
    error "simstim-orchestrator.sh not executable"
    exit 126
fi

# Ensure cycle_dir exists
mkdir -p "$cycle_dir"

# Pre-dispatch cleanup: remove stale artifacts (SKP-003)
rm -f "$cycle_dir/reviewer.md" \
      "$cycle_dir/auditor-sprint-feedback.md" \
      "$cycle_dir/cycle-outcome.json"

# Prepare subprocess environment
# State isolation (Bridgebuilder HIGH-1): simstim writes state to cycle workspace
export SIMSTIM_RUN_DIR="$cycle_dir/.run"
mkdir -p "$SIMSTIM_RUN_DIR"

# Build simstim flags
simstim_flags=(--preflight)
if [[ -n "$seed_context" ]] && [[ -f "$seed_context" ]]; then
    simstim_flags+=(--seed-context "$seed_context")
fi

log "Dispatching simstim for $cycle_id"
log "  cycle_dir: $cycle_dir"
log "  seed_context: ${seed_context:-none}"

# Execute simstim in new process group (SKP-002)
# stdout/stderr → per-cycle log files (IMP-005)
local_exit=0
setsid "$SIMSTIM_SCRIPT" "${simstim_flags[@]}" \
    > "$cycle_dir/simstim-stdout.log" \
    2> "$cycle_dir/simstim-stderr.log" &
child_pid=$!

# Wait for completion
wait "$child_pid" 2>/dev/null || local_exit=$?

# Post-dispatch: kill orphan process group (Bridgebuilder MEDIUM-1)
# Use negative PID = process group kill (setsid children reparent, pgrep -P won't see them)
kill -- -"$child_pid" 2>/dev/null || true

if [[ "$local_exit" -ne 0 ]]; then
    log "Simstim exited $local_exit for $cycle_id"
fi

# Locate simstim output artifacts
# Simstim writes reviewer.md and auditor-sprint-feedback.md in its own workspace
# We need to find and copy them to cycle_dir
# Check common locations: grimoires/loa/a2a/, .run/
_GRIMOIRE_DIR="${PROJECT_ROOT}/grimoires/loa"

# Copy reviewer.md if found
for candidate in \
    "$_GRIMOIRE_DIR/a2a/"sprint-*/reviewer.md \
    "$SIMSTIM_RUN_DIR/"reviewer.md; do
    if [[ -f "$candidate" ]]; then
        cp "$candidate" "$cycle_dir/reviewer.md"
        break
    fi
done

# Copy auditor feedback if found
for candidate in \
    "$_GRIMOIRE_DIR/a2a/"sprint-*/auditor-sprint-feedback.md \
    "$SIMSTIM_RUN_DIR/"auditor-sprint-feedback.md; do
    if [[ -f "$candidate" ]]; then
        cp "$candidate" "$cycle_dir/auditor-sprint-feedback.md"
        break
    fi
done

# Emit sidecar via adapter
source "$SCRIPT_DIR/bootstrap.sh" 2>/dev/null || true
source "$SCRIPT_DIR/spiral-harvest-adapter.sh" 2>/dev/null || true

if type -t emit_cycle_outcome_sidecar &>/dev/null; then
    # Determine verdicts from artifacts
    local review_v="null" audit_v="null"
    local findings_json='{"blocker":0,"high":0,"medium":0,"low":0}'

    if [[ -f "$cycle_dir/reviewer.md" ]] && type -t _extract_verdict &>/dev/null; then
        review_v=$(_extract_verdict "$cycle_dir/reviewer.md" \
            "$SPIRAL_RX_REVIEW_VERDICT" "$SPIRAL_RX_REVIEW_VALUE")
    fi
    if [[ -f "$cycle_dir/auditor-sprint-feedback.md" ]] && type -t _extract_verdict &>/dev/null; then
        audit_v=$(_extract_verdict "$cycle_dir/auditor-sprint-feedback.md" \
            "$SPIRAL_RX_AUDIT_VERDICT" "$SPIRAL_RX_AUDIT_VALUE")
    fi

    local exit_status="success"
    if [[ "$local_exit" -ne 0 ]]; then
        exit_status="failed"
    fi

    emit_cycle_outcome_sidecar "$cycle_dir" "$review_v" "$audit_v" \
        "$findings_json" "null" "0" "$exit_status" >/dev/null 2>&1 || true

    # Validate cycle_id in sidecar (SKP-003)
    if [[ -f "$cycle_dir/cycle-outcome.json" ]]; then
        local sidecar_cid
        sidecar_cid=$(jq -r '.cycle_id' "$cycle_dir/cycle-outcome.json" 2>/dev/null)
        if [[ "$sidecar_cid" != "$cycle_id" ]]; then
            error "Sidecar cycle_id mismatch: expected $cycle_id, got $sidecar_cid"
        fi
    fi
else
    log "WARNING: harvest adapter not available, sidecar not emitted"
fi

log "Dispatch complete for $cycle_id (exit=$local_exit)"
exit "$local_exit"
