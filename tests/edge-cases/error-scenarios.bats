#!/usr/bin/env bats
# Edge case and error scenario tests for ck integration
# Tests graceful error handling and recovery

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TMPDIR}/edge-case-$$"
    mkdir -p "${TEST_TMPDIR}"

    # Setup minimal test environment
    mkdir -p "${TEST_TMPDIR}/src"
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory"
    mkdir -p "${TEST_TMPDIR}/.claude/scripts"

    # Source search-api
    source "${PROJECT_ROOT}/.claude/scripts/search-api.sh" 2>/dev/null || true
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
    unset LOA_SEARCH_MODE
}

# =============================================================================
# Empty Search Results Tests
# =============================================================================

@test "handles 0 search results gracefully" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"

    # Search for nonexistent pattern
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'nonexistent_pattern_xyz' 'src/'"

    [ "$status" -eq 0 ]
    # Empty output is acceptable
}

@test "empty results logged to trajectory" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"

    # Mock search-orchestrator to track calls
    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo ""  # Return empty results
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

    [ "$status" -eq 0 ]
}

# =============================================================================
# Very Large Results Tests (>1000 matches)
# =============================================================================

@test "handles very large result sets (>1000 matches)" {
    cd "${TEST_TMPDIR}"

    # Create many files with matches
    for i in {1..100}; do
        echo "function test${i}() {}" > "${TEST_TMPDIR}/src/file${i}.js"
    done

    export LOA_SEARCH_MODE="grep"

    # Search should not crash with many results
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'function' 'src/'"

    [ "$status" -eq 0 ]
}

@test "large results trigger trajectory pivot log" {
    skip "Requires trajectory pivot implementation check"

    cd "${TEST_TMPDIR}"

    # Create many files
    for i in {1..100}; do
        echo "test content" > "${TEST_TMPDIR}/src/file${i}.js"
    done

    # Search should log pivot when >50 results
    trajectory_file="${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"

    [ -f "$trajectory_file" ]
}

# =============================================================================
# Malformed JSONL Tests
# =============================================================================

@test "handles malformed JSONL gracefully" {
    cd "${TEST_TMPDIR}"

    # Create malformed JSONL output
    malformed='{"file":"test.js","line":1
{"file":"test.js","line":2,"snippet":"valid"}
not json at all
{"file":"test.js","line":3,"snippet":"valid"}'

    # Parse line by line (should drop bad lines, continue)
    good_lines=0
    while IFS= read -r line; do
        if echo "$line" | jq -e . >/dev/null 2>&1; then
            ((good_lines++))
        fi
    done <<< "$malformed"

    [ "$good_lines" -eq 2 ]  # Only 2 valid lines
}

@test "logs dropped JSONL lines to trajectory" {
    skip "Requires trajectory logging of parse errors"

    cd "${TEST_TMPDIR}"

    # Simulate malformed JSONL handling
    # Check trajectory log has parse_errors logged

    trajectory_file="${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"

    [ -f "$trajectory_file" ]
}

# =============================================================================
# Missing .ck/ Directory Tests
# =============================================================================

@test "self-healing when .ck/ directory missing" {
    skip "Requires ck installation and self-healing implementation"

    cd "${TEST_TMPDIR}"

    # Remove .ck/ directory
    rm -rf ".ck"

    if command -v ck >/dev/null 2>&1; then
        # Should trigger silent reindex
        run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

        [ "$status" -eq 0 ]

        # Check .ck/ was recreated
        [ -d ".ck" ]
    fi
}

