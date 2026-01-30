#!/usr/bin/env bats
# Tests for cache-manager.sh - Semantic result cache

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CACHE_MANAGER="$PROJECT_ROOT/.claude/scripts/cache-manager.sh"

    # Create temp directory for test cache
    TEST_CACHE_DIR="$(mktemp -d)"
    export CACHE_DIR="$TEST_CACHE_DIR"
    export CACHE_INDEX="$TEST_CACHE_DIR/index.json"
    export RESULTS_DIR="$TEST_CACHE_DIR/results"
    export FULL_DIR="$TEST_CACHE_DIR/full"

    # Ensure cache is enabled for tests
    export LOA_CACHE_ENABLED="true"
}

teardown() {
    # Clean up test cache
    rm -rf "$TEST_CACHE_DIR"
}

@test "cache-manager.sh exists and is executable" {
    [[ -x "$CACHE_MANAGER" ]]
}

@test "cache-manager.sh shows help with --help" {
    run "$CACHE_MANAGER" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Cache Manager"* ]]
}

@test "generate-key produces consistent hash" {
    run "$CACHE_MANAGER" generate-key \
        --paths "src/auth.ts,src/user.ts" \
        --query "security audit" \
        --operation "audit"
    [[ "$status" -eq 0 ]]
    key1="$output"

    run "$CACHE_MANAGER" generate-key \
        --paths "src/auth.ts,src/user.ts" \
        --query "security audit" \
        --operation "audit"
    [[ "$status" -eq 0 ]]
    key2="$output"

    [[ "$key1" == "$key2" ]]
}

@test "generate-key normalizes path order" {
    run "$CACHE_MANAGER" generate-key \
        --paths "src/user.ts,src/auth.ts" \
        --query "test" \
        --operation "audit"
    [[ "$status" -eq 0 ]]
    key1="$output"

    run "$CACHE_MANAGER" generate-key \
        --paths "src/auth.ts,src/user.ts" \
        --query "test" \
        --operation "audit"
    [[ "$status" -eq 0 ]]
    key2="$output"

    [[ "$key1" == "$key2" ]]
}

@test "generate-key normalizes query case" {
    run "$CACHE_MANAGER" generate-key \
        --paths "src/test.ts" \
        --query "SECURITY AUDIT" \
        --operation "audit"
    [[ "$status" -eq 0 ]]
    key1="$output"

    run "$CACHE_MANAGER" generate-key \
        --paths "src/test.ts" \
        --query "security audit" \
        --operation "audit"
    [[ "$status" -eq 0 ]]
    key2="$output"

    [[ "$key1" == "$key2" ]]
}

@test "set creates cache entry" {
    run "$CACHE_MANAGER" set \
        --key "test-key-001" \
        --condensed '{"verdict":"PASS"}'
    [[ "$status" -eq 0 ]]

    # Check index was updated
    [[ -f "$CACHE_INDEX" ]]
    run jq -r '.entries["test-key-001"]' "$CACHE_INDEX"
    [[ "$output" != "null" ]]

    # Check result file exists
    [[ -f "$RESULTS_DIR/test-key-001.json" ]]
}

@test "get returns cached result" {
    # Set a value
    "$CACHE_MANAGER" set \
        --key "test-key-002" \
        --condensed '{"verdict":"PASS","count":5}'

    # Get it back
    run "$CACHE_MANAGER" get --key "test-key-002"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"verdict":"PASS"'* ]]
}

@test "get returns miss for non-existent key" {
    run "$CACHE_MANAGER" get --key "nonexistent-key"
    [[ "$status" -ne 0 ]]
}

@test "delete removes cache entry" {
    # Set a value
    "$CACHE_MANAGER" set \
        --key "test-key-003" \
        --condensed '{"test":"delete"}'

    # Verify it exists
    [[ -f "$RESULTS_DIR/test-key-003.json" ]]

    # Delete it
    run "$CACHE_MANAGER" delete --key "test-key-003"
    [[ "$status" -eq 0 ]]

    # Verify it's gone
    [[ ! -f "$RESULTS_DIR/test-key-003.json" ]]
}

@test "set rejects secret patterns" {
    run "$CACHE_MANAGER" set \
        --key "test-secrets" \
        --condensed '{"password": "secret123"}'
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Secret patterns detected"* ]]
}

@test "stats shows cache statistics" {
    # Add some entries
    "$CACHE_MANAGER" set --key "stats-test-1" --condensed '{"a":1}'
    "$CACHE_MANAGER" set --key "stats-test-2" --condensed '{"b":2}'

    run "$CACHE_MANAGER" stats --json
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"entries":'* ]]
    [[ "$output" == *'"enabled": true'* ]]
}

@test "clear removes all entries" {
    # Add entries
    "$CACHE_MANAGER" set --key "clear-test-1" --condensed '{"a":1}'
    "$CACHE_MANAGER" set --key "clear-test-2" --condensed '{"b":2}'

    # Clear
    run "$CACHE_MANAGER" clear
    [[ "$status" -eq 0 ]]

    # Verify empty
    run "$CACHE_MANAGER" stats --json
    [[ "$output" == *'"entries": 0'* ]]
}

@test "cache disabled when LOA_CACHE_ENABLED=false" {
    export LOA_CACHE_ENABLED="false"

    run "$CACHE_MANAGER" set --key "disabled-test" --condensed '{"test":1}'
    [[ "$status" -eq 0 ]]  # Should succeed but not cache

    run "$CACHE_MANAGER" get --key "disabled-test"
    [[ "$status" -ne 0 ]]  # Should miss
}

@test "integrity hash verified on get" {
    # Set a value
    "$CACHE_MANAGER" set --key "integrity-test" --condensed '{"test":"integrity"}'

    # Corrupt the result file
    echo '{"corrupted":"data"}' > "$RESULTS_DIR/integrity-test.json"

    # Get should fail due to integrity mismatch
    run "$CACHE_MANAGER" get --key "integrity-test"
    [[ "$status" -ne 0 ]]
}
