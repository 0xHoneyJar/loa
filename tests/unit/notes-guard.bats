#!/usr/bin/env bats
# =============================================================================
# tests/unit/notes-guard.bats — cycle-124 Sprint 4 (PRD FR-10, AC-10.1 / AC-10.2)
#
# .claude/scripts/notes-guard.sh {check [--delta N] | read [--full] | rotate}
# --file PATH. Fixtures are generated at test time by
# tests/fixtures/notes/make-large-notes.sh (nothing large is committed).
# Thresholds are literals: 102,400 B warn, 204,800 B block; `read` is capped at
# 69,632 B (68 KiB = 20k tokens × 3.5 with headroom).
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GUARD="$PROJECT_ROOT/.claude/scripts/notes-guard.sh"
  GEN="$PROJECT_ROOT/tests/fixtures/notes/make-large-notes.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ng.XXXXXX")"
  G="$T/grimoires/loa"
  mkdir -p "$G"
  N="$G/NOTES.md"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

tokens_of() {  # bytes*10/35 — the estimate_tokens heuristic (len/3.5)
  local b; b=$(stat -c%s "$1"); echo $(( b * 10 / 35 ))
}

# --- read --------------------------------------------------------------------

@test "NG-1 read on the 750 KB fixture: ≤ 20k tokens, non-empty, carries Blockers / Session Continuity / Decision Log, names read --full" {
  "$GEN" "$N" 750k
  [ "$(stat -c%s "$N")" -ge 768000 ]
  run "$GUARD" read --file "$N"
  [ "$status" -eq 0 ]
  printf '%s' "$output" > "$T/out"
  [ -s "$T/out" ]
  [ "$(stat -c%s "$T/out")" -le 69632 ]
  [ "$(tokens_of "$T/out")" -le 20000 ]
  grep -q '^## Blockers' "$T/out"
  grep -q '^## Session Continuity' "$T/out"
  grep -q '^## Decision Log' "$T/out"
  grep -q 'read --full' "$T/out"
}

@test "NG-2 read selects by heading date: all Blockers blocks, the newest Session Continuity, the 3 newest Decision Logs — Blockers first" {
  "$GEN" "$N" under
  run "$GUARD" read --file "$N"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$T/out"
  grep -q 'B-1 first blockers block' "$T/out"
  grep -q 'B-2 second blockers block' "$T/out"
  grep -q 'NEWEST-CONTINUITY-0910' "$T/out"
  ! grep -q 'OLD-CONTINUITY-0901' "$T/out"
  grep -q 'D-0905' "$T/out"
  grep -q 'D-0904' "$T/out"
  grep -q 'D-0903' "$T/out"
  ! grep -q 'D-0902' "$T/out"
  ! grep -q 'D-0901' "$T/out"
  ! grep -q '^## Learnings' "$T/out"
  ! grep -q '^## Current Focus' "$T/out"
  # order: Blockers before Session Continuity before the Decision Logs (newest first)
  local lb ls l5 l4 l3
  lb=$(grep -n '^## Blockers' "$T/out" | head -1 | cut -d: -f1)
  ls=$(grep -n '^## Session Continuity' "$T/out" | head -1 | cut -d: -f1)
  l5=$(grep -n 'D-0905' "$T/out" | cut -d: -f1); l4=$(grep -n 'D-0904' "$T/out" | cut -d: -f1); l3=$(grep -n 'D-0903' "$T/out" | cut -d: -f1)
  [ "$lb" -lt "$ls" ] && [ "$ls" -lt "$l5" ] && [ "$l5" -lt "$l4" ] && [ "$l4" -lt "$l3" ]
  # a small file is not capped and carries no footer
  ! grep -q 'read --full' "$T/out"
}

