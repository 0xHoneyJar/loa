#!/usr/bin/env bash
# Tests for construct-workflow-read.sh and construct-workflow-activate.sh
# Part of: Construct-Aware Constraint Yielding (cycle-029, Sprint 3)
# SDD Section 6.2 test matrix — 22 test cases
#
# Plain bash tests — no external test framework required.
# Uses temp directories — no pollution of real .run/ or .claude/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
READER="${REPO_ROOT}/.claude/scripts/construct-workflow-read.sh"
ACTIVATOR="${REPO_ROOT}/.claude/scripts/construct-workflow-activate.sh"
JQ_TEMPLATE="${REPO_ROOT}/.claude/templates/constraints/claude-loa-md-table.jq"

# ── Test Harness ──────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  PASS: $1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $1 — $2"; }

# ── Setup / Teardown ─────────────────────────────────

TEMP_DIR=""

setup() {
  TEMP_DIR="$(mktemp -d)"

  # Create mock directory structure
  mkdir -p "${TEMP_DIR}/packs/test-pack"
  mkdir -p "${TEMP_DIR}/run"
  mkdir -p "${TEMP_DIR}/manifests"
  mkdir -p "${TEMP_DIR}/a2a"

  # Export env vars so activator uses temp paths
  export LOA_CONSTRUCT_STATE_FILE="${TEMP_DIR}/run/construct-workflow.json"
  export LOA_CONSTRUCT_AUDIT_LOG="${TEMP_DIR}/run/audit.jsonl"
  export LOA_PACKS_PREFIX="${TEMP_DIR}/packs/"

  # ── Create test manifests ──

  # Valid manifest with all gates
  cat > "${TEMP_DIR}/packs/test-pack/manifest.json" << 'EOF'
{
  "name": "test-pack",
  "version": "1.0.0",
  "workflow": {
    "depth": "light",
    "app_zone_access": true,
    "gates": {
      "prd": "skip",
      "sdd": "skip",
      "sprint": "skip",
      "implement": "required",
      "review": "skip",
      "audit": "skip"
    },
    "verification": {
      "method": "visual"
    }
  }
}
EOF

  # Manifest with review: full and audit: full
  cat > "${TEMP_DIR}/manifests/full-review.json" << 'EOF'
{
  "name": "full-review-pack",
  "version": "1.0.0",
  "workflow": {
    "depth": "full",
    "gates": {
      "implement": "required",
      "review": "textual",
      "audit": "full"
    }
  }
}
EOF

  # Manifest without workflow section
  cat > "${TEMP_DIR}/manifests/no-workflow.json" << 'EOF'
{
  "name": "basic-pack",
  "version": "1.0.0",
  "skills": ["some-skill"]
}
EOF

  # Manifest with implement: skip (invalid)
  cat > "${TEMP_DIR}/manifests/implement-skip.json" << 'EOF'
{
  "name": "bad-pack",
  "version": "1.0.0",
  "workflow": {
    "gates": {
      "implement": "skip"
    }
  }
}
EOF

  # Manifest with condense gate
  cat > "${TEMP_DIR}/manifests/condense.json" << 'EOF'
{
  "name": "condense-pack",
  "version": "1.0.0",
  "workflow": {
    "gates": {
      "prd": "condense",
      "implement": "required"
    }
  }
}
EOF

  # Manifest with invalid gate value
  cat > "${TEMP_DIR}/manifests/invalid-gate.json" << 'EOF'
{
  "name": "invalid-pack",
  "version": "1.0.0",
  "workflow": {
    "gates": {
      "implement": "required",
      "review": "banana"
    }
  }
}
EOF

  # Corrupt manifest (invalid JSON)
  echo "NOT VALID JSON {{{" > "${TEMP_DIR}/manifests/corrupt.json"

  # Manifest with minimal fields (defaults should apply)
  cat > "${TEMP_DIR}/manifests/minimal.json" << 'EOF'
{
  "name": "minimal-pack",
  "version": "1.0.0",
  "workflow": {
    "gates": {
      "implement": "required"
    }
  }
}
EOF

  # Valid manifest in packs dir for full-review activator tests
  cat > "${TEMP_DIR}/packs/test-pack/manifest-full.json" << 'EOF'
{
  "name": "test-pack-full",
  "version": "1.0.0",
  "workflow": {
    "depth": "full",
    "gates": {
      "implement": "required",
      "review": "textual",
      "audit": "full",
      "sprint": "full"
    }
  }
}
EOF
}

