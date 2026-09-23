#!/usr/bin/env bats
# =============================================================================
# tests/unit/run-state-surface.bats — cycle-125 Sprint 3 (PRD FR-3 AC 3, SDD D-3.3)
# .claude/hooks/session-start/loa-run-state-surface.sh prints the exact resume
# line for a stale/halted run state and nothing for a clean one; the same
# script feeds loa-status.sh's `Run:` line and workflow-state's suggestion.
# =============================================================================

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SURF="$PROJECT_ROOT/.claude/hooks/session-start/loa-run-state-surface.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/rss.XXXXXX")"
  mkdir -p "$T/.run"
  NOW=$(date +%s)
  FRESH=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  STALE=$(date -u -d "@$(( NOW - 14*3600 ))" +%Y-%m-%dT%H:%M:%SZ)
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

surf() { run bash "$SURF" --root "$T" "$@"; }

@test "RSS-1 clean tree, no .run, fresh RUNNING, JACKED_OUT: nothing printed, exit 0" {
  rmdir "$T/.run"; surf; [ "$status" -eq 0 ]; [ -z "$output" ]
  mkdir -p "$T/.run"; surf; [ "$status" -eq 0 ]; [ -z "$output" ]
  printf '{"state":"RUNNING","timestamps":{"last_activity":"%s"}}\n' "$FRESH" > "$T/.run/sprint-plan-state.json"
  surf; [ "$status" -eq 0 ]; [ -z "$output" ]
  printf '{"state":"JACKED_OUT","timestamps":{"last_activity":"%s"}}\n' "$STALE" > "$T/.run/sprint-plan-state.json"
  surf; [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "RSS-2 HALTED sprint-plan state prints the resume line with age and /run-resume" {
  printf '{"state":"HALTED","timestamps":{"last_activity":"%s"}}\n' "$STALE" > "$T/.run/sprint-plan-state.json"
  surf
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l)" -eq 1 ]
  [[ "$output" =~ ^"Run: sprint-plan HALTED (1"[34]"h ago) → /run-resume" ]]
}

@test "RSS-3 RUNNING older than 12h is surfaced as stale with the beads-truth note; INTERRUPTED and state.json HALTED are surfaced too" {
  printf '{"state":"RUNNING","timestamps":{"last_activity":"%s"}}\n' "$STALE" > "$T/.run/sprint-plan-state.json"
  surf
  [[ "$output" =~ "Run: sprint-plan RUNNING but idle for 1"[34]"h → /run-resume" ]]
  [[ "$output" == *"beads hold the task truth"* ]]
  printf '{"state":"INTERRUPTED","timestamps":{"last_activity":"%s"}}\n' "$FRESH" > "$T/.run/sprint-plan-state.json"
  printf '{"run_id":"r","state":"HALTED","timestamps":{"last_activity":"%s"}}\n' "$FRESH" > "$T/.run/state.json"
  surf
  [ "$(echo "$output" | wc -l)" -eq 2 ]
  echo "$output" | grep -q '^Run: sprint-plan INTERRUPTED (0m ago) → /run-resume$'
  echo "$output" | grep -q '^Run: run HALTED (0m ago) → /run-resume$'
}

@test "RSS-4 simstim RUNNING older than 12h suggests /simstim --resume; fresh simstim is silent" {
  printf '{"phase":"implementation","status":"RUNNING","updated_at":"%s"}\n' "$STALE" > "$T/.run/simstim-state.json"
  surf
  [[ "$output" == *"Run: simstim RUNNING but idle for 1"* && "$output" == *"/simstim --resume"* ]]
  printf '{"phase":"implementation","status":"RUNNING","updated_at":"%s"}\n' "$FRESH" > "$T/.run/simstim-state.json"
  surf; [ -z "$output" ]
}

@test "RSS-5 session-limit reset in the past prints the resume-available line; in the future prints nothing" {
  printf '{"hit_at":"x","reset_at":"2026-09-23T01:00:00+00:00","reset_at_epoch":%d}\n' $(( NOW - 60 )) > "$T/.run/session-limit-state.json"
  surf
  [ "$status" -eq 0 ]
  [[ "$output" == "Session limit reset at 2026-09-23T01:00:00+00:00 — resume available: /run-resume"* ]]
  printf '{"hit_at":"x","reset_at":"later","reset_at_epoch":%d}\n' $(( NOW + 3600 )) > "$T/.run/session-limit-state.json"
  surf; [ -z "$output" ]
}

@test "RSS-6 malformed JSON and control characters never break the hook: silent or sanitised, exit 0" {
  printf 'not json' > "$T/.run/sprint-plan-state.json"
  surf; [ "$status" -eq 0 ]; [ -z "$output" ]
  printf '{"state":"HALTED[31m","timestamps":{"last_activity":"%s"}}\n' "$FRESH" > "$T/.run/sprint-plan-state.json"
  surf; [ "$status" -eq 0 ]; [[ "$output" != *$'\033'* ]]
}

@test "RSS-7 hook wiring: present in both settings files, behind hook-guard.sh, once per session" {
  for f in "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/hooks/settings.hooks.json"; do
    jq -e '[.hooks.SessionStart[].hooks[] | select(.command | test("hook-guard.sh.*loa-run-state-surface.sh"))] | length == 1' "$f" >/dev/null
    jq -e '.hooks.SessionStart[].hooks[] | select(.command | test("loa-run-state-surface.sh")) | .once == true' "$f" >/dev/null
  done
}
