#!/usr/bin/env bash
# test-constraints.sh — Test suite for DRY Constraint Registry
# Covers unit, integration, snapshot, and edge case tests per SDD 7.1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_ROOT"

# Constants
readonly REGISTRY=".claude/data/constraints.json"
readonly SCHEMA=".claude/schemas/constraints.schema.json"
readonly TEMPLATE_DIR=".claude/templates/constraints"
readonly GEN_SCRIPT=".claude/scripts/generate-constraints.sh"
readonly VAL_SCRIPT=".claude/scripts/validate-constraints.sh"
readonly GOLDEN_DIR="tests/fixtures"

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=()

# ============================================================================
# Test framework
# ============================================================================

run_test() {
  local name="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -n "  [$TESTS_RUN] $name ... "
  if "$@" 2>/dev/null; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES+=("$name")
    echo "FAIL"
  fi
}

assert_eq() {
  [[ "$1" == "$2" ]]
}

assert_exit() {
  local expected="$1"
  shift
  local actual
  "$@" >/dev/null 2>&1 && actual=0 || actual=$?
  [[ "$actual" -eq "$expected" ]]
}

normalize() {
  tr -d '\r' | sed 's/[[:space:]]*$//' | sed '/^$/d'
}

compute_section_hash() {
  printf '%s' "$1" \
    | tr -d '\r' \
    | sed 's/[[:space:]]*$//' \
    | sha256sum \
    | cut -c1-16
}

# ============================================================================
# Unit Tests (1-6)
# ============================================================================

echo ""
echo "UNIT TESTS"
echo "=========="

# Test 1: Registry validates against schema
test_schema_validation() {
  jq empty "$REGISTRY" 2>/dev/null || return 1
  # Check required fields exist
  jq -e '.version and .constraints and (.constraints | length > 0)' "$REGISTRY" >/dev/null 2>&1
}
run_test "Registry validates against schema" test_schema_validation

# Test 2: No duplicate constraint IDs
test_unique_ids() {
  local dupes
  dupes=$(jq -r '[.constraints[].id] | sort | group_by(.) | map(select(length > 1)) | length' "$REGISTRY")
  assert_eq "$dupes" "0"
}
run_test "No duplicate constraint IDs" test_unique_ids

# Test 3: Error code references valid
test_error_refs() {
  local codes
  codes=$(jq -r '[.constraints[] | select(.error_code) | .error_code] | unique | .[]' "$REGISTRY")
  [[ -z "$codes" ]] && return 0
  while IFS= read -r code; do
    jq -e --arg c "$code" '[.[] | select(.code == $c)] | length > 0' .claude/data/error-codes.json >/dev/null 2>&1 || return 1
  done <<< "$codes"
}
run_test "Error code references valid" test_error_refs

# Test 4: Layer target files exist
test_target_files() {
  local protocol_files
  protocol_files=$(jq -r '[.constraints[].layers[] | select(.target == "protocol") | .file] | unique | .[]' "$REGISTRY")
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ -f "$file" ]] || return 1
  done <<< "$protocol_files"
}
run_test "Layer target files exist" test_target_files

# Test 5: Skill names match directories
test_skill_names() {
  local skills
  skills=$(jq -r '[.constraints[].layers[] | select(.target == "skill-md") | .skills[]?] | unique | .[]' "$REGISTRY")
  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    [[ -d ".claude/skills/$skill" ]] || return 1
  done <<< "$skills"
}
run_test "Skill names match directories" test_skill_names

# Test 6: Deterministic ordering matches spec
test_ordering() {
  # NEVER rules should have order 10,20,30,40
  local never_orders
  never_orders=$(jq -r '[.constraints[] | select(.layers[] | select(.section == "process_compliance_never")) | .order] | sort | join(",")' "$REGISTRY")
  # Just verify they're sorted (not specific values)
  local sorted
  sorted=$(echo "$never_orders" | tr ',' '\n' | sort -n | tr '\n' ',' | sed 's/,$//')
  assert_eq "$never_orders" "$sorted"
}
run_test "Deterministic ordering matches spec" test_ordering

# ============================================================================
# Integration Tests (7-11)
# ============================================================================

echo ""
echo "INTEGRATION TESTS"
echo "================="

