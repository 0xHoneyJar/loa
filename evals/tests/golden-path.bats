#!/usr/bin/env bats
# golden-path.bats — Unit tests for .claude/scripts/golden-path.sh
# Run: bats evals/tests/golden-path.bats

# Setup: create temp workspace mimicking a Loa project
setup() {
  export TMPDIR="${BATS_TMPDIR:-/tmp}"
  export TEST_DIR
  TEST_DIR="$(mktemp -d)"
  export PROJECT_ROOT="$TEST_DIR"

  # Create minimal directory structure
  mkdir -p "$TEST_DIR/.claude/scripts"
  mkdir -p "$TEST_DIR/grimoires/loa/a2a"
  mkdir -p "$TEST_DIR/.run/bugs"

  # Copy golden-path.sh and its dependencies into test workspace
  local repo_root
  repo_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  cp "$repo_root/.claude/scripts/golden-path.sh" "$TEST_DIR/.claude/scripts/golden-path.sh"
  cp "$repo_root/.claude/scripts/bootstrap.sh" "$TEST_DIR/.claude/scripts/bootstrap.sh"
  cp "$repo_root/.claude/scripts/path-lib.sh" "$TEST_DIR/.claude/scripts/path-lib.sh"

  # Create minimal config so path-lib uses defaults
  touch "$TEST_DIR/.loa.config.yaml"

  # Source the script (PROJECT_ROOT already exported above)
  source "$TEST_DIR/.claude/scripts/golden-path.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ─────────────────────────────────────────────────────────
# golden_detect_plan_phase() tests
# ─────────────────────────────────────────────────────────

@test "plan_phase: discovery when no PRD exists" {
  run golden_detect_plan_phase
  [ "$status" -eq 0 ]
  [ "$output" = "discovery" ]
}

@test "plan_phase: architecture when PRD exists but no SDD" {
  echo "# PRD" > "$TEST_DIR/grimoires/loa/prd.md"
  run golden_detect_plan_phase
  [ "$status" -eq 0 ]
  [ "$output" = "architecture" ]
}

@test "plan_phase: sprint_planning when PRD+SDD exist but no sprint" {
  echo "# PRD" > "$TEST_DIR/grimoires/loa/prd.md"
  echo "# SDD" > "$TEST_DIR/grimoires/loa/sdd.md"
  run golden_detect_plan_phase
  [ "$status" -eq 0 ]
  [ "$output" = "sprint_planning" ]
}

@test "plan_phase: complete when PRD+SDD+sprint exist" {
  echo "# PRD" > "$TEST_DIR/grimoires/loa/prd.md"
  echo "# SDD" > "$TEST_DIR/grimoires/loa/sdd.md"
  echo "# Sprint" > "$TEST_DIR/grimoires/loa/sprint.md"
  run golden_detect_plan_phase
  [ "$status" -eq 0 ]
  [ "$output" = "complete" ]
}

# ─────────────────────────────────────────────────────────
# golden_detect_workflow_state() tests
# ─────────────────────────────────────────────────────────

@test "workflow_state: initial when no PRD" {
  run golden_detect_workflow_state
  [ "$status" -eq 0 ]
  [ "$output" = "initial" ]
}

@test "workflow_state: prd_created when only PRD exists" {
  echo "# PRD" > "$TEST_DIR/grimoires/loa/prd.md"
  run golden_detect_workflow_state
  [ "$status" -eq 0 ]
  [ "$output" = "prd_created" ]
}

@test "workflow_state: sdd_created when PRD+SDD exist" {
  echo "# PRD" > "$TEST_DIR/grimoires/loa/prd.md"
  echo "# SDD" > "$TEST_DIR/grimoires/loa/sdd.md"
  run golden_detect_workflow_state
  [ "$status" -eq 0 ]
  [ "$output" = "sdd_created" ]
}

@test "workflow_state: bug_active overrides all states" {
  echo "# PRD" > "$TEST_DIR/grimoires/loa/prd.md"
  echo "# SDD" > "$TEST_DIR/grimoires/loa/sdd.md"
  echo "# Sprint" > "$TEST_DIR/grimoires/loa/sprint.md"

  # Create an active bug
  local bug_dir="$TEST_DIR/.run/bugs/test-bug-001"
  mkdir -p "$bug_dir"
  echo '{"bug_id":"test-bug-001","state":"IMPLEMENTING","bug_title":"Test bug"}' \
    > "$bug_dir/state.json"

  run golden_detect_workflow_state
  [ "$status" -eq 0 ]
  [ "$output" = "bug_active" ]
}

@test "workflow_state: bug_active not triggered for COMPLETED bugs" {
  local bug_dir="$TEST_DIR/.run/bugs/done-bug"
  mkdir -p "$bug_dir"
  echo '{"bug_id":"done-bug","state":"COMPLETED","bug_title":"Done"}' \
    > "$bug_dir/state.json"

  run golden_detect_workflow_state
  [ "$status" -eq 0 ]
  [ "$output" = "initial" ]
}

@test "workflow_state: bug_active not triggered for HALTED bugs" {
  local bug_dir="$TEST_DIR/.run/bugs/halted-bug"
  mkdir -p "$bug_dir"
  echo '{"bug_id":"halted-bug","state":"HALTED","bug_title":"Halted"}' \
    > "$bug_dir/state.json"

  run golden_detect_workflow_state
  [ "$status" -eq 0 ]
  [ "$output" = "initial" ]
}

# ─────────────────────────────────────────────────────────
# golden_menu_options() tests
# ─────────────────────────────────────────────────────────

@test "menu_options: produces exactly 4 lines for initial state" {
  run golden_menu_options
  [ "$status" -eq 0 ]
  local line_count
  line_count=$(echo "$output" | wc -l)
  [ "$line_count" -eq 4 ]
}

@test "menu_options: all lines match pipe-delimited format" {
  run golden_menu_options
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    # Each line must have exactly 2 pipe chars (3 fields)
    local pipes
    pipes=$(echo "$line" | tr -cd '|' | wc -c)
    [ "$pipes" -eq 2 ]
  done <<< "$output"
}

@test "menu_options: last line is always 'View all commands'" {
  run golden_menu_options
  [ "$status" -eq 0 ]
  local last_line
  last_line=$(echo "$output" | tail -1)
  [[ "$last_line" == "View all commands"* ]]
}

@test "menu_options: initial state recommends planning" {
  run golden_menu_options
  [ "$status" -eq 0 ]
  local first_line
  first_line=$(echo "$output" | head -1)
  [[ "$first_line" == "Plan a new project"* ]]
}

@test "menu_options: prd_created state recommends architecture" {
  echo "# PRD" > "$TEST_DIR/grimoires/loa/prd.md"
  run golden_menu_options
  [ "$status" -eq 0 ]
  local first_line
  first_line=$(echo "$output" | head -1)
  [[ "$first_line" == *"architecture"* ]]
}

@test "menu_options: --json produces valid JSON" {
  run golden_menu_options --json
  [ "$status" -eq 0 ]
  # Validate JSON with jq
  echo "$output" | jq . >/dev/null 2>&1
  [ $? -eq 0 ]
}

@test "menu_options: --json array has 4 elements" {
  run golden_menu_options --json
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 4 ]
}

