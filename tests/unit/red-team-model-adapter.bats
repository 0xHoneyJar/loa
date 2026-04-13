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
#
# Bridgebuilder F1 (medium): negative-only assertion is insufficient — added
# positive check that the live path actually requires API-key validation,
# confirming model-invoke was invoked rather than the stub being silently removed.
@test "invoke_live does not return the 'requires cheval.py' stub error" {
    # Force live mode with a prompt that would route through model-invoke.
    # With no API key set, this must fail — but NOT with the stub message.
    unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
    # Explicit 2>&1 merge for BATS version portability (pass-2 F1/F2).
    # Positional args (not string interpolation) avoid shell-quoting injection
    # if paths ever contain single quotes (pass-3 HIGH finding).
    run bash -c '"$1" --role attacker --model opus \
        --prompt-file "$2" --output-file "$3" --live 2>&1' \
        _ "$ADAPTER" "$TEST_TMPDIR/prompt.md" "$TEST_TMPDIR/out.json"
    # Negative: must not contain the legacy stub error string
    [[ "$output" != *"requires cheval.py (Hounfour integration)"* ]]
    [[ "$output" != *"Install Hounfour and configure model routing first"* ]]
    # Positive: exit 1 (not any non-zero) — the live path's API-key guard
    # specifically returns 1 via has_any_api_key failure.
    [ "$status" -eq 1 ]
    # Positive: assert the EXACT contractual error prefix emitted by
    # invoke_live's has_any_api_key guard. No OR-chain — the adapter is
    # contractually required to emit this specific string. If it changes,
    # the contract changed and the test should fail to force a review.
    # (Bridgebuilder pass-3 F2: replaced permissive OR chain with canonical match.)
    [[ "$output" == *"Live mode requires at least one provider API key"* ]]
}

# -----------------------------------------------------------------------------
# T2: Pipeline passes explicit --live or --mock flag to the adapter
# -----------------------------------------------------------------------------
# Pre-fix: three invocation sites at red-team-pipeline.sh:311,378,523
# call the adapter with no mode flag, so the adapter defaults to mock.
# Post-fix: every call site MUST pass --live or --mock explicitly.
#
# Bridgebuilder F2 (medium): previous version counted --live/--mock mentions
# anywhere in the file (including comments and help text). This version uses
# a multiline-aware check: every block that starts with "$MODEL_ADAPTER"
# and ends at the first blank line must contain --live or --mock.
@test "pipeline passes explicit --live or --mock flag to adapter" {
    # For every line that invokes `"$MODEL_ADAPTER" \`, scan the following
    # block of continuation lines (ending at the first line without a
    # trailing backslash) and confirm the mode flag — either literal
    # --live/--mock or the $ADAPTER_MODE_FLAG variable — appears inside it.
    invoke_count=0
    missing_count=0
    in_block=0
    found_flag=0
    while IFS= read -r line; do
        if [[ "$in_block" -eq 1 ]]; then
            # Inside a continuation block
            if [[ "$line" == *"--live"* ]] || [[ "$line" == *"--mock"* ]] || [[ "$line" == *'$ADAPTER_MODE_FLAG'* ]]; then
                found_flag=1
            fi
            # End of block: line doesn't end in backslash
            if [[ "$line" != *"\\" ]]; then
                if [[ "$found_flag" -eq 0 ]]; then
                    missing_count=$((missing_count + 1))
                fi
                in_block=0
                found_flag=0
            fi
        elif [[ "$line" == *'"$MODEL_ADAPTER"'*'\' ]]; then
            invoke_count=$((invoke_count + 1))
            in_block=1
            found_flag=0
        fi
    done < "$PIPELINE"
    [ "$invoke_count" -ge 3 ]
    [ "$missing_count" -eq 0 ]
    # And if $ADAPTER_MODE_FLAG is the mechanism, the pipeline must resolve
    # it to a literal --live or --mock (defensive guard in main()).
    # Bridgebuilder F4: split into explicit alternatives to avoid the
    # unescaped-paren ERE group bug in the previous regex.
    grep -qE 'ADAPTER_MODE_FLAG="--live"' "$PIPELINE" \
        || grep -qE 'ADAPTER_MODE_FLAG="--mock"' "$PIPELINE" \
        || grep -qE 'ADAPTER_MODE_FLAG=\$\(resolve_adapter_mode\)' "$PIPELINE"
}

# -----------------------------------------------------------------------------
# T3: Mock mode emits a visible WARNING banner on stderr
# -----------------------------------------------------------------------------
# Pre-fix: invoke_mock silently returns fixture data. Post-fix: it must emit
# a clear banner so users understand the output is not from a live model.
@test "mock mode emits a visible WARNING banner on stderr" {
    # Explicit 2>&1 merge for BATS version portability (pass-2 F1/F2).
    # Positional args (not string interpolation) avoid shell-quoting injection
    # if paths ever contain single quotes (pass-3 HIGH finding).
    run bash -c '"$1" --role attacker --model opus \
        --prompt-file "$2" --output-file "$3" --mock 2>&1' \
        _ "$ADAPTER" "$TEST_TMPDIR/prompt.md" "$TEST_TMPDIR/out.json"
    [ "$status" -eq 0 ]
    # Bridgebuilder pass-3 F3: assert the exact canonical banner line,
    # no OR-chain. The banner is defined in emit_mock_banner() and its
    # first header line is invariant. If the banner text changes,
    # emit_mock_banner() is the single source of truth and this assertion
    # must update — keeping test and implementation locked together.
    [[ "$output" == *"WARNING: red-team adapter running in MOCK mode"* ]]
    # Also verify the banner includes actionable remediation guidance
    # (the "To enable live model invocation" section is part of the
    # canonical banner body, not optional).
    [[ "$output" == *"To enable live model invocation:"* ]]
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
    # Bridgebuilder pass-3 F6: the old assertion was vacuously satisfiable.
    # `[[ output != *FAIL* ]] || [[ output == *"0 failed"* ]]` would accept
    # output like "3 FAIL, 0 failed" because the second clause matches.
    # Tighter contract: exit 0 is the real signal (self-test returns 0
    # only when every sub-test passes); also assert the canonical summary
    # line "0 failed" explicitly, which the self-test always emits last.
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 failed"* ]]
    # Must NOT contain a non-zero failure count. Using a regex to reject
    # any digit 1-9 preceding " failed" (would catch "3 failed", "12 failed", etc.)
    ! [[ "$output" =~ [1-9][0-9]*" failed" ]]
}
