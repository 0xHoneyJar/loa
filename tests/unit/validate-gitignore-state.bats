#!/usr/bin/env bats
# =============================================================================
# tests/unit/validate-gitignore-state.bats
# cycle-119 C17 — validate-gitignore-state.sh diagnostic
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/validate-gitignore-state.sh"

    TEST_REPO="$(mktemp -d)"
    cd "$TEST_REPO" || exit 1
    git init -q
    git config user.email "test@test.com"
    git config user.name "test"
}

teardown() {
    rm -rf "$TEST_REPO"
}

@test "validate-gitignore-state: --help exits 0 and describes usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: validate-gitignore-state.sh" ]]
}

@test "validate-gitignore-state: no zone dirs present — clean, exit 0" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no State-Zone gitignore drift found" ]]
}

@test "validate-gitignore-state: whole .run/ root gitignored — WARN with pattern" {
    mkdir -p .run
    echo ".run/" > .gitignore
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN: .run is gitignored by:" ]]
    [[ "$output" =~ ".gitignore" ]]
}

@test "validate-gitignore-state: --json emits a warnings array with path/pattern/fix" {
    mkdir -p .beads
    echo ".beads/" > .gitignore
    run "$SCRIPT" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.warnings | length >= 1' >/dev/null
    echo "$output" | jq -e '.warnings[0].path == ".beads"' >/dev/null
}

@test "validate-gitignore-state: curated tracked file caught by a broader drifting pattern" {
    mkdir -p grimoires/loa
    echo "grimoires/loa/known-failures.md" >> grimoires/loa/known-failures.md
    echo "grimoires/*" > .gitignore
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "grimoires/loa/known-failures.md is gitignored by:" ]]
}

@test "validate-gitignore-state: curated tracked file NOT ignored — no warning for it" {
    mkdir -p grimoires/loa
    echo "zones: {}" > grimoires/loa/zones.yaml
    : > .gitignore
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "zones.yaml" ]]
}

@test "validate-gitignore-state: honors LOA_GRIMOIRE_DIR override" {
    mkdir -p custom-grim
    echo "custom-grim/" > .gitignore
    LOA_GRIMOIRE_DIR="custom-grim" run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN: custom-grim is gitignored by:" ]]
}
