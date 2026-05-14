#!/usr/bin/env bats
# =============================================================================
# tests/unit/cheval-alias-regression.bats
#
# Cycle-109 sprint-1 follow-up — regression pin for issue #877.
#
# Issue #877: cheval rejected `claude-opus-4-7` (dash form) as an unknown
# alias because the alias map only declared the period form
# `claude-opus-4.7`. Fix landed via cycle-108 PR #867 (commit 065ce153)
# which added BOTH self-maps to `backward_compat_aliases`. This test
# pins the property so any future regression of the alias map fails CI
# rather than surfacing as the same operator-facing error.
#
# Symmetric coverage for the other claude-opus self-maps that the same
# fix landed (4.6 / 4.5 / 4.1 / 4.0 dash + period forms).
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
}

# Run cheval with --dry-run + given model; assert SUCCESS exit + resolved
# provider == "anthropic" + resolved model == "claude-opus-4-7".
_assert_resolves_to_opus_4_7() {
    local model="$1"
    run env -u ANTHROPIC_API_KEY "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --model "$model" \
        --prompt "regression-pin" \
        --dry-run \
        --json-errors 2>&1
    [ "$status" -eq 0 ] || {
        printf 'FAIL: cheval --dry-run rejected model=%s\n%s\n' "$model" "$output" >&2
        return 1
    }
    [[ "$output" == *"\"resolved_provider\": \"anthropic\""* ]] || {
        printf 'FAIL: model=%s did not resolve to anthropic provider\n%s\n' "$model" "$output" >&2
        return 1
    }
    [[ "$output" == *"\"resolved_model\": \"claude-opus-4-7\""* ]] || {
        printf 'FAIL: model=%s did not resolve to claude-opus-4-7\n%s\n' "$model" "$output" >&2
        return 1
    }
}

# =============================================================================
# A1: dash form — the primary regression of issue #877
# =============================================================================

@test "A1: claude-opus-4-7 (dash form) resolves — pin against #877" {
    _assert_resolves_to_opus_4_7 "claude-opus-4-7"
}

# =============================================================================
# A2: period form — must still resolve (pre-existing behavior)
# =============================================================================

@test "A2: claude-opus-4.7 (period form) resolves" {
    _assert_resolves_to_opus_4_7 "claude-opus-4.7"
}

# =============================================================================
# A3-A6: prior generations both forms — cycle-108 PR #867 symmetric coverage
# =============================================================================

@test "A3: claude-opus-4-6 (dash form) resolves to claude-opus-4-7" {
    _assert_resolves_to_opus_4_7 "claude-opus-4-6"
}

@test "A4: claude-opus-4.6 (period form) resolves to claude-opus-4-7" {
    _assert_resolves_to_opus_4_7 "claude-opus-4.6"
}

@test "A5: claude-opus-4-5 (dash form) resolves to claude-opus-4-7" {
    _assert_resolves_to_opus_4_7 "claude-opus-4-5"
}

@test "A6: claude-opus-4.5 (period form) resolves to claude-opus-4-7" {
    _assert_resolves_to_opus_4_7 "claude-opus-4.5"
}