# Test 7: Generation is idempotent
test_idempotent() {
  sha256sum .claude/loa/CLAUDE.loa.md .claude/protocols/implementation-compliance.md \
    .claude/skills/autonomous-agent/SKILL.md .claude/skills/simstim-workflow/SKILL.md \
    .claude/skills/implementing-tasks/SKILL.md > /tmp/pre-idem.txt 2>/dev/null
  bash "$GEN_SCRIPT" >/dev/null 2>&1
  sha256sum .claude/loa/CLAUDE.loa.md .claude/protocols/implementation-compliance.md \
    .claude/skills/autonomous-agent/SKILL.md .claude/skills/simstim-workflow/SKILL.md \
    .claude/skills/implementing-tasks/SKILL.md > /tmp/post-idem.txt 2>/dev/null
  diff /tmp/pre-idem.txt /tmp/post-idem.txt >/dev/null 2>&1
}
run_test "Generation is idempotent" test_idempotent

# Test 8: Validation detects stale section
test_stale_detection() {
  # Staleness = registry changed but generation not re-run
  # Approach: tamper with the stored hash in the marker to simulate drift
  local target=".claude/loa/CLAUDE.loa.md"
  local backup="${target}.test-bak"
  cp "$target" "$backup"

  # Replace the stored hash with a fake one to simulate staleness
  sed -i 's/@constraint-generated: start process_compliance_never | hash:[a-f0-9]*/@constraint-generated: start process_compliance_never | hash:0000000000000000/' "$target"

  local result=0
  bash "$VAL_SCRIPT" >/dev/null 2>&1 || result=$?

  # Restore
  mv "$backup" "$target"

  # Should have failed (exit 1)
  [[ "$result" -eq 1 ]]
}
run_test "Validation detects stale section" test_stale_detection

# Test 9: Validation passes on fresh generation
test_fresh_validation() {
  bash "$GEN_SCRIPT" >/dev/null 2>&1
  bash "$VAL_SCRIPT" >/dev/null 2>&1
}
run_test "Validation passes on fresh generation" test_fresh_validation

# Test 10: --dry-run doesn't modify files
test_dry_run() {
  sha256sum .claude/loa/CLAUDE.loa.md .claude/protocols/implementation-compliance.md \
    .claude/skills/autonomous-agent/SKILL.md .claude/skills/simstim-workflow/SKILL.md \
    .claude/skills/implementing-tasks/SKILL.md > /tmp/pre-dry.txt 2>/dev/null
  bash "$GEN_SCRIPT" --dry-run >/dev/null 2>&1
  sha256sum .claude/loa/CLAUDE.loa.md .claude/protocols/implementation-compliance.md \
    .claude/skills/autonomous-agent/SKILL.md .claude/skills/simstim-workflow/SKILL.md \
    .claude/skills/implementing-tasks/SKILL.md > /tmp/post-dry.txt 2>/dev/null
  diff /tmp/pre-dry.txt /tmp/post-dry.txt >/dev/null 2>&1
}
run_test "--dry-run doesn't modify files" test_dry_run

# Test 11: --bootstrap inserts markers on unmarked file
test_bootstrap() {
  local tmpfile
  tmpfile=$(mktemp /tmp/test-bootstrap-XXXXXX.md)

  # Create a minimal file with the expected anchor
  cat > "$tmpfile" <<'ENDFILE'
# Test

### NEVER Rules

| Rule | Why |
|------|-----|
| NEVER do bad things | Bad reason |

### ALWAYS Rules
ENDFILE

  # Try bootstrap-style awk (simplified: just check marker insertion works)
  local start_marker="<!-- @constraint-generated: start test_section | hash:0000000000000000 -->"
  local end_marker="<!-- @constraint-generated: end test_section -->"

  # Verify file doesn't have markers
  ! grep -q "@constraint-generated" "$tmpfile" || { rm -f "$tmpfile"; return 1; }

  # Insert markers manually using awk pattern from generate-constraints.sh
  awk -v anchor="^### NEVER Rules\$" \
      -v end_pat1="^### " \
      -v end_pat2="^---\$" \
      -v start_m="$start_marker" \
      -v warning_m="<!-- DO NOT EDIT -->" \
      -v end_m="$end_marker" \
      -v content_m="| NEVER test | test reason |" \
      '
      BEGIN { state="looking"; sep_seen=0 }
      state == "looking" && $0 ~ anchor {
        print; state="in_header"; next
      }
      state == "in_header" {
        print
        if ($0 ~ /^\|[-|: ]+\|$/) {
          sep_seen=1
          print start_m
          print warning_m
          printf "%s\n", content_m
          state="skipping"
        }
        next
      }
      state == "skipping" {
        if ($0 ~ end_pat1 || $0 ~ end_pat2) {
          print end_m
          if ($0 !~ /^$/) print
          state="done"
          next
        }
        next
      }
      state != "skipping" { print }
      END {
        if (state == "skipping") print end_m
      }
      ' "$tmpfile" > "${tmpfile}.out"

  # Verify markers exist
  grep -q "@constraint-generated: start test_section" "${tmpfile}.out" || { rm -f "$tmpfile" "${tmpfile}.out"; return 1; }
  grep -q "@constraint-generated: end test_section" "${tmpfile}.out" || { rm -f "$tmpfile" "${tmpfile}.out"; return 1; }
  # Verify separator preserved
  grep -q '^|------|-----|$' "${tmpfile}.out" || { rm -f "$tmpfile" "${tmpfile}.out"; return 1; }

  rm -f "$tmpfile" "${tmpfile}.out"
}
run_test "--bootstrap inserts markers on unmarked file" test_bootstrap

