#!/usr/bin/env bats
# Tests for condense.sh - Result condensation engine

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CONDENSE="$PROJECT_ROOT/.claude/scripts/condense.sh"

    # Create temp directory for test files
    TEST_DIR="$(mktemp -d)"
    export FULL_DIR="$TEST_DIR/full"
    mkdir -p "$FULL_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "condense.sh exists and is executable" {
    [[ -x "$CONDENSE" ]]
}

@test "condense.sh shows help with --help" {
    run "$CONDENSE" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Condense"* ]]
}

@test "strategies command lists available strategies" {
    run "$CONDENSE" strategies
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"structured_verdict"* ]]
    [[ "$output" == *"identifiers_only"* ]]
    [[ "$output" == *"summary"* ]]
}

@test "strategies command outputs JSON with --json" {
    run "$CONDENSE" strategies --json
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.strategies' > /dev/null
}

@test "structured_verdict extracts verdict and findings" {
    local input='{
        "verdict": "PASS",
        "severity_counts": {"critical": 0, "high": 1, "medium": 2},
        "findings": [
            {"id": "HIGH-001", "severity": "high", "file": "src/auth.ts", "line": 45, "message": "SQL injection"}
        ]
    }'

    run bash -c "echo '$input' | $CONDENSE condense --strategy structured_verdict --input -"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"verdict": "PASS"'* ]]
    [[ "$output" == *'"severity_counts"'* ]]
    [[ "$output" == *'"top_findings"'* ]]
}

@test "identifiers_only extracts path:line identifiers" {
    local input='{
        "files": [
            {"file": "src/auth.ts", "line": 45},
            {"file": "src/user.ts", "line": 12}
        ]
    }'

    run bash -c "echo '$input' | $CONDENSE condense --strategy identifiers_only --input -"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"identifiers"'* ]]
    [[ "$output" == *"src/auth.ts:45"* ]]
}

@test "summary strategy produces summary output" {
    local input='{
        "verdict": "completed",
        "description": "Security audit completed successfully",
        "findings": [{"id": "1"}, {"id": "2"}]
    }'

    run bash -c "echo '$input' | $CONDENSE condense --strategy summary --input -"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"type": "summary"'* ]]
    [[ "$output" == *'"item_count"'* ]]
}

@test "condense rejects invalid JSON" {
    run bash -c "echo 'not valid json' | $CONDENSE condense --strategy structured_verdict --input -"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Invalid JSON"* ]]
}

@test "condense rejects unknown strategy" {
    run bash -c "echo '{}' | $CONDENSE condense --strategy unknown_strategy --input -"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unknown strategy"* ]]
}

@test "externalize writes full result to file" {
    local input='{"verdict": "PASS", "full_data": "lots of data here"}'

    run bash -c "echo '$input' | $CONDENSE condense --strategy structured_verdict --input - --externalize --output-dir $FULL_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"full_result_path"'* ]]

    # Check file was created
    local files=$(ls "$FULL_DIR"/*.json 2>/dev/null | wc -l)
    [[ "$files" -ge 1 ]]
}

@test "estimate shows token estimates" {
    local input='{
        "verdict": "PASS",
        "findings": [{"id": "1"}, {"id": "2"}],
        "lots_of_data": "this is a lot of additional data that takes up tokens"
    }'

    run bash -c "echo '$input' | $CONDENSE estimate --input - --json"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"original_tokens"'* ]]
    [[ "$output" == *'"condensed"'* ]]
    [[ "$output" == *'"savings"'* ]]
}

@test "condense reads from file" {
    local input_file="$TEST_DIR/input.json"
    echo '{"verdict": "PASS", "findings": []}' > "$input_file"

    run "$CONDENSE" condense --strategy structured_verdict --input "$input_file"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"verdict": "PASS"'* ]]
}

@test "condense writes to output file" {
    local input='{"verdict": "PASS", "findings": []}'
    local output_file="$TEST_DIR/output.json"

    run bash -c "echo '$input' | $CONDENSE condense --strategy structured_verdict --input - --output $output_file"
    [[ "$status" -eq 0 ]]
    [[ -f "$output_file" ]]

    local content=$(cat "$output_file")
    [[ "$content" == *'"verdict": "PASS"'* ]]
}

@test "preserve option keeps additional fields" {
    local input='{
        "verdict": "PASS",
        "custom_field": "important",
        "findings": []
    }'

    run bash -c "echo '$input' | $CONDENSE condense --strategy structured_verdict --input - --preserve custom_field"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"custom_field": "important"'* ]]
}
