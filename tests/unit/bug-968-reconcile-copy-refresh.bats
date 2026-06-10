#!/usr/bin/env bats
# =============================================================================
# bug-968-reconcile-copy-refresh.bats — issue #968: the #842 COPY set
# (.claude/hooks, .claude/settings.json) is refreshed only by a full mount;
# --reconcile and update-loa.sh's submodule path left it stale (macOS:
# stale SYMLINKS — the exact pre-#842 breakage; everywhere: stale content
# after a submodule bump). Also: /update-loa doc had no submodule-mode path.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    UPDATE="$REPO_ROOT/.claude/scripts/update-loa.sh"
    DOC="$REPO_ROOT/.claude/commands/update-loa.md"
    [[ -f "$MOUNT" ]] || skip "mount-submodule.sh not found"

    # Fixture consumer repo with a fake .loa submodule payload
    FIX="$BATS_TEST_TMPDIR/consumer"
    mkdir -p "$FIX/.loa/.claude/hooks" "$FIX/.claude"
    printf '#!/bin/sh\necho NEW\n' > "$FIX/.loa/.claude/hooks/probe.sh"
    printf '{"version": "new"}\n' > "$FIX/.loa/.claude/settings.json"
    (cd "$FIX" && git init -q -b main)
}

# Helper: source the mount script's functions inside the fixture
_in_fixture() {
    cd "$FIX" && SUBMODULE_PATH=".loa" source "$MOUNT" --source-only
}

@test "bug-968: refresh_copy_set function exists and is callable" {
    run bash -c "cd '$FIX' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && type refresh_copy_set"
    [ "$status" -eq 0 ]
}

@test "bug-968: refresh replaces a stale pre-#842 SYMLINK dest with a real copy" {
    ln -s "../.loa/.claude/hooks" "$FIX/.claude/hooks"
    ln -s "../.loa/.claude/settings.json" "$FIX/.claude/settings.json"
    run bash -c "cd '$FIX' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && refresh_copy_set true"
    [ "$status" -eq 0 ]
    [[ ! -L "$FIX/.claude/hooks" ]]
    [[ -d "$FIX/.claude/hooks" ]]
    [[ ! -L "$FIX/.claude/settings.json" ]]
    grep -q NEW "$FIX/.claude/hooks/probe.sh"
}

@test "bug-968: refresh overwrites stale COPY content with current submodule content" {
    mkdir -p "$FIX/.claude/hooks"
    printf '#!/bin/sh\necho OLD\n' > "$FIX/.claude/hooks/probe.sh"
    printf '{"version": "old"}\n' > "$FIX/.claude/settings.json"
    run bash -c "cd '$FIX' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && refresh_copy_set true"
    [ "$status" -eq 0 ]
    grep -q NEW "$FIX/.claude/hooks/probe.sh"
    grep -q new "$FIX/.claude/settings.json"
}

@test "bug-968: missing copy source warns and skips (no failure, no deletion)" {
    rm "$FIX/.loa/.claude/settings.json"
    printf '{"version": "keep"}\n' > "$FIX/.claude/settings.json"
    run bash -c "cd '$FIX' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && refresh_copy_set true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Copy source missing"* ]]
    grep -q keep "$FIX/.claude/settings.json"
}

@test "bug-968: check mode reports stale-symlink dest non-zero without mutating" {
    ln -s "../.loa/.claude/hooks" "$FIX/.claude/hooks"
    run bash -c "cd '$FIX' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && refresh_copy_set false"
    [ "$status" -ne 0 ]
    [[ "$output" == *"COPY-STALE"* ]]
    [[ -L "$FIX/.claude/hooks" ]]
}

@test "bug-968: deletion-surface guard refuses non-.claude destinations" {
    mkdir -p "$FIX/grimoires/evil"
    run bash -c "cd '$FIX' && SUBMODULE_PATH='.loa' source '$MOUNT' --source-only && _refresh_copy_entry true 'grimoires/evil:.loa/.claude/hooks' '$FIX'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing non-.claude destination"* ]]
    [[ -d "$FIX/grimoires/evil" ]]
}

@test "bug-968: --reconcile CLI dispatch invokes the copy refresh" {
    grep -A 8 'RECONCILE_SYMLINKS" == "true"' "$MOUNT" | grep -q 'refresh_copy_set'
}

@test "bug-968: --check-symlinks subcommand reports copy-set state" {
    sed -n '/^check_symlinks_subcommand/,/^}/p' "$MOUNT" | grep -q 'refresh_copy_set "false"'
}

@test "bug-968: update-loa.sh submodule path refreshes the copy set after reconcile" {
    grep -q 'refresh_copy_set' "$UPDATE"
}

@test "bug-968: /update-loa doc has a submodule-mode section routing to update-loa.sh" {
    grep -qi 'submodule' "$DOC"
    grep -q 'update-loa.sh' "$DOC"
}
