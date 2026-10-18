#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/check-manifest-paths.bats — cycle-130 Sprint 1 (PRD FR-1, AC-1.2;
# SDD §5.2). tools/check-manifest-paths.sh fails when the integrity manifest
# lists a path that is not tracked (`git ls-files -- .claude`) or not present,
# and labels untracked offenders with a diagnostic class. The classes apply to
# untracked offenders only: a tracked `.lock` file is never flagged. Fixture
# manifests are written by hand so each failure mode is isolated; MP-6 checks
# the committed manifest of this repository.
# =============================================================================

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  CMP="$ROOT/tools/check-manifest-paths.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/cmpaths.XXXXXX")"
  R="$T/repo"
  mkdir -p "$R/.claude/scripts/__pycache__" "$R/.claude/data"
  printf 'echo a\n' > "$R/.claude/scripts/a.sh"
  printf 'pinned\n' > "$R/.claude/data/deps.lock"
  printf 'untracked\n' > "$R/.claude/scripts/stray.sh"
  printf 'bytecode' > "$R/.claude/scripts/__pycache__/a.cpython-313.pyc"
  git -C "$R" init --quiet
  git -C "$R" add .claude/scripts/a.sh .claude/data/deps.lock
  git -C "$R" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null commit --quiet -m fixture
  H="0000000000000000000000000000000000000000000000000000000000000000"
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

# write_manifest <path>... — a manifest listing exactly these paths
write_manifest() {
  local p
  {
    printf '{"generated":"2026-10-15T00:00:00Z","algorithm":"sha256","files":{'
    local first=1
    for p in "$@"; do
      [[ $first -eq 1 ]] || printf ','
      printf '"%s":"%s"' "$p" "$H"
      first=0
    done
    printf '}}\n'
  } > "$T/manifest.json"
}

@test "MP-1 a manifest of tracked, present paths passes (a tracked .lock is never flagged)" {
  write_manifest .claude/scripts/a.sh .claude/data/deps.lock
  run --separate-stderr bash "$CMP" --root "$R" --manifest "$T/manifest.json"
  [ "$status" -eq 0 ]
  [ "$output" = "manifest-paths: 2 entries, 0 untracked, 0 missing" ]
  [[ "$stderr" != *"deps.lock"* ]]
}

@test "MP-2 one untracked path: exit 1, the path and its class are named" {
  write_manifest .claude/scripts/a.sh .claude/scripts/stray.sh
  run --separate-stderr bash "$CMP" --root "$R" --manifest "$T/manifest.json"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"[other] 1 path(s)"* ]]
  [[ "$stderr" == *".claude/scripts/stray.sh"* ]]
  [ "$output" = "manifest-paths: 2 entries, 1 untracked (other=1), 0 missing" ]
}

@test "MP-3 a __pycache__ entry is classed __pycache__" {
  write_manifest .claude/scripts/a.sh .claude/scripts/__pycache__/a.cpython-313.pyc
  run --separate-stderr bash "$CMP" --root "$R" --manifest "$T/manifest.json"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"[__pycache__] 1 path(s)"* ]]
  [[ "$stderr" == *".claude/scripts/__pycache__/a.cpython-313.pyc"* ]]
  [[ "$output" == *"(__pycache__=1)"* ]]
}

@test "MP-4 untracked .pyc, .lock, .run and node_modules entries get their classes" {
  write_manifest .claude/x.pyc .claude/y.lock .claude/.run/state.json .claude/node_modules/p/i.js .claude/.pytest_cache/v
  run --separate-stderr bash "$CMP" --root "$R" --manifest "$T/manifest.json"
  [ "$status" -eq 1 ]
  [ "$output" = "manifest-paths: 5 entries, 5 untracked (.pytest_cache=1, node_modules=1, .run=1, .pyc=1, .lock=1), 0 missing" ]
}

@test "MP-5 a tracked path deleted from the working tree is reported missing" {
  write_manifest .claude/scripts/a.sh .claude/data/deps.lock
  rm -f "$R/.claude/data/deps.lock"
  run --separate-stderr bash "$CMP" --root "$R" --manifest "$T/manifest.json"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"absent from the working tree"* ]]
  [[ "$stderr" == *".claude/data/deps.lock"* ]]
  [ "$output" = "manifest-paths: 2 entries, 0 untracked, 1 missing" ]
}

@test "MP-6 the committed manifest of this repository passes" {
  run --separate-stderr bash "$CMP" --root "$ROOT"
  [ "$status" -eq 0 ] || { echo "$stderr" >&2; false; }
  [[ "$output" == "manifest-paths: "*" entries, 0 untracked, 0 missing" ]]
}

@test "MP-7 exit 2 on a usage error, a missing manifest and outside a git repository" {
  run bash "$CMP" --bogus
  [ "$status" -eq 2 ]
  run bash "$CMP" --root "$R" --manifest "$T/absent.json"
  [ "$status" -eq 2 ]
  mkdir -p "$T/plain"
  write_manifest .claude/a.sh
  run bash "$CMP" --root "$T/plain" --manifest "$T/manifest.json"
  [ "$status" -eq 2 ]
}
