#!/usr/bin/env bats
# =============================================================================
# tests/unit/kf-auto-link-mapping.bats
#
# cycle-109 Sprint 1 T1.5 — KF-auto-link severity-to-downgrade mapping
# (IMP-001 canonical table per PRD §FR-1.5).
#
# Each row of the IMP-001 table is covered by at least one fixture:
#
#   | KF status              | Effect on referenced model                       |
#   |------------------------|--------------------------------------------------|
#   | OPEN                   | Remove all roles from recommended_for           |
#   | RESOLVED               | No degradation                                  |
#   | RESOLVED-VIA-WORKAROUND| Remove only the specific role mentioned in KF   |
#   | RESOLVED-STRUCTURAL    | No degradation                                  |
#   | LATENT / LAYER-N-LATENT| Remove role(s) referenced in the latent layer   |
#   | DEGRADED-ACCEPTED      | No automated change (informational only)        |
#
# Idempotency (NFR-Rel-3): re-running on the same ledger state produces
# byte-identical model-config.yaml.
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

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kf-auto-link-mapping.XXXXXX")"

    # Fixture model-config.yaml — minimal v3 entries for two models.
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

    # Empty operator-override config (T1.6 schema populates this in its own tests).
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
kf_auto_link:
  enabled: true
  overrides: []
YAML
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Run kf-auto-link with stub KF fixture + per-test model-config + loa-config.
_run_link() {
    local kf_file="$1"
    "$PYTHON_BIN" "$KF_AUTO_LINK" \
        --known-failures "$kf_file" \
        --model-config "$BATS_TMP/model-config.yaml" \
        --loa-config "$BATS_TMP/loa-config.yaml" \
        --audit-log "$BATS_TMP/kf-auto-link.jsonl"
}

# Read a model's recommended_for as a JSON array from the result config.
_read_recommended_for() {
    local provider="$1"
    local model="$2"
    "$PYTHON_BIN" - <<PY
import json
import sys
try:
    import yaml
except ImportError:
    print("[]")
    sys.exit(0)
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
mc = cfg.get("providers", {}).get("$provider", {}).get("models", {}).get("$model", {})
print(json.dumps(mc.get("recommended_for", [])))
PY
}

# Read a model's failure_modes_observed.
_read_failure_modes() {
    local provider="$1"
    local model="$2"
    "$PYTHON_BIN" - <<PY
import json
import sys
try:
    import yaml
except ImportError:
    print("[]")
    sys.exit(0)
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
mc = cfg.get("providers", {}).get("$provider", {}).get("models", {}).get("$model", {})
print(json.dumps(mc.get("failure_modes_observed", [])))
PY
}

# =============================================================================
# M1: OPEN status — remove all roles from recommended_for
# =============================================================================

@test "M1: OPEN status removes all roles from recommended_for" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-101: test open entry

**Status**: OPEN
**Feature**: anthropic claude-opus-4-7 streaming
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: empty content on >40K input
**First observed**: 2026-05-13
**Recurrence count**: 3
**Current workaround**: chunking
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]

    run _read_recommended_for "anthropic" "claude-opus-4-7"
    [ "$status" -eq 0 ]
    [[ "$output" == "[]" ]]

    run _read_failure_modes "anthropic" "claude-opus-4-7"
    [ "$status" -eq 0 ]
    [[ "$output" == *"KF-101"* ]]
}

# =============================================================================
# M2: RESOLVED status — no degradation
# =============================================================================

@test "M2: RESOLVED status produces no recommended_for degradation" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-102: test resolved entry

**Status**: RESOLVED 2026-05-13 (patch landed)
**Feature**: openai gpt-5.5-pro
**Model**: openai:gpt-5.5-pro
**Symptom**: regression fixed
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]

    run _read_recommended_for "openai" "gpt-5.5-pro"
    [ "$status" -eq 0 ]
    # All 5 roles preserved.
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"audit"* ]]
    [[ "$output" == *"implementation"* ]]
    [[ "$output" == *"dissent"* ]]
    [[ "$output" == *"arbiter"* ]]
}

# =============================================================================
# M3: RESOLVED-VIA-WORKAROUND — remove only the specific role
# =============================================================================

@test "M3: RESOLVED-VIA-WORKAROUND removes only the role named in KF" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-103: test workaround entry

**Status**: RESOLVED-VIA-WORKAROUND
**Feature**: anthropic claude-opus-4-7 review prompts
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: review-type prompts produce empty content
**First observed**: 2026-05-13
**Recurrence count**: 2
**Current workaround**: chunking
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]

    run _read_recommended_for "anthropic" "claude-opus-4-7"
    [ "$status" -eq 0 ]
    # Only 'review' removed; other 4 roles retained.
    [[ "$output" != *"\"review\""* ]]
    [[ "$output" == *"audit"* ]]
    [[ "$output" == *"implementation"* ]]
    [[ "$output" == *"dissent"* ]]
    [[ "$output" == *"arbiter"* ]]
}

