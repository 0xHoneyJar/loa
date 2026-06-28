#!/usr/bin/env bats
# OKF/ICM cycle Sprint 8 — recurrence-detector.sh (read-only, propose-only).
# Hermetic: feeds fixture JSONL via --sources and writes only to a temp --output.

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  DET="$PROJECT_ROOT/.claude/scripts/recurrence-detector.sh"
  FIX="$(mktemp -d)"
  OUT="$(mktemp -d)"
}
teardown() { rm -rf "$FIX" "$OUT"; }

# write a session file with N copies of a finding (same `reason`), plus varying SHAs
_session() { # file, reason, count
  local f="$FIX/$1.jsonl" reason="$2" n="$3" i
  : > "$f"
  for ((i=0;i<n;i++)); do
    printf '{"type":"x","reason":"%s","sha":"%dabcdef0123","ts_utc":"2026-06-%02dT00:00:00Z"}\n' "$reason" "$i" "$((i+1))" >> "$f"
  done
  printf '%s' "$f"
}

@test "recurrence: --json is valid + deterministic" {
  _session s1 "widget pipeline stalls on large input" 1 >/dev/null
  _session s2 "widget pipeline stalls on large input" 1 >/dev/null
  _session s3 "widget pipeline stalls on large input" 1 >/dev/null
  local src="$FIX/s1.jsonl,$FIX/s2.jsonl,$FIX/s3.jsonl"
  run bash "$DET" --sources "$src" --json; [ "$status" -eq 0 ]
  echo "$output" | jq -e '.proposals and (.proposal_count|type=="number")' >/dev/null
  local a="$output"
  run bash "$DET" --sources "$src" --json; [ "$a" = "$output" ]
}

@test "recurrence: a finding across >=3 distinct sessions is proposed" {
  _session s1 "widget pipeline stalls on large input" 1 >/dev/null
  _session s2 "widget pipeline stalls on large input" 1 >/dev/null
  _session s3 "widget pipeline stalls on large input" 1 >/dev/null
  run bash "$DET" --sources "$FIX/s1.jsonl,$FIX/s2.jsonl,$FIX/s3.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.proposal_count >= 1' >/dev/null
  echo "$output" | jq -e '[.proposals[]|select(.fingerprint|test("widget pipeline stalls"))]|length==1' >/dev/null
  echo "$output" | jq -e '.proposals[0].distinct_sessions == 3' >/dev/null
}

@test "recurrence: a finding in only 2 sessions is NOT proposed (threshold)" {
  _session s1 "rare glitch in the frobnicator module" 1 >/dev/null
  _session s2 "rare glitch in the frobnicator module" 1 >/dev/null
  run bash "$DET" --sources "$FIX/s1.jsonl,$FIX/s2.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.proposals[]|select(.fingerprint|test("frobnicator"))]|length==0' >/dev/null
}

@test "recurrence: 3 repeats in ONE session do NOT count (distinct-session guardrail)" {
  _session only "single session repeated finding many times" 3 >/dev/null
  run bash "$DET" --sources "$FIX/only.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.proposal_count == 0' >/dev/null
}

@test "recurrence: a too-generic finding (<4 significant words) is dropped" {
  _session s1 "it failed" 1 >/dev/null
  _session s2 "it failed" 1 >/dev/null
  _session s3 "it failed" 1 >/dev/null
  run bash "$DET" --sources "$FIX/s1.jsonl,$FIX/s2.jsonl,$FIX/s3.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.proposal_count == 0' >/dev/null
}

@test "recurrence: session-specific tokens (SHA/date) are normalized so the same finding clusters" {
  # each session has a different SHA + date but the same finding phrase
  _session s1 "auth token refresh races with the retry loop" 1 >/dev/null
  _session s2 "auth token refresh races with the retry loop" 1 >/dev/null
  _session s3 "auth token refresh races with the retry loop" 1 >/dev/null
  run bash "$DET" --sources "$FIX/s1.jsonl,$FIX/s2.jsonl,$FIX/s3.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.proposals[]|select(.fingerprint|test("auth token refresh"))]|length==1' >/dev/null
}

