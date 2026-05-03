#!/usr/bin/env bats
# =============================================================================
# Unit tests for archive_cycle_in_ledger pre-archive gate — issue #674
#
# sprint-bug-140 (TIER 1 batch). Pre-fix: post-merge orchestrator's
# archive_cycle_in_ledger() blindly marks the active cycle as archived even
# when its sprints are still in `planned` / `in_progress` state. The integrity
# guard (post-merge.yml) catches this and reverts on every merge — pipeline
# fails on every cycle PR.
#
# Post-fix: pre-archive gate counts incomplete sprints (status != "completed")
# and skips archival when N > 0. Function still returns 0 (no failure cascade);
# emits a single log line per call (idempotent re-invocations no-op cleanly).
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/post-merge-arch-test-$$"
    mkdir -p "$TEST_TMPDIR"

    export TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/.claude/scripts"
    mkdir -p "$TEST_REPO/.run"
    mkdir -p "$TEST_REPO/grimoires/loa"

    git -C "$TEST_REPO" init --quiet
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"

    # Copy required scripts.
    cp "$PROJECT_ROOT_REAL/.claude/scripts/bootstrap.sh"          "$TEST_REPO/.claude/scripts/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/path-lib.sh"           "$TEST_REPO/.claude/scripts/" 2>/dev/null || true
    cp "$PROJECT_ROOT_REAL/.claude/scripts/post-merge-orchestrator.sh" "$TEST_REPO/.claude/scripts/"

    export PROJECT_ROOT="$TEST_REPO"
    TEST_SCRIPT="$TEST_REPO/.claude/scripts/post-merge-orchestrator.sh"

    echo "init" > "$TEST_REPO/README.md"
    git -C "$TEST_REPO" add README.md
    git -C "$TEST_REPO" commit -m "init" --quiet
}

teardown() {
    cd /
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

skip_if_deps_missing() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# Helper: write a ledger.json with one active cycle whose sprints have given statuses.
# Args: $1 = ledger path, $@ = sprint statuses (e.g., "completed completed")
_write_ledger_with_sprints() {
    local ledger_path="$1"; shift
    local statuses=("$@")
    local sprints_json="["
    local i=0
    for s in "${statuses[@]}"; do
        if [[ "$i" -gt 0 ]]; then
            sprints_json+=","
        fi
        sprints_json+="{\"global_id\": $((100 + i)), \"status\": \"$s\"}"
        i=$((i + 1))
    done
    sprints_json+="]"

    jq -n --argjson sprints "$sprints_json" '{
        schema_version: 1,
        global_sprint_counter: 200,
        active_cycle: "cycle-test-001",
        cycles: [{
            id: "cycle-test-001",
            status: "active",
            started: "2026-05-01T00:00:00Z",
            sprints: $sprints
        }]
    }' > "$ledger_path"
}

# Helper: invoke archive_cycle_in_ledger by sourcing the orchestrator.
# Returns the function's exit status; ledger state is observable via the file.
_invoke_archive() {
    bash -c "
        export PROJECT_ROOT='$TEST_REPO'
        # Source helpers — ignore any auto-execution by exiting before main()
        cd '$TEST_REPO'
        SCRIPT_DIR='$TEST_REPO/.claude/scripts'
        source '$TEST_REPO/.claude/scripts/bootstrap.sh' 2>/dev/null || true
        # Source the orchestrator without invoking main(). Use a guard.
        _LOA_SOURCING_ONLY=1
        # Manually source by extracting the function bodies we need.
        source <(awk '/^archive_cycle_in_ledger\\(\\) \\{/,/^\\}\$/' '$TEST_SCRIPT')
        archive_cycle_in_ledger 2>&1
    "
}

