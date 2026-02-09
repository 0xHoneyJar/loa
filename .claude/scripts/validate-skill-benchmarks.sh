#!/usr/bin/env bash
# validate-skill-benchmarks.sh - Validate SKILL.md files against Anthropic benchmarks
# Issue #261: Skill Benchmark Audit
# Version: 1.0.0
#
# Checks SKILL.md content quality against Anthropic's "Complete Guide to Building
# Skills for Claude" standards. Complementary to validate-skills.sh (which checks
# index.yaml structure).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
BENCHMARK_FILE="$PROJECT_ROOT/.claude/schemas/skill-benchmark.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
total=0
passed=0
failed=0
warnings=0

# --- Configuration Loading (IMP-002: graceful error on missing/invalid config) ---

if [[ ! -f "$BENCHMARK_FILE" ]]; then
    echo -e "${RED}ERROR: Benchmark config not found at $BENCHMARK_FILE${NC}"
    echo "Create the file or run the skill benchmark setup."
    exit 1
fi

if ! jq '.' "$BENCHMARK_FILE" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Benchmark config is not valid JSON: $BENCHMARK_FILE${NC}"
    echo "Fix the JSON syntax and retry."
    exit 1
fi

MAX_WORDS=$(jq -r '.max_words // 5000' "$BENCHMARK_FILE")
MAX_DESC_CHARS=$(jq -r '.max_description_chars // 1024' "$BENCHMARK_FILE")
MIN_ERROR_REFS=$(jq -r '.min_error_references // 5' "$BENCHMARK_FILE")
FOLDER_PATTERN=$(jq -r '.folder_name_pattern // "^[a-z][a-z0-9-]+$"' "$BENCHMARK_FILE")

