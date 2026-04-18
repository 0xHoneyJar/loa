#!/usr/bin/env bats
# =============================================================================
# update-loa-bump.bats — Unit tests for update-loa-bump-version.sh
# =============================================================================
# Sprint-bug-103 (Issue #554). Tests the idempotent version-marker bump
# logic that runs in Phase 5.6 of /update-loa.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export BUMP_SCRIPT="$PROJECT_ROOT/.claude/scripts/update-loa-bump-version.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/bump-test"
    mkdir -p "$TEST_DIR/.claude/loa"

    export VERSION_FILE="$TEST_DIR/.loa-version.json"
    export CLAUDE_LOA_FILE="$TEST_DIR/.claude/loa/CLAUDE.loa.md"

    cat > "$VERSION_FILE" <<'EOF'
{
  "framework_version": "1.0.0",
  "schema_version": 2,
  "last_sync": null,
  "zones": {
    "system": ".claude",
    "state": ["grimoires"],
    "app": ["src"]
  },
  "migrations_applied": ["1.1.0-beads-rust"],
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
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# =========================================================================
# UB-T1: .loa-version.json framework_version is refreshed to target
# =========================================================================

@test "bump writes target framework_version to .loa-version.json" {
    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.framework_version' "$VERSION_FILE")" = "2.5.0" ]
}

# =========================================================================
# UB-T2: .loa-version.json last_sync is set to ISO-8601 UTC timestamp
# =========================================================================

@test "bump sets last_sync to ISO-8601 UTC timestamp" {
    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]
    local sync
    sync=$(jq -r '.last_sync' "$VERSION_FILE")
    [[ "$sync" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# =========================================================================
# UB-T3: Preserves untouched fields (migrations_applied, integrity, zones)
# =========================================================================

@test "bump preserves migrations_applied, integrity, zones, dependencies" {
    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.migrations_applied[0]' "$VERSION_FILE")" = "1.1.0-beads-rust" ]
    [ "$(jq -r '.integrity.enforcement' "$VERSION_FILE")" = "warn" ]
    [ "$(jq -r '.zones.system' "$VERSION_FILE")" = ".claude" ]
    [ "$(jq -r '.schema_version' "$VERSION_FILE")" = "2" ]
}

# =========================================================================
# UB-T4: CLAUDE.loa.md header version field is updated
# =========================================================================

@test "bump rewrites CLAUDE.loa.md header version field" {
    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]
    head -n 1 "$CLAUDE_LOA_FILE" | grep -qF "version: 2.5.0"
}

# =========================================================================
# UB-T5: CLAUDE.loa.md header preserves hash + PLACEHOLDER segments
# =========================================================================

@test "bump preserves hash + PLACEHOLDER in CLAUDE.loa.md header" {
    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]
    local header
    header=$(head -n 1 "$CLAUDE_LOA_FILE")
    [[ "$header" == *"hash: abc123PLACEHOLDER"* ]]
    [[ "$header" == *"@loa-managed: true"* ]]
}

# =========================================================================
# UB-T6: Idempotent re-run is a no-op (no file mutation beyond timestamp)
# =========================================================================

@test "bump is idempotent when already at target" {
    "$BUMP_SCRIPT" --target "2.5.0"
    local first_sync
    first_sync=$(jq -r '.last_sync' "$VERSION_FILE")

    # Second run at same version should not change last_sync (no mutation needed)
    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]
    local second_sync
    second_sync=$(jq -r '.last_sync' "$VERSION_FILE")
    [ "$first_sync" = "$second_sync" ]
}

# =========================================================================
# UB-T7: --dry-run does not mutate files
# =========================================================================

@test "--dry-run does not mutate files" {
    local original_version
    original_version=$(jq -r '.framework_version' "$VERSION_FILE")

    run "$BUMP_SCRIPT" --target "9.9.9" --dry-run
    [ "$status" -eq 0 ]
    [ "$(jq -r '.framework_version' "$VERSION_FILE")" = "$original_version" ]
    head -n 1 "$CLAUDE_LOA_FILE" | grep -qF "version: 1.0.0"
}

# =========================================================================
# UB-T8: Skip silently when .loa-version.json is missing
# =========================================================================

@test "bump skips silently when .loa-version.json missing" {
    rm -f "$VERSION_FILE"
    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]
    [ ! -f "$VERSION_FILE" ]
    # CLAUDE.loa.md should still get bumped
    head -n 1 "$CLAUDE_LOA_FILE" | grep -qF "version: 2.5.0"
}

# =========================================================================
# UB-T9: Skip silently when CLAUDE.loa.md header is not @loa-managed
# =========================================================================

@test "bump skips silently when CLAUDE.loa.md header is not @loa-managed" {
    cat > "$CLAUDE_LOA_FILE" <<'EOF'
# Some user-written file

No managed header here.
EOF
    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]
    # Version file still bumps
    [ "$(jq -r '.framework_version' "$VERSION_FILE")" = "2.5.0" ]
    # CLAUDE.loa.md remains untouched
    head -n 1 "$CLAUDE_LOA_FILE" | grep -qF "Some user-written file"
}

