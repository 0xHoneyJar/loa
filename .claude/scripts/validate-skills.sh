#!/usr/bin/env bash
# validate-skills.sh - Validate all skill index.yaml files against schema
# Issue #97: Skill Best Practices Alignment
# Issue #100: HIGH-001 - Safe yq output handling
# Version: 1.1.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
SCHEMA_FILE="$PROJECT_ROOT/.claude/schemas/skill-index.schema.json"

# Source safe yq library
# shellcheck source=yq-safe.sh
source "$SCRIPT_DIR/yq-safe.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
total=0
passed=0
failed=0
warnings=0

echo "Skill Index Validation"
echo "======================"
echo ""

# Check if schema exists
if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo -e "${RED}ERROR: Schema not found at $SCHEMA_FILE${NC}"
    exit 1
fi

# Check for validation tools
has_ajv=false
has_yq=false

if command -v ajv &> /dev/null; then
    has_ajv=true
fi

if command -v yq &> /dev/null; then
    has_yq=true
fi

if [[ "$has_yq" == "false" ]]; then
    echo -e "${RED}ERROR: yq is required for YAML to JSON conversion${NC}"
    echo "Install with: brew install yq (macOS) or snap install yq (Linux)"
    exit 1
fi

if [[ "$has_ajv" == "false" ]]; then
    echo -e "${YELLOW}WARNING: ajv not found, using basic validation only${NC}"
    echo "Install with: npm install -g ajv-cli"
    echo ""
fi

# Validate each skill
for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    index_file="$skill_dir/index.yaml"

    ((total++))

    if [[ ! -f "$index_file" ]]; then
        echo -e "${YELLOW}SKIP${NC}: $skill_name (no index.yaml)"
        ((warnings++))
        continue
    fi

    # Convert YAML to JSON
    json_content=$(yq -o=json "$index_file" 2>&1) || {
        echo -e "${RED}FAIL${NC}: $skill_name - YAML parse error"
        ((failed++))
        continue
    }

    # Basic validation checks (always run)
    errors=()

    # Check required fields (using safe extraction - HIGH-001 fix)
    # Use jq for JSON parsing (safer than piping through yq again)
    name=$(echo "$json_content" | jq -r '.name // ""' 2>/dev/null || echo "")
    version=$(echo "$json_content" | jq -r '.version // ""' 2>/dev/null || echo "")
    description=$(echo "$json_content" | jq -r '.description // ""' 2>/dev/null || echo "")
    triggers=$(echo "$json_content" | jq -r '.triggers // ""' 2>/dev/null || echo "")

    # Validate extracted values against expected patterns (HIGH-001 fix)
    if [[ -n "$name" && ! "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        errors+=("name contains invalid characters (must be kebab-case)")
    fi

    if [[ -z "$name" ]]; then
        errors+=("missing required field: name")
    fi

    if [[ -z "$version" ]]; then
        errors+=("missing required field: version")
    elif ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        errors+=("version must be semver format (got: $version)")
    fi

    if [[ -z "$description" ]]; then
        errors+=("missing required field: description")
    fi

    if [[ -z "$triggers" || "$triggers" == "null" ]]; then
        errors+=("missing required field: triggers")
    fi

    # Check new v1.14.0 fields (warnings only) - using jq for safe extraction (HIGH-001 fix)
    effort_hint=$(echo "$json_content" | jq -r '.effort_hint // ""' 2>/dev/null || echo "")
    danger_level=$(echo "$json_content" | jq -r '.danger_level // ""' 2>/dev/null || echo "")
    categories=$(echo "$json_content" | jq -r '.categories // ""' 2>/dev/null || echo "")

    # Validate enum values (HIGH-001 fix)
    if [[ -n "$effort_hint" && ! "$effort_hint" =~ ^(low|medium|high)$ ]]; then
        errors+=("effort_hint must be low, medium, or high (got: $effort_hint)")
    fi
    if [[ -n "$danger_level" && ! "$danger_level" =~ ^(safe|moderate|high|critical)$ ]]; then
        errors+=("danger_level must be safe, moderate, high, or critical (got: $danger_level)")
    fi

    if [[ -z "$effort_hint" ]]; then
        echo -e "  ${YELLOW}WARN${NC}: $skill_name - missing effort_hint"
    fi

    if [[ -z "$danger_level" ]]; then
        echo -e "  ${YELLOW}WARN${NC}: $skill_name - missing danger_level"
    fi

    if [[ -z "$categories" || "$categories" == "null" ]]; then
        echo -e "  ${YELLOW}WARN${NC}: $skill_name - missing categories"
    fi

    # If ajv is available, run full schema validation
    if [[ "$has_ajv" == "true" ]]; then
        temp_file=$(mktemp) || { echo -e "${RED}FAIL${NC}: $skill_name - mktemp failed"; ((failed++)); continue; }
        chmod 600 "$temp_file"  # CRITICAL-001 FIX
        echo "$json_content" > "$temp_file"

        ajv_output=$(ajv validate -s "$SCHEMA_FILE" -d "$temp_file" 2>&1) || {
            # Parse ajv errors
            while IFS= read -r line; do
                if [[ "$line" == *"error"* || "$line" == *"Error"* ]]; then
                    errors+=("$line")
                fi
            done <<< "$ajv_output"
        }

        rm -f "$temp_file"
    fi

    # Report results
    if [[ ${#errors[@]} -eq 0 ]]; then
        echo -e "${GREEN}PASS${NC}: $skill_name"
        ((passed++))
    else
        echo -e "${RED}FAIL${NC}: $skill_name"
        for err in "${errors[@]}"; do
            echo "       - $err"
        done
        ((failed++))
    fi
done

echo ""
echo "Summary"
echo "-------"
echo "Total: $total"
echo -e "Passed: ${GREEN}$passed${NC}"
echo -e "Failed: ${RED}$failed${NC}"
echo -e "Warnings: ${YELLOW}$warnings${NC}"
echo ""

if [[ $failed -gt 0 ]]; then
    echo -e "${RED}Validation failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All skills valid!${NC}"
    exit 0
fi
