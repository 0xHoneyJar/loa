#!/usr/bin/env bats
# =============================================================================
# tests/integration/endpoint-validator-cross-runtime.bats
#
# cycle-099 Sprint 1E.b — T1.15 endpoint-validator cross-runtime parity test.
#
# Per SDD §1.9.1 the validator is a centralized URL canonicalization gate that
# all HTTP callers MUST funnel through. Per §6.5 the canonicalization pipeline
# has 8 steps, each with a distinct rejection code:
#
#   1. ENDPOINT-PARSE-FAILED      — urlsplit raises
#   2. ENDPOINT-INSECURE-SCHEME   — non-https
#   3. ENDPOINT-RELATIVE          — empty netloc
#   4. ENDPOINT-IPV6-BLOCKED      — IPv6 literal in blocked range
#   5. ENDPOINT-IDN-NOT-ALLOWED   — IDN hostname not in allowlist
#   6. ENDPOINT-PORT-NOT-ALLOWED  — non-default port not allowlisted
#   7. ENDPOINT-PATH-INVALID      — path traversal / RTL / repeated slashes
#   8. ENDPOINT-NOT-ALLOWED       — host not in allowlist
#
# Sprint 1E.b first PR scope: 8-step URL canonicalization (offline string
# logic, no network). Deferred to 1E.c: TS port via Jinja2 codegen, DNS
# rebinding, redirect-chain enforcement.
#
# Cross-runtime parity (Python canonical + bash wrapper) verified by running
# the same fixture through both and asserting byte-equal JSON output.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PY_VALIDATOR="$PROJECT_ROOT/.claude/scripts/lib/endpoint-validator.py"
    SH_VALIDATOR="$PROJECT_ROOT/.claude/scripts/lib/endpoint-validator.sh"
    ALLOWLIST="$PROJECT_ROOT/tests/fixtures/endpoint-validator/allowlist.json"

    [[ -f "$PY_VALIDATOR" ]] || skip "endpoint-validator.py not present"
    [[ -f "$SH_VALIDATOR" ]] || skip "endpoint-validator.sh not present"
    [[ -f "$ALLOWLIST" ]] || skip "allowlist fixture not present"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi
    "$PYTHON_BIN" -c "import idna" 2>/dev/null \
        || skip "idna not available in $PYTHON_BIN"

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helper: validate $1 via Python canonical → JSON; also via bash wrapper → JSON;
# assert byte-equal. Sets py_out, sh_out for downstream literal assertions.
# Allowlist + caller scope come from $ALLOWLIST + a default test scope.
_validate_both() {
    local url="$1"
    py_out="$(URL="$url" ALLOWLIST_PATH="$ALLOWLIST" \
        "$PYTHON_BIN" "$PY_VALIDATOR" --json --allowlist "$ALLOWLIST" "$url" 2>&1 || true)"
    sh_out="$(URL="$url" ALLOWLIST_PATH="$ALLOWLIST" \
        bash "$SH_VALIDATOR" --json --allowlist "$ALLOWLIST" "$url" 2>&1 || true)"
}

_assert_parity() {
    local url="$1"
    _validate_both "$url"
    if [[ "$py_out" != "$sh_out" ]]; then
        printf '\n--- PARITY VIOLATION ---\n' >&2
        printf 'INPUT:  %q\n' "$url" >&2
        printf 'PYTHON: %q\n' "$py_out" >&2
        printf 'BASH:   %q\n' "$sh_out" >&2
        return 1
    fi
}

_assert_rejected_with() {
    local url="$1"
    local code="$2"
    _validate_both "$url"
    [[ "$py_out" == *"$code"* ]] || {
        printf 'PYTHON did not reject %q with %s; got: %s\n' "$url" "$code" "$py_out" >&2
        return 1
    }
    [[ "$sh_out" == *"$code"* ]] || {
        printf 'BASH did not reject %q with %s; got: %s\n' "$url" "$code" "$sh_out" >&2
        return 1
    }
}