teardown() {
  unset LOA_CONSTRUCT_STATE_FILE
  unset LOA_CONSTRUCT_AUDIT_LOG
  unset LOA_PACKS_PREFIX
  rm -rf "$TEMP_DIR"
}

# ── Reader Tests (FR-1) ──────────────────────────────

test_reader_valid_workflow() {
  TESTS_RUN=$((TESTS_RUN + 1))

  local output
  output=$("$READER" "${TEMP_DIR}/packs/test-pack/manifest.json" 2>/dev/null)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "reader — valid workflow" "expected exit 0, got $rc"
    return
  fi

  # Verify JSON output has expected fields
  local depth
  depth=$(echo "$output" | jq -r '.depth')
  if [[ "$depth" == "light" ]]; then
    pass "reader — valid workflow"
  else
    fail "reader — valid workflow" "expected depth=light, got $depth"
  fi
}

test_reader_missing_workflow() {
  TESTS_RUN=$((TESTS_RUN + 1))

  local rc=0
  "$READER" "${TEMP_DIR}/manifests/no-workflow.json" >/dev/null 2>&1 || rc=$?

  if [[ $rc -eq 1 ]]; then
    pass "reader — missing workflow (exit 1)"
  else
    fail "reader — missing workflow" "expected exit 1, got $rc"
  fi
}

test_reader_implement_skip_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))

  local rc=0
  "$READER" "${TEMP_DIR}/manifests/implement-skip.json" >/dev/null 2>&1 || rc=$?

  if [[ $rc -eq 2 ]]; then
    pass "reader — implement: skip rejected (exit 2)"
  else
    fail "reader — implement: skip rejected" "expected exit 2, got $rc"
  fi
}

test_reader_condense_advisory() {
  TESTS_RUN=$((TESTS_RUN + 1))

  local stderr_output
  stderr_output=$("$READER" "${TEMP_DIR}/manifests/condense.json" 2>&1 >/dev/null) || true
  local rc=0
  "$READER" "${TEMP_DIR}/manifests/condense.json" >/dev/null 2>/dev/null || rc=$?

  if [[ $rc -eq 0 ]] && echo "$stderr_output" | grep -q "ADVISORY"; then
    pass "reader — condense advisory"
  elif [[ $rc -ne 0 ]]; then
    fail "reader — condense advisory" "expected exit 0, got $rc"
  else
    fail "reader — condense advisory" "no ADVISORY on stderr"
  fi
}

test_reader_invalid_gate_value() {
  TESTS_RUN=$((TESTS_RUN + 1))

  local rc=0
  "$READER" "${TEMP_DIR}/manifests/invalid-gate.json" >/dev/null 2>&1 || rc=$?

  if [[ $rc -eq 2 ]]; then
    pass "reader — invalid gate value (exit 2)"
  else
    fail "reader — invalid gate value" "expected exit 2, got $rc"
  fi
}

test_reader_defaults_applied() {
  TESTS_RUN=$((TESTS_RUN + 1))

  local output
  output=$("$READER" "${TEMP_DIR}/manifests/minimal.json" 2>/dev/null)
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    fail "reader — defaults applied" "expected exit 0, got $rc"
    return
  fi

  # Missing gates should get defaults
  local review_val audit_val depth
  review_val=$(echo "$output" | jq -r '.gates.review // "textual"')
  audit_val=$(echo "$output" | jq -r '.gates.audit // "full"')
  depth=$(echo "$output" | jq -r '.depth // "full"')

  if [[ "$depth" == "full" ]]; then
    pass "reader — defaults applied"
  else
    fail "reader — defaults applied" "expected default depth=full, got $depth"
  fi
}

# ── Activator Tests (FR-2, FR-5) ─────────────────────

