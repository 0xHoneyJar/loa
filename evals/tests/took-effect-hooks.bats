#!/usr/bin/env bats
# =============================================================================
# evals/tests/took-effect-hooks.bats — cycle-134 Sprint 276 Task 1.1 (bd-bex39; PRD FR-1; SDD C-1, D-1.1, D-1.1a,
# § 3.2, § 11.H). took-effect.sh oracle_closed clause (g), the hook rule: a hook_started event names
# <event>[:<query>]; it belongs to the pinned groups of that event whose matcher hex id (home_hook_groups) is the
# query's or the empty matcher's (n summed), or to the event-level aggregate when only home_hook_counts was
# recorded; per transcript and name the count c = k·n with an integer k >= 0 and k <= the trigger count where
# the transcript yields it. The PreToolUse / UserPromptSubmit events are SYNTHETIC
# (fixtures/took-effect/hook-events-synthetic.jsonl); the SessionStart:startup events are real (Q-1).
# No model call, no docker; the run is built by fixtures/took-effect/te-lib.bash through the real mount library.
# =============================================================================

setup() {
  # shellcheck source=fixtures/took-effect/te-lib.bash
  source "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/fixtures/took-effect/te-lib.bash"
  te_setup
  te_build || { echo "te_build failed"; return 1; }
}
teardown() { te_teardown; }

hex() { printf %s "$1" | sha256sum | cut -c1-12; }
set_ev() {  # set_ev <key> <value> — replace (or add) one evidence line
  sed -i "/^$1=/d" "$ARM_EVIDENCE_FILE"
  printf '%s=%s\n' "$1" "$2" >> "$ARM_EVIDENCE_FILE"
}
syn() { grep -F "\"hook_id\":\"$1\"" "$TFX/hook-events-synthetic.jsonl"; }   # syn <hook_id> — one synthetic event line
bashes() { local i; for i in $(seq 1 "$2"); do te_bash "$1" "b$i"; done; }
# begin / end — a REVIEW transcript around the case's events: the startup hook and init first, the read, then the result
begin() { te_hook REVIEW SessionStart:startup SessionStart; te_init REVIEW; te_read REVIEW; te_ps REVIEW; }
end() { te_result REVIEW; }
pass_with() { [ "$status" -eq 0 ] || { echo "$output"; false; }; te_oc | grep -qF "$1" || { echo "want: $1"; echo "$output"; false; }; }
fail_with() { [ "$status" -eq 1 ] || { echo "$output"; false; }; te_oc | grep -qF "$1" || { echo "want: $1"; echo "$output"; false; }; }
groups_bash() {  # one PreToolUse:Bash group of $1 command(s) and the startup group of one
  set_ev home_hook_counts "PreToolUse:$1,SessionStart:1"
  set_ev home_hook_groups "PreToolUse:$(hex Bash):$1;SessionStart:$(hex ''):1"
}

@test "TEH-0 the shared sample: SHA-256(\"Bash\")[:12] and SHA-256(\"\")[:12] are the sample's ids" {
  [ "$(hex Bash)" = d1e9567da9a8 ]
  [ "$(hex '')" = e3b0c44298fc ]
  [ "$(sed -n 2p "$TESTS_DIR/fixtures/home_hook_groups.sample")" = \
    "home_hook_groups=PreToolUse:$(hex Bash):2;PreToolUse:$(hex ''):1;SessionStart:$(hex ''):8;UserPromptSubmit:$(hex ''):2" ]
}

@test "TEH-1 one configured PreToolUse:Bash hook, two Bash uses, two hook_started: passes with k = 2 <= 2 triggers" {
  groups_bash 1; begin; bashes REVIEW 2; te_hook REVIEW PreToolUse:Bash PreToolUse 2; end
  te_run
  pass_with 'hooks: REVIEW PreToolUse:Bash c=2 n=1 k=2 triggers=2, REVIEW SessionStart:startup c=1 n=1 k=1 triggers=1'
}

@test "TEH-2 no hook event beside many Bash uses passes (k = 0 is legal)" {
  groups_bash 1; begin; bashes REVIEW 6; end
  te_run
  pass_with 'hooks: REVIEW SessionStart:startup c=1 n=1 k=1 triggers=1;'
}

