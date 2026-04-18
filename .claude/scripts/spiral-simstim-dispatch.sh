#!/usr/bin/env bash
# =============================================================================
# spiral-simstim-dispatch.sh — Dispatch wrapper for /spiral (cycle-070)
# =============================================================================
# Invokes `claude -p` as a non-interactive subprocess per spiral cycle.
# Each cycle gets a fresh Claude Code session with full context window.
#
# Usage:
#   spiral-simstim-dispatch.sh <cycle_dir> <cycle_id> [seed_context_path]
#
# Environment:
#   PROJECT_ROOT          — Workspace root (inherited from caller)
#   SPIRAL_ID             — Spiral identifier
#   SPIRAL_CYCLE_NUM      — Current cycle number
#   SPIRAL_TASK           — Task description
#   SPIRAL_PARENT_PR_URL  — Previous cycle's PR URL (for chaining)
#   SPIRAL_USE_STUB       — If "1", use stub mode (no claude -p)
#
# Exit codes:
#   0   — Success (artifacts present)
#   1   — Simstim failed (partial/no artifacts)
#   124 — Timeout
#   126 — claude CLI not executable
#   127 — claude CLI not found
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Arguments
cycle_dir="${1:?Usage: spiral-simstim-dispatch.sh <cycle_dir> <cycle_id> [seed_context_path]}"
cycle_id="${2:?Missing cycle_id}"
seed_context="${3:-}"

log() { echo "[spiral-dispatch] $*" >&2; }
error() { echo "ERROR: $*" >&2; }

# =============================================================================
# Stub Mode (preserved for testing — cycle-067 compatibility)
# =============================================================================

if [[ "${SPIRAL_USE_STUB:-0}" == "1" ]]; then
    log "STUB: dispatch mode (SPIRAL_USE_STUB=1)"

    mkdir -p "$cycle_dir"

    # Write stub artifacts
    cat > "$cycle_dir/reviewer.md" << 'STUB'
## Review: STUB MODE
Verdict: APPROVED
This is a stub review for testing.
STUB

    cat > "$cycle_dir/auditor-sprint-feedback.md" << 'STUB'
