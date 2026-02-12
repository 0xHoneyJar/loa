#!/usr/bin/env bats
# Unit tests for ground-truth-gen.sh - Grounded Truth Generator
# Sprint 1: Foundation — validates checksum generation, token validation, scaffolding

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/ground-truth-gen.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/gt-gen-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create mock project structure
    export TEST_PROJECT="$TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT/grimoires/loa/reality"
    mkdir -p "$TEST_PROJECT/.claude/scripts"

    # Create mock reality files
    cat > "$TEST_PROJECT/grimoires/loa/reality/index.md" <<'EOF'
# Reality Index

## API Surface

Reference: `src/auth/handler.ts:42`

## Architecture

Reference: `lib/database/connection.ts:15`
EOF

    # Create mock source files for checksum testing
    mkdir -p "$TEST_PROJECT/src/auth" "$TEST_PROJECT/lib/database"
    echo "export function handleAuth() { return true; }" > "$TEST_PROJECT/src/auth/handler.ts"
    echo "export function connect() { return pool; }" > "$TEST_PROJECT/lib/database/connection.ts"

    # Initialize as git repo
    cd "$TEST_PROJECT"
    git init -q
    git add -A
    git commit -q -m "init"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

skip_if_deps_missing() {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
}

# =============================================================================
# Script Existence and Help
# =============================================================================

@test "gt-gen: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "gt-gen: --help shows usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# =============================================================================
# Scaffold Mode
# =============================================================================

@test "gt-gen: scaffold creates output directory structure" {
    local output_dir="$TEST_PROJECT/grimoires/loa/ground-truth"

    run "$SCRIPT" --output-dir "$output_dir" --mode scaffold
    [ "$status" -eq 0 ]
    [ -d "$output_dir" ]
    [ -f "$output_dir/index.md" ]
    [ -f "$output_dir/api-surface.md" ]
    [ -f "$output_dir/architecture.md" ]
    [ -f "$output_dir/contracts.md" ]
    [ -f "$output_dir/behaviors.md" ]
}

@test "gt-gen: scaffold without --output-dir fails with exit 2" {
    run "$SCRIPT" --mode scaffold
    [ "$status" -eq 2 ]
}

# =============================================================================
# Checksums Mode
# =============================================================================

@test "gt-gen: checksums generates valid JSON" {
    skip_if_deps_missing
    local output_dir="$TEST_PROJECT/grimoires/loa/ground-truth"
    mkdir -p "$output_dir"

    export PROJECT_ROOT="$TEST_PROJECT"
    run "$SCRIPT" \
        --reality-dir "$TEST_PROJECT/grimoires/loa/reality" \
        --output-dir "$output_dir" \
        --mode checksums
    [ "$status" -eq 0 ]
    [ -f "$output_dir/checksums.json" ]

    # Validate JSON structure
    run jq '.generated_at' "$output_dir/checksums.json"
    [ "$status" -eq 0 ]
    [ "$output" != "null" ]

    run jq '.algorithm' "$output_dir/checksums.json"
    [ "$status" -eq 0 ]
    [ "$output" = '"sha256"' ]

    run jq '.git_sha' "$output_dir/checksums.json"
    [ "$status" -eq 0 ]
    [ "$output" != "null" ]
}

@test "gt-gen: checksums includes referenced source files" {
    skip_if_deps_missing
    local output_dir="$TEST_PROJECT/grimoires/loa/ground-truth"
    mkdir -p "$output_dir"

    export PROJECT_ROOT="$TEST_PROJECT"
    run "$SCRIPT" \
        --reality-dir "$TEST_PROJECT/grimoires/loa/reality" \
        --output-dir "$output_dir" \
        --mode checksums

    [ "$status" -eq 0 ]

    # Should have at least some files
    local file_count
    file_count=$(jq '.files | length' "$output_dir/checksums.json")
    [ "$file_count" -ge 1 ]
}

@test "gt-gen: checksums with missing reality-dir returns exit 2" {
    run "$SCRIPT" \
        --reality-dir "/nonexistent/path" \
        --output-dir "$TEST_PROJECT/grimoires/loa/ground-truth" \
        --mode checksums
    [ "$status" -eq 2 ]
}

# =============================================================================
# Validate Mode
# =============================================================================

@test "gt-gen: validate passes for small files" {
    local output_dir="$TEST_PROJECT/grimoires/loa/ground-truth"
    mkdir -p "$output_dir"

    # Create small test files (well within budget)
    echo "# Index" > "$output_dir/index.md"
    echo "# API Surface" > "$output_dir/api-surface.md"
    echo "# Architecture" > "$output_dir/architecture.md"
    echo "# Contracts" > "$output_dir/contracts.md"
    echo "# Behaviors" > "$output_dir/behaviors.md"

    run "$SCRIPT" --output-dir "$output_dir" --mode validate
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "gt-gen: validate warns for oversized files" {
    local output_dir="$TEST_PROJECT/grimoires/loa/ground-truth"
    mkdir -p "$output_dir"

    # Create an oversized file (3000+ words)
    python3 -c "print(' '.join(['word'] * 3000))" > "$output_dir/index.md" 2>/dev/null || \
    printf '%0.sword ' {1..3000} > "$output_dir/index.md"

    run "$SCRIPT" --output-dir "$output_dir" --mode validate --index-max-tokens 500
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARN"* ]]
}

@test "gt-gen: validate with missing output-dir returns exit 2" {
    run "$SCRIPT" --output-dir "/nonexistent/path" --mode validate
    [ "$status" -eq 2 ]
}

# =============================================================================
# All Mode
# =============================================================================

@test "gt-gen: all mode runs scaffold + checksums + validate" {
    skip_if_deps_missing
    local output_dir="$TEST_PROJECT/grimoires/loa/ground-truth"

    export PROJECT_ROOT="$TEST_PROJECT"
    run "$SCRIPT" \
        --reality-dir "$TEST_PROJECT/grimoires/loa/reality" \
        --output-dir "$output_dir" \
        --mode all

    [ "$status" -eq 0 ]
    [ -f "$output_dir/index.md" ]
    [ -f "$output_dir/checksums.json" ]
    [[ "$output" == *"PASS"* ]]
}