@test "TEH-3 a hook_started whose group is not pinned fails naming the event, the query and the transcript" {
  groups_bash 1; begin; te_tool REVIEW w1 Write '{"file_path": "x"}' ok; te_ev REVIEW "$(syn synthetic-pretooluse-write)"; end
  te_run
  fail_with 'FAIL (g) -: hook PreToolUse:Write in events-REVIEW.jsonl names no pinned group (event PreToolUse, matcher query Write; home_hook_groups)'
}

@test "TEH-4 a count that is not a whole multiple of the group's command count fails naming the group and the counts" {
  groups_bash 2; begin; bashes REVIEW 2; te_hook REVIEW PreToolUse:Bash PreToolUse 3; end
  te_run
  fail_with 'FAIL (g) -: 3 PreToolUse:Bash hook(s) ran in events-REVIEW.jsonl; the pinned user settings declare 2 (home_hook_groups): not a whole multiple'
}

@test "TEH-5 a multiple above the transcript's trigger count fails naming k and the triggers" {
  groups_bash 1; begin; bashes REVIEW 2; te_hook REVIEW PreToolUse:Bash PreToolUse 3; end
  te_run
  fail_with 'FAIL (g) -: 3 PreToolUse:Bash hook(s) ran in events-REVIEW.jsonl; the pinned user settings declare 1 (home_hook_groups): k=3 above 2 trigger(s)'
}

@test "TEH-6 two pinned groups with the same key merge (n summed); the query's group and the matcher-less group add up" {
  set_ev home_hook_counts "PreToolUse:2,SessionStart:1"
  set_ev home_hook_groups "PreToolUse:$(hex Bash):1;PreToolUse:$(hex Bash):1;SessionStart:$(hex ''):1"
  begin; te_bash REVIEW b1; te_hook REVIEW PreToolUse:Bash PreToolUse 2; end
  te_run
  pass_with 'REVIEW PreToolUse:Bash c=2 n=2 k=1 triggers=1'
  # a matcher-less PreToolUse group runs for every tool: Bash's events are k·(2 + 1)
  set_ev home_hook_counts "PreToolUse:3,SessionStart:1"
  set_ev home_hook_groups "PreToolUse:$(hex Bash):2;PreToolUse:$(hex ''):1;SessionStart:$(hex ''):1"
  te_run
  fail_with 'FAIL (g) -: 2 PreToolUse:Bash hook(s) ran in events-REVIEW.jsonl; the pinned user settings declare 3 (home_hook_groups): not a whole multiple'
  te_hook REVIEW PreToolUse:Bash PreToolUse 1
  sed -i '/"type":"result"/d' "$RD/transcripts/events-REVIEW.jsonl"; end
  te_run
  pass_with 'REVIEW PreToolUse:Bash c=3 n=3 k=1 triggers=1'
}

@test "TEH-7 a matcher with colons and pipes round-trips through its hex id (the query is everything after the first colon)" {
  local q='mcp__srv__run:a|b'
  set_ev home_hook_counts "PreToolUse:1,SessionStart:1"
  set_ev home_hook_groups "PreToolUse:$(hex "$q"):1;SessionStart:$(hex ''):1"
  begin; te_tool REVIEW m1 "$q" '{}' ok; te_ev REVIEW "$(syn synthetic-pretooluse-colon-pipe)"; end
  te_run
  pass_with "REVIEW PreToolUse:$q c=1 n=1 k=1 triggers=1"
  # the hex of the part after the LAST colon is not the group
  set_ev home_hook_groups "PreToolUse:$(hex 'a|b'):1;SessionStart:$(hex ''):1"
  te_run
  fail_with "hook PreToolUse:$q in events-REVIEW.jsonl names no pinned group"
}

@test "TEH-8 a recorded run with only home_hook_counts (several matchers under one event) is checked as the event-level aggregate" {
  set_ev home_hook_counts "PreToolUse:3,SessionStart:1"
  begin; te_bash REVIEW b1; te_tool REVIEW w1 Write '{"file_path": "x"}' ok
  te_hook REVIEW PreToolUse:Bash PreToolUse 3; te_hook REVIEW PreToolUse:Write PreToolUse 3; end
  te_run
  pass_with 'hooks: REVIEW PreToolUse c=6 n=3 k=2 triggers=3, REVIEW SessionStart c=1 n=1 k=1 triggers=1'
  # an event the counts do not declare is no pinned group
  set_ev home_hook_counts "SessionStart:1"
  te_run
  fail_with 'hook PreToolUse:Bash in events-REVIEW.jsonl names no pinned group (event PreToolUse, matcher query Bash; home_hook_counts)'
}

