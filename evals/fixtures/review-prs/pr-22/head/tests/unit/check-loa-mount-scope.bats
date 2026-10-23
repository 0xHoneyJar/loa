#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/check-loa-mount-scope.bats — cycle-130 Sprint 1 (PRD FR-1 #1267,
# AC-1.2/AC-1.3; SDD §5.3). check-loa.sh check_integrity classifies every
# manifest path as ok, Tampered (fail), not-mounted (a submodule mount does
# not link it but .loa/<path> has it: counted, one summary line, never a
# failure) or Missing (fail).
#
# Seam: check-loa.sh already guards `main` behind
#   [[ "${BASH_SOURCE[0]}" == "$0" ]]
# so each case sources the script in a child bash inside the fixture
# directory and calls check_integrity alone; the child exits 1 when the
# FAILURES counter is non-zero, the same rule main applies. No other check
# runs, and the script is not modified for the test.
# =============================================================================

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
  CHECK="$ROOT/.claude/scripts/check-loa.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/cloams.XXXXXX")"
  D="$T/downstream"
  # upstream tree inside the submodule path
  mkdir -p "$D/.loa/.claude/lib" "$D/.claude"
  printf 'echo a\n' > "$D/.loa/.claude/a.sh"
  printf 'echo b\n' > "$D/.loa/.claude/b.sh"
  printf 'echo c\n' > "$D/.loa/.claude/lib/c.sh"
  # the mount links a.sh only (b.sh and lib/c.sh are not linked)
  ln -s ../.loa/.claude/a.sh "$D/.claude/a.sh"
  printf 'aleph:\n  enabled: false\n' > "$D/.loa.config.yaml"
  source "$ROOT/.claude/scripts/compat-lib.sh"
  HA="$(sha256_portable "$D/.loa/.claude/a.sh" | cut -d' ' -f1)"
  HB="$(sha256_portable "$D/.loa/.claude/b.sh" | cut -d' ' -f1)"
  HC="$(sha256_portable "$D/.loa/.claude/lib/c.sh" | cut -d' ' -f1)"
  write_manifest
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

# write_manifest [extra-path hash]... — a/b/lib/c plus any extra pairs
write_manifest() {
  local args=(--arg a "$HA" --arg b "$HB" --arg c "$HC")
  local filter='{".claude/a.sh": $a, ".claude/b.sh": $b, ".claude/lib/c.sh": $c}'
  if [[ $# -ge 2 ]]; then
    args+=(--arg xp "$1" --arg xh "$2")
    filter="$filter + {(\$xp): \$xh}"
  fi
  jq -n "${args[@]}" "{generated: \"2026-10-15T00:00:00Z\", algorithm: \"sha256\", files: ($filter)}" \
    > "$D/.claude/checksums.json"
}

run_integrity() {
  run bash -c 'cd "$1" && source "$2" && check_integrity && echo "FAILURES=$FAILURES" && [[ $FAILURES -eq 0 ]]' \
    _ "$D" "$CHECK"
}

@test "CM-1 paths in the upstream tree but not linked are not-mounted; exit unaffected" {
  run_integrity
  [ "$status" -eq 0 ]
  [[ "$output" == *"not-mounted: 2 path(s) exist in the upstream tree but are not linked by this mount"* ]]
  [[ "$output" == *"Integrity verified"* ]]
  [[ "$output" != *"Missing:"* ]]
  [[ "$output" != *"Tampered:"* ]]
  [ "$(grep -c 'not-mounted:' <<< "$output")" -eq 1 ]
}

@test "CM-2 a present file whose hash differs is Tampered and fails" {
  rm -f "$D/.claude/a.sh"
  printf 'echo tampered\n' > "$D/.claude/a.sh"
  run_integrity
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tampered: .claude/a.sh"* ]]
  [[ "$output" != *"Integrity verified"* ]]
  [[ "$output" == *"FAILURES=1"* ]]
}

@test "CM-3 a path absent locally and upstream is Missing and fails" {
  write_manifest .claude/gone.sh "$HA"
  run_integrity
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing: .claude/gone.sh"* ]]
  [[ "$output" == *"not-mounted: 2 path(s)"* ]]
  [[ "$output" != *"Integrity verified"* ]]
}

@test "CM-4 without a .loa/ submodule an absent path is Missing" {
  find "$D/.loa" -mindepth 1 -delete
  rmdir "$D/.loa"
  printf 'echo a\n' > "$D/.claude/a.sh.real"
  rm -f "$D/.claude/a.sh"
  mv "$D/.claude/a.sh.real" "$D/.claude/a.sh"
  run_integrity
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing: .claude/b.sh"* ]]
  [[ "$output" == *"Missing: .claude/lib/c.sh"* ]]
  [[ "$output" != *"not-mounted"* ]]
}

@test "CM-5 every path linked and matching: Integrity verified, no not-mounted line" {
  ln -s ../.loa/.claude/b.sh "$D/.claude/b.sh"
  mkdir -p "$D/.claude/lib"
  ln -s ../../.loa/.claude/lib/c.sh "$D/.claude/lib/c.sh"
  run_integrity
  [ "$status" -eq 0 ]
  [[ "$output" == *"Integrity verified"* ]]
  [[ "$output" != *"not-mounted"* ]]
}

@test "CM-6 no checksums file: warn and skip, no failure" {
  rm -f "$D/.claude/checksums.json"
  run_integrity
  [ "$status" -eq 0 ]
  [[ "$output" == *"No checksums file - skipping integrity check"* ]]
}
