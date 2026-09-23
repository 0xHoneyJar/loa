#!/usr/bin/env bats
# =============================================================================
# tests/unit/loa-status-artefacts.bats — cycle-125 Sprint 2 (PRD FR-2)
# `/loa` prints an `Artefacts:` line with the sizes of prd/sdd/sprint/NOTES
# and flags anything at or over the 100 KiB warn line with the section-read
# remedy (display_artefacts_line in loa-status.sh).
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"
  GEN="$PROJECT_ROOT/tests/fixtures/notes/make-large-notes.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/lsa.XXXXXX")"
}

teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "LSA-1 human output carries an Artefacts line naming the four planning artefacts that exist" {
  run timeout 120 bash "$STATUS"
  [ "$status" -eq 0 ]
  local line; line=$(echo "$output" | grep '^  Artefacts:' | head -1)
  [ -n "$line" ]
  for f in prd sdd sprint NOTES; do
    [ -f "$PROJECT_ROOT/grimoires/loa/$f.md" ] || continue
    [[ "$line" =~ " $f "[0-9]+K ]]
  done
}

@test "LSA-2 a NOTES.md at the warn line is flagged with the section-read remedy; small artefacts are not" {
  mkdir -p "$T/g"
  "$GEN" "$T/g/NOTES.md" 100k
  printf '## Sprint 1: x\n\nbody\n' > "$T/g/sprint.md"
  LOA_GRIMOIRE_DIR="$T/g" run timeout 60 bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^  Artefacts: sprint 1K NOTES 101K'
  echo "$output" | grep -q '⚠ ≥ 100 KiB: NOTES.md — read by section: notes-guard.sh read --file <F> --section <H>'
  "$GEN" "$T/g/NOTES.md" under
  LOA_GRIMOIRE_DIR="$T/g" run timeout 60 bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^  Artefacts: sprint 1K NOTES [12]K'
  ! echo "$output" | grep -q '≥ 100 KiB'
}

@test "LSA-3 --json output is unchanged by the Artefacts line (still one valid envelope)" {
  run timeout 60 bash "$STATUS" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.state' >/dev/null
  [[ "$output" != *"Artefacts:"* ]]
}
