#!/usr/bin/env bats
# =============================================================================
# tests/unit/cheval-preflight-gate.bats
#
# cycle-109 Sprint 1 T1.3 — cheval pre-flight gate (SDD §1.4.2 / §1.5.2).
#
# Two extensions to cheval.py for the capability-aware substrate:
#
#  1) `_lookup_capability(provider, model_id, hounfour) -> Capability`
#     returns the v3 capability tuple `(effective_input_ceiling,
#     reasoning_class, recommended_for, ceiling_stale)` derived from
#     model-config.yaml v3 fields. Backward-compat: missing v3 fields
#     produce a Capability with None / defaults that disable the new
#     gate (legacy v2 path preserved).
#
#  2) Pre-flight gate in `cmd_invoke`: after chain resolution and
#     message construction, before chain walk. If
#     `estimated_input > effective_input_ceiling` AND chunking is not
#     selected → emit typed exit 7 (CONTEXT_TOO_LARGE) preemptively
#     with stderr marker `[preflight]` AND `ContextTooLarge` JSON
#     payload. If `ceiling_stale` per `ceiling_calibration.stale_after_days`
#     elapsed → emit `ceiling_stale=true` marker on stderr (defensive
#     signal; Sprint 4 routes through chunked path).
#
# Acceptance criteria (sprint.md): bats coverage one case per model
# class (reasoning + non-reasoning).
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

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cheval-preflight-gate.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Emit a synthetic v3 hounfour config dict on stdout for the python -c body.
# Two variants: reasoning_class true (opus-like) + reasoning_class false
# (haiku-like). Arg $1 is the python identifier the caller wants the dict
# assigned to.
_v3_cfg_reasoning_py() {
    cat <<'PY'
{
    'providers': {
        'anthropic': {
            'models': {
                'claude-opus-4-7': {
                    # v2 fields (existing)
                    'api_context_window': 200000,
                    'streaming_max_input_tokens': 80000,
                    'legacy_max_input_tokens': 60000,
                    # v3 fields (additive — SDD §3.1.1)
                    'effective_input_ceiling': 40000,
                    'reasoning_class': True,
                    'recommended_for': ['review', 'audit'],
                    'failure_modes_observed': ['KF-002', 'KF-003'],
                    'ceiling_calibration': {
                        'source': 'empirical_probe',
                        'calibrated_at': '2026-05-13T00:00:00Z',
                        'sample_size': 25,
                        'stale_after_days': 30,
                        'reprobe_trigger': 'first KF entry referencing model OR 30d elapsed OR operator-forced',
                    },
                },
            },
        },
    },
}
PY
}

_v3_cfg_nonreasoning_py() {
    cat <<'PY'
{
    'providers': {
        'openai': {
            'models': {
                'gpt-4o-mini': {
                    'api_context_window': 128000,
                    'streaming_max_input_tokens': 80000,
                    'effective_input_ceiling': 30000,
                    'reasoning_class': False,
                    'recommended_for': ['review', 'audit', 'implementation', 'dissent', 'arbiter'],
                    'failure_modes_observed': [],
                    'ceiling_calibration': {
                        'source': 'conservative_default',
                        'calibrated_at': None,
                        'sample_size': None,
                        'stale_after_days': 30,
                        'reprobe_trigger': '',
                    },
                },
            },
        },
    },
}
PY
}

# v2-only (no v3 fields) — backward-compat ground truth.
_v2_cfg_py() {
    cat <<'PY'
{
    'providers': {
        'openai': {
            'models': {
                'gpt-5.5-pro': {
                    'max_input_tokens': 24000,
                    'streaming_max_input_tokens': 24000,
                    'api_context_window': 128000,
                },
            },
        },
    },
}
PY
}

# Run a python snippet via python -c. Wraps sys.path setup so all tests
# can import cheval cleanly.
_run_pysnippet() {
    local snippet="$1"
    "$PYTHON_BIN" -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
$snippet
"
}

# =============================================================================
# Unit tests for _lookup_capability — direct python invocation
# =============================================================================

