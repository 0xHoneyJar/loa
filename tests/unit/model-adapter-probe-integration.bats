#!/usr/bin/env bats
# =============================================================================
# Sprint-3B integration tests: model-adapter.sh probe-cache consult (Task 3B.7)
# Verifies SDD §5.1 row 4-5 + §6.2 contract:
#   - AVAILABLE / no entry / cold-start → proceed
#   - UNAVAILABLE → fail-fast with actionable stderr (exit 4)
#   - UNKNOWN + degraded_ok=true → proceed
#   - UNKNOWN + degraded_ok=false → fail-fast (exit 4)
#   - LOA_PROBE_BYPASS=1 + reason → skip cache check
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ADAPTER="$PROJECT_ROOT/.claude/scripts/model-adapter.sh"

    TEST_DIR="$(mktemp -d)"
    export LOA_CACHE_DIR="$TEST_DIR"
    CACHE="$TEST_DIR/model-health-cache.json"

    # Source helpers without invoking main.
    eval "$(sed 's|^main "\$@"$|: # main_disabled|' "$ADAPTER")"
    PROBE_CACHE_PATH="$CACHE"

    # Hermetic config in tmp dir.
    HERMETIC_CONFIG="$TEST_DIR/loa.config.yaml"
    cat > "$HERMETIC_CONFIG" <<'EOF'
model_health_probe:
  enabled: true
  degraded_ok: true
EOF
    export LOA_CONFIG="$HERMETIC_CONFIG"
}

teardown() {
    [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && {
        find "$TEST_DIR" -mindepth 1 -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    }
    unset LOA_PROBE_BYPASS LOA_PROBE_BYPASS_REASON LOA_CONFIG
}

# -----------------------------------------------------------------------------
# Cold start / no cache file
# -----------------------------------------------------------------------------
@test "cache-check: no cache file -> rc=0 (cold-start fail-open)" {
    [ ! -f "$CACHE" ]
    run _probe_cache_check "openai:gpt-5.3-codex"
    [ "$status" -eq 0 ]
}

@test "cache-check: missing model in cache -> rc=0 (no entry fail-open)" {
    echo '{"schema_version":"1.0","entries":{}}' > "$CACHE"
    run _probe_cache_check "openai:never-probed-model"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# AVAILABLE
# -----------------------------------------------------------------------------
@test "cache-check: AVAILABLE entry -> rc=0" {
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{"openai:gpt-5.3-codex":{"state":"AVAILABLE","reason":"listed in /v1/models","probed_at":"2026-04-25T00:00:00Z"}}}
EOF
    run _probe_cache_check "openai:gpt-5.3-codex"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# UNAVAILABLE
# -----------------------------------------------------------------------------
@test "cache-check: UNAVAILABLE entry -> rc=1 with actionable stderr" {
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{"openai:ghost-model":{"state":"UNAVAILABLE","reason":"not in /v1/models","probed_at":"2026-04-24T14:30:00Z"}}}
EOF
    run _probe_cache_check "openai:ghost-model"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNAVAILABLE"* ]]
    [[ "$output" == *"--invalidate"* ]]
    [[ "$output" == *"LOA_PROBE_BYPASS"* ]]
}

# -----------------------------------------------------------------------------
# UNKNOWN + degraded_ok behavior
# -----------------------------------------------------------------------------
@test "cache-check: UNKNOWN + degraded_ok=true (default) -> rc=0" {
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{"anthropic:claude-opus-4-7":{"state":"UNKNOWN","reason":"429 rate-limited","probed_at":"2026-04-24T14:30:00Z"}}}
EOF
    run _probe_cache_check "anthropic:claude-opus-4-7"
    [ "$status" -eq 0 ]
}

@test "cache-check: UNKNOWN + degraded_ok=false -> rc=1 (fail-closed)" {
    cat > "$HERMETIC_CONFIG" <<'EOF'
model_health_probe:
  degraded_ok: false
EOF
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{"anthropic:claude-opus-4-7":{"state":"UNKNOWN","reason":"429 rate-limited","probed_at":"2026-04-24T14:30:00Z"}}}
EOF
    run _probe_cache_check "anthropic:claude-opus-4-7"
    [ "$status" -eq 1 ]
    [[ "$output" == *"UNKNOWN"* ]]
    [[ "$output" == *"degraded_ok=false"* ]]
}

