#!/usr/bin/env bats
# =============================================================================
# tests/unit/ceiling-probe-protocol.bats
#
# cycle-109 Sprint 1 T1.7 — ceiling-probe protocol (PRD §FR-1.6,
# SDD §3.1, IMP-007). Binary-search empirical ceiling derivation
# per cycle-104 T2.10 precedent:
#
#   - Probe N prompts × M input sizes (default 5×5 at 10K/20K/30K/40K/50K)
#   - Ceiling = lowest size with empty-content rate > 5%
#   - Calibration source: `empirical_probe`
#   - Written to model-config.yaml::providers.<p>.models.<m>.ceiling_calibration
#
# Substrate-degraded environments (Anthropic billing-depleted in
# cycle-109): live calibration is operator-driven; T1.7 SCRIPT is
# always-on but the probe backend is pluggable. Tests use a JSON-fixture
# backend that returns deterministic empty/non-empty rates per
# (provider, model, size) — exercising the binary-search + ceiling-pick
# logic without any network IO.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CEILING_PROBE="$PROJECT_ROOT/tools/ceiling-probe.py"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/ceiling-probe.XXXXXX")"

    # Standard model-config.yaml fixture with a single reasoning-class model.
    cat > "$BATS_TMP/model-config.yaml" <<'YAML'
schema_version: 3
providers:
  anthropic:
    models:
      claude-opus-4-7:
        api_context_window: 200000
        effective_input_ceiling: 40000
        reasoning_class: true
        recommended_for: [review, audit, implementation, dissent, arbiter]
        failure_modes_observed: []
        ceiling_calibration:
          source: conservative_default
          calibrated_at: null
          sample_size: null
          stale_after_days: 30
          reprobe_trigger: ''
YAML
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Read a model's ceiling_calibration as compact JSON.
_read_calibration() {
    "$PYTHON_BIN" - <<PY
import json, yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
mc = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
print(json.dumps(mc.get("ceiling_calibration", {})))
PY
}

# Read the effective_input_ceiling value.
_read_ceiling() {
    "$PYTHON_BIN" - <<PY
import yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
mc = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
v = mc.get("effective_input_ceiling")
print("null" if v is None else v)
PY
}

# Write a fixture backend that maps (size) → empty_count/sample_count.
# JSON shape: { "trials": [ { "size": 10000, "empty_count": 0, "sample_count": 5 }, ... ] }
_write_fixture() {
    local path="$1"
    cat > "$path"
}

# =============================================================================
# B1: ceiling = lowest size with empty-content rate > 5%
# =============================================================================

@test "B1: probe identifies ceiling as lowest size with empty rate > 5%" {
    # Fixture: 5 sizes × 5 trials.
    #   10K: 0/5 empty   = 0%
    #   20K: 0/5 empty   = 0%
    #   30K: 1/5 empty   = 20% → ceiling
    #   40K: 3/5 empty   = 60%
    #   50K: 5/5 empty   = 100%
    _write_fixture "$BATS_TMP/fixture.json" <<'JSON'
{
  "provider": "anthropic",
  "model_id": "claude-opus-4-7",
  "trials": [
    { "size": 10000, "empty_count": 0, "sample_count": 5 },
    { "size": 20000, "empty_count": 0, "sample_count": 5 },
    { "size": 30000, "empty_count": 1, "sample_count": 5 },
    { "size": 40000, "empty_count": 3, "sample_count": 5 },
    { "size": 50000, "empty_count": 5, "sample_count": 5 }
  ]
}
JSON
    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend fixture \
        --fixture "$BATS_TMP/fixture.json" \
        --apply
    [ "$status" -eq 0 ]

    run _read_ceiling
    [ "$status" -eq 0 ]
    [[ "$output" == "20000" ]] || [[ "$output" == "30000" ]]
    # Acceptable: either the LAST safe size (20K) OR the FIRST unsafe
    # size (30K) is a defensible ceiling pick — both bound the empty
    # threshold. The script defines the canonical choice; both forms
    # PASS the protocol contract.
}

# =============================================================================
# B2: when every probed size is empty-free, ceiling = highest probed size
# =============================================================================

@test "B2: every size empty-free → ceiling = highest probed size" {
    _write_fixture "$BATS_TMP/fixture.json" <<'JSON'
{
  "provider": "anthropic",
  "model_id": "claude-opus-4-7",
  "trials": [
    { "size": 10000, "empty_count": 0, "sample_count": 5 },
    { "size": 20000, "empty_count": 0, "sample_count": 5 },
    { "size": 30000, "empty_count": 0, "sample_count": 5 },
    { "size": 40000, "empty_count": 0, "sample_count": 5 },
    { "size": 50000, "empty_count": 0, "sample_count": 5 }
  ]
}
JSON
    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend fixture \
        --fixture "$BATS_TMP/fixture.json" \
        --apply
    [ "$status" -eq 0 ]

    run _read_ceiling
    [[ "$output" == "50000" ]]
}

# =============================================================================
# B3: when smallest size already exceeds threshold, ceiling = that size
#     (defensive: probe found NO safe size, returns lowest probed)
# =============================================================================

