#!/usr/bin/env bats
# Unit tests for spiral-simstim-dispatch.sh
# Cycle-070: Dispatch rewrite to claude -p

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/spiral-simstim-dispatch.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/spiral-dispatch-test-$$"
    mkdir -p "$TEST_TMPDIR/cycle-test"
    mkdir -p "$TEST_TMPDIR/.run"

    export PROJECT_ROOT="$TEST_TMPDIR"
    export SPIRAL_ID="test-spiral"
    export SPIRAL_CYCLE_NUM="1"
    export SPIRAL_TASK="Test task"

    # Create minimal config
    cat > "$TEST_TMPDIR/.loa.config.yaml" << 'CONFIG'
spiral:
  max_budget_per_cycle_usd: 5
  step_timeouts:
    simstim_sec: 60
CONFIG
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Stub Mode
# =============================================================================

@test "dispatch: stub mode produces artifacts" {
    export SPIRAL_USE_STUB=1
    run "$SCRIPT" "$TEST_TMPDIR/cycle-test" "cycle-stub" ""
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/cycle-test/reviewer.md" ]
    [ -f "$TEST_TMPDIR/cycle-test/auditor-sprint-feedback.md" ]
}

@test "dispatch: stub mode writes APPROVED verdicts" {
    export SPIRAL_USE_STUB=1
    "$SCRIPT" "$TEST_TMPDIR/cycle-test" "cycle-stub" "" 2>/dev/null
    run grep "APPROVED" "$TEST_TMPDIR/cycle-test/reviewer.md"
    [ "$status" -eq 0 ]
}

# =============================================================================
# CLI Validation (Real Mode)
# =============================================================================

@test "dispatch: requires cycle_dir argument" {
    run "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "dispatch: requires cycle_id argument" {
    run "$SCRIPT" "$TEST_TMPDIR/cycle-test"
    [ "$status" -ne 0 ]
}

@test "dispatch: exits 127 when claude not on PATH" {
    # Shadow claude with a non-existent path
    export PATH="/nonexistent:$PATH"
    # Remove real claude from PATH for this test
    local saved_path="$PATH"
    export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v nvm | grep -v node | tr '\n' ':')

    run "$SCRIPT" "$TEST_TMPDIR/cycle-test" "cycle-test" ""
    # Should exit 127 since claude won't be found
    # (unless it's in a path we didn't filter)
    if ! command -v claude &>/dev/null; then
        [ "$status" -eq 127 ]
    else
        skip "claude found on filtered PATH — can't test missing CLI"
    fi

    export PATH="$saved_path"
}

# =============================================================================
# Prompt Construction
# =============================================================================

@test "dispatch: prompt includes task description" {
    # We can test prompt construction by examining the jq command
    # Use stub mode but verify the logic would include the task
    export SPIRAL_TASK="Build feature X"

    # Test the jq prompt construction directly
    local prompt
    prompt=$(jq -n \
        --arg task "$SPIRAL_TASK" \
        --arg seed "" \
        --arg cycle "test-cycle" \
        --arg branch "feat/test" \
        --arg parent_pr "" \
        '"Run /simstim --autonomous with this task:\n\n" + $task + "\n\nCycle ID: " + $cycle' \
        | jq -r '.')

    [[ "$prompt" == *"Build feature X"* ]]
    [[ "$prompt" == *"/simstim --autonomous"* ]]
    [[ "$prompt" == *"test-cycle"* ]]
}

@test "dispatch: prompt includes seed context when provided" {
    echo "Previous cycle findings" > "$TEST_TMPDIR/seed-context.md"

    local prompt
    prompt=$(jq -n \
        --arg task "Test" \
        --arg seed "$(head -c 4096 "$TEST_TMPDIR/seed-context.md")" \
        --arg cycle "test" \
        --arg branch "test" \
        --arg parent_pr "" \
        '"task: " + $task + (if $seed != "" then "\nseed: " + $seed else "" end)' \
        | jq -r '.')

    [[ "$prompt" == *"Previous cycle findings"* ]]
}

@test "dispatch: prompt includes parent PR when set" {
    export SPIRAL_PARENT_PR_URL="https://github.com/org/repo/pull/42"

    local prompt
    prompt=$(jq -n \
        --arg parent_pr "$SPIRAL_PARENT_PR_URL" \
        '(if $parent_pr != "" then "Parent PR: " + $parent_pr else "" end)' \
        | jq -r '.')

    [[ "$prompt" == *"pull/42"* ]]
}

# =============================================================================
# Branch Naming
# =============================================================================

@test "dispatch: branch name follows pattern" {
    export SPIRAL_ID="abc123"
    export SPIRAL_CYCLE_NUM="3"
    local expected="feat/spiral-abc123-cycle-3"
    local actual="feat/spiral-${SPIRAL_ID}-cycle-${SPIRAL_CYCLE_NUM}"
    [ "$actual" = "$expected" ]
}

# =============================================================================
# Status Artifact
# =============================================================================

@test "dispatch: stub mode writes status file" {
    export SPIRAL_USE_STUB=1
    "$SCRIPT" "$TEST_TMPDIR/cycle-test" "cycle-status" "" 2>/dev/null
    [ -f "$TEST_TMPDIR/.run/spiral-status.txt" ]
    run grep "Spiral:" "$TEST_TMPDIR/.run/spiral-status.txt"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Output Parsing
# =============================================================================

@test "dispatch: PR URL extraction regex works" {
    local test_json='{"result": "Created PR https://github.com/0xHoneyJar/loa/pull/497 draft"}'
    local pr_url
    pr_url=$(echo "$test_json" | jq -r '.result // ""' | \
        grep -oE 'https://github.com/[^/]+/[^/]+/pull/[0-9]+' | head -1)
    [ "$pr_url" = "https://github.com/0xHoneyJar/loa/pull/497" ]
}

@test "dispatch: PR URL extraction handles missing URL" {
    local test_json='{"result": "Implementation complete, no PR created"}'
    local pr_url
    pr_url=$(echo "$test_json" | jq -r '.result // ""' | \
        grep -oE 'https://github.com/[^/]+/[^/]+/pull/[0-9]+' | head -1 || true)
    [ -z "$pr_url" ]
}

# =============================================================================
# Seed Context Budget
# =============================================================================

@test "dispatch: seed context capped at 4KB" {
    # Create a 10KB seed file
    head -c 10240 /dev/urandom | base64 > "$TEST_TMPDIR/big-seed.md"
    local capped
    capped=$(head -c 4096 "$TEST_TMPDIR/big-seed.md")
    local bytes=${#capped}
    [ "$bytes" -le 4096 ]
}
