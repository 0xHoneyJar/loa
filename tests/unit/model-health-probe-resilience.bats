#!/usr/bin/env bats
# =============================================================================
# Sprint-3B resilience-layer tests for .claude/scripts/model-health-probe.sh
# Covers: feature flag, degraded_ok, LOA_PROBE_BYPASS w/ TTL + reason,
#         circuit breaker (consecutive failure threshold + reset),
#         staleness cutoff (max_stale_hours, alert_on_stale_hours),
#         retry_with_backoff jitter helper.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    PROBE="$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"

    TEST_DIR="$(mktemp -d)"
    export LOA_CACHE_DIR="$TEST_DIR"
    export LOA_TRAJECTORY_DIR="$TEST_DIR/trajectory"
    export LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl"
    export OPENAI_API_KEY="test-openai"
    export GOOGLE_API_KEY="test-google"
    export ANTHROPIC_API_KEY="test-anthropic"
    export LOA_PROBE_MOCK_MODE=1

    # Hermetic config: write a tmp .loa.config.yaml and point the probe at it.
    HERMETIC_CONFIG="$TEST_DIR/loa.config.yaml"
    cat > "$HERMETIC_CONFIG" <<'EOF'
model_health_probe:
  enabled: true
  degraded_ok: true
  max_stale_hours: 72
  alert_on_stale_hours: 24
EOF
    export LOA_CONFIG="$HERMETIC_CONFIG"

    # Source the probe script. The probe's BASH_SOURCE main-guard at the
    # bottom prevents main() from running on source.
    # shellcheck disable=SC1090
    source "$PROBE"

    # Override script-internal constants so writes stay in TEST_DIR.
    TRAJECTORY_DIR="$TEST_DIR/trajectory"
    AUDIT_LOG="$TEST_DIR/audit.jsonl"
    CACHE_PATH_DEFAULT="$TEST_DIR/model-health-cache.json"
    LOA_CACHE_DIR="$TEST_DIR"
    LOA_CONFIG="$HERMETIC_CONFIG"
}

