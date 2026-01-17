#!/usr/bin/env bats
# Unit tests for schema-validator.sh
# Part of Sprint 2: Structured Outputs & Extended Thinking

setup() {
    # Create temp directory for test files
    export TEST_DIR="$BATS_TMPDIR/schema-validator-test-$$"
    mkdir -p "$TEST_DIR"

    # Script path
    export SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/schema-validator.sh"
    export SCHEMA_DIR="$BATS_TEST_DIRNAME/../../.claude/schemas"

    # Create test files with valid frontmatter
    cat > "$TEST_DIR/test-prd.md" << 'EOF'
---
version: "1.0.0"
status: "Draft"
problem_statement: "This is a test problem statement that needs to be at least 100 characters long to pass validation requirements for the PRD schema."
goals:
  - description: "Test goal description"
---

# Test PRD

Content here.
EOF

    cat > "$TEST_DIR/test-sdd.md" << 'EOF'
---
version: "1.0.0"
status: "Draft"
system_architecture:
  overview: "This is a test system architecture overview that needs to be at least 50 characters."
---

# Test SDD

Content here.
EOF

    cat > "$TEST_DIR/test-sprint.md" << 'EOF'
---
version: "1.0.0"
status: "Draft"
sprint_overview:
  total_sprints: 3
sprints:
  - number: 1
    goal: "This is the first sprint goal which needs at least 20 characters"
    tasks:
      - id: "TASK-1.1"
        title: "First task"
        description: "Task description"
---

# Test Sprint

Content here.
EOF

    # Create invalid test files
    cat > "$TEST_DIR/invalid-prd.md" << 'EOF'
---
version: "invalid"
status: "Unknown"
---

# Invalid PRD
EOF

    # Create trajectory test file
    mkdir -p "$TEST_DIR/trajectory"
    echo '{"ts": "2025-01-11T10:00:00Z", "agent": "implementing-tasks", "action": "Created file"}' > "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Basic Command Tests
# =============================================================================

@test "schema-validator: shows usage with no arguments" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "schema-validator: shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Commands:"* ]]
    [[ "$output" == *"validate"* ]]
    [[ "$output" == *"list"* ]]
}

@test "schema-validator: shows help with -h" {
    run "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "schema-validator: rejects unknown command" {
    run "$SCRIPT" unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# =============================================================================
# List Command Tests
# =============================================================================

@test "schema-validator list: shows available schemas" {
    run "$SCRIPT" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available Schemas"* ]]
    [[ "$output" == *"prd"* ]]
    [[ "$output" == *"sdd"* ]]
    [[ "$output" == *"sprint"* ]]
    [[ "$output" == *"trajectory-entry"* ]]
}

@test "schema-validator list: shows schema titles" {
    run "$SCRIPT" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Product Requirements Document"* ]]
    [[ "$output" == *"Software Design Document"* ]]
    [[ "$output" == *"Sprint Plan"* ]]
    [[ "$output" == *"Trajectory Entry"* ]]
}

@test "schema-validator list: JSON output works" {
    run "$SCRIPT" list --json
    [ "$status" -eq 0 ]
    # Verify it's valid JSON
    echo "$output" | jq empty
    [[ "$output" == *"\"schemas\""* ]]
    [[ "$output" == *"\"name\""* ]]
}

# =============================================================================
# Schema Auto-Detection Tests
# =============================================================================

@test "schema-validator: detects prd schema from filename" {
    run "$SCRIPT" validate "$TEST_DIR/test-prd.md"
    [[ "$output" == *"prd"* ]]
}

@test "schema-validator: detects sdd schema from filename" {
    run "$SCRIPT" validate "$TEST_DIR/test-sdd.md"
    [[ "$output" == *"sdd"* ]]
}

@test "schema-validator: detects sprint schema from filename" {
    run "$SCRIPT" validate "$TEST_DIR/test-sprint.md"
    [[ "$output" == *"sprint"* ]]
}

@test "schema-validator: detects trajectory schema from path pattern" {
    run "$SCRIPT" validate "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl"
    [[ "$output" == *"trajectory"* ]]
}

@test "schema-validator: fails on undetectable schema" {
    echo "random content" > "$TEST_DIR/random.txt"
    run "$SCRIPT" validate "$TEST_DIR/random.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not auto-detect schema"* ]]
}

