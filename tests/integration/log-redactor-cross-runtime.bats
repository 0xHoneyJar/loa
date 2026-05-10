#!/usr/bin/env bats
# =============================================================================
# tests/integration/log-redactor.bats
#
# cycle-099 Sprint 1E — T1.13 log-redactor cross-runtime parity test.
#
# Per SDD §5.6 the redactor masks URL userinfo + 6 query-string secret
# patterns (key, token, secret, password, api_key, auth) case-insensitively
# while preserving structural identity (separators + parameter-name case).
#
# The bats test runs both the Python canonical (.claude/scripts/lib/log-redactor.py)
# and the bash twin (.claude/scripts/lib/log-redactor.sh) against the SDD §5.6.4
# fixture corpus and asserts byte-equal output. Divergence indicates a runtime
# missed a pattern.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PY_REDACTOR="$PROJECT_ROOT/.claude/scripts/lib/log-redactor.py"
    BASH_REDACTOR="$PROJECT_ROOT/.claude/scripts/lib/log-redactor.sh"

    [[ -f "$PY_REDACTOR" ]] || skip "log-redactor.py not present"
    [[ -f "$BASH_REDACTOR" ]] || skip "log-redactor.sh not present"

    # Choose a Python interpreter. The redactor is stdlib-only so any python3
    # works; .venv is preferred for reproducibility but fall through to system.
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helper: run both redactors on $1 and compare byte-equality.
# Sets $py_out, $sh_out for downstream assertions.
_redact_both() {
    local input="$1"
    py_out="$(printf '%s' "$input" | "$PYTHON_BIN" "$PY_REDACTOR")"
    # shellcheck disable=SC1090
    sh_out="$(printf '%s' "$input" | bash "$BASH_REDACTOR")"
}

# Helper: assert byte-equal output between python + bash for the given input.
_assert_parity() {
    local input="$1"
    _redact_both "$input"
    if [[ "$py_out" != "$sh_out" ]]; then
        printf '\n--- PARITY VIOLATION ---\n' >&2
        printf 'INPUT:  %q\n' "$input" >&2
        printf 'PYTHON: %q\n' "$py_out" >&2
        printf 'BASH:   %q\n' "$sh_out" >&2
        return 1
    fi
}

