#!/usr/bin/env bats
# =============================================================================
# bug-989-kernel-hash-stamp.bats — issue #989: @loa-managed hash is a hollow
# PLACEHOLDER that nothing stamps or verifies.
# =============================================================================
# Pre-fix defects pinned here:
#   1. marker-utils.sh update_hash sed class [a-f0-9]* cannot consume the
#      literal PLACEHOLDER suffix -> new hash gets glued to "PLACEHOLDER".
#   2. update-loa-bump-version.sh bump_claude_loa_header rewrites version only
#      and documents preserving the placeholder hash.
#   3. lint-invariants.sh check_claude_md checks header PRESENCE only.
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export MARKER_UTILS="$PROJECT_ROOT/.claude/scripts/marker-utils.sh"
    export BUMP_SCRIPT="$PROJECT_ROOT/.claude/scripts/update-loa-bump-version.sh"
    export LINT_SCRIPT="$PROJECT_ROOT/.claude/scripts/lint-invariants.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/hash-stamp"
    mkdir -p "$TEST_DIR/.claude/loa"

    export VERSION_FILE="$TEST_DIR/.loa-version.json"
    export CLAUDE_LOA_FILE="$TEST_DIR/.claude/loa/CLAUDE.loa.md"

    cat > "$VERSION_FILE" <<'EOF'
{
  "framework_version": "1.0.0",
  "schema_version": 2,
  "zones": {"system": ".claude", "state": ["grimoires"], "app": ["src"]},
  "migrations_applied": [],
  "integrity": {"enforcement": "warn"},
  "dependencies": {}
}
EOF

    cat > "$CLAUDE_LOA_FILE" <<'EOF'
<!-- @loa-managed: true | version: 1.0.0 | hash: abc123PLACEHOLDER -->
<!-- WARNING: This file is managed by the Loa Framework. Do not edit directly. -->

# Loa Framework Instructions

Content...
EOF
}

teardown() {
    # bats handles BATS_TEST_TMPDIR cleanup; nothing to do
    :
}

@test "bug-989: update-hash drops the PLACEHOLDER suffix and stamps a bare 64-hex hash" {
    run bash "$MARKER_UTILS" update-hash "$CLAUDE_LOA_FILE"
    [ "$status" -eq 0 ]
    local line1
    line1=$(head -1 "$CLAUDE_LOA_FILE")
    [[ "$line1" != *"PLACEHOLDER"* ]]
    [[ "$line1" =~ hash:\ [a-f0-9]{64} ]]
}

@test "bug-989: update-hash -> verify-hash roundtrip is VALID; content edit flips to MISMATCH" {
    bash "$MARKER_UTILS" update-hash "$CLAUDE_LOA_FILE"
    run bash "$MARKER_UTILS" verify-hash "$CLAUDE_LOA_FILE"
    [[ "$output" == "VALID" ]]
    echo "drift" >> "$CLAUDE_LOA_FILE"
    run bash "$MARKER_UTILS" verify-hash "$CLAUDE_LOA_FILE"
    [[ "$output" == "MISMATCH" ]]
}

@test "bug-989: bump_claude_loa_header stamps a real hash on version bump" {
    run "$BUMP_SCRIPT" --target "2.0.0"
    [ "$status" -eq 0 ]
    local line1
    line1=$(head -1 "$CLAUDE_LOA_FILE")
    [[ "$line1" == *"version: 2.0.0"* ]]
    [[ "$line1" != *"PLACEHOLDER"* ]]
    run bash "$MARKER_UTILS" verify-hash "$CLAUDE_LOA_FILE"
    [[ "$output" == "VALID" ]]
}

@test "bug-989: idempotency guard — no-op bump leaves file byte-identical" {
    "$BUMP_SCRIPT" --target "2.0.0"
    local before
    before=$(md5sum "$CLAUDE_LOA_FILE" | awk '{print $1}')
    run "$BUMP_SCRIPT" --target "2.0.0"
    [ "$status" -eq 0 ]
    [ "$(md5sum "$CLAUDE_LOA_FILE" | awk '{print $1}')" = "$before" ]
}

@test "bug-989: lint check_claude_md WARNs (never ERRORs) on stale/placeholder hash" {
    cd "$TEST_DIR"
    run bash "$LINT_SCRIPT"
    local claude_lines
    claude_lines=$(echo "$output" | grep -i 'claude-md')
    [[ "$claude_lines" == *"WARN"* ]]
    [[ "$claude_lines" == *"hash"* ]]
}

@test "bug-989: lint check_claude_md PASSes hash check after update-hash" {
    bash "$MARKER_UTILS" update-hash "$CLAUDE_LOA_FILE"
    cd "$TEST_DIR"
    run bash "$LINT_SCRIPT"
    local hash_lines
    hash_lines=$(echo "$output" | grep -i 'claude-md' | grep -i 'hash')
    [[ "$hash_lines" == *"PASS"* ]]
}

@test "bug-989: lint WARNs on glued correct-hex+PLACEHOLDER residue even though verify says VALID (DISS-001)" {
    # Reproduce the OLD update_hash glue state: stamp a real hash, then glue
    # the literal PLACEHOLDER back onto it. verify-hash still reports VALID
    # (hex-prefix comparison), so the residue check must WARN independently.
    bash "$MARKER_UTILS" update-hash "$CLAUDE_LOA_FILE"
    sed -i '1s/\(hash: [a-f0-9]*\)/\1PLACEHOLDER/' "$CLAUDE_LOA_FILE"
    run bash "$MARKER_UTILS" verify-hash "$CLAUDE_LOA_FILE"
    [[ "$output" == "VALID" ]]
    cd "$TEST_DIR"
    run bash "$LINT_SCRIPT"
    local residue_lines
    residue_lines=$(echo "$output" | grep -i 'claude-md' | grep -i 'PLACEHOLDER residue')
    [[ "$residue_lines" == *"WARN"* ]]
}

@test "bug-989: live kernel header carries a real verified hash (no PLACEHOLDER, version != 1.94.0)" {
    local line1
    line1=$(head -1 "$PROJECT_ROOT/.claude/loa/CLAUDE.loa.md")
    [[ "$line1" != *"PLACEHOLDER"* ]]
    [[ "$line1" != *"version: 1.94.0"* ]]
    run bash "$MARKER_UTILS" verify-hash "$PROJECT_ROOT/.claude/loa/CLAUDE.loa.md"
    [[ "$output" == "VALID" ]]
}
