#!/usr/bin/env bats
# =============================================================================
# tests/integration/implement-reentry.bats — cycle-125 Sprint 3 Task 3.5
# (PRD FR-3 AC 2): re-entry proof. `/implement sprint-N` claims work through
# `br ready` and closes one bead per task; a new session therefore skips closed
# beads without any state file. This fixture proves it against the REAL `br`
# in a throwaway workspace, and shows the checkpoint helper agreeing with beads.
# Skips when beads_rust is not installed.
# =============================================================================

setup() {
  command -v br >/dev/null 2>&1 || skip "br (beads_rust) not installed"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CK="$PROJECT_ROOT/.claude/scripts/run-checkpoint.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/reentry.XXXXXX")"
  cd "$T"
  git init -q . && br init >/dev/null 2>&1 || skip "br init failed in a temp workspace"
  mkdir -p .run
  br create "Task 1.1: first" -p 1 >/dev/null
  br create "Task 1.2: second" -p 1 >/dev/null
  br create "Task 1.3: third" -p 1 >/dev/null
  # ids in creation order
  mapfile -t IDS < <(br list --json 2>/dev/null | jq -r '.issues | sort_by(.created_at) | .[].id')
  [ "${#IDS[@]}" -eq 3 ]
}
teardown() { cd /; find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

@test "RE-1 after one task is closed, br ready lists only the open beads (a fresh session cannot re-do the closed task)" {
  br update "${IDS[0]}" --status in_progress >/dev/null
  br close "${IDS[0]}" -r "done in session 1" >/dev/null
  run br ready
  [ "$status" -eq 0 ]
  [[ "$output" != *"${IDS[0]}"* ]]
  [[ "$output" == *"${IDS[1]}"* && "$output" == *"${IDS[2]}"* ]]
  run br list --status open --json
  [ "$(echo "$output" | jq -r '.issues | length')" -eq 2 ]
}

@test "RE-2 the checkpoint helper agrees with beads: a checkpoint naming the closed task is trusted, one naming an open task is discarded" {
  br close "${IDS[0]}" -r done >/dev/null
  printf '{"plan_id":"p","state":"RUNNING","timestamps":{"last_activity":"2026-09-23T00:00:00Z"},"sprints":{"current":"sprint-1"}}\n' > .run/sprint-plan-state.json
  bash "$CK" write --file .run/sprint-plan-state.json --sprint sprint-1 --task "${IDS[0]}" --phase IMPLEMENT
  run bash "$CK" read --file .run/sprint-plan-state.json --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e --arg t "${IDS[0]}" '.checkpoint.task==$t' >/dev/null
  bash "$CK" write --file .run/sprint-plan-state.json --sprint sprint-1 --task "${IDS[1]}" --phase IMPLEMENT
  run bash "$CK" read --file .run/sprint-plan-state.json --json
  echo "$output" | tail -n1 | jq -e '.checkpoint==null and (.reason|test("not closed"))' >/dev/null
  # and the resume point beads give is the first open bead
  run br ready
  [[ "$output" == *"${IDS[1]}"* ]]
}
