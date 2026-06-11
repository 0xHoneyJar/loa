#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-114-opus-4-8-registry.bats
#
# Cycle-114 (harness-modernization-opus-4.8) FR-1 — contract pin.
#
# Asserts that Claude Opus 4.8 is registered and resolvable:
#   - the `opus` alias resolves to claude-opus-4-8 (retargeted 4-7 → 4-8)
#   - both the dash (claude-opus-4-8) and dot (claude-opus-4.8) self-maps
#     resolve via cheval (parity with the #877 fix for 4-7)
#   - the generated bash maps and BB config.generated.ts carry 4.8
#     (regeneration parity — guards the "4 maps must stay in sync" hazard)
#
# Resolution is exercised through cheval's real --dry-run path (same oracle
# as cheval-alias-regression.bats), not a hand-rolled map read.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CHEVAL_PY="$PROJECT_ROOT/.claude/adapters/cheval.py"
    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    GENERATED_MAPS="$PROJECT_ROOT/.claude/scripts/generated-model-maps.sh"
    BB_CONFIG="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/config.generated.ts"
}

# Run cheval --dry-run for $model; assert success + anthropic + claude-opus-4-8.
_assert_resolves_to_opus_4_8() {
    local model="$1"
    run env -u ANTHROPIC_API_KEY "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --model "$model" \
        --prompt "cycle-114-pin" \
        --dry-run \
        --json-errors 2>&1
    [ "$status" -eq 0 ] || {
        printf 'FAIL: cheval --dry-run rejected model=%s\n%s\n' "$model" "$output" >&2
        return 1
    }
    [[ "$output" == *"\"resolved_provider\": \"anthropic\""* ]] || {
        printf 'FAIL: model=%s did not resolve to anthropic\n%s\n' "$model" "$output" >&2
        return 1
    }
    [[ "$output" == *"\"resolved_model\": \"claude-opus-4-8\""* ]] || {
        printf 'FAIL: model=%s did not resolve to claude-opus-4-8\n%s\n' "$model" "$output" >&2
        return 1
    }
}

@test "c114-FR1-1: opus alias resolves to claude-opus-4-8" {
    _assert_resolves_to_opus_4_8 "opus"
}

@test "c114-FR1-2: claude-opus-4-8 (dash self-map) resolves" {
    _assert_resolves_to_opus_4_8 "claude-opus-4-8"
}

@test "c114-FR1-3: claude-opus-4.8 (dot self-map) resolves" {
    _assert_resolves_to_opus_4_8 "claude-opus-4.8"
}

@test "c114-FR1-4: generated bash maps carry claude-opus-4-8 across all maps" {
    [ -f "$GENERATED_MAPS" ]
    # provider, id self-map, and cost maps must all carry the entry
    grep -q '\["claude-opus-4-8"\]="anthropic"' "$GENERATED_MAPS"
    grep -q '\["claude-opus-4-8"\]="claude-opus-4-8"' "$GENERATED_MAPS"
    grep -q '\["opus"\]="claude-opus-4-8"' "$GENERATED_MAPS"
    grep -q '\["claude-opus-4.8"\]="claude-opus-4-8"' "$GENERATED_MAPS"
}

@test "c114-FR1-5: BB config.generated.ts carries claude-opus-4-8" {
    [ -f "$BB_CONFIG" ]
    grep -q 'claude-opus-4-8' "$BB_CONFIG"
}

@test "c114-FR1-6: bash adapter maps are not stale vs YAML (drift gate)" {
    run bash "$PROJECT_ROOT/.claude/scripts/gen-adapter-maps.sh" --check
    [ "$status" -eq 0 ]
}