@test "TEH-9 the real SessionStart:startup events (Q-1, 8 per init) pass with k = 1 under home_hook_groups and under home_hook_counts" {
  TE_SID=c0afb74a-4812-462d-af61-7662c36d49bd
  cat "$TFX/hook-events-real-sessionstart-startup.jsonl" >> "$RD/transcripts/events-REVIEW.jsonl"
  te_init REVIEW '.claude_code_version = "2.1.310"'; te_read REVIEW; te_ps REVIEW; te_bash REVIEW b1; te_result REVIEW
  set_ev home_hook_counts "SessionStart:8"
  set_ev home_hook_groups "SessionStart:$(hex ''):8"
  te_run
  pass_with 'hooks: REVIEW SessionStart:startup c=8 n=8 k=1 triggers=1; cc=2.1.310'
  sed -i '/^home_hook_groups=/d' "$ARM_EVIDENCE_FILE"
  te_run
  pass_with 'hooks: REVIEW SessionStart c=8 n=8 k=1 triggers=1; cc=2.1.310'
}

@test "TEH-10 a hook_event that is not the event part of the hook_name fails" {
  groups_bash 1; begin; te_bash REVIEW b1; te_ev REVIEW "$(syn synthetic-event-mismatch)"; end
  te_run
  fail_with 'FAIL (g) -: hook PreToolUse:Bash in events-REVIEW.jsonl: hook_event PostToolUse is not the event of its name'
}

@test "TEH-11 the shared sample (home_hook_groups.sample): startup x8, a prompt with its 2 UserPromptSubmit hooks, a Bash use with the Bash group and the matcher-less PreToolUse group (2 + 1)" {
  sed -i '/^home_hook_counts=/d' "$ARM_EVIDENCE_FILE"
  cat "$TESTS_DIR/fixtures/home_hook_groups.sample" >> "$ARM_EVIDENCE_FILE"
  te_hook REVIEW SessionStart:startup SessionStart 8; te_init REVIEW; te_read REVIEW; te_ps REVIEW
  te_user REVIEW 'Run /review-sprint sprint-1'
  te_ev REVIEW "$(syn synthetic-userpromptsubmit)"; te_ev REVIEW "$(syn synthetic-userpromptsubmit)"
  te_bash REVIEW b1; te_hook REVIEW PreToolUse:Bash PreToolUse 3; end
  te_run
  pass_with 'hooks: REVIEW PreToolUse:Bash c=3 n=3 k=1 triggers=1, REVIEW SessionStart:startup c=8 n=8 k=1 triggers=1, REVIEW UserPromptSubmit c=2 n=2 k=1 triggers=1'
}

@test "TEH-12 the evidence lines: absence of both fails with the existing message; a malformed group entry and groups that disagree with the counts fail" {
  groups_bash 1; begin; end
  sed -i '/^home_hook_counts=/d; /^home_hook_groups=/d' "$ARM_EVIDENCE_FILE"
  te_run
  fail_with "FAIL (g) -: no home_hook_counts evidence (the mount declares the pinned user settings' hooks)"
  set_ev home_hook_counts "SessionStart:1"
  set_ev home_hook_groups "SessionStart:startup:1"
  te_run
  fail_with 'FAIL (g) -: home_hook_groups entry SessionStart:startup:1 is not <event>:<hex12>:<n>'
  set_ev home_hook_groups "SessionStart:$(hex ''):2"
  te_run
  fail_with 'FAIL (g) -: home_hook_groups declares SessionStart:2 but home_hook_counts SessionStart:1'
}

@test "TEH-13 SessionStart above its init count fails (the cycle-133 count rule's one true positive, now k above the triggers)" {
  begin; te_hook REVIEW SessionStart:startup SessionStart; end
  te_run
  fail_with 'FAIL (g) -: 2 SessionStart hook(s) ran in events-REVIEW.jsonl; the pinned user settings declare 1 (home_hook_counts): k=2 above 1 trigger(s)'
}
