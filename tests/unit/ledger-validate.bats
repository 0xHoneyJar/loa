#!/usr/bin/env bats
# =============================================================================
# ledger-validate.bats — `ledger-lib.sh validate_ledger` validates
# `schema_version` and accepts the legacy `version` as an alias (cycle-133
# Sprint 1 Task 1.5; SDD C-4; PRD FR-4(f); bd-4pjqm). The live ledger shape of
# this repository (schema_version, no version) must validate.
# =============================================================================

setup() {
  REAL="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  export PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT_ROOT/grimoires/loa"
  cd "$PROJECT_ROOT"
  L="$PROJECT_ROOT/grimoires/loa/ledger.json"
}

v() { ( source "$REAL/.claude/scripts/ledger-lib.sh" && validate_ledger ); }

@test "ledger-validate: the live ledger shape (schema_version, no version) validates" {
  # this repository's live ledger, copied (never written)
  cp "$REAL/grimoires/loa/ledger.json" "$L"
  [ "$(jq -r 'has("version")' "$L")" = "false" ]
  [ "$(jq -r '.schema_version' "$L")" = "1" ]
  run v
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Ledger is valid"* ]]
}

@test "ledger-validate: the legacy version field is accepted as an alias" {
  printf '{"version": 1, "next_sprint_number": 1, "cycles": []}\n' > "$L"
  run v
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "ledger-validate: neither schema_version nor version is refused naming schema_version" {
  printf '{"next_sprint_number": 1, "cycles": []}\n' > "$L"
  run v
  [ "$status" -eq 5 ]
  [[ "$output" == *"schema_version"* ]]
}

@test "ledger-validate: a non-integer schema_version is refused" {
  printf '{"schema_version": "one", "next_sprint_number": 1, "cycles": []}\n' > "$L"
  run v
  [ "$status" -eq 5 ]
  [[ "$output" == *"schema_version"* ]]
}
