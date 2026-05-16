#!/usr/bin/env bats
# =============================================================================
# bb-dist-drift-gate.bats — cycle-104 Sprint 1 T1.8 — AC-1.5 + AC-1.6
# =============================================================================
# Pins the BB dist build hygiene drift gate behavior (T1.4 deliverable).
#
# Tests the four documented outcomes from `tools/check-bb-dist-fresh.sh`:
#   1. manifest_missing — no manifest in dist/ (CI fails)
#   2. manifest_malformed — manifest lacks source_hash (CI fails)
#   3. fresh — source matches manifest hash (CI passes)
#   4. stale — source has diverged from manifest hash (CI fails)
#
# Uses a hermetic copy of `tools/check-bb-dist-fresh.sh` re-rooted at a
# mktemp dir so the project's actual .claude/skills/bridgebuilder-review/
# is never touched.
# =============================================================================

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    export REAL_SCRIPT="$PROJECT_ROOT/tools/check-bb-dist-fresh.sh"

    [[ -x "$REAL_SCRIPT" ]] || skip "check-bb-dist-fresh.sh not found"

    export WORKDIR
    WORKDIR="$(mktemp -d)"
    mkdir -p "$WORKDIR/tools"
    mkdir -p "$WORKDIR/.claude/skills/bridgebuilder-review/resources"
    mkdir -p "$WORKDIR/.claude/skills/bridgebuilder-review/dist"

    # Re-root the script in the hermetic tree by computing PROJECT_ROOT from
    # SCRIPT_DIR/.. (which is how the real script computes it).
    cp "$REAL_SCRIPT" "$WORKDIR/tools/check-bb-dist-fresh.sh"
    chmod +x "$WORKDIR/tools/check-bb-dist-fresh.sh"
    export SCRIPT="$WORKDIR/tools/check-bb-dist-fresh.sh"

    # Seed some source files
    echo "// source A" > "$WORKDIR/.claude/skills/bridgebuilder-review/resources/a.ts"
    echo "// source B" > "$WORKDIR/.claude/skills/bridgebuilder-review/resources/b.ts"

    cd "$WORKDIR"
}

teardown() {
    [[ -n "${WORKDIR:-}" ]] && [[ -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
}

# -------- AC-1.5: positive control + negative controls --------

@test "AC-1.5: manifest missing → check fails with manifest_missing outcome" {
    run "$SCRIPT" --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.outcome == "manifest_missing"'
}

@test "AC-1.5: write-manifest produces a fresh outcome on subsequent check" {
    run "$SCRIPT" --write-manifest --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.outcome == "manifest_written"'

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.outcome == "fresh"'
}

@test "AC-1.5: source drift after manifest write → stale outcome" {
    "$SCRIPT" --write-manifest >/dev/null

    # Modify source
    echo "// drift" >> "$WORKDIR/.claude/skills/bridgebuilder-review/resources/a.ts"

    run "$SCRIPT" --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.outcome == "stale"'
    echo "$output" | jq -e '.committed_source_hash != .current_source_hash'
}

@test "AC-1.5: malformed manifest (missing source_hash) → check fails" {
    "$SCRIPT" --write-manifest >/dev/null
    # Corrupt the manifest
    echo '{"version": "1.0"}' > "$WORKDIR/.claude/skills/bridgebuilder-review/dist/.build-manifest.json"

    run "$SCRIPT" --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.outcome == "manifest_malformed"'
}

# -------- AC-1.6: content-hash (not timestamp) — touch alone doesn't trigger --------

@test "AC-1.6: touching source file without changing content does NOT trigger drift" {
    "$SCRIPT" --write-manifest >/dev/null

    # Touch (mtime change) but no content change
    touch -d '2027-01-01' "$WORKDIR/.claude/skills/bridgebuilder-review/resources/a.ts"

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.outcome == "fresh"'
}

# -------- Regression: adding/removing files updates hash --------

@test "AC-1.5 regression: adding a new source file invalidates the manifest" {
    "$SCRIPT" --write-manifest >/dev/null

    echo "// new source file" > "$WORKDIR/.claude/skills/bridgebuilder-review/resources/c.ts"

    run "$SCRIPT" --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.outcome == "stale"'
}

@test "AC-1.5 regression: removing a source file invalidates the manifest" {
    "$SCRIPT" --write-manifest >/dev/null

    rm "$WORKDIR/.claude/skills/bridgebuilder-review/resources/b.ts"

    run "$SCRIPT" --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.outcome == "stale"'
}

# -------- Excludes: test/node_modules paths are ignored --------

@test "AC-1.5: __tests__/ and node_modules/ are excluded from source-hash" {
    "$SCRIPT" --write-manifest >/dev/null
    local hash_before
    hash_before=$("$SCRIPT" --json | jq -r '.source_hash')

    # Add files in excluded paths
    mkdir -p "$WORKDIR/.claude/skills/bridgebuilder-review/resources/__tests__"
    echo "// test" > "$WORKDIR/.claude/skills/bridgebuilder-review/resources/__tests__/x.test.ts"

    mkdir -p "$WORKDIR/.claude/skills/bridgebuilder-review/resources/node_modules/zod"
    echo "// vendored" > "$WORKDIR/.claude/skills/bridgebuilder-review/resources/node_modules/zod/index.ts"

    run "$SCRIPT" --json
    [ "$status" -eq 0 ]
    local hash_after
    hash_after=$("$SCRIPT" --json | jq -r '.source_hash')
    [ "$hash_before" = "$hash_after" ]
}
