#!/usr/bin/env bats
# =============================================================================
# cycle-128 sprint-254 audit LOW-003: the framework glossary
# (.claude/loa/GLOSSARY.md) is manifest-covered in submodule mode, and a
# project pinned to an older framework that does not ship it gets a notice and
# no dangling link. get_symlink_manifest adds the entry only when the pinned
# submodule has the file; create, verify, migrate and eject all read that list.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MANIFEST="$REPO_ROOT/.claude/scripts/lib/symlink-manifest.sh"
    MOUNT="$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    [[ -f "$MANIFEST" ]] || skip "symlink-manifest.sh not found"
    FIX="$BATS_TEST_TMPDIR/consumer"
    mkdir -p "$FIX/.loa/.claude/loa"
    echo "# kernel" > "$FIX/.loa/.claude/loa/CLAUDE.loa.md"
}

# manifest_file_entries: the MANIFEST_FILE_SYMLINKS of $FIX, one per line, after
# two calls (the notice must print once per process, not once per call)
manifest_file_entries() {
    run bash -c "
        source '$MANIFEST'
        get_symlink_manifest '.loa' '$FIX'
        get_symlink_manifest '.loa' '$FIX'
        printf '%s\n' \"\${MANIFEST_FILE_SYMLINKS[@]}\"
    "
}

@test "SMG-1 a pinned framework that ships GLOSSARY.md gets the manifest entry and no notice" {
    echo "# Glossary: Loa framework" > "$FIX/.loa/.claude/loa/GLOSSARY.md"
    manifest_file_entries
    [ "$status" -eq 0 ]
    [[ "$output" == *".claude/loa/GLOSSARY.md:../../.loa/.claude/loa/GLOSSARY.md"* ]]
    [[ "$output" != *"NOTICE"* ]]
}

@test "SMG-2 an older pin without GLOSSARY.md gets no entry and exactly one notice" {
    manifest_file_entries
    [ "$status" -eq 0 ]
    [[ "$output" != *".claude/loa/GLOSSARY.md:"* ]]
    [[ "$output" == *".claude/loa/CLAUDE.loa.md:../../.loa/.claude/loa/CLAUDE.loa.md"* ]]
    [ "$(grep -c '^NOTICE: .loa/.claude/loa/GLOSSARY.md is not in the pinned framework version' <<< "$output")" -eq 1 ]
}

@test "SMG-3 the live framework ships GLOSSARY.md, so the manifest entry has real content to cover" {
    [[ -f "$REPO_ROOT/.claude/loa/GLOSSARY.md" ]]
    grep -q '".claude/loa/GLOSSARY.md"' "$MANIFEST"
}

@test "SMG-4 --check-symlinks on an older pin reports no MISSING glossary link; --reconcile creates no dangling one" {
    [[ -f "$MOUNT" ]] || skip "mount-submodule.sh not found"
    (cd "$FIX" && git init -q -b main)
    run bash -c "cd '$FIX' && '$MOUNT' --check-symlinks 2>&1"
    [[ "$output" == *"Verifying"* ]]
    [[ "$output" != *"MISSING: .claude/loa/GLOSSARY.md"* ]]
    [[ "$output" == *"NOTICE: .loa/.claude/loa/GLOSSARY.md is not in the pinned framework version"* ]]
    run bash -c "cd '$FIX' && '$MOUNT' --reconcile 2>&1"
    [ ! -L "$FIX/.claude/loa/GLOSSARY.md" ]
    [ ! -e "$FIX/.claude/loa/GLOSSARY.md" ]
}

@test "SMG-5 on a pin that ships it, --check-symlinks reports the missing glossary link and --reconcile creates a live one" {
    [[ -f "$MOUNT" ]] || skip "mount-submodule.sh not found"
    (cd "$FIX" && git init -q -b main)
    echo "# Glossary: Loa framework" > "$FIX/.loa/.claude/loa/GLOSSARY.md"
    run bash -c "cd '$FIX' && '$MOUNT' --check-symlinks 2>&1"
    [[ "$output" == *"MISSING: .claude/loa/GLOSSARY.md"* ]]
    run bash -c "cd '$FIX' && '$MOUNT' --reconcile 2>&1"
    [ -L "$FIX/.claude/loa/GLOSSARY.md" ]
    [ -e "$FIX/.claude/loa/GLOSSARY.md" ]
    [ "$(head -1 "$FIX/.claude/loa/GLOSSARY.md")" = "# Glossary: Loa framework" ]
}
