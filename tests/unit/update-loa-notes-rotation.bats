#!/usr/bin/env bats
# =============================================================================
# tests/unit/update-loa-notes-rotation.bats — cycle-125 Sprint 2 (PRD FR-2 AC 4)
# update-loa.sh rotates a NOTES.md that is at or over the 200 KiB block line
# after a refresh (rotate_oversized_notes), loudly, archive-first; below the
# line it leaves the file byte-identical. Fixtures are generated at test time.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  UPDATE="$PROJECT_ROOT/.claude/scripts/update-loa.sh"
  GEN="$PROJECT_ROOT/tests/fixtures/notes/make-large-notes.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ulr.XXXXXX")"
  mkdir -p "$T/grimoires/loa"
  N="$T/grimoires/loa/NOTES.md"
  unset LOA_GRIMOIRE_DIR
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

run_rotation() {  # sources update-loa.sh (main is guarded) and runs the step from $T
  run bash -c "cd '$T' && source '$UPDATE' && rotate_oversized_notes"
}

@test "ULR-1 a ≥ 200 KiB NOTES.md is rotated on update: archive first, live file keeps the recovery sections, log line names it" {
  "$GEN" "$N" 250k
  local before; before=$(stat -c%s "$N")
  [ "$before" -ge 204800 ]
  run_rotation
  [ "$status" -eq 0 ]
  [[ "$output" == *"rotating"* && "$output" == *"rotated"* ]]
  local archive; archive=$(ls "$T/grimoires/loa/archive/notes/"NOTES-*.md | head -1)
  [ -n "$archive" ]
  [ "$(stat -c%s "$archive")" -eq "$before" ]
  [ "$(stat -c%s "$N")" -lt 102400 ]
  grep -q '^## Blockers' "$N"
  grep -q '^## Session Continuity' "$N"
  grep -q '^## Archive pointers' "$N"
  # check is silent afterwards: the upgraded framework can append again
  run bash "$PROJECT_ROOT/.claude/scripts/notes-guard.sh" check --file "$N"
  [ "$status" -eq 0 ]
}

@test "ULR-2 below the block line nothing happens: file byte-identical, no rotation log, no archive" {
  "$GEN" "$N" 100k
  local sum; sum=$(sha256sum "$N" | cut -d' ' -f1)
  run_rotation
  [ "$status" -eq 0 ]
  [[ "$output" != *"rotat"* ]]
  [ "$(sha256sum "$N" | cut -d' ' -f1)" = "$sum" ]
  [ ! -d "$T/grimoires/loa/archive/notes" ]
}

@test "ULR-3 no NOTES.md (fresh mount) is a silent no-op; LOA_GRIMOIRE_DIR is honoured" {
  run_rotation
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  mkdir -p "$T/elsewhere"
  "$GEN" "$T/elsewhere/NOTES.md" 250k
  run bash -c "cd '$T' && export LOA_GRIMOIRE_DIR='$T/elsewhere' && source '$UPDATE' && rotate_oversized_notes"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rotated"* ]]
  [ -d "$T/elsewhere/archive/notes" ]
}

@test "ULR-4 main() calls the rotation step after the learning import and before the summary" {
  awk '/^main\(\) \{/,/^\}/' "$UPDATE" > "$T/main.txt"
  grep -n 'import_upstream_learnings$' "$T/main.txt" | head -1 | cut -d: -f1 > "$T/a"
  grep -n 'rotate_oversized_notes$' "$T/main.txt" | head -1 | cut -d: -f1 > "$T/b"
  grep -n 'show_friendly_summary$' "$T/main.txt" | head -1 | cut -d: -f1 > "$T/c"
  [ -s "$T/a" ] && [ -s "$T/b" ] && [ -s "$T/c" ]
  [ "$(cat "$T/a")" -lt "$(cat "$T/b")" ]
  [ "$(cat "$T/b")" -lt "$(cat "$T/c")" ]
}
