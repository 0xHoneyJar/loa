#!/usr/bin/env bats
# =============================================================================
# tests/unit/panel-disagreement-no-op-default.bats
#
# cycle-098 Sprint 1D — FR-L1-6: disagreement check is caller-configurable.
# Default behavior (no embedding fn provided) is a no-op pass — the panel
# binds the selected view regardless of view variance.
#
# AC sources:
#   - PRD FR-L1-6 (Phase 5 modification: caller-configurable, NOT default-wired)
#   - SDD §1.4.2 L1 — "Run caller-configurable disagreement check (default: no-op pass)"
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PANEL_LIB="$PROJECT_ROOT/.claude/scripts/lib/hitl-jury-panel-lib.sh"

    [[ -f "$PANEL_LIB" ]] || skip "hitl-jury-panel-lib.sh not present"
    # shellcheck disable=SC1090
    source "$PANEL_LIB"
}

@test "disagreement-default: no embedding fn → returns 0 (pass) regardless of views" {
    # Three radically divergent views; default fn must still pass.
    local views
    views=$(jq -nc '[
        {id:"alpha",view:"retry once with 5s backoff"},
        {id:"beta",view:"never retry; surface error to operator immediately"},
        {id:"gamma",view:"add a circuit breaker and migrate to async queue"}
    ]')

    run panel_check_disagreement "$views" "0.5"
    [[ "$status" -eq 0 ]]
}

@test "disagreement-default: empty views → still pass (no work to do)" {
    run panel_check_disagreement "[]" "0.5"
    [[ "$status" -eq 0 ]]
}

@test "disagreement-default: identical views → pass" {
    local views='[{"id":"a","view":"X"},{"id":"b","view":"X"},{"id":"c","view":"X"}]'
    run panel_check_disagreement "$views" "0.5"
    [[ "$status" -eq 0 ]]
}

@test "disagreement-fn-pluggable: LOA_PANEL_DISAGREEMENT_FN points to a script that returns non-zero → fail" {
    # Pluggability AC: caller can supply a script via env var.
    local TEST_DIR
    TEST_DIR="$(mktemp -d)"
    cat > "$TEST_DIR/always-disagree.sh" <<'SH'
#!/usr/bin/env bash
exit 7
SH
    chmod +x "$TEST_DIR/always-disagree.sh"

    LOA_PANEL_DISAGREEMENT_FN="$TEST_DIR/always-disagree.sh" \
        run panel_check_disagreement '[{"id":"a","view":"X"},{"id":"b","view":"Y"}]' "0.5"
    # Non-zero exit → caller's fn signals disagreement
    [[ "$status" -ne 0 ]]
    rm -rf "$TEST_DIR"
}

@test "disagreement-fn-pluggable: LOA_PANEL_DISAGREEMENT_FN script that exits 0 → pass" {
    local TEST_DIR
    TEST_DIR="$(mktemp -d)"
    cat > "$TEST_DIR/always-pass.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$TEST_DIR/always-pass.sh"

    LOA_PANEL_DISAGREEMENT_FN="$TEST_DIR/always-pass.sh" \
        run panel_check_disagreement '[{"id":"a","view":"X"},{"id":"b","view":"Y"}]' "0.5"
    [[ "$status" -eq 0 ]]
    rm -rf "$TEST_DIR"
}