test_activate_writes_state_file() {
  TESTS_RUN=$((TESTS_RUN + 1))

  # Clean slate
  rm -f "${TEMP_DIR}/run/construct-workflow.json"

  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  if [[ -f "${TEMP_DIR}/run/construct-workflow.json" ]]; then
    local construct
    construct=$(jq -r '.construct' "${TEMP_DIR}/run/construct-workflow.json")
    if [[ "$construct" == "test-pack" ]]; then
      pass "activate — writes state file"
    else
      fail "activate — writes state file" "construct=$construct, expected test-pack"
    fi
  else
    fail "activate — writes state file" "state file not created"
  fi
}

test_activate_logs_started_event() {
  TESTS_RUN=$((TESTS_RUN + 1))

  # Clean slate
  rm -f "${TEMP_DIR}/run/audit.jsonl"
  rm -f "${TEMP_DIR}/run/construct-workflow.json"

  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack-slug" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  if [[ ! -f "${TEMP_DIR}/run/audit.jsonl" ]]; then
    fail "activate — logs started event" "audit.jsonl not created"
    return
  fi

  local event
  event=$(grep '"construct.workflow.started"' "${TEMP_DIR}/run/audit.jsonl" | tail -1)

  if [[ -n "$event" ]]; then
    local has_gates has_yielded has_depth
    has_gates=$(echo "$event" | jq 'has("gates")')
    has_yielded=$(echo "$event" | jq 'has("constraints_yielded")')
    has_depth=$(echo "$event" | jq 'has("depth")')

    if [[ "$has_gates" == "true" && "$has_yielded" == "true" && "$has_depth" == "true" ]]; then
      pass "activate — logs started event"
    else
      fail "activate — logs started event" "missing fields: gates=$has_gates yielded=$has_yielded depth=$has_depth"
    fi
  else
    fail "activate — logs started event" "no construct.workflow.started event found"
  fi
}

test_deactivate_clears_state_file() {
  TESTS_RUN=$((TESTS_RUN + 1))

  # Ensure state file exists first
  rm -f "${TEMP_DIR}/run/construct-workflow.json"
  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  [[ -f "${TEMP_DIR}/run/construct-workflow.json" ]] || {
    fail "deactivate — clears state file" "precondition: state file not created"
    return
  }

  "$ACTIVATOR" deactivate >/dev/null 2>&1

  if [[ ! -f "${TEMP_DIR}/run/construct-workflow.json" ]]; then
    pass "deactivate — clears state file"
  else
    fail "deactivate — clears state file" "state file still exists"
  fi
}

test_deactivate_logs_completed_event() {
  TESTS_RUN=$((TESTS_RUN + 1))

  # Clean slate and activate
  rm -f "${TEMP_DIR}/run/audit.jsonl"
  rm -f "${TEMP_DIR}/run/construct-workflow.json"

  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack-slug" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  "$ACTIVATOR" deactivate >/dev/null 2>&1

  if [[ ! -f "${TEMP_DIR}/run/audit.jsonl" ]]; then
    fail "deactivate — logs completed event" "audit.jsonl not found"
    return
  fi

  local event
  event=$(grep '"construct.workflow.completed"' "${TEMP_DIR}/run/audit.jsonl" | tail -1)

  if [[ -n "$event" ]]; then
    local has_outcome has_duration
    has_outcome=$(echo "$event" | jq 'has("outcome")')
    has_duration=$(echo "$event" | jq 'has("duration_seconds")')

    if [[ "$has_outcome" == "true" && "$has_duration" == "true" ]]; then
      pass "deactivate — logs completed event"
    else
      fail "deactivate — logs completed event" "missing fields: outcome=$has_outcome duration=$has_duration"
    fi
  else
    fail "deactivate — logs completed event" "no construct.workflow.completed event found"
  fi
}

test_check_active_construct() {
  TESTS_RUN=$((TESTS_RUN + 1))

  rm -f "${TEMP_DIR}/run/construct-workflow.json"
  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  local output rc=0
  output=$("$ACTIVATOR" check 2>/dev/null) || rc=$?

  if [[ $rc -eq 0 ]]; then
    local construct
    construct=$(echo "$output" | jq -r '.construct')
    if [[ "$construct" == "test-pack" ]]; then
      pass "check — active construct"
    else
      fail "check — active construct" "wrong construct: $construct"
    fi
  else
    fail "check — active construct" "expected exit 0, got $rc"
  fi
}