teardown() {
    [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && {
        find "$TEST_DIR" -mindepth 1 -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    }
    unset LOA_PROBE_BYPASS LOA_PROBE_BYPASS_REASON LOA_CONFIG
}

# -----------------------------------------------------------------------------
# Feature flag (Task 3B.1)
# -----------------------------------------------------------------------------
@test "feature-flag: enabled=true (default) -> _probe_enabled returns success" {
    run _probe_enabled
    [ "$status" -eq 0 ]
}

@test "feature-flag: enabled=false in config -> _probe_enabled returns failure" {
    cat > "$HERMETIC_CONFIG" <<'EOF'
model_health_probe:
  enabled: false
EOF
    run _probe_enabled
    [ "$status" -ne 0 ]
}

@test "feature-flag: probe exits 0 cleanly when disabled (subprocess)" {
    cat > "$HERMETIC_CONFIG" <<'EOF'
model_health_probe:
  enabled: false
EOF
    run env LOA_CACHE_DIR="$TEST_DIR" \
        LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl" \
        LOA_CONFIG="$HERMETIC_CONFIG" \
        "$PROBE" --provider openai --quiet --output json
    [ "$status" -eq 0 ]
    grep -q 'probe_disabled' "$TEST_DIR/audit.jsonl"
}

# -----------------------------------------------------------------------------
# degraded_ok behavior (Task 3B.1)
# -----------------------------------------------------------------------------
@test "degraded_ok: default true" {
    run _degraded_ok
    [ "$status" -eq 0 ]
}

@test "degraded_ok: false in config -> _degraded_ok returns failure" {
    cat > "$HERMETIC_CONFIG" <<'EOF'
model_health_probe:
  degraded_ok: false
EOF
    run _degraded_ok
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Bypass governance (Task 3B.bypass_governance)
# -----------------------------------------------------------------------------
@test "bypass: LOA_PROBE_BYPASS=1 without reason -> rc=2 (denied)" {
    LOA_PROBE_BYPASS=1
    unset LOA_PROBE_BYPASS_REASON
    run _check_bypass
    [ "$status" -eq 2 ]
    grep -q 'probe_bypass_denied' "$TEST_DIR/audit.jsonl"
}

@test "bypass: LOA_PROBE_BYPASS=1 with reason -> rc=0 (active) on first call" {
    LOA_PROBE_BYPASS=1
    LOA_PROBE_BYPASS_REASON="provider outage 2026-04-25 ticket #999"
    run _check_bypass
    [ "$status" -eq 0 ]
    grep -q 'probe_bypass_set' "$TEST_DIR/audit.jsonl"
    [ -f "$TEST_DIR/probe-bypass.stamp" ]
}

@test "bypass: LOA_PROBE_BYPASS not set -> rc=1 (no bypass)" {
    unset LOA_PROBE_BYPASS LOA_PROBE_BYPASS_REASON
    run _check_bypass
    [ "$status" -eq 1 ]
}

@test "bypass: TTL expiry (>24h old stamp) -> probe re-engages" {
    # Plant an expired sentinel (25 hours ago).
    mkdir -p "$TEST_DIR"
    local old=$(( $(date +%s) - 25*3600 ))
    printf '%s\n' "$old" > "$TEST_DIR/probe-bypass.stamp"
    LOA_PROBE_BYPASS=1
    LOA_PROBE_BYPASS_REASON="legacy bypass"
    run _check_bypass
    [ "$status" -eq 1 ]    # re-engaged — probe runs
    grep -q 'probe_bypass_expired' "$TEST_DIR/audit.jsonl"
    [ ! -f "$TEST_DIR/probe-bypass.stamp" ]
}

@test "bypass: within TTL window -> reuses existing stamp, rc=0" {
    # Plant a 1-hour-old stamp.
    mkdir -p "$TEST_DIR"
    local recent=$(( $(date +%s) - 3600 ))
    printf '%s\n' "$recent" > "$TEST_DIR/probe-bypass.stamp"
    LOA_PROBE_BYPASS=1
    LOA_PROBE_BYPASS_REASON="ongoing"
    run _check_bypass
    [ "$status" -eq 0 ]
    grep -q 'probe_bypass_active' "$TEST_DIR/audit.jsonl"
}

@test "bypass: subprocess exits 0 with bypass active and reason" {
    LOA_PROBE_BYPASS=1
    LOA_PROBE_BYPASS_REASON="ci probe-known-flaky"
    run env LOA_PROBE_BYPASS=1 \
        LOA_PROBE_BYPASS_REASON="ci probe-known-flaky" \
        LOA_CACHE_DIR="$TEST_DIR" \
        LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl" \
        LOA_CONFIG="$HERMETIC_CONFIG" \
        "$PROBE" --provider openai --quiet --output json
    [ "$status" -eq 0 ]
    grep -q 'probe_bypass_set\|probe_bypass_active' "$TEST_DIR/audit.jsonl"
}

@test "bypass: subprocess exits 64 when bypass=1 but reason missing" {
    run env LOA_PROBE_BYPASS=1 \
        LOA_CACHE_DIR="$TEST_DIR" \
        LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl" \
        LOA_CONFIG="$HERMETIC_CONFIG" \
        "$PROBE" --provider openai --quiet --output json
    [ "$status" -eq 64 ]
}

# -----------------------------------------------------------------------------
# Circuit breaker (Task 3B.1)
# -----------------------------------------------------------------------------
@test "circuit-breaker: closed state on empty cache -> _circuit_open_for false" {
    run _circuit_open_for openai
    [ "$status" -ne 0 ]
}

@test "circuit-breaker: 5 consecutive failures -> circuit OPEN" {
    # Seed an empty cache so _circuit_update has something to RMW.
    local cache="$TEST_DIR/model-health-cache.json"
    echo '{"schema_version":"1.0","entries":{},"provider_circuit_state":{}}' > "$cache"
    OPT_CACHE_PATH="$cache"
    LOA_CACHE_DIR="$TEST_DIR"

    local i
    for i in 1 2 3 4 5; do
        _circuit_update openai failure
    done

    # consecutive_failures should be >= threshold
    local cf
    cf="$(jq -r '.provider_circuit_state.openai.consecutive_failures' "$cache")"
    [ "$cf" -ge 5 ]
    # open_until set
    local ou
    ou="$(jq -r '.provider_circuit_state.openai.open_until' "$cache")"
    [ -n "$ou" ] && [ "$ou" != "null" ]
    # circuit reads as OPEN
    run _circuit_open_for openai
    [ "$status" -eq 0 ]
}

@test "circuit-breaker: success resets failure counter and closes circuit" {
    local cache="$TEST_DIR/model-health-cache.json"
    echo '{"schema_version":"1.0","entries":{},"provider_circuit_state":{"openai":{"consecutive_failures":3,"open_until":null}}}' > "$cache"
    OPT_CACHE_PATH="$cache"
    LOA_CACHE_DIR="$TEST_DIR"

    _circuit_update openai success

    local cf ou
    cf="$(jq -r '.provider_circuit_state.openai.consecutive_failures' "$cache")"
    ou="$(jq -r '.provider_circuit_state.openai.open_until' "$cache")"
    [ "$cf" -eq 0 ]
    [ "$ou" == "null" ]
}

@test "circuit-breaker: per-provider isolation (openai open does not affect google)" {
    local cache="$TEST_DIR/model-health-cache.json"
    echo '{"schema_version":"1.0","entries":{},"provider_circuit_state":{}}' > "$cache"
    OPT_CACHE_PATH="$cache"
    LOA_CACHE_DIR="$TEST_DIR"

    # Trip openai circuit
    local i; for i in 1 2 3 4 5; do _circuit_update openai failure; done

    run _circuit_open_for openai
    [ "$status" -eq 0 ]
    run _circuit_open_for google
    [ "$status" -ne 0 ]
    run _circuit_open_for anthropic
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Staleness cutoff (Task 3B.2)
# -----------------------------------------------------------------------------
@test "staleness: fresh entry (<1h) -> rc=0, no audit alert" {
    local now_iso; now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run _check_staleness "$now_iso" "openai:test-model"
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_DIR/audit.jsonl" ] || ! grep -q 'cache_stale' "$TEST_DIR/audit.jsonl"
}

@test "staleness: 25h-old entry -> rc=0, audit alert (alert_on_stale_hours=24)" {
    local then_epoch=$(( $(date +%s) - 25*3600 ))
    local then_iso
    then_iso="$(date -u -d "@$then_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || date -ju -f %s "$then_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    run _check_staleness "$then_iso" "openai:stale-model"
    [ "$status" -eq 0 ]
    grep -q 'cache_stale_alert' "$TEST_DIR/audit.jsonl"
}

@test "staleness: 73h-old entry + degraded_ok=true -> rc=0, cutoff audit" {
    local then_epoch=$(( $(date +%s) - 73*3600 ))
    local then_iso
    then_iso="$(date -u -d "@$then_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || date -ju -f %s "$then_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    run _check_staleness "$then_iso" "openai:past-cutoff"
    [ "$status" -eq 0 ]    # degraded_ok=true returns 0
    grep -q 'cache_stale_cutoff' "$TEST_DIR/audit.jsonl"
}

@test "staleness: 73h-old entry + degraded_ok=false -> rc=2 (fail-closed)" {
    cat > "$HERMETIC_CONFIG" <<'EOF'
model_health_probe:
  degraded_ok: false
  max_stale_hours: 72
  alert_on_stale_hours: 24
EOF
    LOA_CONFIG="$HERMETIC_CONFIG"
    local then_epoch=$(( $(date +%s) - 73*3600 ))
    local then_iso
    then_iso="$(date -u -d "@$then_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
                || date -ju -f %s "$then_epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    run _check_staleness "$then_iso" "openai:past-cutoff"
    [ "$status" -eq 2 ]
}

# -----------------------------------------------------------------------------
# Retry/backoff (Task 3B.2 — SDD §6.4)
# -----------------------------------------------------------------------------
@test "retry: succeeds on first attempt -> single call, rc=0" {
    counter=0
    _try_once() { counter=$((counter+1)); return 0; }
    run _retry_with_backoff 3 _try_once
    [ "$status" -eq 0 ]
}

@test "retry: succeeds on second attempt after one failure" {
    state_file="$TEST_DIR/retry-state"
    echo 0 > "$state_file"
    _flaky() {
        local n; n="$(cat "$state_file")"
        n=$((n+1))
        echo "$n" > "$state_file"
        [[ "$n" -ge 2 ]] && return 0 || return 1
    }
    run _retry_with_backoff 3 _flaky
    [ "$status" -eq 0 ]
    [ "$(cat "$state_file")" -eq 2 ]
}

@test "retry: exhausts attempts on persistent failure" {
    counter_file="$TEST_DIR/retry-counter"
    echo 0 > "$counter_file"
    _always_fail() {
        local n; n="$(cat "$counter_file")"
        echo $((n+1)) > "$counter_file"
        return 1
    }
    run _retry_with_backoff 3 _always_fail
    [ "$status" -eq 1 ]
    [ "$(cat "$counter_file")" -eq 3 ]
}

# -----------------------------------------------------------------------------
# Iter-2 B-3 regression: _emit_audit_log redacts before webhook fan-out
# -----------------------------------------------------------------------------
@test "audit-log: secret-shaped detail field is redacted in audit log (B-3 fix)" {
    # Plant a fake-but-secret-shaped string in the detail JSON.
    local fake_key='sk-FAKE_TEST_KEY_NOT_REAL_xxxxxxxxxxxxxx'
    local detail
    detail="$(jq -n --arg k "$fake_key" '{leaked_secret:$k}')"
    _emit_audit_log "test_action" "$detail"

    [ -f "$AUDIT_LOG" ]
    # Audit log must not contain the raw key.
    ! grep -F "$fake_key" "$AUDIT_LOG"
    # Audit log MUST contain the redacted form.
    grep -q 'sk-REDACTED' "$AUDIT_LOG"
}

@test "audit-log: PEM private-key block in detail is redacted (B-3 fix)" {
    local pem='-----BEGIN PRIVATE KEY-----MIIEpAIBAAKCAQEAabc-----END PRIVATE KEY-----'
    local detail
    detail="$(jq -n --arg p "$pem" '{leaked_pem:$p}')"
    _emit_audit_log "test_pem" "$detail"

    [ -f "$AUDIT_LOG" ]
    ! grep -F "MIIEpAIB" "$AUDIT_LOG"
    grep -q 'REDACTED-PEM' "$AUDIT_LOG"
}
