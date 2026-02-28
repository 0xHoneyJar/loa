#!/usr/bin/env bats
# =============================================================================
# Tests for write_curl_auth_config() — curl config injection guard (FR-6)
# =============================================================================
# Cycle: cycle-048 (Community Feedback — Review Pipeline Hardening)
# Tests: valid key, CR/LF/null/backslash rejection, quote escaping,
#        base64 chars accepted, file permissions 0600.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"

    # Source lib-security.sh to get write_curl_auth_config
    source "$SCRIPT_DIR/lib-security.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/curl-config-guard-test-$$"
    mkdir -p "$TEST_TMPDIR"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Valid Key Tests
# =============================================================================

@test "write_curl_auth_config: valid Bearer key produces config file" {
    local cfg
    cfg=$(write_curl_auth_config "Authorization" "Bearer sk-proj-abc123def456")
    [ -f "$cfg" ]
    local content
    content=$(cat "$cfg")
    [[ "$content" == *'Authorization: Bearer sk-proj-abc123def456'* ]]
    rm -f "$cfg"
}

@test "write_curl_auth_config: returns path on stdout" {
    local cfg
    cfg=$(write_curl_auth_config "Authorization" "Bearer test-key")
    # Path should start with /tmp or TMPDIR
    [[ "$cfg" == /tmp/* ]] || [[ "$cfg" == "${TMPDIR:-/tmp}"/* ]]
    rm -f "$cfg"
}

@test "write_curl_auth_config: file permissions are 0600" {
    local cfg
    cfg=$(write_curl_auth_config "Authorization" "Bearer test-key")
    [ -f "$cfg" ]
    local perms
    if [[ "$(uname)" == "Darwin" ]]; then
        perms=$(stat -f '%Lp' "$cfg")
    else
        perms=$(stat -c '%a' "$cfg")
    fi
    [ "$perms" = "600" ]
    rm -f "$cfg"
}

@test "write_curl_auth_config: x-api-key header works" {
    local cfg
    cfg=$(write_curl_auth_config "x-api-key" "sk-ant-api03-test-key")
    [ -f "$cfg" ]
    local content
    content=$(cat "$cfg")
    [[ "$content" == *'x-api-key: sk-ant-api03-test-key'* ]]
    rm -f "$cfg"
}

# =============================================================================
# Rejection Tests — Header Injection Prevention
# =============================================================================

@test "write_curl_auth_config: rejects key containing carriage return (CR)" {
    local bad_key
    bad_key=$'Bearer sk-test\rInjected-Header: evil'
    run write_curl_auth_config "Authorization" "$bad_key"
    [ "$status" -eq 1 ]
    [[ "$output" == *"carriage return"* ]]
}

@test "write_curl_auth_config: rejects key containing line feed (LF)" {
    local bad_key
    bad_key=$'Bearer sk-test\nInjected-Header: evil'
    run write_curl_auth_config "Authorization" "$bad_key"
    [ "$status" -eq 1 ]
    [[ "$output" == *"line feed"* ]]
}

@test "write_curl_auth_config: null byte in key causes truncation (bash limitation)" {
    # Bash strips null bytes from variables before they reach the function.
    # The observable effect is truncation: $'Bearer sk-test\x00evil' becomes 'Bearer sk-test'.
    # This test documents the behavior: the function accepts the truncated string
    # (no injection risk since the payload after \0 is already gone).
    local bad_key
    bad_key=$'Bearer sk-test\x00evil'
    # Bash already stripped the null — verify the truncation happened
    [ "${#bad_key}" -eq 14 ]  # "Bearer sk-test" = 14 chars
    # The function succeeds because the truncated string is safe
    run write_curl_auth_config "Authorization" "$bad_key"
    [ "$status" -eq 0 ]
}

@test "write_curl_auth_config: rejects key containing backslash" {
    local bad_key='Bearer sk-test\nevil'
    run write_curl_auth_config "Authorization" "$bad_key"
    [ "$status" -eq 1 ]
    [[ "$output" == *"backslash"* ]]
}

# =============================================================================
# Quote Escaping Tests
# =============================================================================

@test "write_curl_auth_config: escapes double quotes in value" {
    local key_with_quotes='Bearer sk-test"with"quotes'
    # This should NOT be rejected — quotes are escaped, not blocked
    # But wait, double quotes contain no CR/LF/null/backslash
    # However, the backslash check would catch the escaped result...
    # Actually, the INPUT has literal quotes, not backslashes.
    # The function escapes them internally for the config file output.
    local cfg
    cfg=$(write_curl_auth_config "Authorization" "$key_with_quotes")
    [ -f "$cfg" ]
    local content
    content=$(cat "$cfg")
    # The output should have escaped quotes
    [[ "$content" == *'sk-test\"with\"quotes'* ]]
    rm -f "$cfg"
}

# =============================================================================
# Base64 Character Tests
# =============================================================================

@test "write_curl_auth_config: accepts base64 characters (+, /, =)" {
    local b64_key='Bearer abc+def/ghi=jkl=='
    local cfg
    cfg=$(write_curl_auth_config "Authorization" "$b64_key")
    [ -f "$cfg" ]
    local content
    content=$(cat "$cfg")
    [[ "$content" == *'abc+def/ghi=jkl=='* ]]
    rm -f "$cfg"
}

@test "write_curl_auth_config: accepts long base64-encoded key" {
    local long_key='Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U'
    local cfg
    cfg=$(write_curl_auth_config "Authorization" "$long_key")
    [ -f "$cfg" ]
    local content
    content=$(cat "$cfg")
    [[ "$content" == *'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'* ]]
    rm -f "$cfg"
}

# =============================================================================
# Header Name Validation Tests
# =============================================================================

@test "write_curl_auth_config: valid header name 'Authorization' passes" {
    local cfg
    cfg=$(write_curl_auth_config "Authorization" "Bearer test-key")
    [ -f "$cfg" ]
    rm -f "$cfg"
}

@test "write_curl_auth_config: rejects header name with newline" {
    local bad_name=$'Authorization\nX-Evil'
    run write_curl_auth_config "$bad_name" "Bearer test-key"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid header name"* ]]
}

@test "write_curl_auth_config: rejects header name with special chars" {
    run write_curl_auth_config "Auth: evil" "Bearer test-key"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid header name"* ]]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "write_curl_auth_config: empty value is accepted (no injection risk)" {
    local cfg
    cfg=$(write_curl_auth_config "Authorization" "")
    [ -f "$cfg" ]
    local content
    content=$(cat "$cfg")
    [[ "$content" == *'Authorization: '* ]]
    rm -f "$cfg"
}

@test "write_curl_auth_config: exit code is 0 on success" {
    run write_curl_auth_config "Authorization" "Bearer valid-key"
    [ "$status" -eq 0 ]
}

@test "write_curl_auth_config: exit code is 1 on rejection" {
    local bad_key=$'Bearer bad\nkey'
    run write_curl_auth_config "Authorization" "$bad_key"
    [ "$status" -eq 1 ]
}
