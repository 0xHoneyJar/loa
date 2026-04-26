#!/usr/bin/env bats
# =============================================================================
# Tests for .claude/scripts/construct-validate.sh — cycle-006 manifest linter
# Each test builds a minimal fixture pack in $BATS_TEST_TMPDIR and asserts the
# validator's exit code, output severity, and JSON shape.
# =============================================================================

setup_file() {
    # Bridgebuilder F-001: skip with a clear reason when external tooling is
    # missing, so CI distinguishes "skipped: <tool> missing" from a real
    # regression. construct-validate.sh requires both yq and jq.
    command -v yq >/dev/null 2>&1 || skip "yq required (the script under test depends on it)"
    command -v jq >/dev/null 2>&1 || skip "jq required (the script under test depends on it)"
}

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/construct-validate.sh"
    PACK="$BATS_TEST_TMPDIR/test-pack"
    mkdir -p "$PACK"
}

# --- helpers ---------------------------------------------------------------

# Build a minimal happy-path pack at $PACK with all checks satisfied.
build_clean_pack() {
    cat > "$PACK/construct.yaml" <<'YAML'
schema_version: "1.0.0"
slug: test-pack
name: Test Pack
version: "0.1.0"
description: Minimal pack used for validator unit tests.
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
YAML
    mkdir -p "$PACK/skills/doing-things"
    : > "$PACK/skills/doing-things/SKILL.md"
    mkdir -p "$PACK/commands"
    : > "$PACK/commands/do-thing.md"
    cat > "$PACK/CLAUDE.md" <<'MD'
# Test Pack

Reads from grimoires/test-pack/in/
Writes to grimoires/test-pack/out/
MD
}

# -----------------------------------------------------------------------------
# Help / usage
# -----------------------------------------------------------------------------
@test "construct-validate: --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"construct-validate"* ]]
}

@test "construct-validate: missing pack argument -> exit 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "construct-validate: pack path that does not exist -> exit 2" {
    run "$SCRIPT" "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "construct-validate: unknown flag -> exit 2" {
    build_clean_pack
    run "$SCRIPT" "$PACK" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown flag"* ]]
}

# -----------------------------------------------------------------------------
# Critical: missing or unparseable construct.yaml
# -----------------------------------------------------------------------------
@test "construct-validate: missing construct.yaml -> critical, exit 1" {
    # Empty pack (no construct.yaml)
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"critical"* ]]
    [[ "$output" == *"construct.yaml"* ]]
}

@test "construct-validate: malformed construct.yaml -> critical, exit 1" {
    printf 'this is :: not valid yaml ::\n  - [\n' > "$PACK/construct.yaml"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"critical"* ]]
}

# -----------------------------------------------------------------------------
# High: required fields, broken paths
# -----------------------------------------------------------------------------
@test "construct-validate: missing required field 'slug' -> high, exit 1" {
    build_clean_pack
    # Strip slug
    yq -i 'del(.slug)' "$PACK/construct.yaml"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"high"* ]]
    [[ "$output" == *"slug"* ]]
}

@test "construct-validate: missing required field 'description' -> high, exit 1" {
    build_clean_pack
    yq -i 'del(.description)' "$PACK/construct.yaml"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"description"* ]]
}

@test "construct-validate: skills[].path that doesn't resolve -> high, exit 1" {
    build_clean_pack
    rm -rf "$PACK/skills/doing-things"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"skill_path"* ]]
}

@test "construct-validate: commands[].path that doesn't resolve -> high, exit 1" {
    build_clean_pack
    rm -f "$PACK/commands/do-thing.md"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"command_path"* ]]
}

# -----------------------------------------------------------------------------
# Medium: route declaration gap (no commands AND no personas)
# -----------------------------------------------------------------------------
@test "construct-validate: no commands + no personas -> medium route warning" {
    build_clean_pack
    # Strip commands; ensure no personas exist.
    yq -i 'del(.commands)' "$PACK/construct.yaml"
    rm -rf "$PACK/commands"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 0 ]   # MEDIUM is advisory by default
    [[ "$output" == *"route_declared"* ]]
    [[ "$output" == *"medium"* ]]
}

