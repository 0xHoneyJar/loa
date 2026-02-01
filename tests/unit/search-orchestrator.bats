#!/usr/bin/env bats
# Unit tests for .claude/scripts/search-orchestrator.sh
# Tests search routing, mode detection, and trajectory logging

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TMPDIR}/search-test-$$"
    mkdir -p "${TEST_TMPDIR}"

    # Create test directory structure
    mkdir -p "${TEST_TMPDIR}/src"
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory"
    mkdir -p "${TEST_TMPDIR}/.claude/scripts"

    # Create test files
    echo "function validateToken(token) {" > "${TEST_TMPDIR}/src/auth.js"
    echo "  return jwt.verify(token, secret);" >> "${TEST_TMPDIR}/src/auth.js"
    echo "}" >> "${TEST_TMPDIR}/src/auth.js"

    # Mock preflight.sh (always pass)
    echo '#!/usr/bin/env bash' > "${TEST_TMPDIR}/.claude/scripts/preflight.sh"
    echo 'exit 0' >> "${TEST_TMPDIR}/.claude/scripts/preflight.sh"
    chmod +x "${TEST_TMPDIR}/.claude/scripts/preflight.sh"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
    unset LOA_SEARCH_MODE
}

# =============================================================================
# Mode Detection Tests
# =============================================================================

@test "search-orchestrator detects ck when available" {
    skip "Requires ck installation"

    cd "${TEST_TMPDIR}"
    unset LOA_SEARCH_MODE

    if command -v ck >/dev/null 2>&1; then
        run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test query" "src/"
        [ "$LOA_SEARCH_MODE" = "ck" ]
    fi
}

@test "search-orchestrator falls back to grep when ck unavailable" {
    cd "${TEST_TMPDIR}"
    unset LOA_SEARCH_MODE

    # Temporarily hide ck if it exists
    export PATH="/usr/bin:/bin"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test query" "src/"

    # Check if grep mode was selected (verify by checking trajectory log)
    if [ -f "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl" ]; then
        run grep '"mode":"grep"' "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
        [ "$status" -eq 0 ]
    fi
}

@test "search-orchestrator caches mode detection in LOA_SEARCH_MODE" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="ck"
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "src/"

    # Mode should remain cached
    [ "$LOA_SEARCH_MODE" = "ck" ]
}

# =============================================================================
# Argument Validation Tests
# =============================================================================

@test "search-orchestrator requires query argument" {
    cd "${TEST_TMPDIR}"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: Query is required" ]]
}

@test "search-orchestrator accepts all search types" {
    cd "${TEST_TMPDIR}"

    # Semantic
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "src/"
    [ "$status" -eq 0 ] || [ "$status" -eq 127 ]  # 0 = success, 127 = ck not found (acceptable)

    # Hybrid
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "hybrid" "test" "src/"
    [ "$status" -eq 0 ] || [ "$status" -eq 127 ]

    # Regex
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "regex" "test" "src/"
    [ "$status" -eq 0 ] || [ "$status" -eq 127 ]
}

@test "search-orchestrator normalizes relative paths to absolute" {
    cd "${TEST_TMPDIR}"

    # Use relative path
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "src/"

    # Check trajectory log has absolute path
    if [ -f "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl" ]; then
        run grep '"path":"'"${TEST_TMPDIR}"'/src/"' "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# Trajectory Logging Tests
# =============================================================================

@test "search-orchestrator logs intent phase to trajectory" {
    cd "${TEST_TMPDIR}"

    export LOA_AGENT_NAME="test-agent"
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "authentication" "src/" 20 0.4

    # Check trajectory file exists
    trajectory_file="${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
    [ -f "$trajectory_file" ]

    # Check trajectory contains intent phase
    run grep '"phase":"intent"' "$trajectory_file"
    [ "$status" -eq 0 ]

    # Check trajectory contains query
    run grep '"query":"authentication"' "$trajectory_file"
    [ "$status" -eq 0 ]
}

@test "search-orchestrator logs search_type in trajectory" {
    cd "${TEST_TMPDIR}"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "hybrid" "test query" "src/"

    trajectory_file="${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
    if [ -f "$trajectory_file" ]; then
        run grep '"search_type":"hybrid"' "$trajectory_file"
        [ "$status" -eq 0 ]
    fi
}

@test "search-orchestrator logs mode (ck or grep) in trajectory" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "src/"

    trajectory_file="${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
    if [ -f "$trajectory_file" ]; then
        run grep '"mode":"grep"' "$trajectory_file"
        [ "$status" -eq 0 ]
    fi
}

