#!/usr/bin/env bats
# =============================================================================
# Cross-language equivalence test for parse_provider_model_id.
#
# Cycle-096 Sprint 1 Task 1.1 (closes Flatline v1.1 SKP-006).
# Runs the same input set through both the bash helper and the Python helper
# and asserts equivalent outputs. This test is the contract enforcement that
# prevents the two parsers from drifting over time.
#
# SDD reference: §5.4 Centralized Parser Contract — test fixture table.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    LIB="$PROJECT_ROOT/.claude/scripts/lib-provider-parse.sh"
    PYTHON_BIN="${PYTHON_BIN:-python3}"
    unset _LIB_PROVIDER_PARSE_LOADED
    source "$LIB"
}

# Helper: run Python parser, set py_exit, py_provider, py_model_id.
# Output protocol: "OK<TAB>provider<TAB>model_id" or "ERR<TAB>InvalidInputError" .
py_parse() {
    local input="$1"
    local out
    out=$("$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.types import parse_provider_model_id, InvalidInputError
try:
    p, m = parse_provider_model_id(sys.argv[1] if len(sys.argv) > 1 else '')
    print('OK\t' + p + '\t' + m)
except InvalidInputError as e:
    print('ERR\t' + type(e).__name__ + '\t' + str(e))
" "$input" 2>&1)
    py_exit=0
    if [[ "$out" == ERR* ]]; then
        py_exit=2
    fi
    py_provider="$(awk -F'\t' 'NR==1 {print $2}' <<< "$out")"
    py_model_id="$(awk -F'\t' 'NR==1 {print $3}' <<< "$out")"
}

# Helper: run bash parser, set bash_exit, bash_provider, bash_model_id.
bash_parse() {
    local input="$1"
    bash_provider=""
    bash_model_id=""
    if parse_provider_model_id "$input" bash_provider bash_model_id 2>/dev/null; then
        bash_exit=0
    else
        bash_exit=2
    fi
}

# Helper: assert bash and Python agree on a single input.
assert_equivalent() {
    local input="$1"
    local expected_status="$2"  # 0 for success, 2 for error
    local expected_provider="$3"
    local expected_model_id="$4"

    bash_parse "$input"
    py_parse "$input"

    [ "$bash_exit" = "$expected_status" ] || \
        { echo "bash exit mismatch for input '$input': got $bash_exit, expected $expected_status"; return 1; }
    [ "$py_exit" = "$expected_status" ] || \
        { echo "py exit mismatch for input '$input': got $py_exit, expected $expected_status"; return 1; }

    if [ "$expected_status" = "0" ]; then
        [ "$bash_provider" = "$expected_provider" ] || \
            { echo "bash provider mismatch for '$input': got '$bash_provider', expected '$expected_provider'"; return 1; }
        [ "$bash_model_id" = "$expected_model_id" ] || \
            { echo "bash model_id mismatch for '$input': got '$bash_model_id', expected '$expected_model_id'"; return 1; }
        [ "$py_provider" = "$expected_provider" ] || \
            { echo "py provider mismatch for '$input': got '$py_provider', expected '$expected_provider'"; return 1; }
        [ "$py_model_id" = "$expected_model_id" ] || \
            { echo "py model_id mismatch for '$input': got '$py_model_id', expected '$expected_model_id'"; return 1; }
    fi

    return 0
}

# --- Property tests: each row of SDD §5.4 fixture table ---

@test "row 1: anthropic:claude-opus-4-7 → success" {
    assert_equivalent "anthropic:claude-opus-4-7" 0 "anthropic" "claude-opus-4-7"
}

@test "row 2: bedrock:us.anthropic.claude-opus-4-7 → success" {
    assert_equivalent "bedrock:us.anthropic.claude-opus-4-7" 0 "bedrock" "us.anthropic.claude-opus-4-7"
}

@test "row 3: openai:gpt-5.5-pro → success" {
    assert_equivalent "openai:gpt-5.5-pro" 0 "openai" "gpt-5.5-pro"
}

@test "row 4: google:gemini-3.1-pro-preview → success" {
    assert_equivalent "google:gemini-3.1-pro-preview" 0 "google" "gemini-3.1-pro-preview"
}

@test "row 5: empty input → error" {
    assert_equivalent "" 2 "" ""
}

@test "row 6: ':claude-opus-4-7' → error (empty provider)" {
    assert_equivalent ":claude-opus-4-7" 2 "" ""
}

@test "row 7: 'anthropic:' → error (empty model_id)" {
    assert_equivalent "anthropic:" 2 "" ""
}

@test "row 8: 'no-colon-at-all' → error (missing colon)" {
    assert_equivalent "no-colon-at-all" 2 "" ""
}

@test "row 9: 'provider:multi:colon:value' → success (split on FIRST colon)" {
    assert_equivalent "provider:multi:colon:value" 0 "provider" "multi:colon:value"
}

# --- Bedrock Day-1 inference profile IDs (locked from Sprint 0 G-S0-2 probes) ---

@test "Bedrock Day-1: us.anthropic.claude-opus-4-7" {
    assert_equivalent "bedrock:us.anthropic.claude-opus-4-7" 0 "bedrock" "us.anthropic.claude-opus-4-7"
}

@test "Bedrock Day-1: us.anthropic.claude-sonnet-4-6" {
    assert_equivalent "bedrock:us.anthropic.claude-sonnet-4-6" 0 "bedrock" "us.anthropic.claude-sonnet-4-6"
}

@test "Bedrock Day-1: us.anthropic.claude-haiku-4-5-20251001-v1:0 (colon-bearing suffix)" {
    assert_equivalent "bedrock:us.anthropic.claude-haiku-4-5-20251001-v1:0" 0 "bedrock" "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

@test "Bedrock Day-1: global.anthropic.claude-opus-4-7 (alternative namespace)" {
    assert_equivalent "bedrock:global.anthropic.claude-opus-4-7" 0 "bedrock" "global.anthropic.claude-opus-4-7"
}
