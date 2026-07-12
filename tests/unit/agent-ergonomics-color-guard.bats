#!/usr/bin/env bats
# =============================================================================
# tests/unit/agent-ergonomics-color-guard.bats
# agent-ergonomics pass 1 (bd-m1o6) R-011 — NO_COLOR/TTY color guard for
# 5 scripts (composability): validate-skill-capabilities.sh, memory-query.sh,
# grimoire-index.sh, construct-resolve.sh, repo-map-gen.sh.
#
# Guarded against regression: raw ANSI escapes leaking into piped/non-TTY
# output would break downstream JSON/text consumers that compose these
# scripts together (the whole point of a "composability" fix).
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    VALIDATOR="$PROJECT_ROOT/.claude/scripts/validate-skill-capabilities.sh"
    MEMORY_QUERY="$PROJECT_ROOT/.claude/scripts/memory-query.sh"
    GRIMOIRE_INDEX="$PROJECT_ROOT/.claude/scripts/grimoire-index.sh"
    CONSTRUCT_RESOLVE="$PROJECT_ROOT/.claude/scripts/construct-resolve.sh"
    REPO_MAP_GEN="$PROJECT_ROOT/.claude/scripts/repo-map-gen.sh"

    FIXTURE_DIR="$BATS_TEST_TMPDIR/skills"
    mkdir -p "$FIXTURE_DIR/good-skill"
    cat > "$FIXTURE_DIR/good-skill/SKILL.md" << 'EOF'
---
name: good
description: A good skill
allowed-tools: Read, Grep, Glob
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: false
  execute_commands: false
  web_access: false
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: lightweight
---
# Good Skill
EOF
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR/skills" 2>/dev/null || true
}

# --- validate-skill-capabilities.sh ---

@test "R-011: validate-skill-capabilities.sh piped output has no ESC byte" {
    SKILLS_DIR="$FIXTURE_DIR" run timeout 30 bash "$VALIDATOR" --skill good-skill
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}

@test "R-011: validate-skill-capabilities.sh NO_COLOR=1 has no ESC byte" {
    NO_COLOR=1 SKILLS_DIR="$FIXTURE_DIR" run timeout 30 bash "$VALIDATOR" --skill good-skill
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}

# --- memory-query.sh ---

@test "R-011: memory-query.sh --help has no ESC byte" {
    run timeout 30 bash "$MEMORY_QUERY" --help
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}

@test "R-011: memory-query.sh --help NO_COLOR=1 has no ESC byte" {
    NO_COLOR=1 run timeout 30 bash "$MEMORY_QUERY" --help
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}

# --- grimoire-index.sh ---

@test "R-011: grimoire-index.sh --help has no ESC byte" {
    run timeout 30 bash "$GRIMOIRE_INDEX" --help
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}

# --- construct-resolve.sh ---

@test "R-011: construct-resolve.sh --help has no ESC byte" {
    run timeout 30 bash "$CONSTRUCT_RESOLVE" --help
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}

# --- repo-map-gen.sh ---

@test "R-011: repo-map-gen.sh --help has no ESC byte" {
    run timeout 30 bash "$REPO_MAP_GEN" --help
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}
