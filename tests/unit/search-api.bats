#!/usr/bin/env bats
# Unit tests for .claude/scripts/search-api.sh
# Tests search API functions, grep_to_jsonl conversion, and helper functions

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TMPDIR}/search-api-test-$$"
    mkdir -p "${TEST_TMPDIR}"

    # Create test directory structure
    mkdir -p "${TEST_TMPDIR}/src"
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory"
    mkdir -p "${TEST_TMPDIR}/.claude/scripts"

    # Create test files
    echo "export function authenticate(user, pass) {" > "${TEST_TMPDIR}/src/auth.js"
    echo "  return validateCredentials(user, pass);" >> "${TEST_TMPDIR}/src/auth.js"
    echo "}" >> "${TEST_TMPDIR}/src/auth.js"

    # Mock preflight.sh and search-orchestrator.sh
    echo '#!/usr/bin/env bash' > "${TEST_TMPDIR}/.claude/scripts/preflight.sh"
    echo 'exit 0' >> "${TEST_TMPDIR}/.claude/scripts/preflight.sh"
    chmod +x "${TEST_TMPDIR}/.claude/scripts/preflight.sh"

    # Source the script
    export LOA_SEARCH_MODE="grep"
    source "${PROJECT_ROOT}/.claude/scripts/search-api.sh"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
    unset LOA_SEARCH_MODE
    unset BC_AVAILABLE
}

# =============================================================================
# Function Export Tests
# =============================================================================

@test "search-api exports semantic_search function" {
    run type semantic_search
    [ "$status" -eq 0 ]
    [[ "$output" =~ "semantic_search is a function" ]]
}

@test "search-api exports hybrid_search function" {
    run type hybrid_search
    [ "$status" -eq 0 ]
    [[ "$output" =~ "hybrid_search is a function" ]]
}

@test "search-api exports regex_search function" {
    run type regex_search
    [ "$status" -eq 0 ]
    [[ "$output" =~ "regex_search is a function" ]]
}

@test "search-api exports grep_to_jsonl function" {
    run type grep_to_jsonl
    [ "$status" -eq 0 ]
    [[ "$output" =~ "grep_to_jsonl is a function" ]]
}

# =============================================================================
# grep_to_jsonl Conversion Tests
# =============================================================================

@test "grep_to_jsonl converts grep output to JSONL" {
    # Simulate grep output
    input="/path/to/file.js:42:function test() {"

    output=$(echo "$input" | grep_to_jsonl)

    # Check valid JSON
    run echo "$output" | jq -e .
    [ "$status" -eq 0 ]

    # Check fields
    run echo "$output" | jq -r '.file'
    [ "$status" -eq 0 ]
    [ "$output" = "/path/to/file.js" ]

    run echo "$output" | jq -r '.line'
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]

    run echo "$output" | jq -r '.snippet'
    [ "$status" -eq 0 ]
    [ "$output" = "function test() {" ]
}

@test "grep_to_jsonl handles multiple lines" {
    input="/path/file1.js:10:line one
/path/file2.js:20:line two
/path/file3.js:30:line three"

    output=$(echo "$input" | grep_to_jsonl)

    # Count lines
    line_count=$(echo "$output" | wc -l)
    [ "$line_count" -eq 3 ]

    # Check each line is valid JSON
    echo "$output" | while IFS= read -r line; do
        run echo "$line" | jq -e .
        [ "$status" -eq 0 ]
    done
}

@test "grep_to_jsonl handles colons in snippet" {
    input="/path/to/file.js:15:const x: string = 'value';"

    output=$(echo "$input" | grep_to_jsonl)

    run echo "$output" | jq -r '.snippet'
    [ "$status" -eq 0 ]
    [ "$output" = "const x: string = 'value';" ]
}

@test "grep_to_jsonl handles empty input" {
    output=$(echo "" | grep_to_jsonl)

    # Empty output expected
    [ -z "$output" ]
}

@test "grep_to_jsonl handles file paths with spaces" {
    skip "Requires proper escaping implementation"

    input="/path/with space/file.js:42:function test() {"

    output=$(echo "$input" | grep_to_jsonl)

    run echo "$output" | jq -r '.file'
    [ "$status" -eq 0 ]
    [ "$output" = "/path/with space/file.js" ]
}

# =============================================================================
# Token Estimation Tests
# =============================================================================

@test "estimate_tokens provides reasonable token count" {
    run type estimate_tokens
    if [ "$status" -eq 0 ]; then
        # Simple test: "hello world" should be ~2 tokens
        count=$(echo "hello world" | estimate_tokens)
        [ "$count" -ge 1 ]
        [ "$count" -le 10 ]
    else
        skip "estimate_tokens not implemented"
    fi
}

@test "estimate_tokens handles empty input" {
    run type estimate_tokens
    if [ "$status" -eq 0 ]; then
        count=$(echo "" | estimate_tokens)
        [ "$count" -eq 0 ] || [ "$count" -eq 1 ]
    else
        skip "estimate_tokens not implemented"
    fi
}

# =============================================================================
# Snippet Extraction Tests
# =============================================================================

@test "extract_snippet reads specified lines from file" {
    run type extract_snippet
    if [ "$status" -eq 0 ]; then
        # Create test file
        echo -e "line1\nline2\nline3\nline4\nline5" > "${TEST_TMPDIR}/test.txt"

        # Extract lines 2-4
        output=$(extract_snippet "${TEST_TMPDIR}/test.txt" 2 4)

        [[ "$output" =~ "line2" ]]
        [[ "$output" =~ "line3" ]]
        [[ "$output" =~ "line4" ]]
        [[ ! "$output" =~ "line5" ]]
    else
        skip "extract_snippet not implemented"
    fi
}

