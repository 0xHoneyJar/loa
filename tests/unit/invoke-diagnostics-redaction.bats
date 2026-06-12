#!/usr/bin/env bats
# =============================================================================
# invoke-diagnostics-redaction.bats — sprint-bug-206 (#1009)
# =============================================================================
# redact_secrets() in .claude/scripts/lib/invoke-diagnostics.sh had two
# pattern gaps (recovered from the sprint-bug-198 cross-model audit rejection
# sidecar, gpt-5.5-pro, KF-004 class):
#
#   1. AWS key-ID prefixes: only AKIA* was masked — the session/role classes
#      ASIA*, AROA*, AGPA*, AIPA*, ANPA*, ANVA* passed through unredacted
#      (session tokens are common in CI env dumps).
#   2. The Bearer char class [A-Za-z0-9._-]+ excluded '=', so base64-padded
#      tokens were only partially redacted — the padding and anything after a
#      stripped match boundary leaked.
#
# Note: this suite covers redact_secrets() from lib/invoke-diagnostics.sh.
# The sibling lib lib/secret-redaction.sh (_redact_secrets) has its own suite
# in tests/unit/secret-redaction.bats.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/invoke-diagnostics.sh"
}

# Source-and-run helper. invoke-diagnostics.sh sets `set -euo pipefail`;
# calling through a command substitution keeps that confined to the subshell.
redact() {
    # shellcheck disable=SC1090
    source "$LIB"
    printf '%s\n' "$1" | redact_secrets
}

# -----------------------------------------------------------------------------
# AWS key-ID prefix classes (table-driven) — bug #1009 gap 1
# AKIA was already covered; ASIA/AROA/AGPA/AIPA/ANPA/ANVA are the red rows.
# -----------------------------------------------------------------------------
@test "bug-1009: every AWS key-ID prefix class is redacted (table-driven)" {
    local prefix out failed=""
    for prefix in AKIA ASIA AROA AGPA AIPA ANPA ANVA; do
        out="$(redact "aws_key=${prefix}IOSFODNN7EXAMPLE")"
        if [[ "$out" == *"IOSFODNN7EXAMPLE"* ]]; then
            failed+=" $prefix"
            continue
        fi
        # Prefix is preserved in the mask (diagnostic value, no leak).
        if [[ "$out" != *"${prefix}***REDACTED***"* ]]; then
            failed+=" $prefix(mask-shape)"
        fi
    done
    echo "leaking prefix classes:${failed:-none}"
    [ -z "$failed" ]
}

@test "bug-1009: ASIA session key in a CI env-dump line is redacted" {
    local out
    out="$(redact 'AWS_ACCESS_KEY_ID=ASIAIOSFODNN7EXAMPLE AWS_REGION=us-east-1')"
    [[ "$out" != *"ASIAIOSFODNN7EXAMPLE"* ]]
    [[ "$out" == *"ASIA***REDACTED***"* ]]
    # Non-secret context survives.
    [[ "$out" == *"AWS_REGION=us-east-1"* ]]
}

# -----------------------------------------------------------------------------
# Bearer base64 padding — bug #1009 gap 2
# -----------------------------------------------------------------------------
@test "bug-1009: base64-padded Bearer token is fully redacted (no '=' remnant)" {
    # Deliberately NOT an 'Authorization: ' header — the Authorization rule
    # also rewrites 'Bearer ' itself (pre-existing interplay, out of scope);
    # a neutral prefix isolates the Bearer rule under test.
    local out
    out="$(redact 'auth: Bearer dGVzdC10b2tlbi1ib2R5LXNlY3JldA==')"
    [[ "$out" != *"dGVzdC10b2tlbi1ib2R5"* ]]
    # The old pattern stopped at the first '=', leaving 'Bearer ***REDACTED***=='.
    [[ "$out" != *"REDACTED***="* ]]
    [[ "$out" == *"Bearer ***REDACTED***"* ]]
}

@test "bug-1009: Bearer token fragment after an internal '=' does not leak" {
    local out
    out="$(redact 'hdr: Bearer dG9rZW4=c2VjcmV0LXRhaWw=')"
    # Old behavior: match stopped at '=', leaking '=c2VjcmV0LXRhaWw='.
    [[ "$out" != *"c2VjcmV0LXRhaWw"* ]]
    [[ "$out" == *"Bearer ***REDACTED***"* ]]
}

# -----------------------------------------------------------------------------
# Regression pins — behavior that was already correct must stay correct
# -----------------------------------------------------------------------------
@test "bug-1009 pin: AKIA access key stays redacted with prefix-preserving mask" {
    local out
    out="$(redact 'key=AKIAIOSFODNN7EXAMPLE')"
    [[ "$out" != *"IOSFODNN7EXAMPLE"* ]]
    [[ "$out" == *"AKIA***REDACTED***"* ]]
}

@test "bug-1009 pin: unpadded Bearer token stays redacted" {
    local out
    out="$(redact 'auth: Bearer abc.def_ghi-jkl0123456789')"
    [[ "$out" != *"abc.def_ghi-jkl"* ]]
    [[ "$out" == *"Bearer ***REDACTED***"* ]]
}

@test "bug-1009 pin: sk- API key stays redacted" {
    local out
    out="$(redact 'OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz1234')"
    [[ "$out" != *"sk-abcdefghijklm"* ]]
    [[ "$out" == *"sk-***REDACTED***"* ]]
}

@test "bug-1009 pin: JWT (eyJ) stays redacted" {
    local out
    out="$(redact 'token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.sflKxwRJSMeKKF2QT4')"
    [[ "$out" != *"eyJhbGciOiJIUzI1NiJ9"* ]]
    [[ "$out" == *"eyJ***REDACTED***"* ]]
}

@test "bug-1009 pin: non-secret text passes through unchanged" {
    local out
    out="$(redact 'hello world: exit 3 after 120s')"
    [ "$out" = "hello world: exit 3 after 120s" ]
}
