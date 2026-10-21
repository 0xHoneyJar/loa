#!/usr/bin/env bats
# =============================================================================
# cycle-129 FR-7 (SDD D-7.5, D-7.2; sprint-257 Task 3.1) —
# model-health-probe.sh --provider <name> for a provider declared in the merged
# hounfour config: looked up through the cheval loader, probed at
# <endpoint>/models with no credential when keyless, through the endpoint
# validator with the provider's own allow_insecure_endpoint host. The enum
# error lists the configured names. One live case uses a stub server bound to
# 127.0.0.1 that the test starts and stops (with a dead proxy in the env).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    PROBE="$REPO_ROOT/.claude/scripts/model-health-probe.sh"
    TEST_DIR="$(mktemp -d)"
    PROJ="$TEST_DIR/proj"
    mkdir -p "$PROJ/.claude/defaults"
    cp "$REPO_ROOT/.claude/defaults/model-config.yaml" "$PROJ/.claude/defaults/"
    export PROJECT_ROOT="$PROJ"
    export LOA_CACHE_DIR="$TEST_DIR/run"
    export LOA_TRAJECTORY_DIR="$TEST_DIR/trajectory"
    export LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl"
    printf '%s\n' '{"object":"list","data":[{"id":"qwen3-coder-30b"},{"id":"other"}]}' > "$TEST_DIR/models.json"
    STUB_PID=""
}

teardown() {
    if [[ -n "$STUB_PID" ]]; then
        kill "$STUB_PID" 2>/dev/null || true
        wait "$STUB_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_DIR"
}

# _write_config <endpoint> [optin-yaml-value, verbatim] [auth-line]
_write_config() {
    local endpoint="$1" optin="${2:-}" auth="${3:-      keyless: true}"
    {
        printf '%s\n' 'hounfour:' '  providers:' '    local:' '      type: openai_compat'
        printf '      endpoint: "%s"\n' "$endpoint"
        printf '%s\n' "$auth"
        if [[ -n "$optin" ]]; then
            printf '      allow_insecure_endpoint: %s\n' "$optin"
        fi
        printf '%s\n' '      models:' '        qwen3-coder-30b:' '          endpoint_family: chat' \
            '          auth_type: http_api' '          dispatch_group: local' '          capabilities: [chat]' \
            '          context_window: 32768'
    } > "$PROJ/.loa.config.yaml"
}

@test "configured provider: accepted by --provider and probed at <endpoint>/models (mock mode)" {
    _write_config "http://127.0.0.1:8000/v1" '"127.0.0.1"'
    LOA_PROBE_MOCK_MODE=1 LOA_PROBE_MOCK_CONFIGURED="$TEST_DIR/models.json" \
        run bash "$PROBE" --provider local --output json
    [ "$status" -eq 0 ]
    [[ "$output" == *"probing configured provider local at http://127.0.0.1:8000/v1/models (allow_insecure_endpoint=127.0.0.1)"* ]]
    [[ "$output" == *'"local:qwen3-coder-30b"'* ]]
    [[ "$output" == *'"state": "AVAILABLE"'* ]]
}

@test "configured provider: the enum error lists the configured names" {
    _write_config "http://127.0.0.1:8000/v1" '"127.0.0.1"'
    run bash "$PROBE" --provider nope
    [ "$status" -eq 64 ]
    [[ "$output" == *"invalid provider: nope (allowed: openai|google|anthropic|bedrock|"*"local"* ]]
}

@test "configured provider: a non-keyless provider whose {env:VAR} is unset is UNKNOWN (auth), never sent" {
    _write_config "http://127.0.0.1:8000/v1" '"127.0.0.1"' '      auth: "{env:LOA_TEST_LOCAL_KEY}"'
    unset LOA_TEST_LOCAL_KEY
    LOA_PROBE_MOCK_MODE=1 LOA_PROBE_MOCK_CONFIGURED="$TEST_DIR/models.json" \
        run bash "$PROBE" --provider local --output json
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOA_TEST_LOCAL_KEY not set"* ]]
    [[ "$output" != *"probing configured provider"* ]]
}

@test "configured provider: an http endpoint without the opt-in fails at load with the named reason" {
    _write_config "http://127.0.0.1:8000/v1" ""
    run bash "$PROBE" --provider local
    [ "$status" -eq 64 ]
    [[ "$output" == *"ENDPOINT-INSECURE-SCHEME"* ]]
}

@test "configured provider: a boolean opt-in fails at load with the named reason" {
    _write_config "http://127.0.0.1:8000/v1" "true"
    run bash "$PROBE" --provider local
    [ "$status" -eq 64 ]
    [[ "$output" == *"ENDPOINT-OPTIN-BOOLEAN"* ]]
}

@test "configured provider: live probe of a 127.0.0.1 stub honours the opt-in and ignores proxy env" {
    command -v curl >/dev/null || skip "curl not installed"
    local port
    port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
    mkdir -p "$TEST_DIR/srv/v1"
    cp "$TEST_DIR/models.json" "$TEST_DIR/srv/v1/models"
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$TEST_DIR/srv" >/dev/null 2>&1 &
    STUB_PID=$!
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        curl -s --noproxy '*' -o /dev/null "http://127.0.0.1:$port/v1/models" && break
        sleep 0.2
    done
    _write_config "http://127.0.0.1:$port/v1" '"127.0.0.1"'
    HTTP_PROXY="http://127.0.0.1:1" http_proxy="http://127.0.0.1:1" ALL_PROXY="http://127.0.0.1:1" \
        run bash "$PROBE" --provider local --output json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"state": "AVAILABLE"'* ]]
    [[ "$output" == *"listed in local /models"* ]]
}
