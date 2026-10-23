#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/run-checkpoint-derive.bats — cycle-129 Sprint 2 Task 2.10
# (PRD FR-5 AC-5.1 … AC-5.4, FR-4(f) AC-4.6; SDD D-5.1, D-5.1a, D-5.2, D-5.3, D-5.4)
# `run-checkpoint.sh derive` rebuilds the run position from files: one case per
# decision-table row, the breaker recompute from the feedback history, the
# write path and its rollback knob, and one case per known reader over a
# derived file. Fixture: a tiny git repo with a ledger, a2a/ and .run/ in a
# temp dir; nothing touches this checkout's .run/.
# =============================================================================

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CK="$REPO/.claude/scripts/run-checkpoint.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/rcd.XXXXXX")"
  R="$T/repo"
  mkdir -p "$R/grimoires/loa/a2a" "$R/.run" "$R/src"
  git -C "$R" init -q
  printf 'x\n' > "$R/src/a.ts"
  git -C "$R" add -A
  git -C "$R" -c user.name=t -c user.email=t@example.invalid commit -qm "feat: impl"
  ledger completed completed completed
  unset LOA_RUN_DIR LOA_IMPLEMENT_GATE_OVERRIDE
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

# ledger STATUS101 STATUS102 STATUS103 [EXTRA-SPRINT-JSON]
ledger() {
  jq -n --arg a "$1" --arg b "$2" --arg c "$3" --argjson x "${4:-null}" '
    {schema_version: 1, active_cycle: "cycle-x", next_sprint_number: 104,
     cycles: [
       {id: "cycle-old", status: "archived", created: "2025-01-01T00:00:00Z",
        sprints: [{global_id: 1, local_label: "sprint-1", status: "completed", created: "2025-01-01T00:00:00Z"}]},
       {id: "cycle-x", status: "active", created: "2026-01-01T00:00:00Z",
        sprints: ([{global_id: 101, local_label: "sprint-1", status: $a, created: "2026-01-01T00:00:00Z"},
                   {global_id: 102, local_label: "sprint-2", status: $b, created: "2026-01-01T00:00:00Z"},
                   {global_id: 103, local_label: "sprint-3", status: $c, created: "2026-01-01T00:00:00Z"}]
                  + (if $x == null then [] else [$x] end))}]}' > "$R/grimoires/loa/ledger.json"
}

# feedback GID GATE VERDICT [SPRINT_ID] [ROUND] [MEDIUM] [TS] — a feedback file whose trailer verdict-derive accepts
feedback() {
  local gid="$1" gate="$2" verdict="$3" sid="${4:-sprint-$1}" round="${5:-}" med="${6:-0}" ts="${7:-2026-06-01T00:00:00Z}" f prose
  mkdir -p "$R/grimoires/loa/a2a/sprint-$gid"
  if [[ "$gate" == review ]]; then f=engineer-feedback; else f=auditor-sprint-feedback; fi
  [[ -n "$round" ]] && f="$f-r$round"
  if [[ "$verdict" == APPROVED ]]; then
    if [[ "$gate" == review ]]; then prose='All good'; else prose="APPROVED - LET'S FUCKING GO"; fi
  else
    prose=$'# Feedback\n\n## Findings\n\n- MEDIUM: something to fix'
  fi
  printf '%s\n\n<!-- LOA-VERDICT {"gate":"%s","verdict":"%s","counts":{"critical":0,"high":0,"medium":%s,"low":0},"sprint_id":"%s","ts":"%s"} -->\n' \
    "$prose" "$gate" "$verdict" "$med" "$sid" "$ts" > "$R/grimoires/loa/a2a/sprint-$gid/$f.md"
}

# complete GID [SPRINT_ID] — review + audit APPROVED and the COMPLETED marker
complete() {
  feedback "$1" review APPROVED "${2:-}"
  feedback "$1" audit APPROVED "${2:-}"
  printf 'COMPLETED 2026-06-01T00:00:00Z\nsprint: %s\n' "${2:-sprint-$1}" > "$R/grimoires/loa/a2a/sprint-$1/COMPLETED"
}

