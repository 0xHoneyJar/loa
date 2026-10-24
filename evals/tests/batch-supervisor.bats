#!/usr/bin/env bats
# =============================================================================
# evals/tests/batch-supervisor.bats — cycle-133 Sprint 273 Task 2.4 (SDD C-9 supervisor half as amended by
# D-2.5; PRD FR-9; bd-yvjew, KF-052)
#
# evals/harness/lib/batch-supervisor.sh against stub runners (BSV-1 … BSV-11) and run-ablation.sh --supervised
# against the run-ablation.bats stubs (BSV-12, BSV-13): no model call, no docker, no systemd. loginctl,
# docker and systemd-run are stubs first on PATH; the boot id is a test file (LOA_SUPERVISOR_BOOT_ID_FILE).
# =============================================================================

setup() {
  # cycle-133 FR-9 (SDD C-9): these suites drive run-ablation.sh with a stub docker and no egress block; the
  # test-mode escape (LOA_EGRESS_TEST_MODE=1 AND BATS_TEST_FILENAME) records enforced: false instead of refusing.
  export LOA_EGRESS_TEST_MODE=1
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  SUP="$REPO_ROOT/evals/harness/lib/batch-supervisor.sh"
  RA="$REPO_ROOT/evals/harness/run-ablation.sh"
  FX="$TESTS_DIR/fixtures"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/bsv.XXXXXX")"
  mkdir -p "$T/bin" "$T/res"
  B="$T/res/b1"
  # loginctl: Linger from $T/linger (default yes)
  cat > "$T/bin/loginctl" <<'EOF'
#!/usr/bin/env bash
echo "loginctl $*" >> "${STUB_LOGINCTL_LOG:-/dev/null}"
cat "$(dirname "$0")/../linger" 2>/dev/null || echo yes
EOF
  # docker: ps lists $T/containers, rm -f logs; everything else delegated to the run-ablation stub
  cat > "$T/bin/docker" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  ps) cat "$T/containers" 2>/dev/null; exit 0 ;;
  rm) shift; echo "rm \$*" >> "$T/docker.log"; exit 0 ;;
esac
exec "$FX/ablation-docker-stub.sh" "\$@"
EOF
  chmod +x "$T/bin/loginctl" "$T/bin/docker"
  echo "11111111-2222-3333-4444-555555555555" > "$T/boot_id"
  export PATH="$T/bin:$PATH" LOA_SUPERVISOR_BOOT_ID_FILE="$T/boot_id" LOA_SUPERVISOR_POLL_S=0.2 \
    LOA_SUPERVISOR_GRACE_S=1 LOA_SUPERVISOR_MODE=setsid EVAL_DOCKER_BIN="$T/bin/docker"
  unset LOA_SUPERVISOR_HANG_S STUB_LOGINCTL_LOG
}