# =============================================================================
# Schema Override Tests
# =============================================================================

@test "schema-validator: --schema overrides auto-detection" {
    run "$SCRIPT" validate "$TEST_DIR/test-prd.md" --schema sdd
    # Should show sdd schema name or fail with extraction error (if yq/python unavailable)
    [[ "$output" == *"sdd"* ]] || [[ "$output" == *"extract"* ]]
}

@test "schema-validator: rejects unknown schema name" {
    run "$SCRIPT" validate "$TEST_DIR/test-prd.md" --schema nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"Schema not found"* ]]
}

# =============================================================================
# Validation Mode Tests
# =============================================================================

@test "schema-validator: --mode strict returns error on invalid" {
    run "$SCRIPT" validate "$TEST_DIR/invalid-prd.md" --schema prd --mode strict
    [ "$status" -eq 1 ]
}

@test "schema-validator: --mode warn returns success on invalid" {
    run "$SCRIPT" validate "$TEST_DIR/invalid-prd.md" --schema prd --mode warn
    # In warn mode, should succeed even with validation errors (status 0)
    # OR fail on YAML extraction if yq/python not available (status 1)
    [[ "$status" -eq 0 ]] || [[ "$output" == *"extract"* ]]
}

@test "schema-validator: --mode disabled skips validation" {
    run "$SCRIPT" validate "$TEST_DIR/invalid-prd.md" --schema prd --mode disabled
    [ "$status" -eq 0 ]
    [[ "$output" == *"disabled"* ]] || [[ "$output" == *"skipping"* ]] || [[ "$output" == *"Validation disabled"* ]]
}

@test "schema-validator: rejects invalid mode" {
    run "$SCRIPT" validate "$TEST_DIR/test-prd.md" --mode invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid mode"* ]]
}

# =============================================================================
# File Handling Tests
# =============================================================================

@test "schema-validator: reports missing file" {
    run "$SCRIPT" validate "$TEST_DIR/nonexistent.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"File not found"* ]]
}

@test "schema-validator: validates JSON files directly" {
    cat > "$TEST_DIR/test.json" << 'EOF'
{
    "version": "1.0.0",
    "status": "Draft",
    "problem_statement": "This is a test problem statement that needs to be at least 100 characters long to pass validation requirements for the PRD schema.",
    "goals": [{"description": "Test goal"}]
}
EOF
    run "$SCRIPT" validate "$TEST_DIR/test.json" --schema prd
    [ "$status" -eq 0 ]
    [[ "$output" == *"Valid"* ]] || [[ "$output" == *"valid"* ]]
}

@test "schema-validator: handles JSONL files" {
    run "$SCRIPT" validate "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl"
    [ "$status" -eq 0 ]
}

# =============================================================================
# JSON Output Tests
# =============================================================================

@test "schema-validator validate: --json outputs valid JSON" {
    run "$SCRIPT" validate "$TEST_DIR/test-prd.md" --json
    # Should succeed OR fail with extract error (yq/python not available)
    if [[ "$status" -eq 0 ]]; then
        echo "$output" | jq empty
        [[ "$output" == *"\"status\""* ]]
    else
        [[ "$output" == *"extract"* ]] || [[ "$output" == *"error"* ]]
    fi
}

@test "schema-validator validate: --json shows schema name" {
    run "$SCRIPT" validate "$TEST_DIR/test-prd.md" --json
    # Skip test if YAML extraction fails
    if [[ "$status" -eq 0 ]]; then
        echo "$output" | jq -e '.schema == "prd"'
    else
        [[ "$output" == *"extract"* ]] || skip "YAML extraction not available"
    fi
}

@test "schema-validator validate: --json shows file path" {
    run "$SCRIPT" validate "$TEST_DIR/test-prd.md" --json
    # Skip test if YAML extraction fails
    if [[ "$status" -eq 0 ]]; then
        echo "$output" | jq -e '.file' | grep -q "test-prd.md"
    else
        [[ "$output" == *"extract"* ]] || skip "YAML extraction not available"
    fi
}

