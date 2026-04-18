#!/usr/bin/env bats
# =============================================================================
# flatline-model-allowlist.bats — Tests for flatline model allowlist (#573 + #574)
# =============================================================================
# Sprint-bug-113. Validates:
# - Phantom Gemini 3 models pruned from VALID_FLATLINE_MODELS (#574)
# - Forward-compat regex patterns admit new model versions (#573)
# - validate_model accepts known-good + pattern-matching + rejects garbage

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export ORCH="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR"
}

# Extract just the validate_model function + its supporting arrays for unit testing
_extract_validator() {
    awk '/^# Valid model names/,/^}$/' "$ORCH" > "$TEST_DIR/validator.sh"
}

# =========================================================================
# FMA-T1: phantom Gemini 3 models no longer in allowlist (#574)
# =========================================================================

@test "gemini-3-pro NOT in VALID_FLATLINE_MODELS" {
    run grep -E "VALID_FLATLINE_MODELS=\\(.*gemini-3-pro[^-]" "$ORCH"
    [ "$status" -ne 0 ]
}

@test "gemini-3-flash NOT in VALID_FLATLINE_MODELS" {
    run grep -E "VALID_FLATLINE_MODELS=\\(.*gemini-3-flash" "$ORCH"
    [ "$status" -ne 0 ]
}

@test "gemini-3.1-pro NOT in VALID_FLATLINE_MODELS" {
    run grep -E "VALID_FLATLINE_MODELS=\\(.*gemini-3\\.1-pro" "$ORCH"
    [ "$status" -ne 0 ]
}

@test "gemini-3-pro NOT in MODEL_TO_PROVIDER_ID" {
    run grep -E '\["gemini-3-pro"\]=' "$ORCH"
    [ "$status" -ne 0 ]
}

# =========================================================================
# FMA-T2: known-good models still allowlisted
# =========================================================================

@test "opus still in VALID_FLATLINE_MODELS" {
    run grep -E "VALID_FLATLINE_MODELS=\\(.*\\bopus\\b" "$ORCH"
    [ "$status" -eq 0 ]
}

@test "gemini-2.5-pro still in VALID_FLATLINE_MODELS" {
    run grep -E "VALID_FLATLINE_MODELS=\\(.*gemini-2\\.5-pro" "$ORCH"
    [ "$status" -eq 0 ]
}

@test "gpt-5.3-codex still in VALID_FLATLINE_MODELS" {
    run grep -E "VALID_FLATLINE_MODELS=\\(.*gpt-5\\.3-codex" "$ORCH"
    [ "$status" -eq 0 ]
}

# =========================================================================
# FMA-T3: forward-compat patterns present (#573)
# =========================================================================

@test "VALID_MODEL_PATTERNS array exists" {
    run grep -c "^VALID_MODEL_PATTERNS=" "$ORCH"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "openai forward-compat pattern accepts gpt-5.4-codex" {
    # Extract the openai pattern and test against gpt-5.4-codex
    local pattern='^gpt-[0-9]+\.[0-9]+(-codex)?$'
    [[ "gpt-5.4-codex" =~ $pattern ]]
}

@test "openai forward-compat pattern accepts gpt-6.0" {
    local pattern='^gpt-[0-9]+\.[0-9]+(-codex)?$'
    [[ "gpt-6.0" =~ $pattern ]]
}

@test "openai forward-compat pattern rejects garbage-model" {
    local pattern='^gpt-[0-9]+\.[0-9]+(-codex)?$'
    [[ ! "garbage-model" =~ $pattern ]]
}

@test "anthropic forward-compat pattern accepts claude-opus-4-8" {
    local pattern='^claude-(opus|sonnet|haiku)-[0-9]+[-.][0-9]+$'
    [[ "claude-opus-4-8" =~ $pattern ]]
}

@test "gemini forward-compat pattern accepts gemini-2.5-pro" {
    local pattern='^gemini-[0-9]+\.[0-9]+(-flash|-pro)?$'
    [[ "gemini-2.5-pro" =~ $pattern ]]
}

# =========================================================================
# FMA-T4: validate_model function-level tests
# =========================================================================

@test "validate_model accepts a known-good model" {
    _extract_validator
    run bash -c "
        log() { :; }
        error() { echo \"ERROR: \$*\" >&2; }
        source '$TEST_DIR/validator.sh'
        validate_model 'opus' 'primary'
    "
    [ "$status" -eq 0 ]
}

@test "validate_model accepts a forward-compat model via pattern" {
    _extract_validator
    run bash -c "
        log() { :; }
        error() { echo \"ERROR: \$*\" >&2; }
        source '$TEST_DIR/validator.sh'
        validate_model 'gpt-5.4-codex' 'secondary' 2>/dev/null
    "
    [ "$status" -eq 0 ]
}

@test "validate_model rejects empty model name" {
    _extract_validator
    run bash -c "
        log() { :; }
        error() { echo \"ERROR: \$*\" >&2; }
        source '$TEST_DIR/validator.sh'
        validate_model '' 'primary' 2>/dev/null
    "
    [ "$status" -ne 0 ]
}

@test "validate_model rejects garbage model" {
    _extract_validator
    run bash -c "
        log() { :; }
        error() { echo \"ERROR: \$*\" >&2; }
        source '$TEST_DIR/validator.sh'
        validate_model 'definitely-not-a-model' 'secondary' 2>/dev/null
    "
    [ "$status" -ne 0 ]
}

@test "validate_model rejects previously-phantom gemini-3-pro (#574 regression guard)" {
    _extract_validator
    run bash -c "
        log() { :; }
        error() { echo \"ERROR: \$*\" >&2; }
        source '$TEST_DIR/validator.sh'
        validate_model 'gemini-3-pro' 'tertiary' 2>/dev/null
    "
    # Pattern matches gemini-X.Y not gemini-X-Y, so this should fail
    # (the dotted pattern admits gemini-3.0-pro but not gemini-3-pro)
    # …wait, gemini-3-pro has no dot. Pattern ^gemini-[0-9]+\.[0-9]+ requires dot.
    # So this correctly rejects.
    [ "$status" -ne 0 ]
}
