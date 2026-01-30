#!/usr/bin/env bats
# Unit tests for rlm-benchmark.sh

setup() {
    # Create test directory
    export TEST_DIR="$BATS_TMPDIR/rlm-benchmark-test-$$"
    mkdir -p "$TEST_DIR"

    # Set script path
    export SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/rlm-benchmark.sh"

    # Create test codebase structure with enough content for RLM to show benefit
    mkdir -p "$TEST_DIR/src"

    # Create larger files so RLM probe overhead is smaller than savings
    # RLM needs ~500+ tokens to show benefit (probe overhead is ~50 tokens/file)
    for i in {1..10}; do
        cat > "$TEST_DIR/src/module_$i.sh" << 'SCRIPT'
#!/bin/bash
# Module implementation file
# This file contains various utility functions

function do_something() {
    local input="$1"
    local result=""

    # Process the input
    for item in $input; do
        result="${result}${item}"
    done

    echo "$result"
}

function another_function() {
    local data="$1"
    echo "Processing: $data"
}

# More content to ensure sufficient token count
SCRIPT
    done

    # Create a Python file
    cat > "$TEST_DIR/src/main.py" << 'PYTHON'
#!/usr/bin/env python3
"""Main module with various functions."""

def process_data(data):
    """Process input data and return result."""
    result = []
    for item in data:
        result.append(item.strip())
    return result

def main():
    """Entry point."""
    data = ["hello", "world"]
    print(process_data(data))

if __name__ == "__main__":
    main()
PYTHON

    # Create a config file
    echo '{"name": "test", "version": "1.0.0", "settings": {"debug": true}}' > "$TEST_DIR/src/config.json"

    # Override benchmark directory for tests
    export BENCHMARK_DIR="$TEST_DIR/benchmarks"
    export BASELINE_FILE="$BENCHMARK_DIR/baseline.json"
    mkdir -p "$BENCHMARK_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Help and Basic Tests
# =============================================================================

@test "rlm-benchmark.sh --help shows usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"RLM Benchmark"* ]]
    [[ "$output" == *"run"* ]]
    [[ "$output" == *"baseline"* ]]
    [[ "$output" == *"compare"* ]]
}

@test "rlm-benchmark.sh -h shows usage" {
    run "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"RLM Benchmark"* ]]
}

