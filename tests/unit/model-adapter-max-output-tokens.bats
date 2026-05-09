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
    # validate_model_registry / loads API keys). Use the depth-tracking
    # extractor (defined below — see _extract_function_body_with_signature)
    # so a column-0 `}` inside a heredoc/comment doesn't truncate.
    # BB iter-2 F10 (med) + FIND-008 (low): the prior awk slice
    # `/^_lookup_max_output_tokens\(\)/,/^}/` matched the FIRST column-0
    # `}` after the function start — fragile to nested blocks, heredocs,
    # or column-0 `}` in comments. Now we use a brace-depth counter.
    HELPER_FILE="$(mktemp)"
    _extract_function_body_with_signature _lookup_max_output_tokens "$LEGACY_ADAPTER" > "$HELPER_FILE"

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

# Extract function body using a brace-depth counter so nested `{...}`
# blocks, heredocs, or column-0 `}` in comments don't truncate the
# slice. BB iter-2 F10/FIND-008 closure: the prior implementation
# initialized `depth=1` but never updated it; the slice ended at the
# first `^}` regardless of nesting. The new counter increments on
# every `{` and decrements on every `}` (in code, not heredoc bodies),
# closing the function only when depth returns to 0.
#
# `_extract_function_body` returns the body WITHOUT the signature line
# (used by F10a-c which inspect just the inside).
# `_extract_function_body_with_signature` returns the FULL definition
# including the `funcname() {` and trailing `}` lines (used by setup()
# to source the helper).
_extract_function_body_with_signature() {
    local funcname="$1"
    local file="${2:-$LEGACY_ADAPTER}"
    awk -v fn="$funcname" '
        BEGIN { in_fn=0; depth=0 }
        # Function start: matches `funcname() {` at column 0.
        !in_fn && $0 ~ "^"fn"\\(\\) *\\{" {
            in_fn=1; depth=1; print; next
        }
        in_fn {
            print
            # Count braces in code lines. We do NOT attempt full bash
            # heredoc parsing here — single-quoted heredocs (`<<'EOF'`)
            # don'"'"'t expand variables, but their bodies can still
            # contain `{` and `}`. The trade-off: we accept that
            # heredoc-heavy functions will mis-count and require the
            # caller to keep the function body free of column-0 `}`
            # in heredoc bodies. For the legacy-adapter helpers we
            # ship, this holds.
            n_open = gsub(/\{/, "&")
            n_close = gsub(/\}/, "&")
            depth += n_open - n_close
            if (depth <= 0) { in_fn=0; exit }
        }
    ' "$file"
}

_extract_function_body() {
    local funcname="$1"
    _extract_function_body_with_signature "$funcname" "$LEGACY_ADAPTER" \
        | sed '1d;$d'   # drop signature + closing brace lines
}

# BB iter-3 FIND-002 / F8 (med): the previous F10 tests checked for "any
# shell variable" in the payload AND "_lookup_max_output_tokens called
# somewhere in the function" — but did NOT bind the two. A buggy
# implementation could call the helper into one variable and emit a
# different (typo'd) variable into the payload, and both assertions
# would still pass. The new helper extracts BOTH names and asserts
# they match.

# Extract the variable name on the LHS of `<var>=$(_lookup_max_output_tokens ...)`
# from the function body, returning the first match (functions in this
# adapter have one helper call per provider).
_extract_helper_lhs_var() {
    local body="$1"
    echo "$body" \
        | grep -oE '[A-Za-z_][A-Za-z0-9_]*=\$\(_lookup_max_output_tokens\b' \
        | head -1 \
        | sed -E 's/=.*$//'
}

# Extract the variable referenced in a JSON token-count payload field.
# `field` is the JSON key name (max_output_tokens / maxOutputTokens / max_tokens).
_extract_payload_var() {
    local body="$1" field="$2"
    # Match: "<field>":[whitespace]?(${var}|$var|%s)
    # Returns the variable name (or "%s" when printf-formatter is used).
    echo "$body" \
        | grep -oE '"'"$field"'":[[:space:]]*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?' \
        | head -1 \
        | sed -E 's/.*\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/\1/'
}

# Assert: helper-LHS-var == payload-emit-var. Both must be present and equal.
_assert_var_binding() {
    local fnname="$1" json_field="$2"
    local body lhs payload_var
    body="$(_extract_function_body "$fnname")"
    lhs="$(_extract_helper_lhs_var "$body")"
    [[ -n "$lhs" ]] || {
        printf 'FAIL: %s does not assign _lookup_max_output_tokens output to a variable\n' "$fnname" >&2
        return 1
    }
    # printf-style: payload uses %s, then printf args must reference $lhs
    if echo "$body" | grep -qE '"'"$json_field"'":%[ds]'; then
        echo "$body" | grep -qE '\$'"$lhs"'\b' || {
            printf 'FAIL: %s payload uses printf %%s/%%d for "%s" but %%s arg does not reference $%s\n' \
                "$fnname" "$json_field" "$lhs" >&2
            return 1
        }
        return 0
    fi
    # Direct-interpolation style: payload variable name must match LHS.
    payload_var="$(_extract_payload_var "$body" "$json_field")"
    [[ -n "$payload_var" ]] || {
        printf 'FAIL: %s does not interpolate a variable into "%s" payload field\n' "$fnname" "$json_field" >&2
        return 1
    }
    [[ "$payload_var" == "$lhs" ]] || {
        printf 'FAIL: %s helper-LHS=%s does NOT match payload-emit=$%s — variable typo / drift?\n' \
            "$fnname" "$lhs" "$payload_var" >&2
        return 1
    }
}

@test "F10a: call_openai_api binds _lookup_max_output_tokens output to max_output_tokens payload field (FIND-002)" {
    _assert_var_binding call_openai_api max_output_tokens
    body="$(_extract_function_body call_openai_api)"
    ! echo "$body" | grep -qE '"max_output_tokens":8000\b'
}

@test "F10b: call_google_api binds _lookup_max_output_tokens output to maxOutputTokens payload field (FIND-002)" {
    _assert_var_binding call_google_api maxOutputTokens
    body="$(_extract_function_body call_google_api)"
    ! echo "$body" | grep -qE '"maxOutputTokens":[[:space:]]*4096\b'
}

@test "F10c: call_anthropic_api binds _lookup_max_output_tokens output to max_tokens payload field (FIND-002)" {
    _assert_var_binding call_anthropic_api max_tokens
    body="$(_extract_function_body call_anthropic_api)"
    ! echo "$body" | grep -qE '"max_tokens":[[:space:]]*4096\b'
}

@test "F10d: each provider function body invokes _lookup_max_output_tokens (scoped to function body)" {
    # iter-1 FIND-006 closure preserved: scope to per-function body so the
    # count cannot pass via comments or the helper definition.
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
