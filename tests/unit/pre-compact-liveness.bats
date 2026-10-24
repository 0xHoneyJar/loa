#!/usr/bin/env bats
# =============================================================================
# pre-compact-liveness.bats — `.claude/hooks/pre-compact-marker.sh` reports a
# workflow live only from its state allowlist and recency (cycle-133 Sprint 1
# Task 1.5; SDD C-4(c); PRD FR-4(c); bd-nbs7w).
#
# `.state` + `timestamps.last_activity`: RUNNING → active; HALTED, INTERRUPTED
# (simstim also AWAITING_HITL) → awaiting resume; COMPLETED, JACKED_OUT, an
# absent or unreadable file, an unknown state, or last_activity older than
# LOA_HOOK_LIVE_WINDOW_DAYS (default 7) → silent. Silent means the marker
# says active=false and the post-compact reminder announces nothing.
# =============================================================================

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  MARKER="$REPO/.claude/hooks/pre-compact-marker.sh"
  REMINDER="$REPO/.claude/hooks/post-compact-reminder.sh"
  FIX="$BATS_TEST_TMPDIR/proj"; mkdir -p "$FIX/.run"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset LOA_HOOK_LIVE_WINDOW_DAYS
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  OLD="$(date -u -d '-30 days' +%Y-%m-%dT%H:%M:%SZ)"
}

state() {  # file state last_activity [phase]
  jq -n --arg s "$2" --arg t "$3" --arg p "${4:-implementation}" \
    '{state: $s, phase: $p, timestamps: {started: $t, last_activity: $t}}' > "$FIX/.run/$1"
}
mark() { (cd "$FIX" && PROJECT_ROOT="$FIX" bash "$MARKER"); }
m() { jq -r "$1" "$FIX/.run/compact-pending"; }
remind() { (cd "$FIX" && PROJECT_ROOT="$FIX" bash "$REMINDER" </dev/null 2>&1); }

@test "liveness: a COMPLETED simstim file is silent (marker inactive, reminder announces nothing)" {
  state simstim-state.json COMPLETED "$NOW" implementation
  run mark; [ "$status" -eq 0 ]
  [ "$(m .simstim.active)" = "false" ]
  [ "$(m .simstim.liveness)" = "silent" ]
  [ "$(m .active_skill_doc)" = "" ]
  out="$(remind)"
  [[ "$out" != *"Simstim was ACTIVE"* ]]
}

@test "liveness: a RUNNING run state is active and the reminder says so" {
  state sprint-plan-state.json RUNNING "$NOW"
  run mark; [ "$status" -eq 0 ]
  [ "$(m .run_mode.active)" = "true" ]
  [ "$(m .run_mode.liveness)" = "active" ]
  [ "$(m .active_skill_doc)" = ".claude/skills/run-mode/SKILL.md" ]
  out="$(remind)"
  [[ "$out" == *"Run Mode was ACTIVE"*"RUNNING"* ]]
}

@test "liveness: a HALTED run state is awaiting resume (no autonomous resume, no active skill)" {
  state sprint-plan-state.json HALTED "$NOW"
  run mark
  [ "$(m .run_mode.liveness)" = "awaiting_resume" ]
  [ "$(m .run_mode.active)" = "true" ]
  [ "$(m .active_skill_doc)" = "" ]
  out="$(remind)"
  [[ "$out" != *"Resume sprint execution AUTONOMOUSLY"* ]]
}

@test "liveness: an INTERRUPTED simstim is awaiting resume" {
  state simstim-state.json INTERRUPTED "$NOW" flatline_sdd
  run mark
  [ "$(m .simstim.liveness)" = "awaiting_resume" ]
  [ "$(m .simstim.active)" = "true" ]
  [ "$(m .simstim.phase)" = "flatline_sdd" ]
}

@test "liveness: an unknown state, JACKED_OUT, an unreadable file and an absent file are silent" {
  state sprint-plan-state.json SOMETHING_ELSE "$NOW"
  run mark
  [ "$(m .run_mode.liveness)" = "silent" ]; [ "$(m .run_mode.active)" = "false" ]
  state sprint-plan-state.json JACKED_OUT "$NOW"
  run mark
  [ "$(m .run_mode.liveness)" = "silent" ]
  printf 'NOT JSON {{' > "$FIX/.run/sprint-plan-state.json"
  run mark; [ "$status" -eq 0 ]
  [ "$(m .run_mode.liveness)" = "silent" ]; [ "$(m .run_mode.active)" = "false" ]
  rm -f "$FIX/.run/sprint-plan-state.json"
  run mark
  [ "$(m .run_mode.liveness)" = "silent" ]
  out="$(remind)"
  [[ "$out" != *"Run Mode was ACTIVE"* ]]
}

@test "liveness: last_activity older than the window is silent; LOA_HOOK_LIVE_WINDOW_DAYS widens it" {
  state simstim-state.json RUNNING "$OLD" implementation
  run mark
  [ "$(m .simstim.liveness)" = "silent" ]; [ "$(m .simstim.active)" = "false" ]
  (cd "$FIX" && LOA_HOOK_LIVE_WINDOW_DAYS=60 PROJECT_ROOT="$FIX" bash "$MARKER")
  [ "$(m .simstim.liveness)" = "active" ]
  [ "$(m .active_skill_doc)" = ".claude/skills/simstim-workflow/SKILL.md" ]
}

@test "liveness: an unparseable last_activity is silent" {
  state sprint-plan-state.json RUNNING "yesterday-ish"
  run mark
  [ "$(m .run_mode.liveness)" = "silent" ]
}
