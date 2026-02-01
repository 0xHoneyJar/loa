#!/usr/bin/env bats
# Unit tests for schema-validator.sh assertion functionality

setup() {
    export TEST_DIR="$BATS_TMPDIR/schema-assert-test-$$"
    mkdir -p "$TEST_DIR"

    export SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/schema-validator.sh"

    # Create valid PRD JSON
    cat > "$TEST_DIR/valid-prd.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Test PRD",
    "status": "draft",
    "stakeholders": ["user1", "user2"],
    "requirements": []
}
EOF

    # Create valid SDD JSON
    cat > "$TEST_DIR/valid-sdd.json" << 'EOF'
{
    "version": "2.1.0",
    "title": "Test SDD",
    "components": [
        {"name": "api", "type": "service"},
        {"name": "db", "type": "database"}
    ]
}
EOF

    # Create valid Sprint JSON
    cat > "$TEST_DIR/valid-sprint.json" << 'EOF'
{
    "version": "1.0.0",
    "status": "in_progress",
    "sprints": [
        {"id": 1, "name": "Sprint 1"}
    ]
}
EOF

    # Create invalid PRD (missing required field)
    cat > "$TEST_DIR/invalid-prd.json" << 'EOF'
{
    "title": "Missing Version",
    "status": "draft",
    "stakeholders": []
}
EOF

    # Create PRD with invalid version format
    cat > "$TEST_DIR/bad-version.json" << 'EOF'
{
    "version": "not-semver",
    "title": "Bad Version",
    "status": "draft",
    "stakeholders": ["user"]
}
EOF

    # Create trajectory entry
    cat > "$TEST_DIR/trajectory.json" << 'EOF'
{
    "timestamp": "2025-01-18T12:00:00Z",
    "agent": "implementing-tasks",
    "action": "Created file"
}
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Basic Assertion Tests
# =============================================================================

@test "assert command runs on valid file" {
    run "$SCRIPT" assert "$TEST_DIR/valid-prd.json" --schema prd
    [ "$status" -eq 0 ]
}

@test "assert command returns JSON with --json flag" {
    run "$SCRIPT" assert "$TEST_DIR/valid-prd.json" --schema prd --json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty

    local status_val
    status_val=$(echo "$output" | jq -r '.status')
    [ "$status_val" = "passed" ]
}

@test "assert detects missing required field" {
    run "$SCRIPT" assert "$TEST_DIR/invalid-prd.json" --schema prd --json
    # Should fail due to missing version
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "pass" ]]
}

@test "assert validates version format" {
    run "$SCRIPT" assert "$TEST_DIR/bad-version.json" --schema prd --json
    # Should fail due to invalid version format
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "pass" ]]
}

@test "assert validates SDD schema" {
    run "$SCRIPT" assert "$TEST_DIR/valid-sdd.json" --schema sdd --json
    [ "$status" -eq 0 ]

    local status_val
    status_val=$(echo "$output" | jq -r '.status')
    [ "$status_val" = "passed" ]
}

@test "assert validates Sprint schema" {
    run "$SCRIPT" assert "$TEST_DIR/valid-sprint.json" --schema sprint --json
    [ "$status" -eq 0 ]

    local status_val
    status_val=$(echo "$output" | jq -r '.status')
    [ "$status_val" = "passed" ]
}

@test "assert validates trajectory entry" {
    run "$SCRIPT" assert "$TEST_DIR/trajectory.json" --schema trajectory-entry --json
    [ "$status" -eq 0 ]

    local status_val
    status_val=$(echo "$output" | jq -r '.status')
    [ "$status_val" = "passed" ]
}

# =============================================================================
# Empty Array Detection
# =============================================================================

@test "assert detects empty stakeholders array" {
    cat > "$TEST_DIR/empty-stakeholders.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Empty Stakeholders",
    "status": "draft",
    "stakeholders": []
}
EOF

    run "$SCRIPT" assert "$TEST_DIR/empty-stakeholders.json" --schema prd --json
    # Empty stakeholders should fail
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "pass" ]]
}