# Load trigger patterns into array
mapfile -t TRIGGER_PATTERNS < <(jq -r '.description_trigger_patterns[]' "$BENCHMARK_FILE" 2>/dev/null)
if [[ ${#TRIGGER_PATTERNS[@]} -eq 0 ]]; then
    TRIGGER_PATTERNS=("Use when" "Use this" "Use if" "Invoke when" "Trigger when")
fi

# Load forbidden frontmatter patterns
mapfile -t FORBIDDEN_PATTERNS < <(jq -r '.forbidden_frontmatter_patterns[]' "$BENCHMARK_FILE" 2>/dev/null)
if [[ ${#FORBIDDEN_PATTERNS[@]} -eq 0 ]]; then
    FORBIDDEN_PATTERNS=('<[a-zA-Z]' '</[a-zA-Z]')
fi

# --- Check for required tools ---

if ! command -v jq &> /dev/null; then
    echo -e "${RED}ERROR: jq is required but not installed${NC}"
    exit 1
fi

has_yq=false
if command -v yq &> /dev/null; then
    has_yq=true
fi

# --- Header ---

echo "Skill Benchmark Validation (Anthropic Guide)"
echo "============================================="
echo ""

# --- Parse flags ---

INCLUDE_TEST_FIXTURES=false
for arg in "$@"; do
    case "$arg" in
        --include-test-fixtures) INCLUDE_TEST_FIXTURES=true ;;
    esac
done

# --- Check if skills directory exists ---

if [[ ! -d "$SKILLS_DIR" ]]; then
    echo -e "${RED}ERROR: Skills directory not found at $SKILLS_DIR${NC}"
    exit 1
fi

# --- Helper: extract YAML frontmatter from SKILL.md ---
# Returns frontmatter between first pair of --- delimiters
extract_frontmatter() {
    local file="$1"
    sed -n '1{/^---$/!q};1,/^---$/{/^---$/d;p}' "$file" 2>/dev/null
}

# --- Validate each skill ---

for skill_dir in "$SKILLS_DIR"/*/; do
    # Skip test fixture directories (unless --include-test-fixtures)
    skill_name=$(basename "$skill_dir")
    if [[ "$skill_name" == __* && "$INCLUDE_TEST_FIXTURES" == "false" ]]; then
        continue
    fi

    total=$((total + 1))
    skill_errors=()
    skill_warns=()

    # --- Check 1: SKILL.md exists ---
    skill_file="$skill_dir/SKILL.md"
    if [[ ! -f "$skill_file" ]]; then
        skill_errors+=("SKILL.md not found")
        echo -e "${RED}FAIL${NC}: $skill_name (SKILL.md not found)"
        failed=$((failed + 1))
        continue
    fi

    # --- Check 2: Word count ---
    word_count=$(wc -w < "$skill_file" | tr -d ' ')
    if [[ "$word_count" -gt "$MAX_WORDS" ]]; then
        skill_errors+=("$word_count words > $MAX_WORDS limit")
    fi

    # --- Check 3: No README.md ---
    if [[ -f "$skill_dir/README.md" ]]; then
        skill_errors+=("README.md present (use SKILL.md only)")
    fi

    # --- Check 4: Folder kebab-case ---
    if [[ ! "$skill_name" =~ $FOLDER_PATTERN ]]; then
        skill_errors+=("folder name '$skill_name' not kebab-case")
    fi

    # --- Check 5: Frontmatter has name field ---
    # Note: frontmatter `name:` is the command name (e.g. "ride"), which may
    # differ from the folder name (e.g. "riding-codebase"). We only check presence.
    frontmatter=$(extract_frontmatter "$skill_file")
    if [[ -n "$frontmatter" ]]; then
        fm_name=$(echo "$frontmatter" | grep -E "^name:" | head -1 | sed 's/^name:[[:space:]]*//' | tr -d '[:space:]' || true)
        if [[ -n "$frontmatter" && -z "$fm_name" ]] && echo "$frontmatter" | grep -qE "^name:" 2>/dev/null; then
            skill_errors+=("frontmatter has empty name field")
        fi
    fi

    # --- Check 6: No XML in frontmatter ---
    if [[ -n "$frontmatter" ]]; then
        for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
            if echo "$frontmatter" | grep -qE "$pattern" 2>/dev/null; then
                skill_errors+=("XML-like content in frontmatter (pattern: $pattern)")
                break
            fi
        done
    fi

    # --- Check 7: Description length (from index.yaml) ---
    index_file="$skill_dir/index.yaml"
    if [[ -f "$index_file" ]]; then
        if [[ "$has_yq" == "true" ]]; then
            desc=$(yq -r '.description // ""' "$index_file" 2>/dev/null || echo "")
        else
            # Fallback: extract description with grep (handles multi-line poorly but works for single-line)
            desc=$(grep -A1 "^description:" "$index_file" 2>/dev/null | head -1 | sed 's/^description:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')
        fi
        desc_len=${#desc}
        if [[ "$desc_len" -gt "$MAX_DESC_CHARS" ]]; then
            skill_errors+=("description $desc_len chars > $MAX_DESC_CHARS limit")
        fi

        # --- Check 8: Description has trigger context (WARN) ---
        has_trigger=false
        for trigger in "${TRIGGER_PATTERNS[@]}"; do
            if echo "$desc" | grep -qi "$trigger" 2>/dev/null; then
                has_trigger=true
                break
            fi
        done
        if [[ "$has_trigger" == "false" && -n "$desc" ]]; then
            skill_warns+=("description lacks trigger context (no 'Use when'/'Use this' pattern)")
        fi
    fi

    # --- Check 9: Error handling references (WARN) ---
    error_refs=$(grep -ciE 'error|troubleshoot|fail|Error Handling' "$skill_file" 2>/dev/null || echo "0")
    if [[ "$error_refs" -lt "$MIN_ERROR_REFS" ]]; then
        skill_warns+=("only $error_refs error refs (min: $MIN_ERROR_REFS)")
    fi

    # --- Check 10: Frontmatter parses as valid YAML ---
    if [[ -n "$frontmatter" ]]; then
        if [[ "$has_yq" == "true" ]]; then
            if ! echo "$frontmatter" | yq '.' > /dev/null 2>&1; then
                skill_errors+=("frontmatter YAML parse error")
            fi
        fi
    fi

    # --- Report per-skill ---
    if [[ ${#skill_errors[@]} -gt 0 ]]; then
        echo -e "${RED}FAIL${NC}: $skill_name ($word_count words)"
        for err in "${skill_errors[@]}"; do
            echo "       - $err"
        done
        failed=$((failed + 1))
    elif [[ ${#skill_warns[@]} -gt 0 ]]; then
        echo -e "${GREEN}PASS${NC}: $skill_name ($word_count words)"
        for warn in "${skill_warns[@]}"; do
            echo -e "  ${YELLOW}WARN${NC}: $skill_name - $warn"
            warnings=$((warnings + 1))
        done
        passed=$((passed + 1))
    else
        echo -e "${GREEN}PASS${NC}: $skill_name ($word_count words)"
        passed=$((passed + 1))
    fi
done

# --- Summary ---

echo ""
echo "Summary"
echo "-------"
echo "Total: $total"
echo -e "Passed: ${GREEN}$passed${NC}"
echo -e "Failed: ${RED}$failed${NC}"
echo -e "Warnings: ${YELLOW}$warnings${NC}"
echo ""

if [[ $failed -gt 0 ]]; then
    echo -e "${RED}Benchmark validation failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All skills pass benchmarks!${NC}"
    exit 0
fi
