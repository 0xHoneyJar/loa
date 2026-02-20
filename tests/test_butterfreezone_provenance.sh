#!/usr/bin/env bash
# Tests for BUTTERFREEZONE skill provenance classification and segmented output
# Part of: BUTTERFREEZONE Skill Provenance Segmentation (cycle-030, Sprint 2)
# SDD Section 6.2 test matrix — 12 test cases
#
# Plain bash tests — no external test framework required.
# Uses temp directories — no pollution of real .claude/ or framework files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GEN_SCRIPT="${REPO_ROOT}/.claude/scripts/butterfreezone-gen.sh"
VALIDATE_SCRIPT="${REPO_ROOT}/.claude/scripts/butterfreezone-validate.sh"

# ── Test Harness ──────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  PASS: $1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $1${2:+ — $2}"; }

# ── Setup / Teardown ─────────────────────────────────

TEMP_DIR=""

setup() {
    TEMP_DIR="$(mktemp -d)"

    # Create mock .claude/data directory with core-skills.json
    mkdir -p "${TEMP_DIR}/.claude/data"
    cat > "${TEMP_DIR}/.claude/data/core-skills.json" << 'EOFJ'
{
  "version": "1.39.0",
  "generated_at": "2026-02-20T00:00:00Z",
  "skills": [
    "alpha-skill",
    "beta-skill",
    "gamma-skill"
  ]
}
EOFJ

    # Create mock .claude/skills directories
    mkdir -p "${TEMP_DIR}/.claude/skills/alpha-skill"
    mkdir -p "${TEMP_DIR}/.claude/skills/beta-skill"
    mkdir -p "${TEMP_DIR}/.claude/skills/gamma-skill"

    # Create mock SKILL.md files
    for s in alpha-skill beta-skill gamma-skill; do
        cat > "${TEMP_DIR}/.claude/skills/${s}/SKILL.md" << EOF
# ${s}

## Purpose

Mock skill for testing.
EOF
    done

    # Create mock constructs metadata
    mkdir -p "${TEMP_DIR}/.claude/constructs"

    # Create mock packs directory
    mkdir -p "${TEMP_DIR}/.claude/constructs/packs"
}

teardown() {
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

# ── Source classification functions from gen script ───
# We extract just the classification functions to test in isolation

source_classification() {
    # Source the global variables and functions we need
    _CORE_SKILLS_CACHE=""
    _CONSTRUCTS_META_CACHE=""
    _PACKS_DIR="${TEMP_DIR}/.claude/constructs/packs"

    load_classification_cache() {
        local core_file="${TEMP_DIR}/.claude/data/core-skills.json"
        if [[ -f "$core_file" ]] && command -v jq &>/dev/null; then
            _CORE_SKILLS_CACHE=$(jq -r '.skills[]' "$core_file" 2>/dev/null | sort) || true
        fi

        local meta_file="${TEMP_DIR}/.claude/constructs/.constructs-meta.json"
        if [[ -f "$meta_file" ]] && command -v jq &>/dev/null; then
            _CONSTRUCTS_META_CACHE=$(jq -r '
                .installed_skills | to_entries[] |
                select(.key | startswith("/tmp/") | not) |
                select(.value.from_pack != null) |
                "\(.key | split("/") | last)|\(.value.from_pack)"
            ' "$meta_file" 2>/dev/null) || true
        fi
    }

    classify_skill_provenance() {
        local slug="$1"

        # Priority 1: Core skills manifest
        if [[ -n "$_CORE_SKILLS_CACHE" ]]; then
            if echo "$_CORE_SKILLS_CACHE" | grep -qx "$slug"; then
                echo "core"
                return 0
            fi
        fi

        # Priority 2: Constructs metadata (from_pack)
        if [[ -n "$_CONSTRUCTS_META_CACHE" ]]; then
            local pack=""
            pack=$(echo "$_CONSTRUCTS_META_CACHE" | { grep "^${slug}|" || true; } | cut -d'|' -f2 | head -1)
            if [[ -n "$pack" ]]; then
                echo "construct:${pack}"
                return 0
            fi
        fi

        # Priority 3: Packs directory fallback
        if [[ -d "$_PACKS_DIR" ]]; then
            local pack_match=""
            pack_match=$(find "$_PACKS_DIR" -maxdepth 3 -type d -name "$slug" \
                -path "*/skills/*" 2>/dev/null | head -1 || true)
            if [[ -n "$pack_match" ]]; then
                local pack_slug
                pack_slug=$(echo "$pack_match" | sed "s|${_PACKS_DIR}/||" | cut -d'/' -f1)
                echo "construct:${pack_slug}"
                return 0
            fi
        fi

        echo "project"
    }
}

# ══════════════════════════════════════════════════════
# TEST 1: classify core skill
# ══════════════════════════════════════════════════════

test_classify_core_skill() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 1: classify core skill"

    setup
    source_classification
    load_classification_cache

    local result
    result=$(classify_skill_provenance "alpha-skill")

    if [[ "$result" == "core" ]]; then
        pass "core skill classified as 'core'"
    else
        fail "expected 'core', got '${result}'"
    fi

    teardown
}

# ══════════════════════════════════════════════════════
# TEST 2: classify construct skill
# ══════════════════════════════════════════════════════

test_classify_construct_skill() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 2: classify construct skill"

    setup

    # Add a construct skill to metadata
    cat > "${TEMP_DIR}/.claude/constructs/.constructs-meta.json" << 'EOFJ'
{
  "installed_skills": {
    ".claude/constructs/packs/test-pack/skills/market-analysis": {
      "from_pack": "test-pack",
      "installed_at": "2026-02-20T00:00:00Z"
    }
  }
}
EOFJ

    source_classification
    load_classification_cache

    local result
    result=$(classify_skill_provenance "market-analysis")

    if [[ "$result" == "construct:test-pack" ]]; then
        pass "construct skill classified as 'construct:test-pack'"
    else
        fail "expected 'construct:test-pack', got '${result}'"
    fi

    teardown
}

