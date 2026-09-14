#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_REPO="$(mktemp -d)"
    mkdir -p "$TEST_REPO/.claude/scripts"
    cp "$ROOT/.claude/scripts/"{bootstrap.sh,path-lib.sh,semver-bump.sh} "$TEST_REPO/.claude/scripts/"
    git -C "$TEST_REPO" init -q
    git -C "$TEST_REPO" config user.name Test
    git -C "$TEST_REPO" config user.email test@example.invalid
    export PROJECT_ROOT="$TEST_REPO"
    SCRIPT="$TEST_REPO/.claude/scripts/semver-bump.sh"
}

teardown() { rm -rf "$TEST_REPO"; }

commit() { git -C "$TEST_REPO" commit --allow-empty -qm "$1"; }

@test "semver evidence: bootstrap first version from classified history" {
    commit "feat: first application"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    jq -e '.current == "0.0.0" and .next == "0.1.0" and .bump == "initial" and .version_source == "initial"' <<< "$output"
}

@test "semver evidence: unknown squash subject refuses silent patch" {
    commit "feat: initial"
    git -C "$TEST_REPO" tag v1.0.0
    commit "Ship the completed work"
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"classif"* ]]
}

@test "semver evidence: classification records its source and matching commit" {
    commit "feat: initial"
    git -C "$TEST_REPO" tag v1.0.0
    commit "fix: repair corruption"
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    jq -e '.classification.source == "conventional_commits" and (.classification.reasoning | length > 0) and (.classification.commits | length == 1)' <<< "$output"
}

@test "semver evidence: explicit tag mode never bootstraps implicitly" {
    commit "feat: first application"
    run bash "$SCRIPT" --from-tag
    [ "$status" -eq 2 ]
}

@test "semver evidence: breaking body retains the classifying commit identity" {
    commit "feat: initial"
    git -C "$TEST_REPO" tag v1.0.0
    commit $'Ship changed protocol\n\nBREAKING CHANGE: old protocol removed'
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    jq -e '.bump == "major" and (.classification.commits | length == 1) and .commits[0].classified_bump == "major"' <<< "$output"
}
