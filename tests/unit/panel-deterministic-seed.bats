#!/usr/bin/env bats
# =============================================================================
# tests/unit/panel-deterministic-seed.bats
#
# cycle-098 Sprint 1D — panel_select must produce a deterministic selection
# for the same (decision_id, context_hash) pair, across processes (FR-L1-3).
#
# Seed construction: sha256(decision_id || context_hash) interpreted as a
# 256-bit unsigned integer; selected panelist index = seed % len(sorted(panelists, key=id)).
#
# AC sources:
#   - PRD FR-L1-3 (HIGH_CONSENSUS, IMP-002)
#   - SDD §1.4.2 L1 — "Sort panelists by id (cross-process determinism)"
#   - SDD §5.3.2 — panel_select API
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PANEL_LIB="$PROJECT_ROOT/.claude/scripts/lib/hitl-jury-panel-lib.sh"

    [[ -f "$PANEL_LIB" ]] || skip "hitl-jury-panel-lib.sh not present"

    # shellcheck disable=SC1090
    source "$PANEL_LIB"
}

# -----------------------------------------------------------------------------
# Same input → same output
# -----------------------------------------------------------------------------
@test "panel_select: deterministic for same (decision_id, context_hash) — call 1 = call 2" {
    local panelists='[{"id":"alpha"},{"id":"beta"},{"id":"gamma"}]'
    local r1 r2
    r1="$(panel_select "$panelists" "decision-x" "abc123")"
    r2="$(panel_select "$panelists" "decision-x" "abc123")"
    [[ "$r1" == "$r2" ]]
}

@test "panel_select: output emits selection { selected_panelist_id, selection_seed, sorted_panelist_ids }" {
    local panelists='[{"id":"alpha"},{"id":"beta"},{"id":"gamma"}]'
    local out
    out="$(panel_select "$panelists" "decision-x" "abc123")"
    # Expect JSON object with these keys.
    echo "$out" | jq -e '.selected_panelist_id and .selection_seed and (.sorted_panelist_ids | type == "array")' >/dev/null
}

@test "panel_select: selection_seed is 64-hex (SHA-256 hex)" {
    local panelists='[{"id":"alpha"},{"id":"beta"},{"id":"gamma"}]'
    local seed
    seed="$(panel_select "$panelists" "decision-x" "abc123" | jq -r '.selection_seed')"
    [[ "$seed" =~ ^[0-9a-f]{64}$ ]]
}

@test "panel_select: panelist order does not affect selection — sort-by-id is canonical" {
    local panelists_a='[{"id":"alpha"},{"id":"beta"},{"id":"gamma"}]'
    local panelists_b='[{"id":"gamma"},{"id":"alpha"},{"id":"beta"}]'
    local sel_a sel_b
    sel_a="$(panel_select "$panelists_a" "decision-y" "context-y" | jq -r '.selected_panelist_id')"
    sel_b="$(panel_select "$panelists_b" "decision-y" "context-y" | jq -r '.selected_panelist_id')"
    [[ "$sel_a" == "$sel_b" ]]
}

@test "panel_select: different decision_id → potentially different selection" {
    # We can't guarantee they differ (collision possible) but seed must differ.
    local panelists='[{"id":"alpha"},{"id":"beta"},{"id":"gamma"}]'
    local seed1 seed2
    seed1="$(panel_select "$panelists" "decision-1" "ctx" | jq -r '.selection_seed')"
    seed2="$(panel_select "$panelists" "decision-2" "ctx" | jq -r '.selection_seed')"
    [[ "$seed1" != "$seed2" ]]
}

@test "panel_select: different context_hash → different seed" {
    local panelists='[{"id":"alpha"},{"id":"beta"},{"id":"gamma"}]'
    local seed1 seed2
    seed1="$(panel_select "$panelists" "decision-1" "ctx-A" | jq -r '.selection_seed')"
    seed2="$(panel_select "$panelists" "decision-1" "ctx-B" | jq -r '.selection_seed')"
    [[ "$seed1" != "$seed2" ]]
}

@test "panel_select: rejects empty panelist list" {
    run panel_select "[]" "decision-x" "abc123"
    [[ "$status" -ne 0 ]]
}

@test "panel_select: cross-process determinism — bash subshell vs main shell" {
    local panelists='[{"id":"alpha"},{"id":"beta"},{"id":"gamma"}]'
    local r_main r_sub
    r_main="$(panel_select "$panelists" "decision-z" "ctx-z" | jq -r '.selected_panelist_id')"
    r_sub="$(bash -c "source '$PANEL_LIB'; panel_select '$panelists' decision-z ctx-z" | jq -r '.selected_panelist_id')"
    [[ "$r_main" == "$r_sub" ]]
}

@test "panel_select: selected index is in range [0, len(panelists)-1]" {
    # Walk a small sample of decisions, verify selected_panelist_id is one of the inputs.
    local panelists='[{"id":"alpha"},{"id":"beta"},{"id":"gamma"}]'
    local sel
    for i in 1 2 3 4 5; do
        sel="$(panel_select "$panelists" "d-$i" "ctx-$i" | jq -r '.selected_panelist_id')"
        case "$sel" in
            alpha|beta|gamma) ;;
            *) printf 'unexpected selection: %s\n' "$sel" >&2; return 1 ;;
        esac
    done
}
