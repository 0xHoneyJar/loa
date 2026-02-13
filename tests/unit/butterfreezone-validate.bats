#!/usr/bin/env bats
# Unit tests for butterfreezone-validate.sh
# Sprint 2: Validation — all 7 checks, strict mode, JSON output

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/butterfreezone-validate.sh"
    GEN_SCRIPT="$PROJECT_ROOT/.claude/scripts/butterfreezone-gen.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/butterfreezone-validate-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create a mock repo
    export MOCK_REPO="$TEST_TMPDIR/mock-repo"
    mkdir -p "$MOCK_REPO"
    cd "$MOCK_REPO"

    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    mkdir -p src
    echo 'console.log("hi")' > src/index.js
    git add -A
    git commit -q -m "Initial commit"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Helper: generate a valid BUTTERFREEZONE.md
generate_valid() {
    "$GEN_SCRIPT" --output "$MOCK_REPO/BUTTERFREEZONE.md" 2>/dev/null
}

# =============================================================================
# Script Basics
# =============================================================================

@test "validate: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "validate: --help prints usage and exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: butterfreezone-validate.sh"* ]]
}

# =============================================================================
# Check 1: Missing File
# =============================================================================

@test "validate: missing file fails (exit 1)" {
    run "$SCRIPT" --file "$MOCK_REPO/NONEXISTENT.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"not found"* ]]
}

# =============================================================================
# Check 2: Valid File Passes
# =============================================================================

@test "validate: valid generated file passes all checks (exit 0)" {
    generate_valid

    run "$SCRIPT" --file "$MOCK_REPO/BUTTERFREEZONE.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"FAIL"* ]]
}

# =============================================================================
# Check 3: Missing AGENT-CONTEXT
# =============================================================================

@test "validate: missing AGENT-CONTEXT fails" {
    # Create a file without AGENT-CONTEXT
    cat > "$MOCK_REPO/bad.md" <<'EOF'
# My Project

## Section
<!-- provenance: DERIVED -->
Some content.

<!-- ground-truth-meta
head_sha: abc123
generated_at: 2026-02-13T00:00:00Z
generator: butterfreezone-gen v1.0.0
sections:
-->
EOF

    run "$SCRIPT" --file "$MOCK_REPO/bad.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"AGENT-CONTEXT"* ]]
    [[ "$output" == *"FAIL"* ]]
}

# =============================================================================
# Check 4: Missing Provenance
# =============================================================================

@test "validate: missing provenance tags fails" {
    cat > "$MOCK_REPO/noprov.md" <<'EOF'
<!-- AGENT-CONTEXT
name: test
type: app
purpose: testing
version: 1.0.0
-->

# Test

## Section One
No provenance tag here.

## Section Two
Also no provenance.

<!-- ground-truth-meta
head_sha: abc123
generated_at: 2026-02-13T00:00:00Z
generator: butterfreezone-gen v1.0.0
sections:
-->
EOF

    run "$SCRIPT" --file "$MOCK_REPO/noprov.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"provenance"* ]]
    [[ "$output" == *"FAIL"* ]]
}

# =============================================================================
# Check 5: Missing File Reference
# =============================================================================

@test "validate: non-existent file reference fails" {
    cat > "$MOCK_REPO/badref.md" <<'EOF'
<!-- AGENT-CONTEXT
name: test
type: app
purpose: testing
version: 1.0.0
-->

# Test
<!-- provenance: DERIVED -->

## Section
<!-- provenance: DERIVED -->
See `nonexistent/file.ts:someFunction` for details.

<!-- ground-truth-meta
head_sha: abc123
generated_at: 2026-02-13T00:00:00Z
generator: butterfreezone-gen v1.0.0
sections:
-->
EOF

    run "$SCRIPT" --file "$MOCK_REPO/badref.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"missing"* ]]
}

# =============================================================================
# Check 6: Stale SHA (Advisory)
# =============================================================================

@test "validate: stale head_sha warns (exit 2)" {
    generate_valid

    # Make a new commit to change HEAD
    echo "change" >> src/index.js
    git add -A && git commit -q -m "Change HEAD"

    run "$SCRIPT" --file "$MOCK_REPO/BUTTERFREEZONE.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"mismatch"* ]] || [[ "$output" == *"Stale"* ]]
}

# =============================================================================
# Check 7: Strict Mode
# =============================================================================

@test "validate: strict mode turns warnings into failures" {
    generate_valid

    # Make a new commit to make SHA stale
    echo "change" >> src/index.js
    git add -A && git commit -q -m "Change HEAD"

    # Without strict: exit 2 (warnings)
    run "$SCRIPT" --file "$MOCK_REPO/BUTTERFREEZONE.md"
    [ "$status" -eq 2 ]

    # With strict: exit 1 (failures)
    run "$SCRIPT" --file "$MOCK_REPO/BUTTERFREEZONE.md" --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

# =============================================================================
# Word Budget
# =============================================================================

@test "validate: word budget check works" {
    generate_valid

    run "$SCRIPT" --file "$MOCK_REPO/BUTTERFREEZONE.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Word budget"* ]]
    [[ "$output" == *"PASS"* ]]
}

# =============================================================================
# JSON Output
# =============================================================================

@test "validate: --json outputs valid JSON" {
    generate_valid

    local json_out
    json_out=$("$SCRIPT" --file "$MOCK_REPO/BUTTERFREEZONE.md" --json --quiet 2>/dev/null)

    echo "$json_out" | jq . >/dev/null 2>&1
    [ $? -eq 0 ]

    # Check required fields
    echo "$json_out" | jq -e '.status' >/dev/null
    echo "$json_out" | jq -e '.passed' >/dev/null
    echo "$json_out" | jq -e '.checks' >/dev/null
    echo "$json_out" | jq -e '.validator' >/dev/null
}

@test "validate: --json shows fail status for bad file" {
    run "$SCRIPT" --file "$MOCK_REPO/NONEXISTENT.md" --json --quiet
    [ "$status" -eq 1 ]

    local json_status
    json_status=$(echo "$output" | jq -r '.status')
    [ "$json_status" = "fail" ]
}

# =============================================================================
# Quiet Mode
# =============================================================================

@test "validate: --quiet suppresses output" {
    generate_valid

    run "$SCRIPT" --file "$MOCK_REPO/BUTTERFREEZONE.md" --quiet
    [ "$status" -eq 0 ]
    # Should have no PASS/FAIL output
    [[ "$output" != *"PASS"* ]]
}