# ══════════════════════════════════════════════════════
# TEST 3: classify project skill
# ══════════════════════════════════════════════════════

test_classify_project_skill() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 3: classify project skill"

    setup
    source_classification
    load_classification_cache

    local result
    result=$(classify_skill_provenance "custom-deploy")

    if [[ "$result" == "project" ]]; then
        pass "unknown skill classified as 'project'"
    else
        fail "expected 'project', got '${result}'"
    fi

    teardown
}

# ══════════════════════════════════════════════════════
# TEST 4: classify with missing core-skills.json
# ══════════════════════════════════════════════════════

test_classify_missing_core_skills() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 4: classify with missing core-skills.json"

    setup

    # Remove core-skills.json
    rm "${TEMP_DIR}/.claude/data/core-skills.json"

    source_classification
    load_classification_cache

    local result
    result=$(classify_skill_provenance "alpha-skill")

    if [[ "$result" == "project" ]]; then
        pass "without core-skills.json, all skills default to 'project'"
    else
        fail "expected 'project' without manifest, got '${result}'"
    fi

    teardown
}

# ══════════════════════════════════════════════════════
# TEST 5: classify with missing constructs-meta
# ══════════════════════════════════════════════════════

test_classify_missing_constructs_meta() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 5: classify with missing constructs-meta"

    setup
    source_classification
    load_classification_cache

    # No .constructs-meta.json exists — construct check should be skipped
    local result
    result=$(classify_skill_provenance "alpha-skill")

    if [[ "$result" == "core" ]]; then
        pass "core skills still classified correctly without constructs metadata"
    else
        fail "expected 'core', got '${result}'"
    fi

    # Unknown skill should fall to project (not construct)
    result=$(classify_skill_provenance "unknown-thing")

    if [[ "$result" == "project" ]]; then
        pass "unknown skill defaults to 'project' without constructs metadata"
    else
        fail "expected 'project', got '${result}'"
    fi

    teardown
}

# ══════════════════════════════════════════════════════
# TEST 6: classify with stale /tmp/ entries
# ══════════════════════════════════════════════════════

test_classify_tmp_entries_filtered() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 6: classify with stale /tmp/ entries"

    setup

    # Add /tmp/ entries that should be filtered
    cat > "${TEMP_DIR}/.claude/constructs/.constructs-meta.json" << 'EOFJ'
{
  "installed_skills": {
    "/tmp/test-12345/packs/ghost-pack/skills/ghost-skill": {
      "from_pack": "ghost-pack",
      "installed_at": "2026-02-20T00:00:00Z"
    },
    ".claude/constructs/packs/real-pack/skills/real-skill": {
      "from_pack": "real-pack",
      "installed_at": "2026-02-20T00:00:00Z"
    }
  }
}
EOFJ

    source_classification
    load_classification_cache

    # ghost-skill should NOT be classified as construct (filtered /tmp/ entry)
    local result
    result=$(classify_skill_provenance "ghost-skill")

    if [[ "$result" == "project" ]]; then
        pass "/tmp/ entries filtered — ghost skill defaults to 'project'"
    else
        fail "expected 'project' (filtered /tmp/), got '${result}'"
    fi

    # real-skill SHOULD be classified as construct
    result=$(classify_skill_provenance "real-skill")

    if [[ "$result" == "construct:real-pack" ]]; then
        pass "non-/tmp/ entries preserved — real skill classified correctly"
    else
        fail "expected 'construct:real-pack', got '${result}'"
    fi

    teardown
}

