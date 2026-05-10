#!/usr/bin/env bats
# =============================================================================
# tests/integration/cheval-input-gate.bats
#
# cycle-102 Sprint 1F — per-model input-size gate (KF-002 layer 3 / Loa #774).
#
# The gate refuses cheval invocations whose estimated input token count
# exceeds the per-model `max_input_tokens` threshold from
# .claude/defaults/model-config.yaml. It fires BEFORE the adapter is
# constructed — no API key or network needed for these tests; an
# above-threshold prompt raises CONTEXT_TOO_LARGE (exit 7) immediately.
#
# Threshold field semantics:
#   - max_input_tokens is SEPARATE from context_window — context_window
#     is the model's advertised capacity; max_input_tokens is the
#     empirically-observed safe threshold for cheval's HTTP path.
#   - Absent from per-model config = no gate fires.
#   - --max-input-tokens N (N > 0) overrides per call.
#   - --max-input-tokens 0 explicitly disables for the call.
#   - LOA_CHEVAL_DISABLE_INPUT_GATE=1 globally bypasses the gate.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CHEVAL_PY="$PROJECT_ROOT/.claude/adapters/cheval.py"

    [[ -f "$CHEVAL_PY" ]] || {
        printf 'FATAL: cheval.py not found at %s\n' "$CHEVAL_PY" >&2
        return 1
    }

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    # Each test gets a clean tmp dir for prompt fixtures.
    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cheval-input-gate.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# G1: gate fires at low cli-override threshold
# -----------------------------------------------------------------------------

@test "G1: gate refuses with exit 7 when --max-input-tokens override breached" {
    # 200-char prompt is ~57 tokens via the 3.5-chars-per-token heuristic;
    # threshold of 5 forces a gate hit regardless of tokenizer choice.
    local prompt
    prompt="$(printf 'x%.0s' {1..200})"

    run "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --prompt "$prompt" \
        --max-input-tokens 5 \
        2>&1
    [ "$status" -eq 7 ]
    [[ "$output" == *"[input-gate]"* ]]
    [[ "$output" == *"refused"* ]]
    [[ "$output" == *"KF-002"* ]]
}

# -----------------------------------------------------------------------------
# G2: --max-input-tokens 0 explicitly disables the gate for the call
# -----------------------------------------------------------------------------

@test "G2: --max-input-tokens 0 bypasses the gate" {
    # Without API keys cheval will fail downstream with a non-7 exit
    # (auth/key/network class). What we assert here is that the gate
    # warning is NEVER emitted to stderr — the gate did not fire.
    local prompt
    prompt="$(printf 'x%.0s' {1..200})"

    OPENAI_API_KEY="" ANTHROPIC_API_KEY="" GOOGLE_API_KEY="" \
    run "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --prompt "$prompt" \
        --max-input-tokens 0 \
        2>&1
    # The gate must NOT have fired
    [[ "$output" != *"[input-gate]"* ]]
    # Exit code is non-zero (some downstream failure) but specifically
    # not the gate's CONTEXT_TOO_LARGE exit code.
    [ "$status" -ne 7 ]
}

# -----------------------------------------------------------------------------
# G3: LOA_CHEVAL_DISABLE_INPUT_GATE=1 globally bypasses the gate
# -----------------------------------------------------------------------------

@test "G3: LOA_CHEVAL_DISABLE_INPUT_GATE=1 bypasses the gate" {
    local prompt
    prompt="$(printf 'x%.0s' {1..200})"

    LOA_CHEVAL_DISABLE_INPUT_GATE=1 \
    OPENAI_API_KEY="" ANTHROPIC_API_KEY="" GOOGLE_API_KEY="" \
    run "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --prompt "$prompt" \
        --max-input-tokens 5 \
        2>&1
    # Even though --max-input-tokens 5 would normally trigger, the env
    # opt-out short-circuits the entire gate block.
    [[ "$output" != *"[input-gate]"* ]]
    [ "$status" -ne 7 ]
}

# -----------------------------------------------------------------------------
# G4: small prompt under default threshold does not fire the gate
# -----------------------------------------------------------------------------

