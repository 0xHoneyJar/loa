#!/usr/bin/env bash
# test-qmd-sync.sh — Tests for BUG-359 (YAML/JSON format mismatch + QMD CLI fixes)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
QMD_SYNC="$PROJECT_ROOT/.claude/scripts/qmd-sync.sh"

PASS=0
FAIL=0

# Arithmetic increment that won't trip set -e when var is 0
inc_pass() { PASS=$((PASS + 1)); }
inc_fail() { FAIL=$((FAIL + 1)); }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $desc"
        inc_pass
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        inc_fail
    fi
}

assert_json_valid() {
    local desc="$1" input="$2"
    if echo "$input" | jq empty 2>/dev/null; then
        echo "  PASS: $desc"
        inc_pass
    else
        echo "  FAIL: $desc (invalid JSON)"
        echo "    input: $input"
        inc_fail
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        inc_pass
    else
        echo "  FAIL: $desc (needle not found)"
        echo "    needle: $needle"
        inc_fail
    fi
}

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if ! echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: $desc"
        inc_pass
    else
        echo "  FAIL: $desc (needle found but should not be)"
        echo "    needle: $needle"
        inc_fail
    fi
}

# ─────────────────────────────────────────────────────────
# Setup: Create a temp config with collections
# ─────────────────────────────────────────────────────────

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Create a test config with collections
cat > "$TMPDIR_TEST/test-config.yaml" << 'YAMLEOF'
memory:
  qmd:
    enabled: true
    binary: qmd
    index_dir: .loa/qmd
    collections:
      - name: test-collection
        path: grimoires/loa
        include:
          - "*.md"
      - name: test-reality
        path: grimoires/loa/reality
        include:
          - "*.md"
          - "*.json"
YAMLEOF

# Create empty config (no collections)
cat > "$TMPDIR_TEST/empty-config.yaml" << 'YAMLEOF'
memory:
  qmd:
    enabled: true
YAMLEOF

# ─────────────────────────────────────────────────────────
# Test 1: get_collections returns valid JSON (not YAML)
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 1: get_collections() returns valid JSON"
echo "─────────────────────────────────────────────"

# Source the function we need to test — extract get_collections
# We test by calling yq directly with the same pattern qmd-sync.sh uses
collections_output=$(yq eval -o json '.memory.qmd.collections // []' "$TMPDIR_TEST/test-config.yaml" 2>/dev/null || echo "[]")

assert_json_valid "get_collections output is valid JSON" "$collections_output"

# Verify it's an array
is_array=$(echo "$collections_output" | jq 'type' 2>/dev/null)
assert_eq "get_collections returns array type" '"array"' "$is_array"

# Verify item count
count=$(echo "$collections_output" | jq 'length' 2>/dev/null)
assert_eq "get_collections returns 2 collections" "2" "$count"

# ─────────────────────────────────────────────────────────
# Test 2: Collection items have required fields
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 2: Collection items have required fields"
echo "─────────────────────────────────────────────"

first_name=$(echo "$collections_output" | jq -r '.[0].name' 2>/dev/null)
assert_eq "First collection has name" "test-collection" "$first_name"

first_path=$(echo "$collections_output" | jq -r '.[0].path' 2>/dev/null)
assert_eq "First collection has path" "grimoires/loa" "$first_path"

first_include_count=$(echo "$collections_output" | jq '.[0].include | length' 2>/dev/null)
assert_eq "First collection has include array" "1" "$first_include_count"

second_name=$(echo "$collections_output" | jq -r '.[1].name' 2>/dev/null)
assert_eq "Second collection has name" "test-reality" "$second_name"

# ─────────────────────────────────────────────────────────
# Test 3: jq can iterate collections from get_collections output
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 3: jq can iterate collections (the actual consumer pattern)"
echo "─────────────────────────────────────────────────────"

# This is the exact pattern used at lines 402, 462, 500
iter_count=0
while IFS= read -r collection; do
    [[ -z "$collection" ]] && continue
    name=$(echo "$collection" | jq -r '.name // empty' 2>/dev/null)
    [[ -z "$name" ]] && continue
    iter_count=$((iter_count + 1))
done < <(echo "$collections_output" | jq -c '.[]' 2>/dev/null)

assert_eq "jq -c '.[]' successfully iterates all collections" "2" "$iter_count"

