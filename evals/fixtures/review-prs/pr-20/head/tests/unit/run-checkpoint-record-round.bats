#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/run-checkpoint-record-round.bats — cycle-129 Sprint 2 Task 2.5
# (PRD FR-4(f) AC-4.6; SDD D-4.6). `run-checkpoint.sh record-round` replaces the
# run-mode SKILL's breaker prose: the same-issue hash from the derived verdict,
# no-progress, cycle count, timeout; a trip writes OPEN + HALTED and exits 10.
# All files live in a temp dir.
# =============================================================================

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  CK="$REPO/.claude/scripts/run-checkpoint.sh"
  VD="$REPO/.claude/scripts/verdict-derive.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/rcr.XXXXXX")"
  mkdir -p "$T/.run" "$T/a2a"
  B="$T/.run/circuit-breaker.json"
  S="$T/.run/state.json"
  printf '{"run_id":"r","state":"RUNNING","phase":"REVIEW"}\n' > "$S"
}
teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

# fb NAME GATE VERDICT [MEDIUM] — a feedback file verdict-derive accepts
fb() {
  local prose
  if [[ "$3" == APPROVED ]]; then
    if [[ "$2" == review ]]; then prose='All good'; else prose="APPROVED - LET'S FUCKING GO"; fi
  else
    prose=$'# Feedback\n\n## Findings\n\n- MEDIUM: fix it'
  fi
  printf '%s\n\n<!-- LOA-VERDICT {"gate":"%s","verdict":"%s","counts":{"critical":0,"high":0,"medium":%s,"low":0},"sprint_id":"sprint-1","ts":"2026-06-01T00:00:00Z"} -->\n' \
    "$prose" "$2" "$3" "${4:-0}" > "$T/a2a/$1"
}

_md5() { if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1; else md5 -q; fi; }

breaker() {  # $1 jq tweak over a CLOSED breaker started now
  jq -n '{state: "CLOSED",
          triggers: {same_issue: {count: 0, threshold: 3, last_hash: null}, no_progress: {count: 0, threshold: 5},
                     cycle_count: {current: 0, limit: 20}, timeout: {started: (now | floor | todate), limit_hours: 8}},
          history: []}'"${1:+ | $1}" > "$B"
}

rr() { run --separate-stderr bash "$CK" record-round --root "$T" --breaker "$B" --state-file "$S" --sprint sprint-1 "$@"; }

@test "RCR-1 a CHANGES_REQUIRED review increments cycle_count.current, sets same_issue {count 1, last_hash} to the SKILL's derived hash, exit 0" {
  breaker
  fb engineer-feedback.md review CHANGES_REQUIRED 1
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$status" -eq 0 ]
  [[ "$output" == "recorded: review CHANGES_REQUIRED — cycle 1/20, same_issue 1/3, no_progress 0/5" ]]
  local want
  want=$(bash "$VD" --file "$T/a2a/engineer-feedback.md" --gate review --json 2>/dev/null | jq -Sc '{verdict,counts}' | _md5)
  run jq -r '[.state, .triggers.cycle_count.current, .triggers.same_issue.count, .triggers.same_issue.last_hash, (.history | length)] | map(tostring) | join(" ")' "$B"
  [ "$output" = "CLOSED 1 1 $want 0" ]
  [ "$(jq -r .state "$S")" = RUNNING ]
}

@test "RCR-2 the same hash again counts up; a different finding set resets same_issue to 1 with the new last_hash" {
  breaker
  fb engineer-feedback.md review CHANGES_REQUIRED 1
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$(jq -r .triggers.same_issue.count "$B")" = 2 ]
  local h1; h1=$(jq -r .triggers.same_issue.last_hash "$B")
  fb engineer-feedback.md review CHANGES_REQUIRED 2
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$status" -eq 0 ]
  [ "$(jq -r .triggers.same_issue.count "$B")" = 1 ]
  [ "$(jq -r .triggers.same_issue.last_hash "$B")" != "$h1" ]
  [ "$(jq -r .triggers.cycle_count.current "$B")" = 3 ]
}

@test "RCR-3 no_progress counts consecutive rounds whose counts are unchanged and resets when they change" {
  breaker '.triggers.same_issue.threshold = 99'
  fb engineer-feedback.md review CHANGES_REQUIRED 1
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$(jq -r .triggers.no_progress.count "$B")" = 0 ]
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$(jq -r .triggers.no_progress.count "$B")" = 2 ]
  fb engineer-feedback.md review CHANGES_REQUIRED 3
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$(jq -r .triggers.no_progress.count "$B")" = 0 ]
}

