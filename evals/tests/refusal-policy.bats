#!/usr/bin/env bats
# =============================================================================
# evals/tests/refusal-policy.bats — cycle-133 Sprint 273 Task 2.3 (SDD C-8; PRD FR-8; bd-r9abp, KF-051)
#
# The refusal policy: the suite key refusal_policy (exclude | keep | rerun-once, default exclude) per arm, recorded in
# MANIFEST.json before execution; ablation-row.sh 1.6's row fields (refusal_policy_applied, attempt, refusal_attempts,
# refusal_outcome, refusal_denominator, refusal_flagged), its --validate rules and its --refusal-rate mode; and
# run-ablation.sh's rerun-once relaunch (an immutable first-attempt record, both attempts charged, the final-row rule,
# a second refusal, an infrastructure failure on the retry, a resume after the first attempt). Stubs only: the pipeline
# is fixtures/ablation-pipeline-stub.sh behind a per-attempt rules wrapper, the grader fixtures/ablation-grade-stub.sh,
# docker fixtures/ablation-docker-stub.sh. No model call, no docker.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  RA="$REPO_ROOT/evals/harness/run-ablation.sh" ROWB="$REPO_ROOT/evals/harness/ablation-row.sh"
  FX="$TESTS_DIR/fixtures"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/rp.XXXXXX")"
  mkdir -p "$T/bin" "$T/src/.claude"
  cp "$FX/ablation-docker-stub.sh" "$T/bin/docker"
  cp "$FX/docker-stub.sh" "$T/bin/docker-stub.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "2.1.300 (Claude Code)"' > "$T/bin/claude"
  chmod +x "$T/bin/docker" "$T/bin/docker-stub.sh" "$T/bin/claude"
  printf '# loa\n' > "$T/src/.claude/CLAUDE.loa.md"
  ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m src )
  SHA="$(git -C "$T/src" rev-parse HEAD)"
  for i in $(seq 1 36); do echo "self-check base task-$i: PASS hidden 1/1"; done > "$T/self-check.log"
  export PATH="$T/bin:$PATH" EVAL_CLAUDE_BIN="$T/bin/claude" LOA_ABLATION_SOURCE_TREE="$T/src"
  export LOA_ABLATION_RETRY_WAIT_S=0 LOA_ABLATION_POLL_S=0.2 STUB_LOG="$T/stub.log" STUB_GRADE_LOG="$T/grade.log"
  unset STUB_ENV_LOG LOA_ABLATION_BATCH_CONTEXT STUB_ARGV_LOG STUB_RULES STUB_HANG STUB_CLI STUB_COST STUB_GRADE_FAIL STUB_GRADE_HANG LOA_ABLATION_GRADE_TIMEOUT_S LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S LOA_ABLATION_WATCHDOG_S LOA_ABLATION_WATCHDOG_GRACE_S DOCKER_STUB_NO_IMAGE LOA_ABLATION_OUTAGE_BREAKER
  RES="$T/res"
  mkdir -p "$T/creds/.codex"; export LOA_EVAL_CREDS_HOME="$T/creds"
  # the pipeline: the stub, with the rules file of its attempt ($T/rules<k>: k 1 for the run dir without -r<j>, else j)
  cat > "$T/pipe.sh" <<EOF
#!/usr/bin/env bash
rd="" prev=""
for a in "\$@"; do [[ "\$prev" == --run-dir ]] && rd="\$a"; prev="\$a"; done
k=1; [[ "\$(basename "\$rd")" =~ -r([0-9]+)\$ ]] && k="\${BASH_REMATCH[1]}"
if [[ -f "$T/rules\$k" ]]; then export STUB_RULES="$T/rules\$k"; else unset STUB_RULES; fi
exec "$FX/ablation-pipeline-stub.sh" "\$@"
EOF
  chmod +x "$T/pipe.sh"
  # rows for the row-writer cases (the ablation-row.bats fixture runs)
  RFX="$FX/ablation-runs"; cp -a "$RFX/runs" "$T/runs"; cp "$RFX/MANIFEST.json" "$T/MANIFEST.json"
  BUILD_TASK="$RFX/tasks/bf-01/task.yaml"
}

