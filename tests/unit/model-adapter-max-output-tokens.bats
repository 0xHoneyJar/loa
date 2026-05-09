#!/usr/bin/env bats
# =============================================================================
# tests/unit/model-adapter-max-output-tokens.bats
#
# cycle-102 Sprint 1 (T1.9) — Per-model max_output_tokens lookup contract.
# Closes A1 + A2 from sprint-bug-143 (vision-019).
#
# Pinning the helper `_lookup_max_output_tokens` extracted from
# .claude/scripts/model-adapter.sh.legacy and the per-model values
# configured in .claude/defaults/model-config.yaml.
#
# Test taxonomy:
#   F0      Helper function exists in legacy adapter
#   F1-F4   Per-provider lookup returns configured values
#   F5-F8   Fallback-to-default behavior
#   F9      Path-traversal / invalid input rejected (defense-in-depth)
#   F10     Adapter call sites use the helper (grep contract pin)
#   Y1-Y3   model-config.yaml has expected max_output_tokens entries
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LEGACY_ADAPTER="$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy"
    MODEL_CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"

    [[ -f "$LEGACY_ADAPTER" ]] || { printf 'FATAL: missing %s\n' "$LEGACY_ADAPTER" >&2; return 1; }
    [[ -f "$MODEL_CONFIG" ]] || { printf 'FATAL: missing %s\n' "$MODEL_CONFIG" >&2; return 1; }
    command -v yq >/dev/null 2>&1 || skip "yq not installed (legacy lookup helper requires it)"

    # Source ONLY the helper function (sourcing the whole adapter exits via
    # validate_model_registry / loads API keys). Extract the helper with a
    # narrow awk slice between its sentinel comments.
    HELPER_FILE="$(mktemp)"
    awk '/^_lookup_max_output_tokens\(\)/,/^}/' "$LEGACY_ADAPTER" > "$HELPER_FILE"

    # The helper depends on $SCRIPT_DIR; export it to point at the real adapter dir
    # so the helper finds .claude/defaults/model-config.yaml.
    export SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"

    # Source it. The function is now callable.
    # shellcheck disable=SC1090
    source "$HELPER_FILE"
}

teardown() {
    [[ -n "${HELPER_FILE:-}" && -f "$HELPER_FILE" ]] && rm -f "$HELPER_FILE"
}

# -----------------------------------------------------------------------------
# F0 — Helper exists
# -----------------------------------------------------------------------------

@test "F0: _lookup_max_output_tokens function is defined in legacy adapter" {
    grep -q "^_lookup_max_output_tokens()" "$LEGACY_ADAPTER"
}

# -----------------------------------------------------------------------------
# F1-F4 — Per-provider lookup
# -----------------------------------------------------------------------------

@test "F1: openai gpt-5.5-pro -> 32000 (configured reasoning-class)" {
    result="$(_lookup_max_output_tokens openai gpt-5.5-pro 8000)"
    [ "$result" = "32000" ]
}

@test "F2: google gemini-3.1-pro-preview -> 32000 (configured thinking_traces)" {
    result="$(_lookup_max_output_tokens google gemini-3.1-pro-preview 4096)"
    [ "$result" = "32000" ]
}

@test "F3: anthropic claude-opus-4-7 -> 32000 (configured opus-class)" {
    result="$(_lookup_max_output_tokens anthropic claude-opus-4-7 4096)"
    [ "$result" = "32000" ]
}

@test "F4: anthropic claude-sonnet-4-6 -> 16000 (configured sonnet-class)" {
    result="$(_lookup_max_output_tokens anthropic claude-sonnet-4-6 4096)"
    [ "$result" = "16000" ]
}

# -----------------------------------------------------------------------------
# F5-F8 — Fallback behavior
# -----------------------------------------------------------------------------

@test "F5: unknown model -> falls back to default" {
    result="$(_lookup_max_output_tokens openai some-future-model 8000)"
    [ "$result" = "8000" ]
}

@test "F6: unknown provider -> falls back to default" {
    result="$(_lookup_max_output_tokens xai some-model 4096)"
    [ "$result" = "4096" ]
}

