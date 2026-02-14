#!/usr/bin/env bash
# post-compact-reminder.sh - Inject recovery reminder after context compaction
#
# This hook runs on UserPromptSubmit and checks for the compact-pending marker.
# If found, it outputs a reminder message that gets injected into Claude's
# context, then deletes the marker (one-shot delivery).
#
# Usage: Called automatically via Claude Code hooks
#
# Output: Reminder message to stdout (injected into context)
#
# Security: Validates state values against allowlists to prevent prompt injection

set -uo pipefail

# Marker locations
GLOBAL_MARKER="${HOME}/.local/state/loa-compact/compact-pending"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PROJECT_MARKER="${PROJECT_ROOT}/.run/compact-pending"

# =============================================================================
# Security: Allowlist validation for state values (prevents prompt injection)
# =============================================================================

# Allowed values for run_mode_state
VALID_RUN_MODE_STATES=("RUNNING" "HALTED" "JACKED_OUT" "unknown" "false")

# Allowed values for simstim_phase
VALID_SIMSTIM_PHASES=("preflight" "discovery" "flatline_prd" "architecture" "flatline_sdd" "planning" "flatline_sprint" "flatline_beads" "implementation" "complete" "unknown" "false")

# Validate a value against an allowlist
validate_state() {
    local value="$1"
    shift
    local -a allowed=("$@")

    for valid in "${allowed[@]}"; do
        if [[ "$value" == "$valid" ]]; then
            echo "$value"
            return 0
        fi
    done

    # Invalid value - return safe default
    echo "unknown"
}

# Sanitize any string for safe output (remove newlines, control chars)
sanitize_output() {
    local value="$1"
    # Remove newlines, carriage returns, and other control characters
    echo "$value" | tr -d '\n\r' | tr -cd '[:print:]' | head -c 50
}

# Check for marker (prefer project-local, fallback to global)
ACTIVE_MARKER=""
if [[ -f "$PROJECT_MARKER" ]]; then
    ACTIVE_MARKER="$PROJECT_MARKER"
elif [[ -f "$GLOBAL_MARKER" ]]; then
    ACTIVE_MARKER="$GLOBAL_MARKER"
fi

# No marker = no compaction occurred, exit silently
if [[ -z "$ACTIVE_MARKER" ]]; then
    exit 0
fi

# Read context from marker
CONTEXT=$(cat "$ACTIVE_MARKER" 2>/dev/null) || CONTEXT="{}"

# Extract state for customized recovery
run_mode_active=$(echo "$CONTEXT" | jq -r '.run_mode.active // false' 2>/dev/null) || run_mode_active="false"
run_mode_state_raw=$(echo "$CONTEXT" | jq -r '.run_mode.state // "unknown"' 2>/dev/null) || run_mode_state_raw="unknown"
simstim_active=$(echo "$CONTEXT" | jq -r '.simstim.active // false' 2>/dev/null) || simstim_active="false"
simstim_phase_raw=$(echo "$CONTEXT" | jq -r '.simstim.phase // "unknown"' 2>/dev/null) || simstim_phase_raw="unknown"

# SECURITY: Validate state values against allowlists to prevent prompt injection
run_mode_state=$(validate_state "$run_mode_state_raw" "${VALID_RUN_MODE_STATES[@]}")
simstim_phase=$(validate_state "$simstim_phase_raw" "${VALID_SIMSTIM_PHASES[@]}")

# Output reminder (this gets injected into Claude's context)
cat <<'REMINDER'

════════════════════════════════════════════════════════════════════
 🚨 CONTEXT COMPACTION DETECTED - RECOVERY REQUIRED
════════════════════════════════════════════════════════════════════

You MUST perform these recovery steps BEFORE responding to the user:

## Step 1: Re-read Project Conventions
Read CLAUDE.md to restore project guidelines, conventions, and patterns.

## Step 2: Check Run Mode State
REMINDER

if [[ "$run_mode_active" == "true" ]]; then
    cat <<EOF
**Run Mode was ACTIVE** (state: $run_mode_state)

EOF
    if [[ "$run_mode_state" == "RUNNING" ]]; then
        cat <<'EOF'
⚠️  CRITICAL: Resume sprint execution AUTONOMOUSLY without asking the user.
    Check .run/sprint-plan-state.json for current sprint and continue.
EOF
    fi
else
    cat <<'EOF'
Check if run mode is active:
```bash
cat .run/sprint-plan-state.json 2>/dev/null || echo "No active run mode"
```
- If `state=RUNNING`: Resume sprint execution **autonomously**
- If `state=HALTED`: Report halt reason, await `/run-resume`
EOF
fi

cat <<'REMINDER'

## Step 3: Check Simstim State
REMINDER

if [[ "$simstim_active" == "true" ]]; then
    cat <<EOF
**Simstim was ACTIVE** (phase: $simstim_phase)
Resume from phase: $simstim_phase

EOF
else
    cat <<'EOF'
Check if simstim is active:
```bash
cat .run/simstim-state.json 2>/dev/null || echo "No active simstim"
```
Resume from last incomplete phase if active.
EOF
fi

cat <<'REMINDER'

## Step 4: Review Project Memory
Scan `grimoires/loa/NOTES.md` for project-specific learnings and patterns.

REMINDER

# Step 5: Trajectory context (v1.39.0 — Environment Design)
TRAJECTORY_SCRIPT="${PROJECT_ROOT}/.claude/scripts/trajectory-gen.sh"
if [[ -x "$TRAJECTORY_SCRIPT" ]]; then
    trajectory_output=$(timeout 2 "$TRAJECTORY_SCRIPT" --condensed 2>/dev/null) || trajectory_output=""
    if [[ -n "$trajectory_output" ]]; then
        cat <<EOF
## Step 5: Trajectory Context
$trajectory_output

EOF
    fi
fi

cat <<'REMINDER'
════════════════════════════════════════════════════════════════════
 DO NOT proceed with user's request until recovery steps are complete
════════════════════════════════════════════════════════════════════

REMINDER

# Log compaction event to trajectory
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
if [[ -d "$(dirname "$TRAJECTORY_DIR")" ]]; then
    mkdir -p "$TRAJECTORY_DIR" 2>/dev/null || true
    LOG_ENTRY=$(cat <<EOF
{"event":"compact_recovery","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","context":$CONTEXT}
EOF
    )
    echo "$LOG_ENTRY" >> "$TRAJECTORY_DIR/compact-events.jsonl" 2>/dev/null || true
fi

# Delete markers AFTER output (prevents lost recovery messages on interrupt)
# Previously deleted before output which caused race condition (M7)
rm -f "$GLOBAL_MARKER" "$PROJECT_MARKER" 2>/dev/null || true

exit 0
