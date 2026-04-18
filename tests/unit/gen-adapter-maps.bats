#!/usr/bin/env bats
# =============================================================================
# gen-adapter-maps.bats — Tests for gen-adapter-maps.sh (vision-011, #548)
# =============================================================================
# Sprint-bug-108. Validates the YAML → bash generator produces byte-correct
# output and that the generated maps match the values expected by
# model-adapter.sh.legacy.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export GENERATOR="$PROJECT_ROOT/.claude/scripts/gen-adapter-maps.sh"
    export GENERATED="$PROJECT_ROOT/.claude/scripts/generated-model-maps.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR"
}

# =========================================================================
# GAM-T1: generator produces a valid bash file
# =========================================================================

@test "generator emits valid bash to stdout (--dry-run)" {
    run "$GENERATOR" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"declare -A MODEL_PROVIDERS"* ]]
    [[ "$output" == *"declare -A MODEL_IDS"* ]]
    [[ "$output" == *"declare -A COST_INPUT"* ]]
    [[ "$output" == *"declare -A COST_OUTPUT"* ]]
}

@test "generated output is syntactically valid bash" {
    run bash -n "$GENERATED"
    [ "$status" -eq 0 ]
}

# =========================================================================
# GAM-T2: generated maps resolve known aliases correctly
# =========================================================================

@test "generated MODEL_PROVIDERS resolves opus alias to anthropic" {
    run bash -c "source '$GENERATED'; echo \"\${MODEL_PROVIDERS[opus]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "anthropic" ]
}

@test "generated MODEL_IDS resolves opus alias to claude-opus-4-7" {
    run bash -c "source '$GENERATED'; echo \"\${MODEL_IDS[opus]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "claude-opus-4-7" ]
}

@test "generated MODEL_IDS resolves claude-opus-4-6 backward-compat to 4-7" {
    run bash -c "source '$GENERATED'; echo \"\${MODEL_IDS[claude-opus-4-6]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "claude-opus-4-7" ]
}

@test "generated MODEL_PROVIDERS includes all canonical models" {
    # Gemini 3 models pruned per #574 (phantom on Google v1beta).
    run bash -c "source '$GENERATED'; for m in gpt-5.2 gpt-5.3-codex claude-opus-4-7 claude-opus-4-6 claude-sonnet-4-6 gemini-2.5-pro gemini-2.5-flash; do echo \"\$m=\${MODEL_PROVIDERS[\$m]:-MISSING}\"; done"
    [ "$status" -eq 0 ]
    [[ "$output" != *"MISSING"* ]]
}

# =========================================================================
# GAM-T3: pricing conversion (micro-USD per MTok → USD per 1K)
# =========================================================================

@test "generated COST_INPUT for opus matches hand-maintained 0.005" {
    run bash -c "source '$GENERATED'; echo \"\${COST_INPUT[opus]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "0.005" ]
}

@test "generated COST_OUTPUT for opus matches hand-maintained 0.025" {
    run bash -c "source '$GENERATED'; echo \"\${COST_OUTPUT[opus]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "0.025" ]
}

@test "generated COST_INPUT for gpt-5.3-codex is 0.00175" {
    run bash -c "source '$GENERATED'; echo \"\${COST_INPUT[gpt-5.3-codex]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "0.00175" ]
}

@test "generated COST_INPUT for gemini-2.5-pro is 0.00125" {
    run bash -c "source '$GENERATED'; echo \"\${COST_INPUT[gemini-2.5-pro]}\""
    [ "$status" -eq 0 ]
    [ "$output" = "0.00125" ]
}

# =========================================================================
# GAM-T4: --check mode detects drift
# =========================================================================

@test "--check returns 0 when output matches YAML" {
    run "$GENERATOR" --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# =========================================================================
# GAM-T5: usage / error cases
# =========================================================================

@test "--output without value exits 2" {
    run "$GENERATOR" --output
    [ "$status" -eq 2 ]
}

@test "missing yq dependency is reported" {
    # Create an empty bin dir so yq is NOT findable but standard shell
    # builtins still work (setting PATH=/nonexistent breaks bash itself).
    local shimdir="$TEST_DIR/no-yq-bin"
    mkdir -p "$shimdir"
    # Symlink core tools without yq
    for tool in sh bash cat cut tr sed awk grep head mkdir mktemp rm mv diff jq; do
        local found
        found=$(command -v "$tool" 2>/dev/null || true)
        [[ -n "$found" ]] && ln -sf "$found" "$shimdir/$tool" 2>/dev/null || true
    done
    run env PATH="$shimdir" "$GENERATOR" --dry-run
    [ "$status" -ne 0 ]
}

@test "nonexistent config file exits 1" {
    run "$GENERATOR" --config /nonexistent/model-config.yaml --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"config file not found"* ]]
}

# =========================================================================
# GAM-T6: output is idempotent across invocations
# =========================================================================

@test "generator is idempotent (two runs produce identical output)" {
    local first="$TEST_DIR/first.sh"
    local second="$TEST_DIR/second.sh"
    "$GENERATOR" --output "$first" 2>&1 >/dev/null
    sleep 1  # ensure any timestamp field would differ if present in output
    "$GENERATOR" --output "$second" 2>&1 >/dev/null
    # Strip the timestamp line (varies between runs) before comparing
    grep -v "^# Generated by" "$first" | grep -v "Generated at:" > "$TEST_DIR/first.clean"
    grep -v "^# Generated by" "$second" | grep -v "Generated at:" > "$TEST_DIR/second.clean"
    diff "$TEST_DIR/first.clean" "$TEST_DIR/second.clean"
}

# =========================================================================
# GAM-T7: parity with hand-maintained legacy adapter values
# =========================================================================
# This test is the whole point: the generated output's values for each
# entry must match what the hand-maintained maps in model-adapter.sh.legacy
# currently specify. If this fails, the generator introduces runtime drift.

@test "parity: generated MODEL_IDS[claude-opus-4-5] matches hand-maintained (claude-opus-4-7)" {
    run bash -c "source '$GENERATED'; echo \"\${MODEL_IDS[claude-opus-4-5]}\""
    [ "$output" = "claude-opus-4-7" ]
}

@test "parity: generated MODEL_PROVIDERS[gpt-5.2-codex] matches hand-maintained (openai)" {
    run bash -c "source '$GENERATED'; echo \"\${MODEL_PROVIDERS[gpt-5.2-codex]}\""
    [ "$output" = "openai" ]
}

@test "parity: generated COST for claude-opus-4-6 matches hand-maintained (0.005/0.025)" {
    run bash -c "source '$GENERATED'; echo \"\${COST_INPUT[claude-opus-4-6]}/\${COST_OUTPUT[claude-opus-4-6]}\""
    [ "$output" = "0.005/0.025" ]
}