@test "rlm-benchmark.sh with no args shows usage" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "rlm-benchmark.sh unknown command shows error" {
    run "$SCRIPT" invalid_command
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# =============================================================================
# Run Command Tests
# =============================================================================

@test "run command produces comparison data" {
    run "$SCRIPT" run --target "$TEST_DIR/src"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RLM Benchmark Results"* ]]
    [[ "$output" == *"Current Pattern"* ]]
    [[ "$output" == *"RLM Pattern"* ]]
    [[ "$output" == *"Savings"* ]]
}

@test "run command with --json outputs JSON" {
    run "$SCRIPT" run --target "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]
    # Validate JSON structure
    echo "$output" | jq empty
    [[ "$output" == *"current_pattern"* ]]
    [[ "$output" == *"rlm_pattern"* ]]
}

@test "run command JSON includes required fields" {
    run "$SCRIPT" run --target "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    local tokens
    tokens=$(echo "$output" | jq '.current_pattern.tokens')
    [ "$tokens" -gt 0 ]

    local savings
    savings=$(echo "$output" | jq '.rlm_pattern.savings_pct')
    [ -n "$savings" ]
}

@test "run command with --iterations runs multiple times" {
    run "$SCRIPT" run --target "$TEST_DIR/src" --iterations 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Iterations: 2"* ]]
}

@test "run command fails for non-existent directory" {
    run "$SCRIPT" run --target "$TEST_DIR/nonexistent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

# =============================================================================
# Baseline Command Tests
# =============================================================================

@test "baseline command creates baseline.json" {
    run "$SCRIPT" baseline --target "$TEST_DIR/src"
    [ "$status" -eq 0 ]
    [ -f "$BASELINE_FILE" ]
    [[ "$output" == *"Baseline saved"* ]]
}

@test "baseline command fails without --force when exists" {
    # Create initial baseline
    "$SCRIPT" baseline --target "$TEST_DIR/src"
    [ -f "$BASELINE_FILE" ]

    # Try to create again without --force
    run "$SCRIPT" baseline --target "$TEST_DIR/src"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]
}

@test "baseline command with --force overwrites existing" {
    # Create initial baseline
    "$SCRIPT" baseline --target "$TEST_DIR/src"
    local original_time
    original_time=$(jq -r '.timestamp' "$BASELINE_FILE")

    # Wait briefly to ensure different timestamp
    sleep 1

    # Overwrite with --force
    run "$SCRIPT" baseline --target "$TEST_DIR/src" --force
    [ "$status" -eq 0 ]

    local new_time
    new_time=$(jq -r '.timestamp' "$BASELINE_FILE")
    [ "$new_time" != "$original_time" ]
}

# =============================================================================
# Compare Command Tests
# =============================================================================

@test "compare command requires baseline" {
    run "$SCRIPT" compare --target "$TEST_DIR/src"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No baseline"* ]]
}

@test "compare command shows delta from baseline" {
    # Create baseline first
    "$SCRIPT" baseline --target "$TEST_DIR/src"

    run "$SCRIPT" compare --target "$TEST_DIR/src"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Benchmark Comparison"* ]]
    [[ "$output" == *"Baseline"* ]]
    [[ "$output" == *"Current"* ]]
    [[ "$output" == *"Delta"* ]]
}

@test "compare command with --json outputs JSON" {
    "$SCRIPT" baseline --target "$TEST_DIR/src"

    run "$SCRIPT" compare --target "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
    [[ "$output" == *"deltas"* ]]
}

# =============================================================================
# Report Command Tests
# =============================================================================

@test "report command generates markdown file" {
    run "$SCRIPT" report --target "$TEST_DIR/src"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Report generated"* ]]

    # Check file exists
    local report_file
    report_file=$(find "$BENCHMARK_DIR" -name "report-*.md" | head -1)
    [ -f "$report_file" ]
}

@test "report contains expected sections" {
    run "$SCRIPT" report --target "$TEST_DIR/src"
    [ "$status" -eq 0 ]

    local report_file
    report_file=$(find "$BENCHMARK_DIR" -name "report-*.md" | head -1)

    # Check report content
    grep -q "Methodology" "$report_file"
    grep -q "Results" "$report_file"
    grep -q "PRD Success Criteria" "$report_file"
}

# =============================================================================
# Benchmark Function Tests
# =============================================================================

@test "benchmark_current_pattern returns metrics for codebase" {
    run "$SCRIPT" run --target "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    local files
    files=$(echo "$output" | jq '.current_pattern.files')
    [ "$files" -ge 10 ]  # We created 10+ test files
}

@test "benchmark_rlm_pattern shows token reduction" {
    run "$SCRIPT" run --target "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    local current_tokens rlm_tokens
    current_tokens=$(echo "$output" | jq '.current_pattern.tokens')
    rlm_tokens=$(echo "$output" | jq '.rlm_pattern.tokens')

    # RLM should use fewer tokens
    [ "$rlm_tokens" -lt "$current_tokens" ]
}

@test "probe overhead is included in RLM metrics" {
    run "$SCRIPT" run --target "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    local probe_tokens
    probe_tokens=$(echo "$output" | jq '.rlm_pattern.probe_overhead.tokens')
    [ "$probe_tokens" -gt 0 ]
}

# =============================================================================
# History Command Tests
# =============================================================================

@test "history command shows no history initially" {
    run "$SCRIPT" history
    [ "$status" -eq 0 ]
    [[ "$output" == *"No benchmark history"* ]]
}
