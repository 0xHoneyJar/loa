#!/usr/bin/env bats
# =============================================================================
# tests/integration/migrate-model-config-v3.bats
#
# cycle-109 Sprint 1 T1.2 — v2→v3 migration with conservative defaults
# per SDD §3.1.2 (IMP-008).
#
# Driver: .claude/scripts/loa-migrate-model-config.py --to-v3 ...
# Library: .claude/scripts/lib/model-config-migrate.py::migrate_v2_to_v3
#
# Conservative defaults table (SDD §3.1.2):
#   effective_input_ceiling = min(50% × api_context_window, 30000)
#   reasoning_class         = false (default); opt-in flip for known classes
#   recommended_for         = [review, audit, implementation, dissent, arbiter]
#   failure_modes_observed  = []
#   ceiling_calibration     = {source: conservative_default, sample_size: null,
#                              stale_after_days: 30, …}
#   streaming_recovery      = {first_token_deadline_seconds: 30|60 (per
#                              reasoning_class), empty_detection_window_tokens:
#                              200, cot_token_budget: 500|null}
#
# Reasoning-class opt-in list (SDD §3.1.2):
#   claude-opus-4-* | gpt-5.5-pro | gemini-3.1-pro → reasoning_class: true
#
# Test-first: this file lands BEFORE the v2→v3 migrator. Initial state: every
# test skips cleanly. commit-2 lands the migrator and skips flip to active.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CLI="$PROJECT_ROOT/.claude/scripts/loa-migrate-model-config.py"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/model-config-migrate.py"
    SCHEMA_V3="$PROJECT_ROOT/.claude/data/schemas/model-config-v3.schema.json"

    [[ -f "$CLI" ]] || skip "CLI not present"
    [[ -f "$LIB" ]] || skip "lib not present"
    [[ -f "$SCHEMA_V3" ]] || skip "v3 schema not present (run T1.1 first)"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi

    "$PYTHON_BIN" -c "import ruamel.yaml, jsonschema" 2>/dev/null \
        || skip "ruamel.yaml or jsonschema not available"

    # Probe: migrator must expose migrate_v2_to_v3 — skip until landed.
    "$PYTHON_BIN" -c "
import importlib.util, sys
spec = importlib.util.spec_from_file_location('m', '$LIB')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert hasattr(m, 'migrate_v2_to_v3'), 'migrate_v2_to_v3 not defined'
" 2>/dev/null || skip "migrate_v2_to_v3 not yet implemented (T1.2 pending)"

    WORK_DIR="$(mktemp -d)"
    IN="$WORK_DIR/v2.yaml"
    OUT="$WORK_DIR/v3.yaml"

    # Canonical v2 fixture: 3 providers covering both reasoning-class and
    # non-reasoning model patterns the migrator must handle.
    cat > "$IN" <<'YAML'
schema_version: 2
providers:
  anthropic:
    type: anthropic
    endpoint: https://api.anthropic.com
    models:
      claude-opus-4-7:
        context_window: 200000
        max_output_tokens: 8192
      claude-haiku-4-5:
        context_window: 100000
        max_output_tokens: 4096
  openai:
    type: openai
    models:
      gpt-5.5-pro:
        context_window: 400000
        max_output_tokens: 16384
      gpt-5.5:
        context_window: 200000
        max_output_tokens: 8192
  google:
    type: google
    models:
      gemini-3.1-pro:
        context_window: 1000000
        max_output_tokens: 16384
      gemini-3-flash:
        context_window: 100000
        max_output_tokens: 4096
YAML
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Run the CLI; print stderr on failure for debugging.
run_cli() {
    run "$PYTHON_BIN" "$CLI" "$IN" -o "$OUT" --to-v3 --report-format json "$@"
    if [ "$status" -ne 0 ]; then
        echo "CLI failed (exit $status):" >&2
        echo "$output" >&2
    fi
}

