#!/usr/bin/env bats
# =============================================================================
# model-adapter-aliases.bats — Backward compat alias verification
# =============================================================================
# Verifies Opus model IDs resolve correctly through all maps.
# Cycle-049 (FR-3): original cross-version alias validation.
# Cycle-082: migration to Opus 4.7 as top-review default; 4.6 retargeted in bash.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
    export FLATLINE_MOCK_MODE=true
}

# Helper: dry-run a model and capture the resolved model ID from stderr
resolve_model() {
    local model="$1"
    "$SCRIPT_DIR/model-adapter.sh.legacy" \
        --model "$model" --mode review \
        --input "$PROJECT_ROOT/grimoires/loa/prd.md" \
        --dry-run 2>&1 | grep -oP 'Model: \S+ \(\K[^)]+' || echo "RESOLVE_FAILED"
}

# Helper: dry-run and check exit code (0 = validation passed + dry-run ok)
validate_model() {
    local model="$1"
    "$SCRIPT_DIR/model-adapter.sh.legacy" \
        --model "$model" --mode review \
        --input "$PROJECT_ROOT/grimoires/loa/prd.md" \
        --dry-run > /dev/null 2>&1
}

# T1: Registry validation passes with all entries
@test "validate_model_registry passes with no errors" {
    validate_model "opus"
}

# T2: claude-opus-4-0 resolves to current canonical (cycle-082: 4.7)
@test "claude-opus-4-0 resolves to claude-opus-4-7" {
    result=$(resolve_model "claude-opus-4-0")
    [ "$result" = "claude-opus-4-7" ]
}

# T3: claude-opus-4-1 resolves to current canonical
@test "claude-opus-4-1 resolves to claude-opus-4-7" {
    result=$(resolve_model "claude-opus-4-1")
    [ "$result" = "claude-opus-4-7" ]
}

# T4: claude-opus-4.0 (dotted) resolves to current canonical
@test "claude-opus-4.0 resolves to claude-opus-4-7" {
    result=$(resolve_model "claude-opus-4.0")
    [ "$result" = "claude-opus-4-7" ]
}

# T5: claude-opus-4.1 (dotted) resolves to current canonical
@test "claude-opus-4.1 resolves to claude-opus-4-7" {
    result=$(resolve_model "claude-opus-4.1")
    [ "$result" = "claude-opus-4-7" ]
}

# T6: claude-opus-4-5 (hyphenated) resolves to current canonical
@test "claude-opus-4-5 resolves to claude-opus-4-7" {
    result=$(resolve_model "claude-opus-4-5")
    [ "$result" = "claude-opus-4-7" ]
}

# T7: Existing claude-opus-4.5 alias resolves to current (cycle-082: 4.7)
@test "claude-opus-4.5 alias resolves to claude-opus-4-7" {
    result=$(resolve_model "claude-opus-4.5")
    [ "$result" = "claude-opus-4-7" ]
}

# T8: MODEL_TO_ALIAS in v2 shim contains new keys (including 4.7)
@test "v2 shim MODEL_TO_ALIAS contains new aliases" {
    # Check that the v2 shim file contains all new keys
    for key in "claude-opus-4-7" "claude-opus-4.7" "claude-opus-4-5" "claude-opus-4.1" "claude-opus-4-1" "claude-opus-4.0" "claude-opus-4-0"; do
        grep -q "\"$key\"" "$SCRIPT_DIR/model-adapter.sh" || {
            echo "Missing key in v2 shim: $key"
            return 1
        }
    done
}

# T9: opus shorthand resolves to current canonical (cycle-082: 4.7)
@test "opus shorthand resolves to claude-opus-4-7" {
    result=$(resolve_model "opus")
    [ "$result" = "claude-opus-4-7" ]
}

# T10: Unknown model fails with exit 2
@test "unknown model claude-opus-99 fails validation" {
    run "$SCRIPT_DIR/model-adapter.sh.legacy" \
        --model "claude-opus-99" --mode review \
        --input "$PROJECT_ROOT/grimoires/loa/prd.md" \
        --dry-run
    [ "$status" -eq 2 ]
}

# =============================================================================
# Cycle-082 additions: 4.7 canonical + 4.6 backward-compat + four-map invariant
# =============================================================================

# T11: claude-opus-4-7 canonical resolves to itself (self-mapping)
@test "cycle-082: claude-opus-4-7 canonical resolves to claude-opus-4-7" {
    result=$(resolve_model "claude-opus-4-7")
    [ "$result" = "claude-opus-4-7" ]
}

# T12: claude-opus-4.7 (dotted) resolves to canonical
@test "cycle-082: claude-opus-4.7 (dotted) resolves to claude-opus-4-7" {
    result=$(resolve_model "claude-opus-4.7")
    [ "$result" = "claude-opus-4-7" ]
}

# T13: claude-opus-4.6 (dotted) backward-compat resolves to current
@test "cycle-082: claude-opus-4.6 dotted alias resolves to claude-opus-4-7 (bash retarget)" {
    result=$(resolve_model "claude-opus-4.6")
    [ "$result" = "claude-opus-4-7" ]
}

# T14: claude-opus-4-6 (hyphenated canonical) retargets to 4.7 in bash (per PR #207 pattern)
@test "cycle-082: claude-opus-4-6 hyphenated resolves to claude-opus-4-7 in bash layer" {
    result=$(resolve_model "claude-opus-4-6")
    [ "$result" = "claude-opus-4-7" ]
}

# T15: Four-map invariant — 4.7 key present in all four arrays
@test "cycle-082: four-map invariant holds for claude-opus-4-7" {
    run bash -c '
        trap "
            [[ -n \"\${MODEL_PROVIDERS[claude-opus-4-7]:-}\" ]] || exit 10
            [[ -n \"\${MODEL_IDS[claude-opus-4-7]:-}\" ]] || exit 11
            [[ -n \"\${COST_INPUT[claude-opus-4-7]:-}\" ]] || exit 12
            [[ -n \"\${COST_OUTPUT[claude-opus-4-7]:-}\" ]] || exit 13
            exit 0
        " EXIT
        source "$SCRIPT_DIR/model-adapter.sh.legacy" --model opus --mode review 2>/dev/null
    '
    [ "$status" -eq 0 ]
}

# T16: 4.6 registry entry retained as pinnable fallback (YAML layer)
@test "cycle-082: 4.6 registry entry retained in model-config.yaml for pinning" {
    # Verify YAML has both 4.7 (canonical) and 4.6 (pinnable) entries
    run yq -r '.providers.anthropic.models | keys | join(",")' \
        "$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"claude-opus-4-7"* ]]
    [[ "$output" == *"claude-opus-4-6"* ]]
}

# T17: aliases.opus retargeted to 4.7 in defaults
@test "cycle-082: aliases.opus resolves to anthropic:claude-opus-4-7 in YAML defaults" {
    run yq -r '.aliases.opus' "$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = "anthropic:claude-opus-4-7" ]
}