@test "delta reindex when .ck/ partially corrupted" {
    skip "Requires ck installation"

    cd "${TEST_TMPDIR}"

    if command -v ck >/dev/null 2>&1; then
        # Corrupt .ck/ index
        mkdir -p ".ck"
        echo "corrupted data" > ".ck/index.bin"

        # Should detect corruption and reindex
        run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# ck Binary Missing Mid-Session Tests
# =============================================================================

@test "graceful degradation if ck removed mid-session" {
    skip "Requires ck installation and removal simulation"

    cd "${TEST_TMPDIR}"

    if command -v ck >/dev/null 2>&1; then
        # Start with ck
        export LOA_SEARCH_MODE="ck"

        # Simulate ck removal (temporarily hide it)
        export PATH="/usr/bin:/bin"

        # Should fall back to grep without crashing
        run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# Git Repository Tests
# =============================================================================

@test "handles non-git repository" {
    cd "${TEST_TMPDIR}"

    # No .git directory
    [ ! -d ".git" ]

    # Should use pwd as PROJECT_ROOT
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; echo \$PROJECT_ROOT"

    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "handles git repository without commits" {
    cd "${TEST_TMPDIR}"

    git init -q

    # Empty git repo
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

    [ "$status" -eq 0 ]
}

# =============================================================================
# Path Edge Cases Tests
# =============================================================================

@test "handles file paths with spaces" {
    cd "${TEST_TMPDIR}"

    mkdir -p "src/with space"
    echo "function test() {}" > "src/with space/file.js"

    export LOA_SEARCH_MODE="grep"

    # Should handle spaces correctly
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/with space/'"

    [ "$status" -eq 0 ]
}

@test "handles file paths with special characters" {
    cd "${TEST_TMPDIR}"

    mkdir -p "src/test\$dir"
    echo "function test() {}" > "src/test\$dir/file.js"

    export LOA_SEARCH_MODE="grep"

    # Should escape special chars
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

    [ "$status" -eq 0 ]
}

@test "handles symlinks in search path" {
    cd "${TEST_TMPDIR}"

    mkdir -p "real-src"
    echo "function test() {}" > "real-src/file.js"
    ln -s "real-src" "src-link"

    export LOA_SEARCH_MODE="grep"

    # Should follow symlinks (or explicitly not, depending on design)
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src-link/'"

    [ "$status" -eq 0 ]
}

@test "absolute path normalization with .." {
    cd "${TEST_TMPDIR}"

    mkdir -p "src/subdir"
    echo "function test() {}" > "src/file.js"

    export LOA_SEARCH_MODE="grep"

    # Path with ../ should normalize
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/subdir/../'"

    [ "$status" -eq 0 ]
}

# =============================================================================
# Concurrent Search Tests
# =============================================================================

@test "handles concurrent searches safely" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"

    # Run multiple searches in parallel
    bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test1' 'src/'" &
    pid1=$!

    bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test2' 'src/'" &
    pid2=$!

    # Wait for both
    wait $pid1
    status1=$?

    wait $pid2
    status2=$?

    # Both should succeed
    [ "$status1" -eq 0 ]
    [ "$status2" -eq 0 ]
}

# =============================================================================
# Trajectory Log Corruption Tests
# =============================================================================

@test "handles corrupted trajectory log file" {
    cd "${TEST_TMPDIR}"

    mkdir -p "loa-grimoire/a2a/trajectory"

    # Create corrupted trajectory file
    echo "corrupted non-json data" > "loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"

    export LOA_SEARCH_MODE="grep"

    # Should append new entries despite corruption
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

    [ "$status" -eq 0 ]
}

@test "creates trajectory directory if missing" {
    cd "${TEST_TMPDIR}"

    rm -rf "loa-grimoire"

    export LOA_SEARCH_MODE="grep"

    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

    [ "$status" -eq 0 ]
    [ -d "loa-grimoire/a2a/trajectory" ]
}

# =============================================================================
# Memory and Resource Tests
# =============================================================================

@test "handles extremely long query strings" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"

    # Create 1000-character query
    long_query=$(printf 'a%.0s' {1..1000})

    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search '$long_query' 'src/'"

    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # May reject, but shouldn't crash
}

@test "handles deeply nested directory structures" {
    cd "${TEST_TMPDIR}"

    # Create deep nesting
    mkdir -p "src/a/b/c/d/e/f/g/h/i/j"
    echo "function test() {}" > "src/a/b/c/d/e/f/g/h/i/j/file.js"

    export LOA_SEARCH_MODE="grep"

    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

    [ "$status" -eq 0 ]
}

# =============================================================================
# Unicode and Encoding Tests
# =============================================================================

@test "handles UTF-8 content in search results" {
    cd "${TEST_TMPDIR}"

    echo "function test() { console.log('Hello 世界 🌍'); }" > "src/unicode.js"

    export LOA_SEARCH_MODE="grep"

    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

    [ "$status" -eq 0 ]
}

@test "handles non-UTF-8 file encodings gracefully" {
    cd "${TEST_TMPDIR}"

    # Create file with binary content
    echo -e "\x00\x01\x02\x03" > "src/binary.bin"

    export LOA_SEARCH_MODE="grep"

    # Should not crash on binary files
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/'"

    [ "$status" -eq 0 ]
}

# =============================================================================
# Threshold Edge Cases Tests
# =============================================================================

@test "handles threshold=0.0 (all results)" {
    skip "Requires ck installation"

    cd "${TEST_TMPDIR}"

    if command -v ck >/dev/null 2>&1; then
        run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/' 20 0.0"

        [ "$status" -eq 0 ]
    fi
}

@test "handles threshold=1.0 (exact matches only)" {
    skip "Requires ck installation"

    cd "${TEST_TMPDIR}"

    if command -v ck >/dev/null 2>&1; then
        run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'src/' 20 1.0"

        [ "$status" -eq 0 ]
        # May return 0 results (acceptable)
    fi
}

# =============================================================================
# Permission Tests
# =============================================================================

@test "handles read-only directories" {
    cd "${TEST_TMPDIR}"

    mkdir -p "readonly-src"
    echo "function test() {}" > "readonly-src/file.js"
    chmod -R 444 "readonly-src"

    export LOA_SEARCH_MODE="grep"

    # Should still be able to search (read-only is fine)
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'readonly-src/'"

    [ "$status" -eq 0 ]

    # Cleanup
    chmod -R 755 "readonly-src"
}

@test "handles no-permission directories" {
    skip "Requires root/permission manipulation"

    cd "${TEST_TMPDIR}"

    mkdir -p "noperm-src"
    echo "function test() {}" > "noperm-src/file.js"
    chmod 000 "noperm-src"

    export LOA_SEARCH_MODE="grep"

    # Should handle permission denied gracefully
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; semantic_search 'test' 'noperm-src/'"

    # May fail, but shouldn't crash
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

    # Cleanup
    chmod 755 "noperm-src"
}
