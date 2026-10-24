#!/usr/bin/env bats
# =============================================================================
# notes-guard-rotate.bats — `notes-guard.sh rotate` retention section by
# section (cycle-133 Sprint 1 Task 1.5; SDD C-4(b); PRD FR-4(b); bd-rz5ks).
#
# The retained file carries, in order: every `## Blockers` block whole, every
# `## Active Sub-Goals` block whole, the newest `## Session Continuity` block
# whole, the three newest `## Decision Log` blocks (the only section truncated
# to the byte budget), the newest 20 `## Session Log` entries, then the archive
# pointer. A section missing from the source is emitted as its header alone.
# check-loa.sh's NOTES section checks pass on the result.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  GUARD="$PROJECT_ROOT/.claude/scripts/notes-guard.sh"
  T="$BATS_TEST_TMPDIR"
  G="$T/grimoires/loa"
  mkdir -p "$G"
  N="$G/NOTES.md"
}

fixture() {
  {
    printf '# Project Memory\n\n## Current Focus\n- dropped focus\n\n'
    printf '## Blockers\n\n- [ ] BLOCKER-ONE first open blocker\n  continuation line of blocker one\n- [ ] BLOCKER-TWO second open blocker\n\n'
    printf '## Active Sub-Goals\n\n- SUBGOAL-ONE ship the record script\n  - nested detail of sub-goal one\n- SUBGOAL-TWO rotate notes safely\n\n'
    printf '## Session Log\n\n<!-- append-only -->\n\n| Timestamp | Event | Outcome |\n|-----------|-------|---------|\n'
    local i; for i in $(seq -w 1 25); do printf '| 2026-10-%s | SLOG-%s | ok |\n' "$i" "$i"; done
    printf '\n## Decision Log — 2026-10-01\n- DL-1001 oldest\n\n'
    printf '## Decision Log — 2026-10-04\n- DL-1004 newest\n\n'
    printf '## Session Continuity — 2026-10-02\nSC-OLD must go\n\n'
    printf '## Decision Log — 2026-10-02\n- DL-1002 third\n\n'
    printf '## Session Continuity — 2026-10-05\n### Active Context\nSC-NEW line one\nSC-NEW line two\n\n'
    printf '## Decision Log — 2026-10-03\n- DL-1003 second\n\n'
    printf '## Learnings\n- dropped learning\n'
  } > "$N"
}

# check-loa.sh's two NOTES checks, sourced (its main is guarded), against $N.
check_loa_sections() {
  ( cd "$T" && NOTES_FILE="grimoires/loa/NOTES.md" bash -c '
      source "$1" >/dev/null 2>&1
      NOTES_FILE="grimoires/loa/NOTES.md"; FAILURES=0
      check_memory; check_notes_template' _ "$PROJECT_ROOT/.claude/scripts/check-loa.sh" 2>&1 )
}

@test "rotate: two open blockers and two sub-goals survive whole, and check-loa.sh's section checks pass" {
  fixture
  run "$GUARD" rotate --file "$N"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF -- '- [ ] BLOCKER-ONE first open blocker' "$N"
  grep -qF -- '  continuation line of blocker one' "$N"
  grep -qF -- '- [ ] BLOCKER-TWO second open blocker' "$N"
  grep -qF -- '- SUBGOAL-ONE ship the record script' "$N"
  grep -qF -- '  - nested detail of sub-goal one' "$N"
  grep -qF -- '- SUBGOAL-TWO rotate notes safely' "$N"
  run check_loa_sections
  [[ "$output" != *"NOTES.md missing"* ]] || { echo "$output"; false; }
  [[ "$output" == *"Structured memory present and valid"* ]]
}

@test "rotate: newest Session Continuity whole, three newest Decision Logs, newest 20 Session Log entries, sections in order" {
  fixture
  run "$GUARD" rotate --file "$N"
  [ "$status" -eq 0 ]
  grep -q 'SC-NEW line one' "$N"; grep -q 'SC-NEW line two' "$N"
  ! grep -q 'SC-OLD' "$N"
  grep -q 'DL-1004' "$N"; grep -q 'DL-1003' "$N"; grep -q 'DL-1002' "$N"
  ! grep -q 'DL-1001' "$N"
  [ "$(grep -c 'SLOG-' "$N")" -eq 20 ]
  ! grep -q 'SLOG-05 ' "$N"
  grep -q 'SLOG-06 ' "$N"; grep -q 'SLOG-25 ' "$N"
  grep -qF '| Timestamp | Event | Outcome |' "$N"
  ! grep -q 'dropped' "$N"
  order="$(grep -E '^## ' "$N" | sed -E 's/ —.*//' | uniq | paste -sd'|' -)"
  [ "$order" = "## Blockers|## Active Sub-Goals|## Session Continuity|## Decision Log|## Session Log|## Archive pointers" ] || { echo "$order"; false; }
}

@test "rotate: a section missing from the source is emitted as its header with no body" {
  printf '## Blockers\n\n- [ ] ONLY-BLOCKER\n\n## Decision Log — 2026-10-01\n- DL-ONLY\n' > "$N"
  run "$GUARD" rotate --file "$N"
  [ "$status" -eq 0 ]
  for h in '## Active Sub-Goals' '## Session Continuity' '## Session Log'; do
    grep -qxF "$h" "$N" || { echo "no header $h"; cat "$N"; false; }
  done
  # the header-only section has no body before the next header
  awk '/^## Active Sub-Goals$/ { f = 1; next } f && /^## / { exit } f && NF { bad = 1 } END { exit bad }' "$N"
  run check_loa_sections
  [[ "$output" != *"NOTES.md missing"* ]] || { echo "$output"; false; }
}

@test "rotate: a Blockers section larger than the read cap survives whole (only Decision Log is truncated)" {
  {
    printf '## Blockers\n\n'
    awk 'BEGIN { for (i = 1; i <= 1300; i++) printf "- [ ] BIG-BLOCKER %05d ............................................\n", i }'
    printf '\n## Decision Log — 2026-10-01\n- DL-X\n'
    awk 'BEGIN { for (i = 1; i <= 2000; i++) printf "  dl padding %05d ............................................\n", i }'
  } > "$N"
  [ "$(stat -c%s "$N")" -gt 69632 ]
  run "$GUARD" rotate --file "$N"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'BIG-BLOCKER' "$N")" -eq 1300 ]
  grep -q 'BIG-BLOCKER 01300' "$N"
  grep -q '^## Decision Log' "$N"
  grep -q 'notes-guard: Decision Log truncated' "$N"
}
