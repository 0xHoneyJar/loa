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

set -uo pipefail

# Marker locations
GLOBAL_MARKER="${HOME}/.local/state/loa-compact/compact-pending"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PROJECT_MARKER="${PROJECT_ROOT}/.run/compact-pending"

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
run_mode_state=$(echo "$CONTEXT" | jq -r '.run_mode.state // "unknown"' 2>/dev/null) || run_mode_state="unknown"
simstim_active=$(echo "$CONTEXT" | jq -r '.simstim.active // false' 2>/dev/null) || simstim_active="false"
simstim_phase=$(echo "$CONTEXT" | jq -r '.simstim.phase // "unknown"' 2>/dev/null) || simstim_phase="unknown"

# Delete markers immediately (one-shot)
rm -f "$GLOBAL_MARKER" "$PROJECT_MARKER" 2>/dev/null || true

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

exit 0
