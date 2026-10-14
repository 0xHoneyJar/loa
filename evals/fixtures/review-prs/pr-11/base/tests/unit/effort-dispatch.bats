#!/usr/bin/env bats
# =============================================================================
# tests/unit/effort-dispatch.bats — cycle-124 Sprint 3 Task 3.5 (FR-9 / AC-9.1)
#
# Effort defaults use the surface that already exists — the validated SKILL.md
# frontmatter `effort:` key — plus the one missing consumer:
#   model-adapter.sh resolve_effort(): --effort arg > skill frontmatter > none;
#   an invalid level yields no flag; the resolution is a pure function of its
#   inputs (two runs, byte-identical argv), so it can never invalidate the
#   cached prefix. flatline-orchestrator.sh maps mode → effort beside its
#   --max-tokens append (review|skeptic → xhigh, score → medium).
# The dead `effort:` config block and its TypeScript sample are deleted.
# Harness: the recording MODEL_INVOKE shim from cycle-124-dispatch-budgets.bats.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    ADAPTER="$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
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
    # a throwaway skills dir for the resolver's frontmatter branch
    SK="$BATS_TEST_TMPDIR/skills"
    mkdir -p "$SK/with-effort" "$SK/bad-effort" "$SK/no-effort" "$SK/commented"
    printf -- '---\nname: a\neffort: high\n---\nbody\n' > "$SK/with-effort/SKILL.md"
    printf -- '---\nname: b\neffort: turbo\n---\nbody\n' > "$SK/bad-effort/SKILL.md"
    printf -- '---\nname: c\n---\nbody\n' > "$SK/no-effort/SKILL.md"
    printf -- '---\nname: d\neffort: medium  # trailing comment\n---\nbody\n' > "$SK/commented/SKILL.md"
}

_argv_value() { awk -v flag="$1" '$0 == flag {getline; print; exit}' "$ARGV"; }

# resolve_effort() in isolation: eval the function body out of the adapter.
_resolve() {  # <arg> <skill> <skills-dir>
    bash -c '
        eval "$(awk "/^resolve_effort\(\)/,/^}/" "$1")"
        resolve_effort "$2" "$3" "$4"
    ' _ "$ADAPTER" "$1" "$2" "$3"
}

_call_model() {  # <mode>
    MODE_ARG="$1" INPUT_ARG="$BATS_TEST_TMPDIR/input.txt" ORCHESTRATOR_PATH="$ORCHESTRATOR" bash -c '
        SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
        declare -A MODE_TO_AGENT=([review]=flatline-reviewer [skeptic]=flatline-skeptic [score]=flatline-scorer)
        DEFAULT_MODEL_TIMEOUT=30
        PER_CALL_MAX_TOKENS=""
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
}

@test "ED-1 resolve_effort: --effort arg wins over the skill frontmatter" {
    [ "$(_resolve low with-effort "$SK")" = "low" ]
}

@test "ED-2 resolve_effort: skill frontmatter effort is used when no arg is given (comments stripped)" {
    [ "$(_resolve "" with-effort "$SK")" = "high" ]
    [ "$(_resolve "" commented "$SK")" = "medium" ]
}

@test "ED-3 resolve_effort: absent, invalid, unknown skill and a path-shaped skill name all yield nothing" {
    [ -z "$(_resolve "" no-effort "$SK")" ]
    [ -z "$(_resolve "" bad-effort "$SK")" ]
    [ -z "$(_resolve turbo with-effort "$SK")" ]
    [ -z "$(_resolve "" nonexistent "$SK")" ]
    [ -z "$(_resolve "" "../../etc" "$SK")" ]
}

@test "ED-4 model-adapter --skill reviewing-code ⇒ --effort xhigh (skill frontmatter)" {
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-5 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --skill reviewing-code
    [ -s "$ARGV" ] || { echo "$output" >&2; return 1; }
    [ "$(_argv_value --effort)" = "xhigh" ]
}

@test "ED-5 model-adapter --skill auditing-security ⇒ --effort medium; implementing-tasks ⇒ xhigh" {
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-5 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --skill auditing-security
    [ "$(_argv_value --effort)" = "medium" ]
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-5 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --skill implementing-tasks
    [ "$(_argv_value --effort)" = "xhigh" ]
}

@test "ED-6 model-adapter --effort overrides the skill, and a skill without effort adds no flag" {
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-5 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --skill reviewing-code --effort low
    [ "$(_argv_value --effort)" = "low" ]
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-5 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --skill bug-triaging
    [ -s "$ARGV" ]
    ! grep -qx -- '--effort' "$ARGV"
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-5 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --effort bogus
    [ -s "$ARGV" ]
    ! grep -qx -- '--effort' "$ARGV"
}

@test "ED-7 two consecutive resolutions produce byte-identical argv (pure function of the skill)" {
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-5 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --skill reviewing-code
    cp "$ARGV" "$BATS_TEST_TMPDIR/argv.first"
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-5 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --skill reviewing-code
    cmp -s "$BATS_TEST_TMPDIR/argv.first" "$ARGV"
}

@test "ED-8 flatline: review and skeptic ⇒ --effort xhigh, score ⇒ medium; --max-tokens still appended" {
    _call_model review
    [ "$(_argv_value --effort)" = "xhigh" ]
    [ "$(_argv_value --max-tokens)" = "16000" ]
    _call_model skeptic
    [ "$(_argv_value --effort)" = "xhigh" ]
    _call_model score
    [ "$(_argv_value --effort)" = "medium" ]
    [ "$(_argv_value --max-tokens)" = "16000" ]
}

@test "ED-9 validate-skill-capabilities.sh passes on the edited frontmatters" {
    run bash "$PROJECT_ROOT/.claude/scripts/validate-skill-capabilities.sh"
    [ "$status" -eq 0 ]
    grep -qE '^effort: xhigh' "$PROJECT_ROOT/.claude/skills/reviewing-code/SKILL.md"
    grep -qE '^effort: xhigh' "$PROJECT_ROOT/.claude/skills/implementing-tasks/SKILL.md"
    grep -qE '^effort: medium' "$PROJECT_ROOT/.claude/skills/auditing-security/SKILL.md"
}

@test "ED-10 the dead effort config block and its budget_ranges sample are gone" {
    ! grep -qE '^effort:' "$PROJECT_ROOT/.loa.config.yaml.example"
    ! grep -q 'budget_ranges' "$PROJECT_ROOT/.loa.config.yaml.example"
    ! grep -q 'budget_ranges' "$PROJECT_ROOT/docs/integration/runtime-contract.md"
    ! grep -q 'getEffortBudget' "$PROJECT_ROOT/docs/integration/runtime-contract.md"
}