teardown() {
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

# suite <arm=policy>…: the suite file with those arms' refusal_policy set
suite() {
  local f='.' a
  for a in "$@"; do f="$f | (.arms[] | select(.id == \"${a%%=*}\")).refusal_policy = \"${a#*=}\""; done
  yq "$f" "$REPO_ROOT/evals/suites/ablation-2.0.yaml" > "$T/suite.yaml"
}
ra() {
  run "$RA" --source-commit "$SHA" --results-root "$RES" --self-check-log "$T/self-check.log" --suite-file "$T/suite.yaml" \
    --pipeline-bin "$T/pipe.sh" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/bin/docker" "$@"
}
rules() { printf '* %s\n' "$2" > "$T/rules$1"; }   # rules <attempt k> <stub mode>
row_of() { jq -c --arg r "$1" 'select(.run_id == $r)' "$RES/runs.jsonl"; }
calls() { local n; n="$(grep -c "^$1 " "$T/stub.log" 2>/dev/null)" || true; printf '%s' "${n:-0}"; }
R() { jq -r "$1" <<<"$r"; }
# the row-writer cases
wrow() { local run="$1"; shift; "$ROWB" --run-dir "$T/runs/$run" --task-yaml "$BUILD_TASK" --manifest "$T/MANIFEST.json" --out "$T/rows.jsonl" "$@"; }
last() { sed -n '$p' "$T/rows.jsonl"; }
refuse_phase() {  # refuse_phase <run>: REVIEW fell back from Fable to Opus (execute-agent's record shape, EA-12)
  jq '(.phases[] | select(.label == "REVIEW") | .refusal_fallbacks) = [{"from": "claude-fable-5-1", "to": "global.anthropic.claude-opus-5-5", "category": "cyber", "scope": "session"}]' \
    "$T/runs/$1/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$T/runs/$1/meta/pipeline.json"
}
OUTC() { jq -r '"\(.refusal_policy_applied) \(.attempt) \(.refusal_outcome) \(.refusal_denominator) \(.refusal_flagged) \(.degraded)"' <<<"$(last)"; }

# --- ablation-row.sh 1.6 -------------------------------------------------------------------------------------------

@test "RP-1 every 1.6 row carries the refusal fields: no fallback reads none/included; the policy comes from the manifest (exclude when it predates the key); it validates" {
  wrow a1-build
  [ "$(jq -r '.row_writer_version' <<<"$(last)")" = 1.6 ]
  [ "$(OUTC)" = "exclude 1 none included false false" ]
  [ "$(jq -c '.refusal_attempts' <<<"$(last)")" = '[]' ]
  jq '.refusal_policy = {"a1_full": "keep"}' "$T/MANIFEST.json" > "$T/m.json" && mv "$T/m.json" "$T/MANIFEST.json"
  wrow a1-build
  [ "$(OUTC)" = "keep 1 none included false false" ]
  run "$ROWB" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "RP-2 exclude: a row with a fallback is invalid (degraded, cycle-132 behaviour) and leaves the denominator; keep: valid, flagged, counted, another degraded cause still degrades" {
  refuse_phase a1-build
  wrow a1-build
  [ "$(OUTC)" = "exclude 1 excluded excluded false true" ]
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" == *"REVIEW: refusal fallback"* ]]
  # the original and fallback model ids stay on the phase record
  [ "$(jq -r '.phases[] | select(.label == "REVIEW") | .refusal_fallbacks[0] | "\(.from) \(.to)"' <<<"$(last)")" = "claude-fable-5-1 global.anthropic.claude-opus-5-5" ]
  wrow a1-build --refusal-policy keep
  [ "$(OUTC)" = "keep 1 kept included true false" ]
  [ "$(jq -r '.degraded_reason' <<<"$(last)")" = null ]
  jq '(.phases[] | select(.label == "IMPLEMENT") | .models_used) = {"global.anthropic.claude-haiku-4-5": 3}' "$T/runs/a1-build/meta/pipeline.json" > "$T/p.json" && mv "$T/p.json" "$T/runs/a1-build/meta/pipeline.json"
  wrow a1-build --refusal-policy keep
  [ "$(OUTC)" = "keep 1 kept included true true" ]
  [[ "$(jq -r '.degraded_reason' <<<"$(last)")" != *"refusal fallback"* ]]
  run "$ROWB" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "RP-3 rerun-once rows: attempt 2 without a fallback is the cell (rerun_clean, the refused attempt recorded, both attempts in all_spend_usd); a second refusal and an infrastructure failure on the retry are invalid with both attempts recorded; attempt 1 with a fallback is rerun_not_run" {
  cp -a "$T/runs/a1-build" "$T/runs/first"; refuse_phase first
  wrow a1-build --refusal-policy rerun-once --refusal-attempt 2 --refused-attempt "$T/runs/first" --prior-spend 2.5 --attempts 2
  [ "$(OUTC)" = "rerun-once 2 rerun_clean included false false" ]
  [ "$(jq -c '.refusal_attempts[0] | [.attempt, .run_dir, .status, (.refusal_fallbacks[0].label), (.refusal_fallbacks[0].refusal_fallbacks[0].to)]' <<<"$(last)")" = '[1,"first","completed","REVIEW","global.anthropic.claude-opus-5-5"]' ]
  [ "$(jq -r '.refusal_attempts[0].cost_usd' <<<"$(last)")" = "$(jq -r '.spent_usd // 0' "$T/runs/first/meta/pipeline.json")" ]
  [ "$(jq -r '.all_spend_usd == .cost_usd + 2.5' <<<"$(last)")" = true ]
  refuse_phase a1-build
  wrow a1-build --refusal-policy rerun-once --refusal-attempt 2 --refused-attempt "$T/runs/first"
  [ "$(OUTC)" = "rerun-once 2 rerun_refused excluded false true" ]
  cp -a "$T/runs/first" "$T/runs/third"; jq '.phases |= map(.refusal_fallbacks = [])' "$T/runs/first/meta/pipeline.json" > "$T/runs/third/meta/pipeline.json"
  wrow third --refusal-policy rerun-once --refusal-attempt 2 --refused-attempt "$T/runs/first" --status infrastructure_error
  [ "$(OUTC)" = "rerun-once 2 rerun_failed excluded false false" ]
  [ "$(jq -r '.refusal_attempts | length' <<<"$(last)")" = 1 ]
  wrow first --refusal-policy rerun-once
  [ "$(OUTC)" = "rerun-once 1 rerun_not_run excluded false true" ]
  run "$ROWB" --validate "$T/rows.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "RP-4 --validate refuses an inconsistent 1.6 row; usage errors exit 2" {
  wrow a1-build
  local good; good="$(last)"
  while IFS='~' read -r edit want; do
    jq -c "$edit" <<<"$good" > "$T/bad.jsonl"
    run "$ROWB" --validate "$T/bad.jsonl"
    [ "$status" -eq 1 ] || { echo "edit $edit: status $status"; false; }
    grep -qF -- "$want" <<<"$output" || { echo "edit $edit: $output"; false; }
  done <<'EOF'
del(.refusal_outcome)~missing field refusal_outcome
.refusal_policy_applied = "sometimes"~is not exclude|keep|rerun-once
.refusal_outcome = "maybe"~is not none|excluded
.refusal_denominator = "both"~is not included|excluded
.attempt = 2~is inconsistent with refusal_attempts
.attempt = 3~is inconsistent with refusal_attempts
.refusal_outcome = "kept"~is inconsistent with refusal_policy_applied
.refusal_outcome = "excluded" | .refusal_denominator = "excluded" | .refusal_policy_applied = "keep"~is inconsistent with refusal_policy_applied
.refusal_flagged = true~is inconsistent with refusal_policy_applied
.refusal_outcome = "rerun_clean"~is inconsistent with refusal_policy_applied
EOF
  run wrow a1-build --refusal-policy sometimes
  [ "$status" -eq 2 ]; grep -qF -- '--refusal-policy must be exclude, keep or rerun-once' <<<"$output"
  run wrow a1-build --refusal-attempt 2
  [ "$status" -eq 2 ]; grep -qF -- '--refusal-attempt 2 needs --refused-attempt' <<<"$output"
  run wrow a1-build --refused-attempt "$T/runs/a1-build"
  [ "$status" -eq 2 ]; grep -qF -- '--refused-attempt goes with --refusal-attempt 2' <<<"$output"
  run wrow a1-build --refusal-attempt 3
  [ "$status" -eq 2 ]
}

@test "RP-5 --refusal-rate: per arm, refused rows over rows; above 0.2 is flagged (0.2 itself is not); a pre-1.6 row counts by its phase records" {
  wrow a1-build                                   # a1_full, no fallback
  refuse_phase a1-build; wrow a1-build            # a1_full, excluded
  for _ in 1 2 3; do wrow a0-build; done          # a0_bare ×3, clean
  jq -c '.refusal_outcome = "none"' <<<"$(sed -n 3p "$T/rows.jsonl")" >> "$T/rows.jsonl"   # a0_bare 4th row
  jq -c 'del(.refusal_outcome) | .row_writer_version = "1.5" | .arm = "a3_one_voice"' <<<"$(sed -n 2p "$T/rows.jsonl")" >> "$T/rows.jsonl"   # a 1.5 row with a fallback
  run "$ROWB" --refusal-rate "$T/rows.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local j; j="$(grep '^{' <<<"$output")"
  [ "$(jq -c '.arms | to_entries | map("\(.key)=\(.value.refused)/\(.value.rows):\(.value.refusal_rate):\(.value.flagged)")' <<<"$j")" = '["a0_bare=0/4:0:false","a1_full=1/2:0.5:true","a3_one_voice=1/1:1:true"]' ]
  [ "$(jq -r '.threshold' <<<"$j")" = 0.2 ]
  grep -qF 'refusal_rate a1_full 0.5 (1 of 2) FLAGGED (above 0.2)' <<<"$output"
  # exactly 0.2 (1 of 5) is not flagged
  { sed -n 2p "$T/rows.jsonl"; for _ in 1 2 3 4; do sed -n 1p "$T/rows.jsonl"; done; } > "$T/five.jsonl"
  run "$ROWB" --refusal-rate "$T/five.jsonl"
  [ "$(grep '^{' <<<"$output" | jq -r '.arms.a1_full | "\(.refusal_rate) \(.flagged)"')" = "0.2 false" ]
  run "$ROWB" --refusal-rate "$T/nope.jsonl"
  [ "$status" -eq 2 ]
}

# --- run-ablation.sh ------------------------------------------------------------------------------------------------

@test "RP-R1 pre-flight: the policy is recorded in MANIFEST.json before execution (absent = exclude); an unknown value and a non-exclude policy on a matched arm are refused (exit 2)" {
  suite a1_full=rerun-once a3_one_voice=keep
  ra --arms a0_bare,a1_full,a3_one_voice --tasks bugfix-v2-02 --trials-build 1 --batch m1 --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.refusal_policy' "$RES/m1/MANIFEST.json")" = '{"a0_bare":"exclude","a1_full":"rerun-once","a3_one_voice":"keep"}' ]
  suite a1_full=sometimes
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch m2 --dry-run
  [ "$status" -eq 2 ]
  grep -qF "arm 'a1_full': refusal_policy 'sometimes' is not exclude|keep|rerun-once" <<<"$output"
  suite a0_bare_matched=keep
  ra --arms a0_bare_matched --tasks review-01 --trials-review 1 --batch m3 --dry-run
  [ "$status" -eq 2 ]
  grep -qF "arm 'a0_bare_matched' is a matched arm (bare_sessions: matched): refusal_policy must be exclude, not 'keep'" <<<"$output"
  [ ! -e "$RES/m3/MANIFEST.json" ]
}

@test "RP-R2 exclude (the default) and keep: one attempt each; exclude rows the refusal degraded and excluded, keep valid and flagged" {
  suite a0_bare=keep
  rules 1 refusal
  ra --arms a1_full,a0_bare --tasks bugfix-v2-02 --trials-build 1 --batch e1 --concurrency 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(calls e1-a1_full-bugfix-v2-02-t1)" = 1 ] && [ "$(calls e1-a0_bare-bugfix-v2-02-t1)" = 1 ]
  r="$(row_of e1-a1_full-bugfix-v2-02-t1)"
  [ "$(R '"\(.refusal_policy_applied) \(.attempt) \(.refusal_outcome) \(.refusal_denominator) \(.degraded)"')" = "exclude 1 excluded excluded true" ]
  r="$(row_of e1-a0_bare-bugfix-v2-02-t1)"
  [ "$(R '"\(.refusal_policy_applied) \(.attempt) \(.refusal_outcome) \(.refusal_denominator) \(.refusal_flagged) \(.degraded) \(.status)"')" = "keep 1 kept included true false completed" ]
  [ ! -e "$RES/e1/a1_full/bugfix-v2-02-t1.refusal-1.json" ] && [ ! -e "$RES/e1/a1_full/bugfix-v2-02-t1-r2" ]
  run "$ROWB" --validate "$RES/runs.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "RP-R3 rerun-once: the refused attempt is kept and recorded once (immutable), the trial relaunched once at the same plan index; the second attempt's row is the cell; both attempts are charged" {
  suite a1_full=rerun-once
  rules 1 refusal
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch r1 --concurrency 1 --max-usd 100
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  B="$RES/r1/a1_full"
  [ "$(calls r1-a1_full-bugfix-v2-02-t1)" = 2 ]
  [ "$(awk '{print $5}' "$T/stub.log" | tr '\n' ' ')" = "bugfix-v2-02-t1 bugfix-v2-02-t1-r2 " ]
  # the first attempt is untouched: its record still carries the fallback and it was never graded
  jq -e '[.phases[] | select((.refusal_fallbacks | length) > 0)] | length > 0' "$B/bugfix-v2-02-t1/meta/pipeline.json" >/dev/null
  [ ! -e "$B/bugfix-v2-02-t1/grade.json" ] && [ -e "$B/bugfix-v2-02-t1-r2/grade.json" ]
  [ "$(jq -c '[.schema_version, .attempt, .run_dir, .status, .attempts, .cost_usd, (.refusal_fallbacks | length > 0)]' "$B/bugfix-v2-02-t1.refusal-1.json")" = '[1,1,"bugfix-v2-02-t1","completed",1,2.5,true]' ]
  [ "$(wc -l < "$RES/runs.jsonl")" -eq 1 ]
  r="$(row_of r1-a1_full-bugfix-v2-02-t1)"
  [ "$(R '"\(.refusal_policy_applied) \(.attempt) \(.refusal_outcome) \(.refusal_denominator) \(.degraded) \(.status) \(.attempts)"')" = "rerun-once 2 rerun_clean included false completed 2" ]
  [ "$(R '"\(.refusal_attempts[0].run_dir) \(.refusal_attempts[0].cost_usd) \(.cost_usd) \(.all_spend_usd)"')" = "bugfix-v2-02-t1 2.5 2.5 5" ]
  [ "$(jq -r '.spend | "\(.rows_usd) \(.ledger_usd) \(.spent_usd)"' "$RES/r1/STATUS.json")" = "2.5 2.5 5" ]
  grep -q 'attempt 1 kept in .*bugfix-v2-02-t1 .*relaunching once' "$B/bugfix-v2-02-t1.log"
  run "$ROWB" --validate "$RES/runs.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "RP-R4 rerun-once: a second refusal is never relaunched (invalid, both attempts recorded); an infrastructure failure on the retry rows the cell invalid with both attempts recorded" {
  suite a1_full=rerun-once
  rules 1 refusal; rules 2 refusal
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch s1 --concurrency 1
  [ "$(calls s1-a1_full-bugfix-v2-02-t1)" = 2 ]
  r="$(row_of s1-a1_full-bugfix-v2-02-t1)"
  [ "$(R '"\(.attempt) \(.refusal_outcome) \(.refusal_denominator) \(.degraded) \(.refusal_attempts | length) \(.all_spend_usd)"')" = "2 rerun_refused excluded true 1 5" ]
  rules 2 crash
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch s2 --concurrency 1
  [ "$(calls s2-a1_full-bugfix-v2-02-t1)" = 2 ]
  r="$(row_of s2-a1_full-bugfix-v2-02-t1)"
  [ "$(R '"\(.status) \(.attempt) \(.refusal_outcome) \(.refusal_denominator) \(.refusal_attempts[0].run_dir)"')" = "interrupted 2 rerun_failed excluded bugfix-v2-02-t1" ]
  run "$ROWB" --validate "$RES/runs.jsonl"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "RP-R5 rerun-once within the attempt limit: a transport retry then a refusal relaunches once more (3 attempts, every attempt's spend in all_spend_usd)" {
  suite a1_full=rerun-once
  rules 1 transport; rules 2 refusal
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch t1 --concurrency 1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(awk '{print $5}' "$T/stub.log" | tr '\n' ' ')" = "bugfix-v2-02-t1 bugfix-v2-02-t1-r2 bugfix-v2-02-t1-r3 " ]
  [ "$(jq -c '[.run_dir, .attempts, .cost_usd]' "$RES/t1/a1_full/bugfix-v2-02-t1.refusal-1.json")" = '["bugfix-v2-02-t1-r2",2,5]' ]
  r="$(row_of t1-a1_full-bugfix-v2-02-t1)"
  [ "$(R '"\(.attempt) \(.attempts) \(.refusal_outcome) \(.all_spend_usd)"')" = "2 3 rerun_clean 7.5" ]
  [ "$(jq -r '.spend.spent_usd' "$RES/t1/STATUS.json")" = 7.5 ]
}

@test "RP-R6 a driver killed during the second attempt resumes it: the record is reused, the first attempt is never run again and its spend is charged once" {
  suite a1_full=rerun-once
  rules 1 refusal; rules 2 hang
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch k1 --concurrency 1 --detach
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  pid="$(sed -n 's/.* pid \([0-9]*\).*/\1/p' <<<"$output")"
  B="$RES/k1/a1_full"
  for _ in $(seq 1 150); do [[ -f "$B/bugfix-v2-02-t1-r2/meta/pipeline.json" ]] && break; sleep 0.2; done
  [ -f "$B/bugfix-v2-02-t1.refusal-1.json" ]
  kill -TERM "$pid"
  for _ in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
  ! kill -0 "$pid" 2>/dev/null || false
  [ ! -s "$RES/runs.jsonl" ]
  local rec; rec="$(cat "$B/bugfix-v2-02-t1.refusal-1.json")"
  rm -f "$T/rules2"
  ra --batch k1 --resume
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(awk '{print $5}' "$T/stub.log" | tr '\n' ' ')" = "bugfix-v2-02-t1 bugfix-v2-02-t1-r2 bugfix-v2-02-t1-r3 " ]
  [ "$(cat "$B/bugfix-v2-02-t1.refusal-1.json")" = "$rec" ]
  r="$(row_of k1-a1_full-bugfix-v2-02-t1)"
  [ "$(R '"\(.attempt) \(.refusal_outcome) \(.refusal_attempts[0].run_dir) \(.all_spend_usd)"')" = "2 rerun_clean bugfix-v2-02-t1 5" ]
  [ "$(jq -r '.spend | "\(.ledger_usd) \(.spent_usd)"' "$RES/k1/STATUS.json")" = "2.5 5" ]
}

@test "RP-R7 rerun-once at the attempt limit: a --rerun-status replacement whose in-line transport retry then refuses has used 3 attempts, so it is not relaunched (rerun_not_run, excluded)" {
  suite a1_full=rerun-once
  rules 1 crash
  ra --arms a1_full --tasks bugfix-v2-02 --trials-build 1 --batch l1 --concurrency 1
  [ "$(jq -r '.status' "$RES/runs.jsonl")" = interrupted ]
  rules 2 transport; rules 3 refusal
  ra --batch l1 --resume --rerun-status interrupted
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(awk '{print $5}' "$T/stub.log" | tr '\n' ' ')" = "bugfix-v2-02-t1 bugfix-v2-02-t1-r2 bugfix-v2-02-t1-r3 " ]
  [ ! -e "$RES/l1/a1_full/bugfix-v2-02-t1.refusal-1.json" ]
  r="$(row_of l1-a1_full-bugfix-v2-02-t1)"
  [ "$(R '"\(.attempts) \(.attempt) \(.refusal_outcome) \(.refusal_denominator) \(.degraded)"')" = "3 1 rerun_not_run excluded true" ]
  grep -q 'not relaunched: 3 attempts used, the limit is 3 (D-7.3)' "$RES/l1/a1_full/bugfix-v2-02-t1.log"
}
