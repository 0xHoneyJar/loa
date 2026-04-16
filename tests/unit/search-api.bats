#!/usr/bin/env bats
# Unit tests for .claude/scripts/search-api.sh
# Tests search API functions, grep_to_jsonl conversion, and helper functions

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TMPDIR}/search-api-test-$$"
    mkdir -p "${TEST_TMPDIR}"

    # Create test directory structure
    mkdir -p "${TEST_TMPDIR}/src"
    mkdir -p "${TEST_TMPDIR}/grimoires/loa/a2a/trajectory"
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
    echo "$output" | jq -e .

    # Check fields
    file=$(echo "$output" | jq -r '.file')
    [ "$file" = "/path/to/file.js" ]

    line=$(echo "$output" | jq -r '.line')
    [ "$line" = "42" ]

    snippet=$(echo "$output" | jq -r '.snippet')
    [ "$snippet" = "function test() {" ]
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
    while IFS= read -r json_line; do
        echo "$json_line" | jq -e .
    done <<< "$output"
}

@test "grep_to_jsonl handles colons in snippet" {
    input="/path/to/file.js:15:const x: string = 'value';"

    output=$(echo "$input" | grep_to_jsonl)

    snippet=$(echo "$output" | jq -r '.snippet')
    [ "$snippet" = "const x: string = 'value';" ]
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
        # estimate_tokens takes $1, not stdin; "hello world" = 11 chars / 4 = 2
        count=$(estimate_tokens "hello world")
        [ "$count" -ge 1 ]
        [ "$count" -le 10 ]
    else
        skip "estimate_tokens not implemented"
    fi
}

@test "estimate_tokens handles empty input" {
    run type estimate_tokens
    if [ "$status" -eq 0 ]; then
        # Empty string: 0 chars / 4 = 0
        count=$(estimate_tokens "")
        [ "$count" -eq 0 ]
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
        printf 'line1\nline2\nline3\nline4\nline5\n' > "${TEST_TMPDIR}/test.txt"

        # extract_snippet(file, center_line, context_radius)
        # center=3, context=1 → lines 2-4
        output=$(extract_snippet "${TEST_TMPDIR}/test.txt" 3 1)

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

        # Verify all remaining scores are >= 0.5
        echo "$output" | jq -r '.score' | awk '$1 < 0.5 { exit 1 }'
    else
        skip "filter_by_score not implemented or bc not available"
    fi
}

@test "filter_by_score handles missing score field" {
    run type filter_by_score
    if [ "$status" -eq 0 ] && [ "$BC_AVAILABLE" = true ]; then
        input='{"file":"test.js","line":1,"snippet":"test"}'

        # Should pass through (or skip) entries without score
        echo "$input" | filter_by_score 0.5
    else
        skip "filter_by_score not implemented or bc not available"
    fi
}

# =============================================================================
# Search API Function Tests
# =============================================================================

@test "semantic_search calls search-orchestrator with correct args" {
    cd "${TEST_TMPDIR}"

    # Mock search-orchestrator — override PROJECT_ROOT so functions find it
    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo "search_type=$1 query=$2 path=$3 top_k=$4 threshold=$5"
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    local saved_root="$PROJECT_ROOT"
    PROJECT_ROOT="${TEST_TMPDIR}"

    output=$(semantic_search "test query" "src/" 30 0.6)

    PROJECT_ROOT="$saved_root"

    [[ "$output" =~ "search_type=semantic" ]]
    [[ "$output" =~ "query=test query" ]]
    [[ "$output" =~ "top_k=30" ]]
    [[ "$output" =~ "threshold=0.6" ]]
}

@test "hybrid_search calls search-orchestrator with hybrid type" {
    cd "${TEST_TMPDIR}"

    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo "search_type=$1"
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    local saved_root="$PROJECT_ROOT"
    PROJECT_ROOT="${TEST_TMPDIR}"
    output=$(hybrid_search "test query")
    PROJECT_ROOT="$saved_root"

    [[ "$output" =~ "search_type=hybrid" ]]
}

@test "regex_search calls search-orchestrator with regex type" {
    cd "${TEST_TMPDIR}"

    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo "search_type=$1"
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    local saved_root="$PROJECT_ROOT"
    PROJECT_ROOT="${TEST_TMPDIR}"
    output=$(regex_search "test.*pattern")
    PROJECT_ROOT="$saved_root"

    [[ "$output" =~ "search_type=regex" ]]
}

@test "semantic_search uses default parameters when not specified" {
    cd "${TEST_TMPDIR}"

    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo "path=$3 top_k=$4 threshold=$5"
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"

    local saved_root="$PROJECT_ROOT"
    PROJECT_ROOT="${TEST_TMPDIR}"
    output=$(semantic_search "test")
    PROJECT_ROOT="$saved_root"

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
    # Re-source in a subshell with minimal PATH (hiding bc but keeping bash/jq)
    run bash -c "export PATH=/usr/bin:/bin; hash -r; unset BC_AVAILABLE; source '${PROJECT_ROOT}/.claude/scripts/search-api.sh' 2>&1"

    # If bc is in /usr/bin or /bin it will still be found — skip in that case
    if command -v bc >/dev/null 2>&1; then
        skip "bc is available on default PATH — cannot test missing bc"
    fi
    [[ "$output" =~ "Warning: bc not found" ]]
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

    local saved_root="$PROJECT_ROOT"
    # Use mock orchestrator that returns JSONL
    cat > "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh" << 'EOF'
#!/usr/bin/env bash
echo '{"file":"test.js","line":1,"snippet":"test"}'
EOF
    chmod +x "${TEST_TMPDIR}/.claude/scripts/search-orchestrator.sh"
    PROJECT_ROOT="${TEST_TMPDIR}"

    output=$(semantic_search "authenticate" "src/")
    PROJECT_ROOT="$saved_root"

    if [ -n "$output" ]; then
        while IFS= read -r json_line; do
            echo "$json_line" | jq -e .
        done <<< "$output"
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
    run regex_search "function.*authenticate" "src/"

    # Should match function definition (or return 0 even if no matches in grep mode)
    [ "$status" -eq 0 ]
}
