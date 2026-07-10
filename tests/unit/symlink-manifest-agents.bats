#!/usr/bin/env bats
# =============================================================================
# Cycle-119 C12/A6 — .claude/agents/ must be manifest-covered like skills/
# commands so mount-submodule.sh / mount-loa.sh / loa-eject.sh cannot drift
# (the same class of gap a prior scout flagged for MANIFEST_CONSTRUCT_SYMLINKS
# being absent from some consumer loops — do not repeat that drift for
# agents: this test asserts all three consumers iterate the new array).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MANIFEST="$REPO_ROOT/.claude/scripts/lib/symlink-manifest.sh"
    MOUNT_SUBMODULE="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    MOUNT_LOA="$REPO_ROOT/.claude/scripts/mount-loa.sh"
    EJECT="$REPO_ROOT/.claude/scripts/loa-eject.sh"
    [[ -f "$MANIFEST" ]] || skip "symlink-manifest.sh not found"
}

@test "get_symlink_manifest populates MANIFEST_AGENT_SYMLINKS from submodule .claude/agents" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/.loa/.claude/agents"
    echo "---" > "$tmpdir/.loa/.claude/agents/loa-scout.md"

    run bash -c "
        source '$MANIFEST'
        get_symlink_manifest '.loa' '$tmpdir'
        printf '%s\n' \"\${MANIFEST_AGENT_SYMLINKS[@]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *".claude/agents/loa-scout.md:../../.loa/.claude/agents/loa-scout.md"* ]]

    rm -rf "$tmpdir"
}

@test "get_all_manifest_entries includes MANIFEST_AGENT_SYMLINKS entries" {
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/.loa/.claude/agents"
    echo "---" > "$tmpdir/.loa/.claude/agents/loa-scout.md"

    run bash -c "
        source '$MANIFEST'
        get_all_manifest_entries '.loa' '$tmpdir'
        printf '%s\n' \"\${ALL_MANIFEST_ENTRIES[@]}\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *".claude/agents/loa-scout.md:"* ]]

    rm -rf "$tmpdir"
}

@test "mount-submodule.sh create_symlinks iterates MANIFEST_AGENT_SYMLINKS" {
    [[ -f "$MOUNT_SUBMODULE" ]] || skip "mount-submodule.sh not found"
    grep -qE 'MANIFEST_AGENT_SYMLINKS\[@\]' "$MOUNT_SUBMODULE" \
        || { echo "REGRESSION: mount-submodule.sh does not consume MANIFEST_AGENT_SYMLINKS" >&2; return 1; }
}

@test "mount-loa.sh migrate loop iterates MANIFEST_AGENT_SYMLINKS" {
    [[ -f "$MOUNT_LOA" ]] || skip "mount-loa.sh not found"
    grep -qE 'MANIFEST_AGENT_SYMLINKS\[@\]' "$MOUNT_LOA" \
        || { echo "REGRESSION: mount-loa.sh does not consume MANIFEST_AGENT_SYMLINKS" >&2; return 1; }
}

@test "loa-eject.sh eject loop iterates MANIFEST_AGENT_SYMLINKS" {
    [[ -f "$EJECT" ]] || skip "loa-eject.sh not found"
    grep -qE 'MANIFEST_AGENT_SYMLINKS\[@\]' "$EJECT" \
        || { echo "REGRESSION: loa-eject.sh does not consume MANIFEST_AGENT_SYMLINKS" >&2; return 1; }
}

@test ".claude/agents (loa-scout) exists so the manifest has real content to cover" {
    [[ -f "$REPO_ROOT/.claude/agents/loa-scout.md" ]] \
        || { echo "loa-scout.md missing — manifest coverage test would be vacuous" >&2; return 1; }
}