# cache STATE [AGE_HOURS] [EXTRA-JQ] — .run/sprint-plan-state.json (jq now: portable, no GNU date -d)
cache() {
  jq -n --arg s "$1" --argjson h "${2:-0}" '
    {schema_version: 2, plan_id: "plan-x", branch: "feature/x", state: $s,
     timestamps: {started: "2026-06-01T00:00:00Z", last_activity: (now - $h * 3600 | floor | todate)},
     sprints: {total: 3, completed: 0, current: "sprint-1",
               list: [{id: "sprint-1", status: "in_progress"}, {id: "sprint-2", status: "pending"}, {id: "sprint-3", status: "pending"}]}}
    '"${3:+| $3}" > "$R/.run/sprint-plan-state.json"
}

derive() { run --separate-stderr bash "$CK" derive --root "$R" "$@"; }
_md5() { if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1; else md5 -q; fi; }
dj() { jq -r "$1" <<<"$output"; }

# --- decision table: run state -------------------------------------------------

@test "RCD-1 drift fixture (D-5.4): cache RUNNING, three COMPLETED markers with APPROVED trailers, ledger completed → COMPLETE; --write makes the cache say so" {
  complete 101; complete 102; complete 103
  cache RUNNING
  derive --json
  [ "$status" -eq 0 ]
  [ "$(dj '.state')" = COMPLETE ]
  [ "$(dj '.cache_state')" = RUNNING ]
  [ "$(dj '.drift')" = true ]
  [ "$(dj '[.sprints[].state] | join(",")')" = "complete,complete,complete" ]
  [ "$(dj '[.sprints[].completed_marker] | all')" = true ]
  [ "$(dj '.written')" = false ]
  [ "$(jq -r .state "$R/.run/sprint-plan-state.json")" = RUNNING ]   # --json alone writes nothing
  derive --json --write
  [ "$(dj '.written')" = true ]
  run jq -r '[.state, .status, (.derived_at | test("^20[0-9]{2}-")), .derivation.source, .schema_version, .plan_id, .sprints.total] | map(tostring) | join(" ")' "$R/.run/sprint-plan-state.json"
  [ "$output" = "COMPLETE COMPLETE true files 2 plan-x 3" ]
  derive --json
  [ "$(dj '.drift')" = false ]
  [ -z "$(find "$R/.run" -name '*.tmp.*')" ]
}

@test "RCD-2 a stale marker whose trailers name sprint-1 of another cycle (or whose sprint: line names another sprint) is stale_marker, not counted" {
  complete 101; complete 102; complete 103 sprint-1
  cache RUNNING
  derive --json
  [ "$(dj '.sprints[2] | [.marker_present, .stale_marker, .completed_marker, .state] | map(tostring) | join(" ")')" = "true true false in_progress" ]
  [ "$(dj '.derivation.stale_markers | join(",")')" = "sprint-103" ]
  [ "$(dj '.state')" = RUNNING ]
  [[ "$(dj '.notes | join(";")')" == *"sprint-103: COMPLETED marker names another sprint"* ]]
  # trailers right, marker line wrong → still stale
  complete 103
  printf 'COMPLETED x\nsprint: sprint-7\n' > "$R/grimoires/loa/a2a/sprint-103/COMPLETED"
  derive --json
  [ "$(dj '.sprints[2].stale_marker')" = true ]
  [ "$(dj '.sprints[2].state')" = awaiting_marker ]
  # the local label is this sprint's name too
  complete 103 sprint-3
  derive --json
  [ "$(dj '.sprints[2].state')" = complete ]
  [ "$(dj '.state')" = COMPLETE ]
}

