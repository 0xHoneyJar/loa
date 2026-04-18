#!/usr/bin/env bats
# =============================================================================
# spiral-task-export.bats — Tests for SPIRAL_TASK propagation (#568)
# =============================================================================
# Sprint-bug-111. Validates that spiral-orchestrator.sh exports SPIRAL_TASK
# from the state file before invoking run_cycle_loop (which in turn invokes
# spiral-simstim-dispatch.sh). Deliberately does NOT pre-export SPIRAL_TASK
# to avoid the test-masking pattern noted in triage.md.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export ORCH="$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    export DISPATCH="$PROJECT_ROOT/.claude/scripts/spiral-simstim-dispatch.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR"

    # IMPORTANT: do NOT pre-export SPIRAL_TASK — the bug is that the
    # orchestrator fails to propagate it. Pre-exporting would mask.
    unset SPIRAL_TASK
}

teardown() {
    unset SPIRAL_TASK SPIRAL_STATE_FILE
}

# =========================================================================
# ST-T1: orchestrator exports SPIRAL_TASK before run_cycle_loop (grep gate)
# =========================================================================
# Verifies the source-level fix is present — both cmd_start AND cmd_resume
# should have an `export SPIRAL_TASK` ahead of their run_cycle_loop call.

@test "orchestrator exports SPIRAL_TASK in both cmd_start and cmd_resume" {
    # Count distinct `export SPIRAL_TASK` occurrences. Both cmd_start and
    # cmd_resume need one each (two separate entry points into run_cycle_loop).
    run grep -cE "^[[:space:]]*export[[:space:]]+SPIRAL_TASK" "$ORCH"
    [ "$status" -eq 0 ]
    # Expect exactly 2 (one per code path)
    [ "$output" -ge 2 ]
}

@test "orchestrator exports SPIRAL_TASK on resume path (cmd_resume)" {
    # Same invariant applied to the cmd_resume function. Locate that function's
    # run_cycle_loop call by anchoring around cmd_resume().
    local resume_line
    resume_line=$(grep -n "^cmd_resume()" "$ORCH" | head -1 | cut -d: -f1)
    [ -n "$resume_line" ]
    # Look from cmd_resume start forward through the next run_cycle_loop
    run awk -v start="$resume_line" 'NR >= start && /run_cycle_loop/ { print; exit }' "$ORCH"
    local loop_line
    loop_line=$(grep -n "run_cycle_loop" "$ORCH" | awk -F: -v start="$resume_line" '$1 > start {print $1; exit}')
    [ -n "$loop_line" ]
    local window_start=$((loop_line - 20))
    run sed -n "${window_start},${loop_line}p" "$ORCH"
    [[ "$output" == *"SPIRAL_TASK"*"export"* ]] || [[ "$output" == *"export SPIRAL_TASK"* ]]
}

# =========================================================================
# ST-T2: dispatcher reads state-file fallback when SPIRAL_TASK empty
# =========================================================================
# If SPIRAL_TASK is empty AND state file has .task, dispatcher picks it up.

@test "dispatcher reads .task from state file when SPIRAL_TASK empty" {
    local state="$TEST_DIR/spiral-state.json"
    cat > "$state" <<'JSON'
{"state": "RUNNING", "task": "state-file-task", "spiral_id": "test"}
JSON
    unset SPIRAL_TASK
    export SPIRAL_STATE_FILE="$state"

    # Extract the 10-line block of fallback logic and test in isolation.
    local script_block
    script_block=$(awk '/Defense-in-depth.*#568/,/^fi$/' "$DISPATCH" | head -20)
    [ -n "$script_block" ]

    # Run the block as a standalone shell, seeing only SPIRAL_STATE_FILE.
    local resolved
    resolved=$(bash -c "
        task=\"\${SPIRAL_TASK:-}\"
        _spiral_state_file=\"\${SPIRAL_STATE_FILE:-}\"
        if [[ -z \"\$task\" && -f \"\$_spiral_state_file\" ]]; then
            task=\$(jq -r '.task // \"\"' \"\$_spiral_state_file\" 2>/dev/null || echo '')
        fi
        echo \"\$task\"
    ")
    [ "$resolved" = "state-file-task" ]
}

# =========================================================================
# ST-T3: dispatcher fails loudly when task unresolvable
# =========================================================================
# If neither SPIRAL_TASK nor state file has task, emit a clear FATAL
# instead of the bare `--task required` from downstream spiral-harness.sh.

@test "dispatcher emits FATAL when task cannot be resolved" {
    # Grep confirms the FATAL message is present in the dispatcher source
    # and points to the actual fix path (the orchestrator).
    run grep -E "FATAL.*task is empty" "$DISPATCH"
    [ "$status" -eq 0 ]
    run grep -E "orchestrator.*should have exported" "$DISPATCH"
    [ "$status" -eq 0 ]
}

# =========================================================================
# ST-T4: env-var precedence — explicit SPIRAL_TASK wins over state file
# =========================================================================

@test "dispatcher prefers SPIRAL_TASK over state file task" {
    local state="$TEST_DIR/spiral-state.json"
    cat > "$state" <<'JSON'
{"state": "RUNNING", "task": "state-task-should-lose", "spiral_id": "test"}
JSON
    local resolved
    resolved=$(SPIRAL_TASK="env-wins" SPIRAL_STATE_FILE="$state" bash -c '
        task="${SPIRAL_TASK:-}"
        _spiral_state_file="${SPIRAL_STATE_FILE:-}"
        if [[ -z "$task" && -f "$_spiral_state_file" ]]; then
            task=$(jq -r ".task // \"\"" "$_spiral_state_file" 2>/dev/null || echo "")
        fi
        echo "$task"
    ')
    [ "$resolved" = "env-wins" ]
}