## Audit: STUB MODE
Verdict: APPROVED
This is a stub audit for testing.
STUB

    # Emit stub sidecar
    source "$SCRIPT_DIR/bootstrap.sh" 2>/dev/null || true
    source "$SCRIPT_DIR/spiral-harvest-adapter.sh" 2>/dev/null || true
    if type -t emit_cycle_outcome_sidecar &>/dev/null; then
        emit_cycle_outcome_sidecar "$cycle_dir" "APPROVED" "APPROVED" \
            '{"blocker":0,"high":0,"medium":0,"low":0}' "null" "0" "success" >/dev/null 2>&1 || true
    fi

    # Write status artifact for stub mode too
    mkdir -p "$PROJECT_ROOT/.run"
    {
        echo "Spiral: ${SPIRAL_ID:-stub}"
        echo "Cycle: ${SPIRAL_CYCLE_NUM:-0}"
        echo "Status: COMPLETED (stub)"
        echo "PR: none"
        echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "${PROJECT_ROOT}/.run/spiral-status.txt"

    log "STUB: dispatch complete for $cycle_id"
    exit 0
fi

# =============================================================================
# Real Dispatch via claude -p (cycle-070 FR-1)
# =============================================================================

# Validate claude CLI
if ! command -v claude &>/dev/null; then
    error "claude CLI not found on PATH"
    error "Install: npm install -g @anthropic-ai/claude-code"
    exit 127
fi

# Ensure cycle directory exists
mkdir -p "$cycle_dir"

# Pre-dispatch cleanup (SKP-003)
rm -f "$cycle_dir/reviewer.md" \
      "$cycle_dir/auditor-sprint-feedback.md" \
      "$cycle_dir/cycle-outcome.json"

# Read configuration
source "$SCRIPT_DIR/bootstrap.sh" 2>/dev/null || true

_read_config() {
    local key="$1" default="$2"
    local config="$PROJECT_ROOT/.loa.config.yaml"
    [[ ! -f "$config" ]] && { echo "$default"; return 0; }
    local value
    value=$(yq eval ".$key // null" "$config" 2>/dev/null || echo "null")
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

local_budget=$(_read_config "spiral.max_budget_per_cycle_usd" "10")
local_timeout=$(_read_config "spiral.step_timeouts.simstim_sec" "7200")

# Build dispatch prompt (safe via jq --arg — no shell expansion).
# Defense-in-depth (#568): if SPIRAL_TASK is empty but the state file has
# `.task`, read from there. The orchestrator SHOULD have exported it, but
# fall back gracefully so intermediate dispatch invocations (tests,
# debugging, reentry) don't silently run with an empty task.
task="${SPIRAL_TASK:-}"
_spiral_state_file="${SPIRAL_STATE_FILE:-${PROJECT_ROOT}/.run/spiral-state.json}"
if [[ -z "$task" && -f "$_spiral_state_file" ]]; then
    task=$(jq -r '.task // ""' "$_spiral_state_file" 2>/dev/null || echo "")
fi

# If task is STILL empty, fail with a clear, actionable message rather than
# letting spiral-harness.sh emit a bare `ERROR: --task required`.
if [[ -z "$task" ]]; then
    echo "FATAL: spiral-simstim-dispatch.sh: task is empty. Set SPIRAL_TASK env var, pass --task to orchestrator, or populate spiral.task in .loa.config.yaml." >&2
    exit 2
fi

parent_pr="${SPIRAL_PARENT_PR_URL:-}"
spiral_id="${SPIRAL_ID:-unknown}"
cycle_num="${SPIRAL_CYCLE_NUM:-1}"
branch_name="feat/spiral-${spiral_id}-cycle-${cycle_num}"

seed_text=""
if [[ -n "$seed_context" && -f "$seed_context" ]]; then
    # Cap at 4KB (trust boundary)
    seed_text=$(head -c 4096 "$seed_context")
fi

log "Dispatching cycle $cycle_id via harness"
log "  task: ${task:0:80}..."
log "  branch: $branch_name"
log "  budget: \$$local_budget"
log "  timeout: ${local_timeout}s"
log "  parent_pr: ${parent_pr:-none}"

# ── Harness dispatch (cycle-071): evidence-gated orchestrator ──
# Each phase is a separate claude -p call. Quality gates run in bash.
# The LLM cannot skip Flatline, Review, or Audit.
local_exit=0
pr_url=""

harness_output=$("$SCRIPT_DIR/spiral-harness.sh" \
    --task "$task" \
    --cycle-dir "$cycle_dir" \
    --cycle-id "$cycle_id" \
    --branch "$branch_name" \
    --budget "$local_budget" \
    ${seed_context:+--seed-context "$seed_context"} \
    2>"$cycle_dir/harness-stderr.log") || local_exit=$?

# PR URL is the last line of harness stdout
if [[ -n "$harness_output" ]]; then
    pr_url=$(echo "$harness_output" | \
        grep -oE 'https://github.com/[^/]+/[^/]+/pull/[0-9]+' | tail -1 || true)
fi

log "Dispatch complete: exit=$local_exit, pr=${pr_url:-none}"

# Emit sidecar via harvest adapter
source "$SCRIPT_DIR/spiral-harvest-adapter.sh" 2>/dev/null || true

if type -t emit_cycle_outcome_sidecar &>/dev/null; then
    review_v="null"
    audit_v="null"
    findings_json='{"blocker":0,"high":0,"medium":0,"low":0}'

    # Try to extract verdicts from artifacts the subprocess may have created
    if [[ -f "$cycle_dir/reviewer.md" ]] && type -t _extract_verdict &>/dev/null; then
        review_v=$(_extract_verdict "$cycle_dir/reviewer.md" \
            "${SPIRAL_RX_REVIEW_VERDICT:-}" "${SPIRAL_RX_REVIEW_VALUE:-}")
    fi
    if [[ -f "$cycle_dir/auditor-sprint-feedback.md" ]] && type -t _extract_verdict &>/dev/null; then
        audit_v=$(_extract_verdict "$cycle_dir/auditor-sprint-feedback.md" \
            "${SPIRAL_RX_AUDIT_VERDICT:-}" "${SPIRAL_RX_AUDIT_VALUE:-}")
    fi

    exit_status="success"
    if [[ "$local_exit" -ne 0 ]]; then
        exit_status="failed"
    fi

    emit_cycle_outcome_sidecar "$cycle_dir" "$review_v" "$audit_v" \
        "$findings_json" "null" "0" "$exit_status" >/dev/null 2>&1 || true

    # Add pr_url to sidecar if found (cycle-070 FR-5 branch chaining)
    if [[ -n "$pr_url" && -f "$cycle_dir/cycle-outcome.json" ]]; then
        jq --arg url "$pr_url" '. + {pr_url: $url}' \
            "$cycle_dir/cycle-outcome.json" > "$cycle_dir/cycle-outcome.json.tmp" \
            && mv "$cycle_dir/cycle-outcome.json.tmp" "$cycle_dir/cycle-outcome.json"
    fi
fi

# Write status artifact (IMP-007)
status_file="${PROJECT_ROOT}/.run/spiral-status.txt"
{
    echo "Spiral: ${spiral_id}"
    echo "Cycle: ${cycle_num}"
    echo "Status: $([ "$local_exit" -eq 0 ] && echo "COMPLETED" || echo "FAILED (exit $local_exit)")"
    echo "PR: ${pr_url:-none}"
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$status_file"

exit "$local_exit"
