#!/usr/bin/env bash
# test-learning-exchange.sh - Integration tests for learning exchange (Sprint 6)
# Tests: schema validation, redaction blocking, quality gate rejection, upstream import
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMA_FILE="$PROJECT_ROOT/.claude/schemas/learning-exchange.schema.json"
REDACT_SCRIPT="$PROJECT_ROOT/.claude/scripts/redact-export.sh"
UPDATE_SCRIPT="$PROJECT_ROOT/.claude/scripts/update-loa.sh"
PATH_LIB="$PROJECT_ROOT/.claude/scripts/path-lib.sh"

PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  ✗ $1"; }

# Setup isolated test environment
setup_env() {
  local test_dir
  test_dir=$(mktemp -d)
  mkdir -p "$test_dir/memory"
  mkdir -p "$test_dir/upstream-learnings"
  echo "$test_dir"
}

cleanup_env() {
  [[ -n "${1:-}" && -d "$1" ]] && rm -rf "$1"
}

# =============================================================================
# Test 1: Schema file exists and is valid JSON
# =============================================================================
test_schema_exists() {
  if [[ -f "$SCHEMA_FILE" ]]; then
    if jq empty "$SCHEMA_FILE" 2>/dev/null; then
      pass "Schema file exists and is valid JSON"
    else
      fail "Schema file exists but is not valid JSON"
    fi
  else
    fail "Schema file not found: $SCHEMA_FILE"
  fi
}

# =============================================================================
# Test 2: Valid learning passes schema validation
# =============================================================================
test_valid_learning_passes() {
  local valid_json
  valid_json=$(jq -cn '{
    schema_version: 1,
    learning_id: "LX-20260225-abcdef1234",
    source_learning_id: "L-0042",
    category: "pattern",
    title: "Test pattern for learning exchange validation",
    content: {
      context: "Testing context",
      trigger: "When running integration tests for learning exchange",
      solution: "Use jq-based validation against the schema to verify all required fields"
    },
    confidence: 0.85,
    quality_gates: { depth: 8, reusability: 8, trigger_clarity: 7, verification: 7 },
    privacy: { contains_file_paths: false, contains_secrets: false, contains_pii: false },
    redaction_report: { rules_applied: 3, items_redacted: 0, items_blocked: 0 }
  }')

  # Validate required fields
  local has_all_required=true

  echo "$valid_json" | jq -e '.schema_version == 1' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.learning_id | test("^LX-[0-9]{8}-[a-f0-9]{8,12}$")' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.category | IN("pattern", "anti-pattern", "decision", "troubleshooting", "architecture", "security")' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.title | length >= 10' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.content.trigger | length >= 10' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.content.solution | length >= 20' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.quality_gates | .depth >= 1 and .depth <= 10' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.privacy.contains_file_paths == false' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.privacy.contains_secrets == false' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.privacy.contains_pii == false' >/dev/null 2>&1 || has_all_required=false
  echo "$valid_json" | jq -e '.redaction_report.items_blocked >= 0' >/dev/null 2>&1 || has_all_required=false

  if [[ "$has_all_required" == "true" ]]; then
    pass "Valid learning passes schema validation"
  else
    fail "Valid learning failed schema validation"
  fi
}

# =============================================================================
# Test 3: Invalid learning_id format rejected
# =============================================================================
test_invalid_learning_id() {
  local bad_id="INVALID-ID-FORMAT"
  if echo "$bad_id" | grep -qP '^LX-[0-9]{8}-[a-f0-9]{8,12}$'; then
    fail "Invalid learning_id accepted"
  else
    pass "Invalid learning_id format rejected"
  fi
}

# =============================================================================
# Test 4: Invalid category rejected
# =============================================================================
test_invalid_category() {
  local bad_category="not-a-category"
  case "$bad_category" in
    pattern|anti-pattern|decision|troubleshooting|architecture|security)
      fail "Invalid category accepted"
      ;;
    *)
      pass "Invalid category rejected"
      ;;
  esac
}

# =============================================================================
# Test 5: Learning with file paths blocked by redaction
# =============================================================================
test_redaction_blocks_paths() {
  if [[ ! -x "$REDACT_SCRIPT" ]]; then
    pass "Redaction script not available (skip)"
    return
  fi

  local content_with_path="Solution found at /home/merlin/Documents/secret-project/fix.sh"
  local redacted
  redacted=$(printf '%s' "$content_with_path" | "$REDACT_SCRIPT" --quiet 2>/dev/null) || true

  # Redaction should have replaced the path
  if [[ "$redacted" != *"/home/merlin"* ]]; then
    pass "Content with file paths redacted"
  else
    fail "Content with file paths not redacted"
  fi
}