@test "RCD-3 legacy feedback (no LOA-VERDICT trailer) yields no verdict: the sprint stays incomplete and the file is named in derivation.legacy_feedback" {
  complete 101; complete 102; complete 103
  printf 'All good\n' > "$R/grimoires/loa/a2a/sprint-103/engineer-feedback.md"
  cache RUNNING
  derive --json
  [ "$(dj '.sprints[2].review.verdict')" = null ]
  [ "$(dj '.sprints[2].state')" = in_progress ]
  [ "$(dj '.derivation.legacy_feedback | join(",")')" = "grimoires/loa/a2a/sprint-103/engineer-feedback.md" ]
  [ "$(dj '.state')" = RUNNING ]
  derive --write
  [ "$(jq -r '.derivation.legacy_feedback[0]' "$R/.run/sprint-plan-state.json")" = "grimoires/loa/a2a/sprint-103/engineer-feedback.md" ]
}

@test "RCD-4 review and audit APPROVED without a marker is awaiting_marker (counted incomplete); a marker with the ledger row not completed is in_progress" {
  complete 101; complete 102
  feedback 103 review APPROVED; feedback 103 audit APPROVED
  cache RUNNING
  derive --json
  [ "$(dj '.sprints[2].state')" = awaiting_marker ]
  [ "$(dj '.state')" = RUNNING ]
  printf 'COMPLETED x\n' > "$R/grimoires/loa/a2a/sprint-103/COMPLETED"
  ledger completed completed in_progress
  derive --json
  [ "$(dj '.sprints[2] | [.completed_marker, .state] | map(tostring) | join(" ")')" = "true in_progress" ]
  # an inconsistent APPROVED trailer (verdict-derive exit 1) is not APPROVED
  ledger completed completed completed
  printf 'Looks fine\n\n<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-103","ts":"2026-06-01T00:00:00Z"} -->\n' > "$R/grimoires/loa/a2a/sprint-103/auditor-sprint-feedback.md"
  derive --json
  [ "$(dj '.sprints[2].audit.consistent')" = false ]
  [ "$(dj '.sprints[2].state')" = in_progress ]
}

@test "RCD-5 JACKED_OUT is terminal: a cache .state or .status JACKED_OUT, or .completion.merged_sha, stays JACKED_OUT with contradicting files reported as drift" {
  complete 101
  cache JACKED_OUT 30
  derive --json --write
  [ "$(dj '.state')" = JACKED_OUT ]
  [[ "$(dj '.notes | join(";")')" == *"JACKED_OUT is terminal"* ]]
  [ "$(jq -r .state "$R/.run/sprint-plan-state.json")" = JACKED_OUT ]
  # the cycle-128 defect shape: .state RUNNING, .status JACKED_OUT
  cache RUNNING 0 '.status = "JACKED_OUT"'
  derive --json
  [ "$(dj '.state')" = JACKED_OUT ]
  [ "$(dj '.drift')" = true ]
  [[ "$(dj '.notes | join(";")')" == *"cache .state RUNNING and .status JACKED_OUT disagree"* ]]
  cache RUNNING 0 '.completion = {merged_sha: "abc123"}'
  derive --json
  [ "$(dj '.state')" = JACKED_OUT ]
  cache RUNNING 0 '.completion = {merged_sha: null}'
  derive --json
  [ "$(dj '.state')" = RUNNING ]
}

@test "RCD-6 HALTED is sticky: a cache HALTED stays HALTED even when every sprint is complete; a breaker OPEN halts a RUNNING cache" {
  complete 101; complete 102; complete 103
  cache HALTED
  derive --json --write
  [ "$(dj '.state')" = HALTED ]
  [ "$(jq -r '.state + " " + .status' "$R/.run/sprint-plan-state.json")" = "HALTED HALTED" ]
  rm -rf "$R/grimoires/loa/a2a/sprint-103"
  cache RUNNING
  printf '{"state":"OPEN","triggers":{"same_issue":{"count":0,"threshold":3,"last_hash":null},"no_progress":{"count":0,"threshold":5},"cycle_count":{"current":0,"limit":20},"timeout":{"started":"2026-06-01T00:00:00Z","limit_hours":8}},"history":[]}\n' > "$R/.run/circuit-breaker.json"
  derive --json
  [ "$(dj '.state')" = HALTED ]
  [ "$(dj '.breaker.state')" = OPEN ]
}

