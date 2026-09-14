#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIX="$BATS_TEST_TMPDIR/consumer"
    mkdir -p "$FIX/.loa/.claude/scripts" "$FIX/.claude"
    cp "$REPO_ROOT/.claude/scripts/compat-lib.sh" "$FIX/.loa/.claude/scripts/"
    # Keep the production main and argument routing; replace downstream work
    # with sentinels so a regression cannot fetch, swap files, or commit.
    sed '/^main "\$@"$/d' "$REPO_ROOT/.claude/scripts/update.sh" \
        > "$FIX/.loa/.claude/scripts/update.sh"
    cat >> "$FIX/.loa/.claude/scripts/update.sh" <<'SH'
do_version_check() { echo reached-check >> reached; }
do_list_versions() { echo reached-list >> reached; }
do_rollback() { echo reached-rollback >> reached; }
check_deps() { echo reached-update >> reached; exit 91; }
main "$@"
SH
    ln -s ../.loa/.claude/scripts "$FIX/.claude/scripts"
    printf '{"installation_mode":"submodule"}\n' > "$FIX/.loa-version.json"
    cd "$FIX"
}

assert_refused() {
    run bash .claude/scripts/update.sh "$@"
    echo "$output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"submodule"* && "$output" == *"update-loa.sh"* ]]
    [ ! -e reached ]
    [ -L .claude/scripts ]
    [ "$(readlink .claude/scripts)" = ../.loa/.claude/scripts ]
    [ "$(cat .loa-version.json)" = '{"installation_mode":"submodule"}' ]
    [ ! -e .claude_staging ]
}

@test "#1242: normal update refuses submodule before update work" {
    assert_refused
}

@test "#1242: check refuses submodule before version checks" {
    assert_refused --check --json
}

@test "#1242: dry-run refuses submodule before staging" {
    assert_refused --dry-run
}

@test "#1242: list refuses submodule before listing versions" {
    assert_refused --list --all
}

@test "#1242: force and rollback cannot bypass submodule refusal" {
    assert_refused --force --force-restore --rollback
}

@test "#1242: standard and legacy manifests still reach standard check" {
    for manifest in '{"installation_mode":"standard"}' '{"framework_version":"1.0.0"}'; do
        printf '%s\n' "$manifest" > .loa-version.json
        run bash .claude/scripts/update.sh --check
        [ "$status" -eq 0 ]
        [ "$(cat reached)" = reached-check ]
        rm reached
    done
}

@test "#1242: help remains available on submodule mounts" {
    run bash .claude/scripts/update.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [ ! -e reached ]
}

@test "#1242: unreadable installation metadata cannot fall through to a standard update" {
    printf '{broken\n' > .loa-version.json
    run bash .claude/scripts/update.sh --check
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot determine installation mode"* ]]
    [ ! -e reached ]
}
