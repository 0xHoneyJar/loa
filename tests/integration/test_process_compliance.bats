#!/usr/bin/env bats
# tests/integration/test_process_compliance.bats
# Verifies process compliance enforcement artifacts are in place.
# Issue #217: Prevent AI from exiting Loa workflow

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ERROR_CODES="$REPO_ROOT/.claude/data/error-codes.json"
  CLAUDE_LOA="$REPO_ROOT/.claude/loa/CLAUDE.loa.md"
  SIMSTIM_SKILL="$REPO_ROOT/.claude/skills/simstim-workflow/SKILL.md"
  AUTONOMOUS_SKILL="$REPO_ROOT/.claude/skills/autonomous-agent/SKILL.md"
  IMPLEMENTING_SKILL="$REPO_ROOT/.claude/skills/implementing-tasks/SKILL.md"
  PROTOCOL_FILE="$REPO_ROOT/.claude/protocols/implementation-compliance.md"
}

# --- Error Code Tests (1-4) ---

@test "E110-E114 error codes exist in registry" {
  for code in E110 E111 E112 E113 E114; do
    result=$(jq --arg c "$code" '[.[] | select(.code == $c)] | length' "$ERROR_CODES")
    [ "$result" -eq 1 ]
  done
}

@test "all new error codes have required fields" {
  for code in E110 E111 E112 E113 E114; do
    # Check each required field exists and is non-empty
    for field in code name category what fix; do
      result=$(jq --arg c "$code" --arg f "$field" \
        '.[] | select(.code == $c) | .[$f] // empty | length > 0' "$ERROR_CODES")
      [ "$result" = "true" ]
    done
  done
}

@test "all new error codes have category workflow" {
  for code in E110 E111 E112 E113 E114; do
    category=$(jq -r --arg c "$code" '.[] | select(.code == $c) | .category' "$ERROR_CODES")
    [ "$category" = "workflow" ]
  done
}

@test "no duplicate error codes in registry" {
  total=$(jq '[.[].code] | length' "$ERROR_CODES")
  unique=$(jq '[.[].code] | unique | length' "$ERROR_CODES")
  [ "$total" -eq "$unique" ]
}

# --- CLAUDE.loa.md Tests (5-7) ---

@test "CLAUDE.loa.md contains Process Compliance section" {
  grep -q "## Process Compliance" "$CLAUDE_LOA"
}

@test "CLAUDE.loa.md contains NEVER rules" {
  grep -q "NEVER write application code outside of" "$CLAUDE_LOA"
  grep -q "NEVER use Claude.*TaskCreate.*for sprint task tracking" "$CLAUDE_LOA"
  grep -q "NEVER skip from sprint plan directly to implementation" "$CLAUDE_LOA"
  grep -q "NEVER skip.*review-sprint.*audit-sprint" "$CLAUDE_LOA"
}

@test "CLAUDE.loa.md contains ALWAYS rules" {
  grep -q "ALWAYS use.*run sprint-plan.*or.*run sprint-N" "$CLAUDE_LOA"
  grep -q "ALWAYS create beads tasks from sprint plan" "$CLAUDE_LOA"
  grep -q "ALWAYS complete the full implement.*review.*audit cycle" "$CLAUDE_LOA"
  grep -q "ALWAYS check for existing sprint plan before writing code" "$CLAUDE_LOA"
}

# --- Simstim SKILL.md Tests (8-9) ---

@test "simstim SKILL.md contains Phase 7 enforcement" {
  grep -q "Phase 7 MUST invoke.*run sprint-plan" "$SIMSTIM_SKILL"
  grep -q "NEVER implement code directly" "$SIMSTIM_SKILL"
}

@test "simstim SKILL.md contains beads guidance" {
  grep -q 'Use `br` commands for task lifecycle' "$SIMSTIM_SKILL"
  grep -q "PR #216 was rolled back" "$SIMSTIM_SKILL"
}

# --- Autonomous SKILL.md Tests (10) ---

@test "autonomous SKILL.md contains implementation guard" {
  grep -q "Implementation Enforcement" "$AUTONOMOUS_SKILL"
  grep -q "MUST use.*run sprint-plan.*or.*run sprint-N" "$AUTONOMOUS_SKILL"
  grep -q "Implementation Guard" "$AUTONOMOUS_SKILL"
  grep -q "NEVER.*Write application code directly" "$AUTONOMOUS_SKILL"
}

# --- Implementing-Tasks SKILL.md Test (11) ---

@test "implementing-tasks SKILL.md contains TaskCreate guidance" {
  grep -q "Task Tracking: Beads vs TaskCreate" "$IMPLEMENTING_SKILL"
  grep -q "session-level progress display" "$IMPLEMENTING_SKILL"
}

# --- Protocol Tests (12-13) ---

@test "protocol file exists" {
  [ -f "$PROTOCOL_FILE" ]
}

@test "protocol contains checklist and error codes" {
  grep -q "Pre-Implementation Checklist" "$PROTOCOL_FILE"
  grep -q "LOA-E110" "$PROTOCOL_FILE"
  grep -q "LOA-E114" "$PROTOCOL_FILE"
  grep -q "Task Tracking Decision Tree" "$PROTOCOL_FILE"
}

# --- Validation Tests (14-15) ---

@test "error code names are snake_case" {
  # All names for E110-E114 should match snake_case pattern
  for code in E110 E111 E112 E113 E114; do
    name=$(jq -r --arg c "$code" '.[] | select(.code == $c) | .name' "$ERROR_CODES")
    [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]]
  done
}

@test "E108-E109 gap is intentional — no false failures" {
  # E107 exists (highest before gap)
  result_107=$(jq '[.[] | select(.code == "E107")] | length' "$ERROR_CODES")
  [ "$result_107" -eq 1 ]
  # E108 and E109 do NOT exist (intentional gap)
  result_108=$(jq '[.[] | select(.code == "E108")] | length' "$ERROR_CODES")
  [ "$result_108" -eq 0 ]
  result_109=$(jq '[.[] | select(.code == "E109")] | length' "$ERROR_CODES")
  [ "$result_109" -eq 0 ]
  # E110 exists (first new code)
  result_110=$(jq '[.[] | select(.code == "E110")] | length' "$ERROR_CODES")
  [ "$result_110" -eq 1 ]
}
