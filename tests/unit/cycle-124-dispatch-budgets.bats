#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-124-dispatch-budgets.bats
#
# cycle-124 Sprint 1 Task 1.4 (FR-2 / SDD §3.2): every dispatcher whose output
# shape is bounded passes an explicit `--max-tokens` to cheval, so the new
# per-model default (Anthropic 64K) is reserved for open-ended calls and the
# 600 s Flatline / 120 s BB / dissent timeouts never meet a 64K generation.
#   - flatline-orchestrator.sh call_model: review/skeptic 16000, score 4000,
#     --per-call-max-tokens still overrides
#   - model-adapter.sh forwards --max-tokens to MODEL_INVOKE argv
#   - adversarial-review.sh: dissent passes 16000 end-to-end through
#     model-adapter; the primary INPUT budget follows the dissenter's company
#     (Anthropic 160000 = ceiling − 20K, else 24000)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    ADAPTER="$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
    ADVERSARIAL="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    # Recording MODEL_INVOKE shim: captures argv, answers with a minimal
    # model-invoke JSON so callers that parse the result do not choke.
    SHIM="$BATS_TEST_TMPDIR/model-invoke-shim"
    ARGV="$BATS_TEST_TMPDIR/argv.recorded"
    cat > "$SHIM" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGV"
cat <<'JSON'
{"content": "{\\"findings\\": []}", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1}
JSON
SHIM
    chmod +x "$SHIM"
    export MODEL_INVOKE="$SHIM"
    export TEMP_DIR="$BATS_TEST_TMPDIR"
    echo "doc" > "$BATS_TEST_TMPDIR/input.txt"
}

# Run the orchestrator's call_model in isolation (bug-899 harness pattern):
# extract the function body, stub its collaborators, dispatch to the shim.
_call_model() {  # <mode> [PER_CALL_MAX_TOKENS]
    local mode="$1" override="${2:-}"
    MODE_ARG="$mode" OVERRIDE_ARG="$override" INPUT_ARG="$BATS_TEST_TMPDIR/input.txt" \
    ORCHESTRATOR_PATH="$ORCHESTRATOR" bash -c '
        SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
        declare -A MODE_TO_AGENT=([review]=flatline-reviewer [skeptic]=flatline-skeptic [score]=flatline-scorer)
        DEFAULT_MODEL_TIMEOUT=30
        PER_CALL_MAX_TOKENS="$OVERRIDE_ARG"
        # The budgets are top-level constants in the orchestrator; source just those lines.
        eval "$(grep -E "^FLATLINE_(REVIEW|SCORE)_MAX_TOKENS=" "$ORCHESTRATOR_PATH")"
        log() { :; }; log_invoke_failure() { :; }; cleanup_invoke_log() { :; }
        redact_secrets() { cat; }
        setup_invoke_log() { echo "$TEMP_DIR/invoke-$$.log"; }
        configured_flatline_model() { return 1; }
        resolve_provider_id() { echo "anthropic:$1"; }
        is_stage_routing_scorer_enabled() { return 1; }
        eval "$(awk "/^call_model\(\)/,/^}/" "$ORCHESTRATOR_PATH")"
        call_model "opus" "$MODE_ARG" "$INPUT_ARG" "prd" "" "30" >/dev/null 2>&1 || true
    '
    cat "$ARGV" 2>/dev/null
}

_argv_value() {  # <flag>  — prints the token following <flag> in the recorded argv
    awk -v flag="$1" '$0 == flag {getline; print; exit}' "$ARGV"
}

@test "c124-1.4-B1: flatline review call passes --max-tokens 16000 by default" {
    _call_model review >/dev/null
    [ -s "$ARGV" ]
    [ "$(_argv_value --max-tokens)" = "16000" ]
}

@test "c124-1.4-B2: flatline skeptic call passes --max-tokens 16000 by default" {
    _call_model skeptic >/dev/null
    [ "$(_argv_value --max-tokens)" = "16000" ]
}

