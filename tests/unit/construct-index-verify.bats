#!/usr/bin/env bats
# =============================================================================
# construct-index-verify.bats — Tests for construct-index-verify.sh
# =============================================================================
# The coherence guard: every installed schema-bearing pack must appear in the index.
# Catches the regression where the generator silently drops packs (the v4
# construct.yaml-only blindness that hid euler/noether/saaty from resolve).

setup() {
    export BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    GEN="$PROJECT_ROOT/.claude/scripts/construct-index-gen.sh"
    VERIFY="$PROJECT_ROOT/.claude/scripts/construct-index-verify.sh"

    export TEST_TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    export TEST_PACKS_DIR="$TEST_TMPDIR/packs"
    export TEST_INDEX="$TEST_TMPDIR/run/construct-index.yaml"
    mkdir -p "$TEST_PACKS_DIR" "$TEST_TMPDIR/run"
    export LOA_PACKS_DIR="$TEST_PACKS_DIR"
    export CONSTRUCT_INDEX_PATH="$TEST_INDEX"
}
teardown() { rm -rf "$TEST_TMPDIR" 2>/dev/null || true; }

mk_manifest_pack() {   # $1=slug — legacy manifest.json pack
    mkdir -p "$TEST_PACKS_DIR/$1"
    printf '{"name":"%s","slug":"%s","version":"1.0.0"}' "$1" "$1" > "$TEST_PACKS_DIR/$1/manifest.json"
}
mk_yaml_pack() {       # $1=slug — v4 construct.yaml-only pack
    mkdir -p "$TEST_PACKS_DIR/$1"
    printf 'name: %s\nversion: 4.0.0\n' "$1" > "$TEST_PACKS_DIR/$1/construct.yaml"
}
gen_index() { PROJECT_ROOT="$TEST_TMPDIR" LOA_PACKS_DIR="$TEST_PACKS_DIR" "$GEN" --output "$TEST_INDEX" --quiet; }

@test "V1: index covering all packs (manifest + v4) is coherent (exit 0)" {
    mk_manifest_pack "alpha"
    mk_yaml_pack "beta"          # v4 pack — only indexed because of the gate fix
    gen_index
    run "$VERIFY" --quiet
    [ "$status" -eq 0 ]
}

@test "V2: a schema-bearing pack absent from the index is DRIFT (exit 1)" {
    mk_manifest_pack "alpha"
    gen_index                    # index has only alpha
    mk_yaml_pack "gamma"         # gamma installed AFTER generation -> index is blind to it
    run "$VERIFY" --quiet
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "gamma"
}

@test "V3: missing packs dir is vacuously coherent (exit 0)" {
    mk_manifest_pack "alpha"
    gen_index
    rm -rf "$TEST_PACKS_DIR"
    run "$VERIFY" --quiet
    [ "$status" -eq 0 ]
}

@test "V4: missing index is an environment error (exit 3)" {
    mk_manifest_pack "alpha"
    rm -f "$TEST_INDEX"
    run "$VERIFY" --quiet
    [ "$status" -eq 3 ]
}