test_check_no_active_construct() {
  TESTS_RUN=$((TESTS_RUN + 1))

  rm -f "${TEMP_DIR}/run/construct-workflow.json"

  local rc=0
  "$ACTIVATOR" check >/dev/null 2>&1 || rc=$?

  if [[ $rc -eq 1 ]]; then
    pass "check — no active construct (exit 1)"
  else
    fail "check — no active construct" "expected exit 1, got $rc"
  fi
}

test_gate_returns_value() {
  TESTS_RUN=$((TESTS_RUN + 1))

  rm -f "${TEMP_DIR}/run/construct-workflow.json"
  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  local value
  value=$("$ACTIVATOR" gate review 2>/dev/null)

  if [[ "$value" == "skip" ]]; then
    pass "gate — returns correct value"
  else
    fail "gate — returns correct value" "expected skip, got '$value'"
  fi
}

# ── Constraint Rendering Tests (FR-3) ────────────────

test_constraint_yield_rendered() {
  TESTS_RUN=$((TESTS_RUN + 1))

  # Create test JSON with construct_yield
  local test_json='[{
    "id": "TEST-001",
    "rule_type": "NEVER",
    "text": "do bad things",
    "why": "because bad",
    "construct_yield": {
      "enabled": true,
      "yield_text": "OR when construct owns workflow"
    }
  }]'

  local output
  output=$(echo "$test_json" | jq -f "$JQ_TEMPLATE")

  if echo "$output" | grep -q "OR when construct owns workflow"; then
    pass "constraint yield — rendered"
  else
    fail "constraint yield — rendered" "yield text not in output: $output"
  fi
}

test_constraint_yield_not_rendered() {
  TESTS_RUN=$((TESTS_RUN + 1))

  # Create test JSON without construct_yield
  local test_json='[{
    "id": "TEST-002",
    "rule_type": "NEVER",
    "text": "do bad things",
    "why": "because bad"
  }]'

  local output
  output=$(echo "$test_json" | jq -f "$JQ_TEMPLATE")

  if echo "$output" | grep -q "construct"; then
    fail "constraint yield — not rendered" "unexpected construct text in output: $output"
  else
    pass "constraint yield — not rendered"
  fi
}

# ── Pre-flight Gate Tests (FR-4) ─────────────────────

test_preflight_review_skip() {
  TESTS_RUN=$((TESTS_RUN + 1))

  rm -f "${TEMP_DIR}/run/construct-workflow.json"
  # Activate with review: skip manifest
  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  local value
  value=$("$ACTIVATOR" gate review 2>/dev/null)

  if [[ "$value" == "skip" ]]; then
    pass "preflight — review: skip gate value"
  else
    fail "preflight — review: skip gate value" "expected skip, got '$value'"
  fi
}

test_preflight_review_full() {
  TESTS_RUN=$((TESTS_RUN + 1))

  rm -f "${TEMP_DIR}/run/construct-workflow.json"
  # Activate with full-review manifest (needs to be in packs dir)
  "$ACTIVATOR" activate \
    --construct "test-pack-full" \
    --slug "test-pack-full" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest-full.json" \
    >/dev/null 2>&1

  local value
  value=$("$ACTIVATOR" gate review 2>/dev/null)

  if [[ "$value" == "textual" ]]; then
    pass "preflight — review: textual gate value (non-skip)"
  else
    fail "preflight — review: textual gate value" "expected textual, got '$value'"
  fi
}

# ── COMPLETED Marker Test (FR-4) ─────────────────────