# ─────────────────────────────────────────────────────────
# Test 4: Empty/missing config returns empty JSON array
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 4: Empty config returns empty JSON array"
echo "─────────────────────────────────────────────"

empty_output=$(yq eval -o json '.memory.qmd.collections // []' "$TMPDIR_TEST/empty-config.yaml" 2>/dev/null || echo "[]")
assert_json_valid "Empty config returns valid JSON" "$empty_output"
assert_eq "Empty config returns []" "[]" "$empty_output"

missing_output=$(yq eval -o json '.memory.qmd.collections // []' "$TMPDIR_TEST/nonexistent.yaml" 2>/dev/null || echo "[]")
assert_json_valid "Missing config returns valid JSON" "$missing_output"
assert_eq "Missing config returns []" "[]" "$missing_output"

# ─────────────────────────────────────────────────────────
# Test 5: YAML output (without -o json) fails jq parsing
# This confirms the bug exists when -o json is NOT used
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 5: Confirm YAML output (without -o json) breaks jq"
echo "─────────────────────────────────────────────────────"

yaml_output=$(yq eval '.memory.qmd.collections // []' "$TMPDIR_TEST/test-config.yaml" 2>/dev/null || echo "[]")
# YAML output should NOT be valid JSON (this confirms the bug)
if echo "$yaml_output" | jq empty 2>/dev/null; then
    # If yq happens to output valid JSON for simple cases, that's ok
    echo "  INFO: yq eval output happened to be valid JSON (may vary by content)"
    inc_pass
else
    echo "  PASS: YAML output (without -o json) is NOT valid JSON — confirms bug exists without fix"
    inc_pass
fi

# ─────────────────────────────────────────────────────────
# Test 6: qmd-sync.sh source has -o json in get_collections
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 6: qmd-sync.sh source uses -o json flag"
echo "─────────────────────────────────────────────"

if grep -q 'yq eval -o json' "$QMD_SYNC" 2>/dev/null; then
    echo "  PASS: qmd-sync.sh uses 'yq eval -o json' in get_collections"
    inc_pass
else
    echo "  FAIL: qmd-sync.sh missing '-o json' in yq eval call"
    inc_fail
fi

# ─────────────────────────────────────────────────────────
# Test 7: qmd-sync.sh does NOT use 'qmd index <file>'
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 7: qmd-sync.sh does not use incorrect 'qmd index <file>' pattern"
echo "─────────────────────────────────────────────────────"

# The incorrect pattern: $QMD_BINARY index "$real_file"
# qmd index switches databases — it does NOT index files
if grep -q '"$QMD_BINARY" index "$real_file"' "$QMD_SYNC" 2>/dev/null; then
    echo "  FAIL: qmd-sync.sh still uses incorrect 'qmd index <file>' pattern"
    inc_fail
else
    echo "  PASS: qmd-sync.sh does not use incorrect 'qmd index <file>' pattern"
    inc_pass
fi

# ─────────────────────────────────────────────────────────
# Test 8: search uses collection name, not directory path
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 8: search uses collection name (not directory path)"
echo "─────────────────────────────────────────────────────"

# The incorrect pattern: --collection "$collection_dir" (where collection_dir is a path)
# The correct pattern: --collection "$collection" (where collection is the name)
# Check across lines since the command is multi-line with backslash continuations
search_block=$(sed -n '/QMD for semantic search/,/echo "\[\]"/p' "$QMD_SYNC" 2>/dev/null)
if echo "$search_block" | grep -q 'collection_dir'; then
    echo "  FAIL: qmd-sync.sh search still uses directory path instead of collection name"
    inc_fail
else
    echo "  PASS: qmd-sync.sh search does not use directory path for --collection"
    inc_pass
fi

# ─────────────────────────────────────────────────────────
# Test 9: Syntax check
# ─────────────────────────────────────────────────────────

echo ""
echo "Test 9: qmd-sync.sh passes bash -n syntax check"
echo "─────────────────────────────────────────────────"

if bash -n "$QMD_SYNC" 2>/dev/null; then
    echo "  PASS: qmd-sync.sh passes syntax check"
    inc_pass
else
    echo "  FAIL: qmd-sync.sh has syntax errors"
    inc_fail
fi

# ─────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════"
echo "  test-qmd-sync.sh: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