@test "RCD-7 COMPLETE never moves back to RUNNING unless the ledger registers a new incomplete sprint" {
  complete 101; complete 102; complete 103
  cache RUNNING
  derive --write
  [ "$(jq -r .state "$R/.run/sprint-plan-state.json")" = COMPLETE ]
  [ "$(jq -c .derivation.sprint_ids "$R/.run/sprint-plan-state.json")" = '["sprint-101","sprint-102","sprint-103"]' ]
  jq '.timestamps.last_activity = (now | floor | todate)' "$R/.run/sprint-plan-state.json" > "$T/c" && mv "$T/c" "$R/.run/sprint-plan-state.json"
  rm "$R/grimoires/loa/a2a/sprint-103/COMPLETED"
  derive --json
  [ "$(dj '.state')" = COMPLETE ]
  [[ "$(dj '.notes | join(";")')" == *"COMPLETE kept"* ]]
  ledger completed completed completed '{"global_id": 104, "local_label": "sprint-4", "status": "planned", "created": "2026-01-02T00:00:00Z"}'
  complete 103
  derive --json
  [ "$(dj '.state')" = RUNNING ]
  [ "$(dj '.sprints[3].state')" = in_progress ]
}

@test "RCD-8 an incomplete sprint is RUNNING while last_activity is within run_mode.stale_hours (default 12), else INTERRUPTED; the key widens the window" {
  complete 101
  cache RUNNING 1
  derive --json
  [ "$(dj '.state')" = RUNNING ]
  cache RUNNING 13
  derive --json
  [ "$(dj '.state')" = INTERRUPTED ]
  [ "$(dj '.stale_hours')" = 12 ]
  command -v yq >/dev/null || skip "yq not installed"
  printf 'run_mode:\n  stale_hours: 24\n' > "$R/.loa.config.yaml"
  derive --json
  [ "$(dj '.state')" = RUNNING ]
  [ "$(dj '.stale_hours')" = 24 ]
  # no cache at all: the derivation is reported, nothing is written
  rm "$R/.run/sprint-plan-state.json"
  derive --json --write
  [ "$(dj '.cache')" = missing ]
  [ "$(dj '.written')" = false ]
  [ ! -e "$R/.run/sprint-plan-state.json" ]
}

# --- breaker recompute (D-4.6 mechanical caller) ------------------------------

@test "RCD-9 breaker recompute: two -r1 feedback files and a zeroed breaker give cycle_count 2, same_issue 2, no_progress 1; counters are raised, never lowered" {
  complete 101
  feedback 102 review CHANGES_REQUIRED sprint-102 1 1 2026-06-01T01:00:00Z
  feedback 102 audit CHANGES_REQUIRED sprint-102 1 1 2026-06-01T02:00:00Z
  feedback 102 review APPROVED
  cache RUNNING
  printf '{"state":"CLOSED","triggers":{"same_issue":{"count":0,"threshold":3,"last_hash":null},"no_progress":{"count":0,"threshold":5},"cycle_count":{"current":0,"limit":20},"timeout":{"started":"2026-06-01T00:00:00Z","limit_hours":8}},"history":[]}\n' > "$R/.run/circuit-breaker.json"
  derive --json
  [ "$(dj '.active_sprint')" = sprint-102 ]
  [ "$(dj '.breaker.recomputed | [.cycle_count, .same_issue, .no_progress] | map(tostring) | join(" ")')" = "2 2 1" ]
  derive --write
  run jq -r '[.state, .triggers.cycle_count.current, .triggers.same_issue.count, .triggers.no_progress.count, (.triggers.same_issue.last_hash | length)] | map(tostring) | join(" ")' "$R/.run/circuit-breaker.json"
  [ "$output" = "CLOSED 2 2 1 32" ]
  # the recorded hash is the run-mode same-issue hash of the last round
  local want
  want=$(bash "$REPO/.claude/scripts/verdict-derive.sh" --file "$R/grimoires/loa/a2a/sprint-102/auditor-sprint-feedback-r1.md" --gate audit --json 2>/dev/null | jq -Sc '{verdict,counts}' | _md5)
  [ "$(jq -r .triggers.same_issue.last_hash "$R/.run/circuit-breaker.json")" = "$want" ]
  # a higher cached count is kept
  jq '.triggers.cycle_count.current = 7' "$R/.run/circuit-breaker.json" > "$T/b" && mv "$T/b" "$R/.run/circuit-breaker.json"
  derive --write
  [ "$(jq -r .triggers.cycle_count.current "$R/.run/circuit-breaker.json")" = 7 ]
  # /run-resume --reset-ice stamps reset_at: rounds before it no longer count
  jq '.triggers.cycle_count.current = 0 | .triggers.same_issue.count = 0 | .triggers.no_progress.count = 0 | .reset_at = "2026-06-01T01:30:00Z"' "$R/.run/circuit-breaker.json" > "$T/b" && mv "$T/b" "$R/.run/circuit-breaker.json"
  derive --write
  [ "$(jq -r '.triggers.cycle_count.current' "$R/.run/circuit-breaker.json")" = 1 ]
}