# =============================================================================
# M4: RESOLVED-STRUCTURAL — no degradation
# =============================================================================

@test "M4: RESOLVED-STRUCTURAL status produces no degradation" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-104: test structural-resolution

**Status**: RESOLVED-STRUCTURAL — substrate refactor landed in cycle-103
**Feature**: openai gpt-5.5-pro
**Model**: openai:gpt-5.5-pro
**Symptom**: empty content
**First observed**: 2026-05-10
**Recurrence count**: 4
**Current workaround**: N/A
**Upstream issue**: filed and closed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]

    run _read_recommended_for "openai" "gpt-5.5-pro"
    [ "$status" -eq 0 ]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"audit"* ]]
    [[ "$output" == *"implementation"* ]]
}

# =============================================================================
# M5: LATENT / LAYER-N-LATENT — remove role referenced in latent layer
# =============================================================================

@test "M5: LATENT status removes role(s) referenced in latent layer" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-105: layer-1 latent

**Status**: LAYER-1-LATENT — reasoning-budget exhaustion remains observable
**Feature**: anthropic claude-opus-4-7 small max_tokens
**Model**: anthropic:claude-opus-4-7
**Role**: dissent
**Symptom**: empty content when max_tokens too small
**First observed**: 2026-05-12
**Recurrence count**: 2
**Current workaround**: operator must set max_tokens ≥ 16K
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]

    run _read_recommended_for "anthropic" "claude-opus-4-7"
    [ "$status" -eq 0 ]
    # 'dissent' removed; others retained.
    [[ "$output" != *"\"dissent\""* ]]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"audit"* ]]
}

# =============================================================================
# M6: DEGRADED-ACCEPTED — no automated change
# =============================================================================

@test "M6: DEGRADED-ACCEPTED status produces no automated change" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-106: accepted degradation

**Status**: DEGRADED-ACCEPTED — operator chose to live with it
**Feature**: openai gpt-5.5-pro slow latency
**Model**: openai:gpt-5.5-pro
**Symptom**: 30s p95 latency on Responses API
**First observed**: 2026-05-09
**Recurrence count**: 1
**Current workaround**: route to streaming
**Upstream issue**: filed-and-declined

### Reading guide

Test fixture.
MD
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]

    run _read_recommended_for "openai" "gpt-5.5-pro"
    [ "$status" -eq 0 ]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"audit"* ]]
    [[ "$output" == *"implementation"* ]]
}

# =============================================================================
# M7: idempotency — running twice produces byte-identical model-config.yaml
# =============================================================================

@test "M7: running twice on same ledger produces byte-identical model-config.yaml (NFR-Rel-3)" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-107: idempotency test

**Status**: RESOLVED-VIA-WORKAROUND
**Feature**: anthropic claude-opus-4-7
**Model**: anthropic:claude-opus-4-7
**Role**: review
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
    local first_hash
    first_hash="$(sha256sum "$BATS_TMP/model-config.yaml" | awk '{print $1}')"

    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]
    local second_hash
    second_hash="$(sha256sum "$BATS_TMP/model-config.yaml" | awk '{print $1}')"

    [[ "$first_hash" == "$second_hash" ]]
}

# =============================================================================
# M8: failure_modes_observed accumulates KF references for OPEN entries
# =============================================================================

@test "M8: failure_modes_observed accumulates KF IDs for OPEN/LATENT entries" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-108: first open

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7
**Symptom**: test
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Test fixture.

## KF-109: second open

**Status**: LATENT
**Model**: anthropic:claude-opus-4-7
**Role**: implementation
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

    run _read_failure_modes "anthropic" "claude-opus-4-7"
    [ "$status" -eq 0 ]
    [[ "$output" == *"KF-108"* ]]
    [[ "$output" == *"KF-109"* ]]
}

# =============================================================================
# M9: audit log emits one entry per (KF, model) decision
# =============================================================================

@test "M9: audit log .run/kf-auto-link.jsonl carries per-decision entries" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-110: audit log emit test

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7
**Symptom**: test
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Test fixture.
MD
    rm -f "$BATS_TMP/kf-auto-link.jsonl"
    run _run_link "$BATS_TMP/kf.md"
    [ "$status" -eq 0 ]
    [[ -f "$BATS_TMP/kf-auto-link.jsonl" ]]
    run grep -c 'KF-110' "$BATS_TMP/kf-auto-link.jsonl"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
