#!/usr/bin/env bats
# =============================================================================
# tests/integration/activation-path/activation-matrix.bats
#
# cycle-109 Sprint 3 T3.1 (FR-3.5 / FR-3.10 / IMP-009) — Activation
# Regression Matrix scaffolding. Commit A in the SDD §5.3.1 sequence.
#
# 810-cell matrix: consumers (9) × roles (5) × response_classes (6) ×
# dispatch_paths (3). Each cell asserts that the verdict_quality envelope
# the consumer surfaces matches the expected status for that
# (consumer, role, response_class, dispatch_path) tuple.
#
# Sprint 3 lifecycle:
#   Commit A (T3.1 — THIS): scaffolding + dimension counts + SKIPPED placeholder.
#     Legacy adapter still on disk; matrix execution deferred.
#   Commit B (T3.2-T3.5): Cluster B regression fixes at cheval path; matrix
#     still SKIPPED (legacy present).
#   Commit C (T3.6): is_flatline_routing_enabled branches removed; matrix
#     wires up against cheval path; CELLS GO LIVE.
#   Commit D (T3.7): DESTRUCTIVE — legacy file deletion (operator-approval
#     C109.OP-S3 required); matrix asserts G-4 legacy LOC = 0.
#
# Why this is a load-bearing scaffold even before live execution:
#   - Pins the dimension counts (any drift fails the matrix-shape test).
#   - Loads dimensions.json so refactors of the data file fail loudly.
#   - Validates that fixture-dir conventions exist (T3.2-T3.5 fill them).
#   - Establishes the bats harness pattern T3.10 CI workflow consumes.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/cycle-109/activation-matrix"
    DIMENSIONS_FILE="$FIXTURE_DIR/dimensions.json"

    [[ -f "$DIMENSIONS_FILE" ]] || {
        printf 'FATAL: dimensions.json not found at %s\n' "$DIMENSIONS_FILE" >&2
        return 1
    }
}

# Tests that exercise the cycle-099 sprint-1C curl-mock harness skip
# gracefully when the helper is not present (CI containers without the
# mock-curl pinned into PATH — same gating cycle-099 used).
_require_curl_mock() {
    [[ -f "$PROJECT_ROOT/tests/lib/curl-mock.sh" ]] \
        || skip "tests/lib/curl-mock.sh not present (cycle-099 sprint-1C harness)"
}

# =============================================================================
# AM-1: dimensions file shape
# =============================================================================

@test "AM1: dimensions.json declares 9 consumers" {
    local count
    count=$(jq '.consumers | length' "$DIMENSIONS_FILE")
    [ "$count" -eq 9 ]
}

@test "AM2: dimensions.json declares 5 substrate roles" {
    local count
    count=$(jq '.roles | length' "$DIMENSIONS_FILE")
    [ "$count" -eq 5 ]
}

@test "AM3: dimensions.json declares 6 response classes" {
    local count
    count=$(jq '.response_classes | length' "$DIMENSIONS_FILE")
    [ "$count" -eq 6 ]
}

@test "AM4: dimensions.json declares 3 dispatch paths" {
    local count
    count=$(jq '.dispatch_paths | length' "$DIMENSIONS_FILE")
    [ "$count" -eq 3 ]
}

@test "AM5: total cell count is 810 (9 × 5 × 6 × 3)" {
    local consumers roles response_classes dispatch_paths total
    consumers=$(jq '.consumers | length' "$DIMENSIONS_FILE")
    roles=$(jq '.roles | length' "$DIMENSIONS_FILE")
    response_classes=$(jq '.response_classes | length' "$DIMENSIONS_FILE")
    dispatch_paths=$(jq '.dispatch_paths | length' "$DIMENSIONS_FILE")
    total=$((consumers * roles * response_classes * dispatch_paths))
    [ "$total" -eq 810 ]

    # Cross-check against the declared expected_cells.total in the file
    local declared
    declared=$(jq '.expected_cells.total' "$DIMENSIONS_FILE")
    [ "$declared" -eq 810 ]
}

# =============================================================================
# AM-6..8: dimension semantic consistency
# =============================================================================

@test "AM6: every consumer's path field is a defined-existing repo path" {
    local i path
    for i in $(jq '.consumers | keys[]' "$DIMENSIONS_FILE"); do
        path=$(jq -r ".consumers[$i].path" "$DIMENSIONS_FILE")
        # Paths may be directories (.claude/skills/foo/) or files;
        # either form must exist relative to PROJECT_ROOT.
        [[ -e "$PROJECT_ROOT/$path" ]] || {
            printf 'consumer[%s] path does not exist: %s\n' "$i" "$path" >&2
            return 1
        }
    done
}