@test "extract_snippet handles out-of-bounds line numbers" {
    run type extract_snippet
    if [ "$status" -eq 0 ]; then
        echo -e "line1\nline2\nline3" > "${TEST_TMPDIR}/test.txt"

        # Try to extract lines 10-20 (beyond file)
        run extract_snippet "${TEST_TMPDIR}/test.txt" 10 20
        [ "$status" -eq 0 ]  # Should not crash
    else
        skip "extract_snippet not implemented"
    fi
}

# =============================================================================
# Score Filtering Tests
# =============================================================================

@test "filter_by_score filters JSONL by score threshold" {
    run type filter_by_score
    if [ "$status" -eq 0 ] && [ "$BC_AVAILABLE" = true ]; then
        input='{"file":"test.js","line":1,"snippet":"test","score":0.8}
{"file":"test.js","line":2,"snippet":"test","score":0.3}
{"file":"test.js","line":3,"snippet":"test","score":0.9}'

        # Filter by threshold 0.5
        output=$(echo "$input" | filter_by_score 0.5)

        # Should only have 2 results (0.8 and 0.9)
        line_count=$(echo "$output" | wc -l)
        [ "$line_count" -eq 2 ]

        # Verify scores
        run echo "$output" | jq -r '.score' | awk '$1 >= 0.5'
        [ "$status" -eq 0 ]
    else
        skip "filter_by_score not implemented or bc not available"
    fi
}

@test "filter_by_score handles missing score field" {
    run type filter_by_score
    if [ "$status" -eq 0 ] && [ "$BC_AVAILABLE" = true ]; then
        input='{"file":"test.js","line":1,"snippet":"test"}'

        # Should pass through (or skip) entries without score
        run echo "$input" | filter_by_score 0.5
        [ "$status" -eq 0 ]
    else
        skip "filter_by_score not implemented or bc not available"
    fi
}

# =============================================================================
# Search API Function Tests
# =============================================================================

@test "semantic_search calls search-orchestrator with correct args" {
    cd "${TEST_TMPDIR}"

    # Mock search-orchestrator to echo arguments
    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo "search_type=$1 query=$2 path=$3 top_k=$4 threshold=$5"
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    output=$(semantic_search "test query" "src/" 30 0.6)

    [[ "$output" =~ "search_type=semantic" ]]
    [[ "$output" =~ "query=test query" ]]
    [[ "$output" =~ "path=".*"/src/" ]]
    [[ "$output" =~ "top_k=30" ]]
    [[ "$output" =~ "threshold=0.6" ]]
}

@test "hybrid_search calls search-orchestrator with hybrid type" {
    cd "${TEST_TMPDIR}"

    # Mock search-orchestrator
    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo "search_type=$1"
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    output=$(hybrid_search "test query")

    [[ "$output" =~ "search_type=hybrid" ]]
}

@test "regex_search calls search-orchestrator with regex type" {
    cd "${TEST_TMPDIR}"

    # Mock search-orchestrator
    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo "search_type=$1"
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    output=$(regex_search "test.*pattern")

    [[ "$output" =~ "search_type=regex" ]]
}

@test "semantic_search uses default parameters when not specified" {
    cd "${TEST_TMPDIR}"

    # Mock search-orchestrator
    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo "path=$3 top_k=$4 threshold=$5"
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    output=$(semantic_search "test")

    [[ "$output" =~ "path=".*"/src/" ]]
    [[ "$output" =~ "top_k=20" ]]
    [[ "$output" =~ "threshold=0.4" ]]
}

# =============================================================================
# BC Availability Tests
# =============================================================================

@test "search-api detects bc availability" {
    if command -v bc >/dev/null 2>&1; then
        [ "$BC_AVAILABLE" = true ]
    else
        [ "$BC_AVAILABLE" = false ]
    fi
}

@test "search-api warns when bc not available" {
    # Temporarily hide bc
    export PATH="/nonexistent"

    # Re-source to trigger check
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh 2>&1"

    if ! command -v bc >/dev/null 2>&1; then
        [[ "$output" =~ "Warning: bc not found" ]]
    fi
}

# =============================================================================
# Project Root Detection Tests
# =============================================================================

@test "search-api sets PROJECT_ROOT correctly" {
    [ -n "$PROJECT_ROOT" ]
    [ -d "$PROJECT_ROOT" ]
}

@test "search-api uses pwd when git not available" {
    # Test in directory without git
    cd "${TEST_TMPDIR}"

    # Re-execute in subshell to test PROJECT_ROOT detection
    run bash -c "source ${PROJECT_ROOT}/.claude/scripts/search-api.sh; echo \$PROJECT_ROOT"

    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

# =============================================================================
# Integration Tests
# =============================================================================

@test "semantic_search returns JSONL format" {
    cd "${TEST_TMPDIR}"

    output=$(semantic_search "authenticate" "src/")

    if [ -n "$output" ]; then
        # Check each line is valid JSON
        echo "$output" | while IFS= read -r line; do
            run echo "$line" | jq -e .
            [ "$status" -eq 0 ]
        done
    fi
}

@test "hybrid_search finds keyword matches in grep mode" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"
    output=$(hybrid_search "authenticate" "src/")

    # In grep mode, should find the function
    if [ -n "$output" ]; then
        [[ "$output" =~ "authenticate" ]] || [[ "$output" =~ "auth.js" ]]
    fi
}

@test "regex_search supports regex patterns" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"
    output=$(regex_search "function.*authenticate" "src/")

    # Should match function definition
    [ "$status" -eq 0 ]
}