# -----------------------------------------------------------------------------
# Scenario 1.a: cycle with all `completed` sprints → archive succeeds
# -----------------------------------------------------------------------------
@test "archive-gate: cycle with all completed sprints archives normally" {
    skip_if_deps_missing
    _write_ledger_with_sprints "$TEST_REPO/grimoires/loa/ledger.json" "completed" "completed"

    run _invoke_archive
    [[ "$status" -eq 0 ]] || {
        echo "Expected exit 0; got $status"
        echo "output: $output"
        return 1
    }

    local cycle_status
    cycle_status=$(jq -r '.cycles[0].status' "$TEST_REPO/grimoires/loa/ledger.json")
    [[ "$cycle_status" == "archived" ]] || {
        echo "Expected archived, got: $cycle_status"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 1.b: cycle with one planned sprint → archive skipped, log emitted
# -----------------------------------------------------------------------------
@test "archive-gate: cycle with one incomplete sprint is NOT archived" {
    skip_if_deps_missing
    _write_ledger_with_sprints "$TEST_REPO/grimoires/loa/ledger.json" "completed" "planned"

    run _invoke_archive
    [[ "$status" -eq 0 ]] || {
        echo "Expected exit 0 (graceful skip); got $status"
        echo "output: $output"
        return 1
    }

    local cycle_status
    cycle_status=$(jq -r '.cycles[0].status' "$TEST_REPO/grimoires/loa/ledger.json")
    [[ "$cycle_status" == "active" ]] || {
        echo "Expected status remains 'active' (not archived); got: $cycle_status"
        echo "ledger:"
        cat "$TEST_REPO/grimoires/loa/ledger.json"
        return 1
    }

    # Log line should explain the skip
    echo "$output" | grep -qE 'incomplete sprint|skipping archive' || {
        echo "Expected explanation log line, got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 1.c: idempotent re-invocation — no mutation, no log spam
# -----------------------------------------------------------------------------
@test "archive-gate: idempotent re-invocation preserves cycle state" {
    skip_if_deps_missing
    _write_ledger_with_sprints "$TEST_REPO/grimoires/loa/ledger.json" "in_progress"

    # First call
    run _invoke_archive
    [[ "$status" -eq 0 ]]

    # Second call (state unchanged)
    run _invoke_archive
    [[ "$status" -eq 0 ]]

    local cycle_status
    cycle_status=$(jq -r '.cycles[0].status' "$TEST_REPO/grimoires/loa/ledger.json")
    [[ "$cycle_status" == "active" ]]
}

# -----------------------------------------------------------------------------
# Scenario 1.d: cycle with multiple incomplete sprints → still skipped
# -----------------------------------------------------------------------------
@test "archive-gate: multiple incomplete sprints is NOT archived" {
    skip_if_deps_missing
    _write_ledger_with_sprints "$TEST_REPO/grimoires/loa/ledger.json" \
        "completed" "in_progress" "planned" "completed"

    run _invoke_archive
    [[ "$status" -eq 0 ]]

    local cycle_status incomplete
    cycle_status=$(jq -r '.cycles[0].status' "$TEST_REPO/grimoires/loa/ledger.json")
    [[ "$cycle_status" == "active" ]] || {
        echo "Expected active (2 incomplete sprints), got: $cycle_status"
        return 1
    }
    # Log mentions count of incomplete sprints
    incomplete=$(echo "$output" | grep -oE '[0-9]+ incomplete sprint' | head -1 | grep -oE '^[0-9]+')
    [[ "$incomplete" == "2" ]] || {
        echo "Expected log to mention '2 incomplete sprint(s)', got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 1.e: cycle with empty sprints array → archive succeeds
# (zero incomplete sprints since there are no sprints to be incomplete)
# -----------------------------------------------------------------------------
@test "archive-gate: cycle with empty sprints array archives" {
    skip_if_deps_missing
    _write_ledger_with_sprints "$TEST_REPO/grimoires/loa/ledger.json"

    run _invoke_archive
    [[ "$status" -eq 0 ]]

    local cycle_status
    cycle_status=$(jq -r '.cycles[0].status' "$TEST_REPO/grimoires/loa/ledger.json")
    [[ "$cycle_status" == "archived" ]]
}