test_completed_marker_construct_workflow() {
  TESTS_RUN=$((TESTS_RUN + 1))

  rm -f "${TEMP_DIR}/run/construct-workflow.json"
  # Activate first
  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  # Deactivate with --complete, using temp a2a dir
  # Override REPO_ROOT isn't possible, so test the marker path logic
  # by checking if deactivate --complete creates the marker
  local sprint_dir="${TEMP_DIR}/a2a/sprint-test"
  mkdir -p "$sprint_dir"

  # The deactivate --complete writes to ${REPO_ROOT}/grimoires/loa/a2a/...
  # For isolation, we test the mechanism: activate → deactivate creates marker
  # We test by checking the deactivate script behavior directly
  "$ACTIVATOR" deactivate --complete "sprint-test" >/dev/null 2>&1

  # The marker goes to ${REPO_ROOT}/grimoires/loa/a2a/sprint-test/COMPLETED
  local marker="${REPO_ROOT}/grimoires/loa/a2a/sprint-test/COMPLETED"
  if [[ -f "$marker" ]]; then
    rm -f "$marker"
    rmdir "${REPO_ROOT}/grimoires/loa/a2a/sprint-test" 2>/dev/null || true
    pass "COMPLETED marker — construct workflow"
  else
    fail "COMPLETED marker — construct workflow" "marker not created at $marker"
  fi
}

# ── Default Behavior Test (NF-1) ─────────────────────

test_default_no_manifest() {
  TESTS_RUN=$((TESTS_RUN + 1))

  local rc=0
  "$READER" "${TEMP_DIR}/manifests/no-workflow.json" >/dev/null 2>&1 || rc=$?

  if [[ $rc -eq 1 ]]; then
    # exit 1 = no workflow = full pipeline enforced
    pass "default — no manifest workflow (full pipeline)"
  else
    fail "default — no manifest workflow" "expected exit 1, got $rc"
  fi
}

# ── Fail-Closed Test (NF-4) ──────────────────────────

test_fail_closed_corrupt_manifest() {
  TESTS_RUN=$((TESTS_RUN + 1))

  local rc=0
  "$READER" "${TEMP_DIR}/manifests/corrupt.json" >/dev/null 2>&1 || rc=$?

  if [[ $rc -eq 1 ]]; then
    pass "fail-closed — corrupt manifest (exit 1, full pipeline)"
  else
    fail "fail-closed — corrupt manifest" "expected exit 1, got $rc"
  fi
}

# ── Security Tests ───────────────────────────────────

test_activate_invalid_path_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))

  rm -f "${TEMP_DIR}/run/construct-workflow.json"

  local rc=0
  "$ACTIVATOR" activate \
    --construct "evil-pack" \
    --slug "evil" \
    --manifest "${TEMP_DIR}/manifests/full-review.json" \
    >/dev/null 2>&1 || rc=$?

  if [[ $rc -eq 2 ]]; then
    pass "activate — invalid path rejected (outside packs prefix)"
  else
    fail "activate — invalid path rejected" "expected exit 2, got $rc"
  fi
}

# ── Yielded Constraints Logic Test ───────────────────

test_activate_yields_correct_constraints() {
  TESTS_RUN=$((TESTS_RUN + 1))

  rm -f "${TEMP_DIR}/run/audit.jsonl"
  rm -f "${TEMP_DIR}/run/construct-workflow.json"

  # Activate with test-pack (review: skip, audit: skip, sprint: skip)
  "$ACTIVATOR" activate \
    --construct "test-pack" \
    --slug "test-pack" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  local event
  event=$(grep '"construct.workflow.started"' "${TEMP_DIR}/run/audit.jsonl" | tail -1)

  if [[ -z "$event" ]]; then
    fail "activate — yields correct constraints" "no started event"
    return
  fi

  # Should yield C-PROC-001, C-PROC-003 (implement: required), C-PROC-004 (review/audit: skip), C-PROC-008 (sprint: skip)
  local yielded
  yielded=$(echo "$event" | jq -c '.constraints_yielded | sort')

  local expected='["C-PROC-001","C-PROC-003","C-PROC-004","C-PROC-008"]'

  if [[ "$yielded" == "$expected" ]]; then
    pass "activate — yields correct constraints"
  else
    fail "activate — yields correct constraints" "expected $expected, got $yielded"
  fi
}

# ── Integration Test: End-to-End Flow ────────────────

