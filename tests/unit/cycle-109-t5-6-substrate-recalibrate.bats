#!/usr/bin/env bats
# cycle-109 Sprint 5 T5.6 — operator-gated `loa substrate recalibrate`
# CLI shim (FR-1.6 trigger; synchronous-with-progress per C109.OP-5 Q6).

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    RECAL="$PROJECT_ROOT/.claude/scripts/loa-substrate-recalibrate.sh"
    TMP="$(mktemp -d -t loa-substrate-recal-XXXXXX)"

    [[ -x "$RECAL" ]] || skip "recalibrate script not present"

    # Synthetic operators.md so we don't depend on the live one
    export LOA_OPERATORS_FILE="$TMP/operators.md"
    cat > "$LOA_OPERATORS_FILE" <<'YAML'
---
schema_version: "1.0"
operators:
  - id: test-operator-slug
    display_name: "Test Op"
    github_handle: testop
    git_email: "test@example.com"
    capabilities: [dispatch]
    active_since: "2026-05-14T00:00:00Z"
---

# Operators

(test fixture)
YAML

    # Minimal model-config.yaml fixture with one model.
    export FIXTURE_CONFIG="$TMP/model-config.yaml"
    cat > "$FIXTURE_CONFIG" <<'YAML'
schema_version: 3
providers:
  anthropic:
    models:
      claude-opus-4-7:
        api_context_window: 200000
        effective_input_ceiling: 40000
        reasoning_class: true
        recommended_for: [review]
        failure_modes_observed: []
        ceiling_calibration:
          source: conservative_default
          calibrated_at: null
          sample_size: null
          stale_after_days: 30
          reprobe_trigger: ''
YAML

    # Deterministic probe fixture — all trials clean → ceiling = max size.
    export PROBE_FIXTURE="$TMP/probe-fixture.json"
    cat > "$PROBE_FIXTURE" <<'JSON'
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
}

teardown() {
    if [[ -d "$TMP" ]]; then
        find "$TMP" -mindepth 1 -delete
        rmdir "$TMP"
    fi
}

# ---------------------------------------------------------------------------
# Help + argument parsing
# ---------------------------------------------------------------------------

@test "T5.6: --help exits 0 and prints usage" {
    run "$RECAL" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "recalibrate"
    echo "$output" | grep -qi "model-id"
}

@test "T5.6: missing <model-id> exits 2 with usage hint" {
    run "$RECAL"
    [ "$status" -eq 2 ]
    echo "$output$stderr" | grep -qi "usage\|missing.*model"
}

@test "T5.6: missing --operator exits 2 (operator-gated per C109.OP-5 Q1)" {
    run "$RECAL" anthropic:claude-opus-4-7
    [ "$status" -eq 2 ]
    echo "$output$stderr" | grep -qi "operator"
}

# ---------------------------------------------------------------------------
# Operator verification (OPERATORS.md slug gating)
# ---------------------------------------------------------------------------

@test "T5.6: unknown operator slug exits 3" {
    run "$RECAL" anthropic:claude-opus-4-7 \
        --operator nonexistent-operator-xyz \
        --model-config "$FIXTURE_CONFIG" \
        --probe-backend fixture \
        --fixture "$PROBE_FIXTURE"
    [ "$status" -eq 3 ]
    echo "$output$stderr" | grep -qi "operator\|unknown"
}

# ---------------------------------------------------------------------------
# Model-id parsing (provider:model_id form)
# ---------------------------------------------------------------------------

@test "T5.6: malformed model-id (no colon) exits 2" {
    run "$RECAL" claude-opus-4-7 \
        --operator test-operator-slug \
        --model-config "$FIXTURE_CONFIG" \
        --probe-backend fixture \
        --fixture "$PROBE_FIXTURE"
    [ "$status" -eq 2 ]
    echo "$output$stderr" | grep -qi "provider:model\|colon\|format"
}

# ---------------------------------------------------------------------------
# Happy path — fixture probe successfully recalibrates
# ---------------------------------------------------------------------------

@test "T5.6: happy-path fixture probe updates effective_input_ceiling" {
    pre_ceiling=$(python3 -c "import yaml; print(yaml.safe_load(open('$FIXTURE_CONFIG'))['providers']['anthropic']['models']['claude-opus-4-7']['effective_input_ceiling'])")
    [ "$pre_ceiling" = "40000" ]

    run "$RECAL" anthropic:claude-opus-4-7 \
        --operator test-operator-slug \
        --model-config "$FIXTURE_CONFIG" \
        --probe-backend fixture \
        --fixture "$PROBE_FIXTURE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qiE "recalibrat|ceiling|empirical_probe"

    # All trials clean → ceiling promoted to max probed size (50000)
    post_ceiling=$(python3 -c "import yaml; print(yaml.safe_load(open('$FIXTURE_CONFIG'))['providers']['anthropic']['models']['claude-opus-4-7']['effective_input_ceiling'])")
    [ "$post_ceiling" = "50000" ]
}

@test "T5.6: post-run ceiling_calibration.source = empirical_probe" {
    run "$RECAL" anthropic:claude-opus-4-7 \
        --operator test-operator-slug \
        --model-config "$FIXTURE_CONFIG" \
        --probe-backend fixture \
        --fixture "$PROBE_FIXTURE"
    [ "$status" -eq 0 ]
    source=$(python3 -c "import yaml; print(yaml.safe_load(open('$FIXTURE_CONFIG'))['providers']['anthropic']['models']['claude-opus-4-7']['ceiling_calibration']['source'])")
    [ "$source" = "empirical_probe" ]
}

# ---------------------------------------------------------------------------
# Live-backend gate (cycle-109 substrate-degraded posture)
# ---------------------------------------------------------------------------

@test "T5.6: --probe-backend live exits 6 (disabled in cycle-109)" {
    run "$RECAL" anthropic:claude-opus-4-7 \
        --operator test-operator-slug \
        --model-config "$FIXTURE_CONFIG" \
        --probe-backend live
    [ "$status" -eq 6 ]
    echo "$output$stderr" | grep -qi "live\|disabled\|operator-driven"
}