# Tighter helper (review remediation G-M3): runs both redactors and asserts
# BOTH match the expected literal. Single source of truth for the literal
# eliminates the vacuous-green failure mode where one runtime silently
# matches a relaxed value while the other still pins the literal.
_assert_redacts_to() {
    local input="$1"
    local expected="$2"
    _redact_both "$input"
    if [[ "$py_out" != "$expected" ]]; then
        printf '\n--- PYTHON OUTPUT MISMATCH ---\n' >&2
        printf 'INPUT:    %q\n' "$input" >&2
        printf 'EXPECTED: %q\n' "$expected" >&2
        printf 'GOT:      %q\n' "$py_out" >&2
        return 1
    fi
    if [[ "$sh_out" != "$expected" ]]; then
        printf '\n--- BASH OUTPUT MISMATCH ---\n' >&2
        printf 'INPUT:    %q\n' "$input" >&2
        printf 'EXPECTED: %q\n' "$expected" >&2
        printf 'GOT:      %q\n' "$sh_out" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# T1 — URL userinfo redaction (SDD §5.6.4 case 1)
# ---------------------------------------------------------------------------

@test "T1.1 url userinfo: simple user:pass@host" {
    _assert_redacts_to \
        'https://user:pass@api.example.com/v1' \
        'https://[REDACTED]@api.example.com/v1'
}

@test "T1.2 url userinfo: token-form (no colon)" {
    _redact_both 'https://abctok123@api.example.com/v1'
    [[ "$py_out" = 'https://[REDACTED]@api.example.com/v1' ]]
    _assert_parity 'https://abctok123@api.example.com/v1'
}

@test "T1.3 url userinfo: scheme variations http/ws/postgres" {
    _assert_parity 'http://u:p@host/'
    _assert_parity 'ws://u:p@host:8080/'
    _assert_parity 'postgres://app:secret@db.internal:5432/main'
}

@test "T1.4 url userinfo: no userinfo passes through" {
    _assert_redacts_to 'https://api.example.com/v1' 'https://api.example.com/v1'
}

@test "T1.5 url userinfo with empty userinfo (just '@')" {
    _assert_redacts_to 'https://@api.example.com/' 'https://[REDACTED]@api.example.com/'
}

# ---------------------------------------------------------------------------
# T2 — Query parameter redaction (mixed redacted + non-redacted)
# ---------------------------------------------------------------------------

@test "T2.1 query: key, token, foo - foo unchanged" {
    _redact_both 'https://h/v1?key=abc&token=def&foo=bar'
    [[ "$py_out" = 'https://h/v1?key=[REDACTED]&token=[REDACTED]&foo=bar' ]]
    _assert_parity 'https://h/v1?key=abc&token=def&foo=bar'
}

@test "T2.2 query: all six secret types in one URL" {
    _assert_redacts_to \
        'https://h/?key=K&token=T&secret=S&password=P&api_key=A&auth=AU' \
        'https://h/?key=[REDACTED]&token=[REDACTED]&secret=[REDACTED]&password=[REDACTED]&api_key=[REDACTED]&auth=[REDACTED]'
}

@test "T2.3 query: param at end of URL (no trailing &)" {
    _redact_both 'https://h/?token=trailing'
    [[ "$py_out" = 'https://h/?token=[REDACTED]' ]]
    _assert_parity 'https://h/?token=trailing'
}

@test "T2.4 query: param value containing equals sign" {
    _redact_both 'https://h/?token=a=b=c&foo=bar'
    [[ "$py_out" = 'https://h/?token=[REDACTED]&foo=bar' ]]
    _assert_parity 'https://h/?token=a=b=c&foo=bar'
}

# ---------------------------------------------------------------------------
# T3 — Multiline (SDD §5.6.4 case 3)
# ---------------------------------------------------------------------------

@test "T3.1 multiline: each line redacted independently" {
    local input
    input=$'url1: https://u1:p1@a/v1\nurl2: https://u2:p2@b/v2'
    local expected
    expected=$'url1: https://[REDACTED]@a/v1\nurl2: https://[REDACTED]@b/v2'
    _redact_both "$input"
    [[ "$py_out" = "$expected" ]]
    _assert_parity "$input"
}

@test "T3.2 multiline: redaction does not span newlines" {
    # URL on line 1 has no userinfo; URL on line 2 has @ — must not greedy-match across newlines
    local input
    input=$'first: https://no-userinfo.example.com/path\nsecond: https://u:p@host/'
    local expected
    expected=$'first: https://no-userinfo.example.com/path\nsecond: https://[REDACTED]@host/'
    _redact_both "$input"
    [[ "$py_out" = "$expected" ]]
    _assert_parity "$input"
}

@test "T3.3 multiline: query params split by newline" {
    local input
    input=$'?token=abc\n&key=def'
    local expected
    expected=$'?token=[REDACTED]\n&key=[REDACTED]'
    _redact_both "$input"
    [[ "$py_out" = "$expected" ]]
    _assert_parity "$input"
}

# ---------------------------------------------------------------------------
# T4 — URL-encoded chars (SDD §5.6.4 case 4)
# ---------------------------------------------------------------------------

@test "T4.1 encoded: percent-encoded value redacted as one unit" {
    _redact_both 'https://h/?token=abc%20def'
    [[ "$py_out" = 'https://h/?token=[REDACTED]' ]]
    _assert_parity 'https://h/?token=abc%20def'
}

@test "T4.2 encoded: special chars in value (no premature termination)" {
    _redact_both 'https://h/?secret=a:b@c/d?e'
    [[ "$py_out" = 'https://h/?secret=[REDACTED]' ]]
    _assert_parity 'https://h/?secret=a:b@c/d?e'
}

# ---------------------------------------------------------------------------
# T5 — Empty values (SDD §5.6.4 case 5)
# ---------------------------------------------------------------------------

@test "T5.1 empty value: ?token=&key=foo" {
    _redact_both 'https://h/?token=&key=foo'
    [[ "$py_out" = 'https://h/?token=[REDACTED]&key=[REDACTED]' ]]
    _assert_parity 'https://h/?token=&key=foo'
}

@test "T5.2 empty value at end: ?token=" {
    _redact_both 'https://h/?token='
    [[ "$py_out" = 'https://h/?token=[REDACTED]' ]]
    _assert_parity 'https://h/?token='
}

# ---------------------------------------------------------------------------
# T6 — Case-insensitive parameter name + case preservation (SDD §5.6.4 case 6)
# ---------------------------------------------------------------------------

@test "T6.1 case: ?Token preserves capital T" {
    _redact_both 'https://h/?Token=abc'
    [[ "$py_out" = 'https://h/?Token=[REDACTED]' ]]
    _assert_parity 'https://h/?Token=abc'
}

@test "T6.2 case: ?TOKEN all-caps preserved" {
    _redact_both 'https://h/?TOKEN=abc'
    [[ "$py_out" = 'https://h/?TOKEN=[REDACTED]' ]]
    _assert_parity 'https://h/?TOKEN=abc'
}

@test "T6.3 case: mixed Api_Key preserved" {
    _redact_both 'https://h/?Api_Key=abc'
    [[ "$py_out" = 'https://h/?Api_Key=[REDACTED]' ]]
    _assert_parity 'https://h/?Api_Key=abc'
}

@test "T6.4 case: each name in mixed-case URL" {
    _assert_redacts_to \
        'https://h/?Key=1&TOKEN=2&Secret=3&PASSWORD=4&Api_Key=5&AUTH=6' \
        'https://h/?Key=[REDACTED]&TOKEN=[REDACTED]&Secret=[REDACTED]&PASSWORD=[REDACTED]&Api_Key=[REDACTED]&AUTH=[REDACTED]'
}

# ---------------------------------------------------------------------------
# T7 — No URL / passthrough (SDD §5.6.4 case 7)
# ---------------------------------------------------------------------------

@test "T7.1 passthrough: plain text unchanged" {
    _assert_redacts_to 'this is plain text with no URL' 'this is plain text with no URL'
}

@test "T7.2 passthrough: empty input" {
    _assert_redacts_to '' ''
}

@test "T7.3 passthrough: special chars without URL" {
    _redact_both 'foo & bar | baz # quux $ @ at-sign'
    [[ "$py_out" = 'foo & bar | baz # quux $ @ at-sign' ]]
    _assert_parity 'foo & bar | baz # quux $ @ at-sign'
}

@test "T7.4 passthrough: similar but non-secret param names" {
    # 'keyword' and 'token_count' don't end immediately after the param name
    # with '=', so they should NOT be redacted. 'api_key_2' likewise has '_2'
    # before '='. 'authentic' is not 'auth'.
    _assert_redacts_to \
        'https://h/?keyword=fine&token_count=5&secret_chamber=ok&authentic=yes&api_key_2=4' \
        'https://h/?keyword=fine&token_count=5&secret_chamber=ok&authentic=yes&api_key_2=4'
}

# ---------------------------------------------------------------------------
# T8 — Mixed (SDD §5.6.4 case 8)
# ---------------------------------------------------------------------------

@test "T8.1 mixed: MODEL-RESOLVE log line with userinfo + api_key" {
    _assert_redacts_to \
        '[MODEL-RESOLVE] skill=flatline endpoint=https://user:pass@api.example.com/v1?api_key=secret' \
        '[MODEL-RESOLVE] skill=flatline endpoint=https://[REDACTED]@api.example.com/v1?api_key=[REDACTED]'
}

@test "T8.2 mixed: redactor is line-level, not JSON-aware" {
    # SDD §5.6.2 defines `[^&]*` as the only query-value stop-char (with `\n`
    # added implicitly because sed is line-based and the Python regex excludes
    # `\n`). A JSON `"` is NOT a boundary; redacting an entire JSON string
    # consumes the trailing `"}`. Application code is expected to redact URL
    # fragments BEFORE JSON encoding, not after. This test pins that contract.
    local input='{"endpoint":"https://u:p@api.example.com/v1?token=xyz"}'
    local expected='{"endpoint":"https://[REDACTED]@api.example.com/v1?token=[REDACTED]'
    _redact_both "$input"
    [[ "$py_out" = "$expected" ]]
    [[ "$sh_out" = "$expected" ]]
    _assert_parity "$input"
}

@test "T8.3 mixed: structured key=value log line (recommended caller shape)" {
    # `&` is NOT in the input, so api_key=[REDACTED] consumes everything until
    # next `\n` or EOF — including the trailing ` status=resolved`. To prevent
    # this, callers should redact endpoint VALUE in isolation OR ensure the
    # log format uses `&` between fields when value-after-secret is needed.
    # This test pins that expectation. (Caller contract is documented in
    # log-redactor.py module docstring.)
    _assert_redacts_to \
        '[MODEL-RESOLVE] endpoint=https://u:p@host/v1?api_key=secret status=resolved' \
        '[MODEL-RESOLVE] endpoint=https://[REDACTED]@host/v1?api_key=[REDACTED]'
}

@test "T8.4 caller-contract: bare key=val without URL framing is NOT redacted (in-contract)" {
    # SDD §5.6.2 requires `[?&]` separator before the secret-bearing param
    # name. A bare `api_key=secret` without URL framing falls outside the
    # redactor's scope. Callers must reformat their log emission OR redact
    # the value in isolation (see log-redactor.py docstring).
    _assert_redacts_to \
        '[MODEL-RESOLVE] api_key=should-not-be-redacted' \
        '[MODEL-RESOLVE] api_key=should-not-be-redacted'
}

# ---------------------------------------------------------------------------
# T9 — Idempotency (redact-twice == redact-once)
# ---------------------------------------------------------------------------

@test "T9.1 idempotency: python redact-twice equals once" {
    local input='https://u:p@h/?token=secret'
    local once
    once="$(printf '%s' "$input" | "$PYTHON_BIN" "$PY_REDACTOR")"
    local twice
    twice="$(printf '%s' "$once" | "$PYTHON_BIN" "$PY_REDACTOR")"
    [[ "$once" = "$twice" ]]
}

@test "T9.2 idempotency: bash redact-twice equals once" {
    local input='https://u:p@h/?token=secret'
    local once
    once="$(printf '%s' "$input" | bash "$BASH_REDACTOR")"
    local twice
    twice="$(printf '%s' "$once" | bash "$BASH_REDACTOR")"
    [[ "$once" = "$twice" ]]
}

# ---------------------------------------------------------------------------
# T10 — Pathological / safety inputs
# ---------------------------------------------------------------------------

@test "T10.1 safety: very long input does not hang or crash" {
    local long_input
    long_input="$(printf 'https://u:p@h/?token=%s' "$(printf 'a%.0s' {1..1000})")"
    timeout 5 bash -c "printf '%s' \"\$1\" | \"$PYTHON_BIN\" \"$PY_REDACTOR\" > /dev/null" _ "$long_input"
    [[ $? -eq 0 ]]
    timeout 5 bash -c "printf '%s' \"\$1\" | bash \"$BASH_REDACTOR\" > /dev/null" _ "$long_input"
    [[ $? -eq 0 ]]
}

@test "T10.2 safety: nested @ chars in userinfo" {
    # https://user@with-at@host/ — only first '@' terminates userinfo per RFC,
    # so first segment 'user' is the userinfo. Both runtimes should agree.
    _assert_parity 'https://user@with-at@host/'
}

@test "T10.3 safety: regex metachars in non-secret values" {
    _redact_both 'https://h/?token=.*\\$^&foo=ok'
    [[ "$py_out" = 'https://h/?token=[REDACTED]&foo=ok' ]]
    _assert_parity 'https://h/?token=.*\\$^&foo=ok'
}

# ---------------------------------------------------------------------------
# T11 — Module surface (CLI invocation contract)
# ---------------------------------------------------------------------------

@test "T11.1 module: python prints exit-0 on stdin redaction" {
    run bash -c "printf 'plain\n' | \"$PYTHON_BIN\" \"$PY_REDACTOR\""
    [[ "$status" -eq 0 ]]
    [[ "$output" = "plain" ]]
}

@test "T11.2 module: bash sourceable + _redact callable" {
    # shellcheck disable=SC1090
    source "$BASH_REDACTOR"
    run bash -c "source \"$BASH_REDACTOR\" && printf '?token=x' | _redact"
    [[ "$status" -eq 0 ]]
    [[ "$output" = '?token=[REDACTED]' ]]
}

@test "T11.3 module: bash direct invocation (script as filter)" {
    run bash -c "printf '?key=v' | bash \"$BASH_REDACTOR\""
    [[ "$status" -eq 0 ]]
    [[ "$output" = '?key=[REDACTED]' ]]
}

# ---------------------------------------------------------------------------
# T12 — NUL byte safety (defense-in-depth; debug logs should be ASCII text)
# ---------------------------------------------------------------------------

@test "T12.1 nul: input without NUL passes through both runtimes" {
    # Byte-level sanity: ensure non-NUL multi-byte input round-trips identically.
    # NUL bytes are out-of-scope for both runtimes (sed truncates at NUL on many
    # systems; Python depends on stdin decoding); we don't assert NUL behavior
    # but DO assert that all printable ASCII passes through cleanly.
    local input
    input="$(printf '%s' '!"#$%&'"'"'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_\`abcdefghijklmnopqrstuvwxyz{|}~')"
    _assert_redacts_to "$input" "$input"
}

# ---------------------------------------------------------------------------
# T13 — AKIA AWS access keys (cycle-102 sprint-1D / T1.7.b)
#
# Per Sprint 1D §5.6 extension: the redactor recognizes `AKIA[0-9A-Z]{16}`
# (20 chars total) regardless of URL framing. Real AWS access keys are
# always exactly 20 chars; the [REDACTED-AKIA] sentinel preserves
# debuggability while masking the secret value.
# ---------------------------------------------------------------------------

@test "T13.1 akia: bare access key is masked" {
    # Real-shape AKIA: 4-char prefix + 16-char [0-9A-Z] suffix.
    _assert_redacts_to \
        'AKIAIOSFODNN7EXAMPLE' \
        '[REDACTED-AKIA]'
}

@test "T13.2 akia: in surrounding text" {
    _assert_redacts_to \
        'Error 403: credentials AKIAIOSFODNN7EXAMPLE were rejected.' \
        'Error 403: credentials [REDACTED-AKIA] were rejected.'
}

@test "T13.3 akia: multiple keys in same input" {
    _assert_redacts_to \
        'first AKIAIOSFODNN7EXAMPLE second AKIAIOSFODNN7DUMMYY3' \
        'first [REDACTED-AKIA] second [REDACTED-AKIA]'
}

@test "T13.4 akia: lowercase prefix does NOT match (real keys are uppercase)" {
    _assert_redacts_to \
        'akiaiosfodnn7example' \
        'akiaiosfodnn7example'
}

@test "T13.5 akia: too-short suffix passes through (15 chars not 16)" {
    # Negative control: ensures false-positive on AKIAxxxxxxxxxxxxxxx (15
    # alnum chars) does NOT trigger. Real keys are exactly 16 chars after
    # AKIA; shorter strings are not access keys.
    _assert_redacts_to \
        'AKIAONLYFIFTEENN' \
        'AKIAONLYFIFTEENN'
}

@test "T13.6 akia: lowercase chars in suffix do NOT match" {
    # AKIA prefix matches but suffix `[0-9A-Z]{16}` rejects lowercase.
    _assert_redacts_to \
        'AKIAlowercasesuffix' \
        'AKIAlowercasesuffix'
}

@test "T13.7 akia: idempotent (already-redacted input passes through)" {
    local input='already=[REDACTED-AKIA] here'
    _redact_both "$input"
    [[ "$py_out" = "$input" ]]
    [[ "$sh_out" = "$input" ]]
}

# ---------------------------------------------------------------------------
# T14 — PEM private-key blocks (cycle-102 sprint-1D / T1.7.b)
#
# Multi-line PEM redaction. Bash twin uses sed slurp (`:a;N;$!ba;`); Python
# canonical uses `[^-]*` body class (base64 PEM body never contains `-`).
# Both produce byte-equal output across all named-algorithm variants.
# ---------------------------------------------------------------------------

@test "T14.1 pem: PKCS#8 unnamed private key" {
    local input
    input=$'-----BEGIN PRIVATE KEY-----\nMIIBVQIBADANBgkqhkiG9w0BAQEFAAS=\n-----END PRIVATE KEY-----'
    _assert_redacts_to "$input" '[REDACTED-PRIVATE-KEY]'
}

@test "T14.2 pem: RSA private key with algorithm name" {
    local input
    input=$'-----BEGIN RSA PRIVATE KEY-----\nMIICXQIBAAKBgQDH8R\n-----END RSA PRIVATE KEY-----'
    _assert_redacts_to "$input" '[REDACTED-PRIVATE-KEY]'
}

@test "T14.3 pem: EC private key with algorithm name" {
    local input
    input=$'-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIH8mP6+0\n-----END EC PRIVATE KEY-----'
    _assert_redacts_to "$input" '[REDACTED-PRIVATE-KEY]'
}

@test "T14.4 pem: surrounded by text on both sides" {
    local input expected
    input=$'before line\n-----BEGIN PRIVATE KEY-----\nbody=\n-----END PRIVATE KEY-----\nafter line'
    expected=$'before line\n[REDACTED-PRIVATE-KEY]\nafter line'
    _assert_redacts_to "$input" "$expected"
}

@test "T14.5 pem: missing END marker passes through (defense-in-depth)" {
    # Fragment without closing marker is NOT a complete PEM block; redactor
    # leaves it untouched. The cheval-side gate (T1.7.e) catches this case
    # via shape-of-BEGIN-marker detection.
    local input
    input=$'-----BEGIN PRIVATE KEY-----\nbody'
    _assert_redacts_to "$input" "$input"
}

@test "T14.6 pem: idempotent" {
    local input='already=[REDACTED-PRIVATE-KEY] here'
    _redact_both "$input"
    [[ "$py_out" = "$input" ]]
    [[ "$sh_out" = "$input" ]]
}

# ---------------------------------------------------------------------------
# T15 — Bearer-token shape (cycle-102 sprint-1D / T1.7.b)
#
# Case-insensitive on `Bearer` (RFC 7235 HTTP scheme is case-insensitive).
# Token charset is the union of base64url + standard base64 + RFC 6750.
# Separator MUST be space-or-tab (POSIX BRE parity with bash twin's
# `[ <tab>]` literal class — NOT `[[:space:]]` which would also match
# `\n`/`\f`/`\v` in pattern space).
# ---------------------------------------------------------------------------

@test "T15.1 bearer: standard JWT-shape token (space sep)" {
    _assert_redacts_to \
        'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.fake.token' \
        'Authorization: [REDACTED-BEARER-TOKEN]'
}

@test "T15.2 bearer: lowercase scheme keyword" {
    _assert_redacts_to \
        'authorization: bearer abc123def456' \
        'authorization: [REDACTED-BEARER-TOKEN]'
}

@test "T15.3 bearer: tab separator" {
    local input
    input=$'Authorization:\tBearer\tabc.def-ghi'
    _assert_redacts_to "$input" $'Authorization:\t[REDACTED-BEARER-TOKEN]'
}

@test "T15.4 bearer: opaque OAuth token (with =/+ chars)" {
    _assert_redacts_to \
        'Bearer ya29.A0AfH6SM/B+xyz=' \
        '[REDACTED-BEARER-TOKEN]'
}

@test "T15.5 bearer: multiple Bearer tokens in same input" {
    _assert_redacts_to \
        'A: Bearer aaa.bbb B: Bearer ccc.ddd' \
        'A: [REDACTED-BEARER-TOKEN] B: [REDACTED-BEARER-TOKEN]'
}

@test "T15.6 bearer: word 'Bearer' alone (no token) passes through" {
    # Pattern requires Bearer + separator + token chars (one or more).
    # The literal word "Bearer" without a following token is not a header.
    _assert_redacts_to 'The Bearer of this letter' 'The Bearer of this letter'
}

@test "T15.7 bearer: idempotent" {
    local input='already=[REDACTED-BEARER-TOKEN] here'
    _redact_both "$input"
    [[ "$py_out" = "$input" ]]
    [[ "$sh_out" = "$input" ]]
}

# ---------------------------------------------------------------------------
# T16 — Pass-order regression (cycle-102 sprint-1D / T1.7.c)
#
# Mixed input exercising all 5 passes. Confirms (a) the line-by-line passes
# don't collide with the slurp pass and (b) byte-equality holds when
# multiple secret types appear in the same input.
# ---------------------------------------------------------------------------

@test "T16.1 mixed: AKIA + Bearer + URL + PEM in one input" {
    local input expected
    input=$'curl https://u:p@host/?api_key=secret with AKIAIOSFODNN7EXAMPLE\nAuthorization: Bearer eyJ.fake.tok\n-----BEGIN PRIVATE KEY-----\nbody\n-----END PRIVATE KEY-----'
    expected=$'curl https://[REDACTED]@host/?api_key=[REDACTED] with [REDACTED-AKIA]\nAuthorization: [REDACTED-BEARER-TOKEN]\n[REDACTED-PRIVATE-KEY]'
    _assert_redacts_to "$input" "$expected"
}

@test "T16.2 mixed: idempotent on already-redacted mixed input" {
    local input
    input=$'mix [REDACTED-AKIA] | [REDACTED-BEARER-TOKEN]\n[REDACTED-PRIVATE-KEY]'
    _redact_both "$input"
    [[ "$py_out" = "$input" ]]
    [[ "$sh_out" = "$input" ]]
}