@test "B3: smallest size > threshold → ceiling = lowest probed (defensive)" {
    _write_fixture "$BATS_TMP/fixture.json" <<'JSON'
{
  "provider": "anthropic",
  "model_id": "claude-opus-4-7",
  "trials": [
    { "size": 10000, "empty_count": 2, "sample_count": 5 },
    { "size": 20000, "empty_count": 3, "sample_count": 5 },
    { "size": 30000, "empty_count": 4, "sample_count": 5 },
    { "size": 40000, "empty_count": 5, "sample_count": 5 },
    { "size": 50000, "empty_count": 5, "sample_count": 5 }
  ]
}
JSON
    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend fixture \
        --fixture "$BATS_TMP/fixture.json" \
        --apply
    [ "$status" -eq 0 ]

    run _read_ceiling
    [[ "$output" == "10000" ]]
}

# =============================================================================
# B4: calibration record carries source / calibrated_at / sample_size /
#     stale_after_days
# =============================================================================

@test "B4: calibration record carries empirical_probe metadata" {
    _write_fixture "$BATS_TMP/fixture.json" <<'JSON'
{
  "provider": "anthropic",
  "model_id": "claude-opus-4-7",
  "trials": [
    { "size": 10000, "empty_count": 0, "sample_count": 5 },
    { "size": 20000, "empty_count": 0, "sample_count": 5 },
    { "size": 30000, "empty_count": 0, "sample_count": 5 },
    { "size": 40000, "empty_count": 0, "sample_count": 5 },
    { "size": 50000, "empty_count": 0, "sample_count": 5 }
  ]
}
JSON
    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend fixture \
        --fixture "$BATS_TMP/fixture.json" \
        --apply
    [ "$status" -eq 0 ]

    run _read_calibration
    [[ "$output" == *"empirical_probe"* ]]
    [[ "$output" == *"calibrated_at"* ]]
    [[ "$output" == *"sample_size"* ]]
    [[ "$output" == *"stale_after_days"* ]]
    # sample_size == 25 (5 sizes × 5 trials).
    [[ "$output" == *"\"sample_size\": 25"* ]] || [[ "$output" == *"\"sample_size\":25"* ]]
}

# =============================================================================
# B5: --dry-run does NOT mutate model-config.yaml
# =============================================================================

@test "B5: --dry-run leaves model-config.yaml unchanged" {
    _write_fixture "$BATS_TMP/fixture.json" <<'JSON'
{
  "provider": "anthropic",
  "model_id": "claude-opus-4-7",
  "trials": [
    { "size": 10000, "empty_count": 0, "sample_count": 5 },
    { "size": 50000, "empty_count": 5, "sample_count": 5 }
  ]
}
JSON
    local before
    before="$(sha256sum "$BATS_TMP/model-config.yaml" | awk '{print $1}')"
    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend fixture \
        --fixture "$BATS_TMP/fixture.json"
    [ "$status" -eq 0 ]
    # Dry run by absence of --apply.
    local after
    after="$(sha256sum "$BATS_TMP/model-config.yaml" | awk '{print $1}')"
    [[ "$before" == "$after" ]]
    # Result JSON still emitted to stdout.
    [[ "$output" == *"effective_input_ceiling"* ]] || [[ "$output" == *"ceiling"* ]]
}

# =============================================================================
# B6: --apply on second run with same fixture is idempotent
#     (ceiling_calibration changes calibrated_at timestamp but ceiling
#     value remains stable; the model-config drift across runs is bounded
#     to the timestamp field).
# =============================================================================

@test "B6: re-running with same fixture produces stable ceiling value" {
    _write_fixture "$BATS_TMP/fixture.json" <<'JSON'
{
  "provider": "anthropic",
  "model_id": "claude-opus-4-7",
  "trials": [
    { "size": 10000, "empty_count": 0, "sample_count": 5 },
    { "size": 20000, "empty_count": 0, "sample_count": 5 },
    { "size": 30000, "empty_count": 0, "sample_count": 5 },
    { "size": 40000, "empty_count": 1, "sample_count": 5 },
    { "size": 50000, "empty_count": 5, "sample_count": 5 }
  ]
}
JSON
    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend fixture \
        --fixture "$BATS_TMP/fixture.json" \
        --apply
    [ "$status" -eq 0 ]
    run _read_ceiling
    local first="$output"

    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend fixture \
        --fixture "$BATS_TMP/fixture.json" \
        --apply
    [ "$status" -eq 0 ]
    run _read_ceiling
    local second="$output"

    [[ "$first" == "$second" ]]
}

# =============================================================================
# B7: fixture-shape validation — missing required keys exits non-zero
# =============================================================================

@test "B7: malformed fixture exits non-zero" {
    _write_fixture "$BATS_TMP/fixture.json" <<'JSON'
{
  "provider": "anthropic"
}
JSON
    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend fixture \
        --fixture "$BATS_TMP/fixture.json" \
        --apply
    [ "$status" -ne 0 ]
}

# =============================================================================
# B8: unknown probe-backend exits non-zero (only 'fixture' is wired in T1.7;
#     live cheval invocation is documented but operator-driven)
# =============================================================================

@test "B8: --probe-backend live exits non-zero in T1.7 (operator-driven only)" {
    run "$PYTHON_BIN" "$CEILING_PROBE" \
        --provider anthropic \
        --model-id claude-opus-4-7 \
        --model-config "$BATS_TMP/model-config.yaml" \
        --probe-backend live \
        --apply
    # live backend is intentionally not enabled in T1.7 (substrate-degraded).
    # The script must reject with a clear message rather than silently
    # falling back to fixture mode.
    [ "$status" -ne 0 ]
    [[ "$output" == *"live"* ]] || [[ "$output" == *"operator-driven"* ]] || [[ "$output" == *"degraded"* ]]
}
