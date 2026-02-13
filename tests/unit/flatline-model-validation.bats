#!/usr/bin/env bats
# Unit tests for flatline-orchestrator.sh model validation (issue #305)
# Tests validate_model(), DEFAULT_MODEL_TIMEOUT, stderr capture, and stagger logic

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

# =============================================================================
# Model Validation Tests
# =============================================================================

@test "validate_model accepts 'opus'" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "opus" "primary"
    [ "$status" -eq 0 ]
}

@test "validate_model accepts 'gpt-5.2'" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "gpt-5.2" "secondary"
    [ "$status" -eq 0 ]
}

@test "validate_model accepts 'claude-opus-4.6'" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "claude-opus-4.6" "primary"
    [ "$status" -eq 0 ]
}

@test "validate_model accepts 'gemini-2.0'" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "gemini-2.0" "primary"
    [ "$status" -eq 0 ]
}

@test "validate_model rejects 'reviewer' with actionable error" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "reviewer" "secondary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flatline model"* ]]
    [[ "$output" == *"reviewer"* ]]
    [[ "$output" == *".loa.config.yaml"* ]]
    [[ "$output" == *"agent alias"* ]]
}

@test "validate_model rejects 'skeptic'" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "skeptic" "secondary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flatline model"* ]]
}

@test "validate_model rejects empty string" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "" "primary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty"* ]]
}

@test "validate_model rejects 'nonexistent'" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "nonexistent" "secondary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown flatline model"* ]]
}

@test "error message includes valid model list" {
    eval "$(sed -n '/^VALID_FLATLINE_MODELS=/,/^}/p' "$ORCHESTRATOR" | head -30)"
    eval "$(sed -n '/^validate_model()/,/^}/p' "$ORCHESTRATOR")"
    error() { echo "ERROR: $*" >&2; }

    run validate_model "reviewer" "secondary"
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
    # Count occurrences of 2>/dev/null in call_model lines within run_phase1
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
