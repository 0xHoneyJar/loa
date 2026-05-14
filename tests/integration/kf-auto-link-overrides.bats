#!/usr/bin/env bats
# =============================================================================
# tests/integration/kf-auto-link-overrides.bats
#
# cycle-109 Sprint 1 T1.6 — KF-auto-link operator-override BASIC coverage
# (PRD §FR-1.5 IMP-002 — precedence + expiry + CI block on missing
# authorized_by).
#
# Conditional precedence rejection paths live in
# tests/integration/kf-override-conditional.bats; this file covers the
# happy-path semantics that IMP-002 promises:
#
#   O1 force_retain preserves a role that the KF auto-decision would
#      have removed (RESOLVED-VIA-WORKAROUND target)
#   O2 force_remove removes a role that the KF auto-decision would have
#      kept (RESOLVED target with override pulling 'arbiter')
#   O3 expiry honored on next dispatch — re-running with an
#      effective_until in the past flips the override OFF (NFR-Rel-3
#      idempotency: the same input + same clock state produces the same
#      output)
#   O4 multiple overrides for the same model — each role evaluated
#      independently
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

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kf-auto-link-overrides.XXXXXX")"

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

# Test Operators
MD
    export LOA_OPERATORS_FILE="$BATS_TMP/OPERATORS.md"

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
    unset LOA_OPERATORS_FILE
}

_iso_days_from_now() {
    "$PYTHON_BIN" - <<PY
import datetime
now = datetime.datetime.now(datetime.timezone.utc)
print((now + datetime.timedelta(days=$1)).isoformat().replace("+00:00", "Z"))
PY
}

_run_link() {
    "$PYTHON_BIN" "$KF_AUTO_LINK" \
        --known-failures "$BATS_TMP/kf.md" \
        --model-config "$BATS_TMP/model-config.yaml" \
        --loa-config "$BATS_TMP/loa-config.yaml" \
        --audit-log "$BATS_TMP/kf-auto-link.jsonl"
}

_recommended_for() {
    "$PYTHON_BIN" - <<PY
import json, yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
mc = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
print(json.dumps(mc.get("recommended_for", [])))
PY
}

# =============================================================================
# O1: force_retain preserves role that RESOLVED-VIA-WORKAROUND would remove
# =============================================================================

@test "O1: force_retain preserves role that KF auto-decision would remove" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-600: workaround target

**Status**: RESOLVED-VIA-WORKAROUND
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: empty content
**First observed**: 2026-05-12
**Recurrence count**: 2
**Current workaround**: chunking
**Upstream issue**: not filed

### Reading guide

Fixture.
MD
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 standing override"
      effective_until: "$future"
      kf_references: [KF-600]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" == *"\"review\""* ]]
}

# =============================================================================
# O2: force_remove removes role that KF auto-decision would have kept
# =============================================================================

@test "O2: force_remove removes role that KF auto-decision would have kept" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-601: resolved target

**Status**: RESOLVED
**Model**: anthropic:claude-opus-4-7
**Symptom**: addressed
**First observed**: 2026-05-12
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: closed

### Reading guide

Fixture.
MD
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: arbiter
      decision: force_remove
      reason: "operator removes arbiter role for separation of concerns"
      effective_until: "$future"
      kf_references: [KF-601]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" != *"\"arbiter\""* ]]
    # Other roles still present.
    [[ "$output" == *"\"review\""* ]]
    [[ "$output" == *"\"audit\""* ]]
}

# =============================================================================
# O3: expired override stops taking effect on re-run
# =============================================================================

@test "O3: override with effective_until in the past does not apply (idempotent)" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-602: workaround target

**Status**: RESOLVED-VIA-WORKAROUND
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: empty content
**First observed**: 2026-05-12
**Recurrence count**: 2
**Current workaround**: chunking
**Upstream issue**: not filed

### Reading guide

Fixture.
MD
    local past
    past="$(_iso_days_from_now -7)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated override that has since expired"
      effective_until: "$past"
      kf_references: [KF-602]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    # Expired → KF auto-decision applies → review removed.
    [[ "$output" != *"\"review\""* ]]
}

# =============================================================================
# O4: multiple overrides for the same model — independent evaluation
# =============================================================================

@test "O4: multiple overrides on the same model are evaluated independently" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-603: workaround target

**Status**: RESOLVED-VIA-WORKAROUND
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: empty content
**First observed**: 2026-05-12
**Recurrence count**: 2
**Current workaround**: chunking
**Upstream issue**: not filed

### Reading guide

Fixture.
MD
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated retain review"
      effective_until: "$future"
      kf_references: [KF-603]
      authorized_by: test-operator
    - model: claude-opus-4-7
      role: arbiter
      decision: force_remove
      reason: "operator-validated remove arbiter"
      effective_until: "$future"
      kf_references: [KF-603]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    # 'review' retained by override (would have been removed by KF).
    [[ "$output" == *"\"review\""* ]]
    # 'arbiter' removed by override.
    [[ "$output" != *"\"arbiter\""* ]]
    # 'audit' / 'implementation' / 'dissent' untouched (not in any override or KF).
    [[ "$output" == *"\"audit\""* ]]
    [[ "$output" == *"\"implementation\""* ]]
    [[ "$output" == *"\"dissent\""* ]]
}