@test "menu_options: --json first element has recommended=true" {
  run golden_menu_options --json
  [ "$status" -eq 0 ]
  local recommended
  recommended=$(echo "$output" | jq '.[0].recommended')
  [ "$recommended" = "true" ]
}

@test "menu_options: --json non-first elements have recommended=false" {
  run golden_menu_options --json
  [ "$status" -eq 0 ]
  local second
  second=$(echo "$output" | jq '.[1].recommended')
  [ "$second" = "false" ]
}

# ─────────────────────────────────────────────────────────
# golden_format_journey() tests
# ─────────────────────────────────────────────────────────

@test "journey: renders plan marker for initial state" {
  run golden_format_journey
  [ "$status" -eq 0 ]
  [[ "$output" == *"/plan ●"* ]]
}

@test "journey: renders bug journey when bug_active" {
  local bug_dir="$TEST_DIR/.run/bugs/journey-bug"
  mkdir -p "$bug_dir"
  echo '{"bug_id":"journey-bug","state":"IMPLEMENTING","bug_title":"Test"}' \
    > "$bug_dir/state.json"

  run golden_format_journey
  [ "$status" -eq 0 ]
  [[ "$output" == *"/triage"* ]]
  [[ "$output" == *"/fix"* ]]
  [[ "$output" == *"/review"* ]]
  [[ "$output" == *"/close"* ]]
}