@test "RCD-10 three identical changes-required rounds meet the same-issue threshold: the derived breaker trips OPEN (history source derive) and the run derives HALTED" {
  feedback 101 review CHANGES_REQUIRED sprint-101 1 2 2026-06-01T01:00:00Z
  feedback 101 review CHANGES_REQUIRED sprint-101 2 2 2026-06-01T02:00:00Z
  feedback 101 review CHANGES_REQUIRED sprint-101 3 2 2026-06-01T03:00:00Z
  cache RUNNING
  derive --json --write
  [ "$(dj '.state')" = HALTED ]
  run jq -r '[.state, .history[-1].trigger, .history[-1].source] | join(" ")' "$R/.run/circuit-breaker.json"
  [ "$output" = "OPEN same_issue derive" ]
  [ "$(jq -r .state "$R/.run/sprint-plan-state.json")" = HALTED ]
}

# --- write path, schema tolerance, rollback, errors ---------------------------

@test "RCD-11 schema tolerance: a file without derived_at, derivation or .status reads fine, gains the fields on --write and keeps its schema_version" {
  complete 101
  printf '{"plan_id":"old","state":"RUNNING","timestamps":{"last_activity":"2026-06-01T00:00:00Z"}}\n' > "$R/.run/sprint-plan-state.json"
  derive --json
  [ "$(dj '.cache_state')" = RUNNING ]
  [ "$(dj '.cache_status')" = null ]
  [ "$(dj '.state')" = INTERRUPTED ]
  derive --write
  run jq -r '[.state, .status, .schema_version, .derivation.source, .plan_id] | map(tostring) | join(" ")' "$R/.run/sprint-plan-state.json"
  [ "$output" = "INTERRUPTED INTERRUPTED 2 files old" ]
  printf '{"schema_version":1,"plan_id":"v1","state":"RUNNING","timestamps":{"last_activity":"2026-06-01T00:00:00Z"}}\n' > "$R/.run/sprint-plan-state.json"
  derive --write
  [ "$(jq -r .schema_version "$R/.run/sprint-plan-state.json")" = 1 ]
  # readers of the old checkpoint keep working on the derived file
  run bash "$CK" read --file "$R/.run/sprint-plan-state.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sprint granularity"* ]]
}