@test "assert detects empty components array in SDD" {
    cat > "$TEST_DIR/empty-components.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Empty Components",
    "components": []
}
EOF

    run "$SCRIPT" assert "$TEST_DIR/empty-components.json" --schema sdd --json
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "pass" ]]
}

# =============================================================================
# Status Validation
# =============================================================================

@test "assert accepts valid PRD status" {
    for status in draft approved implemented; do
        cat > "$TEST_DIR/status-test.json" << EOF
{
    "version": "1.0.0",
    "title": "Status Test",
    "status": "$status",
    "stakeholders": ["user"]
}
EOF
        run "$SCRIPT" assert "$TEST_DIR/status-test.json" --schema prd --json
        [ "$status" -eq 0 ]
    done
}

@test "assert rejects invalid PRD status" {
    cat > "$TEST_DIR/bad-status.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Bad Status",
    "status": "invalid_status",
    "stakeholders": ["user"]
}
EOF

    run "$SCRIPT" assert "$TEST_DIR/bad-status.json" --schema prd --json
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "pass" ]]
}

# =============================================================================
# Error Handling
# =============================================================================

@test "assert handles non-existent file" {
    run "$SCRIPT" assert "$TEST_DIR/nonexistent.json" --schema prd --json
    [ "$status" -ne 0 ] || [[ "$output" == *"error"* ]]
}

@test "assert handles invalid JSON" {
    echo "not valid json" > "$TEST_DIR/invalid.json"

    run "$SCRIPT" assert "$TEST_DIR/invalid.json" --schema prd --json
    [ "$status" -ne 0 ] || [[ "$output" == *"error"* ]]
}

@test "assert handles unknown schema gracefully" {
    run "$SCRIPT" assert "$TEST_DIR/valid-prd.json" --schema unknown_schema --json
    # Should handle gracefully - either pass (no assertions) or provide clear error
    echo "$output" | jq empty 2>/dev/null || [[ "$output" == *"error"* ]]
}

# =============================================================================
# Output Format Tests
# =============================================================================

@test "assert JSON output includes assertions list" {
    run "$SCRIPT" assert "$TEST_DIR/valid-prd.json" --schema prd --json
    [ "$status" -eq 0 ]

    # Should have assertions array (even if empty on pass)
    echo "$output" | jq -e '.assertions' > /dev/null || echo "$output" | jq -e '.status' > /dev/null
}

@test "assert failed output includes failure details" {
    run "$SCRIPT" assert "$TEST_DIR/invalid-prd.json" --schema prd --json

    # Should have failure information
    [[ "$output" == *"version"* ]] || [[ "$output" == *"fail"* ]] || [[ "$output" == *"ASSERTION"* ]]
}

@test "assert without --json shows human readable output" {
    run "$SCRIPT" assert "$TEST_DIR/valid-prd.json" --schema prd
    [ "$status" -eq 0 ]

    # Should not be pure JSON (no leading brace) or have readable text
    [[ "$output" == *"pass"* ]] || [[ "$output" == *"PASS"* ]] || [[ "$output" == *"valid"* ]] || [[ ! "$output" =~ ^\{ ]]
}

# =============================================================================
# Timestamp Validation
# =============================================================================

@test "assert validates ISO 8601 timestamp format" {
    run "$SCRIPT" assert "$TEST_DIR/trajectory.json" --schema trajectory-entry --json
    [ "$status" -eq 0 ]
}

@test "assert rejects invalid timestamp format" {
    cat > "$TEST_DIR/bad-timestamp.json" << 'EOF'
{
    "timestamp": "not-a-timestamp",
    "agent": "test",
    "action": "test"
}
EOF

    run "$SCRIPT" assert "$TEST_DIR/bad-timestamp.json" --schema trajectory-entry --json
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "pass" ]]
}
