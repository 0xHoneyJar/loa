#!/usr/bin/env bats
# =============================================================================
# Cycle-112 D-7 (#948) — post-flight tokens_input / tokens_output attribution
# =============================================================================
# Pins the contract that cheval.cmd_invoke captures provider-reported token
# counts from `CompletionResult.usage` and threads them into the MODELINV
# envelope as `payload.tokens_input` + `payload.tokens_output`.
#
# Pre-D-7 reality: writer signature lacked these fields entirely; cost
# computation in `/loa status --economy` fell back to
# `pricing_snapshot.input_per_mtok × capability_evaluation.estimated_input_tokens`
# (pre-flight estimate, present in 50% of envelopes). D-7 closes that gap
# with the actual provider-reported usage so cost rolls up honestly.
#
# Test strategy: invoke cheval with --mock-fixture-dir against a fixture
# that returns a canned CompletionResult with known usage values, redirect
# MODELINV log to a temp path via LOA_MODELINV_LOG_PATH, and assert the
# resulting envelope's payload carries the expected token counts.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CHEVAL="$REPO_ROOT/.claude/adapters/cheval.py"
    TMP_DIR="$(mktemp -d)"
    export PROJECT_ROOT="$REPO_ROOT"
    export LOA_MODELINV_LOG_PATH="$TMP_DIR/model-invoke.jsonl"
    export LOA_ADVISOR_STRATEGY_DISABLE=1

    # Mock fixture with known token values. cheval's mock-fixture path
    # loads response.json and synthesizes a CompletionResult — usage
    # values flow through to _result.usage.{input,output}_tokens.
    FIXTURE_DIR="$TMP_DIR/fixture"
    mkdir -p "$FIXTURE_DIR"
    cat > "$FIXTURE_DIR/response.json" <<'EOF'
{
  "content": "## D-7 post-flight token capture test",
  "usage": {"input_tokens": 12345, "output_tokens": 678}
}
EOF
}

teardown() {
    rm -rf "$TMP_DIR"
}

_pick_agent() {
    if python3 "$CHEVAL" --print-effective-config 2>/dev/null \
        | grep -qE 'flatline-reviewer'; then
        echo "flatline-reviewer"
    else
        echo "reviewing-code"
    fi
}

@test "D-7: payload.tokens_input is populated from CompletionResult.usage" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not on PATH"
    fi
    [[ -f "$CHEVAL" ]] || skip "cheval.py not found"

    local agent
    agent="$(_pick_agent)"

    run python3 "$CHEVAL" \
        --agent "$agent" \
        --prompt "test input" \
        --mock-fixture-dir "$FIXTURE_DIR" \
        --output-format json

    [ -f "$LOA_MODELINV_LOG_PATH" ]
    # Exact match — fixture said input_tokens: 12345, envelope must mirror.
    grep -qE '"tokens_input":[[:space:]]*12345' "$LOA_MODELINV_LOG_PATH"
}

@test "D-7: payload.tokens_output is populated from CompletionResult.usage" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not on PATH"
    fi
    [[ -f "$CHEVAL" ]] || skip "cheval.py not found"

    local agent
    agent="$(_pick_agent)"

    run python3 "$CHEVAL" \
        --agent "$agent" \
        --prompt "test input" \
        --mock-fixture-dir "$FIXTURE_DIR" \
        --output-format json

    [ -f "$LOA_MODELINV_LOG_PATH" ]
    grep -qE '"tokens_output":[[:space:]]*678' "$LOA_MODELINV_LOG_PATH"
}

@test "D-7: both token fields appear in same envelope (atomic capture)" {
    # Negative-confound guard: ensures we aren't accidentally writing one
    # value and the other separately (e.g., from a different invocation's
    # state). The mock fixture path writes ONE envelope; both fields must
    # be in that single envelope.
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not on PATH"
    fi
    [[ -f "$CHEVAL" ]] || skip "cheval.py not found"

    local agent
    agent="$(_pick_agent)"

    run python3 "$CHEVAL" \
        --agent "$agent" \
        --prompt "test input" \
        --mock-fixture-dir "$FIXTURE_DIR" \
        --output-format json

    [ -f "$LOA_MODELINV_LOG_PATH" ]

    # Exactly one envelope on this log; it should contain BOTH fields.
    local n
    n=$(wc -l < "$LOA_MODELINV_LOG_PATH")
    [ "$n" -eq 1 ]
    grep -qE '"tokens_input":[[:space:]]*12345' "$LOA_MODELINV_LOG_PATH"
    grep -qE '"tokens_output":[[:space:]]*678' "$LOA_MODELINV_LOG_PATH"
}

@test "D-7: zero output_tokens is recorded (not omitted)" {
    # Some providers report 0 output_tokens on empty content. Treating
    # 0 as "no signal" would silently drop the data point. The cheval
    # capture logic uses `isinstance(x, int) and x >= 0`, so 0 is kept.
    # This regression guard pins that behavior.
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not on PATH"
    fi
    [[ -f "$CHEVAL" ]] || skip "cheval.py not found"

    cat > "$FIXTURE_DIR/response.json" <<'EOF'
{
  "content": "",
  "usage": {"input_tokens": 100, "output_tokens": 0}
}
EOF

    local agent
    agent="$(_pick_agent)"

    run python3 "$CHEVAL" \
        --agent "$agent" \
        --prompt "test input" \
        --mock-fixture-dir "$FIXTURE_DIR" \
        --output-format json

    [ -f "$LOA_MODELINV_LOG_PATH" ]
    grep -qE '"tokens_input":[[:space:]]*100' "$LOA_MODELINV_LOG_PATH"
    grep -qE '"tokens_output":[[:space:]]*0' "$LOA_MODELINV_LOG_PATH"
}
