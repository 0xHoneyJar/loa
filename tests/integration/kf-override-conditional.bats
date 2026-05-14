#!/usr/bin/env bats
# =============================================================================
# tests/integration/kf-override-conditional.bats
#
# cycle-109 Sprint 1 T1.6 — SKP-004 conditional precedence for KF-auto-link
# operator overrides (PRD §FR-1.5 IMP-002 hardening; SDD §3.5.1).
#
# Each rejection condition has a fixture; the rejected override must NOT
# preserve the role (KF auto-decision falls through), the stderr must
# carry a `[kf-override-rejected]` warning, and the audit log gains a
# `decision_outcome: rejected:<reason>` entry.
#
# Rejection conditions (T1.6 enforces):
#   C1 effective_until missing
#   C2 effective_until in the past
#   C3 effective_until > now() + 90d
#   C4 kf_references[] empty
#   C5 kf_references[] entry not present in known-failures.md
#   C6 authorized_by not in OPERATORS.md
#   C7 force_retain on OPEN KF without break_glass block
#   C8 break_glass.expiry > now() + 24h
#   C9 break_glass.reason shorter than 16 chars
#   C10 break_glass.audit_event_id missing
#
# Positive control:
#   P1 well-formed non-break-glass override on RESOLVED-VIA-WORKAROUND KF
#
# See tests/integration/kf-override-breakglass.bats for break-glass
# positive-control cases (OPEN KF + valid break_glass = accepted).
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

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kf-override-conditional.XXXXXX")"

    # Fake OPERATORS.md fixture with a single known slug `test-operator`.
    cat > "$BATS_TMP/OPERATORS.md" <<'MD'
---
schema_version: "1.0"
operators:
  - id: test-operator
    display_name: "Test Operator"
    github_handle: test-operator
    git_email: "test-operator@example.com"
    capabilities:
      - dispatch
      - merge
    active_since: "2026-01-01T00:00:00Z"
---

# Test Operators
MD

    export LOA_OPERATORS_FILE="$BATS_TMP/OPERATORS.md"

    # Standard model-config.yaml fixture (v3, two models).
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

# Compute an ISO-8601 timestamp at +/- N days from now.
_iso_days_from_now() {
    "$PYTHON_BIN" - <<PY
import datetime
now = datetime.datetime.now(datetime.timezone.utc)
delta = datetime.timedelta(days=$1)
print((now + delta).isoformat().replace("+00:00", "Z"))
PY
}

_iso_hours_from_now() {
    "$PYTHON_BIN" - <<PY
import datetime
now = datetime.datetime.now(datetime.timezone.utc)
delta = datetime.timedelta(hours=$1)
print((now + delta).isoformat().replace("+00:00", "Z"))
PY
}

# Run kf-auto-link with the per-test override config.
_run_link() {
    "$PYTHON_BIN" "$KF_AUTO_LINK" \
        --known-failures "$BATS_TMP/kf.md" \
        --model-config "$BATS_TMP/model-config.yaml" \
        --loa-config "$BATS_TMP/loa-config.yaml" \
        --audit-log "$BATS_TMP/kf-auto-link.jsonl"
}

# Inspect a model's recommended_for as JSON.
_recommended_for() {
    "$PYTHON_BIN" - <<PY
import json, yaml
cfg = yaml.safe_load(open("$BATS_TMP/model-config.yaml"))
mc = cfg["providers"]["anthropic"]["models"]["claude-opus-4-7"]
print(json.dumps(mc.get("recommended_for", [])))
PY
}

# Standard KF fixture: RESOLVED-VIA-WORKAROUND on opus, role=review.
# Used by C1-C6 + P1 since those reject paths don't depend on KF status.
_write_workaround_kf() {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-400: workaround target

**Status**: RESOLVED-VIA-WORKAROUND
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: test
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Fixture.
MD
}

# OPEN KF fixture for the break-glass-required cases.
_write_open_kf() {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-401: open target

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: test
**First observed**: 2026-05-13
**Recurrence count**: 1
**Current workaround**: N/A
**Upstream issue**: not filed

### Reading guide

Fixture.
MD
}

# =============================================================================
# C1: effective_until MISSING → rejected
# =============================================================================

@test "C1: override missing effective_until is rejected" {
    _write_workaround_kf
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      kf_references: [KF-400]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    # Override rejected → role 'review' must be removed by KF auto-decision.
    run _recommended_for
    [[ "$output" != *"\"review\""* ]]
    # Stderr / audit-log signal the rejection reason.
    [[ "$output" == *""* ]] || grep -q 'rejected.*effective_until\|effective_until.*missing' "$BATS_TMP/kf-auto-link.jsonl" 2>/dev/null
}

