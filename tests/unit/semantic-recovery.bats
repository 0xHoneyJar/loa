#!/usr/bin/env bats
# Tests for semantic recovery enhancement in context-manager.sh

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CONTEXT_MANAGER="$PROJECT_ROOT/.claude/scripts/context-manager.sh"

    # Create temp directory for test files
    TEST_DIR="$(mktemp -d)"
    export NOTES_FILE="$TEST_DIR/NOTES.md"
    export GRIMOIRE_DIR="$TEST_DIR"
    export TRAJECTORY_DIR="$TEST_DIR/trajectory"
    mkdir -p "$TRAJECTORY_DIR"

    # Create test NOTES.md with sections
    cat > "$NOTES_FILE" << 'EOF'
# Project Notes

## Session Continuity

Current focus: Implementing authentication flow
Last task: beads-abc123
Status: In progress

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-01-22 | Use JWT for auth | Industry standard |
| 2026-01-22 | Redis for sessions | Performance requirements |

## Blockers

- [x] [RESOLVED] API key configuration
- [ ] Database migration pending

## Security Notes

Authentication uses bcrypt with cost factor 12.
All tokens have 15-minute expiry.
Refresh tokens stored securely.

## Performance Optimization

Query optimization completed for user lookups.
Caching layer added for frequent reads.
Connection pooling configured.
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "context-manager.sh exists and is executable" {
    [[ -x "$CONTEXT_MANAGER" ]]
}

@test "recover command works without query" {
    run "$CONTEXT_MANAGER" recover 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Level 1"* ]]
}

@test "recover command accepts --query flag" {
    run "$CONTEXT_MANAGER" recover 2 --query "authentication"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Query:"* ]]
    [[ "$output" == *"authentication"* ]]
}

@test "recover level 1 shows session continuity" {
    run "$CONTEXT_MANAGER" recover 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Session Continuity"* ]]
}

@test "recover level 2 mentions decision log" {
    run "$CONTEXT_MANAGER" recover 2
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Decision Log"* ]]
}

@test "recover level 3 mentions trajectory" {
    run "$CONTEXT_MANAGER" recover 3
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Trajectory"* ]]
}

@test "semantic recovery finds security-related content" {
    run "$CONTEXT_MANAGER" recover 2 --query "security tokens"
    [[ "$status" -eq 0 ]]
    # Should use semantic/keyword search
    [[ "$output" == *"Semantic Recovery"* ]] || [[ "$output" == *"keyword search"* ]]
}

@test "semantic recovery falls back when no matches" {
    run "$CONTEXT_MANAGER" recover 2 --query "nonexistent_topic_xyz"
    [[ "$status" -eq 0 ]]
    # Should fall back to positional
    [[ "$output" == *"falling back"* ]] || [[ "$output" == *"Level 2"* ]]
}

@test "empty query treated as no query" {
    run "$CONTEXT_MANAGER" recover 1 --query ""
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Level 1"* ]]
}

@test "invalid level rejected" {
    run "$CONTEXT_MANAGER" recover 5
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Invalid level"* ]]
}

@test "recover handles missing NOTES.md" {
    rm -f "$NOTES_FILE"

    run "$CONTEXT_MANAGER" recover 1
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not found"* ]]
}

@test "recover with query respects token budget" {
    # Level 1 = 100 tokens, Level 2 = 500 tokens, Level 3 = 2000 tokens
    run "$CONTEXT_MANAGER" recover 1 --query "authentication"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"100 tokens"* ]]

    run "$CONTEXT_MANAGER" recover 2 --query "authentication"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"500 tokens"* ]]

    run "$CONTEXT_MANAGER" recover 3 --query "authentication"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"2000 tokens"* ]]
}

@test "status command still works" {
    run "$CONTEXT_MANAGER" status
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Context Manager Status"* ]]
}

@test "rules command still works" {
    run "$CONTEXT_MANAGER" rules
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Preservation Rules"* ]]
}

@test "probe command still works" {
    run "$CONTEXT_MANAGER" probe "$TEST_DIR"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Directory Probe"* ]] || [[ "$output" == *"directory"* ]]
}
