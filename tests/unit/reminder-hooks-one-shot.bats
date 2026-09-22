#!/usr/bin/env bats
# =============================================================================
# tests/unit/reminder-hooks-one-shot.bats — cycle-124 FR-8 / AC-8.3
#
# The two UserPromptSubmit reminder hooks are ONE-SHOT and were deliberately
# left unmodified by the prompt audit (touching their emitted text would move
# two parity goldens for no measurable gain — skill-loop-golden-scope.bats
# pins the bytes). This suite is the regression fence for the one-shot
# contract itself:
#   post-compact-reminder.sh    fires once while .run/compact-pending (or the
#                               global marker) exists, deletes BOTH markers
#                               after emitting, and is silent afterwards
#   post-session-limit-reminder.sh  fires once after reset_at_epoch passes,
#                               deletes its marker after emitting, silent after
# (tests/unit/post-session-limit-reminder.bats pins the session-limit hook in
# depth; the cases here are the cross-hook fence.)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    COMPACT_HOOK="$REPO_ROOT/.claude/hooks/post-compact-reminder.sh"
    LIMIT_HOOK="$REPO_ROOT/.claude/hooks/post-session-limit-reminder.sh"
    PR="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PR/.run" "$PR/grimoires/loa"
    export PROJECT_ROOT="$PR"
    export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.local/state/loa-compact"
    PAYLOAD='{"session_id":"t","transcript_path":"/dev/null","cwd":"'"$PR"'","hook_event_name":"UserPromptSubmit","prompt":"continue"}'
    COMPACT_MARKER="$BATS_TEST_TMPDIR/compact-pending.fixture"
    printf '{"run_mode_state":"RUNNING","simstim_phase":"false","timestamp":"2026-09-21T00:00:00Z"}\n' > "$COMPACT_MARKER"
}

_compact() { run bash -c "printf '%s' '$PAYLOAD' | '$COMPACT_HOOK'"; }
_limit()   { run bash -c "printf '' | '$LIMIT_HOOK'"; }

@test "RH-1 post-compact: fires once on the project marker, deletes it, silent on the next prompt" {
    cp "$COMPACT_MARKER" "$PR/.run/compact-pending"
    _compact
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [[ "$output" == *"COMPACTION"* || "$output" == *"compact"* ]]
    [ ! -e "$PR/.run/compact-pending" ]
    _compact
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "RH-2 post-compact: the global marker also fires once, and both markers are cleared together" {
    cp "$COMPACT_MARKER" "$HOME/.local/state/loa-compact/compact-pending"
    cp "$COMPACT_MARKER" "$PR/.run/compact-pending"
    _compact
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ ! -e "$HOME/.local/state/loa-compact/compact-pending" ]
    [ ! -e "$PR/.run/compact-pending" ]
    _compact
    [ -z "$output" ]
}

@test "RH-3 post-compact: no marker means no output (nothing is re-inserted on a cadence)" {
    _compact
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    _compact
    [ -z "$output" ]
}

@test "RH-4 session-limit: silent before the reset, fires exactly once after it, marker deleted" {
    local future past
    future=$(( $(date +%s) + 3600 )); past=$(( $(date +%s) - 60 ))
    printf '{"reset_at_epoch":%s,"reset_at":"2026-09-21T00:00:00Z","sprint_plan_state":"RUNNING","sprint_plan_current":"sprint-3"}\n' "$future" > "$PR/.run/session-limit-state.json"
    _limit
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -f "$PR/.run/session-limit-state.json" ]
    printf '{"reset_at_epoch":%s,"reset_at":"2026-09-21T00:00:00Z","sprint_plan_state":"RUNNING","sprint_plan_current":"sprint-3"}\n' "$past" > "$PR/.run/session-limit-state.json"
    _limit
    [ "$status" -eq 0 ]
    [[ "$output" == *"SESSION LIMIT RESET"* ]]
    [ ! -e "$PR/.run/session-limit-state.json" ]
    _limit
    [ -z "$output" ]
}

@test "RH-5 both hooks are byte-identical to their parity goldens' inputs (no hook text moved this cycle)" {
    # skill-loop-golden-scope.bats verifies the emitted bytes; here: the hooks
    # still delete AFTER emitting (the M7 ordering), which is what makes them one-shot
    grep -n 'rm -f "\$GLOBAL_MARKER" "\$PROJECT_MARKER"' "$COMPACT_HOOK" >/dev/null
    grep -n 'rm -f "\$MARKER"' "$LIMIT_HOOK" >/dev/null
    # the delete lines come after the reminder emission in both files
    local emit del
    emit=$(grep -n "^printf '%s' \"\$_blk\"" "$COMPACT_HOOK" | tail -1 | cut -d: -f1); del=$(grep -n 'rm -f "\$GLOBAL_MARKER"' "$COMPACT_HOOK" | cut -d: -f1)
    [ "$emit" -lt "$del" ]
    emit=$(grep -n "^printf '%s' \"\$_blk\"" "$LIMIT_HOOK" | tail -1 | cut -d: -f1); del=$(grep -n 'rm -f "\$MARKER"' "$LIMIT_HOOK" | cut -d: -f1)
    [ "$emit" -lt "$del" ]
}
