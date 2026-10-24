#!/usr/bin/env bats
# =============================================================================
# evals/tests/session-exec.bats — cycle-133 Sprint 273 Task 2.1 (SDD §1.4 C-6; PRD FR-6; bd-wqaj4, bd-g2c5i)
#
# evals/harness/lib/session-exec.sh in isolation: the fail-closed pricing sentinel (`ERR` + non-zero status)
# for every condition C-6 names, the metering rules (streaming snapshots per message id, cache rates, an
# interrupted turn, a refusal rerun, an unmetered attempt), the exec shim's descriptor enumeration
# (/proc/self/fd, LOA_KEEP_FDS, the closerange fallbacks) and the startup secrecy assertion. No model call.
# The descriptor-above-65535 case needs a hard RLIMIT_NOFILE above 65536: it runs natively when the host
# allows it, else in a throw-away container (--network none) when docker and $LOA_TEST_FD_IMAGE (default
# loa-ablation:258) are present, else it is skipped with the reason; SE-22 covers the same logic simulated.
# =============================================================================

setup() {
  TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
  LIB="$REPO_ROOT/evals/harness/lib/session-exec.sh"
  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/se.XXXXXX")"
  unset LOA_EVAL_PRICING_JSON LOA_KEEP_FDS
  # shellcheck source=../harness/lib/session-exec.sh
  source "$LIB"
  P1='{"in":1000000,"out":2000000,"cr":100000,"cc":1250000}'   # micro-USD per Mtok: 1, 2, 0.1, 1.25 micro-USD a token
}
teardown() { chmod -R u+rwx "$T" 2>/dev/null || true; find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }

# pf <table-json> <model> — price_for under an override table; sets status/output like `run`
pf() { LOA_EVAL_PRICING_JSON="$1" run price_for "$2"; }
# pe <prices> <budget> <line…> — price_events over a transcript built from the lines (each newline-terminated)
pe() { local p="$1" b="$2"; shift 2; printf '%s\n' "$@" > "$T/ev.jsonl"; run price_events "$T/ev.jsonl" "$p" "$b"; }
asst() {  # asst <id> <usage-json|none> [stop_reason]
  if [[ "$2" == none ]]; then jq -cn --arg id "$1" '{type: "assistant", message: {id: $id, content: [{type: "text", text: "x"}]}}'
  else jq -cn --arg id "$1" --argjson u "$2" --arg s "${3:-}" \
         '{type: "assistant", message: ({id: $id, content: [{type: "text", text: "x"}], usage: $u}
                                        + (if $s == "" then {} else {stop_reason: $s} end))}'; fi
}
INIT='{"type":"system","subtype":"init","session_id":"s1"}'
RESULT='{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'

# --- price_for: the sentinel ----------------------------------------------------------------------------------

@test "SE-1 price_for: a table entry → {in,out,cr,cc}; absent cache prices derive from the input price (0.1, 1.25)" {
  pf '{"m": {"input_per_mtok": 4000000, "output_per_mtok": 20000000}}' m
  [ "$status" -eq 0 ]
  [ "$output" = '{"in":4000000,"out":20000000,"cr":400000,"cc":5000000}' ]
  pf '{"m": {"input_per_mtok": 3, "output_per_mtok": 15, "cache_read_per_mtok": 0.3, "cache_write_per_mtok": 3.75}}' m
  [ "$status" -eq 0 ]
  [ "$output" = '{"in":3,"out":15,"cr":0.3,"cc":3.75}' ]
  pf '{"m": {"input_per_mtok": 3, "output_per_mtok": 15, "cache_creation_per_mtok": 4}}' m
  [ "$output" = '{"in":3,"out":15,"cr":0.3,"cc":4}' ]
}

@test "SE-2 price_for: a malformed LOA_EVAL_PRICING_JSON → ERR, non-zero" {
  pf '{"m": {"input_per_mtok": 1,' m
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  pf '[{"m": 1}]' m
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
}

@test "SE-3 price_for: a well-formed table without the session's model id → ERR, non-zero" {
  pf '{"other": {"input_per_mtok": 1, "output_per_mtok": 1}}' m
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  [[ "$output" == *"no price for model m"* ]]
}

