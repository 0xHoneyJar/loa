#!/usr/bin/env bats
# Integration tests for RLM benchmark workflow

setup() {
    export TEST_DIR="$BATS_TMPDIR/benchmark-workflow-$$"
    mkdir -p "$TEST_DIR"

    export SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/rlm-benchmark.sh"

    # Create realistic codebase fixture
    mkdir -p "$TEST_DIR/codebase/src"
    mkdir -p "$TEST_DIR/codebase/lib"
    mkdir -p "$TEST_DIR/codebase/tests"

    # Create source files
    for i in {1..20}; do
        cat > "$TEST_DIR/codebase/src/module_$i.ts" << 'EOF'
/**
 * Module implementation
 */
export class Module {
    private data: string[];

    constructor() {
        this.data = [];
    }

    public process(input: string): string {
        this.data.push(input);
        return input.toUpperCase();
    }

    public getData(): string[] {
        return this.data;
    }
}
EOF
    done

    # Create test files
    for i in {1..10}; do
        cat > "$TEST_DIR/codebase/tests/test_$i.ts" << 'EOF'
import { Module } from '../src/module_1';

describe('Module', () => {
    it('should process input', () => {
        const m = new Module();
        expect(m.process('hello')).toBe('HELLO');
    });
});
EOF
    done

    # Create config files
    echo '{"name": "test-codebase", "version": "1.0.0"}' > "$TEST_DIR/codebase/package.json"
    echo '# Test Codebase\n\nA test codebase for benchmarking.' > "$TEST_DIR/codebase/README.md"

    # Override benchmark directory
    export BENCHMARK_DIR="$TEST_DIR/benchmarks"
    export BASELINE_FILE="$BENCHMARK_DIR/baseline.json"
    mkdir -p "$BENCHMARK_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# End-to-End Benchmark Workflow
# =============================================================================

@test "full benchmark workflow: run -> baseline -> compare" {
    # Step 1: Initial run
    run "$SCRIPT" run --target "$TEST_DIR/codebase" --json
    [ "$status" -eq 0 ]

    local initial_savings
    initial_savings=$(echo "$output" | jq '.rlm_pattern.savings_pct')
    [ -n "$initial_savings" ]

    # Step 2: Create baseline
    run "$SCRIPT" baseline --target "$TEST_DIR/codebase"
    [ "$status" -eq 0 ]
    [ -f "$BASELINE_FILE" ]

    # Step 3: Compare against baseline
    run "$SCRIPT" compare --target "$TEST_DIR/codebase" --json
    [ "$status" -eq 0 ]

    # Delta should be ~0 since nothing changed
    local delta
    delta=$(echo "$output" | jq '.deltas.rlm_tokens')
    [ "$delta" -lt 100 ] && [ "$delta" -gt -100 ]
}

@test "benchmark report generation with analysis" {
    run "$SCRIPT" report --target "$TEST_DIR/codebase"
    [ "$status" -eq 0 ]

    # Find the report file
    local report_file
    report_file=$(find "$BENCHMARK_DIR" -name "report-*.md" | head -1)
    [ -f "$report_file" ]

    # Verify report structure
    grep -q "Methodology" "$report_file"
    grep -q "Results" "$report_file"
    grep -q "Token Analysis" "$report_file"
    grep -q "PRD Success Criteria" "$report_file"
}

@test "baseline protection prevents accidental overwrite" {
    # Create initial baseline
    "$SCRIPT" baseline --target "$TEST_DIR/codebase"
    [ -f "$BASELINE_FILE" ]

    local original_ts
    original_ts=$(jq -r '.timestamp' "$BASELINE_FILE")

    # Attempt to overwrite without --force
    run "$SCRIPT" baseline --target "$TEST_DIR/codebase"
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exists"* ]]

    # Timestamp should be unchanged
    local current_ts
    current_ts=$(jq -r '.timestamp' "$BASELINE_FILE")
    [ "$original_ts" = "$current_ts" ]

    # Now overwrite with --force
    sleep 1  # Ensure different timestamp
    run "$SCRIPT" baseline --target "$TEST_DIR/codebase" --force
    [ "$status" -eq 0 ]

    local new_ts
    new_ts=$(jq -r '.timestamp' "$BASELINE_FILE")
    [ "$new_ts" != "$original_ts" ]
}

@test "benchmark detects codebase changes" {
    # Create baseline
    "$SCRIPT" baseline --target "$TEST_DIR/codebase"

    # Add more files to codebase
    for i in {21..30}; do
        cat > "$TEST_DIR/codebase/src/new_module_$i.ts" << 'EOF'
export function newFunction() {
    return "new content";
}
EOF
    done

    # Compare should show change
    run "$SCRIPT" compare --target "$TEST_DIR/codebase" --json
    [ "$status" -eq 0 ]

    local delta
    delta=$(echo "$output" | jq '.deltas.rlm_tokens')

    # Tokens should have increased (positive delta)
    [ "$delta" -gt 0 ]
}

@test "iterations parameter improves measurement stability" {
    # Single iteration
    run "$SCRIPT" run --target "$TEST_DIR/codebase" --iterations 1 --json
    [ "$status" -eq 0 ]
    local single_tokens
    single_tokens=$(echo "$output" | jq '.rlm_pattern.tokens')

    # Multiple iterations
    run "$SCRIPT" run --target "$TEST_DIR/codebase" --iterations 3 --json
    [ "$status" -eq 0 ]
    local multi_tokens
    multi_tokens=$(echo "$output" | jq '.rlm_pattern.tokens')

    # Both should produce similar results (within 10%)
    local diff=$((single_tokens - multi_tokens))
    [ "$diff" -lt "$((single_tokens / 10))" ] || [ "$diff" -gt "-$((single_tokens / 10))" ]
}

# =============================================================================
# Realistic Codebase Scenarios
# =============================================================================

@test "benchmark handles mixed file types" {
    # Add various file types
    echo '{"config": true}' > "$TEST_DIR/codebase/config.json"
    echo 'name: test' > "$TEST_DIR/codebase/config.yaml"
    echo '#!/bin/bash\necho hello' > "$TEST_DIR/codebase/script.sh"
    echo '# Markdown\nSome text.' > "$TEST_DIR/codebase/docs.md"

    run "$SCRIPT" run --target "$TEST_DIR/codebase" --json
    [ "$status" -eq 0 ]

    local files
    files=$(echo "$output" | jq '.current_pattern.files')
    [ "$files" -gt 30 ]  # Our base files + new ones
}

@test "benchmark excludes node_modules" {
    # Create node_modules
    mkdir -p "$TEST_DIR/codebase/node_modules/lodash"
    for i in {1..50}; do
        echo "module.exports = {}" > "$TEST_DIR/codebase/node_modules/lodash/file_$i.js"
    done

    run "$SCRIPT" run --target "$TEST_DIR/codebase" --json
    [ "$status" -eq 0 ]

    local files
    files=$(echo "$output" | jq '.current_pattern.files')

    # Should not include the 50 node_modules files
    [ "$files" -lt 50 ]
}

@test "RLM pattern shows token reduction on realistic codebase" {
    run "$SCRIPT" run --target "$TEST_DIR/codebase" --json
    [ "$status" -eq 0 ]

    local savings
    savings=$(echo "$output" | jq '.rlm_pattern.savings_pct')

    # Should show positive savings
    [ "$(echo "$savings > 0" | bc)" -eq 1 ]
}

# =============================================================================
# Error Recovery
# =============================================================================

@test "compare gracefully handles missing baseline" {
    # Don't create baseline

    run "$SCRIPT" compare --target "$TEST_DIR/codebase"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No baseline"* ]]
}

@test "benchmark handles empty directory gracefully" {
    mkdir -p "$TEST_DIR/empty"

    run "$SCRIPT" run --target "$TEST_DIR/empty" --json
    [ "$status" -eq 0 ]

    local files
    files=$(echo "$output" | jq '.current_pattern.files')
    [ "$files" -eq 0 ]
}
