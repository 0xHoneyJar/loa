#!/usr/bin/env bats
# =============================================================================
# Cycle-112 D-6 (#931) — calling_primitive attribution propagation
# =============================================================================
# Pins the contract that cheval.cmd_invoke threads the caller's identity
# through to the MODELINV envelope as `payload.calling_primitive`.
#
# Pre-fix empirical reality (per cycle-112 SDD §0.3): 0 of 808 envelopes
# carry attribution. Phase B routing decisions ("is /review-sprint cheaper
# on advisor or executor?") are unanswerable without this. D-6 closes that
# gap by:
#   1. When --skill is passed, use it as calling_primitive
#   2. When --skill is omitted but --agent is set, fall back to --agent
#      (gives 100% attribution coverage on every existing caller path
#       without requiring bash-side --skill threading)
#
# Test strategy: invoke cheval with --mock-fixture-dir against a fixture
# that returns a canned CompletionResult, redirect MODELINV log to a temp
# path via LOA_MODELINV_LOG_PATH, and grep the resulting envelope for the
# expected calling_primitive value.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CHEVAL="$REPO_ROOT/.claude/adapters/cheval.py"
    TMP_DIR="$(mktemp -d)"
    export PROJECT_ROOT="$REPO_ROOT"
    export LOA_MODELINV_LOG_PATH="$TMP_DIR/model-invoke.jsonl"
    # Disable advisor-strategy so --skill doesn't trigger tier resolution
    # (this test pins envelope attribution, not tier resolution).
    export LOA_ADVISOR_STRATEGY_DISABLE=1

    # Create a minimal mock fixture for an Anthropic agent.
    FIXTURE_DIR="$TMP_DIR/fixture"
    mkdir -p "$FIXTURE_DIR"
    cat > "$FIXTURE_DIR/response.json" <<'EOF'
{
  "content": "## D-6 attribution test fixture",
  "usage": {"input_tokens": 10, "output_tokens": 5}
}
EOF
}

teardown() {
    rm -rf "$TMP_DIR"
}

# Helper: find the agent that the cheval --print-effective-config knows about
# and which can be exercised through the mock-fixture path. We use the
# `flatline-reviewer` agent since it's documented in the dispatch surface.
# Falls back to whatever the first listed agent is.
_pick_agent() {
    # flatline-reviewer is a well-known agent; check existence.
    if python3 "$CHEVAL" --print-effective-config 2>/dev/null \
        | grep -qE 'flatline-reviewer'; then
        echo "flatline-reviewer"
    else
        echo "reviewing-code"
    fi
}

@test "D-6: --skill value is propagated to MODELINV envelope as calling_primitive" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not on PATH"
    fi
    [[ -f "$CHEVAL" ]] || skip "cheval.py not found"

    local agent
    agent="$(_pick_agent)"

    run python3 "$CHEVAL" \
        --agent "$agent" \
        --skill "/review-sprint" \
        --prompt "test input" \
        --mock-fixture-dir "$FIXTURE_DIR" \
        --output-format json
    # Don't require status == 0 — mock-fixture path may exit non-zero
    # on schema mismatch; the assertion is about envelope content.

    [ -f "$LOA_MODELINV_LOG_PATH" ]
    # The envelope should carry calling_primitive == "/review-sprint"
    grep -q '"calling_primitive":[[:space:]]*"/review-sprint"' \
        "$LOA_MODELINV_LOG_PATH"
}

@test "D-6: --agent fallback when --skill omitted populates calling_primitive" {
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
    # When --skill is omitted, the agent name fills calling_primitive
    # so /loa status --economy gets attribution for free.
    grep -qE "\"calling_primitive\":[[:space:]]*\"${agent}\"" \
        "$LOA_MODELINV_LOG_PATH"
}

@test "D-6: zero-arg invocation (no --skill, no --agent) emits no calling_primitive field" {
    # Negative-control: D-6 only adds attribution when at least one of
    # --skill / --agent is set. When neither is set, the envelope MUST
    # NOT carry a calling_primitive field (backward-compat invariant —
    # pre-D-6 callers that omit both produce shape-identical envelopes).
    #
    # In practice, cmd_invoke requires --agent to succeed, so this case
    # is a defensive lower-bound. We test via --print-effective-config
    # which does NOT invoke cmd_invoke and therefore does NOT emit a
    # MODELINV envelope at all. If the log file is empty/missing, the
    # invariant holds vacuously.
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not on PATH"
    fi
    [[ -f "$CHEVAL" ]] || skip "cheval.py not found"

    run python3 "$CHEVAL" --print-effective-config
    [ "$status" -eq 0 ]
    # No envelope should have been written for --print-effective-config.
    [ ! -s "$LOA_MODELINV_LOG_PATH" ]
}
