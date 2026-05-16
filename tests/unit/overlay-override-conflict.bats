#!/usr/bin/env bats
# =============================================================================
# tests/unit/overlay-override-conflict.bats
#
# cycle-109 Sprint 1 T1.9 — overlay/override conflict lint
# (SDD §3.5.2). When `.loa.config.yaml::model_overlay.providers.<p>.models.<m>.recommended_for`
# (L1 layer per the §3.5.2 precedence) disagrees with `kf_auto_link.overrides[]`
# (L3 layer) for the same (model, role), the lint surfaces the conflict
# on stderr and exits non-zero so CI gates a contradictory operator
# config before it reaches cheval.
#
# Conflict shapes:
#   - overlay includes role X + override declares force_remove for X
#   - overlay excludes role X + override declares force_retain for X
# Non-conflict shapes:
#   - overlay matches override's direction
#   - overlay silent on role X (override is the sole decision)
#   - no overlay / no overrides at all
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LINT="$PROJECT_ROOT/tools/lint-overlay-override-conflict.py"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/overlay-override-conflict.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

_run_lint() {
    "$PYTHON_BIN" "$LINT" --config "$BATS_TMP/loa-config.yaml"
}

# =============================================================================
# L1: empty / no overrides → exit 0
# =============================================================================

@test "L1: empty config (no overlay, no overrides) exits 0" {
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
kf_auto_link:
  enabled: true
  overrides: []
YAML
    run _run_lint
    [ "$status" -eq 0 ]
}

# =============================================================================
# L2: overlay-only (no overrides) → exit 0
# =============================================================================

@test "L2: overlay set with no overrides exits 0" {
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
model_overlay:
  providers:
    anthropic:
      models:
        claude-opus-4-7:
          recommended_for: [review, audit]
kf_auto_link:
  enabled: true
  overrides: []
YAML
    run _run_lint
    [ "$status" -eq 0 ]
}

# =============================================================================
# L3: overlay INCLUDES role + override force_remove same role → CONFLICT
# =============================================================================

@test "L3: overlay includes role + override force_remove same role surfaces conflict" {
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
model_overlay:
  providers:
    anthropic:
      models:
        claude-opus-4-7:
          recommended_for: [review, audit, implementation]
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_remove
      reason: "operator chose to remove review"
      effective_until: "2026-08-01T00:00:00Z"
      kf_references: [KF-001]
      authorized_by: test-operator
YAML
    run _run_lint
    [ "$status" -ne 0 ]
    [[ "$output" == *"conflict"* ]] || [[ "$output" == *"CONFLICT"* ]]
    [[ "$output" == *"claude-opus-4-7"* ]]
    [[ "$output" == *"review"* ]]
}

# =============================================================================
# L4: overlay EXCLUDES role + override force_retain same role → CONFLICT
# =============================================================================

@test "L4: overlay excludes role + override force_retain same role surfaces conflict" {
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
model_overlay:
  providers:
    anthropic:
      models:
        claude-opus-4-7:
          recommended_for: [audit, implementation]
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator wants review preserved"
      effective_until: "2026-08-01T00:00:00Z"
      kf_references: [KF-002]
      authorized_by: test-operator
YAML
    run _run_lint
    [ "$status" -ne 0 ]
    [[ "$output" == *"conflict"* ]] || [[ "$output" == *"CONFLICT"* ]]
    [[ "$output" == *"review"* ]]
}

# =============================================================================
# L5: overlay AGREES with override direction → no conflict
# =============================================================================

@test "L5: overlay includes role + override force_retain same role does NOT conflict" {
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
model_overlay:
  providers:
    anthropic:
      models:
        claude-opus-4-7:
          recommended_for: [review, audit]
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator wants review preserved"
      effective_until: "2026-08-01T00:00:00Z"
      kf_references: [KF-001]
      authorized_by: test-operator
YAML
    run _run_lint
    [ "$status" -eq 0 ]
}

# =============================================================================
# L6: overlay silent on role + override declares it → no conflict
#     (override is the sole decision authority)
# =============================================================================

@test "L6: overlay omits target model + override declares role does NOT conflict" {
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
model_overlay:
  providers:
    openai:
      models:
        gpt-5.5-pro:
          recommended_for: [review]
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_remove
      reason: "operator chose to remove review"
      effective_until: "2026-08-01T00:00:00Z"
      kf_references: [KF-001]
      authorized_by: test-operator
YAML
    run _run_lint
    [ "$status" -eq 0 ]
}

# =============================================================================
# L7: --json output emits a structured report on stdout
# =============================================================================

@test "L7: --json emits structured report with conflict array" {
    cat > "$BATS_TMP/loa-config.yaml" <<'YAML'
model_overlay:
  providers:
    anthropic:
      models:
        claude-opus-4-7:
          recommended_for: [audit]
kf_auto_link:
  enabled: true
  overrides:
    - model: claude-opus-4-7
      role: review
      decision: force_retain
      reason: "operator wants review preserved"
      effective_until: "2026-08-01T00:00:00Z"
      kf_references: [KF-002]
      authorized_by: test-operator
YAML
    run "$PYTHON_BIN" "$LINT" --config "$BATS_TMP/loa-config.yaml" --json
    [ "$status" -ne 0 ]
    [[ "$output" == *"conflicts"* ]]
    [[ "$output" == *"claude-opus-4-7"* ]]
    [[ "$output" == *"review"* ]]
}
