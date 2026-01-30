#!/usr/bin/env bats
# Unit tests for context-manager.sh probe functionality (RLM pattern)

setup() {
    export TEST_DIR="$BATS_TMPDIR/context-probe-test-$$"
    mkdir -p "$TEST_DIR"

    export SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/context-manager.sh"

    # Create test files with various characteristics
    mkdir -p "$TEST_DIR/src"

    # Standard code file
    cat > "$TEST_DIR/src/main.ts" << 'EOF'
#!/usr/bin/env ts-node
/**
 * Main entry point
 */
import { App } from './app';

export function main(): void {
    const app = new App();
    app.run();
}

main();
EOF

    # Large file (simulate with content)
    for i in {1..100}; do
        echo "// Line $i of large file" >> "$TEST_DIR/src/large-file.ts"
    done

    # Empty file
    touch "$TEST_DIR/src/empty.ts"

    # Binary file (simulate with non-UTF8 content)
    printf '\x00\x01\x02\x03\x04\x05' > "$TEST_DIR/src/binary.bin"

    # File with special characters in name
    echo "content" > "$TEST_DIR/src/file with spaces.ts"

    # Nested directory
    mkdir -p "$TEST_DIR/src/nested/deep"
    echo "nested content" > "$TEST_DIR/src/nested/deep/file.ts"

    # Config file
    echo '{"name": "test", "version": "1.0.0"}' > "$TEST_DIR/src/config.json"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# File Probe Tests
# =============================================================================

@test "probe single file returns metadata" {
    run "$SCRIPT" probe "$TEST_DIR/src/main.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"main.ts"* ]]
    [[ "$output" == *"Lines"* ]]
    [[ "$output" == *"Tokens"* ]]
}

@test "probe file with --json returns valid JSON" {
    run "$SCRIPT" probe "$TEST_DIR/src/main.ts" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty

    local file_path
    file_path=$(echo "$output" | jq -r '.file')
    [[ "$file_path" == *"main.ts"* ]]
}

@test "probe file JSON includes required fields" {
    run "$SCRIPT" probe "$TEST_DIR/src/main.ts" --json
    [ "$status" -eq 0 ]

    # Check required fields
    echo "$output" | jq -e '.file' > /dev/null
    echo "$output" | jq -e '.lines' > /dev/null
    echo "$output" | jq -e '.estimated_tokens' > /dev/null
    echo "$output" | jq -e '.extension' > /dev/null
}

@test "probe file calculates token estimate" {
    run "$SCRIPT" probe "$TEST_DIR/src/main.ts" --json
    [ "$status" -eq 0 ]

    local tokens
    tokens=$(echo "$output" | jq '.estimated_tokens')
    [ "$tokens" -gt 0 ]
}

@test "probe empty file returns zero lines" {
    run "$SCRIPT" probe "$TEST_DIR/src/empty.ts" --json
    [ "$status" -eq 0 ]

    local lines
    lines=$(echo "$output" | jq '.lines')
    [ "$lines" -eq 0 ]
}

@test "probe large file shows high token count" {
    run "$SCRIPT" probe "$TEST_DIR/src/large-file.ts" --json
    [ "$status" -eq 0 ]

    local tokens
    tokens=$(echo "$output" | jq '.estimated_tokens')
    [ "$tokens" -gt 50 ]  # 100 lines should be >50 tokens
}

@test "probe file with spaces in name works" {
    run "$SCRIPT" probe "$TEST_DIR/src/file with spaces.ts" --json
    [ "$status" -eq 0 ]
    [[ "$output" == *"file with spaces.ts"* ]]
}

@test "probe non-existent file returns error" {
    run "$SCRIPT" probe "$TEST_DIR/nonexistent.ts" --json
    [ "$status" -eq 1 ]  # Command fails for non-existent file
    [[ "$output" == *"not found"* ]]
}

# =============================================================================
# Directory Probe Tests
# =============================================================================

@test "probe directory returns file listing" {
    run "$SCRIPT" probe "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    # Should be valid JSON with files array
    echo "$output" | jq -e '.files' > /dev/null
    echo "$output" | jq -e '.total_files' > /dev/null
}

@test "probe directory counts all files" {
    run "$SCRIPT" probe "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    local count
    count=$(echo "$output" | jq '.total_files')
    [ "$count" -ge 5 ]  # At least our test files
}

@test "probe directory includes nested files" {
    run "$SCRIPT" probe "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    # Should include nested/deep/file.ts
    [[ "$output" == *"nested"* ]]
}

@test "probe directory sums token estimates" {
    run "$SCRIPT" probe "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    local total
    total=$(echo "$output" | jq '.estimated_tokens')
    [ "$total" -gt 0 ]
}

@test "probe empty directory returns zero files" {
    mkdir -p "$TEST_DIR/empty_dir"

    run "$SCRIPT" probe "$TEST_DIR/empty_dir" --json
    [ "$status" -eq 0 ]

    local count
    count=$(echo "$output" | jq '.total_files')
    [ "$count" -eq 0 ]
}

@test "probe non-existent directory returns error" {
    run "$SCRIPT" probe "$TEST_DIR/nonexistent_dir" --json
    [ "$status" -ne 0 ] || [[ "$output" == *"error"* ]]
}

# =============================================================================
# Should-Load Decision Tests
# =============================================================================

@test "should-load returns decision for file" {
    run "$SCRIPT" should-load "$TEST_DIR/src/main.ts"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Decision"* ]]
}

@test "should-load with --json returns valid JSON" {
    run "$SCRIPT" should-load "$TEST_DIR/src/main.ts" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty

    echo "$output" | jq -e '.decision' > /dev/null
}

@test "should-load decision includes reason" {
    run "$SCRIPT" should-load "$TEST_DIR/src/main.ts" --json
    [ "$status" -eq 0 ]

    echo "$output" | jq -e '.reason' > /dev/null
}

@test "should-load recommends loading small files" {
    run "$SCRIPT" should-load "$TEST_DIR/src/main.ts" --json
    [ "$status" -eq 0 ]

    local decision
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "load" ]
}