@test "c124-1.4-B3: flatline score call passes --max-tokens 4000 by default" {
    _call_model score >/dev/null
    [ "$(_argv_value --max-tokens)" = "4000" ]
}

@test "c124-1.4-B4: --per-call-max-tokens still overrides the bounded default" {
    _call_model review 2222 >/dev/null
    [ "$(_argv_value --max-tokens)" = "2222" ]
}

@test "c124-1.4-B5: model-adapter.sh forwards --max-tokens to MODEL_INVOKE argv" {
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-4-7 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --max-tokens 16000
    [ -s "$ARGV" ] || { echo "$output" >&2; return 1; }
    [ "$(_argv_value --max-tokens)" = "16000" ]
}

@test "c124-1.4-B6: model-adapter.sh without --max-tokens leaves the flag out (cheval default applies)" {
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-4-7 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt"
    [ -s "$ARGV" ] || { echo "$output" >&2; return 1; }
    ! grep -qx -- '--max-tokens' "$ARGV"
}

# Source adversarial-review.sh with main disabled (repair-loop harness pattern).
_source_adversarial() {
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL")"
    # eval-sourcing rewrites SCRIPT_DIR/PROJECT_ROOT from BASH_SOURCE (the bats
    # file) — restore them, as adversarial-review-repair-loop.bats does.
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
    # Defaults load_adversarial_config would set.
    CONF_ESCALATION_ENABLED="false"
    CONF_SECONDARY_BUDGET=12000
    CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200
    CONF_SECRET_SCANNING="true"
    CONF_SECRET_ALLOWLIST=()
}

@test "c124-1.4-B7: adversarial input budget is 160000 for Anthropic dissenters, 24000 otherwise" {
    _source_adversarial
    [ "$(_adv_input_budget_for_model opus)" = "160000" ]
    [ "$(_adv_input_budget_for_model fable)" = "160000" ]
    [ "$(_adv_input_budget_for_model anthropic:claude-opus-5)" = "160000" ]
    [ "$(_adv_input_budget_for_model claude-opus-4-8)" = "160000" ]
    [ "$(_adv_input_budget_for_model gpt-5.5)" = "24000" ]
    [ "$(_adv_input_budget_for_model reviewer)" = "24000" ]
    [ "$(_adv_input_budget_for_model openai:gpt-5.5-pro)" = "24000" ]
    [ "$(_adv_input_budget_for_model no-such-alias)" = "24000" ]
    [ "$DISSENT_MAX_OUTPUT_TOKENS" = "16000" ]
}

@test "c124-1.4-B8: adversarial dissent reaches cheval with --max-tokens 16000 (through model-adapter)" {
    _source_adversarial
    export FLATLINE_MOCK_MODE=true
    echo "system" > "$BATS_TEST_TMPDIR/sys.txt"
    run invoke_dissenter "$BATS_TEST_TMPDIR/sys.txt" "$BATS_TEST_TMPDIR/input.txt" claude-opus-4-7 30 "" review
    [ -s "$ARGV" ] || { echo "$output" >&2; return 1; }
    [ "$(_argv_value --max-tokens)" = "16000" ]
    [ "$(_argv_value --skill)" = "adversarial-review" ]
}

@test "c124-1.4-B9: assemble_dissent_context honours the per-company primary budget (4th arg)" {
    _source_adversarial
    local diff="$BATS_TEST_TMPDIR/big.diff"
    {
        echo "diff --git a/big.txt b/big.txt"
        echo "+++ b/big.txt"
        for i in $(seq 1 6000); do echo "+line $i $(printf 'x%.0s' $(seq 1 60))"; done
    } > "$diff"
    local small big
    small=$(assemble_dissent_context "$diff" review "" 24000 | jq -r '.user_prompt' | wc -c)
    big=$(assemble_dissent_context "$diff" review "" 160000 | jq -r '.user_prompt' | wc -c)
    [ "$big" -gt "$small" ]
}
