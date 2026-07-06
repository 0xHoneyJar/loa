#!/usr/bin/env bats
# =============================================================================
# tests/integration/d3-flatline-scorer-compat.bats — cycle-116 D3
# (bd-c116-d3-tiering)
# =============================================================================
# Proves the per-stage tier-routing opt-in is TRULY opt-in: with the flag
# default-off, flatline-orchestrator.sh's call_model() builds a byte-for-byte
# identical cheval argv to pre-D3 (the hardcoded `--model` pin). Divergence to
# the advisor_strategy role/skill path happens ONLY when the operator flips
# advisor_strategy.stage_routing.flatline_scorer AND the mode is `score`.
#
# Method (mirrors tests/unit/bug-899-vq-sidecar-survives-failure.bats): extract
# call_model() via awk, stub its collaborators + a recording MODEL_INVOKE that
# writes its argv to a file, then assert the recorded argv per flag/mode combo.
# No live API calls.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export PROJECT_ROOT
    ORCH="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    CHEVAL="$PROJECT_ROOT/.claude/adapters/cheval.py"
    WORK="$(mktemp -d)"
    export WORK
    # Recording MODEL_INVOKE stub: dumps argv, emits minimal valid cheval JSON.
    cat > "$WORK/stub.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$REC_ARGS"
echo '{"content":"{\"scores\":[]}","usage":{"input_tokens":1,"output_tokens":1},"latency_ms":1}'
exit 0
STUB
    chmod +x "$WORK/stub.sh"
    export STUB="$WORK/stub.sh"
    export REC_ARGS="$WORK/args.txt"
    echo "x" > "$WORK/input"
}

teardown() {
    rm -rf "$WORK"
}

# Run call_model with a given flag-state and mode; recorded argv lands in REC_ARGS.
_run_call_model() {
    local flag="$1" mode="$2"
    FLAG="$flag" MODE="$mode" bash -c '
        set +e
        SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
        MODEL_INVOKE="$STUB"
        TEMP_DIR="$WORK"
        DEFAULT_MODEL_TIMEOUT=30
        declare -A MODE_TO_AGENT=( ["review"]="flatline-reviewer" ["score"]="flatline-scorer" )
        declare -A MODEL_TO_PROVIDER_ID=()
        resolve_provider_id(){ echo "prov:$1"; }
        log(){ :; }; log_invoke_failure(){ :; }; cleanup_invoke_log(){ :; }
        redact_secrets(){ cat; }
        setup_invoke_log(){ echo "$WORK/il"; }
        is_stage_routing_scorer_enabled(){ [ "$FLAG" = "true" ]; }
        eval "$(awk "/^call_model\(\)/,/^}/" "'"$ORCH"'")"
        call_model "opus" "$MODE" "$WORK/input" "prd" "" "5" >/dev/null 2>/dev/null
    '
}

@test "default-off + score: argv keeps --model pin, no --role (byte-identical to pre-D3)" {
    _run_call_model "false" "score"
    grep -qx -- "--model" "$REC_ARGS"
    ! grep -qx -- "--role" "$REC_ARGS"
    ! grep -qx -- "--skill" "$REC_ARGS"
}

@test "flag-on + score: argv routes via --role/--skill, drops --model" {
    _run_call_model "true" "score"
    grep -qx -- "--role" "$REC_ARGS"
    grep -A1 -x -- "--role" "$REC_ARGS" | grep -qx "implementation"
    grep -qx -- "--skill" "$REC_ARGS"
    grep -A1 -x -- "--skill" "$REC_ARGS" | grep -qx "flatline-scorer"
    ! grep -qx -- "--model" "$REC_ARGS"
}

@test "flag-on + review: only score-mode routes; review keeps --model pin" {
    _run_call_model "true" "review"
    grep -qx -- "--model" "$REC_ARGS"
    ! grep -qx -- "--role" "$REC_ARGS"
}

@test "agent binding for score mode is unchanged (--agent flatline-scorer both paths)" {
    _run_call_model "false" "score"
    grep -A1 -x -- "--agent" "$REC_ARGS" | grep -qx "flatline-scorer"
    _run_call_model "true" "score"
    grep -A1 -x -- "--agent" "$REC_ARGS" | grep -qx "flatline-scorer"
}

# --- Flag-reading: is_stage_routing_scorer_enabled honors config -------------

_flag_returns() {
    # Prints the return code of is_stage_routing_scorer_enabled against $1 config.
    local cfg="$1"
    CONFIG_FILE="$cfg" bash -c '
        set +e
        eval "$(awk "/^read_config\(\)/,/^}/" "'"$ORCH"'")"
        eval "$(awk "/^is_stage_routing_scorer_enabled\(\)/,/^}/" "'"$ORCH"'")"
        is_stage_routing_scorer_enabled
        echo "rc=$?"
    '
}

@test "flag-read: absent stage_routing key => disabled (rc!=0)" {
    printf 'advisor_strategy:\n  enabled: true\n' > "$WORK/cfg.yaml"
    run _flag_returns "$WORK/cfg.yaml"
    echo "$output" | grep -qx "rc=1"
}

@test "flag-read: flatline_scorer: false => disabled (rc!=0)" {
    printf 'advisor_strategy:\n  stage_routing:\n    flatline_scorer: false\n' > "$WORK/cfg.yaml"
    run _flag_returns "$WORK/cfg.yaml"
    echo "$output" | grep -qx "rc=1"
}

@test "flag-read: flatline_scorer: true => enabled (rc=0)" {
    printf 'advisor_strategy:\n  stage_routing:\n    flatline_scorer: true\n' > "$WORK/cfg.yaml"
    run _flag_returns "$WORK/cfg.yaml"
    echo "$output" | grep -qx "rc=0"
}

# --- Live resolver: divergence is opt-in (cheval dry-run, no API) ------------

@test "resolver: today's scorer binding (agent-only) resolves to the cheap-tier pin" {
    run env PYTHONPATH="$PROJECT_ROOT/.claude/adapters" python3 "$CHEVAL" \
        --agent flatline-scorer --dry-run --output-format json
    [ "$status" -eq 0 ]
    # cycle-114 binding: flatline-scorer -> cheap tier (Sonnet 4.6).
    echo "$output" | jq -e '.resolved_model == "claude-sonnet-4-6"'
}

@test "resolver: role/skill path is governed by advisor_strategy (diverges only when --role passed)" {
    run env PYTHONPATH="$PROJECT_ROOT/.claude/adapters" python3 "$CHEVAL" \
        --agent flatline-scorer --role implementation --skill flatline-scorer \
        --dry-run --output-format json
    [ "$status" -eq 0 ]
    # No per_skill_override for flatline-scorer => role default (implementation
    # -> advisor). Advisor tier for anthropic is claude-opus-4-8. This differs
    # from the agent-only path above, proving the flag flip is a deliberate,
    # operator-visible change — never a silent default drift.
    echo "$output" | jq -e '.resolved_model == "claude-opus-4-8"'
}
