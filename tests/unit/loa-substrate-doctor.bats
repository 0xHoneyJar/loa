#!/usr/bin/env bats

# Cycle-110 sprint-2b2a T2.10 — `loa substrate doctor` bash shim smoke tests.
#
# The doctor's per-CLI probe matrix (3 CLIs × 3 outcomes × 2 probe methods)
# is fully covered by `.claude/adapters/tests/test_doctor.py` (30 pytest
# cases). This bats suite is a smoke test of the BASH SHIM at
# `.claude/scripts/loa-substrate-doctor.sh` — it verifies the shim:
#
#   - forwards args to the Python implementation
#   - emits JSON when --json is passed
#   - exits 0 when all probes return auth_state=ok
#   - exits 2 when any probe returns non-ok
#   - honors --provider filter
#   - --help is side-effect-free (no .run/ touched)

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  export PROJECT_ROOT
  export PYTHONPATH="$PROJECT_ROOT/.claude/adapters${PYTHONPATH:+:$PYTHONPATH}"
  export TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/doctor-bats-$$-$BATS_TEST_NUMBER"
  mkdir -p "$TEST_TMPDIR/fakebin"

  # Synthesize fake CLIs that exit 0 with empty stdout (auth_state=ok path).
  for cli in claude codex gemini; do
    printf '#!/bin/sh\nexit 0\n' > "$TEST_TMPDIR/fakebin/$cli"
    chmod +x "$TEST_TMPDIR/fakebin/$cli"
  done

  # Use ONLY fakebin + minimal system path — must not inherit operator's
  # real CLI binaries (they would be found by shutil.which instead of the
  # fakes and break the test isolation).
  export PATH="$TEST_TMPDIR/fakebin:/usr/bin:/bin"
}

teardown() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# ============================================================================
# Smoke tests via fake CLIs
# ============================================================================

@test "shim forwards --json and returns JSON" {
  run "$PROJECT_ROOT/.claude/scripts/loa-substrate-doctor.sh" --json --timeout 5
  [ "$status" -eq 0 ]
  [[ "$output" == *'"schema_version": 1'* ]]
  [[ "$output" == *'"probes"'* ]]
  [[ "$output" == *'"verdict"'* ]]
}

@test "shim exits 0 when all fake CLIs return exit 0 (auth_state=ok)" {
  run "$PROJECT_ROOT/.claude/scripts/loa-substrate-doctor.sh" --json --timeout 5
  [ "$status" -eq 0 ]
  [[ "$output" == *'"auth_state": "ok"'* ]]
  [[ "$output" == *'3/3 ready'* ]]
}

@test "shim exits 2 when a fake CLI returns non-zero (status-command)" {
  # codex uses status-command; non-zero → needs-login (state ≠ ok).
  printf '#!/bin/sh\nexit 1\n' > "$TEST_TMPDIR/fakebin/codex"
  chmod +x "$TEST_TMPDIR/fakebin/codex"
  run "$PROJECT_ROOT/.claude/scripts/loa-substrate-doctor.sh" --json --timeout 5
  [ "$status" -eq 2 ]
  [[ "$output" == *'"auth_state": "needs-login"'* ]]
}

@test "shim --provider filter narrows to one CLI" {
  run "$PROJECT_ROOT/.claude/scripts/loa-substrate-doctor.sh" --json --provider anthropic --timeout 5
  [ "$status" -eq 0 ]
  # 1 probe total when filter is applied.
  count=$(printf '%s' "$output" | grep -c '"provider"')
  [ "$count" -eq 1 ]
  [[ "$output" == *'1/1 ready'* ]]
}

@test "shim text mode renders provider + cli + state" {
  run "$PROJECT_ROOT/.claude/scripts/loa-substrate-doctor.sh" --timeout 5
  [ "$status" -eq 0 ]
  [[ "$output" == *'anthropic'* ]]
  [[ "$output" == *'claude-headless'* ]]
  [[ "$output" == *'codex-headless'* ]]
  [[ "$output" == *'gemini-headless'* ]]
  [[ "$output" == *'Verdict:'* ]]
}

@test "shim --help is side-effect-free (no .run/ writes)" {
  # Snapshot .run/ mtime before/after --help — must not change.
  if [[ ! -d "$PROJECT_ROOT/.run" ]]; then
    skip "no .run/ directory present"
  fi
  before=$(stat -c %Y "$PROJECT_ROOT/.run" 2>/dev/null || stat -f %m "$PROJECT_ROOT/.run")
  run "$PROJECT_ROOT/.claude/scripts/loa-substrate-doctor.sh" --help
  after=$(stat -c %Y "$PROJECT_ROOT/.run" 2>/dev/null || stat -f %m "$PROJECT_ROOT/.run")
  [ "$status" -eq 0 ]
  [ "$before" = "$after" ]
}

@test "shim rejects unknown --provider value (argparse error)" {
  run "$PROJECT_ROOT/.claude/scripts/loa-substrate-doctor.sh" --provider bogus
  [ "$status" -ne 0 ]
}

# ============================================================================
# Missing-binary handling (auth_state=unreachable)
# ============================================================================

@test "shim reports unreachable when a CLI is missing from PATH" {
  rm "$TEST_TMPDIR/fakebin/claude"
  run "$PROJECT_ROOT/.claude/scripts/loa-substrate-doctor.sh" --json --timeout 5
  [ "$status" -eq 2 ]
  [[ "$output" == *'"auth_state": "unreachable"'* ]]
  [[ "$output" == *'binary not found on PATH'* ]]
}