@test "construct-validate: no commands + no personas + --strict -> exit 1" {
    build_clean_pack
    yq -i 'del(.commands)' "$PACK/construct.yaml"
    rm -rf "$PACK/commands"
    run "$SCRIPT" "$PACK" --strict
    [ "$status" -eq 1 ]
}

@test "construct-validate: no commands but persona via identity/HANDLE.md -> route OK" {
    build_clean_pack
    yq -i 'del(.commands)' "$PACK/construct.yaml"
    rm -rf "$PACK/commands"
    mkdir -p "$PACK/identity"
    : > "$PACK/identity/ALEXANDER.md"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"route_declared"* ]]
}

@test "construct-validate: no commands but personas: list -> route OK" {
    build_clean_pack
    yq -i 'del(.commands) | .personas = ["ALEXANDER"]' "$PACK/construct.yaml"
    rm -rf "$PACK/commands"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"route_declared"* ]]
}

# -----------------------------------------------------------------------------
# Medium: §12 grimoires-section convention on CLAUDE.md
# -----------------------------------------------------------------------------
@test "construct-validate: CLAUDE.md without grimoires/ ref -> medium grimoires_section" {
    build_clean_pack
    cat > "$PACK/CLAUDE.md" <<'MD'
# Test Pack

This pack does not declare any grimoire interactions.
MD
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"grimoires_section"* ]]
    [[ "$output" == *"medium"* ]]
}

@test "construct-validate: CLAUDE.md with grimoires/ but no read/write declaration -> medium" {
    build_clean_pack
    cat > "$PACK/CLAUDE.md" <<'MD'
# Test Pack

Some prose mentioning grimoires/test-pack/ without saying read or write.
MD
    run "$SCRIPT" "$PACK"
    [[ "$output" == *"grimoires_section"* ]]
}

@test "construct-validate: missing CLAUDE.md -> medium claude_md finding" {
    build_clean_pack
    rm -f "$PACK/CLAUDE.md"
    run "$SCRIPT" "$PACK"
    [[ "$output" == *"claude_md"* ]]
    [[ "$output" == *"missing CLAUDE.md"* ]]
}

# -----------------------------------------------------------------------------
# Low: stream declarations
# -----------------------------------------------------------------------------
@test "construct-validate: empty reads: array -> low streams" {
    build_clean_pack
    yq -i '.reads = []' "$PACK/construct.yaml"
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"streams"* ]]
    [[ "$output" == *"low"* ]]
}

# -----------------------------------------------------------------------------
# Happy path
# -----------------------------------------------------------------------------
@test "construct-validate: clean pack -> all checks passed, exit 0" {
    build_clean_pack
    run "$SCRIPT" "$PACK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"all checks passed"* ]]
}

# -----------------------------------------------------------------------------
# JSON output shape
# -----------------------------------------------------------------------------
@test "construct-validate: --json on clean pack emits empty array" {
    build_clean_pack
    run "$SCRIPT" "$PACK" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'type == "array" and length == 0' >/dev/null
}

@test "construct-validate: --json findings conform to Verdict schema shape" {
    build_clean_pack
    yq -i 'del(.slug)' "$PACK/construct.yaml"
    run "$SCRIPT" "$PACK" --json
    [ "$status" -eq 1 ]
    # Each finding row has the Verdict-stream shape
    echo "$output" | jq -e '
        type == "array"
        and length > 0
        and (.[0] | (
            .stream_type == "Verdict"
            and (.severity | IN("critical","high","medium","low"))
            and (.verdict | type == "string")
            and (.evidence | type == "array")
            and (.tags | type == "array")
            and (.subject | type == "string")
        ))
    ' >/dev/null
}

@test "construct-validate: --json finding for missing-slug carries the field name in the message" {
    build_clean_pack
    yq -i 'del(.slug)' "$PACK/construct.yaml"
    run "$SCRIPT" "$PACK" --json
    echo "$output" | jq -e '[.[] | select(.tags[]? == "required_field" and (.verdict | contains("slug")))] | length >= 1' >/dev/null
}

# -----------------------------------------------------------------------------
# --strict promotion of MEDIUM to blocking
# -----------------------------------------------------------------------------
@test "construct-validate: clean pack with --strict still passes" {
    build_clean_pack
    run "$SCRIPT" "$PACK" --strict
    [ "$status" -eq 0 ]
}