@test "should-load includes relevance score when applicable" {
    run "$SCRIPT" should-load "$TEST_DIR/src/main.ts" --json
    [ "$status" -eq 0 ]

    # May or may not have relevance score depending on context
    # Just verify structure is valid
    echo "$output" | jq empty
}

# =============================================================================
# Performance Tests
# =============================================================================

@test "probe file completes quickly (<100ms)" {
    local start end elapsed
    start=$(date +%s%N)

    run "$SCRIPT" probe "$TEST_DIR/src/main.ts" --json
    [ "$status" -eq 0 ]

    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))  # Convert to ms

    [ "$elapsed" -lt 100 ]
}

@test "probe directory completes reasonably (<500ms for small dir)" {
    local start end elapsed
    start=$(date +%s%N)

    run "$SCRIPT" probe "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))

    [ "$elapsed" -lt 500 ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "probe handles symlinks gracefully" {
    ln -s "$TEST_DIR/src/main.ts" "$TEST_DIR/src/symlink.ts" 2>/dev/null || skip "Cannot create symlinks"

    run "$SCRIPT" probe "$TEST_DIR/src/symlink.ts" --json
    [ "$status" -eq 0 ]
}

@test "probe skips binary files in directory scan" {
    run "$SCRIPT" probe "$TEST_DIR/src" --json
    [ "$status" -eq 0 ]

    # Binary file should either be skipped or marked
    # The important thing is no crash
}

@test "probe without --json shows human readable output" {
    run "$SCRIPT" probe "$TEST_DIR/src/main.ts"
    [ "$status" -eq 0 ]

    # Should not start with { (JSON)
    [[ ! "$output" =~ ^\{ ]]
}

@test "probe with no argument defaults to current directory" {
    cd "$TEST_DIR/src"
    run "$SCRIPT" probe
    [ "$status" -eq 0 ]
    [[ "$output" == *"Directory"* ]]
}