@test "NG-3 read falls back loudly on template drift and is never empty" {
  printf '# notes\n\n## Foo\nbar\n\n## Baz\nqux\n' > "$N"
  run "$GUARD" read --file "$N"
  [ "$status" -eq 0 ]
  [[ "$output" == NOTES-GUARD:*"no known sections"* ]]
  grep -q '## Foo' <<<"$output"
  : > "$N"
  run "$GUARD" read --file "$N"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "NG-4 read --full is byte-identical to the file" {
  "$GEN" "$N" 250k
  "$GUARD" read --full --file "$N" > "$T/full"
  cmp -s "$N" "$T/full"
}

# --- check -------------------------------------------------------------------

@test "NG-5 check: silent below 100 KiB, NOTES-WARN at 100 KiB (exit 0), NOTES-BLOCK with the remedy at 200 KiB (exit 3), missing file exit 0" {
  "$GEN" "$N" under
  run "$GUARD" check --file "$N"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  "$GEN" "$N" 100k
  run "$GUARD" check --file "$N"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOTES-WARN"* ]]
  [[ "$output" == *"rotate"* ]]
  "$GEN" "$N" 200k
  run "$GUARD" check --file "$N"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NOTES-BLOCK"* ]]
  [[ "$output" == *"notes-guard.sh rotate"* ]]
  run "$GUARD" check --file "$T/does-not-exist.md"
  [ "$status" -eq 0 ]
}

@test "NG-6 check --delta is direction-aware: shrinking passes at 200 KiB, growing is refused, and a growing write that crosses the line is refused" {
  "$GEN" "$N" 200k
  run "$GUARD" check --delta -5 --file "$N"
  [ "$status" -eq 0 ]
  run "$GUARD" check --delta 0 --file "$N"
  [ "$status" -eq 0 ]
  run "$GUARD" check --delta 5 --file "$N"
  [ "$status" -eq 3 ]
  "$GEN" "$N" 204700          # just under the block line (the generator lands in [204700, 204763])
  run "$GUARD" check --delta 20 --file "$N"
  [ "$status" -eq 0 ]
  run "$GUARD" check --delta 200 --file "$N"
  [ "$status" -eq 3 ]
}

# --- rotate ------------------------------------------------------------------

@test "NG-7 rotate: archive equals the original and is fsynced before the live file changes; retained < 100 KiB with both recovery headings and an archive pointer; archive path gitignored" {
  "$GEN" "$N" 250k
  cp "$N" "$T/orig"
  run "$GUARD" rotate --file "$N"
  [ "$status" -eq 0 ]
  local arch; arch=$(ls "$G"/archive/notes/NOTES-*.md | head -1)
  [ -n "$arch" ]
  cmp -s "$T/orig" "$arch"
  local o a r; o=$(stat -c%s "$T/orig"); a=$(stat -c%s "$arch"); r=$(stat -c%s "$N")
  [ $(( a + r )) -ge "$o" ]
  [ "$r" -lt 102400 ]
  grep -q '^## Session Continuity' "$N"
  grep -q '^## Decision Log' "$N"
  grep -q '^## Blockers' "$N"
  grep -q '^## Archive pointers' "$N"
  grep -qF "$(basename "$arch")" "$N"
  grep -q 'NEWEST-CONTINUITY-0910' "$N"
  ! grep -q 'OLD-CONTINUITY-0901' "$N"
  # ordering: the archive was completed (mtime) no later than the live rewrite
  python3 - "$arch" "$N" <<'PY'
import os, sys
a, n = sys.argv[1], sys.argv[2]
assert os.stat(a).st_mtime_ns <= os.stat(n).st_mtime_ns, "archive must be written before the live file"
PY
  # the archive location is gitignored in this repo
  ( cd "$PROJECT_ROOT" && git check-ignore -q grimoires/loa/archive/notes/NOTES-20260101T000000Z.md )
}

@test "NG-8 rotate refuses an existing target (exit 4) and leaves the live file unchanged" {
  "$GEN" "$N" 250k
  cp "$N" "$T/orig"
  mkdir -p "$G/archive/notes"
  # occupy the target names for this second and the next, so the collision is race-free
  local now next
  now=$(date -u +%s); next=$(( now + 1 ))
  : > "$G/archive/notes/NOTES-$(date -u -d "@$now" +%Y%m%dT%H%M%SZ).md"
  : > "$G/archive/notes/NOTES-$(date -u -d "@$next" +%Y%m%dT%H%M%SZ).md"
  run "$GUARD" rotate --file "$N"
  [ "$status" -eq 4 ]
  cmp -s "$N" "$T/orig"
}

@test "NG-9 rotate is not blocked at 200 KiB (no deadlock): the escape hatch works and check is silent afterwards" {
  "$GEN" "$N" 200k
  run "$GUARD" check --file "$N"
  [ "$status" -eq 3 ]
  run "$GUARD" rotate --file "$N"
  [ "$status" -eq 0 ]
  run "$GUARD" check --file "$N"
  [ "$status" -eq 0 ]
}

@test "NG-10 rotate never uses git stash" {
  ! grep -qE 'git[[:space:]]+stash' "$GUARD"
}

# --- writer gate -------------------------------------------------------------

@test "NG-11 update-notes-learnings.sh exits 3 and leaves NOTES.md byte-identical at 200 KiB; below the line it still appends" {
  "$GEN" "$N" 200k
  cp "$N" "$T/orig"
  local learn='[{"signature":"fixture-learning","type":"pattern","confidence":0.9,"sessions":["s1"]}]'
  run env LOA_GRIMOIRE_DIR="$G" "$PROJECT_ROOT/.claude/scripts/update-notes-learnings.sh" --learnings <(printf '%s' "$learn")
  [ "$status" -eq 3 ]
  cmp -s "$N" "$T/orig"
  [[ "$output" == *"NOTES-BLOCK"* ]]
  "$GEN" "$N" under
  cp "$N" "$T/orig"
  printf '%s' "$learn" > "$T/learn.json"
  run env LOA_GRIMOIRE_DIR="$G" "$PROJECT_ROOT/.claude/scripts/update-notes-learnings.sh" --learnings "$T/learn.json"
  [ "$status" -eq 0 ]
  grep -q 'fixture-learning' "$N"
}

# --- usage -------------------------------------------------------------------

@test "NG-12 usage errors exit 2: unknown subcommand, missing --file value, non-integer --delta" {
  run "$GUARD" bogus --file "$N"
  [ "$status" -eq 2 ]
  run "$GUARD" check --file
  [ "$status" -eq 2 ]
  "$GEN" "$N" under
  run "$GUARD" check --delta abc --file "$N"
  [ "$status" -eq 2 ]
}
