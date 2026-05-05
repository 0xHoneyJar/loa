#!/usr/bin/env bats
# =============================================================================
# tests/integration/endpoint-validator-ts-parity.bats
#
# cycle-099 Sprint 1E.c.1 — TS-from-Python codegen byte-equal parity test.
#
# Per SDD §1.9.1 IMP-002, the TS validator at
# .claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts
# is generated from .claude/scripts/lib/endpoint-validator.py via the
# loa_cheval.codegen.emit_endpoint_validator_ts module + Jinja2 template.
#
# This bats suite asserts:
#   1. The committed .generated.ts matches a fresh codegen run (drift gate).
#   2. The TS validator produces byte-equal JSON output to the Python canonical
#      across the §6.5 fixture corpus (acceptance + every rejection code).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    PY_VALIDATOR="$PROJECT_ROOT/.claude/scripts/lib/endpoint-validator.py"
    TS_GENERATED="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts"
    TS_TEMPLATE="$PROJECT_ROOT/.claude/scripts/lib/codegen/endpoint-validator.ts.j2"
    EMIT_MODULE_PARENT="$PROJECT_ROOT/.claude/adapters"
    ALLOWLIST="$PROJECT_ROOT/tests/fixtures/endpoint-validator/allowlist.json"

    [[ -f "$PY_VALIDATOR" ]] || skip "endpoint-validator.py not present"
    [[ -f "$TS_GENERATED" ]] || skip "endpoint-validator.generated.ts not present"
    [[ -f "$TS_TEMPLATE" ]] || skip "endpoint-validator.ts.j2 template not present"
    [[ -f "$ALLOWLIST" ]] || skip "allowlist fixture not present"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi
    "$PYTHON_BIN" -c "import idna, jinja2" 2>/dev/null \
        || skip "idna or jinja2 not available in $PYTHON_BIN"

    # tsx must be available — the BB skill ships it.
    if [[ -x "$PROJECT_ROOT/.claude/skills/bridgebuilder-review/node_modules/.bin/tsx" ]]; then
        TSX_BIN="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/node_modules/.bin/tsx"
    elif command -v tsx >/dev/null 2>&1; then
        TSX_BIN="$(command -v tsx)"
    else
        skip "tsx not available (run npm ci in .claude/skills/bridgebuilder-review)"
    fi

    WORK_DIR="$(mktemp -d)"

    # A tiny TS driver that imports the generated validator and runs one URL
    # through it, emitting JSON identical to the Python CLI's --json output.
    TS_DRIVER="$WORK_DIR/run-validator.ts"
    cat > "$TS_DRIVER" <<TS_EOF
import { validate, loadAllowlist } from "$TS_GENERATED";
import { readFileSync } from "node:fs";

const allowlistPath = process.argv[2];
const url = process.argv[3];
const allowlist = loadAllowlist(JSON.parse(readFileSync(allowlistPath, "utf-8")));
const result = validate(url, allowlist);

// Match Python's emit shape: drop None/null values, sort keys, indent 2.
const cleaned: Record<string, unknown> = {};
const ordered = Object.keys(result).sort();
for (const k of ordered) {
    const v = (result as any)[k];
    if (v === null || v === undefined) continue;
    cleaned[k] = v;
}
const out = JSON.stringify(cleaned, Object.keys(cleaned).sort(), 2);
if (result.valid) {
    process.stdout.write(out);
} else {
    process.stderr.write(out);
    process.exit(78);
}
TS_EOF
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helper: run URL through both runtimes, capture stdout-only on accept and
# stderr-only on reject (matches Python's stream contract from sprint-1E.b).
_run_both() {
    local url="$1"
    local py_stdout="$WORK_DIR/py.stdout"
    local py_stderr="$WORK_DIR/py.stderr"
    local ts_stdout="$WORK_DIR/ts.stdout"
    local ts_stderr="$WORK_DIR/ts.stderr"
    "$PYTHON_BIN" "$PY_VALIDATOR" --json --allowlist "$ALLOWLIST" "$url" \
        > "$py_stdout" 2> "$py_stderr" || true
    "$TSX_BIN" "$TS_DRIVER" "$ALLOWLIST" "$url" \
        > "$ts_stdout" 2> "$ts_stderr" || true
    py_out="$(cat "$py_stdout" "$py_stderr")"
    ts_out="$(cat "$ts_stdout" "$ts_stderr")"
}

