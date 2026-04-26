#!/usr/bin/env bats
# =============================================================================
# Tests for .claude/scripts/butterfreezone-construct-gen.sh — cycle-005 L6
# Generates CONSTRUCT-README.md per pack from construct.yaml + skills/ +
# identity/ + CLAUDE.md. Idempotent modulo the optional --timestamp footer.
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/butterfreezone-construct-gen.sh"
    PACK="$BATS_TEST_TMPDIR/test-pack"
    mkdir -p "$PACK"
}

build_pack() {
    cat > "$PACK/construct.yaml" <<'YAML'
schema_version: "1.0.0"
slug: test-pack
name: Test Pack
version: "0.1.0"
description: Pack used for butterfreezone generator unit tests.
short_description: Generator test fixture
author: Tests
license: MIT
personas:
  - ALEXANDER
skills:
  - slug: doing-things
    path: skills/doing-things/
commands:
  - name: do-thing
    path: commands/do-thing.md
reads:
  - Artifact
writes:
  - Verdict
grimoires:
  reads:
    - grimoires/test-pack/in/
  writes:
    - grimoires/test-pack/out/
YAML
    mkdir -p "$PACK/skills/doing-things"
    cat > "$PACK/skills/doing-things/SKILL.md" <<'MD'
---
name: doing-things
description: A skill that does things in service of the test pack.
---
# Doing Things

Body content.
MD
    mkdir -p "$PACK/commands"
    cat > "$PACK/commands/do-thing.md" <<'MD'
---
name: do-thing
description: Run the canonical thing.
---
MD
    mkdir -p "$PACK/identity"
    cat > "$PACK/identity/ALEXANDER.md" <<'MD'
# ALEXANDER

The canonical persona for this test pack.
MD
    cat > "$PACK/CLAUDE.md" <<'MD'
# Test Pack

Reads from grimoires/test-pack/in/
Writes to grimoires/test-pack/out/
MD
}

# -----------------------------------------------------------------------------
# Help / arg validation
# -----------------------------------------------------------------------------
@test "bfz-construct-gen: --help exits 0 and shows usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"butterfreezone-construct-gen"* || "$output" == *"pack-path"* ]]
}

@test "bfz-construct-gen: missing pack path -> exit 1" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "bfz-construct-gen: pack path that doesn't exist -> exit 1" {
    run "$SCRIPT" "$BATS_TEST_TMPDIR/missing"
    [ "$status" -eq 1 ]
    [[ "$output" == *"pack path missing"* ]]
}

@test "bfz-construct-gen: pack path without construct.yaml -> exit 1" {
    run "$SCRIPT" "$PACK"  # empty pack
    [ "$status" -eq 1 ]
    [[ "$output" == *"construct.yaml not found"* ]]
}

@test "bfz-construct-gen: unknown flag -> exit 2" {
    build_pack
    run "$SCRIPT" "$PACK" --bogus
    [ "$status" -eq 2 ]
}

# -----------------------------------------------------------------------------
# Output generation
# -----------------------------------------------------------------------------
@test "bfz-construct-gen: writes CONSTRUCT-README.md by default" {
    build_pack
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 0 ]
    [ -f "$PACK/CONSTRUCT-README.md" ]
}

@test "bfz-construct-gen: --stdout emits to stdout, no file write" {
    build_pack
    run "$SCRIPT" "$PACK" --stdout
    [ "$status" -eq 0 ]
    [ ! -f "$PACK/CONSTRUCT-README.md" ]
    [[ "$output" == *"Test Pack"* ]]
}

@test "bfz-construct-gen: --output PATH writes to custom path" {
    build_pack
    local out="$BATS_TEST_TMPDIR/custom-readme.md"
    run "$SCRIPT" "$PACK" --output "$out"
    [ "$status" -eq 0 ]
    [ -f "$out" ]
    [ ! -f "$PACK/CONSTRUCT-README.md" ]
}

@test "bfz-construct-gen: --dry-run does not write file" {
    build_pack
    run "$SCRIPT" "$PACK" --dry-run
    [ "$status" -eq 0 ]
    [ ! -f "$PACK/CONSTRUCT-README.md" ]
    [[ "$output" == *"would write"* ]]
}

# -----------------------------------------------------------------------------
# Content fidelity — does the README reflect the manifest?
# -----------------------------------------------------------------------------
@test "bfz-construct-gen: README includes pack name + description" {
    build_pack
    "$SCRIPT" "$PACK" >/dev/null
    grep -qF "Test Pack" "$PACK/CONSTRUCT-README.md"
    grep -qF "Pack used for butterfreezone generator unit tests." "$PACK/CONSTRUCT-README.md"
}

@test "bfz-construct-gen: README references each declared skill" {
    build_pack
    "$SCRIPT" "$PACK" >/dev/null
    grep -qF "doing-things" "$PACK/CONSTRUCT-README.md"
}

@test "bfz-construct-gen: README references each declared command" {
    build_pack
    "$SCRIPT" "$PACK" >/dev/null
    grep -qF "do-thing" "$PACK/CONSTRUCT-README.md"
}

@test "bfz-construct-gen: README references persona handle" {
    build_pack
    "$SCRIPT" "$PACK" >/dev/null
    grep -qF "ALEXANDER" "$PACK/CONSTRUCT-README.md"
}

@test "bfz-construct-gen: README declares stream reads/writes" {
    build_pack
    "$SCRIPT" "$PACK" >/dev/null
    grep -qE "Artifact|Verdict" "$PACK/CONSTRUCT-README.md"
}

# -----------------------------------------------------------------------------
# Idempotency — two consecutive runs without --timestamp must produce
# byte-identical output. With --timestamp the only difference must be the
# timestamp line in the footer.
# -----------------------------------------------------------------------------
@test "bfz-construct-gen: two runs without --timestamp produce byte-identical output" {
    build_pack
    "$SCRIPT" "$PACK" --output "$BATS_TEST_TMPDIR/r1.md" >/dev/null
    "$SCRIPT" "$PACK" --output "$BATS_TEST_TMPDIR/r2.md" >/dev/null
    diff -q "$BATS_TEST_TMPDIR/r1.md" "$BATS_TEST_TMPDIR/r2.md"
}

@test "bfz-construct-gen: --timestamp adds a 'Generated at:' line" {
    build_pack
    "$SCRIPT" "$PACK" --timestamp --output "$BATS_TEST_TMPDIR/ts.md" >/dev/null
    grep -qE "^- Generated at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" "$BATS_TEST_TMPDIR/ts.md"
}

@test "bfz-construct-gen: --timestamp difference is confined to the timestamp line" {
    build_pack
    "$SCRIPT" "$PACK" --output "$BATS_TEST_TMPDIR/no-ts.md" >/dev/null
    "$SCRIPT" "$PACK" --timestamp --output "$BATS_TEST_TMPDIR/with-ts.md" >/dev/null
    # Strip the timestamp footer line from the timestamped output and compare.
    grep -v "^- Generated at:" "$BATS_TEST_TMPDIR/with-ts.md" > "$BATS_TEST_TMPDIR/with-ts-stripped.md"
    diff -q "$BATS_TEST_TMPDIR/no-ts.md" "$BATS_TEST_TMPDIR/with-ts-stripped.md"
}
