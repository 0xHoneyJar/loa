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

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    [[ -n "${HELPER_FILE:-}" && -f "$HELPER_FILE" ]] && rm -f "$HELPER_FILE"
    [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
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

@test "F9a: provider with shell metas rejected (output AND side-effect safe)" {
    # BB iter-1 F13 (medium): output-safety alone is insufficient. A naive
    # implementation could `eval "$provider"` BEFORE returning the default,
    # and this test would still pass on the output but the injection would
    # have already executed. Add a sentinel-file check to assert the
    # injected command did NOT execute as a side effect.
    local sentinel="${WORK_DIR:-/tmp}/f9a-sentinel-$$"
    : > "$sentinel"
    # The injection attempt tries to `touch /tmp/PWNED-f9a` via command
    # substitution + path-traversal. If the helper executes it (eval/$()
    # path), /tmp/PWNED-f9a appears.
    rm -f /tmp/PWNED-f9a
    result="$(_lookup_max_output_tokens 'openai;rm -f '"$sentinel"' #' gpt-5.5-pro 8000)"
    [ "$result" = "8000" ]                           # output-safe
    [ -f "$sentinel" ]                                # side-effect-safe (sentinel survives)
    rm -f "$sentinel"
}

@test "F9b: provider with quote rejected" {
    result="$(_lookup_max_output_tokens 'openai"' gpt-5.5-pro 8000)"
    [ "$result" = "8000" ]
}

@test "F9c: model_id with path-traversal (..) rejected" {
    result="$(_lookup_max_output_tokens openai '../etc/passwd' 8000)"
    [ "$result" = "8000" ]
}

@test "F9d: model_id with shell metas rejected (output AND side-effect safe)" {
    # F13 strengthening: same side-effect sentinel pattern as F9a.
    local sentinel="${WORK_DIR:-/tmp}/f9d-sentinel-$$"
    : > "$sentinel"
    result="$(_lookup_max_output_tokens openai 'gpt-5.5-pro$(rm -f '"$sentinel"' )' 8000)"
    [ "$result" = "8000" ]
    [ -f "$sentinel" ]
    rm -f "$sentinel"
}

@test "F9e: empty inputs return default" {
    result="$(_lookup_max_output_tokens '' '' 8000)"
    [ "$result" = "8000" ]
}

# -----------------------------------------------------------------------------
# F10 — Adapter call sites use the helper (contract pin)
# -----------------------------------------------------------------------------

# BB iter-1 F2 (medium) + FIND-006 (medium): the previous F10 tests
# pinned the EXACT prior-bug literal shape ("max_output_tokens":8000),
# which would pass trivially after JSON reformatting or literal value
# changes. The new tests assert the underlying INVARIANT — that the
# token-count value in each provider's payload is a shell variable
# expansion ($var or ${var}), not a literal integer. Per Netflix's
# chaos engineering principle: test the invariant, not the incident.
#
# We extract each provider's call_*_api function body via awk, then
# regex-search for the payload pattern. Scoping to the function body
# eliminates the FIND-006 hazard of grepping the full file (which
# matches comments + the helper definition).

# Extract function body by name, between `funcname() {` and the
# matching `^}`. Returns the body on stdout.
_extract_function_body() {
    local funcname="$1"
    awk -v fn="$funcname" '
        $0 ~ "^"fn"\\(\\) \\{" { in_fn=1; depth=1; next }
        in_fn { print }
        in_fn && /^\}/ { in_fn=0 }
    ' "$LEGACY_ADAPTER"
}

@test "F10a: call_openai_api payload max_output_tokens is a shell variable, not a literal" {
    body="$(_extract_function_body call_openai_api)"
    # Invariant: the responses-API payload sets max_output_tokens to a
    # %s/%d formatter that consumes a shell variable, NOT a literal int.
    # Match either `"max_output_tokens":${var}` or `"max_output_tokens":%s` (printf).
    echo "$body" | grep -qE '"max_output_tokens":(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|%[ds])'
    # Defense-in-depth: still no bare 8000-literal residue
    ! echo "$body" | grep -qE '"max_output_tokens":8000\b'
}

@test "F10b: call_google_api generationConfig.maxOutputTokens is a shell variable" {
    body="$(_extract_function_body call_google_api)"
    echo "$body" | grep -qE '"maxOutputTokens":[[:space:]]*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?'
    ! echo "$body" | grep -qE '"maxOutputTokens":[[:space:]]*4096\b'
}

@test "F10c: call_anthropic_api max_tokens is a shell variable" {
    body="$(_extract_function_body call_anthropic_api)"
    echo "$body" | grep -qE '"max_tokens":[[:space:]]*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?'
    ! echo "$body" | grep -qE '"max_tokens":[[:space:]]*4096\b'
}

@test "F10d: each provider function body invokes _lookup_max_output_tokens (scoped, not full-file count)" {
    # FIND-006: scope to per-function body so the test cannot pass via
    # comments or the helper definition.
    for fn in call_openai_api call_google_api call_anthropic_api; do
        body="$(_extract_function_body "$fn")"
        echo "$body" | grep -qE '_lookup_max_output_tokens\b' || {
            printf 'FAIL: %s does not invoke _lookup_max_output_tokens\n' "$fn" >&2
            return 1
        }
    done
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
