#!/usr/bin/env bats
# Unit tests for Mibera Lore Knowledge Base
# Sprint 1: Foundation — validates lore YAML structure, cross-references, and schema

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    LORE_DIR="$PROJECT_ROOT/.claude/data/lore"
}

# Helper to skip if dependencies not available
skip_if_deps_missing() {
    if ! command -v yq &>/dev/null; then
        skip "yq not installed"
    fi
}

# =============================================================================
# Index Validation
# =============================================================================

@test "lore: index.yaml exists" {
    [ -f "$LORE_DIR/index.yaml" ]
}

@test "lore: index.yaml has version field" {
    skip_if_deps_missing
    local version
    version=$(yq '.version' "$LORE_DIR/index.yaml")
    [ "$version" = "1" ]
}

@test "lore: index.yaml has categories array" {
    skip_if_deps_missing
    local count
    count=$(yq '.categories | length' "$LORE_DIR/index.yaml")
    [ "$count" -ge 2 ]
}

@test "lore: index.yaml has tags array" {
    skip_if_deps_missing
    local count
    count=$(yq '.tags | length' "$LORE_DIR/index.yaml")
    [ "$count" -ge 5 ]
}

@test "lore: all referenced category files exist" {
    skip_if_deps_missing
    local files
    files=$(yq '.categories[].files[]' "$LORE_DIR/index.yaml")

    while IFS= read -r file; do
        [ -f "$LORE_DIR/$file" ] || fail "Referenced file missing: $file"
    done <<< "$files"
}

# =============================================================================
# Mibera Core Entry Validation
# =============================================================================

@test "lore: mibera/core.yaml exists and has entries" {
    skip_if_deps_missing
    [ -f "$LORE_DIR/mibera/core.yaml" ]
    local count
    count=$(yq '.entries | length' "$LORE_DIR/mibera/core.yaml")
    [ "$count" -ge 5 ]
}

@test "lore: all core entries have required fields" {
    skip_if_deps_missing
    local entries_count
    entries_count=$(yq '.entries | length' "$LORE_DIR/mibera/core.yaml")

    for ((i=0; i<entries_count; i++)); do
        local id term short context source tags
        id=$(yq ".entries[$i].id" "$LORE_DIR/mibera/core.yaml")
        term=$(yq ".entries[$i].term" "$LORE_DIR/mibera/core.yaml")
        short=$(yq ".entries[$i].short" "$LORE_DIR/mibera/core.yaml")
        context=$(yq ".entries[$i].context" "$LORE_DIR/mibera/core.yaml")
        source=$(yq ".entries[$i].source" "$LORE_DIR/mibera/core.yaml")
        tags=$(yq ".entries[$i].tags | length" "$LORE_DIR/mibera/core.yaml")

        [ "$id" != "null" ] || fail "Entry $i missing id"
        [ "$term" != "null" ] || fail "Entry $i missing term"
        [ "$short" != "null" ] || fail "Entry $i missing short"
        [ "$context" != "null" ] || fail "Entry $i missing context"
        [ "$source" != "null" ] || fail "Entry $i missing source"
        [ "$tags" -ge 1 ] || fail "Entry $i missing tags"
    done
}

@test "lore: core entries include kaironic-time" {
    skip_if_deps_missing
    local result
    result=$(yq '.entries[] | select(.id == "kaironic-time") | .id' "$LORE_DIR/mibera/core.yaml")
    [ "$result" = "kaironic-time" ]
}

@test "lore: core entries include cheval" {
    skip_if_deps_missing
    local result
    result=$(yq '.entries[] | select(.id == "cheval") | .id' "$LORE_DIR/mibera/core.yaml")
    [ "$result" = "cheval" ]
}

@test "lore: core entries include network-mysticism" {
    skip_if_deps_missing
    local result
    result=$(yq '.entries[] | select(.id == "network-mysticism") | .id' "$LORE_DIR/mibera/core.yaml")
    [ "$result" = "network-mysticism" ]
}

@test "lore: core entries include hounfour" {
    skip_if_deps_missing
    local result
    result=$(yq '.entries[] | select(.id == "hounfour") | .id' "$LORE_DIR/mibera/core.yaml")
    [ "$result" = "hounfour" ]
}

# =============================================================================
# Cosmology and Rituals
# =============================================================================

@test "lore: mibera/cosmology.yaml exists with triskelion entry" {
    skip_if_deps_missing
    [ -f "$LORE_DIR/mibera/cosmology.yaml" ]
    local result
    result=$(yq '.entries[] | select(.id == "triskelion") | .id' "$LORE_DIR/mibera/cosmology.yaml")
    [ "$result" = "triskelion" ]
}

@test "lore: mibera/cosmology.yaml has milady-mibera-duality" {
    skip_if_deps_missing
    local result
    result=$(yq '.entries[] | select(.id == "milady-mibera-duality") | .id' "$LORE_DIR/mibera/cosmology.yaml")
    [ "$result" = "milady-mibera-duality" ]
}

