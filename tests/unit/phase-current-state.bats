#!/usr/bin/env bats
# =============================================================================
# phase-current-state.bats — tests for cycle-092 Sprint 1 .phase-current file
# =============================================================================
# Validates the `.phase-current` state-file lifecycle:
# - _phase_current_write creates tab-separated record with defaults
# - _phase_current_touch updates attempt/fix_iter without changing start_ts
# - _phase_current_read returns raw line or individual fields
# - _phase_current_clear removes file (idempotent)
# - EXIT trap in harness main() clears file on abnormal exit (crash)
# - Missing arguments, unwritable paths, and absent files fail safely
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export EVIDENCE_SH="$PROJECT_ROOT/.claude/scripts/spiral-evidence.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/phase-current-test"
    mkdir -p "$TEST_DIR"
}

teardown() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# =========================================================================
# PC-T1: _phase_current_write — basic record creation
# =========================================================================

@test "write creates .phase-current with tab-separated fields in order" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW' '2' '1'
        cat '$TEST_DIR/.phase-current'
    "
    [ "$status" -eq 0 ]
    # Format: phase_label \t start_ts \t attempt_num \t fix_iter
    [[ "$output" =~ ^REVIEW[[:space:]]+[0-9T:Z-]+[[:space:]]+2[[:space:]]+1$ ]]
}

@test "write defaults attempt_num and fix_iter to '-' when unspecified" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'DISCOVERY'
        cat '$TEST_DIR/.phase-current'
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^DISCOVERY[[:space:]]+[0-9T:Z-]+[[:space:]]+-[[:space:]]+-$ ]]
}

@test "write captures UTC ISO-8601 start_ts" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'IMPLEMENT'
        awk -F'\t' '{print \$2}' '$TEST_DIR/.phase-current'
    "
    [ "$status" -eq 0 ]
    # Match YYYY-MM-DDTHH:MM:SSZ
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "write is atomic (uses .tmp + rename — no .tmp leftover)" {
    # After a successful write, .phase-current exists and no .tmp file remains.
    # ls doesn't show dotfiles by default, so check via filesystem directly.
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW' '1' '-'
        [[ -f '$TEST_DIR/.phase-current' ]] || exit 1
        [[ ! -f '$TEST_DIR/.phase-current.tmp' ]] || exit 1
    "
    [ "$status" -eq 0 ]
}

@test "write overwrites existing file (not append)" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'DISCOVERY'
        _phase_current_write '$TEST_DIR' 'REVIEW' '1' '-'
        wc -l < '$TEST_DIR/.phase-current'
    "
    [ "$status" -eq 0 ]
    # Single line
    [[ "$output" =~ ^[[:space:]]*1[[:space:]]*$ ]]
}

@test "write fails when cycle_dir is missing or empty" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '' 'REVIEW'
    "
    [ "$status" -eq 1 ]
}

@test "write fails when phase_label is empty" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' ''
    "
    [ "$status" -eq 1 ]
}

@test "write fails when cycle_dir does not exist" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR/nonexistent' 'REVIEW'
    "
    [ "$status" -eq 1 ]
}

# cycle-092 Sprint 1 review F-3: phase_label input validation
@test "write rejects phase_label containing tab (prevents field corruption)" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' \$'REVIEW\tMALICIOUS' '1' '-'
    "
    [ "$status" -eq 1 ]
    [[ ! -f "$TEST_DIR/.phase-current" ]]
}

@test "write rejects phase_label containing newline (prevents single-line break)" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' \$'REVIEW\nEXTRA_LINE' '1' '-'
    "
    [ "$status" -eq 1 ]
    [[ ! -f "$TEST_DIR/.phase-current" ]]
}

# =========================================================================
# PC-T2: _phase_current_touch — sub-state updates
# =========================================================================

