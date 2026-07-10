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
#
# perf pass-4 (2026-07-05, skill-loop): redundant-I/O elimination on the
# marker path. Was: cat x9 (1 marker read + 8 heredoc feeders) + jq x4 +
# date + dirname + mkdir + rm ≈ 17 spawns / ~46ms. Now: jq x1 + rm x1
# (+ mkdir only when the trajectory dir is missing) ≈ 2 spawns:
#   - marker read: builtin $(<file) replaces the cat spawn. The group
#     2>/dev/null redirect matches cat's stderr silencing; a failed read
#     (marker deleted in a race) falls back to "{}" exactly like the old
#     `|| CONTEXT="{}"`. (A directory marker is unreachable — the [[ -f ]]
#     checks above gate it. Accepted cosmetic divergence, pass-3 precedent:
#     bash's "ignored null byte" warning for NUL-bearing markers is now
#     silenced too.)
#   - ONE jq -s replaces the four per-field spawns, NUL-delimited fields.
#     Per-field failure granularity is preserved via per-field try/catch
#     defaults (a scalar .run_mode still yields "false"/"unknown" for its
#     two fields while .simstim fields compute — host-verified against the
#     old four-call behavior). Strings render raw; non-string values render
#     via tojson (pass-3 rule — compact where the old jq -r pretty-printed
#     containers; every non-string rendering fails the =="true" test and
#     the allowlist validation identically in both versions). Trailing
#     newlines are stripped and NUL bytes dropped exactly like the old
#     $(...) captures (denul + scap). Whole-parse failure → 0 fields → the
#     old per-call `|| default` values.
#   - heredoc bodies are UNCHANGED but consumed by builtin `read -rd ''`
#     and emitted with printf '%s' instead of spawning cat per block
#     (pass-2 precedent) — byte-identical output.
#   - trajectory event: bash strftime replaces the date spawn (byte-
#     identical format, pass-2 precedent); printf -v replaces the $(cat
#     <<EOF) builder; ${VAR%/*} replaces the dirname spawn (the path is a
#     constant suffix, always slash-containing, never slash-terminated);
#     [[ -d ]] guard skips mkdir when the trajectory dir exists.
#   - $(pwd) → $PWD (pass-2 precedent) — also removes a fork from the
#     every-prompt no-marker path; everything else on that path is
#     untouched.

set -uo pipefail

# Marker locations
GLOBAL_MARKER="${HOME}/.local/state/loa-compact/compact-pending"
PROJECT_ROOT="${PROJECT_ROOT:-$PWD}"
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

# Read context from marker (builtin read — see pass-4 header note)
{ CONTEXT=$(<"$ACTIVE_MARKER"); } 2>/dev/null || CONTEXT="{}"

