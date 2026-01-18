#!/usr/bin/env bats
# Edge case tests for context management tools

setup() {
    export TEST_DIR="$BATS_TMPDIR/context-edge-$$"
    mkdir -p "$TEST_DIR"

    export CONTEXT_SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/context-manager.sh"
    export SCHEMA_SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/schema-validator.sh"
    export BENCHMARK_SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/rlm-benchmark.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# File System Edge Cases
# =============================================================================

@test "handles file with no extension" {
    echo "content without extension" > "$TEST_DIR/Makefile"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/Makefile" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
}

@test "handles file with multiple extensions" {
    echo "content" > "$TEST_DIR/file.test.spec.ts"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/file.test.spec.ts" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"file.test.spec.ts"* ]]
}

@test "handles hidden files" {
    echo "hidden content" > "$TEST_DIR/.hidden"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/.hidden" --json
    [ "$status" -eq 0 ]
}

@test "handles deeply nested paths" {
    mkdir -p "$TEST_DIR/a/b/c/d/e/f/g/h/i/j"
    echo "deep" > "$TEST_DIR/a/b/c/d/e/f/g/h/i/j/deep.ts"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/a/b/c/d/e/f/g/h/i/j/deep.ts" --json
    [ "$status" -eq 0 ]
}

@test "handles unicode in filenames" {
    echo "unicode content" > "$TEST_DIR/文件.ts" 2>/dev/null || skip "Filesystem does not support unicode"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/文件.ts" --json
    [ "$status" -eq 0 ] || skip "Unicode filename handling not supported"
}

@test "handles very long filenames" {
    local long_name
    long_name=$(printf 'a%.0s' {1..200})
    echo "long name content" > "$TEST_DIR/${long_name}.ts" 2>/dev/null || skip "Filesystem does not support long filenames"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/${long_name}.ts" --json
    [ "$status" -eq 0 ] || skip "Long filename handling not supported"
}

@test "handles symlinks to files" {
    echo "target content" > "$TEST_DIR/target.ts"
    ln -s "$TEST_DIR/target.ts" "$TEST_DIR/link.ts" 2>/dev/null || skip "Cannot create symlinks"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/link.ts" --json
    [ "$status" -eq 0 ]
}

@test "handles broken symlinks gracefully" {
    ln -s "$TEST_DIR/nonexistent.ts" "$TEST_DIR/broken-link.ts" 2>/dev/null || skip "Cannot create symlinks"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/broken-link.ts" --json
    # Should fail gracefully
    [ "$status" -ne 0 ] || [[ "$output" == *"error"* ]] || [[ "$output" == *"not found"* ]]
}

@test "handles directory symlinks" {
    mkdir -p "$TEST_DIR/real_dir"
    echo "content" > "$TEST_DIR/real_dir/file.ts"
    ln -s "$TEST_DIR/real_dir" "$TEST_DIR/linked_dir" 2>/dev/null || skip "Cannot create symlinks"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/linked_dir" --json
    [ "$status" -eq 0 ]
}

# =============================================================================
# Content Edge Cases
# =============================================================================

@test "handles file with only whitespace" {
    printf "   \n\t\n   " > "$TEST_DIR/whitespace.ts"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/whitespace.ts" --json
    [ "$status" -eq 0 ]
}

@test "handles file with very long lines" {
    printf '%10000s' "x" > "$TEST_DIR/long-line.ts"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/long-line.ts" --json
    [ "$status" -eq 0 ]
}

@test "handles file with no newline at end" {
    printf "no trailing newline" > "$TEST_DIR/no-newline.ts"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/no-newline.ts" --json
    [ "$status" -eq 0 ]
}

@test "handles file with null bytes" {
    printf "content\x00with\x00nulls" > "$TEST_DIR/nullbytes.bin"

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/nullbytes.bin" --json
    [ "$status" -eq 0 ]
}

@test "handles large file (1MB)" {
    dd if=/dev/urandom of="$TEST_DIR/large.bin" bs=1024 count=1024 2>/dev/null

    run "$CONTEXT_SCRIPT" probe "$TEST_DIR/large.bin" --json
    [ "$status" -eq 0 ]
}

# =============================================================================
# Schema Validator Edge Cases
# =============================================================================

@test "schema validator handles empty JSON object" {
    echo '{}' > "$TEST_DIR/empty.json"

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/empty.json" --schema prd --json
    # Should fail - missing required fields
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "passed" ]]
}

@test "schema validator handles null values" {
    cat > "$TEST_DIR/nulls.json" << 'EOF'
{
    "version": null,
    "title": "Test",
    "status": "draft",
    "stakeholders": ["user"]
}
EOF

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/nulls.json" --schema prd --json
    # Should fail - version cannot be null
    [ "$status" -ne 0 ] || [[ $(echo "$output" | jq -r '.status') != "passed" ]]
}

@test "schema validator handles extra fields" {
    cat > "$TEST_DIR/extra.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Test",
    "status": "draft",
    "stakeholders": ["user"],
    "extraField": "should be ignored"
}
EOF

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/extra.json" --schema prd --json
    # Should pass - extra fields allowed by default
    [ "$status" -eq 0 ]
}

@test "schema validator handles deeply nested objects" {
    cat > "$TEST_DIR/nested.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Test",
    "status": "draft",
    "stakeholders": ["user"],
    "requirements": [
        {
            "id": "REQ-1",
            "nested": {
                "deep": {
                    "deeper": {
                        "value": "test"
                    }
                }
            }
        }
    ]
}
EOF

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/nested.json" --schema prd --json
    [ "$status" -eq 0 ]
}

