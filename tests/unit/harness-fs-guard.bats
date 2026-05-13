#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-1 T1.E: harness-fs-guard.sh unit tests
# =============================================================================
# Tests the FS guards: symlink-scan (no escapes), snapshot-pre/post.
# Closes SDD §20.6 ATK-A14 (symlink-traversal escape from worktree).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GUARD="$REPO_ROOT/.claude/scripts/lib/harness-fs-guard.sh"
    TEST_DIR=$(mktemp -d "/tmp/harness-fs-guard-XXXXXX")
    OUTSIDE_DIR=$(mktemp -d "/tmp/outside-XXXXXX")
    # shellcheck disable=SC1090
    source "$GUARD"
}

teardown() {
    rm -rf "$TEST_DIR" "$OUTSIDE_DIR"
}

# --- harness_symlink_scan ----------------------------------------------------

@test "T1.E: symlink_scan returns 0 on directory with no symlinks" {
    mkdir -p "$TEST_DIR/sub"
    touch "$TEST_DIR/sub/file.txt"
    run harness_symlink_scan "$TEST_DIR"
    [ "$status" -eq 0 ]
}

@test "T1.E: symlink_scan returns 0 on internal symlinks" {
    mkdir -p "$TEST_DIR/a" "$TEST_DIR/b"
    touch "$TEST_DIR/a/target.txt"
    ln -s "$TEST_DIR/a/target.txt" "$TEST_DIR/b/link"
    run harness_symlink_scan "$TEST_DIR"
    [ "$status" -eq 0 ]
}

@test "T1.E: symlink_scan returns 1 on external-pointing symlink" {
    mkdir -p "$TEST_DIR/sub"
    touch "$OUTSIDE_DIR/secret.txt"
    ln -s "$OUTSIDE_DIR/secret.txt" "$TEST_DIR/sub/escape"
    run harness_symlink_scan "$TEST_DIR"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "symlink_escape"
}

@test "T1.E: symlink_scan emits JSON-line on stdout for external symlink" {
    mkdir -p "$TEST_DIR/sub"
    touch "$OUTSIDE_DIR/secret.txt"
    ln -s "$OUTSIDE_DIR/secret.txt" "$TEST_DIR/sub/escape"
    run harness_symlink_scan "$TEST_DIR"
    # JSON line on stdout (the BLOCK message goes to stderr in `run`'s combined output)
    echo "$output" | grep -q '"event":"symlink_escape"'
    echo "$output" | grep -q '"link":'
    echo "$output" | grep -q '"target":'
}

@test "T1.E: symlink_scan returns 2 when directory does not exist" {
    run harness_symlink_scan "/tmp/does-not-exist-cycle108-$$"
    [ "$status" -eq 2 ]
}

@test "T1.E: symlink_scan detects multiple external symlinks" {
    mkdir -p "$TEST_DIR/sub"
    touch "$OUTSIDE_DIR/a.txt" "$OUTSIDE_DIR/b.txt"
    ln -s "$OUTSIDE_DIR/a.txt" "$TEST_DIR/sub/escape1"
    ln -s "$OUTSIDE_DIR/b.txt" "$TEST_DIR/sub/escape2"
    run harness_symlink_scan "$TEST_DIR"
    [ "$status" -eq 1 ]
    # Two BLOCK entries
    count=$(echo "$output" | grep -c "symlink_escape")
    [ "$count" -eq 2 ]
}

# --- harness_fs_snapshot_pre / _post -----------------------------------------

@test "T1.E: snapshot_pre creates output file" {
    out_file="$TEST_DIR/snapshot.txt"
    # Constrain protected paths to a controlled subset for the test
    export LOA_HARNESS_FS_GUARD_EXTRA_PATHS=""
    # Override default paths via clever envvar — for the stub, we just
    # confirm the function executes and produces output.
    harness_fs_snapshot_pre "$out_file"
    [ -f "$out_file" ]
}

@test "T1.E: snapshot_post returns 0 when no mutations between pre and post" {
    # Exclusive mode: monitor only our controlled test dir (avoids
    # /tmp / $HOME mutations from unrelated processes)
    export LOA_HARNESS_FS_GUARD_EXCLUSIVE=1
    export LOA_HARNESS_FS_GUARD_EXTRA_PATHS="$TEST_DIR/monitored"
    mkdir -p "$TEST_DIR/monitored"
    touch "$TEST_DIR/monitored/stable.txt"
    pre_file="$TEST_DIR/pre.txt"
    harness_fs_snapshot_pre "$pre_file"
    run harness_fs_snapshot_post "$pre_file"
    [ "$status" -eq 0 ]
}

@test "T1.E: snapshot_post returns 2 when pre-file missing" {
    run harness_fs_snapshot_post "$TEST_DIR/nonexistent.txt"
    [ "$status" -eq 2 ]
}

@test "T1.E: snapshot_post detects new file in monitored path" {
    # Exclusive mode: monitor only our controlled test dir
    export LOA_HARNESS_FS_GUARD_EXCLUSIVE=1
    export LOA_HARNESS_FS_GUARD_EXTRA_PATHS="$TEST_DIR/monitored"
    mkdir -p "$TEST_DIR/monitored"
    pre_file="$TEST_DIR/pre.txt"
    harness_fs_snapshot_pre "$pre_file"
    # Plant a new file in the monitored dir
    touch "$TEST_DIR/monitored/planted.txt"
    sleep 0.1   # ensure mtime difference is observable
    run harness_fs_snapshot_post "$pre_file"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "fs_mutation"
}