_assert_accepted() {
    local url="$1"
    _validate_both "$url"
    # Acceptance is signaled by JSON `"valid": true` in the output.
    [[ "$py_out" == *'"valid": true'* ]] || {
        printf 'PYTHON did not accept %q; got: %s\n' "$url" "$py_out" >&2
        return 1
    }
    [[ "$sh_out" == *'"valid": true'* ]] || {
        printf 'BASH did not accept %q; got: %s\n' "$url" "$sh_out" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# E1 — Step 1: parse failures (ENDPOINT-PARSE-FAILED)
# ---------------------------------------------------------------------------

@test "E1.1 parse-failed: utterly malformed URL" {
    _assert_rejected_with 'http://[invalid-bracket' 'ENDPOINT-PARSE-FAILED'
}

@test "E1.2 parse-failed: empty string" {
    _assert_rejected_with '' 'ENDPOINT-RELATIVE'
}

# ---------------------------------------------------------------------------
# E2 — Step 2: insecure-scheme rejection (ENDPOINT-INSECURE-SCHEME)
# ---------------------------------------------------------------------------

@test "E2.1 scheme: http rejected" {
    _assert_rejected_with 'http://api.openai.com/v1' 'ENDPOINT-INSECURE-SCHEME'
}

@test "E2.2 scheme: ws rejected" {
    _assert_rejected_with 'ws://api.openai.com/v1' 'ENDPOINT-INSECURE-SCHEME'
}

@test "E2.3 scheme: custom rejected" {
    _assert_rejected_with 'gopher://api.openai.com/v1' 'ENDPOINT-INSECURE-SCHEME'
}

@test "E2.4 scheme: file:// rejected" {
    _assert_rejected_with 'file:///etc/passwd' 'ENDPOINT-INSECURE-SCHEME'
}

# ---------------------------------------------------------------------------
# E3 — Step 3: relative URL rejection (ENDPOINT-RELATIVE)
# ---------------------------------------------------------------------------

@test "E3.1 relative: missing netloc" {
    _assert_rejected_with '/v1/chat/completions' 'ENDPOINT-RELATIVE'
}

@test "E3.2 relative: scheme-only" {
    _assert_rejected_with 'https:///v1' 'ENDPOINT-RELATIVE'
}

# ---------------------------------------------------------------------------
# E4 — Step 4: IPv6 blocked-range rejection (ENDPOINT-IPV6-BLOCKED)
# ---------------------------------------------------------------------------

@test "E4.1 ipv6: loopback ::1 rejected" {
    _assert_rejected_with 'https://[::1]:443/v1' 'ENDPOINT-IPV6-BLOCKED'
}

@test "E4.2 ipv6: link-local fe80:: rejected" {
    _assert_rejected_with 'https://[fe80::1]:443/v1' 'ENDPOINT-IPV6-BLOCKED'
}

@test "E4.3 ipv6: ULA fc00:: rejected" {
    _assert_rejected_with 'https://[fc00::1]:443/v1' 'ENDPOINT-IPV6-BLOCKED'
}

@test "E4.4 ipv6: ULA fd00:: rejected" {
    _assert_rejected_with 'https://[fd00::1]:443/v1' 'ENDPOINT-IPV6-BLOCKED'
}

@test "E4.5 ipv6: multicast ff00:: rejected" {
    _assert_rejected_with 'https://[ff00::1]:443/v1' 'ENDPOINT-IPV6-BLOCKED'
}

# ---------------------------------------------------------------------------
# E5 — Step 5: IDN/punycode allowlist rejection (ENDPOINT-IDN-NOT-ALLOWED)
# ---------------------------------------------------------------------------

@test "E5.1 idn: cyrillic homograph rejected (gооgle.com with Cyrillic 'o')" {
    _assert_rejected_with 'https://gооgle.com/v1' 'ENDPOINT-IDN-NOT-ALLOWED'
}

@test "E5.2 idn: punycode form of homograph rejected" {
    _assert_rejected_with 'https://xn--ggle-vqa.com/v1' 'ENDPOINT-IDN-NOT-ALLOWED'
}

@test "E5.3 idn: legitimate punycode for unallowed host rejected" {
    _assert_rejected_with 'https://xn--fsq.com/v1' 'ENDPOINT-IDN-NOT-ALLOWED'
}

# ---------------------------------------------------------------------------
# E6 — Step 6: port allowlist rejection (ENDPOINT-PORT-NOT-ALLOWED)
# ---------------------------------------------------------------------------

@test "E6.1 port: openai on :8443 rejected" {
    _assert_rejected_with 'https://api.openai.com:8443/v1' 'ENDPOINT-PORT-NOT-ALLOWED'
}

@test "E6.2 port: anthropic on :80 rejected" {
    _assert_rejected_with 'https://api.anthropic.com:80/v1' 'ENDPOINT-PORT-NOT-ALLOWED'
}

@test "E6.3 port: google on :8080 rejected" {
    _assert_rejected_with 'https://generativelanguage.googleapis.com:8080/v1' 'ENDPOINT-PORT-NOT-ALLOWED'
}

# ---------------------------------------------------------------------------
# E7 — Step 7: path normalization rejection (ENDPOINT-PATH-INVALID)
# ---------------------------------------------------------------------------

@test "E7.1 path: .. traversal rejected" {
    _assert_rejected_with 'https://api.openai.com/v1/../admin' 'ENDPOINT-PATH-INVALID'
}

@test "E7.2 path: ./ rejected" {
    _assert_rejected_with 'https://api.openai.com/./v1' 'ENDPOINT-PATH-INVALID'
}

@test "E7.3 path: repeated slashes rejected" {
    _assert_rejected_with 'https://api.openai.com//v1' 'ENDPOINT-PATH-INVALID'
}

@test "E7.4 path: percent-encoded traversal %2e%2e rejected" {
    _assert_rejected_with 'https://api.openai.com/v1/%2e%2e/admin' 'ENDPOINT-PATH-INVALID'
}

@test "E7.5 path: RTL override (U+202E) in path rejected" {
    _assert_rejected_with $'https://api.openai.com/v1/admin‮' 'ENDPOINT-PATH-INVALID'
}

# ---------------------------------------------------------------------------
# E8 — Step 8: explicit-allowlist rejection (ENDPOINT-NOT-ALLOWED)
# ---------------------------------------------------------------------------

@test "E8.1 allowlist: unknown host rejected" {
    _assert_rejected_with 'https://attacker.example.com/v1' 'ENDPOINT-NOT-ALLOWED'
}

@test "E8.2 allowlist: subdomain typo rejected" {
    _assert_rejected_with 'https://api2.openai.com/v1' 'ENDPOINT-NOT-ALLOWED'
}

@test "E8.3 allowlist: api.openai.co (wrong TLD) rejected" {
    _assert_rejected_with 'https://api.openai.co/v1' 'ENDPOINT-NOT-ALLOWED'
}

# ---------------------------------------------------------------------------
# A — Acceptance cases (the production endpoints in our allowlist)
# ---------------------------------------------------------------------------

@test "A1 accept: openai canonical" {
    _assert_accepted 'https://api.openai.com/v1'
}

@test "A2 accept: anthropic canonical" {
    _assert_accepted 'https://api.anthropic.com/v1'
}

@test "A3 accept: google canonical" {
    _assert_accepted 'https://generativelanguage.googleapis.com/v1beta'
}

@test "A4 accept: bedrock us-east-1 canonical" {
    _assert_accepted 'https://bedrock-runtime.us-east-1.amazonaws.com'
}

@test "A5 accept: bedrock us-west-2 canonical" {
    _assert_accepted 'https://bedrock-runtime.us-west-2.amazonaws.com'
}

@test "A6 accept: openai with explicit :443 port" {
    _assert_accepted 'https://api.openai.com:443/v1'
}

@test "A7 accept: openai uppercase host normalized" {
    _assert_accepted 'https://API.OPENAI.COM/v1'
}

# ---------------------------------------------------------------------------
# P — Cross-runtime parity (every test case round-trips byte-equal)
# ---------------------------------------------------------------------------

@test "P1 parity: rejection messages identical across runtimes" {
    _assert_parity 'http://api.openai.com/v1'
    _assert_parity 'https://[::1]:443/v1'
    _assert_parity 'https://attacker.example.com/v1'
    _assert_parity 'https://api.openai.com/v1/../admin'
}

@test "P2 parity: acceptance JSON identical across runtimes" {
    _assert_parity 'https://api.openai.com/v1'
    _assert_parity 'https://api.anthropic.com/v1'
}

# ---------------------------------------------------------------------------
# C — CLI contract
# ---------------------------------------------------------------------------

@test "C1 cli: python --json mode produces valid JSON" {
    "$PYTHON_BIN" "$PY_VALIDATOR" --json --allowlist "$ALLOWLIST" 'https://api.openai.com/v1' \
        | "$PYTHON_BIN" -c 'import json, sys; json.load(sys.stdin)'
}

@test "C2 cli: bash --json mode produces valid JSON" {
    bash "$SH_VALIDATOR" --json --allowlist "$ALLOWLIST" 'https://api.openai.com/v1' \
        | "$PYTHON_BIN" -c 'import json, sys; json.load(sys.stdin)'
}

@test "C3 cli: rejection exits non-zero" {
    run "$PYTHON_BIN" "$PY_VALIDATOR" --json --allowlist "$ALLOWLIST" 'http://api.openai.com/v1'
    [[ "$status" -ne 0 ]]
}

@test "C4 cli: acceptance exits 0" {
    run "$PYTHON_BIN" "$PY_VALIDATOR" --json --allowlist "$ALLOWLIST" 'https://api.openai.com/v1'
    [[ "$status" -eq 0 ]]
}

@test "C5 cli: missing allowlist arg errors out" {
    run "$PYTHON_BIN" "$PY_VALIDATOR" --json 'https://api.openai.com/v1'
    [[ "$status" -ne 0 ]]
}

# ---------------------------------------------------------------------------
# C — Stream contract (gp M1 + cypherpunk LOW 3): rejection JSON to STDERR,
# acceptance JSON to STDOUT, both modes byte-identical across runtimes
# ---------------------------------------------------------------------------

@test "C6 stream: --json acceptance lands on STDOUT (not stderr)" {
    local out err
    out="$("$PYTHON_BIN" "$PY_VALIDATOR" --json --allowlist "$ALLOWLIST" 'https://api.openai.com/v1' 2>"$WORK_DIR/err")"
    err="$(cat "$WORK_DIR/err")"
    [[ -n "$out" ]]
    [[ -z "$err" ]]
    [[ "$out" == *'"valid": true'* ]]
}

@test "C7 stream: --json rejection lands on STDERR (not stdout)" {
    local out err
    out="$("$PYTHON_BIN" "$PY_VALIDATOR" --json --allowlist "$ALLOWLIST" 'http://attacker.example.com/v1' 2>"$WORK_DIR/err" || true)"
    err="$(cat "$WORK_DIR/err")"
    [[ -z "$out" ]]
    [[ -n "$err" ]]
    [[ "$err" == *'"valid": false'* ]]
}

@test "C8 stream: bash wrapper preserves the same stream contract" {
    local out err
    out="$(bash "$SH_VALIDATOR" --json --allowlist "$ALLOWLIST" 'http://attacker.example.com/v1' 2>"$WORK_DIR/err" || true)"
    err="$(cat "$WORK_DIR/err")"
    [[ -z "$out" ]]
    [[ -n "$err" ]]
    [[ "$err" == *'"valid": false'* ]]
}

# ---------------------------------------------------------------------------
# E0 — Userinfo rejection (general-purpose review HIGH 1)
# ---------------------------------------------------------------------------

@test "E0.1 userinfo: user:pass@ rejected" {
    _assert_rejected_with 'https://user:pass@api.openai.com/v1' 'ENDPOINT-USERINFO-PRESENT'
}

@test "E0.2 userinfo: user@ alone rejected" {
    _assert_rejected_with 'https://user@api.openai.com/v1' 'ENDPOINT-USERINFO-PRESENT'
}

@test "E0.3 userinfo: confusable api.openai.com@evil.com rejected as userinfo" {
    # urllib parses `api.openai.com@evil.com` — host=evil.com, userinfo=
    # api.openai.com. With the userinfo-reject in place the rejection reason
    # is the userinfo presence, not the host-not-allowed; clearer diagnostic
    # for the operator.
    _assert_rejected_with 'https://api.openai.com@evil.com/v1' 'ENDPOINT-USERINFO-PRESENT'
}

# ---------------------------------------------------------------------------
# E4 — IPv4 literal blocking + decimal/hex obfuscation (CRITICAL gp finding)
# ---------------------------------------------------------------------------

@test "E4.6 ipv4: 127.0.0.1 loopback rejected" {
    _assert_rejected_with 'https://127.0.0.1/v1' 'ENDPOINT-IP-BLOCKED'
}

@test "E4.7 ipv4: 169.254.169.254 AWS IMDS rejected" {
    _assert_rejected_with 'https://169.254.169.254/latest/meta-data/' 'ENDPOINT-IP-BLOCKED'
}

@test "E4.8 ipv4: 10.0.0.1 RFC 1918 private rejected" {
    _assert_rejected_with 'https://10.0.0.1/v1' 'ENDPOINT-IP-BLOCKED'
}

@test "E4.9 ipv4: 172.16.0.1 RFC 1918 private rejected" {
    _assert_rejected_with 'https://172.16.0.1/v1' 'ENDPOINT-IP-BLOCKED'
}

@test "E4.10 ipv4: 192.168.1.1 RFC 1918 private rejected" {
    _assert_rejected_with 'https://192.168.1.1/v1' 'ENDPOINT-IP-BLOCKED'
}

@test "E4.11 ipv4: 0.0.0.0 unspecified rejected" {
    _assert_rejected_with 'https://0.0.0.0/v1' 'ENDPOINT-IP-BLOCKED'
}

@test "E4.12 ipv4 obfuscation: decimal 2130706433 == 127.0.0.1 rejected" {
    _assert_rejected_with 'https://2130706433/v1' 'ENDPOINT-IP-BLOCKED'
}

@test "E4.13 ipv4 obfuscation: hex 0x7f000001 == 127.0.0.1 rejected" {
    _assert_rejected_with 'https://0x7f000001/v1' 'ENDPOINT-IP-BLOCKED'
}

@test "E4.14 ipv4 obfuscation: octal 017700000001 == 127.0.0.1 rejected" {
    _assert_rejected_with 'https://017700000001/v1' 'ENDPOINT-IP-BLOCKED'
}

# ---------------------------------------------------------------------------
# E4-extended — IPv4 obfuscation public form rejected (defense-in-depth):
# even non-private decimal IPs are rejected because no legitimate provider
# URL uses the form
# ---------------------------------------------------------------------------

@test "E4.15 ipv4 obfuscation: decimal 134744072 (8.8.8.8) rejected" {
    _assert_rejected_with 'https://134744072/v1' 'ENDPOINT-IP-BLOCKED'
}

# ---------------------------------------------------------------------------
# E4-IPv6 — public IPv6 fail-closed when allowlist is hostname-only (gp H2)
# ---------------------------------------------------------------------------

@test "E4.16 ipv6: public 2001:4860:4860::8888 rejected as IPV6-NOT-ALLOWED" {
    _assert_rejected_with 'https://[2001:4860:4860::8888]/v1' 'ENDPOINT-IPV6-NOT-ALLOWED'
}

# ---------------------------------------------------------------------------
# E5 — IDN trailing-dot FQDN normalization (cypherpunk HIGH 3)
# ---------------------------------------------------------------------------

@test "E5.4 idn: trailing-dot FQDN api.openai.com. accepted via normalization" {
    _assert_accepted 'https://api.openai.com./v1'
}

# ---------------------------------------------------------------------------
# E7 — Path-traversal regex extensions (gp H3 + cypherpunk HIGH 1 + HIGH 2)
# ---------------------------------------------------------------------------

@test "E7.6 path: half-encoded %2e./ rejected" {
    _assert_rejected_with 'https://api.openai.com/v1/%2e./admin' 'ENDPOINT-PATH-INVALID'
}

@test "E7.7 path: half-encoded .%2e/ rejected" {
    _assert_rejected_with 'https://api.openai.com/v1/.%2e/admin' 'ENDPOINT-PATH-INVALID'
}

@test "E7.8 path: uppercase %2E%2E rejected" {
    _assert_rejected_with 'https://api.openai.com/v1/%2E%2E/admin' 'ENDPOINT-PATH-INVALID'
}

@test "E7.9 path: encoded slash %2f rejected" {
    _assert_rejected_with 'https://api.openai.com/v1/..%2fadmin' 'ENDPOINT-PATH-INVALID'
}

@test "E7.10 path: NUL byte %00 rejected" {
    _assert_rejected_with 'https://api.openai.com/v1/foo%00bar' 'ENDPOINT-PATH-INVALID'
}

@test "E7.11 path: literal CR rejected (CRLF smuggling)" {
    # urllib normalizes some control chars; we assert the validator catches what
    # urllib hands us. Use printf to embed a literal CR.
    local url
    url="$(printf 'https://api.openai.com/v1\rfoo')"
    _assert_rejected_with "$url" 'ENDPOINT-PATH-INVALID'
}

@test "E7.12 path: literal LF rejected" {
    local url
    url="$(printf 'https://api.openai.com/v1\nfoo')"
    _assert_rejected_with "$url" 'ENDPOINT-PATH-INVALID'
}

@test "E7.13 path: literal TAB rejected" {
    local url
    url="$(printf 'https://api.openai.com/v1\tfoo')"
    _assert_rejected_with "$url" 'ENDPOINT-PATH-INVALID'
}

# ---------------------------------------------------------------------------
# A — Acceptance: empty / root / canonical paths (general-purpose review HIGH 4)
# ---------------------------------------------------------------------------

@test "A8 accept: bare host (no path) https://api.openai.com" {
    _assert_accepted 'https://api.openai.com'
}

@test "A9 accept: root path https://api.openai.com/" {
    _assert_accepted 'https://api.openai.com/'
}

# ---------------------------------------------------------------------------
# B — Bash wrapper hardening (cypherpunk MEDIUM 3 — argv smuggling)
# ---------------------------------------------------------------------------

@test "B1 bash: argv smuggling — URL starting with -- treated as positional" {
    # An attacker URL that begins with `--allowlist=/dev/stdin` MUST NOT be
    # parsed by argparse as a `--allowlist` flag value. The wrapper inserts a
    # `--` separator before the URL slot to enforce this.
    local fake_allowlist="$WORK_DIR/fake-allowlist.json"
    printf '{"providers": {"hijack": [{"host": "evil.com", "ports": [443]}]}}' > "$fake_allowlist"
    run bash "$SH_VALIDATOR" --json --allowlist "$ALLOWLIST" "--allowlist=$fake_allowlist"
    # The URL is the literal string `--allowlist=...`. Because of `--` the
    # validator parses it as a URL (urlsplit returns no scheme), step 1/3
    # rejects with parse-failed or relative — anything BUT
    # ENDPOINT-NOT-ALLOWED on `evil.com` (which would prove the smuggle worked).
    [[ "$status" -ne 0 ]]
    [[ "$output" != *'evil.com'* ]]
}

@test "B2 bash: missing python interpreter errors with clear code" {
    # Force the wrapper to fail by overriding PATH to nothing AND removing
    # .venv access. We do this by running through env -i.
    run env -i HOME="$HOME" PATH="/nonexistent" bash "$SH_VALIDATOR" --json --allowlist "$ALLOWLIST" 'https://api.openai.com/v1'
    # Either python3 isn't found (ENDPOINT-VALIDATOR-NO-PYTHON), or .venv path
    # is unreachable. Either way the wrapper exits non-zero with our prefix.
    [[ "$status" -ne 0 ]]
}

# ---------------------------------------------------------------------------
# E4-zone — IPv6 zone-id regression (cypherpunk MEDIUM 2)
# ---------------------------------------------------------------------------

@test "E4.17 ipv6 zone-id: [fe80::1%25eth0] still rejected as link-local" {
    # Per RFC 6874 IPv6 zone IDs in URLs are %-encoded (% → %25). The link-
    # local range fe80::/10 must reject regardless of zone suffix.
    _assert_rejected_with 'https://[fe80::1%25eth0]/v1' 'ENDPOINT-IPV6-BLOCKED'
}
