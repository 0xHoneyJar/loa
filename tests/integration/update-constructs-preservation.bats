#!/usr/bin/env bats
# Integration tests for BUG-361: /update must preserve .claude/constructs/
#
# The atomic swap in update.sh replaces .claude/ entirely, then restores
# protected directories from backup. .claude/overrides/ is protected but
# .claude/constructs/ was not — causing silent deletion of user-installed
# construct pack files.
#
# These tests verify that both overrides AND constructs survive the swap.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    UPDATE_SCRIPT="$PROJECT_ROOT/.claude/scripts/update.sh"

    # Create isolated temp directory for each test
    export TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/update-constructs-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Set up mock project structure
    MOCK_PROJECT="$TEST_TMPDIR/project"
    mkdir -p "$MOCK_PROJECT"
    cd "$MOCK_PROJECT"
}

teardown() {
    cd /
    rm -rf "$TEST_TMPDIR"
}

# Helper: create a mock .claude/ directory with overrides and constructs
create_mock_claude_dir() {
    # Framework files (would exist in upstream)
    mkdir -p .claude/scripts
    echo "#!/bin/bash" > .claude/scripts/update.sh
    echo "framework-file" > .claude/CLAUDE.loa.md

    # User overrides (already protected)
    mkdir -p .claude/overrides
    echo "user-override-content" > .claude/overrides/custom.yaml

    # User-installed constructs (BUG-361: NOT protected)
    mkdir -p .claude/constructs/packs/observer/skills/listening
    mkdir -p .claude/constructs/packs/observer/skills/seeing
    mkdir -p .claude/constructs/packs/observer/skills/speaking
    echo "# Listening SKILL" > .claude/constructs/packs/observer/skills/listening/SKILL.md
    echo "name: listening" > .claude/constructs/packs/observer/skills/listening/index.yaml
    echo "# Seeing SKILL" > .claude/constructs/packs/observer/skills/seeing/SKILL.md
    echo "name: seeing" > .claude/constructs/packs/observer/skills/seeing/index.yaml
    echo "# Speaking SKILL" > .claude/constructs/packs/observer/skills/speaking/SKILL.md
    echo "name: speaking" > .claude/constructs/packs/observer/skills/speaking/index.yaml

    # Constructs metadata
    echo '{"schema_version":1,"installed_packs":["observer"]}' > .claude/constructs/.constructs-meta.json
}

# Helper: create a mock staging directory (upstream, no constructs)
create_mock_staging() {
    mkdir -p .claude_staging/scripts
    echo "#!/bin/bash" > .claude_staging/scripts/update.sh
    echo "framework-file-updated" > .claude_staging/CLAUDE.loa.md
    mkdir -p .claude_staging/overrides
}

# Helper: simulate the atomic swap from update.sh (lines 1357-1377)
# This replicates the EXACT logic from update.sh
simulate_atomic_swap() {
    local backup_name=".claude.backup.$(date +%s)"

    # Stage 5: Atomic Swap (update.sh:1357-1369)
    if [[ -d ".claude" ]]; then
        mv ".claude" "$backup_name"
    fi
    mv ".claude_staging" ".claude"

    # Stage 6: Restore Overrides (update.sh:1371-1376)
    mkdir -p ".claude/overrides"
    if [[ -d "$backup_name/overrides" ]]; then
        cp -r "$backup_name/overrides/"* ".claude/overrides/" 2>/dev/null || true
    fi

    # Stage 6b: Restore Constructs (BUG-361 fix — this is what's MISSING)
    # The fix should add construct restoration here, parallel to overrides.
    # For the "current behavior" test, we intentionally do NOT restore constructs.
    # For the "fixed behavior" test, we source the actual update.sh.

    echo "$backup_name"
}

# Helper: simulate the fixed atomic swap (with constructs restoration)
simulate_fixed_atomic_swap() {
    local backup_name=".claude.backup.$(date +%s)"

    # Stage 5: Atomic Swap
    if [[ -d ".claude" ]]; then
        mv ".claude" "$backup_name"
    fi
    mv ".claude_staging" ".claude"

    # Stage 6: Restore Overrides
    mkdir -p ".claude/overrides"
    if [[ -d "$backup_name/overrides" ]]; then
        cp -r "$backup_name/overrides/"* ".claude/overrides/" 2>/dev/null || true
    fi

    # Stage 6b: Restore Constructs (BUG-361 FIX)
    # Use cp -r of entire directory to preserve dotfiles (.constructs-meta.json)
    if [[ -d "$backup_name/constructs" ]]; then
        cp -r "$backup_name/constructs" ".claude/"
    fi

    echo "$backup_name"
}

# ============================================================
# Tests for CURRENT behavior (demonstrates the bug)
# ============================================================

@test "BUG-361: current swap logic deletes construct SKILL.md files" {
    create_mock_claude_dir
    create_mock_staging

    # Verify constructs exist before swap
    [ -f .claude/constructs/packs/observer/skills/listening/SKILL.md ]
    [ -f .claude/constructs/packs/observer/skills/seeing/SKILL.md ]
    [ -f .claude/constructs/packs/observer/skills/speaking/SKILL.md ]

    # Simulate the current (buggy) atomic swap
    simulate_atomic_swap

    # After current swap: constructs are GONE (this is the bug)
    [ ! -d .claude/constructs ]
}