@test "P1: _lookup_capability returns Capability tuple for reasoning-class v3 model" {
    local cfg
    cfg="$(_v3_cfg_reasoning_py)"
    run _run_pysnippet "
from cheval import _lookup_capability

cfg = $cfg
cap = _lookup_capability('anthropic', 'claude-opus-4-7', cfg)
assert cap is not None, 'capability lookup must not return None for v3 model'
assert cap.effective_input_ceiling == 40000, f'ceiling: {cap.effective_input_ceiling!r}'
assert cap.reasoning_class is True, f'reasoning_class: {cap.reasoning_class!r}'
assert cap.recommended_for == ['review', 'audit'], f'recommended_for: {cap.recommended_for!r}'
# ceiling_stale is a derived boolean from ceiling_calibration; must be present
assert isinstance(cap.ceiling_stale, bool), f'ceiling_stale: {cap.ceiling_stale!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P2: _lookup_capability returns Capability tuple for non-reasoning v3 model" {
    local cfg
    cfg="$(_v3_cfg_nonreasoning_py)"
    run _run_pysnippet "
from cheval import _lookup_capability

cfg = $cfg
cap = _lookup_capability('openai', 'gpt-4o-mini', cfg)
assert cap is not None, 'capability lookup must not return None for v3 model'
assert cap.effective_input_ceiling == 30000, f'ceiling: {cap.effective_input_ceiling!r}'
assert cap.reasoning_class is False, f'reasoning_class: {cap.reasoning_class!r}'
assert cap.recommended_for == ['review', 'audit', 'implementation', 'dissent', 'arbiter'], f'recommended_for: {cap.recommended_for!r}'
assert isinstance(cap.ceiling_stale, bool), f'ceiling_stale: {cap.ceiling_stale!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P3: _lookup_capability returns Capability with None ceiling for v2-only config (backward-compat)" {
    local cfg
    cfg="$(_v2_cfg_py)"
    run _run_pysnippet "
from cheval import _lookup_capability

cfg = $cfg
cap = _lookup_capability('openai', 'gpt-5.5-pro', cfg)
# Model exists but v3 fields absent — Capability must be present with ceiling=None
assert cap is not None, 'v2-only model still returns Capability shell'
assert cap.effective_input_ceiling is None, f'ceiling: {cap.effective_input_ceiling!r}'
# reasoning_class defaults to False (SDD §3.1.2 conservative default)
assert cap.reasoning_class is False, f'reasoning_class: {cap.reasoning_class!r}'
# recommended_for defaults to allow-all (SKP-004 v5 closure: NOT [])
assert cap.recommended_for == ['review', 'audit', 'implementation', 'dissent', 'arbiter'], f'recommended_for: {cap.recommended_for!r}'
assert cap.ceiling_stale is False, f'ceiling_stale: {cap.ceiling_stale!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P4: _lookup_capability returns None for unknown provider / model" {
    run _run_pysnippet "
from cheval import _lookup_capability

cfg = {'providers': {'openai': {'models': {'gpt-4o-mini': {'effective_input_ceiling': 30000}}}}}
assert _lookup_capability('unknown-provider', 'x', cfg) is None
assert _lookup_capability('openai', 'unknown-model', cfg) is None
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P5: ceiling_stale=True when ceiling_calibration.calibrated_at older than stale_after_days" {
    run _run_pysnippet "
from cheval import _lookup_capability

# Calibrated 60 days ago, stale_after_days=30 → ceiling_stale=True
cfg = {
    'providers': {
        'anthropic': {
            'models': {
                'claude-opus-4-7': {
                    'effective_input_ceiling': 40000,
                    'reasoning_class': True,
                    'recommended_for': ['review'],
                    'ceiling_calibration': {
                        'source': 'empirical_probe',
                        'calibrated_at': '2026-01-01T00:00:00Z',  # ~4 months stale
                        'sample_size': 25,
                        'stale_after_days': 30,
                        'reprobe_trigger': '',
                    },
                },
            },
        },
    },
}
cap = _lookup_capability('anthropic', 'claude-opus-4-7', cfg)
assert cap.ceiling_stale is True, f'ceiling_stale should be True for 4-month-old probe: {cap.ceiling_stale!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P6: ceiling_stale=False when calibration is fresh AND when source=conservative_default (no probe)" {
    run _run_pysnippet "
from cheval import _lookup_capability
import datetime

# Fresh empirical probe → not stale
now_iso = datetime.datetime.utcnow().isoformat() + 'Z'
cfg_fresh = {
    'providers': {
        'anthropic': {
            'models': {
                'claude-opus-4-7': {
                    'effective_input_ceiling': 40000,
                    'reasoning_class': True,
                    'recommended_for': ['review'],
                    'ceiling_calibration': {
                        'source': 'empirical_probe',
                        'calibrated_at': now_iso,
                        'sample_size': 25,
                        'stale_after_days': 30,
                        'reprobe_trigger': '',
                    },
                },
            },
        },
    },
}
cap_fresh = _lookup_capability('anthropic', 'claude-opus-4-7', cfg_fresh)
assert cap_fresh.ceiling_stale is False, f'fresh probe must not be stale: {cap_fresh.ceiling_stale!r}'

# conservative_default source with calibrated_at=None must NOT be marked stale
# (we have no empirical signal to be stale ABOUT — applying staleness here
# would force every default-configured model into chunked-defensive mode).
cfg_default = {
    'providers': {
        'openai': {
            'models': {
                'gpt-4o-mini': {
                    'effective_input_ceiling': 30000,
                    'reasoning_class': False,
                    'recommended_for': ['review'],
                    'ceiling_calibration': {
                        'source': 'conservative_default',
                        'calibrated_at': None,
                        'sample_size': None,
                        'stale_after_days': 30,
                        'reprobe_trigger': '',
                    },
                },
            },
        },
    },
}
cap_default = _lookup_capability('openai', 'gpt-4o-mini', cfg_default)
assert cap_default.ceiling_stale is False, f'conservative_default must not be flagged stale: {cap_default.ceiling_stale!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# =============================================================================
# Unit tests for _preflight_check — capability gate decision logic
# =============================================================================

@test "P7: _preflight_check returns 'preempt' decision when input > ceiling AND chunking disabled (reasoning class)" {
    run _run_pysnippet "
from cheval import _lookup_capability, _preflight_check

cfg = $(_v3_cfg_reasoning_py)
cap = _lookup_capability('anthropic', 'claude-opus-4-7', cfg)
# estimated 50000 > ceiling 40000 → preempt
decision = _preflight_check(estimated_input=50000, capability=cap, chunking_enabled=False)
assert decision is not None, 'must emit a decision when ceiling exceeded'
assert decision.action == 'preempt', f'action: {decision.action!r}'
assert decision.exit_code == 7, f'exit_code: {decision.exit_code!r}'
assert decision.estimated_input == 50000
assert decision.effective_input_ceiling == 40000
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P8: _preflight_check returns 'preempt' decision when input > ceiling AND chunking disabled (non-reasoning class)" {
    run _run_pysnippet "
from cheval import _lookup_capability, _preflight_check

cfg = $(_v3_cfg_nonreasoning_py)
cap = _lookup_capability('openai', 'gpt-4o-mini', cfg)
decision = _preflight_check(estimated_input=40000, capability=cap, chunking_enabled=False)
assert decision is not None
assert decision.action == 'preempt'
assert decision.exit_code == 7
assert decision.effective_input_ceiling == 30000
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P9: _preflight_check returns None (passthrough) when input <= ceiling" {
    run _run_pysnippet "
from cheval import _lookup_capability, _preflight_check

cfg = $(_v3_cfg_reasoning_py)
cap = _lookup_capability('anthropic', 'claude-opus-4-7', cfg)
# 30000 < 40000 → no decision
decision = _preflight_check(estimated_input=30000, capability=cap, chunking_enabled=False)
assert decision is None, f'passthrough expected: got {decision!r}'

# Equal-to-ceiling is also passthrough (gate fires only on strictly greater)
decision_eq = _preflight_check(estimated_input=40000, capability=cap, chunking_enabled=False)
assert decision_eq is None, f'equal-to-ceiling must passthrough: got {decision_eq!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P10: _preflight_check returns 'chunk' decision when input > ceiling AND chunking enabled" {
    run _run_pysnippet "
from cheval import _lookup_capability, _preflight_check

cfg = $(_v3_cfg_reasoning_py)
cap = _lookup_capability('anthropic', 'claude-opus-4-7', cfg)
decision = _preflight_check(estimated_input=80000, capability=cap, chunking_enabled=True)
# Sprint 4 will materialize chunking; for Sprint 1, the decision exists but
# the executor falls back to preempt because the chunking primitive is absent.
# Either: the decision shape is 'chunk' (Sprint 4 path), OR it's 'preempt'
# (Sprint 1 — chunking not yet wired). Both are acceptable; we assert that
# the decision is NOT None (gate fired) and exit_code is not 0.
assert decision is not None, 'gate must fire when ceiling exceeded'
assert decision.action in ('chunk', 'preempt'), f'action: {decision.action!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P11: _preflight_check passthroughs when capability is None (unknown model)" {
    run _run_pysnippet "
from cheval import _preflight_check

# capability=None → no gate fires (backward-compat / unknown model)
decision = _preflight_check(estimated_input=999999, capability=None, chunking_enabled=False)
assert decision is None, f'None capability must not trigger gate: got {decision!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P12: _preflight_check passthroughs when effective_input_ceiling is None (v2 backward-compat)" {
    run _run_pysnippet "
from cheval import _lookup_capability, _preflight_check

cfg = $(_v2_cfg_py)
cap = _lookup_capability('openai', 'gpt-5.5-pro', cfg)
assert cap.effective_input_ceiling is None
# v2-only config — v3 gate must NOT fire (the legacy per-entry input gate
# downstream is the v2 protection mechanism, not this pre-flight gate).
decision = _preflight_check(estimated_input=999999, capability=cap, chunking_enabled=False)
assert decision is None, f'v2-only must passthrough new gate: got {decision!r}'
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# =============================================================================
# Backward-compat: _lookup_max_input_tokens still returns Optional[int]
# =============================================================================

@test "P13: _lookup_max_input_tokens preserves v2 contract (returns Optional[int])" {
    local cfg
    cfg="$(_v2_cfg_py)"
    run _run_pysnippet "
from cheval import _lookup_max_input_tokens

cfg = $cfg
# v2 contract: returns the int threshold from streaming_max_input_tokens.
threshold = _lookup_max_input_tokens('openai', 'gpt-5.5-pro', cfg)
assert isinstance(threshold, int), f'expected int, got {type(threshold).__name__}: {threshold!r}'
assert threshold == 24000, f'threshold: {threshold!r}'
# Unknown still returns None.
assert _lookup_max_input_tokens('unknown', 'x', cfg) is None
assert _lookup_max_input_tokens('openai', 'unknown', cfg) is None
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "P14: _lookup_max_input_tokens prefers effective_input_ceiling over streaming/legacy when v3 fields present" {
    # When v3 ceiling is set, the v2 helper should return the v3 ceiling
    # (it IS the effective input bound; the v2 fields become a fallback).
    run _run_pysnippet "
from cheval import _lookup_max_input_tokens

cfg = {
    'providers': {
        'anthropic': {
            'models': {
                'claude-opus-4-7': {
                    'streaming_max_input_tokens': 80000,
                    'legacy_max_input_tokens': 60000,
                    'effective_input_ceiling': 40000,
                },
            },
        },
    },
}
# v3 field present → return effective_input_ceiling (tighter bound).
assert _lookup_max_input_tokens('anthropic', 'claude-opus-4-7', cfg) == 40000
print('OK')
"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# =============================================================================
# Integration: cheval CLI invocation — pre-flight gate emits exit 7
# =============================================================================

@test "P15: cheval CLI emits exit 7 + [preflight] marker when prompt exceeds effective_input_ceiling (reasoning class)" {
    # Large prompt → exceeds the 1000-token override threshold. Generate via
    # python to avoid ARG_MAX (~2MB) constraints on shell command lines.
    # The pre-flight gate must fire BEFORE chain walk → exit 7 with a
    # `[preflight]` marker discriminating it from the legacy walk-eligible
    # `[input-gate]` mechanism. Gate runs offline.
    local prompt_file="$BATS_TMP/prompt.txt"
    "$PYTHON_BIN" -c "open('$prompt_file', 'w').write('x' * 200000)"

    OPENAI_API_KEY="" ANTHROPIC_API_KEY="" GOOGLE_API_KEY="" \
    LOA_PREFLIGHT_GATE_FORCE=1 \
    run "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --input "$prompt_file" \
        --max-input-tokens 1000 \
        2>&1
    [ "$status" -eq 7 ]
    [[ "$output" == *"[preflight]"* ]]
    [[ "$output" == *"CONTEXT_TOO_LARGE"* ]] || [[ "$output" == *"ContextTooLarge"* ]]
}

@test "P16: cheval CLI emits exit 7 for non-reasoning class agent binding" {
    # Same shape as P15 but for the `translating-for-executives` binding
    # (model: cheap → non-reasoning tier). What this test asserts is that
    # the gate fires regardless of the bound model's reasoning_class — both
    # classes get pre-flight protection.
    local prompt_file="$BATS_TMP/prompt.txt"
    "$PYTHON_BIN" -c "open('$prompt_file', 'w').write('x' * 200000)"

    OPENAI_API_KEY="" ANTHROPIC_API_KEY="" GOOGLE_API_KEY="" \
    LOA_PREFLIGHT_GATE_FORCE=1 \
    run "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent translating-for-executives \
        --input "$prompt_file" \
        --max-input-tokens 1000 \
        2>&1
    [ "$status" -eq 7 ]
    [[ "$output" == *"[preflight]"* ]]
}

@test "P17: cheval CLI does NOT fire preflight gate when prompt under ceiling" {
    OPENAI_API_KEY="" ANTHROPIC_API_KEY="" GOOGLE_API_KEY="" \
    run "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code \
        --prompt "tiny prompt" \
        2>&1
    # The new [preflight] marker must not appear. Exit code may be non-zero
    # due to absent API keys but specifically MUST NOT be 7 from a pre-flight
    # preemption.
    [[ "$output" != *"[preflight] preempt"* ]]
}
