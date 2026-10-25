#!/usr/bin/env bats
# =============================================================================
# evals/tests/took-effect-transcripts.bats — cycle-134 Sprint 276 Task 1.2 (bd-k3dia; PRD FR-2; SDD C-2, D-1.2,
# D-1.2a). took-effect.sh oracle_closed clause (g), transcript completeness: labels_run = the non-skipped phases of
# meta/pipeline.json, which lists every phase the suite declares for the arm (a stopped run: a prefix) and gives
# every skipped phase a skipped_reason; per label a regular, non-symlink, non-empty transcripts/events-<label>.jsonl
# whose every non-empty line is a JSON object (a line above EVENT_CAP still ends with its newline and is counted as
# skipped_for_size), with exactly one result event as the final non-empty line, a system/init before it, and one
# session_id across the events that carry one. Failures read `transcript <label>: <reason> (line N)`.
# No model call, no docker; the run is built by fixtures/took-effect/te-lib.bash through the real mount library.
# =============================================================================

setup() {
  # shellcheck source=fixtures/took-effect/te-lib.bash
  source "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures/took-effect/te-lib.bash"
  te_setup
}
teardown() { te_teardown; }

PH2='[{"name": "REVIEW", "label": "REVIEW", "skipped": false, "skipped_reason": null}, {"name": "AUDIT", "label": "AUDIT", "skipped": false, "skipped_reason": null}]'
two() {  # two — a REVIEW + AUDIT run (the suite arm declares both)
  te_build "$PH2" || return 1
  yq -i '(.arms[] | select(.id == "a1_te") | .phases) = ["REVIEW", "AUDIT"]' "$S"
}
pass_with() { [ "$status" -eq 0 ] || { echo "$output"; false; }; te_oc | grep -qF "$1" || { echo "want: $1"; echo "$output"; false; }; }
fail_with() { [ "$status" -eq 1 ] || { echo "$output"; false; }; te_oc | grep -qF "$1" || { echo "want: $1"; echo "$output"; false; }; }
tf() { printf '%s' "$RD/transcripts/events-$1.jsonl"; }

@test "TET-1 complete captures for every executed phase pass; the evidence names lines, init, result and skipped_for_size per label" {
  two; te_clean REVIEW AUDIT
  te_run
  pass_with 'transcripts: REVIEW lines=5 init=1 result=last skipped_for_size=0, AUDIT lines=3 init=1 result=last skipped_for_size=0; unlabelled=none'
}

@test "TET-2 an executed phase without its transcript fails naming the phase" {
  two; te_clean REVIEW AUDIT; rm "$(tf AUDIT)"
  te_run
  fail_with 'FAIL (g) -: transcript AUDIT: missing (transcripts/events-AUDIT.jsonl)'
}

@test "TET-3 an empty transcript (no bytes, or blank lines only) fails" {
  two; te_clean REVIEW AUDIT; : > "$(tf AUDIT)"
  te_run
  fail_with 'FAIL (g) -: transcript AUDIT: empty'
  printf '\n  \n' > "$(tf AUDIT)"
  te_run
  fail_with 'FAIL (g) -: transcript AUDIT: empty'
}

@test "TET-4 a transcript with no system/init event fails" {
  te_build; te_hook REVIEW SessionStart:startup SessionStart; te_read REVIEW; te_result REVIEW; te_ps REVIEW
  te_run
  fail_with 'FAIL (g) -: transcript REVIEW: no system/init event'
}

@test "TET-5 a transcript with no result event (a session killed before its end) fails naming its last line" {
  te_build; te_hook REVIEW SessionStart:startup SessionStart; te_init REVIEW; te_read REVIEW; te_ps REVIEW
  te_run
  fail_with 'FAIL (g) -: transcript REVIEW: no result event (last line 4)'
}

@test "TET-6 a malformed interior line fails naming the line: not JSON, invalid UTF-8, or JSON that is not an object" {
  te_build; te_clean
  cp "$(tf REVIEW)" "$T/good.jsonl"
  local bad
  for bad in '{"type": "assistant", "message": {' $'\xff\xfe{}' '[1, 2]' '"text"'; do
    { sed -n 1,2p "$T/good.jsonl"; printf '%s\n' "$bad"; sed -n '3,$p' "$T/good.jsonl"; } > "$(tf REVIEW)"
    te_run
    fail_with 'FAIL (g) -: transcript REVIEW: not a JSON object (line 3)'
  done
}

@test "TET-7 a result event that is not the final non-empty line fails; trailing blank lines are allowed" {
  te_build; te_clean
  printf '\n\n' >> "$(tf REVIEW)"
  te_run
  pass_with 'transcripts: REVIEW lines=5 init=1 result=last'
  te_bash REVIEW b9
  te_run
  fail_with 'FAIL (g) -: transcript REVIEW: the result event is not the final line (line 5)'
}

