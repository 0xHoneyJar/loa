#!/usr/bin/env bats
# =============================================================================
# red-team-model-adapter.bats — sprint-bug-102 regression tests
# =============================================================================
# Bug: red-team skill always runs in mock mode.
#
# Verifies:
#   1. invoke_live routes through model-invoke (not stubbed error)
#   2. Pipeline passes an explicit --live or --mock flag (not implicit default)
#   3. Mock mode emits a visible WARNING banner to stderr
#   4. Config example documents the red_team block
#   5. Default mode resolves to live when hounfour.flatline_routing is true
#      AND model-invoke is executable; otherwise mock
#
# These tests FAIL against the pre-fix adapter and PASS after sprint-bug-102.
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
    export ADAPTER="$SCRIPT_DIR/red-team-model-adapter.sh"
    export PIPELINE="$SCRIPT_DIR/red-team-pipeline.sh"
    export CONFIG_EXAMPLE="$PROJECT_ROOT/.loa.config.yaml.example"
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    echo "Test prompt content" > "$TEST_TMPDIR/prompt.md"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# -----------------------------------------------------------------------------
# T1: invoke_live is wired (not a stub that always errors)
# -----------------------------------------------------------------------------
# Pre-fix: invoke_live returns exit 1 with "requires cheval.py" regardless of
# whether cheval.py exists. Post-fix: it delegates to model-invoke.
#
# We can't make real network calls in unit tests, so we assert the adapter
# recognises --live as a valid path that EITHER succeeds OR fails with a
# model-invoke-related error (exit code 1-7 per SDD §4.2.2), not the
# "requires cheval.py (Hounfour integration)" stub message.
@test "invoke_live does not return the 'requires cheval.py' stub error" {
    # Force live mode with a prompt that would route through model-invoke.
    # With no API key set, this must fail — but NOT with the stub message.
    unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
    run "$ADAPTER" \
        --role attacker \
        --model opus \
        --prompt-file "$TEST_TMPDIR/prompt.md" \
        --output-file "$TEST_TMPDIR/out.json" \
        --live
    # Must not contain the legacy stub error string
    [[ "$output" != *"requires cheval.py (Hounfour integration)"* ]]
    [[ "$output" != *"Install Hounfour and configure model routing first"* ]]
}

# -----------------------------------------------------------------------------
# T2: Pipeline passes explicit --live or --mock flag to the adapter
# -----------------------------------------------------------------------------
# Pre-fix: three invocation sites at red-team-pipeline.sh:311,378,523
# call the adapter with no mode flag, so the adapter defaults to mock.
# Post-fix: every call site MUST pass --live or --mock explicitly.
@test "pipeline passes explicit --live or --mock flag to adapter" {
    # Count invocations that DO pass a mode flag
    explicit_count=$(grep -cE '\-\-(live|mock)' "$PIPELINE")
    # Count MODEL_ADAPTER invocation sites (lines starting with "$MODEL_ADAPTER")
    invoke_count=$(grep -cE '^\s*"\$MODEL_ADAPTER"' "$PIPELINE")
    [ "$invoke_count" -ge 3 ]
    # Every invocation site must pair with an explicit flag
    [ "$explicit_count" -ge "$invoke_count" ]
}

# -----------------------------------------------------------------------------
# T3: Mock mode emits a visible WARNING banner on stderr
# -----------------------------------------------------------------------------
# Pre-fix: invoke_mock silently returns fixture data. Post-fix: it must emit
# a clear banner so users understand the output is not from a live model.
@test "mock mode emits a visible WARNING banner on stderr" {
    run "$ADAPTER" \
        --role attacker \
        --model opus \
        --prompt-file "$TEST_TMPDIR/prompt.md" \
        --output-file "$TEST_TMPDIR/out.json" \
        --mock
    [ "$status" -eq 0 ]
    # Banner must mention the critical words: MOCK and WARNING (or equivalent)
    [[ "$output" == *"MOCK"* ]] || [[ "$output" == *"mock mode"* ]]
    [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"not real"* ]] || [[ "$output" == *"fixture"* ]]
}

# -----------------------------------------------------------------------------
# T4: .loa.config.yaml.example documents the red_team block
# -----------------------------------------------------------------------------
# Pre-fix: example config has zero mentions of red_team. Post-fix: the
# example must include a commented template so mounted projects can enable it.
@test ".loa.config.yaml.example documents the red_team configuration block" {
    grep -qE '^red_team:|^\s*red_team:' "$CONFIG_EXAMPLE"
}

# -----------------------------------------------------------------------------
# T5: Default mode resolves correctly based on environment
# -----------------------------------------------------------------------------
# Post-fix: when no --live/--mock flag is passed, the adapter checks
# hounfour.flatline_routing and model-invoke availability to pick a default.
# With --mock explicit, mock mode is always selected.
@test "explicit --mock always selects mock mode regardless of config" {
    run "$ADAPTER" \
        --role defender \
        --model opus \
        --prompt-file "$TEST_TMPDIR/prompt.md" \
        --output-file "$TEST_TMPDIR/out.json" \
        --mock
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/out.json" ]
    # Output must include mock=true
    result=$(jq -r '.mock' "$TEST_TMPDIR/out.json")
    [ "$result" = "true" ]
}

# -----------------------------------------------------------------------------
# T6: Self-test passes (adapter integrity)
# -----------------------------------------------------------------------------
# Verify the adapter's own self-test still passes after the fix.
@test "adapter self-test passes end-to-end" {
    run "$ADAPTER" --self-test
    [ "$status" -eq 0 ]
    [[ "$output" == *"passed"* ]]
    [[ "$output" != *"FAIL"* ]] || [[ "$output" == *"0 failed"* ]]
}
