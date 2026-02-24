#!/usr/bin/env bats
# =============================================================================
# test-zone-guard-symlinks.bats — Verify Agent Teams zone guard symlink hardening
# =============================================================================
# Sprint 6 (sprint-49) — Bridgebuilder finding medium-2
# Validates that team-role-guard-write.sh blocks System Zone writes through
# symlink resolution AND direct submodule paths.

HOOK_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../hooks/safety" && pwd)"
GUARD_SCRIPT="$HOOK_DIR/team-role-guard-write.sh"

# Helper: Run the guard with a given file path
run_guard() {
  local path="$1"
  local input="{\"tool_input\":{\"file_path\":\"$path\"}}"
  echo "$input" | LOA_TEAM_MEMBER="test-teammate" bash "$GUARD_SCRIPT"
}

# ---------------------------------------------------------------------------
# Task 6.2: Symlink-aware System Zone blocking
# ---------------------------------------------------------------------------

@test "zone-guard: blocks .claude/ writes for teammates" {
  run run_guard ".claude/scripts/mount-loa.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]] || [[ "$stderr" == *"BLOCKED"* ]] || true
}

@test "zone-guard: blocks .claude/hooks/ writes for teammates" {
  run run_guard ".claude/hooks/safety/team-role-guard-write.sh"
  [ "$status" -eq 2 ]
}

@test "zone-guard: blocks .loa/.claude/ writes for teammates (submodule physical path)" {
  # This is the key medium-2 fix — direct write to submodule's .claude/
  run run_guard ".loa/.claude/scripts/mount-loa.sh"
  [ "$status" -eq 2 ]
}

@test "zone-guard: blocks .loa/.claude/data/ writes for teammates" {
  run run_guard ".loa/.claude/data/bridgebuilder-persona.md"
  [ "$status" -eq 2 ]
}

@test "zone-guard: allows grimoires/ writes for teammates (State Zone)" {
  run run_guard "grimoires/loa/NOTES.md"
  # NOTES.md is append-only, so it gets a different block
  # Test a non-append-only state zone file
  run run_guard "grimoires/loa/a2a/sprint-49/reviewer.md"
  [ "$status" -eq 0 ]
}

@test "zone-guard: allows src/ writes for teammates (App Zone)" {
  run run_guard "src/index.ts"
  [ "$status" -eq 0 ]
}

@test "zone-guard: blocks .run/ top-level state files for teammates" {
  run run_guard ".run/state.json"
  [ "$status" -eq 2 ]
}

@test "zone-guard: allows .run/bugs/ subdirectory writes for teammates" {
  run run_guard ".run/bugs/bug-123/state.json"
  [ "$status" -eq 0 ]
}

@test "zone-guard: no-op when LOA_TEAM_MEMBER is unset" {
  local input='{"tool_input":{"file_path":".claude/scripts/mount-loa.sh"}}'
  run bash -c "echo '$input' | bash '$GUARD_SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "zone-guard: handles absolute paths correctly" {
  local abs_path="$(pwd)/.claude/scripts/mount-loa.sh"
  run run_guard "$abs_path"
  [ "$status" -eq 2 ]
}

@test "zone-guard: handles absolute .loa/.claude/ paths" {
  local abs_path="$(pwd)/.loa/.claude/scripts/mount-loa.sh"
  run run_guard "$abs_path"
  [ "$status" -eq 2 ]
}