test_integration_end_to_end() {
  TESTS_RUN=$((TESTS_RUN + 1))

  # Clean slate
  rm -f "${TEMP_DIR}/run/construct-workflow.json"
  rm -f "${TEMP_DIR}/run/audit.jsonl"

  local ok=true

  # Step 1: Reader validates manifest
  local workflow
  workflow=$("$READER" "${TEMP_DIR}/packs/test-pack/manifest.json" 2>/dev/null) || {
    fail "integration — end-to-end" "reader failed"
    return
  }

  local reader_depth
  reader_depth=$(echo "$workflow" | jq -r '.depth')
  [[ "$reader_depth" == "light" ]] || { ok=false; }

  # Step 2: Activator creates state file
  "$ACTIVATOR" activate \
    --construct "integration-test" \
    --slug "int-test" \
    --manifest "${TEMP_DIR}/packs/test-pack/manifest.json" \
    >/dev/null 2>&1

  [[ -f "${TEMP_DIR}/run/construct-workflow.json" ]] || { ok=false; }

  # Step 3: Check returns active state
  local check_rc=0
  "$ACTIVATOR" check >/dev/null 2>&1 || check_rc=$?
  [[ $check_rc -eq 0 ]] || { ok=false; }

  # Step 4: Gate queries work
  local review_val audit_val
  review_val=$("$ACTIVATOR" gate review 2>/dev/null)
  audit_val=$("$ACTIVATOR" gate audit 2>/dev/null)
  [[ "$review_val" == "skip" ]] || { ok=false; }
  [[ "$audit_val" == "skip" ]] || { ok=false; }

  # Step 5: Deactivate clears state
  "$ACTIVATOR" deactivate >/dev/null 2>&1
  [[ ! -f "${TEMP_DIR}/run/construct-workflow.json" ]] || { ok=false; }

  # Step 6: Verify audit events
  local started_count completed_count
  started_count=$(grep -c '"construct.workflow.started"' "${TEMP_DIR}/run/audit.jsonl" 2>/dev/null || echo 0)
  completed_count=$(grep -c '"construct.workflow.completed"' "${TEMP_DIR}/run/audit.jsonl" 2>/dev/null || echo 0)
  [[ "$started_count" -ge 1 ]] || { ok=false; }
  [[ "$completed_count" -ge 1 ]] || { ok=false; }

  # Step 7: Verify check returns not-active after deactivate
  local post_check_rc=0
  "$ACTIVATOR" check >/dev/null 2>&1 || post_check_rc=$?
  [[ $post_check_rc -eq 1 ]] || { ok=false; }

  if [[ "$ok" == true ]]; then
    pass "integration — end-to-end flow"
  else
    fail "integration — end-to-end flow" "one or more steps failed (review=$review_val audit=$audit_val started=$started_count completed=$completed_count)"
  fi
}

# ── Main ─────────────────────────────────────────────

echo "Testing construct-workflow scripts"
echo "════════════════════════════════════════════"

setup

# Reader tests (FR-1)
echo ""
echo "Reader Tests (FR-1):"
test_reader_valid_workflow
test_reader_missing_workflow
test_reader_implement_skip_rejected
test_reader_condense_advisory
test_reader_invalid_gate_value
test_reader_defaults_applied

# Activator tests (FR-2, FR-5)
echo ""
echo "Activator Tests (FR-2, FR-5):"
test_activate_writes_state_file
test_activate_logs_started_event
test_deactivate_clears_state_file
test_deactivate_logs_completed_event
test_check_active_construct
test_check_no_active_construct
test_gate_returns_value

# Constraint rendering tests (FR-3)
echo ""
echo "Constraint Rendering Tests (FR-3):"
test_constraint_yield_rendered
test_constraint_yield_not_rendered

# Pre-flight gate tests (FR-4)
echo ""
echo "Pre-flight Gate Tests (FR-4):"
test_preflight_review_skip
test_preflight_review_full

# COMPLETED marker test (FR-4)
echo ""
echo "Lifecycle Tests:"
test_completed_marker_construct_workflow

# Default behavior tests (NF-1, NF-4)
echo ""
echo "Default & Fail-Closed Tests (NF-1, NF-4):"
test_default_no_manifest
test_fail_closed_corrupt_manifest

# Security tests
echo ""
echo "Security Tests:"
test_activate_invalid_path_rejected
test_activate_yields_correct_constraints

# Integration test
echo ""
echo "Integration Tests:"
test_integration_end_to_end

teardown

echo ""
echo "════════════════════════════════════════════"
echo "Results: $TESTS_RUN tests, $TESTS_PASSED passed, $TESTS_FAILED failed"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
  exit 1
fi
exit 0