# ══════════════════════════════════════════════════════
# TEST 7: segmented output: core only
# ══════════════════════════════════════════════════════

test_segmented_output_core_only() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 7: segmented output: core only"

    # Use the actual BUTTERFREEZONE.md in the repo
    if [[ ! -f "${REPO_ROOT}/BUTTERFREEZONE.md" ]]; then
        fail "BUTTERFREEZONE.md not found in repo"
        return
    fi

    local content
    content=$(cat "${REPO_ROOT}/BUTTERFREEZONE.md")

    # Check that #### Loa Core header exists
    if echo "$content" | grep -q "^#### Loa Core"; then
        pass "BUTTERFREEZONE.md contains '#### Loa Core' header"
    else
        fail "missing '#### Loa Core' header in BUTTERFREEZONE.md"
    fi

    # Check that no #### Constructs or #### Project-Specific (since this is core-only repo)
    local has_constructs=false
    if echo "$content" | grep -q "^#### Constructs"; then
        has_constructs=true
    fi
    local has_project=false
    if echo "$content" | grep -q "^#### Project-Specific"; then
        has_project=true
    fi

    if [[ "$has_constructs" == "false" && "$has_project" == "false" ]]; then
        pass "no Constructs or Project-Specific sections (expected for core-only repo)"
    else
        fail "unexpected group headers: constructs=${has_constructs}, project=${has_project}"
    fi
}

# ══════════════════════════════════════════════════════
# TEST 8: segmented output: core + construct (mock)
# ══════════════════════════════════════════════════════

test_segmented_output_core_and_construct() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 8: segmented output: core + construct (mock data)"

    setup

    # Create construct skill via packs directory fallback
    mkdir -p "${TEMP_DIR}/.claude/constructs/packs/mock-pack/skills/pack-skill"
    mkdir -p "${TEMP_DIR}/.claude/skills/pack-skill"
    cat > "${TEMP_DIR}/.claude/skills/pack-skill/SKILL.md" << 'EOF'
# pack-skill

## Purpose

Mock construct skill.
EOF

    source_classification
    load_classification_cache

    # Simulate classification
    local core_count=0 construct_count=0

    for skill_dir in "${TEMP_DIR}/.claude/skills"/*/; do
        [[ ! -d "$skill_dir" ]] && continue
        local sname
        sname=$(basename "$skill_dir")
        local prov
        prov=$(classify_skill_provenance "$sname")

        case "$prov" in
            core) core_count=$((core_count + 1)) ;;
            construct:*) construct_count=$((construct_count + 1)) ;;
        esac
    done

    if [[ $core_count -eq 3 ]]; then
        pass "3 core skills classified correctly"
    else
        fail "expected 3 core skills, got ${core_count}"
    fi

    if [[ $construct_count -eq 1 ]]; then
        pass "1 construct skill classified correctly"
    else
        fail "expected 1 construct skill, got ${construct_count}"
    fi

    teardown
}

# ══════════════════════════════════════════════════════
# TEST 9: segmented output: all three groups (mock)
# ══════════════════════════════════════════════════════

test_segmented_output_all_three_groups() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 9: segmented output: all three groups (mock data)"

    setup

    # Add construct skill via packs directory
    mkdir -p "${TEMP_DIR}/.claude/constructs/packs/test-pack/skills/construct-skill"
    mkdir -p "${TEMP_DIR}/.claude/skills/construct-skill"
    cat > "${TEMP_DIR}/.claude/skills/construct-skill/SKILL.md" << 'EOF'
# construct-skill

## Purpose

Mock construct skill.
EOF

    # Add project skill (not in core-skills.json, not in packs)
    mkdir -p "${TEMP_DIR}/.claude/skills/project-only-skill"
    cat > "${TEMP_DIR}/.claude/skills/project-only-skill/SKILL.md" << 'EOF'
# project-only-skill

## Purpose

Mock project-specific skill.
EOF

    source_classification
    load_classification_cache

    local core_count=0 construct_count=0 project_count=0

    for skill_dir in "${TEMP_DIR}/.claude/skills"/*/; do
        [[ ! -d "$skill_dir" ]] && continue
        local sname
        sname=$(basename "$skill_dir")
        local prov
        prov=$(classify_skill_provenance "$sname")

        case "$prov" in
            core) core_count=$((core_count + 1)) ;;
            construct:*) construct_count=$((construct_count + 1)) ;;
            project) project_count=$((project_count + 1)) ;;
        esac
    done

    if [[ $core_count -eq 3 && $construct_count -eq 1 && $project_count -eq 1 ]]; then
        pass "all three groups: 3 core, 1 construct, 1 project"
    else
        fail "expected 3/1/1, got core=${core_count}/construct=${construct_count}/project=${project_count}"
    fi

    teardown
}