# =============================================================================
# C2: effective_until in the past → rejected
# =============================================================================

@test "C2: override with effective_until in the past is rejected" {
    _write_workaround_kf
    local past
    past="$(_iso_days_from_now -1)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$past"
      kf_references: [KF-400]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" != *"\"review\""* ]]
    grep -q 'rejected.*effective_until\|expired\|past' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# C3: effective_until > now() + 90 days → rejected
# =============================================================================

@test "C3: override with effective_until > now()+90d is rejected" {
    _write_workaround_kf
    local far_future
    far_future="$(_iso_days_from_now 120)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$far_future"
      kf_references: [KF-400]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" != *"\"review\""* ]]
    grep -q 'rejected.*effective_until\|effective_until.*exceeds\|90' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# C4: kf_references EMPTY → rejected
# =============================================================================

@test "C4: override with empty kf_references is rejected" {
    _write_workaround_kf
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$future"
      kf_references: []
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" != *"\"review\""* ]]
    grep -q 'rejected.*kf_references\|kf_references.*empty' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# C5: kf_references[] entry not present in known-failures.md → rejected
# =============================================================================

@test "C5: override with unknown kf_references entry is rejected" {
    _write_workaround_kf
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$future"
      kf_references: [KF-999]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" != *"\"review\""* ]]
    grep -q 'rejected.*kf_references\|KF-999\|unknown' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# C6: authorized_by not in OPERATORS.md → rejected
# =============================================================================

@test "C6: override with unknown authorized_by slug is rejected" {
    _write_workaround_kf
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$future"
      kf_references: [KF-400]
      authorized_by: unknown-stranger
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" != *"\"review\""* ]]
    grep -q 'rejected.*authorized_by\|unknown-stranger\|OPERATORS' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# C7: force_retain on OPEN KF without break_glass → rejected
# =============================================================================

@test "C7: force_retain on OPEN KF without break_glass is rejected" {
    _write_open_kf
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$future"
      kf_references: [KF-401]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    # OPEN KF on opus removes ALL roles; override rejected → no recovery.
    [[ "$output" == "[]" ]]
    grep -q 'rejected.*break_glass\|break_glass.*required\|OPEN' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# C8: break_glass.expiry > now()+24h → rejected
# =============================================================================

@test "C8: break_glass with expiry > now()+24h is rejected" {
    _write_open_kf
    local future
    future="$(_iso_days_from_now 30)"
    local long_break
    long_break="$(_iso_hours_from_now 48)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$future"
      kf_references: [KF-401]
      authorized_by: test-operator
      break_glass:
        operator_slug: test-operator
        reason: "production incident — must dispatch on degraded path"
        expiry: "$long_break"
        audit_event_id: "fake-event-hash-for-test-only-not-validated"
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" == "[]" ]]
    grep -q 'rejected.*break_glass.*expiry\|break_glass.*24h\|expiry.*exceeds' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# C9: break_glass.reason < 16 chars → rejected
# =============================================================================

@test "C9: break_glass with reason shorter than 16 chars is rejected" {
    _write_open_kf
    local future
    future="$(_iso_days_from_now 30)"
    local short_break
    short_break="$(_iso_hours_from_now 12)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$future"
      kf_references: [KF-401]
      authorized_by: test-operator
      break_glass:
        operator_slug: test-operator
        reason: "too short"
        expiry: "$short_break"
        audit_event_id: "fake-event-hash-for-test-only-not-validated"
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" == "[]" ]]
    grep -q 'rejected.*break_glass.*reason\|reason.*16' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# C10: break_glass.audit_event_id missing → rejected
# =============================================================================

@test "C10: break_glass with missing audit_event_id is rejected" {
    _write_open_kf
    local future
    future="$(_iso_days_from_now 30)"
    local short_break
    short_break="$(_iso_hours_from_now 12)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test"
      effective_until: "$future"
      kf_references: [KF-401]
      authorized_by: test-operator
      break_glass:
        operator_slug: test-operator
        reason: "production incident — degraded path"
        expiry: "$short_break"
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" == "[]" ]]
    grep -q 'rejected.*audit_event_id\|audit_event_id.*missing' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# P1: well-formed non-break-glass override → accepted (positive control)
# =============================================================================

@test "P1: well-formed override on RESOLVED-VIA-WORKAROUND KF is accepted" {
    _write_workaround_kf
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated cycle-109 test fixture"
      effective_until: "$future"
      kf_references: [KF-400]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    # Override accepted → review retained.
    [[ "$output" == *"\"review\""* ]]
    grep -q 'accepted\|decision_outcome.*accepted' "$BATS_TMP/kf-auto-link.jsonl"
}
