#!/usr/bin/env bats
# =============================================================================
# security-audit-scope.bats — `.claude/scripts/security-audit-scope.sh`
# --help, --files FILE and --paths P… restrict the walk (cycle-133 Sprint 1
# Task 1.5; SDD C-4; PRD FR-4(e); bd-crzm5).
# =============================================================================

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  S="$REPO/.claude/scripts/security-audit-scope.sh"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/src/api" "$P/lib"
  printf 'import subprocess\npassword = input()\n' > "$P/src/a.py"
  printf 'import subprocess\n' > "$P/lib/b.py"
  printf 'def handler(): pass\n' > "$P/src/api/handler.py"
  printf 'const x = require("child_process").exec\n' > "$P/lib/c.js"
}

scope() { (cd "$P" && bash "$S" --json "$@"); }

@test "scope: --help exits 0 and names --files and --paths" {
  run bash "$S" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--files"* ]]
  [[ "$output" == *"--paths"* ]]
}

@test "scope: without a restriction the whole tree is walked" {
  run scope
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .sinks.command_exec <<<"$output")" -eq 3 ]
  [ "$(jq -r .scope.mode <<<"$output")" = "tree" ]
}

@test "scope: --files FILE restricts the walk to the listed files" {
  printf 'src/a.py\n\nlib/c.js\n' > "$P/changed.txt"
  run scope --files changed.txt
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .sinks.command_exec <<<"$output")" -eq 2 ]
  [ "$(jq -r .auth_files <<<"$output")" -eq 1 ]
  [ "$(jq -r .sources.handlers <<<"$output")" -eq 0 ]
  [ "$(jq -r .scope.mode <<<"$output")" = "files" ]
  [ "$(jq -r .scope.roots <<<"$output")" -eq 2 ]
}

@test "scope: --paths P... restricts the walk to those directories or files" {
  run scope --paths src/api lib/b.py
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .sources.handlers <<<"$output")" -eq 1 ]
  [ "$(jq -r .sinks.command_exec <<<"$output")" -eq 1 ]
  [ "$(jq -r .auth_files <<<"$output")" -eq 0 ]
}

@test "scope: usage errors exit 2 (unknown option, missing --files file, nonexistent --paths entry, empty --paths)" {
  run bash "$S" --bogus
  [ "$status" -eq 2 ]
  run scope --files no-such-list.txt
  [ "$status" -eq 2 ]
  run scope --paths no/such/dir
  [ "$status" -eq 2 ]
  run scope --paths
  [ "$status" -eq 2 ]
}