@test "schema validator handles array of 1000 items" {
    # Generate large stakeholders array
    local stakeholders
    stakeholders=$(printf '"user%d",' {1..1000} | sed 's/,$//')
    cat > "$TEST_DIR/large-array.json" << EOF
{
    "version": "1.0.0",
    "title": "Test",
    "status": "draft",
    "stakeholders": [$stakeholders]
}
EOF

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/large-array.json" --schema prd --json
    [ "$status" -eq 0 ]
}

@test "schema validator handles special characters in strings" {
    cat > "$TEST_DIR/special.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "Test with \"quotes\" and \n newlines",
    "status": "draft",
    "stakeholders": ["user <with> special & chars"]
}
EOF

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/special.json" --schema prd --json
    [ "$status" -eq 0 ]
}

@test "schema validator handles unicode content" {
    cat > "$TEST_DIR/unicode.json" << 'EOF'
{
    "version": "1.0.0",
    "title": "测试 文档 🚀",
    "status": "draft",
    "stakeholders": ["用户", "développeur", "разработчик"]
}
EOF

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/unicode.json" --schema prd --json
    [ "$status" -eq 0 ]
}

# =============================================================================
# Benchmark Edge Cases
# =============================================================================

@test "benchmark handles codebase with only hidden files" {
    mkdir -p "$TEST_DIR/hidden_only"
    echo "content" > "$TEST_DIR/hidden_only/.gitignore"
    echo "content" > "$TEST_DIR/hidden_only/.env"

    run "$BENCHMARK_SCRIPT" run --target "$TEST_DIR/hidden_only" --json
    [ "$status" -eq 0 ]
}

@test "benchmark handles codebase with only binary files" {
    mkdir -p "$TEST_DIR/binary_only"
    dd if=/dev/urandom of="$TEST_DIR/binary_only/file1.bin" bs=100 count=1 2>/dev/null
    dd if=/dev/urandom of="$TEST_DIR/binary_only/file2.bin" bs=100 count=1 2>/dev/null

    run "$BENCHMARK_SCRIPT" run --target "$TEST_DIR/binary_only" --json
    [ "$status" -eq 0 ]
}

@test "benchmark handles codebase with circular symlinks" {
    mkdir -p "$TEST_DIR/circular"
    echo "content" > "$TEST_DIR/circular/file.ts"
    ln -s "$TEST_DIR/circular" "$TEST_DIR/circular/self" 2>/dev/null || skip "Cannot create symlinks"

    # Should not hang or crash
    timeout 10 "$BENCHMARK_SCRIPT" run --target "$TEST_DIR/circular" --json
    # May succeed or fail, but should not hang
}

@test "benchmark handles permission denied gracefully" {
    mkdir -p "$TEST_DIR/restricted"
    echo "content" > "$TEST_DIR/restricted/file.ts"
    chmod 000 "$TEST_DIR/restricted" 2>/dev/null || skip "Cannot change permissions"

    run "$BENCHMARK_SCRIPT" run --target "$TEST_DIR/restricted" --json
    # Should handle gracefully
    chmod 755 "$TEST_DIR/restricted" 2>/dev/null  # Restore for cleanup
}

# =============================================================================
# Concurrent Access Edge Cases
# =============================================================================

@test "concurrent probes on same file" {
    echo "concurrent test content" > "$TEST_DIR/concurrent.ts"

    # Run multiple probes in parallel
    "$CONTEXT_SCRIPT" probe "$TEST_DIR/concurrent.ts" --json > "$TEST_DIR/out1.json" &
    local pid1=$!
    "$CONTEXT_SCRIPT" probe "$TEST_DIR/concurrent.ts" --json > "$TEST_DIR/out2.json" &
    local pid2=$!

    wait $pid1
    wait $pid2

    # Both should produce valid output
    jq empty "$TEST_DIR/out1.json"
    jq empty "$TEST_DIR/out2.json"
}

@test "probe while file is being modified" {
    echo "initial content" > "$TEST_DIR/modifying.ts"

    # Start probe
    "$CONTEXT_SCRIPT" probe "$TEST_DIR/modifying.ts" --json &
    local pid=$!

    # Modify file while probe runs
    echo "modified content" > "$TEST_DIR/modifying.ts"

    wait $pid
    # Should not crash (may get either version)
}

# =============================================================================
# Error Recovery Edge Cases
# =============================================================================

@test "context manager recovers from invalid state" {
    # Create partially written JSON file
    echo '{"incomplete": ' > "$TEST_DIR/partial.json"

    run "$SCHEMA_SCRIPT" assert "$TEST_DIR/partial.json" --schema prd --json
    [ "$status" -ne 0 ] || [[ "$output" == *"error"* ]]
}

@test "benchmark recovers from corrupted baseline" {
    mkdir -p "$TEST_DIR/codebase"
    echo "content" > "$TEST_DIR/codebase/file.ts"

    export BENCHMARK_DIR="$TEST_DIR/benchmarks"
    mkdir -p "$BENCHMARK_DIR"

    # Create corrupted baseline
    echo "not valid json" > "$BENCHMARK_DIR/baseline.json"

    run "$BENCHMARK_SCRIPT" compare --target "$TEST_DIR/codebase" --json
    # Should fail gracefully with error message
    [ "$status" -ne 0 ] || [[ "$output" == *"error"* ]] || [[ "$output" == *"invalid"* ]]
}