@test "RCD-12 run_mode.file_authoritative: false makes --write report-only: the caches stay byte-identical and the report says why" {
  command -v yq >/dev/null || skip "yq not installed"
  complete 101; complete 102; complete 103
  cache RUNNING
  printf 'run_mode:\n  file_authoritative: false\n' > "$R/.loa.config.yaml"
  cp "$R/.run/sprint-plan-state.json" "$T/before"
  derive --json --write
  [ "$status" -eq 0 ]
  [ "$(dj '.file_authoritative')" = false ]
  [ "$(dj '.written')" = false ]
  [ "$(dj '.state')" = COMPLETE ]
  [[ "$(dj '.notes | join(";")')" == *"file_authoritative: false"* ]]
  cmp "$T/before" "$R/.run/sprint-plan-state.json"
  [ ! -e "$R/.run/circuit-breaker.json" ]
  # and write's own checkpoint still lands, as today
  run bash "$CK" write --file "$R/.run/sprint-plan-state.json" --sprint sprint-3 --phase REVIEW
  [ "$status" -eq 0 ]
  [ "$(jq -r '.checkpoint.phase + " " + .state' "$R/.run/sprint-plan-state.json")" = "REVIEW RUNNING" ]
  [ "$(jq -r '.derived_at // "none"' "$R/.run/sprint-plan-state.json")" = none ]
}

@test "RCD-13 no active cycle or no ledger → exit 4 with a named reason; the cache is untouched" {
  cache RUNNING
  cp "$R/.run/sprint-plan-state.json" "$T/before"
  jq '.active_cycle = null' "$R/grimoires/loa/ledger.json" > "$T/l" && mv "$T/l" "$R/grimoires/loa/ledger.json"
  derive --json --write
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"no active cycle"* ]]
  rm "$R/grimoires/loa/ledger.json"
  derive --write
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"no readable ledger"* ]]
  cmp "$T/before" "$R/.run/sprint-plan-state.json"
}

@test "RCD-14 write refreshes the derived cache after its own update; an unparseable cache is reported and never rewritten" {
  complete 101; complete 102; complete 103
  cache RUNNING
  run bash "$CK" write --file "$R/.run/sprint-plan-state.json" --sprint sprint-3 --phase AUDIT
  [ "$status" -eq 0 ]
  run jq -r '[.checkpoint.phase, .state, .status, (.derived_at != null)] | map(tostring) | join(" ")' "$R/.run/sprint-plan-state.json"
  [ "$output" = "AUDIT COMPLETE COMPLETE true" ]
  printf '{"state": "RUNNING",\n' > "$R/.run/sprint-plan-state.json"
  cp "$R/.run/sprint-plan-state.json" "$T/before"
  derive --json --write
  [ "$status" -eq 0 ]
  [ "$(dj '.cache')" = unparseable ]
  [ "$(dj '.written')" = false ]
  cmp "$T/before" "$R/.run/sprint-plan-state.json"
}

@test "RCD-15 impl_commit is the newest non-merge commit since the sprint started that touches a path outside the state set; state-only commits are skipped" {
  complete 101
  cache RUNNING
  local impl
  impl=$(git -C "$R" rev-parse HEAD)
  printf 'n\n' > "$R/grimoires/loa/NOTES.md"; printf '# c\n' > "$R/CHANGELOG.md"
  git -C "$R" add -A
  git -C "$R" -c user.name=t -c user.email=t@example.invalid commit -qm "docs: state only"
  derive --json
  [ "$(dj '.sprints[0].impl_commit')" = "$impl" ]
  # a sprint started in the future has no implementation commit yet
  jq '(.cycles[1].sprints[1].started) = "2099-01-01T00:00:00Z"' "$R/grimoires/loa/ledger.json" > "$T/l" && mv "$T/l" "$R/grimoires/loa/ledger.json"
  derive --json
  [ "$(dj '.sprints[1].impl_commit')" = null ]
}

@test "RCD-16 the jack-out step in completion-modes.md writes .state (and mirrors .status) on the sprint-plan cache; run-resume derives on drift; the recovery doc reads .state" {
  local cm="$REPO/.claude/skills/run-mode/resources/completion-modes.md" hr="$REPO/.claude/skills/run-mode/resources/halt-resume.md"
  grep -q '^## Jack-out' "$cm"
  sed -n '/^## Jack-out/,/^## /p' "$cm" | grep -qF '.state = "JACKED_OUT" | .status = .state'
  grep -qF 'run-checkpoint.sh derive --json' "$hr"
  grep -qF 'derive --write' "$hr"
  grep -qF '.reset_at = $ts' "$hr"
  grep -q 'Read `.state`' "$hr"
}

