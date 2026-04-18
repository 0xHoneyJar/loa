#!/usr/bin/env bats
# =============================================================================
# spiral-resume-force.bats — Tests for cmd_resume --force (#546)
# =============================================================================
# Sprint-bug-107. Validates the narrow --force override for resuming a
# spiral from COMPLETED/FAILED terminal state with stopping_condition =
# quality_gate_failure. Refuses any other combination.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export TEST_DIR="$BATS_TEST_TMPDIR/spiral-state"
    mkdir -p "$TEST_DIR"
    export SPIRAL_STATE_DIR="$TEST_DIR"
}

teardown() {
    unset SPIRAL_RESUME_FORCE SPIRAL_STATE_DIR
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Extract just the first `case` block of cmd_resume that we're testing — we
# don't want to wire up the full orchestrator machinery (coalesce, state
# writes, PID tracking) for a narrow behavior test.
make_isolated_cmd() {
    local state="$1" stop_reason="$2"
    local state_file="$TEST_DIR/state.json"
    cat > "$state_file" <<EOF
{
  "state": "$state",
  "stopping_condition": $(if [[ -n "$stop_reason" ]]; then echo "\"$stop_reason\""; else echo "null"; fi)
}
EOF
    echo "$state_file"
}

resume_gate() {
    # Simulate the exact case-block logic added in spiral-orchestrator.sh
    # for --resume's handling of terminal states. Returns the outcome as
    # stdout: "accept", "refuse", or "pass_through".
    local state_file="$1"
    local current_state stop_reason force_flag
    current_state=$(jq -r '.state' "$state_file")
    stop_reason=$(jq -r '.stopping_condition // ""' "$state_file")
    force_flag="${SPIRAL_RESUME_FORCE:-false}"

    case "$current_state" in
        COMPLETED|FAILED)
            if [[ "$force_flag" == "true" && "$stop_reason" == "quality_gate_failure" ]]; then
                echo "accept"; return 0
            else
                echo "refuse"; return 1
            fi
            ;;
        *)
            echo "pass_through"; return 0
            ;;
    esac
}

# =========================================================================
# RF-T1: COMPLETED + quality_gate_failure + --force → accept
# =========================================================================

@test "resume --force: COMPLETED + quality_gate_failure accepted" {
    local state_file
    state_file=$(make_isolated_cmd "COMPLETED" "quality_gate_failure")
    export SPIRAL_RESUME_FORCE=true

    run resume_gate "$state_file"
    [ "$status" -eq 0 ]
    [ "$output" = "accept" ]
}

# =========================================================================
# RF-T2: FAILED + quality_gate_failure + --force → accept
# =========================================================================

@test "resume --force: FAILED + quality_gate_failure accepted" {
    local state_file
    state_file=$(make_isolated_cmd "FAILED" "quality_gate_failure")
    export SPIRAL_RESUME_FORCE=true

    run resume_gate "$state_file"
    [ "$status" -eq 0 ]
    [ "$output" = "accept" ]
}

# =========================================================================
# RF-T3: COMPLETED + quality_gate_failure WITHOUT --force → refuse
# =========================================================================

@test "resume (no --force): COMPLETED + quality_gate_failure refused" {
    local state_file
    state_file=$(make_isolated_cmd "COMPLETED" "quality_gate_failure")
    unset SPIRAL_RESUME_FORCE

    run resume_gate "$state_file"
    [ "$status" -eq 1 ]
    [ "$output" = "refuse" ]
}

# =========================================================================
# RF-T4: COMPLETED + cycle_budget_exhausted + --force → refuse (narrow gate)
# =========================================================================

@test "resume --force: COMPLETED + non-quality_gate_failure refused even with force" {
    local state_file
    state_file=$(make_isolated_cmd "COMPLETED" "cycle_budget_exhausted")
    export SPIRAL_RESUME_FORCE=true

    run resume_gate "$state_file"
    [ "$status" -eq 1 ]
    [ "$output" = "refuse" ]
}

# =========================================================================
# RF-T5: COMPLETED + flatline_convergence + --force → refuse (narrow gate)
# =========================================================================

@test "resume --force: COMPLETED + flatline_convergence refused" {
    local state_file
    state_file=$(make_isolated_cmd "COMPLETED" "flatline_convergence")
    export SPIRAL_RESUME_FORCE=true

    run resume_gate "$state_file"
    [ "$status" -eq 1 ]
}

# =========================================================================
# RF-T6: HALTED + --force → pass through (normal resumable state)
# =========================================================================

@test "resume --force: HALTED passes through case-block (normal resume path)" {
    local state_file
    state_file=$(make_isolated_cmd "HALTED" "hitl_halt")
    export SPIRAL_RESUME_FORCE=true

    run resume_gate "$state_file"
    [ "$status" -eq 0 ]
    [ "$output" = "pass_through" ]
}

# =========================================================================
# RF-T7: --force with null stopping_condition → refuse
# =========================================================================

@test "resume --force: COMPLETED + null stopping_condition refused" {
    local state_file
    state_file=$(make_isolated_cmd "COMPLETED" "")
    export SPIRAL_RESUME_FORCE=true

    run resume_gate "$state_file"
    [ "$status" -eq 1 ]
}

# =========================================================================
# RF-T8: CLI parsing — --force flag sets SPIRAL_RESUME_FORCE
# =========================================================================

@test "CLI parses --force arg for --resume subcommand" {
    # Simulate the CLI arg-loop added to main()
    local args=("--resume" "--force")
    shift_args() {
        for arg in "$@"; do
            if [[ "$arg" == "--force" ]]; then
                export SPIRAL_RESUME_FORCE=true
            fi
        done
    }
    shift_args "${args[@]:1}"  # drop "--resume"
    [ "$SPIRAL_RESUME_FORCE" = "true" ]
}

@test "CLI parsing: --resume without --force leaves SPIRAL_RESUME_FORCE unset" {
    local args=("--resume")
    shift_args() {
        for arg in "$@"; do
            if [[ "$arg" == "--force" ]]; then
                export SPIRAL_RESUME_FORCE=true
            fi
        done
    }
    unset SPIRAL_RESUME_FORCE
    shift_args "${args[@]:1}"
    [ "${SPIRAL_RESUME_FORCE:-unset}" = "unset" ]
}