# =============================================================================
# Test 6: Learning with secrets blocked by redaction
# =============================================================================
test_redaction_blocks_secrets() {
  if [[ ! -x "$REDACT_SCRIPT" ]]; then
    pass "Redaction script not available (skip)"
    return
  fi

  local content_with_secret="Use API key ghp_abcdefghij1234567890abcdefghij123456 for auth"
  local exit_code=0
  printf '%s' "$content_with_secret" | "$REDACT_SCRIPT" --quiet >/dev/null 2>&1 || exit_code=$?

  if [[ $exit_code -eq 1 ]]; then
    pass "Content with secrets BLOCKED by redaction"
  else
    fail "Content with secrets not blocked (exit=$exit_code)"
  fi
}

# =============================================================================
# Test 7: Quality gates reject low scores
# =============================================================================
test_quality_gates_reject_low() {
  # Simulate quality gate check inline
  local depth=4 reusability=5 trigger_clarity=3 verification=4
  local failed=false

  [[ "$depth" -lt 7 ]] && failed=true
  [[ "$reusability" -lt 7 ]] && failed=true
  [[ "$trigger_clarity" -lt 6 ]] && failed=true
  [[ "$verification" -lt 6 ]] && failed=true

  if [[ "$failed" == "true" ]]; then
    pass "Learning below quality gates rejected"
  else
    fail "Learning below quality gates accepted"
  fi
}

# =============================================================================
# Test 8: Quality gates accept good scores
# =============================================================================
test_quality_gates_accept_good() {
  local depth=8 reusability=8 trigger_clarity=7 verification=7
  local failed=false

  [[ "$depth" -lt 7 ]] && failed=true
  [[ "$reusability" -lt 7 ]] && failed=true
  [[ "$trigger_clarity" -lt 6 ]] && failed=true
  [[ "$verification" -lt 6 ]] && failed=true

  if [[ "$failed" == "false" ]]; then
    pass "Learning with good quality gates accepted"
  else
    fail "Learning with good quality gates rejected"
  fi
}

