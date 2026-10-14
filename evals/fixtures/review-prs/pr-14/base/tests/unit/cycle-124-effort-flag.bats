#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/cycle-124-effort-flag.bats
#
# cycle-124 Sprint 1 Task 1.4 (FR-2 / SDD §4.1): the cheval CLI surface for
# output budgets and effort, observed through `--dry-run` (which now reports
# the primary hop's resolved `max_tokens` and the requested `effort`).
#   - the literal `--effort xhigh` on the opus alias ⇒ max_tokens ≥ 64000
#   - non-Anthropic default stays 4096; LOA_CHEVAL_DISABLE_STREAMING ⇒ 16000;
#     LOA_CHEVAL_LEGACY_WIRE ⇒ 4096 (pre-cycle body)
#   - explicit values clamp to the catalog max_output_tokens; 0 is refused
#     as INVALID_INPUT; an unknown effort is an argparse usage error
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
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
    unset LOA_CHEVAL_DISABLE_STREAMING LOA_CHEVAL_LEGACY_WIRE
}

# `run` merges stderr into $output by default; the JSON is on stdout and
# diagnostics (persona warnings, the clamp warning) on stderr, so keep them apart.
_dry_run() {  # <extra args...> — $output = stdout (the JSON), $stderr = diagnostics
    run --separate-stderr env -u ANTHROPIC_API_KEY "$PYTHON_BIN" "$CHEVAL_PY" \
        --agent reviewing-code --prompt "cycle-124-effort" --dry-run --json-errors "$@"
}

_field() {  # <json> <field>
    printf '%s' "$1" | "$PYTHON_BIN" -c "import json,sys; print(json.load(sys.stdin)$2)"
}

@test "c124-1.4-1: --effort xhigh on opus ⇒ dry-run reports effort and max_tokens ≥ 64000" {
    _dry_run --model opus --effort xhigh
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [ "$(_field "$output" "['effort']")" = "xhigh" ]
    [ "$(_field "$output" "['resolved_model']")" = "claude-opus-5" ]
    local mt; mt="$(_field "$output" "['max_tokens']")"
    [ "$mt" -ge 64000 ]
}

@test "c124-1.4-2: default without --effort is effort=None and 64000 on the fable alias" {
    _dry_run --model fable
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [ "$(_field "$output" "['effort']")" = "None" ]
    [ "$(_field "$output" "['max_tokens']")" = "64000" ]
}

@test "c124-1.4-3: non-Anthropic default stays 4096 (FR-2 is Anthropic-only)" {
    _dry_run --model gpt-5.5
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [ "$(_field "$output" "['max_tokens']")" = "4096" ]
}

@test "c124-1.4-4: LOA_CHEVAL_DISABLE_STREAMING=1 ⇒ 16000 non-streaming default" {
    LOA_CHEVAL_DISABLE_STREAMING=1 _dry_run --model opus
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [ "$(_field "$output" "['max_tokens']")" = "16000" ]
}

@test "c124-1.4-5: LOA_CHEVAL_LEGACY_WIRE=1 ⇒ the pre-cycle 4096 default" {
    LOA_CHEVAL_LEGACY_WIRE=1 _dry_run --model opus
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [ "$(_field "$output" "['max_tokens']")" = "4096" ]
}

@test "c124-1.4-6: an Anthropic entry without max_output_tokens keeps 4096 (haiku)" {
    _dry_run --model tiny
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [ "$(_field "$output" "['resolved_model']")" = "claude-haiku-4-5-20251001" ]
    [ "$(_field "$output" "['max_tokens']")" = "4096" ]
}

@test "c124-1.4-7: explicit --max-tokens above the catalog max_output_tokens is clamped" {
    _dry_run --model opus --max-tokens 200000
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    [ "$(_field "$output" "['max_tokens']")" = "128000" ]
}

@test "c124-1.4-8: --max-tokens 0 is INVALID_INPUT (no silent rewrite to 4096)" {
    _dry_run --model opus --max-tokens 0
    [ "$status" -ne 0 ]
    [[ "$stderr" == *'"INVALID_INPUT"'* ]]
}

@test "c124-1.4-9: --effort outside the five levels is an argparse usage error" {
    _dry_run --model opus --effort ultra
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"invalid choice"* ]]
}
