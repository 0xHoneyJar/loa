#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/.claude/scripts/workspace-cleanup.sh"
    export REAL_REALPATH="$(command -v realpath)"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/work/grimoires/loa"
    cat > "$BATS_TEST_TMPDIR/bin/realpath" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "-m" ]]; then
    echo 'realpath: illegal option -- m' >&2
    exit 1
fi
exec "$REAL_REALPATH" "$@"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/realpath"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    unset _PORTABLE_REALPATH_HAS_M
    cd "$BATS_TEST_TMPDIR/work"
    printf 'archive me\n' > grimoires/loa/prd.md
}

@test "#1197: BSD realpath cleanup dry-run lists the existing artifact" {
    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run --json
    echo "$output"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.dry_run and .would_archive_count == 1 and .files == ["prd.md"]'
    [ -f grimoires/loa/prd.md ]
}

@test "#1197: BSD path validation accepts files and rejects symlink escapes" {
    mkdir outside
    printf 'keep\n' > outside/private.md
    ln -s ../../outside grimoires/loa/escape
    run bash -c '
        source "$1"
        validate_single_path prd.md
        FOLLOW_SYMLINKS=true
        ! validate_single_path escape/private.md
        ! validate_single_path ../outside/private.md
        ! validate_single_path /etc/passwd
    ' _ "$SCRIPT"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "#1197: an empty successful resolver must not admit paths" {
    run bash -c '
        source "$1"
        resolve_path_portable() { return 0; }
        validate_single_path prd.md
    ' _ "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "#1197: unresolved grimoire exits with security validation failure" {
    run bash -c '
        source "$1"
        resolve_path_portable() { return 1; }
        main --grimoire grimoires/loa --dry-run --json
    ' _ "$SCRIPT"
    echo "$output"
    [ "$status" -eq 3 ]
    [[ "$output" == *"Cannot resolve grimoire path"* ]]
    [[ "$output" != *'"dry_run": true'* ]]
    [ ! -e grimoires/loa/.cleanup.lock ]
}
