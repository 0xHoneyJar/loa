#!/usr/bin/env bats
# =============================================================================
# tests/integration/kf-override-breakglass.bats
#
# cycle-109 Sprint 1 T1.6 — KF-override break-glass positive controls
# (PRD §FR-1.5 IMP-002 + SKP-004 closure).
#
# Validates that well-formed break-glass overrides for OPEN KFs ARE
# accepted, with audit-log recording the break-glass usage. T1.6 ships
# basic break-glass acceptance; full L4 signed-trust-event emission is
# wired via cycle-098 graduated-trust integration as a follow-up.
#
# Cases:
#   B1 well-formed break-glass on OPEN KF → role retained + audit record
#   B2 force_retain on LATENT KF without break_glass → accepted
#      (LATENT is NOT treated as CRITICAL — only OPEN status requires
#      break_glass per the PRD IMP-002 hardening)
#   B3 break-glass operator_slug ≠ authorized_by → audit captures both;
#      override still validates because operator_slug is the break-glass
#      authorizer, distinct from the standing override authorizer
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

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/kf-override-breakglass.XXXXXX")"

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
  - id: break-glass-operator
    display_name: "Break-Glass Operator"
    github_handle: break-glass-operator
    git_email: "break-glass@example.com"
    capabilities: [break_glass]
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
_iso_hours_from_now() {
    "$PYTHON_BIN" - <<PY
import datetime
now = datetime.datetime.now(datetime.timezone.utc)
print((now + datetime.timedelta(hours=$1)).isoformat().replace("+00:00", "Z"))
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
# B1: well-formed break-glass on OPEN KF → role retained + audit recorded
# =============================================================================

@test "B1: well-formed break-glass on OPEN KF retains role + audit record" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-500: open-target break-glass test

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: production-blocking
**First observed**: 2026-05-13
**Recurrence count**: 3
**Current workaround**: none
**Upstream issue**: not filed

### Reading guide

Break-glass test.
MD
    local future
    future="$(_iso_days_from_now 30)"
    local break_expiry
    break_expiry="$(_iso_hours_from_now 12)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "production-incident operator-validated break-glass"
      effective_until: "$future"
      kf_references: [KF-500]
      authorized_by: test-operator
      break_glass:
        operator_slug: break-glass-operator
        reason: "production incident — review path must dispatch"
        expiry: "$break_expiry"
        audit_event_id: "ed25519-sig-9f23e8a4c1d7b2"
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    # OPEN KF would have stripped all roles; break-glass retains 'review'.
    [[ "$output" == *"\"review\""* ]]
    # Other roles still removed (OPEN strips them; only 'review' is forced
    # back by the override).
    [[ "$output" != *"\"audit\""* ]]
    grep -q 'break_glass\|accepted' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# B2: force_retain on LATENT KF without break_glass → accepted
#
# LATENT status removes only the named role (NOT all roles like OPEN).
# Per PRD §IMP-002, break_glass is required only when the override
# targets an OPEN KF — LATENT is a softer signal and the standing
# override path (without break-glass) is the correct shape.
# =============================================================================

@test "B2: force_retain on LATENT KF without break_glass is accepted" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-501: latent target

**Status**: LATENT
**Model**: anthropic:claude-opus-4-7
**Role**: dissent
**Symptom**: edge-case latency under reasoning-budget exhaustion
**First observed**: 2026-05-12
**Recurrence count**: 1
**Current workaround**: raise max_tokens
**Upstream issue**: not filed

### Reading guide

Latent test fixture.
MD
    local future
    future="$(_iso_days_from_now 30)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: dissent
      decision: force_retain
      reason: "operator-validated latency budget tuning"
      effective_until: "$future"
      kf_references: [KF-501]
      authorized_by: test-operator
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" == *"\"dissent\""* ]]
    grep -q 'accepted\|decision_outcome.*accepted' "$BATS_TMP/kf-auto-link.jsonl"
}

# =============================================================================
# B3: break_glass.operator_slug different from authorized_by → both audited
#
# Authorized_by is the standing-override authority; operator_slug inside
# break_glass is the break-glass authority. They may differ (a senior
# operator standing-authorizes the override; an on-call operator
# break-glasses the OPEN KF). Both must resolve via OPERATORS.md.
# =============================================================================

@test "B3: break-glass operator_slug distinct from authorized_by is accepted" {
    cat > "$BATS_TMP/kf.md" <<'MD'
# Known Failures

## KF-502: dual-authority test

**Status**: OPEN
**Model**: anthropic:claude-opus-4-7
**Role**: review
**Symptom**: regression
**First observed**: 2026-05-13
**Recurrence count**: 2
**Current workaround**: chunking
**Upstream issue**: not filed

### Reading guide

Dual-authority test.
MD
    local future
    future="$(_iso_days_from_now 30)"
    local break_expiry
    break_expiry="$(_iso_hours_from_now 6)"
    cat > "$BATS_TMP/loa-config.yaml" <<YAML
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator-validated standing override"
      effective_until: "$future"
      kf_references: [KF-502]
      authorized_by: test-operator
      break_glass:
        operator_slug: break-glass-operator
        reason: "incident response, dispatching review path"
        expiry: "$break_expiry"
        audit_event_id: "ed25519-deadbeef-cafebabe"
YAML
    run _run_link
    [ "$status" -eq 0 ]
    run _recommended_for
    [[ "$output" == *"\"review\""* ]]
    # Audit log mentions both authorizers.
    grep -q 'test-operator' "$BATS_TMP/kf-auto-link.jsonl"
    grep -q 'break-glass-operator' "$BATS_TMP/kf-auto-link.jsonl"
}