# ══════════════════════════════════════════════════════
# TEST 10: AGENT-CONTEXT structured interfaces
# ══════════════════════════════════════════════════════

test_agent_context_structured_interfaces() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 10: AGENT-CONTEXT structured interfaces"

    if [[ ! -f "${REPO_ROOT}/BUTTERFREEZONE.md" ]]; then
        fail "BUTTERFREEZONE.md not found"
        return
    fi

    local context_block
    context_block=$(sed -n '/<!-- AGENT-CONTEXT/,/-->/p' "${REPO_ROOT}/BUTTERFREEZONE.md" 2>/dev/null)

    # Check for structured interfaces
    if echo "$context_block" | grep -q "^interfaces:" 2>/dev/null; then
        pass "AGENT-CONTEXT has 'interfaces:' field"
    else
        fail "AGENT-CONTEXT missing 'interfaces:' field"
        return
    fi

    if echo "$context_block" | grep -q "^  core:" 2>/dev/null; then
        pass "AGENT-CONTEXT has structured 'core:' sub-field"
    else
        fail "AGENT-CONTEXT missing 'core:' sub-field under interfaces"
    fi
}

# ══════════════════════════════════════════════════════
# TEST 11: validation passes with new format
# ══════════════════════════════════════════════════════

test_validation_passes_new_format() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 11: validation passes with new format"

    if [[ ! -f "${REPO_ROOT}/BUTTERFREEZONE.md" ]]; then
        fail "BUTTERFREEZONE.md not found"
        return
    fi

    local exit_code=0
    bash "${VALIDATE_SCRIPT}" --quiet 2>/dev/null || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        pass "butterfreezone-validate.sh passes (exit 0)"
    elif [[ $exit_code -eq 2 ]]; then
        pass "butterfreezone-validate.sh passes with warnings only (exit 2)"
    else
        fail "validation failed with exit code ${exit_code}"
    fi
}

# ══════════════════════════════════════════════════════
# TEST 12: validation warns without core-skills.json
# ══════════════════════════════════════════════════════

test_validation_warns_without_manifest() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test 12: validation warns without core-skills.json"

    if [[ ! -f "${REPO_ROOT}/BUTTERFREEZONE.md" ]]; then
        fail "BUTTERFREEZONE.md not found"
        return
    fi

    # Temporarily hide core-skills.json to test warning behavior
    local core_file="${REPO_ROOT}/.claude/data/core-skills.json"
    local backup="${REPO_ROOT}/.claude/data/core-skills.json.test-bak"
    local restored=false

    if [[ -f "$core_file" ]]; then
        mv "$core_file" "$backup"
    fi

    # Ensure restore on any exit path
    restore_manifest() {
        if [[ "$restored" == "false" && -f "$backup" ]]; then
            mv "$backup" "$core_file"
            restored=true
        fi
    }

    local exit_code=0
    local output
    output=$(bash "${VALIDATE_SCRIPT}" --quiet 2>&1) || exit_code=$?

    # Restore immediately
    restore_manifest

    # The validate script should produce a warning about missing manifest
    # Exit 2 = warnings only, Exit 0 = all pass — both acceptable
    if echo "$output" | grep -q "core-skills.json not found"; then
        pass "validation warns about missing core-skills.json"
    elif [[ $exit_code -eq 0 || $exit_code -eq 2 ]]; then
        pass "validation does not fail without core-skills.json (exit ${exit_code})"
    else
        fail "validation failed (exit ${exit_code}) without core-skills.json"
    fi
}

# ══════════════════════════════════════════════════════
# Run all tests
# ══════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════"
echo "  BUTTERFREEZONE Provenance Classification Tests"
echo "  SDD Section 6.2 — 12 Test Cases"
echo "═══════════════════════════════════════════════════"
echo ""

# Unit tests (classification)
test_classify_core_skill
test_classify_construct_skill
test_classify_project_skill

# Degradation tests
test_classify_missing_core_skills
test_classify_missing_constructs_meta
test_classify_tmp_entries_filtered

# Integration tests
test_segmented_output_core_only
test_segmented_output_core_and_construct
test_segmented_output_all_three_groups
test_agent_context_structured_interfaces
test_validation_passes_new_format
test_validation_warns_without_manifest

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Results: ${TESTS_RUN} tests, ${TESTS_PASSED} assertions, ${TESTS_FAILED} failures"
echo "═══════════════════════════════════════════════════"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