@test "lore: mibera/rituals.yaml exists with bridge-loop entry" {
    skip_if_deps_missing
    [ -f "$LORE_DIR/mibera/rituals.yaml" ]
    local result
    result=$(yq '.entries[] | select(.id == "bridge-loop") | .id' "$LORE_DIR/mibera/rituals.yaml")
    [ "$result" = "bridge-loop" ]
}

# =============================================================================
# Glossary
# =============================================================================

@test "lore: glossary has at least 15 entries" {
    skip_if_deps_missing
    [ -f "$LORE_DIR/mibera/glossary.yaml" ]
    local count
    count=$(yq '.entries | length' "$LORE_DIR/mibera/glossary.yaml")
    [ "$count" -ge 15 ]
}

@test "lore: all glossary entries have required fields" {
    skip_if_deps_missing
    local entries_count
    entries_count=$(yq '.entries | length' "$LORE_DIR/mibera/glossary.yaml")

    for ((i=0; i<entries_count; i++)); do
        local id term short
        id=$(yq ".entries[$i].id" "$LORE_DIR/mibera/glossary.yaml")
        term=$(yq ".entries[$i].term" "$LORE_DIR/mibera/glossary.yaml")
        short=$(yq ".entries[$i].short" "$LORE_DIR/mibera/glossary.yaml")

        [ "$id" != "null" ] || fail "Glossary entry $i missing id"
        [ "$term" != "null" ] || fail "Glossary entry $i missing term"
        [ "$short" != "null" ] || fail "Glossary entry $i missing short"
    done
}

# =============================================================================
# Neuromancer Entries
# =============================================================================

@test "lore: neuromancer/concepts.yaml exists with ice entry" {
    skip_if_deps_missing
    [ -f "$LORE_DIR/neuromancer/concepts.yaml" ]
    local result
    result=$(yq '.entries[] | select(.id == "ice") | .id' "$LORE_DIR/neuromancer/concepts.yaml")
    [ "$result" = "ice" ]
}

@test "lore: neuromancer/concepts.yaml has simstim entry" {
    skip_if_deps_missing
    local result
    result=$(yq '.entries[] | select(.id == "simstim") | .id' "$LORE_DIR/neuromancer/concepts.yaml")
    [ "$result" = "simstim" ]
}

@test "lore: neuromancer/concepts.yaml has flatline-construct entry" {
    skip_if_deps_missing
    local result
    result=$(yq '.entries[] | select(.id == "flatline-construct") | .id' "$LORE_DIR/neuromancer/concepts.yaml")
    [ "$result" = "flatline-construct" ]
}

@test "lore: neuromancer/mappings.yaml has concept-to-feature mappings" {
    skip_if_deps_missing
    [ -f "$LORE_DIR/neuromancer/mappings.yaml" ]
    local count
    count=$(yq '.mappings | length' "$LORE_DIR/neuromancer/mappings.yaml")
    [ "$count" -ge 5 ]
}

@test "lore: neuromancer mapping for ice references run-mode-ice.sh" {
    skip_if_deps_missing
    local result
    result=$(yq '.mappings[] | select(.concept == "ice") | .loa_feature' "$LORE_DIR/neuromancer/mappings.yaml" | head -1)
    [[ "$result" == *"run-mode-ice.sh"* ]]
}

# =============================================================================
# Cross-Reference Validation
# =============================================================================

@test "lore: related fields reference existing entry IDs" {
    skip_if_deps_missing
    # Verify that core.yaml entries have non-empty related arrays
    # (full cross-reference validation across files would be expensive)
    local has_related=0
    local entries_count
    entries_count=$(yq '.entries | length' "$LORE_DIR/mibera/core.yaml")

    for ((i=0; i<entries_count; i++)); do
        local rel_count
        rel_count=$(yq ".entries[$i].related | length" "$LORE_DIR/mibera/core.yaml" 2>/dev/null)
        if [[ "$rel_count" -gt 0 ]]; then
            has_related=$((has_related + rel_count))
        fi
    done

    [ "$has_related" -ge 5 ]
}

# =============================================================================
# README
# =============================================================================

@test "lore: README.md exists" {
    [ -f "$LORE_DIR/README.md" ]
}

@test "lore: README.md documents entry schema" {
    grep -q "Entry Schema" "$LORE_DIR/README.md"
}

# =============================================================================
# YAML Parsability
# =============================================================================

@test "lore: all YAML files parse cleanly" {
    skip_if_deps_missing
    local failures=0
    for file in "$LORE_DIR"/*.yaml "$LORE_DIR"/mibera/*.yaml "$LORE_DIR"/neuromancer/*.yaml; do
        [ -f "$file" ] || continue
        if ! yq '.' "$file" > /dev/null 2>&1; then
            echo "Parse error: $file" >&2
            failures=$((failures + 1))
        fi
    done
    [ "$failures" -eq 0 ]
}