# Extract state for customized recovery — ONE jq, NUL-delimited fields
# (see pass-4 header note for the per-field failure/rendering contract).
mapfile -d '' -t _pc_fields < <(
    printf '%s' "$CONTEXT" | jq -sj '
        def r: if type == "string" then . else tojson end;
        ([0] | implode) as $z |
        def scap: . / ([0] | implode) | join("") | sub("\n+$"; "");
        def fld(g; $d): (try (map(g | r) | join("\n") | scap) catch $d);
        fld(.run_mode.active // false; "false") + $z +
        fld(.run_mode.state // "unknown"; "unknown") + $z +
        fld(.simstim.active // false; "false") + $z +
        fld(.simstim.phase // "unknown"; "unknown") + $z
    ' 2>/dev/null
)
if [[ "${#_pc_fields[@]}" -eq 4 ]]; then
    run_mode_active="${_pc_fields[0]}"
    run_mode_state_raw="${_pc_fields[1]}"
    simstim_active="${_pc_fields[2]}"
    simstim_phase_raw="${_pc_fields[3]}"
else
    # Whole-parse failure — the old per-call `|| default` values.
    run_mode_active="false"
    run_mode_state_raw="unknown"
    simstim_active="false"
    simstim_phase_raw="unknown"
fi

# SECURITY: Validate state values against allowlists to prevent prompt injection
run_mode_state=$(validate_state "$run_mode_state_raw" "${VALID_RUN_MODE_STATES[@]}")
simstim_phase=$(validate_state "$simstim_phase_raw" "${VALID_SIMSTIM_PHASES[@]}")

# Output reminder (this gets injected into Claude's context)
# (heredoc bodies unchanged; builtin read+printf replaces the cat spawns)
IFS= read -rd '' _blk <<'REMINDER' || true

════════════════════════════════════════════════════════════════════
 🚨 CONTEXT COMPACTION DETECTED - RECOVERY REQUIRED
════════════════════════════════════════════════════════════════════

You MUST perform these recovery steps BEFORE responding to the user:

## Step 1: Re-read Project Conventions
Read CLAUDE.md to restore project guidelines, conventions, and patterns.

## Step 2: Check Run Mode State
REMINDER
printf '%s' "$_blk"

if [[ "$run_mode_active" == "true" ]]; then
    IFS= read -rd '' _blk <<EOF || true
**Run Mode was ACTIVE** (state: $run_mode_state)

EOF
    printf '%s' "$_blk"
    if [[ "$run_mode_state" == "RUNNING" ]]; then
        IFS= read -rd '' _blk <<'EOF' || true
⚠️  CRITICAL: Resume sprint execution AUTONOMOUSLY without asking the user.
    Check .run/sprint-plan-state.json for current sprint and continue.
EOF
        printf '%s' "$_blk"
    fi
else
    IFS= read -rd '' _blk <<'EOF' || true
Check if run mode is active:
```bash
cat .run/sprint-plan-state.json 2>/dev/null || echo "No active run mode"
```
- If `state=RUNNING`: Resume sprint execution **autonomously**
- If `state=HALTED`: Report halt reason, await `/run-resume`
EOF
    printf '%s' "$_blk"
fi

IFS= read -rd '' _blk <<'REMINDER' || true

## Step 3: Check Simstim State
REMINDER
printf '%s' "$_blk"

if [[ "$simstim_active" == "true" ]]; then
    IFS= read -rd '' _blk <<EOF || true
**Simstim was ACTIVE** (phase: $simstim_phase)
Resume from phase: $simstim_phase

EOF
    printf '%s' "$_blk"
else
    IFS= read -rd '' _blk <<'EOF' || true
Check if simstim is active:
```bash
cat .run/simstim-state.json 2>/dev/null || echo "No active simstim"
```
Resume from last incomplete phase if active.
EOF
    printf '%s' "$_blk"
fi

IFS= read -rd '' _blk <<'REMINDER' || true

## Step 4: Review Project Memory
Scan `grimoires/loa/NOTES.md` for project-specific learnings and patterns.

REMINDER
printf '%s' "$_blk"

# Step 5: Trajectory context (v1.39.0 — Environment Design)
TRAJECTORY_SCRIPT="${PROJECT_ROOT}/.claude/scripts/trajectory-gen.sh"
if [[ -x "$TRAJECTORY_SCRIPT" ]]; then
    trajectory_output=$(timeout 2 "$TRAJECTORY_SCRIPT" --condensed 2>/dev/null) || trajectory_output=""
    if [[ -n "$trajectory_output" ]]; then
        IFS= read -rd '' _blk <<EOF || true
## Step 5: Trajectory Context
$trajectory_output

EOF
        printf '%s' "$_blk"
    fi
fi

IFS= read -rd '' _blk <<'REMINDER' || true
════════════════════════════════════════════════════════════════════
 DO NOT proceed with user's request until recovery steps are complete
════════════════════════════════════════════════════════════════════

REMINDER
printf '%s' "$_blk"

# Log compaction event to trajectory
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
if [[ -d "${TRAJECTORY_DIR%/*}" ]]; then
    [[ -d "$TRAJECTORY_DIR" ]] || mkdir -p "$TRAJECTORY_DIR" 2>/dev/null || true
    TZ=UTC0 printf -v _pc_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
    printf -v LOG_ENTRY '{"event":"compact_recovery","timestamp":"%s","context":%s}' \
        "$_pc_ts" "$CONTEXT"
    echo "$LOG_ENTRY" >> "$TRAJECTORY_DIR/compact-events.jsonl" 2>/dev/null || true
fi

# Delete markers AFTER output (prevents lost recovery messages on interrupt)
# Previously deleted before output which caused race condition (M7)
rm -f "$GLOBAL_MARKER" "$PROJECT_MARKER" 2>/dev/null || true

exit 0