# yq helper using Python (ruamel.yaml) — keeps test deps minimal.
yqp() {
    local path="$1"
    "$PYTHON_BIN" -c "
import sys, json
from ruamel.yaml import YAML
yaml = YAML(typ='safe')
with open('$OUT') as f:
    doc = yaml.load(f)
def get(d, path):
    cur = d
    for k in path.strip('.').split('.'):
        if k.startswith('[') and k.endswith(']'):
            cur = cur[int(k[1:-1])]
        else:
            cur = cur[k]
    return cur
print(json.dumps(get(doc, '$path')))
"
}

# -----------------------------------------------------------------------------
# G-2.1: end-to-end CLI works + schema_version bumps to 3
# -----------------------------------------------------------------------------

@test "G-2.1: --to-v3 produces schema_version 3" {
    run_cli
    [ "$status" -eq 0 ]
    [ "$(yqp '.schema_version')" = "3" ]
}

@test "G-2.1: --to-v3 produces a schema-valid v3 document" {
    run_cli
    [ "$status" -eq 0 ]
    run "$PYTHON_BIN" -c "
import json, jsonschema
from ruamel.yaml import YAML
yaml = YAML(typ='safe')
with open('$OUT') as f: doc = yaml.load(f)
schema = json.load(open('$SCHEMA_V3'))
jsonschema.validate(doc, schema)
"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Conservative defaults table (SDD §3.1.2)
# -----------------------------------------------------------------------------

@test "Defaults: effective_input_ceiling = min(50% × api_context_window, 30000)" {
    run_cli
    [ "$status" -eq 0 ]
    # claude-opus-4-7: api=200000 → 50% = 100000 → min(100000, 30000) = 30000
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.effective_input_ceiling')" = "30000" ]
    # claude-haiku-4-5: api=100000 → 50% = 50000 → min(50000, 30000) = 30000
    [ "$(yqp '.providers.anthropic.models.claude-haiku-4-5.effective_input_ceiling')" = "30000" ]
    # If api_context_window < 60000, 50% wins. Build a small fixture inline:
    run "$PYTHON_BIN" -c "
import importlib.util
spec = importlib.util.spec_from_file_location('m', '$LIB')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
v2 = {'schema_version': 2, 'providers': {'p': {'models': {'tiny': {'context_window': 40000}}}}}
v3, _ = m.migrate_v2_to_v3(v2)
assert v3['providers']['p']['models']['tiny']['effective_input_ceiling'] == 20000, \
    v3['providers']['p']['models']['tiny']['effective_input_ceiling']
"
    [ "$status" -eq 0 ]
}

@test "Defaults: reasoning_class opt-in for claude-opus-4-*, gpt-5.5-pro, gemini-3.1-pro" {
    run_cli
    [ "$status" -eq 0 ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.reasoning_class')" = "true" ]
    [ "$(yqp '.providers.openai.models.\"gpt-5.5-pro\".reasoning_class')" = "true" ]
    [ "$(yqp '.providers.google.models.\"gemini-3.1-pro\".reasoning_class')" = "true" ]
    # Non-reasoning classes default to false
    [ "$(yqp '.providers.anthropic.models.claude-haiku-4-5.reasoning_class')" = "false" ]
    [ "$(yqp '.providers.openai.models.\"gpt-5.5\".reasoning_class')" = "false" ]
    [ "$(yqp '.providers.google.models.\"gemini-3-flash\".reasoning_class')" = "false" ]
}

@test "Defaults: recommended_for = allow-all 5-role list per SKP-004 v5 closure" {
    run_cli
    [ "$status" -eq 0 ]
    expected='["review", "audit", "implementation", "dissent", "arbiter"]'
    got="$(yqp '.providers.anthropic.models.claude-opus-4-7.recommended_for')"
    [ "$got" = "$expected" ]
}

@test "Defaults: failure_modes_observed = [] (populated later by FR-1.5)" {
    run_cli
    [ "$status" -eq 0 ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.failure_modes_observed')" = "[]" ]
}

@test "Defaults: ceiling_calibration.source = conservative_default + stale_after_days = 30" {
    run_cli
    [ "$status" -eq 0 ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.ceiling_calibration.source')" = '"conservative_default"' ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.ceiling_calibration.sample_size')" = "null" ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.ceiling_calibration.stale_after_days')" = "30" ]
}

@test "Defaults: streaming_recovery — reasoning_class gets 60s + 500-token cot_budget" {
    run_cli
    [ "$status" -eq 0 ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.streaming_recovery.first_token_deadline_seconds')" = "60" ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.streaming_recovery.empty_detection_window_tokens')" = "200" ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.streaming_recovery.cot_token_budget')" = "500" ]
}

@test "Defaults: streaming_recovery — non-reasoning gets 30s + null cot_budget" {
    run_cli
    [ "$status" -eq 0 ]
    [ "$(yqp '.providers.anthropic.models.claude-haiku-4-5.streaming_recovery.first_token_deadline_seconds')" = "30" ]
    [ "$(yqp '.providers.anthropic.models.claude-haiku-4-5.streaming_recovery.cot_token_budget')" = "null" ]
}

# -----------------------------------------------------------------------------
# Idempotency + preservation
# -----------------------------------------------------------------------------

@test "Idempotent: --to-v3 on v3 input is a no-op (re-emits same fields)" {
    run_cli
    [ "$status" -eq 0 ]
    cp "$OUT" "$WORK_DIR/first.yaml"
    # Second invocation with the v3 output as input
    run "$PYTHON_BIN" "$CLI" "$WORK_DIR/first.yaml" -o "$WORK_DIR/second.yaml" \
        --to-v3 --report-format json
    [ "$status" -eq 0 ]
    # The structural content matches (compare normalized YAML)
    run "$PYTHON_BIN" -c "
from ruamel.yaml import YAML
yaml = YAML(typ='safe')
with open('$WORK_DIR/first.yaml') as f: a = yaml.load(f)
with open('$WORK_DIR/second.yaml') as f: b = yaml.load(f)
assert a == b, f'idempotency violated:\nA={a}\nB={b}'
"
    [ "$status" -eq 0 ]
}

@test "Preservation: existing v2 fields (context_window, max_output_tokens) preserved verbatim" {
    run_cli
    [ "$status" -eq 0 ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.context_window')" = "200000" ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.max_output_tokens')" = "8192" ]
}

# -----------------------------------------------------------------------------
# Edge cases
# -----------------------------------------------------------------------------

@test "Edge: model entry with no context_window uses 0 → effective_input_ceiling = 0 → schema rejects" {
    # Schema requires effective_input_ceiling minimum 1; migrator MUST NOT emit
    # 0. When context_window is absent, migrator falls back to a safe minimum
    # (the SDD says conservative_default = min(50% × api, 30000), so for
    # api=undefined we use 30000 as the floor).
    cat > "$IN" <<'YAML'
schema_version: 2
providers:
  p:
    type: anthropic
    models:
      missing-cw:
        max_output_tokens: 4096
YAML
    run_cli
    [ "$status" -eq 0 ]
    # Migrator falls back to 30000 default
    [ "$(yqp '.providers.p.models.missing-cw.effective_input_ceiling')" = "30000" ]
}

@test "Edge: v1 input (no schema_version) auto-chains v1→v2→v3" {
    cat > "$IN" <<'YAML'
providers:
  anthropic:
    type: anthropic
    models:
      claude-opus-4-7:
        context_window: 200000
YAML
    run_cli
    [ "$status" -eq 0 ]
    [ "$(yqp '.schema_version')" = "3" ]
    [ "$(yqp '.providers.anthropic.models.claude-opus-4-7.reasoning_class')" = "true" ]
}