@test "RCD-17 a ledger row without local_label or timestamps keeps its fields aligned (empty TSV fields do not collapse)" {
  ledger completed completed completed '{"global_id": 104, "status": "planned"}'
  complete 101; complete 102; complete 103
  cache RUNNING
  derive --json
  [ "$(dj '.sprints[3] | [.global_id, .local_label, .status, .state] | map(tostring) | join(" ")')" = "104  planned in_progress" ]
  [ "$(dj '.state')" = RUNNING ]
}

# --- readers over a derived file (D-5.3) --------------------------------------

@test "RCD-R1 loa-run-state-surface.sh prints for a derived file exactly what it prints for a hand-written file with the same .state" {
  local surf="$REPO/.claude/hooks/session-start/loa-run-state-surface.sh" st age a b
  complete 101
  for st in RUNNING INTERRUPTED HALTED COMPLETE JACKED_OUT; do
    case "$st" in INTERRUPTED) age=14 ;; *) age=1 ;; esac
    cache "$st" "$age"
    case "$st" in HALTED|JACKED_OUT) ;; COMPLETE) complete 102; complete 103 ;; *) rm -rf "$R/grimoires/loa/a2a/sprint-102" "$R/grimoires/loa/a2a/sprint-103" ;; esac
    derive --write
    [ "$(jq -r '.state + " " + .status' "$R/.run/sprint-plan-state.json")" = "$st $st" ] || { echo "$st: derived $(jq -r .state "$R/.run/sprint-plan-state.json")" >&2; return 1; }
    a=$(bash "$surf" --root "$R" --line)
    jq '{state, timestamps}' "$R/.run/sprint-plan-state.json" > "$T/plain.json"
    cp "$R/.run/sprint-plan-state.json" "$T/derived.json"; cp "$T/plain.json" "$R/.run/sprint-plan-state.json"
    b=$(bash "$surf" --root "$R" --line)
    [ "$a" = "$b" ] || { echo "$st: derived '$a' vs plain '$b'" >&2; return 1; }
  done
  # the derived INTERRUPTED and HALTED are surfaced with the resume command
  cache INTERRUPTED 14; rm -rf "$R/grimoires/loa/a2a/sprint-102"; derive --write
  run bash "$surf" --root "$R" --line
  [[ "$output" == "Run: sprint-plan INTERRUPTED ("*"→ /run-resume" ]]
}

@test "RCD-R2 run-preflight.sh P6 classifies a derived file as it classifies the same .state by hand (resumable HALTED/INTERRUPTED, in progress RUNNING)" {
  local pf="$REPO/.claude/scripts/run-preflight.sh" st age a b
  complete 101
  for st in RUNNING INTERRUPTED HALTED; do
    case "$st" in INTERRUPTED) age=14 ;; *) age=1 ;; esac
    cache "$st" "$age"
    derive --write
    [ "$(jq -r .state "$R/.run/sprint-plan-state.json")" = "$st" ]
    a=$(bash "$pf" --unattended --json --root "$R" 2>/dev/null | jq -r '.checks[] | select(.id == "P6") | .status + " " + .detail') || true
    jq '{state, timestamps}' "$R/.run/sprint-plan-state.json" > "$T/plain.json"; cp "$T/plain.json" "$R/.run/sprint-plan-state.json"
    b=$(bash "$pf" --unattended --json --root "$R" 2>/dev/null | jq -r '.checks[] | select(.id == "P6") | .status + " " + .detail') || true
    [ -n "$a" ] && [ "$a" = "$b" ] || { echo "$st: derived '$a' vs plain '$b'" >&2; return 1; }
  done
  # --resume (the run-resume pre-flight) passes on a derived HALTED file
  cache HALTED; derive --write
  run bash -c 'bash "$1" --unattended --resume --json --root "$2" 2>/dev/null | jq -r ".checks[] | select(.id == \"P6\") | .status"' _ "$pf" "$R"
  [ "$output" = PASS ]
}

