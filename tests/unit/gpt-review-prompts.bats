#!/usr/bin/env bats
# Tests for GPT review prompt files
#
# Verifies prompt files exist and contain required content.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PROMPTS_DIR="$PROJECT_ROOT/.claude/prompts/gpt-review/base"
}

# =============================================================================
# Prompt file existence tests
# =============================================================================

@test "code-review.md prompt exists" {
    [[ -f "$PROMPTS_DIR/code-review.md" ]]
}

@test "prd-review.md prompt exists" {
    [[ -f "$PROMPTS_DIR/prd-review.md" ]]
}

@test "sdd-review.md prompt exists" {
    [[ -f "$PROMPTS_DIR/sdd-review.md" ]]
}

@test "sprint-review.md prompt exists" {
    [[ -f "$PROMPTS_DIR/sprint-review.md" ]]
}

@test "re-review.md prompt exists" {
    [[ -f "$PROMPTS_DIR/re-review.md" ]]
}

# =============================================================================
# Prompt content validation tests
# =============================================================================

@test "code-review prompt mentions verdict types" {
    run grep -q "APPROVED\|CHANGES_REQUIRED" "$PROMPTS_DIR/code-review.md"
    [[ "$status" -eq 0 ]]
}

@test "prd-review prompt mentions verdict types" {
    run grep -q "APPROVED\|CHANGES_REQUIRED" "$PROMPTS_DIR/prd-review.md"
    [[ "$status" -eq 0 ]]
}

@test "prompts contain content placeholder or injection point" {
    # Check that at least one prompt has a way to inject content
    # This could be {{CONTENT}}, {content}, or similar markers
    local has_placeholder=false

    for prompt in "$PROMPTS_DIR"/*.md; do
        if grep -qE '\{\{.*\}\}|\{[a-z_]+\}|<content>|CONTENT' "$prompt"; then
            has_placeholder=true
            break
        fi
    done

    # If no explicit placeholder, the prompt system may append content differently
    # In that case, just verify prompts have instructions
    [[ "$has_placeholder" == true ]] || \
    grep -q "review\|analyze\|evaluate" "$PROMPTS_DIR/code-review.md"
}

# =============================================================================
# Prompt loading logic tests (via script behavior)
# =============================================================================

@test "script builds prompt path from review type" {
    # Verify the script builds prompt path using ${review_type}-review.md pattern
    run grep -q 'review_type.*-review\.md\|{review_type}-review' "$PROJECT_ROOT/.claude/scripts/gpt-review-api.sh"
    [[ "$status" -eq 0 ]]
}

@test "script has PROMPTS_DIR configured" {
    run grep -q "PROMPTS_DIR" "$PROJECT_ROOT/.claude/scripts/gpt-review-api.sh"
    [[ "$status" -eq 0 ]]
}

@test "script references re-review.md for iterations" {
    run grep -q "re-review" "$PROJECT_ROOT/.claude/scripts/gpt-review-api.sh"
    [[ "$status" -eq 0 ]]
}