_assert_parity() {
    # Canonical-form parity: extract the structural fields per SDD §1.9.1
    # ("byte-equal canonicalized output OR byte-equal rejection error
    # structure"). The `detail` field is operator-readable diagnostic text;
    # its exact wording is intentionally NOT part of the cross-runtime parity
    # contract because the two runtimes phrase the same condition slightly
    # differently (e.g., bracket inclusion in IPv6 hostnames).
    local url="$1"
    _run_both "$url"
    local py_canonical ts_canonical
    py_canonical="$(printf '%s' "$py_out" | "$PYTHON_BIN" -c '
import json, sys
d = json.loads(sys.stdin.read())
keep = ("valid", "code", "url", "scheme", "host", "port", "path", "matched_provider")
out = {k: d[k] for k in keep if k in d}
print(json.dumps(out, indent=2, sort_keys=True))
')"
    ts_canonical="$(printf '%s' "$ts_out" | "$PYTHON_BIN" -c '
import json, sys
d = json.loads(sys.stdin.read())
keep = ("valid", "code", "url", "scheme", "host", "port", "path", "matched_provider")
out = {k: d[k] for k in keep if k in d}
print(json.dumps(out, indent=2, sort_keys=True))
')"
    if [[ "$py_canonical" != "$ts_canonical" ]]; then
        printf '\n--- TS PARITY VIOLATION (canonical fields) ---\n' >&2
        printf 'INPUT:        %q\n' "$url" >&2
        printf 'PYTHON full:  %s\n' "$py_out" >&2
        printf 'TS full:      %s\n' "$ts_out" >&2
        printf 'PYTHON canon: %s\n' "$py_canonical" >&2
        printf 'TS canon:     %s\n' "$ts_canonical" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# D — Drift gate: committed .generated.ts must match fresh codegen
# ---------------------------------------------------------------------------

@test "D1 drift: committed endpoint-validator.generated.ts matches fresh codegen" {
    local fresh="$WORK_DIR/fresh.ts"
    PYTHONPATH="$EMIT_MODULE_PARENT" \
        "$PYTHON_BIN" -m loa_cheval.codegen.emit_endpoint_validator_ts > "$fresh"
    diff -u "$TS_GENERATED" "$fresh"
}

# ---------------------------------------------------------------------------
# A — Acceptance parity (each provider's canonical endpoint)
# ---------------------------------------------------------------------------

@test "A1 parity-accept: openai canonical" {
    _assert_parity 'https://api.openai.com/v1'
}

@test "A2 parity-accept: anthropic canonical" {
    _assert_parity 'https://api.anthropic.com/v1'
}

@test "A3 parity-accept: google canonical" {
    _assert_parity 'https://generativelanguage.googleapis.com/v1beta'
}

@test "A4 parity-accept: bedrock us-east-1 canonical" {
    _assert_parity 'https://bedrock-runtime.us-east-1.amazonaws.com'
}

@test "A5 parity-accept: openai uppercase host normalized" {
    _assert_parity 'https://API.OPENAI.COM/v1'
}

@test "A6 parity-accept: openai with trailing-dot FQDN" {
    _assert_parity 'https://api.openai.com./v1'
}

@test "A7 parity-accept: openai bare host (no path)" {
    _assert_parity 'https://api.openai.com'
}

@test "A8 parity-accept: openai root path" {
    _assert_parity 'https://api.openai.com/'
}

# ---------------------------------------------------------------------------
# E — Rejection parity (one fixture per SDD §6.5 step + sprint-1E.b additions)
# ---------------------------------------------------------------------------

@test "E1 parity-reject: parse failed (unmatched brackets)" {
    _assert_parity 'http://[invalid-bracket'
}

@test "E2 parity-reject: insecure scheme http" {
    _assert_parity 'http://api.openai.com/v1'
}

@test "E3 parity-reject: relative URL" {
    _assert_parity '/v1/chat/completions'
}

@test "E4 parity-reject: ipv6 loopback ::1" {
    _assert_parity 'https://[::1]:443/v1'
}

@test "E5 parity-reject: ipv6 link-local fe80::" {
    _assert_parity 'https://[fe80::1]:443/v1'
}

@test "E6 parity-reject: idn cyrillic homograph" {
    _assert_parity 'https://gооgle.com/v1'
}

@test "E7 parity-reject: port not allowlisted (8443)" {
    _assert_parity 'https://api.openai.com:8443/v1'
}

@test "E8 parity-reject: path traversal .." {
    _assert_parity 'https://api.openai.com/v1/../admin'
}

@test "E9 parity-reject: half-encoded path %2e./" {
    _assert_parity 'https://api.openai.com/v1/%2e./admin'
}

@test "E10 parity-reject: encoded slash %2f" {
    _assert_parity 'https://api.openai.com/v1/..%2fadmin'
}

@test "E11 parity-reject: percent-encoded NUL %00" {
    _assert_parity 'https://api.openai.com/v1/foo%00bar'
}

@test "E12 parity-reject: host not allowlisted" {
    _assert_parity 'https://attacker.example.com/v1'
}

@test "E13 parity-reject: ipv4 loopback 127.0.0.1" {
    _assert_parity 'https://127.0.0.1/v1'
}

@test "E14 parity-reject: ipv4 AWS IMDS 169.254.169.254" {
    _assert_parity 'https://169.254.169.254/latest/meta-data/'
}

@test "E15 parity-reject: ipv4 RFC 1918 10.0.0.1" {
    _assert_parity 'https://10.0.0.1/v1'
}

@test "E16 parity-reject: ipv4 decimal obfuscation 2130706433" {
    _assert_parity 'https://2130706433/v1'
}

@test "E17 parity-reject: ipv4 hex obfuscation 0x7f000001" {
    _assert_parity 'https://0x7f000001/v1'
}

@test "E18 parity-reject: userinfo user:pass@" {
    _assert_parity 'https://user:pass@api.openai.com/v1'
}

@test "E19 parity-reject: userinfo confusable api.openai.com@evil.com" {
    _assert_parity 'https://api.openai.com@evil.com/v1'
}

@test "E20 parity-reject: ipv6 public not allowed" {
    _assert_parity 'https://[2001:4860:4860::8888]/v1'
}

# ---------------------------------------------------------------------------
# E21-E28 — Sprint-1E.c.1 review-remediation parity fixtures.
# These cover the cross-runtime divergences caught by the dual-review:
# percent-encoded hostnames, Unicode dot equivalents, soft-hyphen, backslash
# userinfo, obfuscated IPv4 octets, IPv6 zone-id, IPv4-compat IPv6, leading-
# zero octets. Both runtimes MUST land on the same rejection code.
# ---------------------------------------------------------------------------

@test "E21 parity-reject: percent-encoded hostname dots %2E" {
    _assert_parity 'https://api%2Eopenai%2Ecom/v1'
}

@test "E22 parity-reject: full-width Unicode dot U+FF0E" {
    _assert_parity $'https://api\xef\xbc\x8eopenai\xef\xbc\x8ecom/v1'
}

@test "E23 parity-reject: ideographic full stop U+3002" {
    _assert_parity $'https://api\xe3\x80\x82openai\xe3\x80\x82com/v1'
}

@test "E24 parity-reject: soft hyphen U+00AD in hostname" {
    _assert_parity $'https://api.openai\xc2\xadcom/v1'
}

@test "E25 parity-reject: backslash userinfo confusion" {
    _assert_parity 'https://attacker.com\@api.openai.com/v1'
}

@test "E26 parity-reject: obfuscated IPv4 octet 010.0.0.1 (octal)" {
    _assert_parity 'https://010.0.0.1/v1'
}

@test "E27 parity-reject: IPv6 zone-id loopback [fe80::1%25eth0]" {
    _assert_parity 'https://[fe80::1%25eth0]/v1'
}

@test "E28 parity-reject: IPv4-compatible IPv6 [::1.2.3.4] (deprecated)" {
    _assert_parity 'https://[::1.2.3.4]/v1'
}