teardown() {
  # every process a case left (a supervisor, a stub runner, a sleeper) is killed by its session
  for f in "$T"/pids/* "$B"/supervisor/state.json; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *state.json) for p in $(jq -r '.owner_pid, .runner_pid | select(. != null)' "$f" 2>/dev/null); do kill -KILL -- "-$p" 2>/dev/null || kill -KILL "$p" 2>/dev/null || true; done ;;
      *) p="$(cat "$f")"; kill -KILL -- "-$p" 2>/dev/null || kill -KILL "$p" 2>/dev/null || true ;;
    esac
  done
  find "$T" -mindepth 1 -delete 2>/dev/null || true
  rmdir "$T" 2>/dev/null || true
}

# runner <body> — a stub runner at $T/runner: logs its argv (one line per invocation) to $T/runner.log; $N is the
# 1-based invocation number; BATCH_DIR is the batch dir; the body follows
runner() {
  cat > "$T/runner" <<EOF
#!/usr/bin/env bash
set -uo pipefail
BATCH_DIR="$B" T="$T"
echo "\$*" >> "$T/runner.log"
N=\$(wc -l < "$T/runner.log" | tr -d ' ')
mkdir -p "\$BATCH_DIR"
[[ -f "\$BATCH_DIR/MANIFEST.json" ]] || echo '{}' > "\$BATCH_DIR/MANIFEST.json"
st() { printf '{"schema_version":1,"state":"%s","cuts":%s,"paused_arms":%s,"outage":%s,"signalled":%s}\n' "\$1" "\${2:-[]}" "\${3:-{\}}" "\${4:-null}" "\${5:-false}" > "\$BATCH_DIR/STATUS.json"; }
$1
EOF
  chmod +x "$T/runner"
}
launch() { run "$SUP" launch "$B" --runner "$T/runner" "$@"; }
# wait_for <seconds> <bash condition>
wait_for() { local i=0 n; n=$(( $1 * 10 )); while (( i < n )); do eval "$2" && return 0; sleep 0.1; i=$((i + 1)); done; echo "timed out: $2" >&2; return 1; }
sup_done() { local p; p="$(jq -r '.owner_pid // empty' "$B/supervisor/state.json" 2>/dev/null)"; [[ -n "$p" ]] && ! kill -0 "$p" 2>/dev/null && [[ "$(jq -r '.state' "$B/supervisor/state.json")" != running ]]; }
S() { jq -r "$1" "$B/supervisor/state.json"; }
ticks_of() { awk '{ sub(/^.*\) /, ""); print $20 }' "/proc/$1/stat"; }
sleeper() { mkdir -p "$T/pids"; setsid sleep 300 </dev/null >/dev/null 2>&1 & echo "$!" > "$T/pids/$1"; wait_for 5 "[ -e /proc/$! ]"; echo "$!"; }

@test "BSV-1 a killed driver is resumed once: the retry carries a retry id, the second runner gets --resume --batch, STATUS.json and state.json hold the supervisor entry" {
  runner '
if [[ $N -eq 1 ]]; then st running; kill -KILL $$; fi
st complete; exit 0'
  launch --max-retries 3 -- --arms a0_bare --batch b1 --source-commit abc1234 --results-root "$T/res"
  [ "$status" -eq 0 ]
  grep -q "^supervised: batch $B mode setsid pid [0-9]*" <<<"$output"
  wait_for 20 sup_done
  [ "$(wc -l < "$T/runner.log")" -eq 2 ]
  [ "$(sed -n 1p "$T/runner.log")" = "--arms a0_bare --batch b1 --source-commit abc1234 --results-root $T/res" ]
  [ "$(sed -n 2p "$T/runner.log")" = "--resume --batch b1 --results-root $T/res" ]
  [ "$(S .state)" = complete ]
  [ "$(S '.retries | length')" = 1 ]
  [ "$(S '.retries[0].reason_class')" = driver_lost ]
  [[ "$(S '.retries[0].retry_id')" =~ ^sv-[0-9TZ]+-[0-9a-f]{8}-r1$ ]]
  [[ "$(S '.retries[0].retry_id')" == "$(S .attempt_id)-r1" ]]
  [ "$(S .cap)" = 3 ]
  [ "$(S .boot_id)" = "11111111-2222-3333-4444-555555555555" ]
  for k in owner_pid boot_id start_time start_ticks unit mode attempt_id retries cap; do jq -e --arg k "$k" 'has($k)' "$B/supervisor/state.json" >/dev/null || { echo "missing $k"; false; }; done
  [ "$(S .unit)" = null ]
  # the STATUS.json entry is the state record, mirrored under the status lock
  [ "$(jq -c '.supervisor | del(.updated)' "$B/STATUS.json")" = "$(jq -c 'del(.updated)' "$B/supervisor/state.json")" ]
  [ "$(jq -r '.args | join(" ")' "$B/supervisor/args.json")" = "--arms a0_bare --batch b1 --source-commit abc1234 --results-root $T/res" ]
}

@test "BSV-2 a second supervisor of the same batch is refused while the first holds supervisor.lock (exit 2, nothing changed)" {
  runner 'st running; sleep 300'
  launch -- --batch b1
  [ "$status" -eq 0 ]
  wait_for 10 "[ -s '$T/runner.log' ]"
  before="$(cat "$B/supervisor/state.json")"
  launch -- --batch b1
  [ "$status" -eq 2 ]
  grep -q "batch-supervisor: refused: $B is supervised by pid $(jq -r .owner_pid <<<"$before")" <<<"$output"
  [ "$(cat "$B/supervisor/state.json")" = "$before" ]
  [ "$(wc -l < "$T/runner.log")" -eq 1 ]
}

@test "BSV-3 the linger precondition: Linger=no and an absent loginctl refuse before any write and name loginctl enable-linger; Linger=yes launches" {
  runner 'st complete; exit 0'
  echo no > "$T/linger"
  launch -- --batch b1
  [ "$status" -eq 2 ]
  grep -q 'loginctl enable-linger' <<<"$output"
  [ ! -e "$B" ]
  LOA_SUPERVISOR_LOGINCTL="$T/no-such-loginctl" launch -- --batch b1
  [ "$status" -eq 2 ]
  grep -q 'loginctl enable-linger' <<<"$output"
  [ ! -e "$B" ]
  echo yes > "$T/linger"
  launch -- --batch b1
  [ "$status" -eq 0 ]
  wait_for 10 sup_done
  [ "$(S .state)" = complete ]
}

@test "BSV-4 the retry cap: a driver that dies every time is retried --max-retries times, then the supervisor gives up (state gave_up, exit 1 in the log)" {
  runner 'st running; kill -KILL $$'
  launch --max-retries 2 -- --batch b1
  [ "$status" -eq 0 ]
  wait_for 20 sup_done
  [ "$(wc -l < "$T/runner.log")" -eq 3 ]
  [ "$(S .state)" = gave_up ]
  [ "$(S '.retries | length')" = 2 ]
  [ "$(S '[.retries[].retry_id] | unique | length')" = 2 ]
  [ "$(S '.last_exit.reason_class')" = driver_lost ]
  grep -q 'retry cap 2 reached' "$B/supervisor/supervisor.log"
  grep -q 'exit 1' "$B/supervisor/supervisor.log"
}

@test "BSV-5 non-retryable classes are reported, never retried: budget cut, metering_incomplete, refusal (exit 2), paused arm, outage, failed (exit 3)" {
  for case in "budget|st partial '[{\"reason\":\"max_usd\"}]'; exit 1" \
              "metering_incomplete|mkdir -p \$BATCH_DIR/a/x-t1/meta; echo '{\"status\":\"infrastructure_error\",\"reason\":\"metering_incomplete: no valid price\"}' > \$BATCH_DIR/a/x-t1/meta/pipeline.json; st partial; exit 1" \
              "refusal|exit 2" \
              "paused_arm|st partial '[]' '{\"a1_full\":\"took-effect FAIL\"}'; exit 1" \
              "outage|st partial '[]' '{}' '{\"consecutive\":3}'; exit 1" \
              "failed|st failed; exit 3"; do
    want="${case%%|*}" body="${case#*|}"
    rm -rf "$B" "$T/runner.log"
    runner "$body"
    launch -- --batch b1
    [ "$status" -eq 0 ]
    wait_for 15 sup_done
    [ "$(wc -l < "$T/runner.log")" -eq 1 ] || { echo "$want retried"; false; }
    [ "$(S .state)" = halted ] || { echo "$want: $(S .state)"; false; }
    [ "$(S .last_exit.reason_class)" = "$want" ] || { echo "want $want got $(S .last_exit.reason_class)"; false; }
    [ "$(S '.retries | length')" = 0 ]
  done
}

@test "BSV-6 a partial batch with infrastructure_error rows is retryable: the resume reruns those rows (--rerun-status infrastructure_error)" {
  runner '
if [[ $N -eq 1 ]]; then st partial; echo "{\"run_id\":\"b1-a-x-t1\",\"status\":\"infrastructure_error\"}" > "$BATCH_DIR/rows.jsonl"; exit 1; fi
st complete; exit 0'
  mkdir -p "$B"
  launch -- --batch b1 --rows "$B/rows.jsonl"
  [ "$status" -eq 0 ]
  wait_for 15 sup_done
  [ "$(S .state)" = complete ]
  [ "$(S '.retries[0].reason_class')" = infrastructure_error ]
  [ "$(sed -n 2p "$T/runner.log")" = "--resume --batch b1 --rerun-status infrastructure_error" ]
}

@test "BSV-7 hang detection: a runner alive with no file under the batch updated for the hang window is terminated (its process group) and resumed" {
  export LOA_SUPERVISOR_HANG_S=2
  runner '
if [[ $N -eq 1 ]]; then st running; mkdir -p "$T/pids"; setsid sleep 300 </dev/null >/dev/null 2>&1 & echo $! > "$T/pids/hang-child"; sleep 300; fi
st complete; exit 0'
  launch -- --batch b1
  [ "$status" -eq 0 ]
  wait_for 30 sup_done
  [ "$(S .state)" = complete ]
  [ "$(S '.retries[0].reason_class')" = hang ]
  [ "$(wc -l < "$T/runner.log")" -eq 2 ]
}

@test "BSV-8 cancellation during an active request: stop terminates the runner's group and the pipeline groups under .jobs/, removes the batch's containers only, records the uncertain provider requests and never retries" {
  printf '%s\n' "loa-abl-b1-a1_full-x-t1-IMPLEMENT" "loa-abl-b10-a1_full-x-t1-IMPLEMENT" "loa-abl-other-x" > "$T/containers"
  runner '
st running
mkdir -p "$BATCH_DIR/.jobs" "$BATCH_DIR/a1_full/x-t1/meta" "$BATCH_DIR/a1_full/x-t1/sandbox/.eval" "$BATCH_DIR/a1_full/y-t1/meta" "$BATCH_DIR/a1_full/y-t1/eval"
echo "{\"status\":\"running\"}" > "$BATCH_DIR/a1_full/x-t1/meta/pipeline.json"
printf "%s\n" "{\"request_id\":\"req-b\",\"cost_micro_usd\":10}" "{\"request_id\":\"req-a\",\"cost_micro_usd\":5}" > "$BATCH_DIR/a1_full/x-t1/sandbox/.eval/cost-ledger.jsonl"
echo "{\"status\":\"completed\"}" > "$BATCH_DIR/a1_full/y-t1/meta/pipeline.json"
echo "{\"request_id\":\"req-done\"}" > "$BATCH_DIR/a1_full/y-t1/eval/cost-ledger.jsonl"
setsid sleep 300 </dev/null >/dev/null 2>&1 & echo "$! 0" > "$BATCH_DIR/.jobs/j0001.pgid"; echo $! > "$T/pipeline-pid"
echo ready > "$T/ready"; sleep 300'
  launch -- --batch b1 --docker-bin "$T/bin/docker"
  [ "$status" -eq 0 ]
  wait_for 10 "[ -f '$T/ready' ]"
  pp="$(cat "$T/pipeline-pid")" rp="$(S .runner_pid)"
  run "$SUP" stop "$B"
  [ "$status" -eq 0 ]
  wait_for 20 sup_done
  ! kill -0 "$pp" 2>/dev/null
  ! kill -0 "$rp" 2>/dev/null
  [ "$(S .state)" = stopped ]
  [ "$(S '.retries | length')" = 0 ]
  [ "$(S .stopped.reason_class)" = intentional_stop ]
  [ "$(S '.stopped.provider_request_ids | join(",")')" = "req-a,req-b" ]
  [ "$(S '.stopped.uncertain_runs | join(",")')" = "a1_full/x-t1" ]
  [ "$(S '.stopped.ledger_micro_usd')" = 15 ]
  [ "$(cat "$T/docker.log")" = "rm -f loa-abl-b1-a1_full-x-t1-IMPLEMENT" ]
  [ "$(wc -l < "$T/runner.log")" -eq 1 ]
}

@test "BSV-9 reboot with PID reuse: the recorded runner pid and job group now belong to unrelated live processes (boot id changed) — they are not signalled, the stale .lock and .jobs are cleared, the batch resumes as a reboot retry" {
  p="$(sleeper reused)"
  mkdir -p "$B/supervisor" "$B/.lock" "$B/.jobs"
  echo "$p" > "$B/.lock/pid"; echo "$p 0" > "$B/.jobs/j0001.pgid"
  jq -n --argjson p "$p" --arg t "$(ticks_of "$p")" '{schema_version: 1, state: "running", owner_pid: $p, boot_id: "old-boot",
    start_ticks: $t, runner_pid: $p, runner_start_ticks: $t, attempt_id: "sv-old", unit: null, mode: "setsid", cap: 3, retries: []}' > "$B/supervisor/state.json"
  printf '{"schema_version":1,"args":["--batch","b1","--arms","a0_bare"],"runner":"%s","max_retries":3}\n' "$T/runner" > "$B/supervisor/args.json"
  echo '{"schema_version":1,"dry_run":false}' > "$B/MANIFEST.json"; echo '{"state":"running"}' > "$B/STATUS.json"
  runner 'st complete; exit 0'
  run "$SUP" restore "$B"
  [ "$status" -eq 0 ]
  wait_for 15 sup_done
  kill -0 "$p"
  [ ! -e "$B/.lock" ]
  [ ! -e "$B/.jobs" ]
  [ "$(S .state)" = complete ]
  [ "$(S '.retries[0].reason_class')" = reboot ]
  [ "$(S '.retries[0].groups_terminated | length')" = 0 ]
  [ "$(cat "$T/runner.log")" = "--resume --batch b1" ]
}

@test "BSV-10 same boot, PID reused: a live pid whose start time differs from the record is not the owner — not signalled, the restore proceeds" {
  p="$(sleeper reused)"
  mkdir -p "$B/supervisor"
  jq -n --argjson p "$p" '{schema_version: 1, state: "running", owner_pid: $p, boot_id: "11111111-2222-3333-4444-555555555555",
    start_ticks: "1", runner_pid: $p, runner_start_ticks: "1", attempt_id: "sv-old", unit: null, mode: "setsid", cap: 3, retries: []}' > "$B/supervisor/state.json"
  printf '{"schema_version":1,"args":["--batch","b1"],"runner":"%s","max_retries":3}\n' "$T/runner" > "$B/supervisor/args.json"
  echo '{"schema_version":1,"dry_run":false}' > "$B/MANIFEST.json"; echo '{"state":"running"}' > "$B/STATUS.json"
  runner 'st complete; exit 0'
  run "$SUP" restore "$B"
  [ "$status" -eq 0 ]
  wait_for 15 sup_done
  kill -0 "$p"
  [ "$(S .state)" = complete ]
  [ "$(S '.retries[0].reason_class')" = driver_lost ]
}

@test "BSV-11 systemd mode: the batch runs as systemd-run --user --unit loa-batch-<name> --collect, the unit is recorded" {
  cat > "$T/bin/systemd-run" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$T/systemd-run.argv"
while [[ \$# -gt 0 && "\$1" != -- ]]; do shift; done; shift
setsid "\$@" </dev/null >/dev/null 2>&1 &
EOF
  chmod +x "$T/bin/systemd-run"
  runner 'st complete; exit 0'
  LOA_SUPERVISOR_MODE=systemd launch -- --batch b1
  [ "$status" -eq 0 ]
  grep -q "^supervised: batch $B mode systemd unit loa-batch-b1" <<<"$output"
  wait_for 15 sup_done
  grep -q -- '--user --unit loa-batch-b1 --collect' "$T/systemd-run.argv"
  ! grep -qE 'KEY|TOKEN|SECRET' "$T/systemd-run.argv"
  [ "$(S .unit)" = loa-batch-b1 ]
  [ "$(S .mode)" = systemd ]
  [ "$(S .state)" = complete ]
}

# --- run-ablation.sh --supervised (the run-ablation.bats stubs) -------------------------------------------------------
ra_env() {
  mkdir -p "$T/src/.claude"
  cp "$FX/docker-stub.sh" "$T/bin/docker-stub.sh"; chmod +x "$T/bin/docker-stub.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "2.1.300 (Claude Code)"' > "$T/bin/claude"; chmod +x "$T/bin/claude"
  echo "# loa" > "$T/src/.claude/CLAUDE.loa.md"
  ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m src )
  SHA="$(git -C "$T/src" rev-parse HEAD)"
  for i in $(seq 1 36); do echo "self-check base task-$i: PASS hidden 1/1"; done > "$T/self-check.log"
  mkdir -p "$T/creds/.codex"
  export EVAL_CLAUDE_BIN="$T/bin/claude" LOA_ABLATION_SOURCE_TREE="$T/src" LOA_ABLATION_RETRY_WAIT_S=0 LOA_ABLATION_POLL_S=0.2 \
    STUB_LOG="$T/stub.log" STUB_GRADE_LOG="$T/grade.log" LOA_EVAL_CREDS_HOME="$T/creds"
}

@test "BSV-12 run-ablation.sh --supervised: usage (--max-retries needs --supervised, 0-9; exclusive with --detach and --dry-run) and the linger refusal (exit 2, no batch written)" {
  ra_env
  run "$RA" --max-retries 2 --source-commit "$SHA" --batch b1 --results-root "$T/res"
  [ "$status" -eq 2 ]; grep -q -- '--max-retries needs --supervised' <<<"$output"
  run "$RA" --supervised --max-retries x --source-commit "$SHA" --batch b1 --results-root "$T/res"
  [ "$status" -eq 2 ]; grep -q -- '--max-retries must be' <<<"$output"
  run "$RA" --supervised --detach --source-commit "$SHA" --batch b1 --results-root "$T/res"
  [ "$status" -eq 2 ]; grep -q 'exclusive' <<<"$output"
  run "$RA" --supervised --dry-run --source-commit "$SHA" --batch b1 --results-root "$T/res"
  [ "$status" -eq 2 ]; grep -q 'exclusive' <<<"$output"
  echo no > "$T/linger"
  run "$RA" --supervised --arms a0_bare --tasks bugfix-v2-02 --source-commit "$SHA" --batch b1 --results-root "$T/res" \
    --self-check-log "$T/self-check.log" --pipeline-bin "$FX/ablation-pipeline-stub.sh" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/bin/docker"
  [ "$status" -eq 2 ]
  grep -q 'loginctl enable-linger' <<<"$output"
  [ ! -e "$B" ]
}

@test "BSV-13 end to end: the driver is SIGKILLed after a row landed while a second trial's pipeline is mid-request; the supervisor reconciles the orphan group and the batch's container, resumes once, and every run_id is rowed exactly once; MANIFEST keeps the run arguments" {
  ra_env
  printf '%s\n' "loa-abl-b1-a0_bare-refactor-v2-05-t1-BARE" "loa-abl-other-x" > "$T/containers"
  # the pipeline: refactor's first attempt is the active request (a ledger row, no final record) that waits for
  # bugfix's row, then SIGKILLs the driver and keeps running as an orphan; every other launch is the stub
  cat > "$T/pipeline" <<EOF
#!/usr/bin/env bash
rid="" rd=""; a=("\$@")
for ((i = 0; i < \${#a[@]}; i++)); do case "\${a[\$i]}" in --run-id) rid="\${a[\$((i + 1))]}" ;; --run-dir) rd="\${a[\$((i + 1))]}" ;; esac; done
if [[ "\$rid" == *refactor* && ! -e "$T/killed" ]]; then
  mkdir -p "\$rd/meta" "\$rd/sandbox/.eval"
  echo '{"status":"running"}' > "\$rd/meta/pipeline.json"
  echo '{"request_id":"req-inflight","cost_micro_usd":1000}' > "\$rd/sandbox/.eval/cost-ledger.jsonl"
  echo \$\$ > "$T/orphan-pid"
  for i in \$(seq 1 300); do grep -q 'bugfix-v2-02' "$T/res/runs.jsonl" 2>/dev/null && break; sleep 0.1; done
  touch "$T/killed"; kill -KILL "\$(cat "$B/.lock/pid")"
  sleep 300; exit 0
fi
exec "$FX/ablation-pipeline-stub.sh" "\$@"
EOF
  chmod +x "$T/pipeline"
  run "$RA" --supervised --max-retries 2 --arms a0_bare --tasks bugfix-v2-02,refactor-v2-05 --trials-build 1 --concurrency 2 \
    --source-commit "$SHA" --batch b1 --results-root "$T/res" --self-check-log "$T/self-check.log" \
    --pipeline-bin "$T/pipeline" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/bin/docker"
  [ "$status" -eq 0 ]
  grep -q "^supervised: batch $B mode setsid" <<<"$output"
  wait_for 90 sup_done
  cat "$B/supervisor/supervisor.log" >&2
  [ "$(S .state)" = complete ]
  [ "$(S '.retries | length')" = 1 ]
  [ "$(S '.retries[0].reason_class')" = driver_lost ]
  [ "$(S '.retries[0].provider_request_ids | join(",")')" = req-inflight ]
  [ "$(S '.retries[0].uncertain_runs | join(",")')" = "a0_bare/refactor-v2-05-t1" ]
  [ "$(S '.retries[0].groups_terminated | length')" -ge 1 ]
  ! kill -0 "$(cat "$T/orphan-pid")" 2>/dev/null
  [ "$(cat "$T/docker.log")" = "rm -f loa-abl-b1-a0_bare-refactor-v2-05-t1-BARE" ]
  [ "$(jq -r '.run_id' "$T/res/runs.jsonl" | sort | uniq -d)" = "" ]
  [ "$(jq -r '.run_id' "$T/res/runs.jsonl" | sort | tr '\n' ,)" = "b1-a0_bare-bugfix-v2-02-t1,b1-a0_bare-refactor-v2-05-t1," ]
  [ "$(jq -r '.state' "$B/STATUS.json")" = complete ]
  [ "$(jq -r '.supervisor.retries[0].retry_id' "$B/STATUS.json")" = "$(S '.retries[0].retry_id')" ]
  [ "$(jq -r '.supervisor.max_retries' "$B/MANIFEST.json")" = 2 ]
  jq -e '.supervisor.args | index("--arms") != null and index("--supervised") == null' "$B/MANIFEST.json" >/dev/null
}