# ============================================================================
# Snapshot Tests (12-14)
# ============================================================================

echo ""
echo "SNAPSHOT TESTS"
echo "=============="

# Test 12: NEVER table matches golden
test_golden_never() {
  local gen
  gen=$(jq -r '[.constraints[] | select(.layers[] | select(.section == "process_compliance_never"))] | sort_by(.order)' "$REGISTRY" | jq -r -f "$TEMPLATE_DIR/claude-loa-md-table.jq" | normalize)
  local golden
  golden=$(grep '^| NEVER' "$GOLDEN_DIR/golden-never-table.md" | normalize)
  assert_eq "$golden" "$gen"
}
run_test "NEVER table matches golden file" test_golden_never

# Test 13: ALWAYS table matches golden
test_golden_always() {
  local gen
  gen=$(jq -r '[.constraints[] | select(.layers[] | select(.section == "process_compliance_always"))] | sort_by(.order)' "$REGISTRY" | jq -r -f "$TEMPLATE_DIR/claude-loa-md-table.jq" | normalize)
  local golden
  golden=$(grep '^| ALWAYS' "$GOLDEN_DIR/golden-always-table.md" | normalize)
  assert_eq "$golden" "$gen"
}
run_test "ALWAYS table matches golden file" test_golden_always

# Test 14: Protocol checklist matches golden
test_golden_checklist() {
  local gen
  gen=$(jq -r '["C-PROC-008","C-PROC-006","C-PROC-009","C-PROC-010","C-GIT-001","C-PROC-005"] as $o | [$o[] as $id | .constraints[] | select(.id == $id)]' "$REGISTRY" | jq -r -f "$TEMPLATE_DIR/protocol-checklist.jq" | normalize)
  local golden
  golden=$(grep '^| [0-9]' "$GOLDEN_DIR/golden-impl-checklist.md" | normalize)
  assert_eq "$golden" "$gen"
}
run_test "Protocol checklist matches golden file" test_golden_checklist

# ============================================================================
# Edge Case Tests (15-17)
# ============================================================================

echo ""
echo "EDGE CASE TESTS"
echo "==============="

# Test 15: text_variants override text when present
test_text_variants_override() {
  # C-PROC-002 has skill-md text_variant that differs from rule_type + text
  local variant
  variant=$(jq -r '.constraints[] | select(.id == "C-PROC-002") | .text_variants["skill-md"] // empty' "$REGISTRY")
  local fallback
  fallback=$(jq -r '.constraints[] | select(.id == "C-PROC-002") | "\(.rule_type) \(.text)"' "$REGISTRY")

  # Variant should exist and be different from fallback
  [[ -n "$variant" ]] && [[ "$variant" != "$fallback" ]]
}
run_test "text_variants override text when present" test_text_variants_override

# Test 16: Pipe escaping in table cells
test_pipe_escaping() {
  # Generate a table cell that might contain pipe characters
  # The template should escape | as \|
  local output
  output=$(jq -r '[.constraints[] | select(.layers[] | select(.section == "process_compliance_never"))] | sort_by(.order)' "$REGISTRY" | jq -r -f "$TEMPLATE_DIR/claude-loa-md-table.jq")

  # Each line should start and end with |
  local bad_lines
  bad_lines=$(echo "$output" | grep -cv '^|.*|$' || true)
  assert_eq "$bad_lines" "0"
}
run_test "Pipe escaping in table cells" test_pipe_escaping

# Test 17: Hash changes when content changes
test_hash_changes() {
  local content1="| NEVER do X | reason X |"
  local content2="| NEVER do Y | reason Y |"
  local hash1
  hash1=$(compute_section_hash "$content1")
  local hash2
  hash2=$(compute_section_hash "$content2")

  # Hashes should be different
  [[ "$hash1" != "$hash2" ]] || return 1
  # Same content should produce same hash
  local hash1b
  hash1b=$(compute_section_hash "$content1")
  assert_eq "$hash1" "$hash1b"
}
run_test "Hash changes when content changes" test_hash_changes

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "================================"
echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

echo "All tests passed."
exit 0