@test "bug_journey: fix position for IMPLEMENTING state" {
  local bug_dir="$TEST_DIR/.run/bugs/pos-bug"
  mkdir -p "$bug_dir"
  echo '{"bug_id":"pos-bug","state":"IMPLEMENTING","bug_title":"Test"}' \
    > "$bug_dir/state.json"

  run golden_format_bug_journey "pos-bug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/fix ●"* ]]
}

@test "bug_journey: review position for REVIEWING state" {
  local bug_dir="$TEST_DIR/.run/bugs/rev-bug"
  mkdir -p "$bug_dir"
  echo '{"bug_id":"rev-bug","state":"REVIEWING","bug_title":"Test"}' \
    > "$bug_dir/state.json"

  run golden_format_bug_journey "rev-bug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/review ●"* ]]
}

# ─────────────────────────────────────────────────────────
# Pipe sanitization tests
# ─────────────────────────────────────────────────────────

@test "menu_options: bug title with pipe char is sanitized" {
  local bug_dir="$TEST_DIR/.run/bugs/pipe-bug"
  mkdir -p "$bug_dir"
  echo '{"bug_id":"pipe-bug","state":"IMPLEMENTING","bug_title":"Bug with | pipe char"}' \
    > "$bug_dir/state.json"

  run golden_menu_options
  [ "$status" -eq 0 ]
  # No line should have more than 2 pipes (3 fields)
  while IFS= read -r line; do
    local pipes
    pipes=$(echo "$line" | tr -cd '|' | wc -c)
    [ "$pipes" -eq 2 ]
  done <<< "$output"
}

# ─────────────────────────────────────────────────────────
# golden_validate_bug_transition() tests
# ─────────────────────────────────────────────────────────

@test "bug_transition: TRIAGE -> IMPLEMENTING is valid" {
  run golden_validate_bug_transition "TRIAGE" "IMPLEMENTING"
  [ "$status" -eq 0 ]
}

@test "bug_transition: TRIAGE -> REVIEWING is invalid" {
  run golden_validate_bug_transition "TRIAGE" "REVIEWING"
  [ "$status" -eq 1 ]
}

@test "bug_transition: IMPLEMENTING -> REVIEWING is valid" {
  run golden_validate_bug_transition "IMPLEMENTING" "REVIEWING"
  [ "$status" -eq 0 ]
}

@test "bug_transition: REVIEWING -> AUDITING is valid" {
  run golden_validate_bug_transition "REVIEWING" "AUDITING"
  [ "$status" -eq 0 ]
}

@test "bug_transition: REVIEWING -> IMPLEMENTING is valid (rework)" {
  run golden_validate_bug_transition "REVIEWING" "IMPLEMENTING"
  [ "$status" -eq 0 ]
}

@test "bug_transition: AUDITING -> COMPLETED is valid" {
  run golden_validate_bug_transition "AUDITING" "COMPLETED"
  [ "$status" -eq 0 ]
}

@test "bug_transition: COMPLETED is terminal (no transitions out)" {
  run golden_validate_bug_transition "COMPLETED" "IMPLEMENTING"
  [ "$status" -eq 1 ]
}

@test "bug_transition: ANY -> HALTED is always valid" {
  run golden_validate_bug_transition "TRIAGE" "HALTED"
  [ "$status" -eq 0 ]
  run golden_validate_bug_transition "IMPLEMENTING" "HALTED"
  [ "$status" -eq 0 ]
  run golden_validate_bug_transition "REVIEWING" "HALTED"
  [ "$status" -eq 0 ]
}

@test "bug_transition: HALTED is terminal" {
  run golden_validate_bug_transition "HALTED" "IMPLEMENTING"
  [ "$status" -eq 1 ]
}
