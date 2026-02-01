#!/usr/bin/env bats
# test-detect-codebase.bats - Unit tests for detect-codebase.sh
#
# Run with: bats .claude/scripts/tests/test-detect-codebase.bats

# Get the directory containing the script under test
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
SCRIPT="${SCRIPT_DIR}/detect-codebase.sh"

setup() {
    # Create a temp directory for each test
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
}

teardown() {
    # Clean up temp directory
    cd /
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Helper Functions
# =============================================================================

run_detect() {
    run "$SCRIPT"
}

get_json_field() {
    local field="$1"
    echo "$output" | jq -r ".$field"
}

# =============================================================================
# Empty Directory Tests
# =============================================================================

@test "empty directory returns GREENFIELD" {
    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

@test "empty directory has zero files" {
    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field files)" = "0" ]
}

@test "empty directory has zero lines" {
    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field lines)" = "0" ]
}

@test "empty directory has unknown language" {
    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field language)" = "unknown" ]
}

@test "empty directory has no paths found" {
    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field 'paths_found | length')" = "0" ]
}

# =============================================================================
# File Threshold Tests
# =============================================================================

@test "9 files returns GREENFIELD (below threshold)" {
    mkdir -p src
    for i in $(seq 1 9); do
        echo "const x = $i;" > "src/file$i.ts"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
    [ "$(get_json_field files)" = "9" ]
}

@test "10 files returns BROWNFIELD (at threshold)" {
    mkdir -p src
    for i in $(seq 1 10); do
        echo "const x = $i;" > "src/file$i.ts"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
    [ "$(get_json_field files)" = "10" ]
}

@test "15 files returns BROWNFIELD (above threshold)" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "const x = $i;" > "src/file$i.ts"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
    [ "$(get_json_field files)" = "15" ]
}

# =============================================================================
# Line Threshold Tests
# =============================================================================

@test "499 lines returns GREENFIELD (below threshold)" {
    mkdir -p src
    # Create 5 files with ~100 lines each = 500 lines
    for i in $(seq 1 5); do
        for j in $(seq 1 99); do
            echo "const line$j = $j;" >> "src/file$i.ts"
        done
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

@test "500 lines returns BROWNFIELD (at threshold)" {
    mkdir -p src
    # Create 5 files with 100 lines each = 500 lines
    for i in $(seq 1 5); do
        for j in $(seq 1 100); do
            echo "const line$j = $j;" >> "src/file$i.ts"
        done
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
}

# =============================================================================
# Directory Exclusion Tests
# =============================================================================

@test "node_modules files are excluded" {
    mkdir -p node_modules/package
    for i in $(seq 1 20); do
        echo "module.exports = $i;" > "node_modules/package/file$i.js"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
    [ "$(get_json_field files)" = "0" ]
}

@test "vendor directory is excluded" {
    mkdir -p vendor/package
    for i in $(seq 1 20); do
        echo "<?php echo $i;" > "vendor/package/file$i.php"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

@test ".git directory is excluded" {
    mkdir -p .git/hooks
    for i in $(seq 1 20); do
        echo "#!/bin/bash" > ".git/hooks/hook$i.sh"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

@test "dist directory is excluded" {
    mkdir -p dist
    for i in $(seq 1 20); do
        echo "var x = $i;" > "dist/bundle$i.js"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

@test "build directory is excluded" {
    mkdir -p build
    for i in $(seq 1 20); do
        echo "class Build$i {}" > "build/Build$i.java"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

@test "__pycache__ is excluded" {
    mkdir -p __pycache__
    for i in $(seq 1 20); do
        echo "# cached" > "__pycache__/module$i.pyc"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

@test "target directory is excluded (Rust)" {
    mkdir -p target/release
    for i in $(seq 1 20); do
        echo "fn main() {}" > "target/release/file$i.rs"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

# =============================================================================
# Source Path Detection Tests
# =============================================================================

@test "src directory detected" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "export const x$i = $i;" > "src/file$i.ts"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field 'paths_found[0]')" = "src/" ]
}

@test "lib directory detected" {
    mkdir -p lib
    for i in $(seq 1 15); do
        echo "def func$i(): pass" > "lib/file$i.py"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field 'paths_found[0]')" = "lib/" ]
}

@test "app directory detected" {
    mkdir -p app
    for i in $(seq 1 15); do
        echo "class App$i {}" > "app/App$i.java"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field 'paths_found[0]')" = "app/" ]
}

@test "multiple source directories detected" {
    mkdir -p src lib
    for i in $(seq 1 8); do
        echo "const x = $i;" > "src/file$i.ts"
    done
    for i in $(seq 1 8); do
        echo "const y = $i;" > "lib/file$i.js"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field 'paths_found | length')" = "2" ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
}

# =============================================================================
# Language Detection Tests
# =============================================================================

@test "TypeScript detected as primary language" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "const x: number = $i;" > "src/file$i.ts"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field language)" = "typescript" ]
}

