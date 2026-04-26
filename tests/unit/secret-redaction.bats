#!/usr/bin/env bats
# =============================================================================
# Sprint-3B unit tests for .claude/scripts/lib/secret-redaction.sh
# Closes Flatline sprint-review SKP-005 (centralized scrubber).
# =============================================================================

setup() {
    TEST_DIR="$(mktemp -d)"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/secret-redaction.sh"

    # shellcheck disable=SC1090
    source "$LIB"
}

teardown() {
    [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && {
        find "$TEST_DIR" -mindepth 1 -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    }
    unset _LOA_SECRET_REDACTION_SOURCED
}

# -----------------------------------------------------------------------------
# OpenAI key (sk-*)
# -----------------------------------------------------------------------------
@test "redact: sk- prefix with mock 30-char body is replaced" {
    local out
    out="$(_redact_secrets "Authorization: Bearer sk-abcdefghijklmnopqrstuvwxyz1234")"
    [[ "$out" != *"sk-abc"* ]]
    [[ "$out" == *"sk-REDACTED"* || "$out" == *"REDACTED"* ]]
}

@test "redact: sk- with hyphens and underscores still matches" {
    local out
    out="$(_redact_secrets "key=sk-proj_abc-def_ghi-jkl_mno-pqr_stu")"
    [[ "$out" != *"sk-proj"* ]]
}

# -----------------------------------------------------------------------------
# Google AIza
# -----------------------------------------------------------------------------
@test "redact: AIza key is replaced" {
    local out
    out="$(_redact_secrets "key=AIzaSyD12345678901234567890abcdefghi")"
    [[ "$out" != *"AIzaSyD"* ]]
    [[ "$out" == *"AIza-REDACTED"* ]]
}

# -----------------------------------------------------------------------------
# GitHub PAT and OAuth tokens
# -----------------------------------------------------------------------------
@test "redact: ghp_ token is replaced" {
    local out
    out="$(_redact_secrets "x-token: ghp_aBcDeFgHiJkLmNoPqRsT12345678")"
    [[ "$out" != *"ghp_aBc"* ]]
    [[ "$out" == *"ghp_REDACTED"* ]]
}

@test "redact: gho_ token is replaced" {
    local out
    out="$(_redact_secrets "x-token: gho_aBcDeFgHiJkLmNoPqRsT12345678")"
    [[ "$out" != *"gho_aBc"* ]]
}

# -----------------------------------------------------------------------------
# Slack tokens
# -----------------------------------------------------------------------------
@test "redact: xoxb token is replaced" {
    local out
    out="$(_redact_secrets "Slack: xoxb-12345678901-2345678901-abcDefGhi")"
    [[ "$out" != *"xoxb-12345"* ]]
}

# -----------------------------------------------------------------------------
# Bearer header
# -----------------------------------------------------------------------------
@test "redact: Bearer with non-prefixed token is replaced" {
    local out
    out="$(_redact_secrets "Authorization: Bearer abcdefghijklmnopqrstuvwxyz1234")"
    [[ "$out" != *"abcdefghijklm"* ]]
}

# -----------------------------------------------------------------------------
# PEM blocks (multi-line)
# -----------------------------------------------------------------------------
@test "redact: PEM private key block is replaced" {
    local pem
    pem="-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1234567890abcdefghijklmnop
qrstuvwxABCDEFGH
-----END RSA PRIVATE KEY-----"
    local out
    out="$(_redact_secrets "$pem")"
    [[ "$out" != *"MIIEpAIB"* ]]
    [[ "$out" == *"REDACTED-PEM-BLOCK"* ]]
}

# -----------------------------------------------------------------------------
# Combined / mixed (defense-in-depth — multi-pattern strings)
# -----------------------------------------------------------------------------
@test "redact: multiple secrets in one string all get redacted" {
    local mixed='openai=sk-abcdefghijklmnopqrstuvwxyz1234 google=AIzaSyD12345678901234567890abcdefghi github=ghp_aBcDeFgHiJkLmNoPqRsT12345678'
    local out
    out="$(_redact_secrets "$mixed")"
    [[ "$out" != *"sk-abc"* ]]
    [[ "$out" != *"AIzaSyD"* ]]
    [[ "$out" != *"ghp_aBc"* ]]
}

# -----------------------------------------------------------------------------
# Idempotent re-source guard
# -----------------------------------------------------------------------------
@test "lib: re-sourcing is a no-op (idempotent guard)" {
    # Already sourced once in setup. Re-source should not re-run init.
    source "$LIB"
    [ "$_LOA_SECRET_REDACTION_SOURCED" -eq 1 ]
}

# -----------------------------------------------------------------------------
# Allowlist-checked structured logging
# -----------------------------------------------------------------------------
@test "structured-log: allowed field appears in output" {
    local stderr
    stderr="$(_emit_structured_log INFO "probe complete" model_id=openai:gpt-5.3 latency_ms=342 2>&1 1>/dev/null)"
    [[ "$stderr" == *"model_id=openai:gpt-5.3"* ]]
    [[ "$stderr" == *"latency_ms=342"* ]]
}

@test "structured-log: disallowed field is dropped" {
    local stderr
    stderr="$(_emit_structured_log INFO "test" \
        model_id=openai:gpt-5.3 \
        secret_payload="sk-abcdefghijklmnopqrstuvwxyz1234" \
        2>&1 1>/dev/null)"
    [[ "$stderr" == *"model_id=openai:gpt-5.3"* ]]
    # secret_payload field name is not on the allowlist; entire field is dropped.
    [[ "$stderr" != *"secret_payload"* ]]
    # Defense-in-depth: even if it leaked, the value would be redacted.
    [[ "$stderr" != *"sk-abcdefg"* ]]
}

@test "structured-log: allowlist accepts custom field via LOA_LOG_ALLOWLIST" {
    LOA_LOG_ALLOWLIST="model_id custom_field"
    local stderr
    stderr="$(_emit_structured_log INFO "x" model_id=test custom_field=value 2>&1 1>/dev/null)"
    [[ "$stderr" == *"custom_field=value"* ]]
}

# -----------------------------------------------------------------------------
# Empty / short input
# -----------------------------------------------------------------------------
@test "redact: empty string produces empty output without error" {
    local out
    out="$(_redact_secrets "")"
    [ -z "$out" ]
}

@test "redact: short non-key text passes through unchanged" {
    local out
    out="$(_redact_secrets "hello world")"
    [ "$out" = "hello world" ]
}

# -----------------------------------------------------------------------------
# Probe regression — no secrets in stdout/stderr (Task 3B.6 SKP-005)
# -----------------------------------------------------------------------------
@test "probe-regression: --help output contains no secret-shaped text" {
    PROBE="$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"
    run "$PROBE" --help
    [ "$status" -eq 0 ]
    # Assert NONE of the secret patterns appear in either stdout or stderr.
    [[ "$output" != *"sk-"*[A-Za-z0-9]* || "$output" == *"sk-REDACTED"* ]]
    [[ "$output" != *"AIza"*[A-Za-z0-9]* || "$output" == *"AIza-REDACTED"* ]]
    [[ "$output" != *"ghp_"*[A-Za-z0-9]* || "$output" == *"ghp_REDACTED"* ]]
    [[ "$output" != *"-----BEGIN"* || "$output" == *"REDACTED-PEM"* ]]
}

@test "probe-regression: --version output contains no secret-shaped text" {
    PROBE="$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"
    run "$PROBE" --version
    [ "$status" -eq 0 ]
    [[ "$output" != *"sk-"*[A-Za-z0-9]* || "$output" == *"REDACTED"* ]]
    [[ "$output" != *"AIza"*[A-Za-z0-9]* || "$output" == *"REDACTED"* ]]
    [[ "$output" != *"ghp_"*[A-Za-z0-9]* || "$output" == *"REDACTED"* ]]
    [[ "$output" != *"-----BEGIN"* ]]
}

@test "probe-regression: --dry-run JSON output contains no secret-shaped text" {
    PROBE="$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"
    local d; d="$(mktemp -d)"
    OPENAI_API_KEY="sk-FAKE_TEST_KEY_NOT_REAL_xxxxxxxxxxxxxx"
    GOOGLE_API_KEY="AIzaFAKE_TEST_KEY_NOT_REAL_xxxxxxxxxxxx"
    ANTHROPIC_API_KEY="ant-FAKE_TEST_KEY_NOT_REAL"
    run env LOA_CACHE_DIR="$d" \
        OPENAI_API_KEY="$OPENAI_API_KEY" \
        GOOGLE_API_KEY="$GOOGLE_API_KEY" \
        ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
        "$PROBE" --dry-run --output json --quiet
    [ "$status" -eq 0 ]
    # In dry-run nothing makes HTTP, but assert keys never landed in stdout.
    [[ "$output" != *"FAKE_TEST_KEY"* ]]
    find "$d" -mindepth 1 -delete 2>/dev/null
    rmdir "$d" 2>/dev/null
}
