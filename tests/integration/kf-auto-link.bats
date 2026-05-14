#!/usr/bin/env bats
# =============================================================================
# tests/integration/kf-auto-link.bats
#
# cycle-109 Sprint 1 T1.5 — KF-auto-link end-to-end integration.
#
# Sprint AC: "KF-auto-link integration test: seeds a fake KF-NNN
# referencing claude-opus-4-7 with status OPEN, expects
# recommended_for: [] after run; expects failure_modes_observed:
# ['KF-NNN'] populated".
#
# Plus basic operator-override consultation (T1.5 stub; T1.6 will harden
# conditional precedence).
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

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kf-auto-link-e2e.XXXXXX")"

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
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Seed a KF entry referencing claude-opus-4-7 (OPEN). Expect:
#   - recommended_for empties
#   - failure_modes_observed gains the KF id
#   - audit log gains a decision entry
@test "E1: seed OPEN KF for opus → recommended_for [], failure_modes_observed [KF-300]" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-300: e2e open seed

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7
**Symptom**: e2e test
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

E2E fixture.
MD
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
kf_auto_link:
  enabled: true
  overrides: []
YAML

    run "$PYTHON_BIN" "$KF_AUTO_LINK" \
        --known-failures "$BATS_TMP/kf.md" \
        --model-config "$BATS_TMP/model-config.yaml" \
        --loa-config "$BATS_TMP/loa-config.yaml" \
        --audit-log "$BATS_TMP/kf-auto-link.jsonl"
    [ "$status" -eq 0 ]

    "$PYTHON_BIN" - <<PY
import yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
opus = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
assert opus["recommended_for"] == [], f"recommended_for: {opus['recommended_for']}"
assert opus["failure_modes_observed"] == ["KF-300"], f"failure_modes_observed: {opus['failure_modes_observed']}"
print("OK")
PY

    [[ -f "$BATS_TMP/kf-auto-link.jsonl" ]]
    run grep -c 'KF-300' "$BATS_TMP/kf-auto-link.jsonl"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# =============================================================================
# E2: kf_auto_link.enabled: false → no-op (NFR-Rel-3 escape hatch)
# =============================================================================

@test "E2: kf_auto_link.enabled=false skips processing entirely" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-301: would-have-degraded

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7
**Symptom**: test
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

E2E fixture.
MD
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
kf_auto_link:
  enabled: false
  overrides: []
YAML

    run "$PYTHON_BIN" "$KF_AUTO_LINK" \
        --known-failures "$BATS_TMP/kf.md" \
        --model-config "$BATS_TMP/model-config.yaml" \
        --loa-config "$BATS_TMP/loa-config.yaml" \
        --audit-log "$BATS_TMP/kf-auto-link.jsonl"
    [ "$status" -eq 0 ]

    "$PYTHON_BIN" - <<PY
import yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
opus = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
# All roles preserved because auto-link was disabled.
assert opus["recommended_for"] == ["review", "audit", "implementation", "dissent", "arbiter"]
assert opus["failure_modes_observed"] == []
print("OK")
PY
}

# =============================================================================
# E3: operator-override force_retain → KF auto-link does not remove the role
#
# T1.6 hardens this path with SKP-004 conditional precedence: the
# override must declare effective_until ≤ 90d, non-empty
# kf_references[], and an authorized_by slug present in OPERATORS.md
# (LOA_OPERATORS_FILE points at a per-test fixture).
# =============================================================================

@test "E3: well-formed operator-override force_retain preserves role" {
    # Per-test OPERATORS.md fixture (T1.6 SKP-004 ACL resolution).
    cat > "$BATS_TMP/OPERATORS.md" <<'MD'
---
schema_version: "1.0"
operators:
  - id: test-operator
    display_name: "Test Operator"
    github_handle: test-operator
    git_email: "test-operator@example.com"
    capabilities: [dispatch, merge]
    active_since: "2026-01-01T00:00:00Z"
---
MD
    export LOA_OPERATORS_FILE="$BATS_TMP/OPERATORS.md"

    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-302: override target

**Status**: RESOLVED-VIA-WORKAROUND
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: test
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

E2E fixture.
MD
    # effective_until ~30d in the future (within 90d cap).
    local future
    future="$("$PYTHON_BIN" - <<'PY'
import datetime
print((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=30)).isoformat().replace("+00:00", "Z"))
PY
)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 sprint-1 fixture"
      effective_until: "$future"
      kf_references: [KF-302]
      authorized_by: test-operator
YAML

    run "$PYTHON_BIN" "$KF_AUTO_LINK" \
        --known-failures "$BATS_TMP/kf.md" \
        --model-config "$BATS_TMP/model-config.yaml" \
        --loa-config "$BATS_TMP/loa-config.yaml" \
        --audit-log "$BATS_TMP/kf-auto-link.jsonl"
    [ "$status" -eq 0 ]

    "$PYTHON_BIN" - <<PY
import yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
opus = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
assert "review" in opus["recommended_for"], f"review missing: {opus['recommended_for']}"
print("OK")
PY
    unset LOA_OPERATORS_FILE
}
