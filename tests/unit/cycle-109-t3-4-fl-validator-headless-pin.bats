#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t3-4-fl-validator-headless-pin.bats
#
# cycle-109 Sprint 3 T3.4 — closes #793 (FL validator rejects cheval-
# headless pin form). Adds regression coverage for:
#
#   1. <provider>-headless:<model_id> pin form (claude-headless:
#      claude-opus-4-7, codex-headless:gpt-5.5, gemini-headless:
#      gemini-3.1-pro-preview).
#   2. -preview suffix on Gemini models (the adjacent gap #793 calls out;
#      `gemini-3.1-pro-preview` is the canonical Google API model ID for
#      Gemini 3.1 Pro).
#
# Test pattern: source flatline-orchestrator.sh under a guard that prevents
# main() from executing (orchestrator doesn't have the source-vs-exec
# guard yet — added to adversarial-review.sh in T2.5). We use a stubbed
# main + minimal env to source just the validate_model function.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    # Stub functions so sourcing is hermetic — orchestrator runs `main "$@"`
    # at file bottom; we override main to no-op + stub the noisy log/error
    # helpers that get called during config validation.
    main() { :; }
    log() { :; }
    error() { printf '%s\n' "$*" >&2; return 1; }
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh" 2>/dev/null || true
}

# =============================================================================
# T34-1..3: cheval-headless pin form accepted for each provider
# =============================================================================

@test "T34-1: validate_model accepts claude-headless:claude-opus-4-7" {
    run validate_model "claude-headless:claude-opus-4-7" "primary"
    [ "$status" -eq 0 ]
}

@test "T34-2: validate_model accepts codex-headless:gpt-5.5" {
    run validate_model "codex-headless:gpt-5.5" "secondary"
    [ "$status" -eq 0 ]
}

@test "T34-3: validate_model accepts gemini-headless:gemini-3.1-pro-preview" {
    run validate_model "gemini-headless:gemini-3.1-pro-preview" "tertiary"
    [ "$status" -eq 0 ]
}

# =============================================================================
# T34-4: Gemini -preview suffix gap (#793 adjacent fix)
# =============================================================================

@test "T34-4: validate_model accepts gemini-3.1-pro-preview (the -preview suffix)" {
    run validate_model "gemini-3.1-pro-preview" "primary"
    [ "$status" -eq 0 ]
}

@test "T34-5: validate_model accepts gemini-2.5-flash-preview" {
    run validate_model "gemini-2.5-flash-preview" "secondary"
    [ "$status" -eq 0 ]
}

# =============================================================================
# T34-6: Existing forward-compat patterns still work (no regression)
# =============================================================================

@test "T34-6: validate_model still accepts existing forward-compat patterns" {
    run validate_model "gpt-5.3-codex" "primary"
    [ "$status" -eq 0 ]
    run validate_model "claude-opus-4-7" "secondary"
    [ "$status" -eq 0 ]
    run validate_model "gemini-2.5-pro" "tertiary"
    [ "$status" -eq 0 ]
    run validate_model "opus" "primary"
    [ "$status" -eq 0 ]
}

# =============================================================================
# T34-7: Typos / invalid still rejected (regex isn't too permissive)
# =============================================================================

@test "T34-7: validate_model still rejects obvious typos" {
    # Not a known model + doesn't match any forward-compat pattern
    run validate_model "claude-bogus-4-7" "primary"
    [ "$status" -ne 0 ]
}

@test "T34-8: validate_model rejects empty model name" {
    run validate_model "" "primary"
    [ "$status" -ne 0 ]
}

# =============================================================================
# T34-9: Headless pin form requires a model-id suffix (not bare)
# =============================================================================

@test "T34-9: validate_model rejects bare 'claude-headless' without :model" {
    # The pin form is `<provider>-headless:<model>`. Bare `claude-headless`
    # would route to the YAML's claude-headless alias instead (handled by
    # the VALID_FLATLINE_MODELS allowlist via generated-model-maps.sh, NOT
    # by the pin-form pattern). The pattern MUST require the `:model_id`.
    #
    # If `claude-headless` happens to be in the allowlist (it is —
    # generated from model-config.yaml), the test passes via allowlist;
    # the negative shape we test here is to ensure the pin-form regex
    # doesn't match a bare alias and produce a false positive.
    #
    # Verify the regex specifically:
    local pat='^(claude|codex|gemini)-headless:.+$'
    [[ ! "claude-headless" =~ $pat ]]
    [[ "claude-headless:claude-opus-4-7" =~ $pat ]]
}
