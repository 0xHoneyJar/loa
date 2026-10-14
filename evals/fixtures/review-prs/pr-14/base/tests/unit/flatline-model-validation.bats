#!/usr/bin/env bats
# Unit tests for flatline-orchestrator.sh model validation (issue #305)
# Tests validate_model(), DEFAULT_MODEL_TIMEOUT, stderr capture, and stagger logic

# Bats quirk: each `@test` runs in a subshell that does not inherit non-exported
# state from setup() or file-top-level. Bash arrays cannot be exported, so the
# strategy below is to redefine validate_model as a wrapper that sources
# generated-model-maps.sh inside its OWN body. That way every `run validate_model`
# call sees the populated VALID_FLATLINE_MODELS regardless of subshell scoping.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    export ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    export GENERATED_MAPS="$PROJECT_ROOT/.claude/scripts/generated-model-maps.sh"

    # Stubs for functions defined elsewhere in the orchestrator.
    error() { echo "ERROR: $*" >&2; }
    log() { echo "$*" >&2; }
    export -f error log

    # Extract the orchestrator's validate_model() definition and rename it so
    # we can wrap it with a fresh-source-each-call wrapper (see below).
    local fn_src
    fn_src=$(awk '/^validate_model\(\)/{found=1} found{print; if(/^}/)exit}' "$ORCHESTRATOR")
    # Rename the extracted function to _real_validate_model.
    fn_src="${fn_src/validate_model()/_real_validate_model()}"
    eval "$fn_src"

    # Extract VALID_MODEL_PATTERNS (top-level definition).
    eval "$(awk '/^VALID_MODEL_PATTERNS=/{found=1} found{print} found && /^\)/{exit}' "$ORCHESTRATOR")"

    # Wrapper: sources VALID_FLATLINE_MODELS fresh into the call's local scope
    # (combined with `declare -ga`-style re-export below) before delegating.
    # This avoids the bats-subshell-vs-bash-array visibility issue: arrays
    # cannot be exported across subshell boundaries, but a freshly-sourced
    # generated-model-maps.sh inside the function body brings the array into
    # validate_model's own scope so the for-loop sees it.
    validate_model() {
        # shellcheck source=/dev/null
        [[ -f "$GENERATED_MAPS" ]] && source "$GENERATED_MAPS"
        _real_validate_model "$@"
    }
    export -f validate_model _real_validate_model
}

# =============================================================================
# Model Validation Tests
# =============================================================================

@test "validate_model accepts 'opus'" {
    run validate_model "opus" "primary"
    [ "$status" -eq 0 ]
}

@test "validate_model accepts 'gpt-5.2'" {
    run validate_model "gpt-5.2" "secondary"
    [ "$status" -eq 0 ]
}

@test "validate_model accepts 'claude-opus-4.6'" {
    run validate_model "claude-opus-4.6" "primary"
    [ "$status" -eq 0 ]
}

@test "validate_model accepts 'claude-opus-4.7' (cycle-082)" {
    run validate_model "claude-opus-4.7" "primary"
    [ "$status" -eq 0 ]
}

@test "validate_model accepts 'claude-opus-4-7' (cycle-082 canonical)" {
    run validate_model "claude-opus-4-7" "primary"
    [ "$status" -eq 0 ]
}

@test "validate_model accepts 'gemini-2.0'" {
    run validate_model "gemini-2.0" "primary"
    [ "$status" -eq 0 ]
}

@test "validate_model rejects an unknown name with actionable error" {
    # Note: this test originally used 'reviewer' as the rejection example.
    # cycle-093 sprint-4 (T4.2) added 'reviewer' (and other aliases) to the
    # SSOT-derived VALID_FLATLINE_MODELS array — aliases are now valid
    # flatline model names by design. Use a name that's neither in the array
    # nor matches any forward-compat pattern to exercise the rejection path.
    run validate_model "agent-style-bogus-name" "secondary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flatline model"* ]]
    [[ "$output" == *"agent-style-bogus-name"* ]]
    [[ "$output" == *".loa.config.yaml"* ]]
    [[ "$output" == *"agent alias"* ]]
}

@test "validate_model rejects 'skeptic'" {
    run validate_model "skeptic" "secondary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flatline model"* ]]
}

@test "validate_model rejects empty string" {
    run validate_model "" "primary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty"* ]]
}

@test "validate_model rejects 'nonexistent'" {
    run validate_model "nonexistent" "secondary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flatline model"* ]]
}

@test "error message includes valid model list" {
    # Use a model name that's definitively NOT in the array AND doesn't match
    # any forward-compat pattern, so validate_model falls through to the
    # error-path which prints `Known-good models: ${VALID_FLATLINE_MODELS[*]}`.
    run validate_model "definitely-not-a-real-model-zzz" "secondary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flatline model"* ]]
    # Two well-known sentinels from the SSOT-derived list.
    [[ "$output" == *"opus"* ]]
    [[ "$output" == *"gpt-5.2"* ]]
}

# =============================================================================
# Timeout Configuration Test
# =============================================================================

@test "DEFAULT_MODEL_TIMEOUT is at least 120 seconds" {
    local timeout
    timeout=$(grep -E '^DEFAULT_MODEL_TIMEOUT=' "$ORCHESTRATOR" | head -1 | cut -d= -f2)
    [ "$timeout" -ge 120 ]
}

# =============================================================================
# Stderr Capture Tests (structural)
# =============================================================================

@test "Phase 1 call_model lines do not redirect stderr to /dev/null" {
    local devnull_count
    devnull_count=$(sed -n '/^run_phase1/,/^}/p' "$ORCHESTRATOR" | grep 'call_model' | grep -c '2>/dev/null' || true)
    [ "$devnull_count" -eq 0 ]
}

@test "Phase 1 uses stderr capture files for all 4 calls" {
    local stderr_count
    stderr_count=$(sed -n '/^run_phase1/,/^}/p' "$ORCHESTRATOR" | grep -c 'stderr.log' || true)
    [ "$stderr_count" -ge 4 ]
}

# =============================================================================
# Stagger Tests (structural)
# =============================================================================

@test "Phase 1 includes stagger sleep between review and skeptic waves" {
    local stagger_count
    stagger_count=$(sed -n '/^run_phase1/,/^}/p' "$ORCHESTRATOR" | grep -c 'sleep' || true)
    [ "$stagger_count" -ge 1 ]
}