@test "JavaScript detected as primary language" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "const x = $i;" > "src/file$i.js"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field language)" = "javascript" ]
}

@test "Python detected as primary language" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "x = $i" > "src/file$i.py"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field language)" = "python" ]
}

@test "Go detected as primary language" {
    mkdir -p pkg
    for i in $(seq 1 15); do
        echo "package main" > "pkg/file$i.go"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field language)" = "go" ]
}

@test "Rust detected as primary language" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "fn main() {}" > "src/file$i.rs"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field language)" = "rust" ]
}

@test "mixed languages uses most common" {
    mkdir -p src
    # 10 TypeScript, 5 JavaScript
    for i in $(seq 1 10); do
        echo "const x: number = $i;" > "src/file$i.ts"
    done
    for i in $(seq 1 5); do
        echo "const y = $i;" > "src/js$i.js"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field language)" = "typescript" ]
}

# =============================================================================
# Reality Detection Tests
# =============================================================================

@test "reality_exists false when no reality file" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "const x = $i;" > "src/file$i.ts"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field reality_exists)" = "false" ]
}

@test "reality_exists true when reality file exists" {
    mkdir -p grimoires/loa/reality
    echo "# Extracted PRD" > grimoires/loa/reality/extracted-prd.md

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field reality_exists)" = "true" ]
}

@test "reality_age_days is 999 when no reality file" {
    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field reality_age_days)" = "999" ]
}

@test "reality_age_days is 0 for fresh reality file" {
    mkdir -p grimoires/loa/reality
    echo "# Extracted PRD" > grimoires/loa/reality/extracted-prd.md

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field reality_age_days)" = "0" ]
}

# =============================================================================
# Root Directory Tests
# =============================================================================

@test "root source files counted" {
    for i in $(seq 1 15); do
        echo "const x = $i;" > "file$i.ts"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
    [ "$(get_json_field files)" = "15" ]
    [ "$(get_json_field 'paths_found[0]')" = "./" ]
}

@test "root and src files combined" {
    mkdir -p src
    for i in $(seq 1 5); do
        echo "const x = $i;" > "file$i.ts"
    done
    for i in $(seq 1 6); do
        echo "const y = $i;" > "src/file$i.ts"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
    [ "$(get_json_field files)" = "11" ]
}

# =============================================================================
# JSON Output Tests
# =============================================================================

@test "output is valid JSON" {
    run_detect
    [ "$status" -eq 0 ]

    # jq will fail if output is not valid JSON
    echo "$output" | jq . >/dev/null 2>&1
    [ "$?" -eq 0 ]
}

@test "error field is null on success" {
    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field error)" = "null" ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "handles missing directories gracefully" {
    # Just run in empty dir - no src, lib, etc.
    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
}

@test "handles non-source files" {
    mkdir -p src
    # Create non-source files
    echo "# README" > src/README.md
    echo "config: true" > src/config.yaml
    echo '{"key": "value"}' > src/data.json

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "GREENFIELD" ]
    [ "$(get_json_field files)" = "0" ]
}

@test "handles TSX files" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "export const Component$i = () => <div>$i</div>;" > "src/Component$i.tsx"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
    [ "$(get_json_field language)" = "typescript" ]
}

@test "handles JSX files" {
    mkdir -p src
    for i in $(seq 1 15); do
        echo "export const Component$i = () => <div>$i</div>;" > "src/Component$i.jsx"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
    [ "$(get_json_field language)" = "javascript" ]
}

@test "handles Vue files" {
    mkdir -p src/components
    for i in $(seq 1 15); do
        echo "<template><div>$i</div></template>" > "src/components/Component$i.vue"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
    [ "$(get_json_field language)" = "vue" ]
}

@test "handles Svelte files" {
    mkdir -p src/components
    for i in $(seq 1 15); do
        echo "<script>let x = $i;</script>" > "src/components/Component$i.svelte"
    done

    run_detect
    [ "$status" -eq 0 ]
    [ "$(get_json_field type)" = "BROWNFIELD" ]
    [ "$(get_json_field language)" = "svelte" ]
}
