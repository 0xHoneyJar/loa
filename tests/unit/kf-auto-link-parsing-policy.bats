#!/usr/bin/env bats
# =============================================================================
# tests/unit/kf-auto-link-parsing-policy.bats
#
# cycle-109 Sprint 1 T1.5 — KF-auto-link IMP-005 parsing policy
# (PRD §FR-1.5 IMP-005, deterministic + fail-loud).
#
# Each of the 5 IMP-005 rules has a fixture:
#
#   1. Unrecognized Status value  → log warning + skip auto-link (no
#      downgrade), surface in CI report (exit 0; stderr warning)
#   2. Empty/missing Model ref    → skip entry (no-op; exit 0)
#   3. Malformed YAML/markdown    → exit non-zero with line reference
#   4. Multiple model references  → process each independently
#   5. Duplicate KF IDs           → exit non-zero
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    KF_AUTO_LINK="$PROJECT_ROOT/.claude/scripts/lib/kf-auto-link.py"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kf-auto-link-policy.XXXXXX")"

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
  openai:
    models:
      gpt-5.5-pro:
        api_context_window: 128000
        effective_input_ceiling: 30000
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
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
kf_auto_link:
  enabled: true
  overrides: []
YAML
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

_run_link() {
    "$PYTHON_BIN" "$KF_AUTO_LINK" \
        --known-failures "$1" \
        --model-config "$BATS_TMP/model-config.yaml" \
        --loa-config "$BATS_TMP/loa-config.yaml" \
        --audit-log "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# P1: unrecognized Status → warn + skip (exit 0, no downgrade)
# =============================================================================

@test "P1: unrecognized Status value warns + skips without downgrade" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-201: unknown status

**Status**: PARTIALLY-MELTED — operator-coined status
**Model**: anthropic:claude-opus-4-7
**Symptom**: test
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"warning"* ]] || [[ "$output" == *"unknown"* ]]
    # No downgrade: recommended_for unchanged.
    "$PYTHON_BIN" - <<PY
import yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
mc = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
rf = mc.get("recommended_for", [])
assert rf == ["review", "audit", "implementation", "dissent", "arbiter"], f"recommended_for changed: {rf}"
print("OK")
PY
}

# =============================================================================
# P2: empty/missing Model ref → skip (exit 0, no-op)
# =============================================================================

@test "P2: empty or missing Model: reference skips entry as no-op" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-202: no model reference

**Status**: OPEN
**Symptom**: meta-issue not tied to a specific model
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]
    # No model-config mutation.
    "$PYTHON_BIN" - <<PY
import yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
for prov_name, prov in cfg["providers"].items():
    for model_name, mc in prov["models"].items():
        rf = mc.get("recommended_for", [])
        assert "review" in rf, f"{prov_name}:{model_name} review missing: {rf}"
print("OK")
PY
}

# =============================================================================
# P3: malformed markdown/YAML → exit non-zero with line reference
# =============================================================================

@test "P3: malformed KF entry exits non-zero with line reference" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-203: malformed

**Status**:
**Model**:
**Symptom**: completely empty critical fields
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"line"* ]] || [[ "$output" == *"KF-203"* ]] || [[ "$output" == *"malformed"* ]]
}

# =============================================================================
# P4: multiple Model references → process each independently
# =============================================================================

@test "P4: multiple model references in one KF process each independently" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-204: multi-model entry

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7, openai:gpt-5.5-pro
**Symptom**: cross-provider regression
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]
    "$PYTHON_BIN" - <<PY
import yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
opus = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
gpt = cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]
assert opus["recommended_for"] == [], f"opus recommended_for: {opus['recommended_for']}"
assert gpt["recommended_for"] == [], f"gpt recommended_for: {gpt['recommended_for']}"
assert "KF-204" in opus.get("failure_modes_observed", [])
assert "KF-204" in gpt.get("failure_modes_observed", [])
print("OK")
PY
}

# =============================================================================
# P5: duplicate KF IDs → exit non-zero
# =============================================================================

@test "P5: duplicate KF IDs exit non-zero" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-205: first occurrence

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7
**Symptom**: first
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Test fixture.

## KF-205: duplicate id

**Status**: RESOLVED
**Model**: openai:gpt-5.5-pro
**Symptom**: second
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"duplicate"* ]] || [[ "$output" == *"KF-205"* ]]
}