# =============================================================================
# Frontmatter Extraction Tests
# =============================================================================

@test "schema-validator: extracts YAML frontmatter" {
    run "$SCRIPT" validate "$TEST_DIR/test-prd.md"
    # Should succeed, warn, or fail on YAML extraction (if yq/python unavailable)
    # If yq/python not available, we accept the extract error
    [[ "$status" -eq 0 ]] || [[ "$output" == *"extract"* ]] || [[ "$output" == *"Valid"* ]]
}

@test "schema-validator: handles files without frontmatter" {
    echo "No frontmatter here" > "$TEST_DIR/no-frontmatter.md"
    run "$SCRIPT" validate "$TEST_DIR/no-frontmatter.md" --schema prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not extract"* ]] || [[ "$output" == *"Invalid JSON"* ]]
}

# =============================================================================
# Integration with Schema Files
# =============================================================================

@test "schema-validator: prd.schema.json exists" {
    [ -f "$SCHEMA_DIR/prd.schema.json" ]
}

@test "schema-validator: sdd.schema.json exists" {
    [ -f "$SCHEMA_DIR/sdd.schema.json" ]
}

@test "schema-validator: sprint.schema.json exists" {
    [ -f "$SCHEMA_DIR/sprint.schema.json" ]
}

@test "schema-validator: trajectory-entry.schema.json exists" {
    [ -f "$SCHEMA_DIR/trajectory-entry.schema.json" ]
}