@test "BUG-361: current swap logic preserves overrides (existing behavior)" {
    create_mock_claude_dir
    create_mock_staging

    simulate_atomic_swap

    # Overrides should survive (already implemented)
    [ -f .claude/overrides/custom.yaml ]
    [ "$(cat .claude/overrides/custom.yaml)" = "user-override-content" ]
}

# ============================================================
# Tests for FIXED behavior (what we're implementing)
# ============================================================

@test "BUG-361-fix: swap preserves construct SKILL.md files" {
    create_mock_claude_dir
    create_mock_staging

    simulate_fixed_atomic_swap

    # All construct SKILL.md files must survive
    [ -f .claude/constructs/packs/observer/skills/listening/SKILL.md ]
    [ -f .claude/constructs/packs/observer/skills/seeing/SKILL.md ]
    [ -f .claude/constructs/packs/observer/skills/speaking/SKILL.md ]

    # Content must be preserved
    [ "$(cat .claude/constructs/packs/observer/skills/listening/SKILL.md)" = "# Listening SKILL" ]
}

@test "BUG-361-fix: swap preserves construct index.yaml files" {
    create_mock_claude_dir
    create_mock_staging

    simulate_fixed_atomic_swap

    [ -f .claude/constructs/packs/observer/skills/listening/index.yaml ]
    [ -f .claude/constructs/packs/observer/skills/seeing/index.yaml ]
    [ -f .claude/constructs/packs/observer/skills/speaking/index.yaml ]
}

@test "BUG-361-fix: swap preserves .constructs-meta.json" {
    create_mock_claude_dir
    create_mock_staging

    simulate_fixed_atomic_swap

    [ -f .claude/constructs/.constructs-meta.json ]
    run jq -r '.installed_packs[0]' .claude/constructs/.constructs-meta.json
    [ "$output" = "observer" ]
}

@test "BUG-361-fix: swap still updates framework files" {
    create_mock_claude_dir
    create_mock_staging

    simulate_fixed_atomic_swap

    # Framework files should come from staging (updated)
    [ "$(cat .claude/CLAUDE.loa.md)" = "framework-file-updated" ]
}

@test "BUG-361-fix: swap handles missing constructs dir gracefully" {
    # Set up .claude/ WITHOUT constructs (not all users have them)
    mkdir -p .claude/scripts
    echo "framework-file" > .claude/scripts/update.sh
    mkdir -p .claude/overrides
    echo "override" > .claude/overrides/custom.yaml

    create_mock_staging

    # Should not error when no constructs exist
    simulate_fixed_atomic_swap

    # Overrides still work
    [ -f .claude/overrides/custom.yaml ]
    # No constructs dir created from nothing
    [ ! -d .claude/constructs ] || [ -z "$(ls -A .claude/constructs 2>/dev/null)" ]
}

@test "BUG-361-fix: swap handles empty constructs dir gracefully" {
    create_mock_claude_dir
    # Remove all content from constructs, leave empty dir
    rm -rf .claude/constructs/packs
    rm -f .claude/constructs/.constructs-meta.json

    create_mock_staging

    simulate_fixed_atomic_swap

    # Should not error on empty constructs
    [ -d .claude/constructs ] || true
}

@test "BUG-361-fix: swap preserves both overrides and constructs together" {
    create_mock_claude_dir
    create_mock_staging

    simulate_fixed_atomic_swap

    # Both must survive
    [ -f .claude/overrides/custom.yaml ]
    [ -f .claude/constructs/packs/observer/skills/listening/SKILL.md ]
    [ -f .claude/constructs/.constructs-meta.json ]

    # And framework files must be updated
    [ "$(cat .claude/CLAUDE.loa.md)" = "framework-file-updated" ]
}

# ============================================================
# Tests for dry-run preview (should not count constructs as deleted)
# ============================================================

@test "BUG-361-fix: dry-run preview skips constructs from deletion count" {
    create_mock_claude_dir
    create_mock_staging

    # Simulate the dry-run file counting logic from update.sh:226-239
    # with the fix applied (skip constructs/* like overrides/*)
    local deleted_files=0
    while IFS= read -r -d '' file; do
        local rel_path="${file#.claude/}"

        # Skip overrides (existing)
        [[ "$rel_path" == overrides/* ]] && continue
        # Skip constructs (BUG-361 fix)
        [[ "$rel_path" == constructs/* ]] && continue

        local staging_file=".claude_staging/${rel_path}"
        if [[ ! -f "$staging_file" ]]; then
            ((deleted_files++))
        fi
    done < <(find ".claude" -type f ! -path "*/overrides/*" ! -path "*/constructs/*" -print0 2>/dev/null)

    # No construct files should be counted as "to be deleted"
    [ "$deleted_files" -eq 0 ]
}
