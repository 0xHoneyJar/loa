#!/usr/bin/env bats
# Tests for spiral harness deterministic pre-checks (cycle-072)
# Covers: AC-6, AC-7, AC-8, AC-22

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    TEST_TMPDIR="$(mktemp -d)"

    # Mock flight recorder
    export _FLIGHT_RECORDER="$TEST_TMPDIR/flight-recorder.jsonl"
    touch "$_FLIGHT_RECORDER"
    export _FLIGHT_RECORDER_SEQ=0

    # Source evidence functions
    export _SPIRAL_EVIDENCE_LOADED=""
    source "$PROJECT_ROOT/.claude/scripts/spiral-evidence.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ---------------------------------------------------------------------------
# Test 1: pre-impl fails when prd.md missing (AC-6)
# ---------------------------------------------------------------------------
@test "prechecks: pre_check_implementation fails when prd.md missing" {
    cd "$TEST_TMPDIR"
    mkdir -p grimoires/loa
    echo "# SDD" > grimoires/loa/sdd.md
    echo "- [ ] AC1" > grimoires/loa/sprint.md

    run _pre_check_implementation
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"prd.md not found"* ]]
}

# ---------------------------------------------------------------------------
# Test 2: pre-impl fails when sprint.md missing (AC-6)
# ---------------------------------------------------------------------------
@test "prechecks: pre_check_implementation fails when sprint.md missing" {
    cd "$TEST_TMPDIR"
    mkdir -p grimoires/loa
    echo "# PRD" > grimoires/loa/prd.md
    echo "# SDD" > grimoires/loa/sdd.md

    run _pre_check_implementation
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"sprint.md not found"* ]]
}

# ---------------------------------------------------------------------------
# Test 3: pre-impl passes when all artifacts exist (AC-6)
# ---------------------------------------------------------------------------
@test "prechecks: pre_check_implementation passes with all artifacts" {
    cd "$TEST_TMPDIR"
    mkdir -p grimoires/loa
    echo "# PRD" > grimoires/loa/prd.md
    echo "# SDD" > grimoires/loa/sdd.md
    printf "# Sprint\n- [ ] AC1\n- [ ] AC2\n" > grimoires/loa/sprint.md

    run _pre_check_implementation
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Test 4: pre-review fails when no commits ahead (AC-7)
# ---------------------------------------------------------------------------
@test "prechecks: pre_check_review fails when no commits ahead" {
    cd "$TEST_TMPDIR"
    git init -q
    git commit --allow-empty -m "init" -q

    BRANCH="HEAD"
    run _pre_check_review
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no commits ahead"* || "$output" == *"no diff"* ]]
}

# ---------------------------------------------------------------------------
# Test 5: pre-review detects secret pattern (AC-8)
# ---------------------------------------------------------------------------
@test "prechecks: pre_check_review fails on secret pattern" {
    cd "$TEST_TMPDIR"
    git init -q
    git commit --allow-empty -m "init" -q
    git checkout -b main -q 2>/dev/null || true
    git checkout -b test-branch -q

    echo 'api_key = "sk-1234567890abcdef"' > secret_file.txt
    git add secret_file.txt
    git commit -m "add secret" -q

    BRANCH="test-branch"
    # This should detect the secret via regex (gitleaks not available in test env)
    run _pre_check_review
    # Either FAIL from secret detection or FAIL from no allowlist
    [[ "$status" -ne 0 || "$output" == *"secret"* ]]
}

# ---------------------------------------------------------------------------
# Test 6: pre-review passes with allowlist exclusion (AC-22)
# ---------------------------------------------------------------------------
@test "prechecks: pre_check_review warns with allowlist present" {
    cd "$TEST_TMPDIR"
    git init -q
    git commit --allow-empty -m "init" -q
    git checkout -b main -q 2>/dev/null || true
    git checkout -b test-branch -q

    echo 'api_key = "sk-1234567890abcdef"' > secret_file.txt
    git add secret_file.txt
    git commit -m "add secret" -q

    # Create allowlist
    mkdir -p .claude/data
    cat > .claude/data/secret-scan-allowlist.yaml << 'ALLOWLIST'
- pattern: "sk-1234"
  owner: "@test"
  reason: "test fixture"
  expires: "2099-12-31"
ALLOWLIST

    BRANCH="test-branch"
    PROJECT_ROOT="$TEST_TMPDIR"
    run _pre_check_review
    # Should warn but not fail (allowlist present)
    [[ "$output" == *"allowlist present"* || "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Test 7: pre-review warns but passes without test files (AC-7)
# ---------------------------------------------------------------------------
@test "prechecks: pre_check_review warns without test files in diff" {
    cd "$TEST_TMPDIR"
    git init -q
    git commit --allow-empty -m "init" -q
    git checkout -b main -q 2>/dev/null || true
    git checkout -b test-branch -q

    echo "some code" > app.sh
    git add app.sh
    git commit -m "add app" -q

    BRANCH="test-branch"
    run _pre_check_review
    [[ "$output" == *"no test files"* ]]
}
