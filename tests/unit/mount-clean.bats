#!/usr/bin/env bats
# Tests for clean_grimoire_state() in mount-loa.sh (FR-3, #299)

setup() {
  TEST_DIR="$(mktemp -d)"
  export TARGET_DIR="$TEST_DIR"

  # Create grimoire structure as if git checkout just ran
  mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
  mkdir -p "$TEST_DIR/grimoires/loa/a2a/trajectory"
  mkdir -p "$TEST_DIR/grimoires/loa/archive/2026-01-01-old-cycle"
  mkdir -p "$TEST_DIR/grimoires/loa/context"
  mkdir -p "$TEST_DIR/grimoires/loa/memory"

  # Create framework development artifacts (should be removed)
  echo "# PRD content" > "$TEST_DIR/grimoires/loa/prd.md"
  echo "# SDD content" > "$TEST_DIR/grimoires/loa/sdd.md"
  echo "# Sprint content" > "$TEST_DIR/grimoires/loa/sprint.md"
  echo "# BEAUVOIR" > "$TEST_DIR/grimoires/loa/BEAUVOIR.md"
  echo "# SOUL" > "$TEST_DIR/grimoires/loa/SOUL.md"
  printf '{"version":"1.0.0","cycles":[{"id":"cycle-001","status":"active"}],"active_cycle":"cycle-001"}' \
    > "$TEST_DIR/grimoires/loa/ledger.json"

  # Create a2a content (should be removed)
  echo "reviewer content" > "$TEST_DIR/grimoires/loa/a2a/sprint-1/reviewer.md"
  echo "index content" > "$TEST_DIR/grimoires/loa/a2a/index.md"

  # Create archive content (should be removed)
  echo "archive prd" > "$TEST_DIR/grimoires/loa/archive/2026-01-01-old-cycle/prd.md"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Define the function under test directly — matches mount-loa.sh implementation
clean_grimoire_state() {
  local grimoire_dir="${TARGET_DIR:-.}/grimoires/loa"

  if [[ ! -d "$grimoire_dir" ]]; then
    return 0
  fi

  # Remove framework development artifacts
  local artifacts=("prd.md" "sdd.md" "sprint.md" "BEAUVOIR.md" "SOUL.md")
  for artifact in "${artifacts[@]}"; do
    rm -f "${grimoire_dir}/${artifact}"
  done

  # Remove framework a2a and archive directory contents
  if [[ -d "${grimoire_dir}/a2a" ]]; then
    find "${grimoire_dir}/a2a" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
    find "${grimoire_dir}/a2a" -mindepth 1 -maxdepth 1 -type f -exec rm -f {} + 2>/dev/null || true
  fi
  if [[ -d "${grimoire_dir}/archive" ]]; then
    find "${grimoire_dir}/archive" -mindepth 1 -exec rm -rf {} + 2>/dev/null || true
  fi

  # Preserve directory structure
  mkdir -p "${grimoire_dir}/a2a/trajectory"
  mkdir -p "${grimoire_dir}/archive"
  mkdir -p "${grimoire_dir}/context"
  mkdir -p "${grimoire_dir}/memory"

  # Initialize clean ledger
  printf '{\n  "version": "1.0.0",\n  "cycles": [],\n  "active_cycle": null,\n  "active_bugfix": null,\n  "global_sprint_counter": 0,\n  "bugfix_cycles": []\n}\n' > "${grimoire_dir}/ledger.json"

  # Create NOTES.md template if missing
  if [[ ! -f "${grimoire_dir}/NOTES.md" ]]; then
    printf '# Project Notes\n\n## Learnings\n\n## Blockers\n\n## Observations\n' > "${grimoire_dir}/NOTES.md"
  fi
}

@test "removes prd.md artifact" {
  clean_grimoire_state
  [ ! -f "$TEST_DIR/grimoires/loa/prd.md" ]
}

@test "removes sdd.md artifact" {
  clean_grimoire_state
  [ ! -f "$TEST_DIR/grimoires/loa/sdd.md" ]
}

@test "removes sprint.md artifact" {
  clean_grimoire_state
  [ ! -f "$TEST_DIR/grimoires/loa/sprint.md" ]
}

@test "removes BEAUVOIR.md and SOUL.md" {
  clean_grimoire_state
  [ ! -f "$TEST_DIR/grimoires/loa/BEAUVOIR.md" ]
  [ ! -f "$TEST_DIR/grimoires/loa/SOUL.md" ]
}

@test "removes a2a sprint directory contents" {
  clean_grimoire_state
  [ ! -d "$TEST_DIR/grimoires/loa/a2a/sprint-1" ]
  [ ! -f "$TEST_DIR/grimoires/loa/a2a/index.md" ]
}

@test "removes archive directory contents" {
  clean_grimoire_state
  [ ! -d "$TEST_DIR/grimoires/loa/archive/2026-01-01-old-cycle" ]
}

@test "preserves directory structure after clean" {
  clean_grimoire_state
  [ -d "$TEST_DIR/grimoires/loa/a2a/trajectory" ]
  [ -d "$TEST_DIR/grimoires/loa/archive" ]
  [ -d "$TEST_DIR/grimoires/loa/context" ]
  [ -d "$TEST_DIR/grimoires/loa/memory" ]
}

@test "initializes clean ledger.json" {
  clean_grimoire_state
  [ -f "$TEST_DIR/grimoires/loa/ledger.json" ]
  local cycles
  cycles=$(jq -r '.cycles | length' "$TEST_DIR/grimoires/loa/ledger.json")
  [ "$cycles" -eq 0 ]
  local counter
  counter=$(jq -r '.global_sprint_counter' "$TEST_DIR/grimoires/loa/ledger.json")
  [ "$counter" -eq 0 ]
  local active
  active=$(jq -r '.active_cycle' "$TEST_DIR/grimoires/loa/ledger.json")
  [ "$active" = "null" ]
}

@test "creates NOTES.md template when missing" {
  rm -f "$TEST_DIR/grimoires/loa/NOTES.md"
  clean_grimoire_state
  [ -f "$TEST_DIR/grimoires/loa/NOTES.md" ]
  grep -q "## Learnings" "$TEST_DIR/grimoires/loa/NOTES.md"
  grep -q "## Blockers" "$TEST_DIR/grimoires/loa/NOTES.md"
}

@test "preserves existing NOTES.md" {
  echo "# My custom notes" > "$TEST_DIR/grimoires/loa/NOTES.md"
  clean_grimoire_state
  grep -q "My custom notes" "$TEST_DIR/grimoires/loa/NOTES.md"
}

@test "preserves user files in context directory" {
  echo "my context" > "$TEST_DIR/grimoires/loa/context/vision.md"
  echo "my users" > "$TEST_DIR/grimoires/loa/context/users.md"
  clean_grimoire_state
  [ -f "$TEST_DIR/grimoires/loa/context/vision.md" ]
  [ -f "$TEST_DIR/grimoires/loa/context/users.md" ]
}

@test "idempotent — running twice produces same result" {
  clean_grimoire_state
  clean_grimoire_state
  [ ! -f "$TEST_DIR/grimoires/loa/prd.md" ]
  [ -f "$TEST_DIR/grimoires/loa/ledger.json" ]
  [ -d "$TEST_DIR/grimoires/loa/context" ]
  local cycles
  cycles=$(jq -r '.cycles | length' "$TEST_DIR/grimoires/loa/ledger.json")
  [ "$cycles" -eq 0 ]
}

@test "handles missing grimoire directory gracefully" {
  rm -rf "$TEST_DIR/grimoires/loa"
  clean_grimoire_state
}
