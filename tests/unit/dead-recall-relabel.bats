#!/usr/bin/env bats
# cycle-115 D2 relabeled the dead semantic-memory recall pipeline EXPERIMENTAL.
# cycle-121 sprint-3 DELETED the subsystem outright (approved: review r1+r2,
# audit) — these tests now pin the deletion's documentation contract instead
# of the relabel markers (whose subject files/sections no longer exist).

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    MEMORY_REF="$PROJECT_ROOT/.claude/loa/reference/memory-reference.md"
    REC_HOOKS="$PROJECT_ROOT/.claude/protocols/recommended-hooks.md"
    HOOKS_README="$PROJECT_ROOT/.claude/hooks/README.md"
}

@test "memory-reference.md is deleted (subsystem removed cycle-121)" {
    [ ! -f "$MEMORY_REF" ]
}

@test "no memory subsystem scripts remain" {
    for s in memory-query memory-admin memory-bootstrap memory-setup memory-sync; do
        [ ! -f "$PROJECT_ROOT/.claude/scripts/${s}.sh" ]
    done
    [ ! -f "$PROJECT_ROOT/.claude/hooks/memory-inject.sh" ]
    [ ! -f "$PROJECT_ROOT/.claude/hooks/memory-writer.sh" ]
}

@test "recommended-hooks.md section 4 documents the deletion (anchor-stable stub)" {
    grep -q "### 4. Memory Injection Hook" "$REC_HOOKS"
    grep -q "auto-memory owns cross-session recall" "$REC_HOOKS"
}

@test "hooks/README.md carries no memory hook rows" {
    ! grep -qE '\| `memory-(writer|inject)\.sh`' "$HOOKS_README"
}

@test "no live references to the deleted subsystem in agent-context surfaces" {
    run grep -rlE "memory-query|memory-inject|memory-writer|observations\.jsonl" \
        "$PROJECT_ROOT/.claude" "$PROJECT_ROOT/CLAUDE.md" "$PROJECT_ROOT/README.md" \
        --exclude=checksums.json --exclude-dir=node_modules --exclude-dir=__pycache__
    [ "$status" -ne 0 ]
}

@test "the migrated observation survives in lore" {
    grep -q "tertiary-skeptic-load-bearing" "$PROJECT_ROOT/grimoires/loa/lore/patterns.yaml"
}