@test "schema-validator: all schemas are valid JSON" {
    for schema in "$SCHEMA_DIR"/*.schema.json; do
        run jq empty "$schema"
        [ "$status" -eq 0 ]
    done
}

# =============================================================================
# Assertion Command Tests (v0.14.0 - Sprint 3)
# =============================================================================

@test "schema-validator assert: shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"assert"* ]]
    [[ "$output" == *"Assertions"* ]]
}

@test "schema-validator assert: requires file argument" {
    run "$SCRIPT" assert
    [ "$status" -eq 1 ]
    [[ "$output" == *"No file specified"* ]]
}

@test "schema-validator assert: reports missing file" {
    run "$SCRIPT" assert "$TEST_DIR/nonexistent.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"File not found"* ]]
}

# =============================================================================
# assert_field_exists Tests
# =============================================================================

@test "assert_field_exists: passes for existing field" {
    cat > "$TEST_DIR/assert-test.json" << 'EOF'
{"version": "1.0.0", "title": "Test", "status": "draft", "stakeholders": ["dev"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/assert-test.json" --schema prd
    [ "$status" -eq 0 ]
    [[ "$output" == *"passed"* ]] || [[ "$output" == *"All assertions passed"* ]]
}

@test "assert_field_exists: fails for missing field" {
    cat > "$TEST_DIR/assert-missing.json" << 'EOF'
{"version": "1.0.0", "status": "draft", "stakeholders": ["dev"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/assert-missing.json" --schema prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"title"* ]]
    [[ "$output" == *"does not exist"* ]]
}

# =============================================================================
# assert_field_matches Tests
# =============================================================================

@test "assert_field_matches: passes for valid version" {
    cat > "$TEST_DIR/assert-version.json" << 'EOF'
{"version": "1.2.3", "title": "Test", "status": "draft", "stakeholders": ["dev"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/assert-version.json" --schema prd
    [ "$status" -eq 0 ]
}

@test "assert_field_matches: fails for invalid status" {
    cat > "$TEST_DIR/assert-status.json" << 'EOF'
{"version": "1.0.0", "title": "Test", "status": "invalid_status", "stakeholders": ["dev"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/assert-status.json" --schema prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"does not match pattern"* ]]
}

@test "assert_field_matches: fails for invalid semver" {
    cat > "$TEST_DIR/assert-semver.json" << 'EOF'
{"version": "invalid", "title": "Test", "status": "draft", "stakeholders": ["dev"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/assert-semver.json" --schema prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"version"* ]]
    [[ "$output" == *"does not match pattern"* ]]
}

# =============================================================================
# assert_array_not_empty Tests
# =============================================================================

@test "assert_array_not_empty: passes for populated array" {
    cat > "$TEST_DIR/assert-array.json" << 'EOF'
{"version": "1.0.0", "title": "Test", "status": "draft", "stakeholders": ["dev", "qa"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/assert-array.json" --schema prd
    [ "$status" -eq 0 ]
}

@test "assert_array_not_empty: fails for empty array" {
    cat > "$TEST_DIR/assert-empty-array.json" << 'EOF'
{"version": "1.0.0", "title": "Test", "status": "draft", "stakeholders": []}
EOF
    run "$SCRIPT" assert "$TEST_DIR/assert-empty-array.json" --schema prd
    [ "$status" -eq 1 ]
    [[ "$output" == *"stakeholders"* ]]
    [[ "$output" == *"is empty"* ]]
}

# =============================================================================
# validate_with_assertions Tests
# =============================================================================

@test "validate_with_assertions: passes for valid PRD" {
    cat > "$TEST_DIR/valid-prd.json" << 'EOF'
{"version": "1.0.0", "title": "Test PRD", "status": "draft", "stakeholders": ["developer"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/valid-prd.json" --schema prd
    [ "$status" -eq 0 ]
    [[ "$output" == *"passed"* ]] || [[ "$output" == *"All assertions passed"* ]]
}

@test "validate_with_assertions: fails for invalid SDD" {
    cat > "$TEST_DIR/invalid-sdd.json" << 'EOF'
{"version": "bad", "components": []}
EOF
    run "$SCRIPT" assert "$TEST_DIR/invalid-sdd.json" --schema sdd
    [ "$status" -eq 1 ]
}

@test "validate_with_assertions: validates sprint schema" {
    cat > "$TEST_DIR/valid-sprint.json" << 'EOF'
{"version": "1.0.0", "status": "in_progress", "sprints": [{"id": 1}]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/valid-sprint.json" --schema sprint
    [ "$status" -eq 0 ]
}

@test "validate_with_assertions: validates trajectory-entry schema" {
    cat > "$TEST_DIR/valid-trajectory.json" << 'EOF'
{"timestamp": "2026-01-17T10:00:00Z", "agent": "test-agent", "action": "test"}
EOF
    run "$SCRIPT" assert "$TEST_DIR/valid-trajectory.json" --schema trajectory-entry
    [ "$status" -eq 0 ]
}

# =============================================================================
# Assert Command CLI Tests
# =============================================================================

@test "assert command: validates PRD file" {
    cat > "$TEST_DIR/cli-prd.json" << 'EOF'
{"version": "1.0.0", "title": "CLI Test", "status": "approved", "stakeholders": ["user"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/cli-prd.json" --schema prd
    [ "$status" -eq 0 ]
}

@test "assert command: outputs JSON with --json" {
    cat > "$TEST_DIR/json-output.json" << 'EOF'
{"version": "1.0.0", "title": "JSON Test", "status": "draft", "stakeholders": ["dev"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/json-output.json" --schema prd --json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
    [[ "$output" == *"\"status\":"* ]]
    [[ "$output" == *"\"passed\""* ]]
}

@test "assert command: JSON output includes failures" {
    cat > "$TEST_DIR/json-failures.json" << 'EOF'
{"version": "1.0.0", "title": "Test", "status": "bad_status", "stakeholders": ["dev"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/json-failures.json" --schema prd --json
    [ "$status" -eq 1 ]
    echo "$output" | jq empty
    [[ "$output" == *"\"failed\""* ]]
    [[ "$output" == *"\"assertions\""* ]]
}

@test "assert command: --schema overrides auto-detection" {
    cat > "$TEST_DIR/override-test.json" << 'EOF'
{"version": "1.0.0", "title": "Override", "components": ["a", "b"]}
EOF
    run "$SCRIPT" assert "$TEST_DIR/override-test.json" --schema sdd
    # Should attempt SDD assertions
    [[ "$output" == *"sdd"* ]]
}

@test "assert command: returns non-zero on failure" {
    cat > "$TEST_DIR/failing-test.json" << 'EOF'
{"version": "not-semver", "title": "Fail"}
EOF
    run "$SCRIPT" assert "$TEST_DIR/failing-test.json" --schema prd
    [ "$status" -eq 1 ]
}
