#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/.claude/scripts/workspace-cleanup.sh"
    [ -f "$SCRIPT" ]
    export REAL_REALPATH="$(command -v realpath)"
    export REAL_DU="$(command -v du)"
    export REAL_DF="$(command -v df)"
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
    cat > "$BATS_TEST_TMPDIR/bin/du" <<'SH'
#!/usr/bin/env bash
[[ "$*" != *-sb* ]] || { echo 'du: illegal option -- b' >&2; exit 64; }
case "${DU_RESULT:-real}" in
    fail) echo 'du: fixture failure' >&2; exit 64 ;;
    empty) exit 0 ;;
    malformed) printf 'unknown\t%s\n' "${@: -1}"; exit 0 ;;
    fixed) printf '8\t%s\n' "${@: -1}"; exit 0 ;;
esac
exec "$REAL_DU" "$@"
SH
    cat > "$BATS_TEST_TMPDIR/bin/df" <<'SH'
#!/usr/bin/env bash
[[ "$*" != *-B* ]] || { echo 'df: illegal option -- B' >&2; exit 64; }
case "${DF_RESULT:-real}" in
    fail) echo 'df: fixture failure' >&2; exit 64 ;;
    empty) exit 0 ;;
    malformed) printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nfixture 100 10 unknown 10%% /fixture\n'; exit 0 ;;
    fixed) printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nfixture 100 84 16 84%% /fixture\n'; exit 0 ;;
    low) printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nfixture 100 85 15 85%% /fixture\n'; exit 0 ;;
esac
exec "$REAL_DF" "$@"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/du" "$BATS_TEST_TMPDIR/bin/df"
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

@test "#1197: BSD du and df archive the artifact and retain verified bytes" {
    run bash "$SCRIPT" --grimoire grimoires/loa --yes --json
    echo "$output"
    [ "$status" -eq 0 ]
    local archive
    archive=$(echo "$output" | jq -er '.archive_path')
    [ "$(cat "$archive/prd.md")" = "archive me" ]
    [ -f "$archive/.committed" ]
    [ ! -e grimoires/loa/prd.md ]
}

@test "#1197: KiB size and free space use the same byte conversion" {
    export DU_RESULT=fixed DF_RESULT=fixed
    run bash "$SCRIPT" --grimoire grimoires/loa --dry-run --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.would_archive_size_bytes == 8192'
    run bash "$SCRIPT" --grimoire grimoires/loa --yes --json
    echo "$output"
    [ "$status" -eq 0 ]
    [ "$(cat "$(echo "$output" | jq -r .archive_path)/prd.md")" = "archive me" ]
}

@test "#1197: insufficient portable free space preserves the source" {
    export DU_RESULT=fixed DF_RESULT=low
    run bash "$SCRIPT" --grimoire grimoires/loa --yes --json
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Insufficient disk space"* ]]
    [ "$(cat grimoires/loa/prd.md)" = "archive me" ]
}

@test "#1197: failed empty and malformed du results are diagnosed before archiving" {
    local result mode
    for result in fail empty malformed; do
        for mode in --dry-run --yes; do
            run env DU_RESULT="$result" bash "$SCRIPT" --grimoire grimoires/loa "$mode" --json
            echo "$result $mode: $output"
            [ "$status" -eq 1 ]
            [[ "$output" == *"Cannot determine archive size"* ]]
            [[ "$output" != *'"archived": true'* ]]
            [ "$(cat grimoires/loa/prd.md)" = "archive me" ]
        done
    done
}

@test "#1197: failed empty and malformed df results are not reported as low disk space" {
    local result
    for result in fail empty malformed; do
        run env DF_RESULT="$result" bash "$SCRIPT" --grimoire grimoires/loa --yes --json
        echo "$result: $output"
        [ "$status" -eq 1 ]
        [[ "$output" == *"Cannot determine available disk space"* ]]
        [[ "$output" != *"Insufficient disk space"* ]]
        [ "$(cat grimoires/loa/prd.md)" = "archive me" ]
    done
}

@test "#1197: df failure is diagnosed independently of the size scan" {
    run env DF_RESULT=fail bash -c '
        source "$1"
        TOTAL_SIZE=8192
        check_disk_space
    ' _ "$SCRIPT"
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot determine available disk space"* ]]
    [[ "$output" != *"Insufficient disk space"* ]]
}