@test "RCD-R3 golden-path.sh: the bug-state detector reads .run/bugs/*/state.json as before, a derived sprint-plan cache beside it changes nothing" {
  mkdir -p "$R/.run/bugs/b-1"
  printf '{"bug_id":"b-1","state":"IMPLEMENTING"}\n' > "$R/.run/bugs/b-1/state.json"
  local a b
  a=$(bash -c 'export PROJECT_ROOT="$1"; source "$2/.claude/scripts/golden-path.sh"; golden_detect_active_bug' _ "$R" "$REPO")
  complete 101; cache RUNNING; derive --write
  [ -n "$(jq -r .derived_at "$R/.run/sprint-plan-state.json")" ]
  b=$(bash -c 'export PROJECT_ROOT="$1"; source "$2/.claude/scripts/golden-path.sh"; golden_detect_active_bug' _ "$R" "$REPO")
  [ "$a" = "$b" ]
  [[ "$b" == b-1:* ]]
}

@test "RCD-R4 implement-gate.sh over a derived file: derived RUNNING sanctions (one sanctioned_run row); derived COMPLETE under deny is denied; a cache derived 13 h ago is an unknown position" {
  command -v yq >/dev/null || skip "yq not installed"
  local gate="$REPO/.claude/hooks/compliance/implement-gate.sh"
  complete 101
  cache RUNNING
  derive --write
  jq -nc --arg p "$R/src/a.ts" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$T/stdin.json"
  run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" LOA_AUDIT_REPLAY=1 bash "$2" < "$3"' _ "$R" "$gate" "$T/stdin.json"
  [ -z "$output" ]
  [ "$(jq -sr 'map(select(.hook == "implement-gate") | .decision) | join(",")' "$R/.run/audit.jsonl")" = sanctioned_run ]
  printf 'implement_gate:\n  mode: deny\n' > "$R/.loa.config.yaml"
  complete 102; complete 103
  derive --write
  [ "$(jq -r .state "$R/.run/sprint-plan-state.json")" = COMPLETE ]
  run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$R" "$gate" "$T/stdin.json"
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = deny ]
  [[ "$(jq -r .hookSpecificOutput.permissionDecisionReason <<<"$output")" == *"(derived position: COMPLETE)"* ]]
  jq '.derived_at = (now - 13 * 3600 | floor | todate)' "$R/.run/sprint-plan-state.json" > "$T/c" && mv "$T/c" "$R/.run/sprint-plan-state.json"
  run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$R" "$gate" "$T/stdin.json"
  [ "$(jq -r .hookSpecificOutput.permissionDecision <<<"$output")" = ask ]
}

@test "RCD-R5 the /loa Run line reports drift report-only (files say X, cache said Y) and the Gate line prints the effective mode; nothing is written" {
  complete 101; complete 102; complete 103
  cache RUNNING
  cp "$R/.run/sprint-plan-state.json" "$T/before"
  printf 'implement_gate:\n  mode: telemetry\n' > "$T/cfg.yaml"
  run timeout 120 env LOA_STATUS_DERIVE_ROOT="$R" LOA_STATUS_CONFIG_FILE="$T/cfg.yaml" bash "$REPO/.claude/scripts/loa-status.sh" --no-stale-check
  [ "$status" -eq 0 ]
  local plain
  plain=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$output")
  grep -qxF '  Run: files say COMPLETE, cache said RUNNING (drift) → run-checkpoint.sh derive --write' <<<"$plain"
  if command -v yq >/dev/null; then grep -qxF '  Gate: implement_gate.mode telemetry' <<<"$plain"; fi
  cmp "$T/before" "$R/.run/sprint-plan-state.json"
  # after derive --write there is no drift, so no Run drift line
  derive --write
  run timeout 120 env LOA_STATUS_DERIVE_ROOT="$R" LOA_STATUS_CONFIG_FILE="$T/cfg.yaml" bash "$REPO/.claude/scripts/loa-status.sh" --no-stale-check
  [[ "$output" != *"(drift) → run-checkpoint.sh derive --write"* ]]
}