# =========================================================================
# UB-T10: Exit non-zero without --target when FETCH_HEAD is missing
# =========================================================================

@test "exits non-zero when no --target and no FETCH_HEAD" {
    cd "$TEST_DIR"
    run "$BUMP_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not resolve target version"* ]]
}

# =========================================================================
# UB-T11: Short-SHA target (non-semver) is accepted
# =========================================================================

@test "accepts short-SHA format as valid target" {
    run "$BUMP_SCRIPT" --target "c258c4af"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.framework_version' "$VERSION_FILE")" = "c258c4af" ]
    head -n 1 "$CLAUDE_LOA_FILE" | grep -qF "version: c258c4af"
}

# =========================================================================
# UB-T12: --target without value exits 2 with clear error (DISS-002)
# =========================================================================
# Addresses Phase 2.5 advisory: arg parsing did not guard `$2` access under
# `set -u`, producing unbound-variable errors instead of usage errors.

@test "--target without a value exits 2 with clear error" {
    run "$BUMP_SCRIPT" --target
    [ "$status" -eq 2 ]
    [[ "$output" == *"--target requires a value"* ]]
}

# =========================================================================
# UB-T13: --target rejects malicious/malformed version strings (audit DISS-002)
# =========================================================================
# A malicious upstream tag like "1.0.0 --> injected content" must not be
# written into the managed instruction-file header without validation.

@test "--target rejects injection-shaped target" {
    run "$BUMP_SCRIPT" --target "1.0.0 --> <!-- injected"
    [ "$status" -eq 3 ]
    [[ "$output" == *"failed validation"* ]]
    # Files should remain unmodified
    [ "$(jq -r '.framework_version' "$VERSION_FILE")" = "1.0.0" ]
}

@test "--target rejects empty-ish garbage" {
    run "$BUMP_SCRIPT" --target "not-a-version"
    [ "$status" -eq 3 ]
    [[ "$output" == *"failed validation"* ]]
}

@test "--target accepts pre-release semver" {
    run "$BUMP_SCRIPT" --target "2.5.0-rc1"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.framework_version' "$VERSION_FILE")" = "2.5.0-rc1" ]
}

@test "--target accepts semver with build metadata" {
    run "$BUMP_SCRIPT" --target "2.5.0+build.5"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.framework_version' "$VERSION_FILE")" = "2.5.0+build.5" ]
}

# =========================================================================
# UB-T17..UB-T22: Lock down validation regex boundary (Bridgebuilder F5)
# =========================================================================
# Per Bridgebuilder kaironic review: "When untrusted input is written into
# a structured document (markdown, YAML, JSON), the test corpus should
# mirror the document's escape sequences — for markdown headers, that's
# newlines and comment terminators."

@test "--target rejects embedded newline" {
    run "$BUMP_SCRIPT" --target $'1.0.0\n<!-- injected'
    [ "$status" -eq 3 ]
    [[ "$output" == *"failed validation"* ]]
}

@test "--target rejects HTML comment terminator" {
    run "$BUMP_SCRIPT" --target "1.0.0 -->"
    [ "$status" -eq 3 ]
}

@test "--target rejects shell command substitution" {
    run "$BUMP_SCRIPT" --target '1.0.0$(echo hi)'
    [ "$status" -eq 3 ]
}

@test "--target rejects leading whitespace" {
    run "$BUMP_SCRIPT" --target " 1.0.0"
    [ "$status" -eq 3 ]
}

@test "--target rejects 6-char hex (below min SHA length)" {
    run "$BUMP_SCRIPT" --target "abc123"
    [ "$status" -eq 3 ]
}

@test "--target accepts 40-char full SHA" {
    run "$BUMP_SCRIPT" --target "1234567890abcdef1234567890abcdef12345678"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.framework_version' "$VERSION_FILE")" = "1234567890abcdef1234567890abcdef12345678" ]
}

# =========================================================================
# UB-T23: Idempotency — CLAUDE.loa.md untouched on second identical run
# =========================================================================
# Addresses Bridgebuilder low-idempotency-check-incomplete: idempotency
# should mean "leaves no footprints" (no mtime churn for build systems).

@test "idempotent bump does not rewrite CLAUDE.loa.md content unchanged" {
    "$BUMP_SCRIPT" --target "2.5.0"
    local checksum_before
    checksum_before=$(md5sum "$CLAUDE_LOA_FILE" | awk '{print $1}')

    run "$BUMP_SCRIPT" --target "2.5.0"
    [ "$status" -eq 0 ]

    local checksum_after
    checksum_after=$(md5sum "$CLAUDE_LOA_FILE" | awk '{print $1}')
    [ "$checksum_before" = "$checksum_after" ]
}