@test "TET-8 an init after the result fails (the init must precede it)" {
  te_build; te_hook REVIEW SessionStart:startup SessionStart; te_read REVIEW; te_result REVIEW; te_init REVIEW; te_ps REVIEW
  te_run
  fail_with 'FAIL (g) -: transcript REVIEW: the system/init event follows the result (line 5)'
}

@test "TET-9 an event carrying a foreign session_id fails naming the line" {
  te_build; te_hook REVIEW SessionStart:startup SessionStart; te_init REVIEW; te_read REVIEW
  TE_SID=other-session; te_bash REVIEW b1; TE_SID=s; te_result REVIEW; te_ps REVIEW
  te_run
  fail_with 'FAIL (g) -: transcript REVIEW: foreign session_id other-session (line 5; the init has s)'
}

@test "TET-10 a symlinked transcript fails (never followed)" {
  two; te_clean REVIEW AUDIT; mv "$(tf AUDIT)" "$T/elsewhere.jsonl"; ln -s "$T/elsewhere.jsonl" "$(tf AUDIT)"
  te_run
  fail_with 'FAIL (g) -: transcript AUDIT: a symlink (transcripts/events-AUDIT.jsonl)'
  rm "$(tf AUDIT)"; mkdir "$(tf AUDIT)"
  te_run
  fail_with 'FAIL (g) -: transcript AUDIT: not a regular file (transcripts/events-AUDIT.jsonl)'
}

@test "TET-11 a transcript whose label is not in labels_run is reported in the evidence (and still read)" {
  te_build; te_clean REVIEW PLAN; rm "$RD/meta/ps-PLAN.txt"
  te_run
  pass_with 'transcripts: REVIEW lines=5 init=1 result=last skipped_for_size=0; unlabelled=events-PLAN.jsonl'
}

@test "TET-12 a skipped phase needs a skipped_reason; a skipped phase needs no transcript" {
  two; te_clean REVIEW
  jq '.phases[1].skipped = true' "$RD/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$RD/meta/pipeline.json"
  te_run
  fail_with 'FAIL (g) -: phases: incomplete record (AUDIT skipped without a skipped_reason)'
  jq '.phases[1].skipped_reason = "the review approved"' "$RD/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$RD/meta/pipeline.json"
  te_run
  pass_with 'transcripts: REVIEW lines=5 init=1 result=last skipped_for_size=0; unlabelled=none'
}

@test "TET-13 the record lists every phase the suite declares for the arm; a stopped run may hold a prefix" {
  te_build; te_clean
  yq -i '(.arms[] | select(.id == "a1_te") | .phases) = ["REVIEW", "AUDIT"]' "$S"
  te_run
  fail_with 'FAIL (g) -: phases: incomplete record (missing AUDIT; status completed)'
  jq '.status = "agent_error"' "$RD/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$RD/meta/pipeline.json"
  te_run
  pass_with 'transcripts: REVIEW lines=5 init=1 result=last'
  # a stopped run's records are a prefix, never a gap
  jq '.phases[0].label = "AUDIT" | .phases[0].name = "AUDIT"' "$RD/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$RD/meta/pipeline.json"
  te_run
  fail_with 'FAIL (g) -: phases: incomplete record (missing REVIEW; status agent_error)'
}

@test "TET-14 a line above EVENT_CAP (8 MiB) is counted as skipped_for_size when it ends with its newline; without it the transcript fails" {
  te_build; te_clean
  cp "$(tf REVIEW)" "$T/good.jsonl"
  python3 -I -c 'import json, sys; sys.stdout.write(json.dumps({"type": "user", "session_id": "s", "message": {"content": "x" * (9 << 20)}}) + "\n")' > "$T/big.jsonl"
  { sed -n 1,2p "$T/good.jsonl"; cat "$T/big.jsonl"; sed -n '3,$p' "$T/good.jsonl"; } > "$(tf REVIEW)"
  te_run
  pass_with 'transcripts: REVIEW lines=6 init=1 result=last skipped_for_size=1'
  { cat "$T/good.jsonl"; head -c -1 "$T/big.jsonl"; } > "$(tf REVIEW)"
  te_run
  fail_with 'FAIL (g) -: transcript REVIEW: an oversize line without its newline (line 6)'
}

@test "TET-15 exactly one result event: a second one fails naming both lines" {
  te_build; te_clean; te_result REVIEW
  te_run
  fail_with 'FAIL (g) -: transcript REVIEW: 2 result events (lines 5, 6)'
}