# -----------------------------------------------------------------------------
# Bypass
# -----------------------------------------------------------------------------
@test "cache-check: LOA_PROBE_BYPASS=1 + reason -> rc=0 (cache skipped)" {
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{"openai:ghost-model":{"state":"UNAVAILABLE","reason":"x","probed_at":"2026-04-24T14:30:00Z"}}}
EOF
    LOA_PROBE_BYPASS=1
    LOA_PROBE_BYPASS_REASON="ci flake; debugging"
    run _probe_cache_check "openai:ghost-model"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BYPASS"* ]]
}

@test "cache-check: LOA_PROBE_BYPASS=1 without reason -> bypass NOT honored" {
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{"openai:ghost-model":{"state":"UNAVAILABLE","reason":"x","probed_at":"2026-04-24T14:30:00Z"}}}
EOF
    LOA_PROBE_BYPASS=1
    unset LOA_PROBE_BYPASS_REASON
    run _probe_cache_check "openai:ghost-model"
    [ "$status" -eq 1 ]   # bypass refused; cache check ran and failed
}

# -----------------------------------------------------------------------------
# Malformed cache (defense-in-depth)
# -----------------------------------------------------------------------------
@test "cache-check: corrupt JSON cache -> rc=0 (fail-open)" {
    printf 'not json {{{\n' > "$CACHE"
    run _probe_cache_check "openai:gpt-5.3-codex"
    [ "$status" -eq 0 ]
}

@test "cache-check: provider_model_id without colon -> rc=0 (no-op)" {
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{}}
EOF
    run _probe_cache_check "just-a-model-name"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Background re-probe spawn (Pattern 3 — PID sentinel dedup)
# -----------------------------------------------------------------------------
@test "bg-probe: stale entry triggers _adapter_spawn_bg_probe" {
    # Stale entry — probed 30 hours ago.
    local epoch=$(( $(date +%s) - 30*3600 ))
    local probed_at
    probed_at="$(date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || date -ju -f %s "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{"openai:gpt-5.3-codex":{"state":"AVAILABLE","reason":"listed","probed_at":"$probed_at"}}}
EOF

    # Stub the probe script with a cheap shim so spawn doesn't run real probes.
    local stub="$TEST_DIR/probe-stub.sh"
    cat > "$stub" <<'EOF'
#!/usr/bin/env bash
echo "$$" > "$LOA_CACHE_DIR/probe-spawned.flag"
EOF
    chmod +x "$stub"
    PROBE_SCRIPT="$stub"

    run _probe_cache_check "openai:gpt-5.3-codex"
    [ "$status" -eq 0 ]
    # Allow the background process a moment to write the flag.
    sleep 0.2
    [ -f "$TEST_DIR/probe-spawned.flag" ]
}

@test "bg-probe: existing PID sentinel for live process -> NO spawn (dedup)" {
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{}}
EOF
    # Plant a PID sentinel pointing at this test's own PID (definitely alive).
    echo "$$" > "$TEST_DIR/model-health-probe.openai.pid"

    local stub="$TEST_DIR/probe-stub.sh"
    cat > "$stub" <<'EOF'
#!/usr/bin/env bash
touch "$LOA_CACHE_DIR/probe-SHOULD-NOT-FIRE.flag"
EOF
    chmod +x "$stub"
    PROBE_SCRIPT="$stub"

    _adapter_spawn_bg_probe openai
    sleep 0.2
    [ ! -f "$TEST_DIR/probe-SHOULD-NOT-FIRE.flag" ]
}

# -----------------------------------------------------------------------------
# Iter-2 B-2 regression: TOCTOU race in adapter's _adapter_spawn_bg_probe
# -----------------------------------------------------------------------------
@test "bg-probe: 5 parallel adapter spawns yield ≤ 1 probe (B-2 race fix)" {
    cat > "$CACHE" <<EOF
{"schema_version":"1.0","entries":{}}
EOF
    rm -f "$TEST_DIR/model-health-probe.openai.pid"

    local stub="$TEST_DIR/probe-stub.sh"
    cat > "$stub" <<'EOF'
#!/usr/bin/env bash
echo "fired-$$" >> "$LOA_CACHE_DIR/spawn-log"
sleep 0.5
EOF
    chmod +x "$stub"
    PROBE_SCRIPT="$stub"

    # Burst 5 parallel adapter spawn calls.
    local i
    for i in 1 2 3 4 5; do
        ( _adapter_spawn_bg_probe openai ) &
    done
    wait
    sleep 0.7   # let the winning stub run + exit

    local fires
    fires="$(wc -l < "$TEST_DIR/spawn-log" 2>/dev/null || echo 0)"
    [ "$fires" -le 1 ]
}