@test "RCR-4 a trip at threshold writes state OPEN, appends one history entry, sets .run/state.json HALTED, prints TRIPPED and exits 10" {
  breaker
  fb auditor-sprint-feedback.md audit CHANGES_REQUIRED 1
  rr --gate audit --file "$T/a2a/auditor-sprint-feedback.md"
  rr --gate audit --file "$T/a2a/auditor-sprint-feedback.md"
  [ "$status" -eq 0 ]
  rr --gate audit --file "$T/a2a/auditor-sprint-feedback.md"
  [ "$status" -eq 10 ]
  [[ "$output" == *$'\n'"TRIPPED: same_issue: same issue hash "*" seen 3 times in a row" ]]
  run jq -r '[.state, (.history | length), .history[0].trigger, .history[0].gate, .history[0].sprint] | map(tostring) | join(" ")' "$B"
  [ "$output" = "OPEN 1 same_issue audit sprint-1" ]
  [ "$(jq -r '.state + " " + .run_id' "$S")" = "HALTED r" ]
  # a further round on an OPEN breaker still exits 10 and does not duplicate the history entry
  rr --gate audit --file "$T/a2a/auditor-sprint-feedback.md"
  [ "$status" -eq 10 ]
  [ "$(jq -r '.history | length' "$B")" = 1 ]
}

@test "RCR-5 the cycle limit, the no-progress threshold and the timeout trip in that documented order" {
  fb engineer-feedback.md review CHANGES_REQUIRED 1
  breaker '.triggers.same_issue.threshold = 99 | .triggers.cycle_count.current = 19'
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$status" -eq 10 ]
  [[ "$output" == *"TRIPPED: cycle_count: 20 changes-required rounds reached the limit 20" ]]
  breaker '.triggers.same_issue.threshold = 99 | .triggers.no_progress.count = 4 | .triggers.no_progress.last_counts = "{\"critical\":0,\"high\":0,\"medium\":1,\"low\":0}"'
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$status" -eq 10 ]
  [[ "$output" == *"TRIPPED: no_progress: "* ]]
  breaker '.triggers.same_issue.threshold = 99 | .triggers.timeout.started = (now - 9 * 3600 | floor | todate)'
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$status" -eq 10 ]
  [[ "$output" == *"TRIPPED: timeout: run older than 8 hours" ]]
  [ "$(jq -r .history[-1].trigger "$B")" = timeout ]
}

@test "RCR-6 APPROVED leaves every counter and the run state as they were (exit 0)" {
  breaker '.triggers.same_issue.count = 2 | .triggers.same_issue.last_hash = "abc" | .triggers.cycle_count.current = 4 | .triggers.no_progress.count = 1'
  cp "$B" "$T/before"
  fb engineer-feedback.md review APPROVED
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$status" -eq 0 ]
  [[ "$output" == "recorded: review APPROVED — breaker counters unchanged" ]]
  cmp "$T/before" "$B"
  [ "$(jq -r .state "$S")" = RUNNING ]
}

@test "RCR-7 an inconsistent APPROVED trailer counts as findings; a legacy file without a trailer hashes its findings section; a missing breaker file is created from the schema defaults" {
  printf 'Looks fine\n\n<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-06-01T00:00:00Z"} -->\n' > "$T/a2a/auditor-sprint-feedback.md"
  rr --gate audit --file "$T/a2a/auditor-sprint-feedback.md"
  [ "$status" -eq 0 ]
  run jq -r '[.state, .triggers.cycle_count.current, .triggers.cycle_count.limit, .triggers.same_issue.threshold, .triggers.no_progress.threshold, .triggers.timeout.limit_hours] | map(tostring) | join(" ")' "$B"
  [ "$output" = "CLOSED 1 20 3 5 8" ]
  printf '# Review\n\n## Findings\n\n- a legacy finding\n' > "$T/a2a/engineer-feedback.md"
  rr --gate review --file "$T/a2a/engineer-feedback.md"
  [ "$status" -eq 0 ]
  local want
  want=$(grep -A 100 "## Findings\|## Issues\|## Changes Required" "$T/a2a/engineer-feedback.md" | head -50 | _md5)
  [ "$(jq -r .triggers.same_issue.last_hash "$B")" = "$want" ]
  [ "$(jq -r .triggers.cycle_count.current "$B")" = 2 ]
}

@test "RCR-8 usage: a missing feedback file or gate exits 2 and writes nothing" {
  rr --gate review --file "$T/a2a/nope.md"
  [ "$status" -eq 2 ]
  rr --file "$T/a2a/nope.md"
  [ "$status" -eq 2 ]
  [ ! -e "$B" ]
}