@test "SE-4 price_for: a null, missing, negative, non-finite or non-numeric price → ERR, non-zero (each)" {
  local e
  for e in '{"input_per_mtok": null, "output_per_mtok": 1}' '{"output_per_mtok": 1}' \
           '{"input_per_mtok": -1, "output_per_mtok": 1}' '{"input_per_mtok": 1, "output_per_mtok": -0.5}' \
           '{"input_per_mtok": NaN, "output_per_mtok": 1}' '{"input_per_mtok": 1, "output_per_mtok": Infinity}' \
           '{"input_per_mtok": 1e999, "output_per_mtok": 1}' '{"input_per_mtok": "1", "output_per_mtok": 1}' \
           '{"input_per_mtok": true, "output_per_mtok": 1}' \
           '{"input_per_mtok": 1, "output_per_mtok": 1, "cache_read_per_mtok": null}' \
           '{"input_per_mtok": 1, "output_per_mtok": 1, "cache_write_per_mtok": -2}' \
           '"not an object"'; do
    pf "{\"m\": $e}" m
    echo "$e → $status $output"
    [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  done
}

@test "SE-5 price_for: zero prices are accepted as zero (distinct from an unknown price)" {
  pf '{"m": {"input_per_mtok": 0, "output_per_mtok": 0, "cache_read_per_mtok": 0, "cache_write_per_mtok": 0}}' m
  [ "$status" -eq 0 ]
  [ "$output" = '{"in":0,"out":0,"cr":0,"cc":0}' ]
  pf '{"m": {"input_per_mtok": 0, "output_per_mtok": 0}}' m
  [ "$output" = '{"in":0,"out":0,"cr":0,"cc":0}' ]
  printf '%s\n' "$(asst a '{"input_tokens": 1000, "output_tokens": 1000}')" "$RESULT" > "$T/z.jsonl"
  run price_events "$T/z.jsonl" '{"in":0,"out":0,"cr":0,"cc":0}' 100
  [ "$status" -eq 0 ]; [ "$output" = "1 0 0" ]
}

@test "SE-6 price_for without an override: pricing.py prices a known alias; an alias it does not know (null prices) → ERR" {
  run price_for global.anthropic.claude-opus-5-5
  [ "$status" -eq 0 ]
  [ "$(jq -r '"\(.in) \(.out)"' <<<"$output")" = "4000000 20000000" ]
  run price_for global.anthropic.claude-no-such-model-9
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
}

# --- price_events: the sentinel and the metering rules --------------------------------------------------------

@test "SE-7 price_events: per-turn cost, the estimate and the crossing turn (output contract unchanged)" {
  pe "$P1" 1000000000 "$INIT" "$(asst a '{"input_tokens": 10, "output_tokens": 5}')" "$(asst b '{"input_tokens": 20, "output_tokens": 0}')" "$RESULT"
  [ "$status" -eq 0 ]; [ "$output" = "2 40 0" ]
  # the budget is crossed at the second turn
  pe "$P1" 30 "$INIT" "$(asst a '{"input_tokens": 10, "output_tokens": 5}')" "$(asst b '{"input_tokens": 20, "output_tokens": 0}')" "$RESULT"
  [ "$output" = "2 40 2" ]
  # an empty stream (the CLI has not written yet) prices to zero
  : > "$T/empty.jsonl"
  run price_events "$T/empty.jsonl" "$P1" 10
  [ "$status" -eq 0 ]; [ "$output" = "0 0 0" ]
}

@test "SE-8 price_events: an unparseable line inside the stream → ERR; a partial last line still being written is skipped" {
  printf '%s\n' "$INIT" 'not json at all' "$(asst a '{"input_tokens": 10, "output_tokens": 5}')" > "$T/bad.jsonl"
  run price_events "$T/bad.jsonl" "$P1" 100
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  [[ "$output" == *"line 2"* ]]
  { printf '%s\n' "$INIT" "$(asst a '{"input_tokens": 10, "output_tokens": 5}')"; printf '{"type":"assistant","message":{"id":"b","us'; } > "$T/tail.jsonl"
  run price_events "$T/tail.jsonl" "$P1" 1000
  [ "$status" -eq 0 ]; [ "$output" = "1 20 0" ]
}

@test "SE-9 price_events: an invalid token count (negative, fractional, string, boolean, NaN, an object, none at all) → ERR (each)" {
  local u
  for u in '{"input_tokens": -1, "output_tokens": 5}' '{"input_tokens": 1.5, "output_tokens": 5}' \
           '{"input_tokens": 1, "output_tokens": "5"}' '{"input_tokens": 1, "output_tokens": true}' \
           '{"input_tokens": 1, "output_tokens": 5, "cache_read_input_tokens": NaN}' \
           '{"input_tokens": 1, "output_tokens": 5, "cache_creation_input_tokens": {"n": 1}}' \
           '{"service_tier": "standard"}' '"usage"'; do
    printf '%s\n' "$INIT" "{\"type\":\"assistant\",\"message\":{\"id\":\"a\",\"usage\":$u}}" "$RESULT" > "$T/u.jsonl"
    run price_events "$T/u.jsonl" "$P1" 100
    echo "$u → $status $output"
    [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  done
  # an absent or null cache counter is zero (the Messages API sent null for "no cache activity")
  pe "$P1" 1000 "$(asst a '{"input_tokens": 10, "output_tokens": 5, "cache_read_input_tokens": null}')" "$RESULT"
  [ "$status" -eq 0 ]; [ "$output" = "1 20 0" ]
}

@test "SE-10 price_events: a completed assistant turn without a usage event → ERR (metering incomplete); the turn in flight is not yet completed" {
  pe "$P1" 1000 "$INIT" "$(asst a none)" "$(asst b '{"input_tokens": 10, "output_tokens": 5}')"
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  [[ "$output" == *"turn a has no usage"* ]]
  # followed by the result event: completed
  pe "$P1" 1000 "$INIT" "$(asst a '{"input_tokens": 10, "output_tokens": 5}')" "$(asst b none)" "$RESULT"
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  # followed by a tool result: completed
  pe "$P1" 1000 "$(asst a none)" '{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}'
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  # the last event of a live stream: in flight, priced as zero so far
  pe "$P1" 1000 "$INIT" "$(asst a '{"input_tokens": 10, "output_tokens": 5}')" "$(asst b none)"
  [ "$status" -eq 0 ]; [ "$output" = "1 20 0" ]
}

@test "SE-11 price_events: streaming — repeated snapshots of one message id price once (the largest count per field, never summed); stream_event deltas attach to their message" {
  pe "$P1" 100000 "$(asst a '{"input_tokens": 10, "output_tokens": 1}')" "$(asst a '{"input_tokens": 10, "output_tokens": 5}')" \
     "$(asst a '{"input_tokens": 10, "output_tokens": 5}')" "$RESULT"
  [ "$status" -eq 0 ]; [ "$output" = "1 20 0" ]
  pe "$P1" 100000 '{"type":"stream_event","event":{"type":"message_start","message":{"id":"s","usage":{"input_tokens":10,"output_tokens":1}}}}' \
     '{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"x"}}}' \
     '{"type":"stream_event","event":{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":40}}}' \
     "$(asst s '{"input_tokens": 10, "output_tokens": 1}')" "$RESULT"
  [ "$status" -eq 0 ]; [ "$output" = "1 90 0" ]
  # a delta with no open message cannot be attributed
  pe "$P1" 100000 '{"type":"stream_event","event":{"type":"message_delta","usage":{"output_tokens":40}}}' "$RESULT"
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
}

@test "SE-12 price_events: cached-read and cache-write tokens are priced by their own rates" {
  pe "$P1" 100000000 "$(asst a '{"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 0}')" "$RESULT"
  [ "$output" = "1 100 0" ]
  pe "$P1" 100000000 "$(asst a '{"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 1000}')" "$RESULT"
  [ "$output" = "1 1250 0" ]
}