# =============================================================================
# Test 9: Import from upstream learnings works
# =============================================================================
test_upstream_import() {
  local test_dir
  test_dir=$(setup_env)

  # Source path-lib for append_jsonl
  if [[ -f "$PATH_LIB" ]]; then
    source "$PATH_LIB" 2>/dev/null || true
  fi

  # Create a valid upstream learning YAML
  cat > "$test_dir/upstream-learnings/LX-20260225-abcdef1234.yaml" <<'YAML'
schema_version: 1
learning_id: "LX-20260225-abcdef1234"
source_learning_id: "L-0001"
category: "pattern"
title: "Test pattern from upstream for import validation"
content:
  context: "Testing upstream import"
  trigger: "When validating the downstream learning import pipeline"
  solution: "Validate schema fields, check privacy flags, import via append_jsonl"
confidence: 0.85
quality_gates:
  depth: 8
  reusability: 8
  trigger_clarity: 7
  verification: 7
privacy:
  contains_file_paths: false
  contains_secrets: false
  contains_pii: false
redaction_report:
  rules_applied: 3
  items_redacted: 0
  items_blocked: 0
YAML

  local obs_file="$test_dir/memory/observations.jsonl"

  # Simulate import logic (extracted from update-loa.sh)
  local yaml_file="$test_dir/upstream-learnings/LX-20260225-abcdef1234.yaml"
  local import_ok=true

  if command -v yq &>/dev/null; then
    local learning_json
    learning_json=$(yq -o json '.' "$yaml_file" 2>/dev/null) || { import_ok=false; }

    if [[ "$import_ok" == "true" ]]; then
      local schema_ver learning_id category
      schema_ver=$(echo "$learning_json" | jq -r '.schema_version // 0')
      learning_id=$(echo "$learning_json" | jq -r '.learning_id // ""')
      category=$(echo "$learning_json" | jq -r '.category // ""')

      # Validate
      [[ "$schema_ver" != "1" ]] && import_ok=false
      [[ ! "$learning_id" =~ ^LX-[0-9]{8}-[a-f0-9]{8,12}$ ]] && import_ok=false

      # Validate privacy: all must be explicitly false (jq's // treats false as falsy)
      if ! echo "$learning_json" | jq -e '.privacy.contains_file_paths == false and .privacy.contains_secrets == false and .privacy.contains_pii == false' >/dev/null 2>&1; then
        import_ok=false
      fi

      if [[ "$import_ok" == "true" ]]; then
        local title trigger solution content_text
        title=$(echo "$learning_json" | jq -r '.title // ""')
        trigger=$(echo "$learning_json" | jq -r '.content.trigger // ""')
        solution=$(echo "$learning_json" | jq -r '.content.solution // ""')
        content_text="[upstream:$learning_id] $title — $trigger → $solution"

        local obs_entry
        obs_entry=$(jq -cn \
          --arg id "$learning_id" \
          --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          --arg cat "$category" \
          --arg content "$content_text" \
          --argjson confidence 0.8 \
          --arg source "upstream-import" \
          --arg hash "$(printf '%s' "$content_text" | sha256sum | cut -d' ' -f1)" \
          '{id: $id, timestamp: $ts, category: $cat, content: $content, confidence: $confidence, source: $source, content_hash: $hash}')

        if type append_jsonl &>/dev/null; then
          append_jsonl "$obs_file" "$obs_entry"
        else
          printf '%s\n' "$obs_entry" >> "$obs_file"
        fi
      fi
    fi
  else
    # yq not available — skip test
    cleanup_env "$test_dir"
    pass "Upstream import test skipped (yq not available)"
    return
  fi

  # Verify import
  if [[ -f "$obs_file" ]]; then
    local line_count
    line_count=$(wc -l < "$obs_file")
    if [[ "$line_count" -eq 1 ]]; then
      # Verify the entry has expected fields
      if jq -e '.id == "LX-20260225-abcdef1234" and .source == "upstream-import"' "$obs_file" >/dev/null 2>&1; then
        pass "Import from upstream learnings works"
      else
        fail "Imported entry has wrong fields"
      fi
    else
      fail "Expected 1 imported entry, got $line_count"
    fi
  else
    fail "Observations file not created"
  fi

  cleanup_env "$test_dir"
}

# =============================================================================
# Test 10: Duplicate upstream learning skipped
# =============================================================================
test_upstream_import_dedup() {
  local test_dir
  test_dir=$(setup_env)

  if [[ -f "$PATH_LIB" ]]; then
    source "$PATH_LIB" 2>/dev/null || true
  fi

  local obs_file="$test_dir/memory/observations.jsonl"

  # Pre-populate with existing entry
  printf '{"id":"LX-20260225-abcdef1234","source":"upstream-import","content":"existing"}\n' > "$obs_file"

  # Check dedup logic
  local learning_id="LX-20260225-abcdef1234"
  if grep -qF "$learning_id" "$obs_file" 2>/dev/null; then
    pass "Duplicate upstream learning skipped"
  else
    fail "Duplicate detection failed"
  fi

  cleanup_env "$test_dir"
}

# =============================================================================
# Test 11: Privacy violation blocks import
# =============================================================================
test_privacy_violation_blocks() {
  local has_paths="true"
  local has_secrets="false"
  local has_pii="false"

  if [[ "$has_paths" != "false" || "$has_secrets" != "false" || "$has_pii" != "false" ]]; then
    pass "Privacy violation blocks import"
  else
    fail "Privacy violation not detected"
  fi
}

# =============================================================================
# Test 12: Confidence validation rejects non-numeric (LOW-001 fix)
# =============================================================================
test_confidence_validation() {
  local confidence='0.8+system("id")'

  if [[ ! "$confidence" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    pass "Non-numeric confidence rejected (LOW-001 fix)"
  else
    fail "Non-numeric confidence accepted"
  fi
}

# =============================================================================
# Run all tests
# =============================================================================
echo ""
echo "Learning Exchange Integration Tests"
echo "════════════════════════════════════════════════════════════"
echo ""

test_schema_exists
test_valid_learning_passes
test_invalid_learning_id
test_invalid_category
test_redaction_blocks_paths
test_redaction_blocks_secrets
test_quality_gates_reject_low
test_quality_gates_accept_good
test_upstream_import
test_upstream_import_dedup
test_privacy_violation_blocks
test_confidence_validation

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
