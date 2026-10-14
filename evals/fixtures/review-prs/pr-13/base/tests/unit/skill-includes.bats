#!/usr/bin/env bats
# cycle-121: generated skill-include blocks — drift detection + idempotence.
# Round-2 (dissenter DISS-001/DISS-002): every MUTATING invocation runs against
# a fixture tree under $BATS_TMPDIR via --root; PROJECT_ROOT stays read-only.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    GEN="$PROJECT_ROOT/.claude/scripts/generate-skill-includes.sh"
    FIX="$(mktemp -d "$BATS_TMPDIR/skill-includes-XXXXXX")"
    mkdir -p "$FIX/.claude/data" "$FIX/.claude/skills"
    cp -r "$PROJECT_ROOT/.claude/data/skill-includes" "$FIX/.claude/data/"
    mkdir -p "$FIX/.claude/skills/implementing-tasks"
    cp "$PROJECT_ROOT/.claude/skills/implementing-tasks/SKILL.md" "$FIX/.claude/skills/implementing-tasks/SKILL.md"
}

teardown() { rm -rf "$FIX"; }

@test "skill-includes: --check passes on the real tree (read-only)" {
    run bash "$GEN" --check
    [ "$status" -eq 0 ]
}

@test "skill-includes: --check passes on a clean fixture" {
    run bash "$GEN" --check --root "$FIX"
    [ "$status" -eq 0 ]
}

@test "skill-includes: --write is idempotent on a clean fixture (0 rewrites)" {
    run bash "$GEN" --write --root "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 block(s) rewritten"* ]]
}

@test "skill-includes: --check FAILS with DRIFT message when a generated block is edited in place (fixture tamper)" {
    sed -i 's/Follow `.claude\/protocols\/tool-result-clearing.md`/Follow NOTHING/' "$FIX/.claude/skills/implementing-tasks/SKILL.md"
    run bash "$GEN" --check --root "$FIX"
    [ "$status" -ne 0 ]
    [[ "$output" == *"DRIFT DETECTED"* ]]
}

@test "skill-includes: --write REPAIRS a tampered fixture block back to the canonical rendering" {
    sed -i 's/Follow `.claude\/protocols\/tool-result-clearing.md`/Follow NOTHING/' "$FIX/.claude/skills/implementing-tasks/SKILL.md"
    run bash "$GEN" --write --root "$FIX"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 block(s) rewritten"* ]]
    run bash "$GEN" --check --root "$FIX"
    [ "$status" -eq 0 ]
    grep -q 'Follow `.claude/protocols/tool-result-clearing.md`' "$FIX/.claude/skills/implementing-tasks/SKILL.md"
}

@test "skill-includes: fixture mutations never touch the real tree" {
    before="$(md5sum "$PROJECT_ROOT/.claude/skills/implementing-tasks/SKILL.md")"
    sed -i 's/## Context Discipline/## TAMPERED/' "$FIX/.claude/skills/implementing-tasks/SKILL.md"
    run bash "$GEN" --write --root "$FIX"
    after="$(md5sum "$PROJECT_ROOT/.claude/skills/implementing-tasks/SKILL.md")"
    [ "$before" = "$after" ]
}

@test "skill-includes: every source file is consumed by at least one marker (real tree, read-only)" {
    for src in "$PROJECT_ROOT"/.claude/data/skill-includes/*.md; do
        name="$(basename "$src" .md)"
        grep -rq "@skill-include: start $name" "$PROJECT_ROOT/.claude/skills/" || {
            echo "orphan source: $name"; return 1; }
    done
}
