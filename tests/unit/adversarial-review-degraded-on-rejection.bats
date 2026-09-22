#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-degraded-on-rejection.bats
#
# cycle-124 Sprint 2 Task 2.4 (FR-7): the KF-004 degraded-trajectory record
# on rejected findings no longer hides behind a config flag — any result
# with rejected_count > 0 emits it, on both parse paths; a clean result never does.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    EMITS="$TEST_DIR/emits"
    : > "$EMITS"
    degraded_verdict_maybe_emit() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$EMITS"; return 0; }
}

_result() {  # <rejected> <repaired> <parse_path>
    jq -nc --argjson rc "$1" --argjson rp "$2" --arg pp "$3" '{findings: [], metadata: {type: "review", model: "m",
        sprint_id: "sprint-x", timestamp: "2026-09-18T00:00:00Z", status: "reviewed", degraded: false,
        rejected_count: $rc, repaired_count: $rp, parse_path: $pp}}'
}

@test "DR-1: rejected_count>0 on the normalized path emits the repair-loop DEGRADED record (no flag)" {
    _emit_rejection_degraded "$(_result 2 1 normalized)" review sprint-x
    grep -q '^adversarial-review:review:repair-loop|DEGRADED|kf-004-repair-loop: 2 rejected finding(s) survived repair (1 repaired; parse_path=normalized)$' "$EMITS"
}

@test "DR-2: rejected_count>0 on the ENFORCED path emits too (a drift signal, not a model slip)" {
    _emit_rejection_degraded "$(_result 1 0 schema_enforced)" audit sprint-x
    grep -q '^adversarial-review:audit:repair-loop|DEGRADED|.*parse_path=schema_enforced)$' "$EMITS"
}

@test "DR-3: rejected_count=0 emits nothing" {
    _emit_rejection_degraded "$(_result 0 0 normalized)" review sprint-x
    [ ! -s "$EMITS" ]
}

@test "DR-4: write_output routes through the unconditional emitter (grep-lock: no repair_loop gate remains)" {
    grep -q '_emit_rejection_degraded "\$result_json" "\$type" "\$sprint_id"' "$ADVERSARIAL_REVIEW"
    ! grep -q 'CONF_REPAIR_LOOP' "$ADVERSARIAL_REVIEW"
}