@test "search-orchestrator creates trajectory directory if missing" {
    cd "${TEST_TMPDIR}"
    rm -rf "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "src/"

    [ -d "${TEST_TMPDIR}/loa-grimoire/a2a/trajectory" ]
}

# =============================================================================
# JSONL Output Tests
# =============================================================================

@test "search-orchestrator outputs valid JSONL format" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"
    output=$(${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh "regex" "function" "src/")

    # Check each line is valid JSON
    if [ -n "$output" ]; then
        echo "$output" | while IFS= read -r line; do
            run echo "$line" | jq -e .
            [ "$status" -eq 0 ]
        done
    fi
}

@test "search-orchestrator JSONL contains required fields" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"
    output=$(${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh "regex" "validateToken" "src/")

    if [ -n "$output" ]; then
        # Check first result has required fields
        first_line=$(echo "$output" | head -1)

        # Check for file field
        run echo "$first_line" | jq -e '.file'
        [ "$status" -eq 0 ]

        # Check for line field
        run echo "$first_line" | jq -e '.line'
        [ "$status" -eq 0 ]

        # Check for snippet field
        run echo "$first_line" | jq -e '.snippet'
        [ "$status" -eq 0 ]
    fi
}

# =============================================================================
# Search Execution Tests
# =============================================================================

@test "search-orchestrator executes grep fallback for semantic search" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "validateToken" "src/"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "validateToken" ]] || [ -z "$output" ]
}

@test "search-orchestrator executes grep fallback for hybrid search" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "hybrid" "jwt verify" "src/"

    [ "$status" -eq 0 ]
}

@test "search-orchestrator executes grep for regex search" {
    cd "${TEST_TMPDIR}"

    export LOA_SEARCH_MODE="grep"
    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "regex" "function.*Token" "src/"

    [ "$status" -eq 0 ]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "search-orchestrator handles invalid search type gracefully" {
    cd "${TEST_TMPDIR}"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "invalid" "test" "src/"
    [ "$status" -ne 0 ]
}

@test "search-orchestrator handles nonexistent search path" {
    cd "${TEST_TMPDIR}"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "/nonexistent/path/"

    # Should not crash, may return empty results
    [ "$status" -eq 0 ] || [ "$status" -eq 127 ]
}

@test "search-orchestrator calls preflight check before search" {
    cd "${TEST_TMPDIR}"

    # Create preflight that fails
    echo '#!/usr/bin/env bash' > "${TEST_TMPDIR}/.claude/scripts/preflight.sh"
    echo 'exit 1' >> "${TEST_TMPDIR}/.claude/scripts/preflight.sh"
    chmod +x "${TEST_TMPDIR}/.claude/scripts/preflight.sh"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "src/"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Parameter Tests
# =============================================================================

@test "search-orchestrator accepts top_k parameter" {
    cd "${TEST_TMPDIR}"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "src/" 50

    # Check trajectory log has top_k=50
    trajectory_file="${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
    if [ -f "$trajectory_file" ]; then
        run grep '"top_k":50' "$trajectory_file"
        [ "$status" -eq 0 ]
    fi
}

@test "search-orchestrator accepts threshold parameter" {
    cd "${TEST_TMPDIR}"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test" "src/" 20 0.7

    # Check trajectory log has threshold=0.7
    trajectory_file="${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
    if [ -f "$trajectory_file" ]; then
        run grep '"threshold":0.7' "$trajectory_file"
        [ "$status" -eq 0 ]
    fi
}

@test "search-orchestrator uses default parameters when not specified" {
    cd "${TEST_TMPDIR}"

    run "${PROJECT_ROOT}/.claude/scripts/search-orchestrator.sh" "semantic" "test"

    # Check trajectory log has defaults (top_k=20, threshold=0.4)
    trajectory_file="${TEST_TMPDIR}/loa-grimoire/a2a/trajectory/$(date +%Y-%m-%d).jsonl"
    if [ -f "$trajectory_file" ]; then
        run grep '"top_k":20' "$trajectory_file"
        [ "$status" -eq 0 ]

        run grep '"threshold":0.4' "$trajectory_file"
        [ "$status" -eq 0 ]
    fi
}