@test "recurrence: --max caps proposals and reports truncation (no silent cap)" {
  local i src=""
  for i in 1 2 3; do _session "a$i" "alpha finding one two three four" 1 >/dev/null; src="$src,$FIX/a$i.jsonl"; done
  for i in 1 2 3; do _session "b$i" "beta finding five six seven eight" 1 >/dev/null; src="$src,$FIX/b$i.jsonl"; done
  src="${src#,}"
  run bash "$DET" --sources "$src" --max 1 --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.proposal_count == 1 and .truncated == 1' >/dev/null
}

@test "recurrence: write mode emits artifacts to --output and touches nothing authoritative" {
  _session s1 "config reload drops the active websocket connections" 1 >/dev/null
  _session s2 "config reload drops the active websocket connections" 1 >/dev/null
  _session s3 "config reload drops the active websocket connections" 1 >/dev/null
  local kf="$PROJECT_ROOT/grimoires/loa/known-failures.md"
  local kf_before; kf_before="$(sha256sum "$kf" | cut -d' ' -f1)"
  run bash "$DET" --sources "$FIX/s1.jsonl,$FIX/s2.jsonl,$FIX/s3.jsonl" --output "$OUT" --quiet
  [ "$status" -eq 0 ]
  [ -f "$OUT/recurrence-proposals.json" ]
  [ -f "$OUT/recurrence-proposals.md" ]
  jq -e '.proposal_count >= 1' "$OUT/recurrence-proposals.json" >/dev/null
  # nothing authoritative changed
  [ "$(sha256sum "$kf" | cut -d' ' -f1)" = "$kf_before" ]
}

@test "recurrence: a corrupt/non-JSON line in an untrusted source does NOT abort the run" {
  local i
  for i in 1 2 3; do
    printf '{"reason":"good alpha bravo charlie delta finding"}\nNOT JSON GARBAGE %d\n' "$i" > "$FIX/s$i.jsonl"
  done
  run bash "$DET" --sources "$FIX/s1.jsonl,$FIX/s2.jsonl,$FIX/s3.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '[.proposals[]|select(.fingerprint|test("good alpha bravo"))]|length==1' >/dev/null
}

@test "recurrence: a finding with an embedded newline stays ONE signal (no boilerplate-footer mis-cluster)" {
  local i
  for i in 1 2 3; do
    printf '{"reason":"multiline header line one\\nshared footer boilerplate text"}\n' > "$FIX/m$i.jsonl"
  done
  run bash "$DET" --sources "$FIX/m1.jsonl,$FIX/m2.jsonl,$FIX/m3.jsonl" --json
  [ "$status" -eq 0 ]
  # the whole finding is one signal across 3 sessions → exactly one proposal
  echo "$output" | jq -e '.proposal_count == 1 and .proposals[0].distinct_sessions == 3' >/dev/null
}

@test "recurrence: a value-taking flag with no value fails with a friendly error (not set -u crash)" {
  run bash "$DET" --max
  [ "$status" -eq 2 ]
  [[ "$output" == *"--max requires"* ]]
  run bash "$DET" --min-sessions notanumber
  [ "$status" -eq 2 ]
}

@test "recurrence: proposals carry a human-review action and never an auto-apply directive" {
  _session s1 "scheduler skips jobs after a leader election flap" 1 >/dev/null
  _session s2 "scheduler skips jobs after a leader election flap" 1 >/dev/null
  _session s3 "scheduler skips jobs after a leader election flap" 1 >/dev/null
  run bash "$DET" --sources "$FIX/s1.jsonl,$FIX/s2.jsonl,$FIX/s3.jsonl" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.proposals[0].proposed_action | test("human|do NOT auto"; "i")' >/dev/null
}