@test "F7: model with no max_output_tokens field -> falls back to default (e.g., haiku)" {
    # claude-haiku-4-5-20251001 doesn't have max_output_tokens configured per
    # the cycle-102 Sprint 1 T1.9 scope (intentionally — flash/haiku tier
    # keeps the original 4096 cap to preserve cost envelope).
    result="$(_lookup_max_output_tokens anthropic claude-haiku-4-5-20251001 4096)"
    [ "$result" = "4096" ]
}

@test "F8: gemini flash-tier model (no max_output_tokens configured) -> default" {
    result="$(_lookup_max_output_tokens google gemini-2.5-flash 4096)"
    [ "$result" = "4096" ]
}

# -----------------------------------------------------------------------------
# F9 — Defense-in-depth: invalid input rejected, returns default
# -----------------------------------------------------------------------------

@test "F9a: provider with shell metas rejected" {
    # ; rm -rf attempt: the helper validates provider against ^[a-z][a-z0-9_]*$
    result="$(_lookup_max_output_tokens 'openai;rm -rf /' gpt-5.5-pro 8000)"
    [ "$result" = "8000" ]
}

@test "F9b: provider with quote rejected" {
    result="$(_lookup_max_output_tokens 'openai"' gpt-5.5-pro 8000)"
    [ "$result" = "8000" ]
}

@test "F9c: model_id with path-traversal (..) rejected" {
    result="$(_lookup_max_output_tokens openai '../etc/passwd' 8000)"
    [ "$result" = "8000" ]
}

@test "F9d: model_id with shell metas rejected" {
    result="$(_lookup_max_output_tokens openai 'gpt-5.5-pro$(echo pwn)' 8000)"
    [ "$result" = "8000" ]
}

@test "F9e: empty inputs return default" {
    result="$(_lookup_max_output_tokens '' '' 8000)"
    [ "$result" = "8000" ]
}

# -----------------------------------------------------------------------------
# F10 — Adapter call sites use the helper (contract pin)
# -----------------------------------------------------------------------------

@test "F10a: call_openai_api uses _lookup_max_output_tokens (no hardcoded 8000 literal in payload)" {
    # The new payload formatter must reference the helper output via the
    # max_output_tokens variable — NOT a literal 8000.
    # Before the fix: `"max_output_tokens":8000` was hardcoded.
    # After: payload uses `${max_output_tokens}` substitution.
    ! grep -E '"max_output_tokens":8000' "$LEGACY_ADAPTER"
}

@test "F10b: call_google_api uses _lookup_max_output_tokens (no hardcoded 4096)" {
    # Look for the OLD hardcoded literal `"maxOutputTokens": 4096,` that
    # was replaced. The new payload uses `${max_output_tokens}` interpolation.
    ! grep -E '"maxOutputTokens": 4096,' "$LEGACY_ADAPTER"
}

@test "F10c: call_anthropic_api uses _lookup_max_output_tokens (no hardcoded 4096)" {
    # Old: `"max_tokens": 4096,` literal → new: `"max_tokens": ${max_tokens},`.
    ! grep -E '"max_tokens": 4096,' "$LEGACY_ADAPTER"
}

@test "F10d: at least 3 call sites invoke _lookup_max_output_tokens (one per provider)" {
    n="$(grep -c '_lookup_max_output_tokens' "$LEGACY_ADAPTER")"
    # 1 definition + 3 call sites = 4
    [ "$n" -ge 4 ]
}

# -----------------------------------------------------------------------------
# Y1-Y3 — model-config.yaml entries
# -----------------------------------------------------------------------------

@test "Y1: gpt-5.5-pro has max_output_tokens: 32000 in model-config.yaml" {
    v="$(yq -r '.providers["openai"].models["gpt-5.5-pro"].max_output_tokens' "$MODEL_CONFIG")"
    [ "$v" = "32000" ]
}

@test "Y2: gemini-3.1-pro-preview has max_output_tokens: 32000 in model-config.yaml" {
    v="$(yq -r '.providers["google"].models["gemini-3.1-pro-preview"].max_output_tokens' "$MODEL_CONFIG")"
    [ "$v" = "32000" ]
}

@test "Y3: claude-opus-4-7 has max_output_tokens: 32000 in model-config.yaml" {
    v="$(yq -r '.providers["anthropic"].models["claude-opus-4-7"].max_output_tokens' "$MODEL_CONFIG")"
    [ "$v" = "32000" ]
}
