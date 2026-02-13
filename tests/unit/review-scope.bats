#!/usr/bin/env bats
# Tests for review-scope.sh (FR-4, #303)

setup() {
  TEST_DIR="$(mktemp -d)"
  export LOA_VERSION_FILE="$TEST_DIR/.loa-version.json"
  export REVIEWIGNORE_FILE="$TEST_DIR/.reviewignore"

  # Create .loa-version.json with zone definitions
  cat > "$LOA_VERSION_FILE" << 'JSON'
{
  "framework_version": "1.37.0",
  "zones": {
    "system": ".claude",
    "state": ["grimoires", ".beads", ".ck", ".run"],
    "app": ["src", "lib", "app"]
  }
}
JSON

  # Source the functions under test
  source "$(dirname "$BATS_TEST_DIRNAME")/../.claude/scripts/review-scope.sh"

  # Initialize zones
  detect_zones
}

teardown() {
  rm -rf "$TEST_DIR"
}

# === Zone Detection Tests ===

@test "detects system zone from .loa-version.json" {
  [[ "${SYSTEM_ZONE_PATHS[0]}" == ".claude" ]]
}

@test "detects state zone paths from .loa-version.json" {
  [[ " ${STATE_ZONE_PATHS[*]} " == *" grimoires "* ]]
  [[ " ${STATE_ZONE_PATHS[*]} " == *" .beads "* ]]
  [[ " ${STATE_ZONE_PATHS[*]} " == *" .run "* ]]
}

@test "system zone files are excluded" {
  is_excluded ".claude/scripts/mount-loa.sh"
}

@test "state zone files are excluded" {
  is_excluded "grimoires/loa/prd.md"
  is_excluded ".beads/tasks.json"
  is_excluded ".run/state.json"
}

@test "app zone files pass through" {
  ! is_excluded "src/app.ts"
  ! is_excluded "lib/utils.js"
  ! is_excluded "app/index.html"
}

@test "root files pass through" {
  ! is_excluded "README.md"
  ! is_excluded "package.json"
}

# === .reviewignore Tests ===

@test "parses .reviewignore patterns" {
  cat > "$REVIEWIGNORE_FILE" << 'IGNORE'
# Comment line
*.min.js
vendor/

IGNORE

  REVIEWIGNORE_PATTERNS=()
  load_reviewignore
  [[ ${#REVIEWIGNORE_PATTERNS[@]} -eq 2 ]]
}

@test "ignores comment lines" {
  cat > "$REVIEWIGNORE_FILE" << 'IGNORE'
# This is a comment
*.test.js
# Another comment
IGNORE

  REVIEWIGNORE_PATTERNS=()
  load_reviewignore
  [[ ${#REVIEWIGNORE_PATTERNS[@]} -eq 1 ]]
  [[ "${REVIEWIGNORE_PATTERNS[0]}" == "*.test.js" ]]
}

@test "ignores blank lines" {
  cat > "$REVIEWIGNORE_FILE" << 'IGNORE'

*.css

*.map

IGNORE

  REVIEWIGNORE_PATTERNS=()
  load_reviewignore
  [[ ${#REVIEWIGNORE_PATTERNS[@]} -eq 2 ]]
}

@test "glob patterns exclude matching files" {
  cat > "$REVIEWIGNORE_FILE" << 'IGNORE'
*.min.js
IGNORE

  REVIEWIGNORE_PATTERNS=()
  load_reviewignore
  is_excluded "dist/bundle.min.js"
}

@test "directory patterns exclude contents" {
  cat > "$REVIEWIGNORE_FILE" << 'IGNORE'
vendor/
IGNORE

  REVIEWIGNORE_PATTERNS=()
  load_reviewignore
  is_excluded "vendor/lib/something.js"
}

@test ".reviewignore non-matching files pass through" {
  cat > "$REVIEWIGNORE_FILE" << 'IGNORE'
*.min.js
vendor/
IGNORE

  REVIEWIGNORE_PATTERNS=()
  load_reviewignore
  ! is_excluded "src/app.ts"
}

# === --no-reviewignore Tests ===

@test "no-reviewignore bypasses custom patterns" {
  cat > "$REVIEWIGNORE_FILE" << 'IGNORE'
*.test.js
IGNORE

  REVIEWIGNORE_PATTERNS=()
  load_reviewignore
  # With reviewignore: excluded
  is_excluded "foo.test.js" "false"
  # Without reviewignore: passes through (zone detection only)
  ! is_excluded "foo.test.js" "true"
}

# === Missing Files Tests ===

@test "missing .loa-version.json passes everything through" {
  rm -f "$LOA_VERSION_FILE"
  SYSTEM_ZONE_PATHS=()
  STATE_ZONE_PATHS=()
  detect_zones
  ! is_excluded ".claude/scripts/foo.sh"
}

@test "missing .reviewignore uses zone detection only" {
  rm -f "$REVIEWIGNORE_FILE"
  REVIEWIGNORE_PATTERNS=()
  load_reviewignore
  [[ ${#REVIEWIGNORE_PATTERNS[@]} -eq 0 ]]
  # Zone detection still works
  is_excluded ".claude/foo"
  ! is_excluded "src/bar.ts"
}

# === Filter Pipeline Tests ===

@test "filter_files passes app files through" {
  local result
  result=$(echo -e "src/app.ts\nsrc/utils.ts\nlib/core.js" | filter_files)
  [[ $(echo "$result" | wc -l) -eq 3 ]]
}

@test "filter_files excludes system zone files" {
  local result
  result=$(echo -e ".claude/foo.sh\nsrc/app.ts" | filter_files)
  # Should only contain the non-excluded file
  [[ "$(echo "$result" | grep -c 'src/app.ts')" -eq 1 ]]
  [[ "$(echo "$result" | grep -c '.claude')" -eq 0 ]]
}

@test "filter_files combined zone + reviewignore filtering" {
  cat > "$REVIEWIGNORE_FILE" << 'IGNORE'
*.map
IGNORE

  REVIEWIGNORE_PATTERNS=()
  load_reviewignore

  local result
  result=$(echo -e ".claude/foo\nsrc/app.ts\ndist/app.js.map\nlib/core.js" | filter_files)
  # Should have only the 2 non-excluded files
  [[ "$(echo "$result" | grep -c 'src/app.ts')" -eq 1 ]]
  [[ "$(echo "$result" | grep -c 'lib/core.js')" -eq 1 ]]
  [[ "$(echo "$result" | grep -c '.claude')" -eq 0 ]]
  [[ "$(echo "$result" | grep -c '.map')" -eq 0 ]]
}

@test "filter_files handles empty input" {
  local result
  result=$(echo "" | filter_files)
  [[ -z "$result" || "$result" == "" ]]
}