@test "AM7: substrate roles match the v1.3 MODELINV role enum" {
    # cycle-108 sprint-1 T1.F role enum: review/dissent/audit/implementation/arbiter.
    local expected="arbiter audit dissent implementation review"
    local actual
    actual=$(jq -r '.roles[]' "$DIMENSIONS_FILE" | sort | tr '\n' ' ' | sed 's/ $//')
    [ "$actual" = "$expected" ]
}

@test "AM8: response classes cover the 4 documented regression issues + KF-002 + preempt" {
    # Each ID must map to a known SDD §5.3.5 / IMP-009 fixture class:
    #   success                  — happy-path baseline
    #   empty-content            — KF-002 class (cycle-109 PRD-review trajectory)
    #   rate-limited             — provider 429 / RateLimited
    #   chain-exhausted          — #868 class / ChainExhausted hard rule
    #   provider-disconnect      — #774 PROVIDER_DISCONNECT class
    #   context-too-large-preempt — preflight gate dispatch (T1.3)
    local expected="chain-exhausted context-too-large-preempt empty-content provider-disconnect rate-limited success"
    local actual
    actual=$(jq -r '.response_classes[].id' "$DIMENSIONS_FILE" | sort | tr '\n' ' ' | sed 's/ $//')
    [ "$actual" = "$expected" ]
}

# =============================================================================
# AM-9: fixture conventions ready for T3.2-T3.5 to fill in
# =============================================================================

@test "AM9: fixture-cell dir convention is documented in README" {
    grep -q "cells/<consumer>/<role>/<response_class>/<dispatch_path>.json" \
        "$FIXTURE_DIR/README.md"
}

# =============================================================================
# AM-10: scaffold cells (the actual 810-cell sweep)
# =============================================================================
#
# Commit A behavior: every cell SKIPS with a clear reason. Commit C (T3.6)
# flips the skip into live execution by setting LOA_ACTIVATION_MATRIX_LIVE=1
# and providing fixture files at the cells/ paths.
#
# The single-test design uses an inner loop over the cartesian product so
# that scaffolding doesn't generate 810 individual bats names (which would
# explode test-suite reporting). Per-cell granularity comes back when
# T3.10 CI workflow shards by consumer.

@test "AM10: 810-cell sweep — currently SKIPPED (commit A scaffolding)" {
    _require_curl_mock

    if [[ "${LOA_ACTIVATION_MATRIX_LIVE:-0}" != "1" ]]; then
        skip "matrix execution deferred until commit C (T3.6 — is_flatline_routing_enabled branches removed). Set LOA_ACTIVATION_MATRIX_LIVE=1 post-T3.6 to run."
    fi

    # Live mode (post-T3.6) — iterate the cartesian product.
    local consumers_count roles_count classes_count paths_count
    consumers_count=$(jq '.consumers | length' "$DIMENSIONS_FILE")
    roles_count=$(jq '.roles | length' "$DIMENSIONS_FILE")
    classes_count=$(jq '.response_classes | length' "$DIMENSIONS_FILE")
    paths_count=$(jq '.dispatch_paths | length' "$DIMENSIONS_FILE")

    local total_cells=$((consumers_count * roles_count * classes_count * paths_count))
    [ "$total_cells" -eq 810 ]

    local cells_run=0 cells_passed=0 cells_failed=0
    local ci rl cl pa
    for ((ci = 0; ci < consumers_count; ci++)); do
        for ((rl = 0; rl < roles_count; rl++)); do
            for ((cl = 0; cl < classes_count; cl++)); do
                for ((pa = 0; pa < paths_count; pa++)); do
                    cells_run=$((cells_run + 1))
                    # T3.2-T3.5 fill in per-cell fixture loading + assertion.
                    # Placeholder: count cells visited as a smoke check.
                    cells_passed=$((cells_passed + 1))
                done
            done
        done
    done

    [ "$cells_run" -eq 810 ]
    [ "$cells_failed" -eq 0 ]
}

# =============================================================================
# AM-11: SDD §5.3.1 commit sequence checkpoint
# =============================================================================

@test "AM11: legacy adapter still present (commit A is non-destructive)" {
    [[ -f "$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy" ]]
}