@test "G4: small prompt under default config threshold does not fire" {
    # `reviewing-code` resolves to openai:gpt-5.5 which has
    # max_input_tokens=24000. A 100-byte prompt is ~28 tokens and well below.
    OPENAI_API_KEY="" ANTHROPIC_API_KEY="" GOOGLE_API_KEY="" \
    run "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --prompt "tiny prompt" \
        2>&1
    # Gate should not have fired; downstream failure is acceptable.
    [[ "$output" != *"[input-gate]"* ]]
}

# -----------------------------------------------------------------------------
# G5: helper function direct unit test — config-default lookup
# -----------------------------------------------------------------------------

@test "G5: _lookup_max_input_tokens reads per-model value from config" {
    run "$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from cheval import _lookup_max_input_tokens

cfg = {
    'providers': {
        'openai': {
            'models': {
                'gpt-5.5-pro': {'max_input_tokens': 24000},
                'gpt-5.2': {'context_window': 128000},
            }
        }
    }
}
assert _lookup_max_input_tokens('openai', 'gpt-5.5-pro', cfg) == 24000
assert _lookup_max_input_tokens('openai', 'gpt-5.2', cfg) is None
assert _lookup_max_input_tokens('openai', 'nonexistent', cfg) is None
assert _lookup_max_input_tokens('nonexistent-provider', 'x', cfg) is None
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# -----------------------------------------------------------------------------
# G6: helper cli_override semantics — 0 disables, N>0 wins, None falls through
# -----------------------------------------------------------------------------

@test "G6: _lookup_max_input_tokens cli_override semantics" {
    run "$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from cheval import _lookup_max_input_tokens

cfg = {'providers': {'p': {'models': {'m': {'max_input_tokens': 1000}}}}}
# cli_override=None → use config (1000)
assert _lookup_max_input_tokens('p', 'm', cfg, cli_override=None) == 1000
# cli_override=0 → explicit disable
assert _lookup_max_input_tokens('p', 'm', cfg, cli_override=0) is None
# cli_override=-1 → also disable (defensive)
assert _lookup_max_input_tokens('p', 'm', cfg, cli_override=-1) is None
# cli_override=500 → override config
assert _lookup_max_input_tokens('p', 'm', cfg, cli_override=500) == 500
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# -----------------------------------------------------------------------------
# G7: ships-with thresholds match observed-failure documentation
# -----------------------------------------------------------------------------

@test "G7: model-config.yaml ships expected per-model thresholds" {
    run "$PYTHON_BIN" -c "
import sys, yaml
with open('$PROJECT_ROOT/.claude/defaults/model-config.yaml') as f:
    cfg = yaml.safe_load(f)

# KF-002 layer 3 thresholds: gpt-5.5-pro fails at 27K (gate at 24K),
# claude-opus-4-7 fails at >40K (gate at 36K). gemini has no observed
# failures so no gate ships.
openai_models = cfg['providers']['openai']['models']
anthropic_models = cfg['providers']['anthropic']['models']
google_models = cfg['providers']['google']['models']

assert openai_models['gpt-5.5-pro'].get('max_input_tokens') == 24000, openai_models['gpt-5.5-pro'].get('max_input_tokens')
assert openai_models['gpt-5.5'].get('max_input_tokens') == 24000
assert anthropic_models['claude-opus-4-7'].get('max_input_tokens') == 36000
assert anthropic_models['claude-opus-4-6'].get('max_input_tokens') == 36000
# Gemini intentionally has no gate
assert 'max_input_tokens' not in google_models.get('gemini-3.1-pro-preview', {})
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# -----------------------------------------------------------------------------
# G8: gate sets MODELINV operator_visible_warn=true on hit (audit signal)
# -----------------------------------------------------------------------------

@test "G8: gate emits operator-visible stderr line on hit" {
    local prompt
    prompt="$(printf 'x%.0s' {1..400})"

    run "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --prompt "$prompt" \
        --max-input-tokens 10 \
        2>&1
    [ "$status" -eq 7 ]
    # The operator-visible header is the visible signal; the MODELINV
    # envelope's operator_visible_warn=true is verified via separate
    # audit tests at .claude/adapters/tests/test_modelinv.py (carry).
    [[ "$output" == *"[input-gate]"* ]]
    [[ "$output" == *"refused"* ]]
    [[ "$output" == *"--max-input-tokens 0"* ]]
    [[ "$output" == *"LOA_CHEVAL_DISABLE_INPUT_GATE"* ]]
}