@test "touch updates attempt_num without changing phase_label or start_ts" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW' '1' '-'
        orig_ts=\$(awk -F'\t' '{print \$2}' '$TEST_DIR/.phase-current')
        sleep 1
        _phase_current_touch '$TEST_DIR' '2' ''
        new_line=\$(cat '$TEST_DIR/.phase-current')
        new_ts=\$(echo \"\$new_line\" | awk -F'\t' '{print \$2}')
        # phase_label preserved
        [[ \"\$new_line\" == REVIEW* ]] || exit 1
        # start_ts preserved (no re-writing across touch)
        [[ \"\$orig_ts\" == \"\$new_ts\" ]] || exit 1
        # attempt_num updated to 2
        attempt=\$(echo \"\$new_line\" | awk -F'\t' '{print \$3}')
        [[ \"\$attempt\" == '2' ]] || exit 1
    "
    [ "$status" -eq 0 ]
}

@test "touch updates fix_iter without disturbing attempt_num" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW' '2' '-'
        _phase_current_touch '$TEST_DIR' '' '1'
        line=\$(cat '$TEST_DIR/.phase-current')
        attempt=\$(echo \"\$line\" | awk -F'\t' '{print \$3}')
        fix=\$(echo \"\$line\" | awk -F'\t' '{print \$4}')
        [[ \"\$attempt\" == '2' ]] || exit 1
        [[ \"\$fix\" == '1' ]] || exit 1
    "
    [ "$status" -eq 0 ]
}

@test "touch empty args preserve existing values" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW' '2' '1'
        _phase_current_touch '$TEST_DIR' '' ''
        line=\$(cat '$TEST_DIR/.phase-current')
        attempt=\$(echo \"\$line\" | awk -F'\t' '{print \$3}')
        fix=\$(echo \"\$line\" | awk -F'\t' '{print \$4}')
        [[ \"\$attempt\" == '2' ]] || exit 1
        [[ \"\$fix\" == '1' ]] || exit 1
    "
    [ "$status" -eq 0 ]
}

@test "touch fails when .phase-current does not exist (no phase in flight)" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_touch '$TEST_DIR' '2' ''
    "
    [ "$status" -eq 1 ]
}

# =========================================================================
# PC-T3: _phase_current_read — field extraction
# =========================================================================

@test "read without field arg returns raw tab-separated line" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW' '2' '1'
        _phase_current_read '$TEST_DIR'
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^REVIEW[[:space:]]+[0-9T:Z-]+[[:space:]]+2[[:space:]]+1$ ]]
}

@test "read returns phase_label field" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'IMPLEMENT' '-' '-'
        _phase_current_read '$TEST_DIR' phase_label
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "IMPLEMENT" ]]
}

@test "read returns attempt_num field" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'AUDIT' '3' '-'
        _phase_current_read '$TEST_DIR' attempt_num
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "3" ]]
}

@test "read returns fix_iter field" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW' '1' '2'
        _phase_current_read '$TEST_DIR' fix_iter
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "2" ]]
}

@test "read returns start_ts field (UTC ISO-8601)" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'DISCOVERY'
        _phase_current_read '$TEST_DIR' start_ts
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "read fails with unknown field name" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW'
        _phase_current_read '$TEST_DIR' bogus_field
    "
    [ "$status" -eq 1 ]
}

@test "read fails when .phase-current is absent" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_read '$TEST_DIR'
    "
    [ "$status" -eq 1 ]
}

# =========================================================================
# PC-T4: _phase_current_clear — removal + idempotence
# =========================================================================

@test "clear removes .phase-current" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_write '$TEST_DIR' 'REVIEW'
        _phase_current_clear '$TEST_DIR'
        [[ ! -f '$TEST_DIR/.phase-current' ]]
    "
    [ "$status" -eq 0 ]
}

@test "clear is idempotent (succeeds when file absent)" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_clear '$TEST_DIR'
        _phase_current_clear '$TEST_DIR'
    "
    [ "$status" -eq 0 ]
}

@test "clear fails with empty cycle_dir" {
    run bash -c "
        source '$EVIDENCE_SH'
        _phase_current_clear ''
    "
    [ "$status" -eq 1 ]
}

# =========================================================================
# PC-T5: EXIT trap behavior — crash scenarios
# =========================================================================
# The harness main() sets up:
#   trap '_phase_current_clear "$CYCLE_DIR"; log ".phase-current cleared"' EXIT
# These tests validate the trap invocation itself works under bash abnormal
# exit modes (exit 1, kill, set -e trigger).

@test "EXIT trap clears .phase-current on normal exit" {
    run bash -c "
        source '$EVIDENCE_SH'
        trap '_phase_current_clear '\''$TEST_DIR'\''' EXIT
        _phase_current_write '$TEST_DIR' 'REVIEW'
    "
    [ "$status" -eq 0 ]
    [[ ! -f "$TEST_DIR/.phase-current" ]]
}

@test "EXIT trap clears .phase-current on non-zero exit" {
    run bash -c "
        source '$EVIDENCE_SH'
        trap '_phase_current_clear '\''$TEST_DIR'\''' EXIT
        _phase_current_write '$TEST_DIR' 'REVIEW'
        exit 42
    "
    [ "$status" -eq 42 ]
    [[ ! -f "$TEST_DIR/.phase-current" ]]
}

@test "EXIT trap clears .phase-current on set -e trigger (crash)" {
    run bash -c "
        set -e
        source '$EVIDENCE_SH'
        trap '_phase_current_clear '\''$TEST_DIR'\''' EXIT
        _phase_current_write '$TEST_DIR' 'IMPLEMENT'
        false  # triggers set -e exit
        echo 'UNREACHABLE'
    "
    # set -e from `false` gives exit 1
    [ "$status" -eq 1 ]
    [[ "$output" != *"UNREACHABLE"* ]]
    [[ ! -f "$TEST_DIR/.phase-current" ]]
}

# =========================================================================
# PC-T6: Format stability — atomicity of rapid writes
# =========================================================================

@test "rapid write sequence produces no partial files" {
    # Issue 20 writes in succession; monitor should never see .tmp
    run bash -c "
        source '$EVIDENCE_SH'
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            _phase_current_write '$TEST_DIR' 'REVIEW' \"\$i\" '-'
        done
        # Final state should be attempt_num=20
        _phase_current_read '$TEST_DIR' attempt_num
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "20" ]]
    [[ ! -f "$TEST_DIR/.phase-current.tmp" ]]
}