@test "SE-13 price_events: an interrupted turn (no result event) is priced on the usage received" {
  pe "$P1" 100000 "$INIT" "$(asst a '{"input_tokens": 10, "output_tokens": 5}')" "$(asst b '{"input_tokens": 100, "output_tokens": 50}')"
  [ "$status" -eq 0 ]; [ "$output" = "2 220 0" ]
}

@test "SE-14 price_events: a refusal rerun is priced as a second attempt (the refused turn and the rerun both count)" {
  pe "$P1" 100000 "$INIT" "$(asst r '{"input_tokens": 10, "output_tokens": 5}' refusal)" \
     '{"type":"system","subtype":"model_refusal_fallback","original_model":"m","fallback_model":"f"}' \
     "$(asst f1 '{"input_tokens": 10, "output_tokens": 5}')" "$RESULT"
  [ "$status" -eq 0 ]; [ "$output" = "2 40 0" ]
}

@test "SE-15 price_events: the prices argument is checked too — ERR, null or a negative price → ERR; a bad budget or a missing file → ERR" {
  printf '%s\n' "$(asst a '{"input_tokens": 1, "output_tokens": 1}')" > "$T/a.jsonl"
  local p
  for p in ERR null '{"in":1,"out":1,"cr":1}' '{"in":-1,"out":1,"cr":1,"cc":1}' '{"in":1,"out":1,"cr":1,"cc":"1"}'; do
    run price_events "$T/a.jsonl" "$p" 100
    echo "$p → $status $output"
    [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  done
  run price_events "$T/a.jsonl" "$P1" not-a-number
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
  run price_events "$T/missing.jsonl" "$P1" 100
  [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
}

@test "SE-16 unmetered_tail: an attempt that started (init, thinking, a usage-less turn) with no usage event is unmetered; an empty stream and a metered one are not" {
  printf '%s\n' "$INIT" > "$T/i.jsonl"
  run unmetered_tail "$T/i.jsonl"; [ "$status" -eq 0 ]; [ "$output" = true ]
  printf '%s\n' "$INIT" '{"type":"system","subtype":"thinking_tokens","estimated_tokens":50}' "$(asst a none)" > "$T/t.jsonl"
  run unmetered_tail "$T/t.jsonl"; [ "$status" -eq 0 ]; [ "$output" = true ]
  : > "$T/e.jsonl"
  run unmetered_tail "$T/e.jsonl"; [ "$status" -eq 0 ]; [ "$output" = false ]
  printf '%s\n' "$INIT" "$(asst a '{"input_tokens": 1, "output_tokens": 1}')" > "$T/m.jsonl"
  run unmetered_tail "$T/m.jsonl"; [ "$status" -eq 0 ]; [ "$output" = false ]
  printf 'garbage\n%s\n' "$INIT" > "$T/g.jsonl"
  run unmetered_tail "$T/g.jsonl"; [ "$status" -ne 0 ]; [ "${lines[-1]}" = ERR ]
}

# --- ENV_SHIM: descriptors ------------------------------------------------------------------------------------

# fdprobe.py <shim> <fd> <soft|-> <keep-csv|-> — open <fd> (inheritable), optionally lower the soft RLIMIT_NOFILE
# in the child, run the shim (no environment key kept) around `ls /proc/self/fd`, print the child's descriptors
fdprobe_script() {
  cat > "$T/fdprobe.py" <<'PY'
import os, resource, subprocess, sys
shim, fd, soft, keep = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
src = os.open("/dev/null", os.O_RDONLY)
os.dup2(src, fd, inheritable=True)
fds = [fd]
if keep != "-":
    for k in keep.split(","):
        os.dup2(src, int(k), inheritable=True); fds.append(int(k))
env = dict(os.environ)
if keep != "-":
    env["LOA_KEEP_FDS"] = keep
def pre():
    if soft != "-":
        resource.setrlimit(resource.RLIMIT_NOFILE, (int(soft), resource.getrlimit(resource.RLIMIT_NOFILE)[1]))
r = subprocess.run([sys.executable, "-I", "-c", shim, "", "ls", "/proc/self/fd"], pass_fds=fds, preexec_fn=pre,
                   env=env, capture_output=True, text=True)
sys.stdout.write(r.stdout); sys.stderr.write(r.stderr); sys.exit(r.returncode)
PY
}

@test "SE-17 ENV_SHIM keeps exactly the named environment keys" {
  run env FOO=1 BAR=2 python3 -I -c "$ENV_SHIM" FOO,NOPE /usr/bin/env
  [ "$status" -eq 0 ]
  [ "$output" = "FOO=1" ]
}

@test "SE-18 ENV_SHIM closes an inherited descriptor above a lowered soft limit (enumerated from /proc/self/fd)" {
  [[ -d /proc/self/fd ]] || skip "no /proc on this host"
  fdprobe_script
  local hard; hard="$(ulimit -Hn)"
  [[ "$hard" == unlimited || "$hard" -gt 3001 ]] || skip "hard RLIMIT_NOFILE $hard"
  run python3 -I "$T/fdprobe.py" "$ENV_SHIM" 3000 1024 -
  echo "$output"
  [ "$status" -eq 0 ]
  ! grep -qx 3000 <<<"$output"
  # the control: without the shim the descriptor reaches the child
  run python3 -I "$T/fdprobe.py" 'import os, sys; os.execvp(sys.argv[2], sys.argv[2:])' 3000 1024 -
  grep -qx 3000 <<<"$output"
}

@test "SE-19 ENV_SHIM: LOA_KEEP_FDS keeps a named descriptor and closes the rest; a malformed list refuses (exit 2)" {
  [[ -d /proc/self/fd ]] || skip "no /proc on this host"
  fdprobe_script
  run python3 -I "$T/fdprobe.py" "$ENV_SHIM" 8 - 9
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qx 9 <<<"$output"
  ! grep -qx 8 <<<"$output"
  run env LOA_KEEP_FDS='9;rm' python3 -I -c "$ENV_SHIM" "" /bin/true
  [ "$status" -eq 2 ]
  [[ "$output" == *"LOA_KEEP_FDS"* ]]
}

@test "SE-20 ENV_SHIM closes an inherited descriptor above 65535 in a subprocess (native when the hard limit allows, else in a container)" {
  fdprobe_script
  local hard; hard="$(ulimit -Hn)"
  if [[ "$hard" == unlimited || "$hard" -gt 70001 ]] && [[ -d /proc/self/fd ]]; then
    run python3 -I -c 'import resource; h = resource.getrlimit(resource.RLIMIT_NOFILE)[1]; resource.setrlimit(resource.RLIMIT_NOFILE, (h if h != resource.RLIM_INFINITY else 1048576, h))
import os, sys; os.execvp(sys.executable, [sys.executable, "-I"] + sys.argv[1:])' "$T/fdprobe.py" "$ENV_SHIM" 70000 - -
  else
    local img="${LOA_TEST_FD_IMAGE:-loa-ablation:258}"
    command -v docker >/dev/null 2>&1 && docker image inspect "$img" >/dev/null 2>&1 \
      || skip "hard RLIMIT_NOFILE $hard on this host and no docker image $img (SE-22 covers the logic simulated)"
    chmod 0755 "$T"; chmod 0644 "$T/fdprobe.py"
    run docker run --rm --network none --ulimit nofile=200000:200000 -v "$T:/t:ro" "$img" \
      python3 -I /t/fdprobe.py "$ENV_SHIM" 70000 - -
  fi
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qx 0 <<<"$output"
  ! grep -qx 70000 <<<"$output"
}

@test "SE-21 ENV_SHIM fallbacks (simulated): no /proc → closerange(3, hard limit); an infinite or unusable hard limit → 1048576; kept descriptors survive the fallback" {
  cat > "$T/sim.py" <<'PY'
import os, resource, sys
shim, mode = sys.argv[1], sys.argv[2]
calls = []
real_open = os.open
def fake_open(path, *a, **k):
    if path == "/proc/self/fd":
        raise FileNotFoundError(path)
    return real_open(path, *a, **k)
os.open = fake_open
os.closerange = lambda lo, hi: calls.append((lo, hi))
os.close = lambda fd: calls.append(("close", fd))
if mode == "inf":
    resource.getrlimit = lambda r: (1024, resource.RLIM_INFINITY)
elif mode == "bad":
    resource.getrlimit = lambda r: (1024, 2)
elif mode == "raise":
    def boom(r): raise OSError("no rlimit")
    resource.getrlimit = boom
else:
    resource.getrlimit = lambda r: (1024, 4096)
os.execvpe = lambda f, a, e: (print(calls), sys.exit(0))
sys.argv = ["-c", "", "/bin/true"]
exec(compile(shim, "ENV_SHIM", "exec"))
PY
  run python3 -I "$T/sim.py" "$ENV_SHIM" finite;  [ "$output" = "[(3, 4096)]" ]
  run python3 -I "$T/sim.py" "$ENV_SHIM" inf;     [ "$output" = "[(3, 1048576)]" ]
  run python3 -I "$T/sim.py" "$ENV_SHIM" bad;     [ "$output" = "[(3, 1048576)]" ]
  run python3 -I "$T/sim.py" "$ENV_SHIM" raise;   [ "$output" = "[(3, 1048576)]" ]
  run env LOA_KEEP_FDS=7,5 python3 -I "$T/sim.py" "$ENV_SHIM" finite
  [ "$output" = "[(3, 5), (6, 7), (8, 4096)]" ]
}

@test "SE-22 ENV_SHIM (simulated /proc listing): every listed descriptor above 2 is closed except the listing handle and LOA_KEEP_FDS, 70000 included" {
  cat > "$T/sim2.py" <<'PY'
import os, sys
shim = sys.argv[1]
calls = []
os.open = lambda path, *a, **k: 99
os.listdir = lambda d: ["0", "1", "2", "3", "99", "255", "70000", "5"]
os.close = lambda fd: calls.append(fd)
os.closerange = lambda lo, hi: calls.append(("range", lo, hi))
os.execvpe = lambda f, a, e: (print(sorted(c for c in calls if c != 99), 99 in calls), sys.exit(0))
sys.argv = ["-c", "", "/bin/true"]
exec(compile(shim, "ENV_SHIM", "exec"))
PY
  run env LOA_KEEP_FDS=5 python3 -I "$T/sim2.py" "$ENV_SHIM"
  echo "$output"
  [ "$output" = "[3, 255, 70000] True" ]
}

# --- the secrecy assertion ------------------------------------------------------------------------------------

@test "SE-23 SECRET_KEY_PATTERN unit vector: key-shaped names match, route and model names do not" {
  [ "$SECRET_KEY_PATTERN" = '(KEY|TOKEN|SECRET|PASSWORD|PASS|CREDENTIAL|AUTH)' ]
  local k
  for k in AWS_BEARER_TOKEN_BEDROCK OPENAI_API_KEY AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN DB_PASSWORD SMTP_PASS \
           GOOGLE_APPLICATION_CREDENTIALS GH_AUTH anthropic_api_key; do
    [[ "$(printf '%s' "$k" | tr 'a-z' 'A-Z')" =~ $SECRET_KEY_PATTERN ]] || { echo "no match: $k"; return 1; }
  done
  for k in AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE ANTHROPIC_BEDROCK_REGION_PREFIX ANTHROPIC_DEFAULT_OPUS_MODEL \
           ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL CLAUDE_CODE_USE_BEDROCK; do
    ! [[ "$k" =~ $SECRET_KEY_PATTERN ]] || { echo "match: $k"; return 1; }
  done
}

@test "SE-24 assert_secret_keys: the shipped lists pass; a key-shaped PASS_KEYS entry absent from SECRET_KEYS fails; SECRET_KEYS or NON_SECRET_ALLOWLIST clears it" {
  run assert_secret_keys
  [ "$status" -eq 0 ]
  PASS_KEYS="$PASS_KEYS OPENAI_API_KEY"
  run assert_secret_keys
  [ "$status" -ne 0 ]
  [[ "$output" == *"OPENAI_API_KEY"* ]]
  SECRET_KEYS="$SECRET_KEYS OPENAI_API_KEY "
  run assert_secret_keys
  [ "$status" -eq 0 ]
  PASS_KEYS="$PASS_KEYS session_token"
  run assert_secret_keys
  [ "$status" -ne 0 ]; [[ "$output" == *"session_token"* ]]
  NON_SECRET_ALLOWLIST=" session_token "
  run assert_secret_keys
  [ "$status" -eq 0 ]
}

# --- the lint walk --------------------------------------------------------------------------------------------

@test "SE-25 check-no-swallowed-jq.sh default mode walks evals/harness/lib/ (a planted swallow there is caught) and is green on this repo" {
  mkdir -p "$T/repo/evals/harness/lib"
  printf '#!/usr/bin/env bash\nj="$(jq -c . <<<"$x" 2>/dev/null || echo null)"\n' > "$T/repo/evals/harness/lib/bad.sh"
  run bash -c "cd '$T/repo' && bash '$REPO_ROOT/tools/check-no-swallowed-jq.sh'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"evals/harness/lib/bad.sh:2"* ]]
  run bash -c "cd '$REPO_ROOT' && bash tools/check-no-swallowed-jq.sh"
  echo "$output"
  [ "$status" -eq 0 ]
}
