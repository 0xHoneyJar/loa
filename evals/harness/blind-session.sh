#!/usr/bin/env bash
# =============================================================================
# blind-session.sh — run ONE blind labelling role (annotator A, annotator B, the judge) as a
# `claude -p` session over a sandbox that holds only the role's packet files
# (cycle-132 Task 1.4; SDD §1.4 "Blind session runner", §5.2; D-7.1; PRD FR-2, FR-4)
#
# Usage:
#   blind-session.sh --packets DIR --prompt FILE --model ID --out DIR
#                    [--image loa-ablation:258] [--max-usd 6] [--executor container|host]
#                    [--claude-bin B] [--docker-bin D] [--max-turns 120] [--timeout-min 60]
#
# Options:
#   --packets DIR      the role's packet files: regular files directly in DIR (no symlink, no
#                      sub-directory, names [A-Za-z0-9][A-Za-z0-9._-]*, none named labels.json),
#                      at most 64 files and 20 MiB; they are copied into a fresh sandbox
#   --prompt FILE      the role's prompt (sent as the -p argument). `{{LABELS_PATH}}` in it is
#                      replaced by the label file's path in the session; a prompt without the
#                      placeholder gets one closing line naming that path
#   --model ID         the session model (global.anthropic.claude-opus-5-5 for the roles)
#   --out DIR          output directory (must not exist, or be empty)
#   --image IMG        container image (default loa-ablation:258)
#   --max-usd USD      the session cap (default 6): the stream is re-priced every
#                      $LOA_EVAL_WATCHDOG_POLL_S seconds (default 1) and the session is stopped
#                      when the estimate reaches the cap (cost.json cap_hit, exit 1)
#   --executor MODE    container (default; $LOA_EVAL_EXECUTOR) or host. host runs the CLI on this
#                      machine without isolation and is refused (exit 2) unless
#                      LOA_EVAL_ALLOW_HOST_SESSION=1 (tests use the stub CLI this way)
#   --claude-bin B     host-mode CLI (default $EVAL_CLAUDE_BIN, else claude); in the container
#                      the CLI is $LOA_EVAL_CONTAINER_CLAUDE_BIN (default claude)
#   --docker-bin D     docker CLI (default $EVAL_DOCKER_BIN, else docker)
#   --max-turns N      the CLI's --max-turns (default 120)
#   --timeout-min M    the session deadline (default 60; timeout --signal=TERM --kill-after=15)
#
# Session: `claude -p <prompt> --output-format stream-json --verbose --model <id>
# --permission-mode bypassPermissions --dangerously-skip-permissions --setting-sources ""
# --tools Read,Grep,Glob,Write --max-turns <n>`, cwd the sandbox, with exactly this environment
# (the BARE phase's allowlist, pipeline-run.sh): PATH HOME LANG LC_ALL TERM TMPDIR
# CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_SUBAGENT_MODEL LOA_MODELINV_LOG_PATH LOA_COST_LEDGER_PATH
# GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GH_CONFIG_DIR, plus the Bedrock pass-through
# keys when set (AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_BEARER_TOKEN_BEDROCK
# ANTHROPIC_BEDROCK_REGION_PREFIX ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL). The python3 -I exec
# shim of lib/session-exec.sh keeps exactly those keys and closes every descriptor above 2;
# AWS_BEARER_TOKEN_BEDROCK travels by name only and is recorded as "<set>". No Bash, no web tool,
# no Task: the model API is the only egress the session needs.
# Container mode runs the same command inside
#   docker run --rm --name <n> --user <uid>:<gid> --network bridge --read-only
#     --tmpfs /tmp:rw,size=1g --pids-limit 512 --memory 4g --cpus 2
#     -v <sandbox>:/workspace:rw -v <home>:/home/evaluser:rw -w /workspace -e … <image> …
# Exactly two mounts and no repository mount. The per-session HOME (mode 0700, both modes) holds
# an empty .claude/ and .aws/, .claude.json (the sandbox pre-trusted) and .eval/ (the cost ledger,
# outside the sandbox); no credential file is copied — the Bedrock route authenticates from the
# environment and a blind role has no use for the codex CLI. The sandbox and the HOME live in one
# mktemp directory that is deleted at exit, on every path.
#
# Outputs (--out; no timestamps; host paths appear only as <sandbox> / <home>):
#   labels.json      the sandbox's labels.json (a regular file, ≤ 2 MiB, a JSON object), when written
#   transcript.jsonl the stream-json transcript (the access log); stderr.log the CLI's stderr
#   cost.json        {result_cost_usd, ledger_rows, ledger_cost_usd, total_cost_usd, num_turns,
#                     subtype, is_error, cap_usd, cap_hit, cap_turn, estimate_usd, watchdog,
#                     timed_out, cli_exit, model}; cost-ledger.jsonl when the ledger has rows
#   taint.json       {tainted, events: [{event, tool, reason, input}], allowed_tools, sandbox}:
#                    a tool_use of any tool outside Read/Grep/Glob/Write, or a Read/Grep/Glob/Write
#                    path (file_path, path, an absolute or `..` pattern/glob) outside the sandbox
#                    after normalisation, taints the role (the lead reruns it)
#   session.json     model, executor, image, image_id, tools, caps, packets, argv (the prompt as
#                    <prompt.md>), env (secrets <set>), status, label_status, exit
#   prompt.md        the prompt as sent; sandbox.sha256 the packet files as copied
#
# Exit: 0 labels written; 1 session failed (CLI error, timeout, cap, interrupted, no or an
#       invalid labels.json); 2 usage (bad option, packet rule, missing CLI / docker / image);
#       3 tainted (takes precedence over 1).
# Tested by evals/tests/blind-session.bats (stub claude, stub docker).
# =============================================================================
set -euo pipefail
export LC_ALL=C
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: '&' in ${x//p/r} stays literal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PACKETS="" PROMPT="" MODEL="" OUT="" IMAGE="loa-ablation:258" MAX_USD="6"
EXECUTOR="${LOA_EVAL_EXECUTOR:-container}" CLAUDE_BIN="${EVAL_CLAUDE_BIN:-claude}" DOCKER_BIN="${EVAL_DOCKER_BIN:-docker}"
MAX_TURNS=120 TIMEOUT_MIN=60
TOOLS="Read,Grep,Glob,Write"
LABEL_NAME="labels.json"

die_usage() { echo "blind-session.sh: $*" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --packets)     PACKETS="${2:-}"; shift 2 ;;
    --prompt)      PROMPT="${2:-}"; shift 2 ;;
    --model)       MODEL="${2:-}"; shift 2 ;;
    --out)         OUT="${2:-}"; shift 2 ;;
    --image)       IMAGE="${2:-}"; shift 2 ;;
    --max-usd)     MAX_USD="${2:-}"; shift 2 ;;
    --executor)    EXECUTOR="${2:-}"; shift 2 ;;
    --claude-bin)  CLAUDE_BIN="${2:-}"; shift 2 ;;
    --docker-bin)  DOCKER_BIN="${2:-}"; shift 2 ;;
    --max-turns)   MAX_TURNS="${2:-}"; shift 2 ;;
    --timeout-min) TIMEOUT_MIN="${2:-}"; shift 2 ;;
    -h|--help)     sed -n '2,/^# =====/p' "$0" | sed '$d'; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

[[ -n "$PACKETS" ]] || die_usage "missing --packets"
[[ -n "$PROMPT" ]] || die_usage "missing --prompt"
[[ -n "$MODEL" ]] || die_usage "missing --model"
[[ -n "$OUT" ]] || die_usage "missing --out"
[[ "$MODEL" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || die_usage "--model is not a model id: $MODEL"
{ [[ "$MAX_USD" =~ ^[0-9]+([.][0-9]+)?$ ]] && jq -en --arg c "$MAX_USD" '($c | tonumber) > 0' >/dev/null; } \
  || die_usage "--max-usd must be a positive number"
[[ "$MAX_TURNS" =~ ^[1-9][0-9]{0,3}$ ]] || die_usage "--max-turns must be an integer 1-9999"
[[ "$TIMEOUT_MIN" =~ ^[1-9][0-9]{0,2}$ ]] || die_usage "--timeout-min must be an integer 1-999"
case "$EXECUTOR" in
  container) ;;
  host) [[ "${LOA_EVAL_ALLOW_HOST_SESSION:-}" == 1 ]] || die_usage "--executor host runs the CLI without isolation: set LOA_EVAL_ALLOW_HOST_SESSION=1 to allow it" ;;
  *) die_usage "--executor must be container or host" ;;
esac
for t in jq python3 timeout; do command -v "$t" >/dev/null 2>&1 || die_usage "required tool missing: $t"; done
[[ -d "$PACKETS" && ! -L "$PACKETS" ]] || die_usage "--packets is not a directory: $PACKETS"
[[ -f "$PROMPT" && ! -L "$PROMPT" && -s "$PROMPT" ]] || die_usage "--prompt is not a non-empty regular file: $PROMPT"
[[ "$(wc -c < "$PROMPT" | tr -d ' ')" -le 262144 ]] || die_usage "--prompt is larger than 256 KiB"
if [[ -e "$OUT" || -L "$OUT" ]]; then
  [[ -d "$OUT" && ! -L "$OUT" && -z "$(ls -A "$OUT")" ]] || die_usage "--out exists and is not an empty directory: $OUT"
fi

# the packet rule: regular files directly in DIR, safe names, no labels.json, bounded
PACKET_LIST="$(python3 -I - "$PACKETS" "$LABEL_NAME" <<'PY'
import os, re, stat, sys
d, label = sys.argv[1], sys.argv[2]
names, total = sorted(os.listdir(d)), 0
if not names:
    sys.exit("the packet directory is empty")
if len(names) > 64:
    sys.exit(f"{len(names)} packet files (at most 64)")
for n in names:
    st = os.lstat(os.path.join(d, n))
    if not stat.S_ISREG(st.st_mode):
        sys.exit(f"packet {n!r} is not a regular file (no symlink or sub-directory)")
    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]*$", n):
        sys.exit(f"packet name {n!r} is not [A-Za-z0-9][A-Za-z0-9._-]*")
    if n == label:
        sys.exit(f"a packet may not be named {label} (the role's output)")
    total += st.st_size
if total > 20 * 1024 * 1024:
    sys.exit("the packets exceed 20 MiB")
print("\n".join(names))
PY
)" || die_usage "packet rule: see above"

if [[ "$EXECUTOR" == host ]]; then
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || [[ -x "$CLAUDE_BIN" ]] || die_usage "claude CLI not found: $CLAUDE_BIN"
  IMAGE_ID=null
else
  command -v "$DOCKER_BIN" >/dev/null 2>&1 || [[ -x "$DOCKER_BIN" ]] || die_usage "docker CLI not found: $DOCKER_BIN"
  IMAGE_ID="$("$DOCKER_BIN" image inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}{{.Id}}{{end}}' "$IMAGE" 2>/dev/null || true)"
  [[ -n "$IMAGE_ID" ]] || die_usage "container image not found: $IMAGE"
fi

# --- shared session mechanics (eval.yml trust boundary: a literal relative path) -------------
[[ -f "$SCRIPT_DIR/lib/session-exec.sh" ]] || die_usage "session library not found: $SCRIPT_DIR/lib/session-exec.sh"
pushd "$SCRIPT_DIR" >/dev/null
# shellcheck source=lib/session-exec.sh
source ./lib/session-exec.sh
popd >/dev/null

# --- the session directory (sandbox + HOME), deleted on every exit ---------------------------
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
SESS="$(mktemp -d "${TMPDIR:-/tmp}/blind-session.XXXXXX")"
SESS="$(cd "$SESS" && pwd -P)"   # the physical path: the taint check compares normalised paths against it
WS="$SESS/workspace"; HOME_DIR="$SESS/home"
CUR_PID="" CUR_CONTAINER="" INTERRUPTED=0
remove_tree() {  # remove_tree <dir> — permission-tolerant delete
  [[ -e "$1" ]] || return 0
  chmod -R u+rwx "$1" 2>/dev/null || true
  find "$1" -depth -delete 2>/dev/null || true
}
kill_session() {
  if [[ -n "$CUR_CONTAINER" ]]; then "$DOCKER_BIN" kill --signal TERM "$CUR_CONTAINER" >/dev/null 2>&1 || true; fi
  if [[ -n "$CUR_PID" ]]; then kill -TERM "$CUR_PID" 2>/dev/null || true; fi
}
on_exit() { kill_session; remove_tree "$SESS"; }
on_signal() { INTERRUPTED=1; kill_session; }
trap on_exit EXIT
trap on_signal TERM INT HUP

mkdir -p "$WS" "$HOME_DIR/.claude" "$HOME_DIR/.aws" "$HOME_DIR/.eval/gh-empty" "$SESS/tmp"
while IFS= read -r p; do cp "$PACKETS/$p" "$WS/$p"; chmod 0644 "$WS/$p"; done <<<"$PACKET_LIST"
python3 -I - "$WS" "$OUT/sandbox.sha256" <<'PY'
import hashlib, os, sys
ws, out = sys.argv[1], sys.argv[2]
with open(out, "w", encoding="utf-8") as f:
    for n in sorted(os.listdir(ws)):
        f.write(hashlib.sha256(open(os.path.join(ws, n), "rb").read()).hexdigest() + "  " + n + "\n")
PY
: > "$HOME_DIR/.eval/cost-ledger.jsonl"; : > "$HOME_DIR/.eval/model-invoke.jsonl"

ev_ws="$WS" home_v="$HOME_DIR" path_v="$PATH" tmp_v="$SESS/tmp"
if [[ "$EXECUTOR" == container ]]; then
  ev_ws="/workspace" home_v="/home/evaluser" path_v="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" tmp_v="/tmp"
fi
jq -n --arg ws "$ev_ws" '{projects: {($ws): {hasTrustDialogAccepted: true}}}' > "$HOME_DIR/.claude.json"
chmod 0700 "$SESS" "$HOME_DIR" "$HOME_DIR/.claude" "$HOME_DIR/.aws" "$HOME_DIR/.eval"

# --- the prompt ------------------------------------------------------------------------------
LABELS_PATH="$ev_ws/$LABEL_NAME"
PROMPT_TEXT="$(cat "$PROMPT")"
if [[ "$PROMPT_TEXT" == *"{{LABELS_PATH}}"* ]]; then
  PROMPT_TEXT="${PROMPT_TEXT//\{\{LABELS_PATH\}\}/$LABELS_PATH}"
else
  PROMPT_TEXT="$PROMPT_TEXT"$'\n\n'"Write your label file, as JSON, to $LABELS_PATH. It is the only file you write."
fi
# the record of the prompt names the host sandbox as <sandbox> (outputs carry no absolute host path)
if [[ "$EXECUTOR" == host ]]; then printf '%s\n' "${PROMPT_TEXT//$WS/<sandbox>}" > "$OUT/prompt.md"
else printf '%s\n' "$PROMPT_TEXT" > "$OUT/prompt.md"; fi

# --- the launcher ----------------------------------------------------------------------------
cbin="$CLAUDE_BIN"; [[ "$EXECUTOR" == container ]] && cbin="${LOA_EVAL_CONTAINER_CLAUDE_BIN:-claude}"
TSEC=$(( TIMEOUT_MIN * 60 ))
cargv=("$cbin" -p "$PROMPT_TEXT" --output-format stream-json --verbose --model "$MODEL"
       --permission-mode bypassPermissions --dangerously-skip-permissions --setting-sources ""
       --tools "$TOOLS" --max-turns "$MAX_TURNS")
envkv=("PATH=$path_v" "HOME=$home_v" "LANG=${LANG:-C.UTF-8}" "LC_ALL=$LC_ALL" "TERM=${TERM:-dumb}"
       "TMPDIR=$tmp_v" "CLAUDE_CODE_USE_BEDROCK=${CLAUDE_CODE_USE_BEDROCK:-1}")
for pk in $PASS_KEYS; do
  if [[ -n "${!pk:-}" ]]; then envkv+=("$pk=${!pk}"); fi
done
envkv+=("CLAUDE_CODE_SUBAGENT_MODEL=$MODEL"
        "LOA_MODELINV_LOG_PATH=$home_v/.eval/model-invoke.jsonl"
        "LOA_COST_LEDGER_PATH=$home_v/.eval/cost-ledger.jsonl"
        "GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1" "GH_CONFIG_DIR=$home_v/.eval/gh-empty")
keys=""
for kv in "${envkv[@]}"; do keys="$keys${keys:+,}${kv%%=*}"; done
if [[ "$EXECUTOR" == container ]]; then
  # one session per --out (it must be empty), so the out path names the container: unique and reproducible
  CUR_NAME="loa-blind-$(basename "$OUT" | tr -c 'A-Za-z0-9_.-' '-' | cut -c1-80)-$(printf '%s' "$OUT" | python3 -I -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:10])')"
  hostkeys="PATH,HOME,DOCKER_HOST,DOCKER_CONFIG,XDG_RUNTIME_DIR"
  for k in $SECRET_KEYS; do if [[ -n "${!k:-}" ]]; then hostkeys="$hostkeys,$k"; fi; done
  full=(python3 -I -c "$ENV_SHIM" "$hostkeys"
        "$DOCKER_BIN" run --rm --name "$CUR_NAME" --user "$(id -u):$(id -g)"
        --network bridge --read-only --tmpfs /tmp:rw,size=1g
        --pids-limit 512 --memory 4g --cpus 2
        -v "$WS:/workspace:rw"
        -v "$HOME_DIR:/home/evaluser:rw"
        -w /workspace)
  for kv in "${envkv[@]}"; do
    k="${kv%%=*}"
    if [[ "$SECRET_KEYS" == *" $k "* ]]; then full+=(-e "$k"); else full+=(-e "$kv"); fi
  done
  full+=("$IMAGE" python3 -I -c "$ENV_SHIM" "$keys" timeout --signal=TERM --kill-after=15 "$TSEC" "${cargv[@]}")
else
  CUR_NAME=""
  full=(python3 -I -c "$ENV_SHIM" "$keys" timeout --signal=TERM --kill-after=15 "$TSEC" "${cargv[@]}")
fi

EVENTS="$OUT/transcript.jsonl" ERRF="$OUT/stderr.log"
CAP_MICRO="$(jq -n --arg c "$MAX_USD" '($c|tonumber) * 1000000 | round')"
prices="$(price_for "$MODEL")"
rc=0 cap_hit=false cap_turn=0 est="0 0 0" start_s="$(date +%s)"
( cd "$WS" || exit 2
  if [[ "$EXECUTOR" == host ]]; then for kv in "${envkv[@]}"; do export "$kv"; done; fi
  exec "${full[@]}" ) < /dev/null > "$EVENTS" 2> "$ERRF" &
CUR_PID=$! CUR_CONTAINER="$CUR_NAME"
poll="${LOA_EVAL_WATCHDOG_POLL_S:-1}"
while kill -0 "$CUR_PID" 2>/dev/null; do
  sleep "$poll" || true
  [[ "$INTERRUPTED" -eq 1 ]] && break
  if [[ "$prices" != null ]]; then
    est="$(price_events "$EVENTS" "$prices" "$CAP_MICRO")"
    if [[ "${est##* }" -gt 0 ]]; then
      cap_hit=true; cap_turn="${est##* }"
      echo "blind-session.sh: watchdog: the estimate passes the cap (USD $MAX_USD) at turn $cap_turn; SIGTERM" >&2
      kill_session
      break
    fi
  fi
done
wait "$CUR_PID" 2>/dev/null || rc=$?
if [[ $rc -gt 128 && "$INTERRUPTED" -eq 1 ]]; then
  while kill -0 "$CUR_PID" 2>/dev/null; do sleep 0.2; done
  rc2=0; wait "$CUR_PID" 2>/dev/null || rc2=$?
  [[ $rc2 -ne 127 ]] && rc=$rc2
fi
CUR_PID="" CUR_CONTAINER=""
elapsed=$(( $(date +%s) - start_s ))
[[ "$prices" != null ]] && est="$(price_events "$EVENTS" "$prices" "$CAP_MICRO")"
timed_out=false
if [[ $rc -eq 124 ]] || { [[ $rc -eq 137 ]] && [[ $elapsed -ge $TSEC ]]; }; then timed_out=true; fi

# --- outputs ---------------------------------------------------------------------------------
if [[ -s "$HOME_DIR/.eval/cost-ledger.jsonl" ]]; then cp "$HOME_DIR/.eval/cost-ledger.jsonl" "$OUT/cost-ledger.jsonl"; fi
LABEL_STATUS="$(python3 -I - "$WS/$LABEL_NAME" "$OUT/$LABEL_NAME" <<'PY'
import json, os, stat, sys
src, dst = sys.argv[1], sys.argv[2]
try:
    st = os.lstat(src)
except OSError:
    print("missing"); sys.exit(0)
if not stat.S_ISREG(st.st_mode):
    print("not_a_regular_file"); sys.exit(0)
if st.st_size > 2 * 1024 * 1024:
    print("too_large"); sys.exit(0)
fd = os.open(src, os.O_RDONLY | os.O_NOFOLLOW)
with os.fdopen(fd, "rb") as f:
    data = f.read()
try:
    obj = json.loads(data.decode("utf-8"))
except (UnicodeDecodeError, ValueError):
    print("invalid_json"); sys.exit(0)
if not isinstance(obj, dict):
    print("not_an_object"); sys.exit(0)
with open(dst, "wb") as f:
    f.write(data)
print("ok")
PY
)"

python3 -I - "$EVENTS" "$OUT/taint.json" "$ev_ws" "$EXECUTOR" "$TOOLS" <<'PY'
import json, posixpath, sys
events, out, root, executor, tools = sys.argv[1:6]
allowed = tools.split(",")
shown_root = root if executor == "container" else "<sandbox>"

def show(v):
    """an input value with the host sandbox path replaced (no absolute host path in the output)"""
    s = json.dumps(v, sort_keys=True, ensure_ascii=False)
    if executor != "container":
        s = s.replace(json.dumps(root)[1:-1], "<sandbox>")
    return json.loads(s)

def outside(p, glob=False):
    """True when path p (absolute, or relative to the sandbox) leaves the sandbox after normalisation;
    a glob pattern counts only when it is absolute or holds a `..` component"""
    if not isinstance(p, str) or p == "":
        return False
    if glob and not (p.startswith("/") or ".." in p.split("/")):
        return False
    if p.startswith("~"):
        return True
    full = posixpath.normpath(p if p.startswith("/") else posixpath.join(root, p))
    return not (full == root or full.startswith(root.rstrip("/") + "/"))

hits = []
try:
    lines = open(events, encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    lines = []
for n, line in enumerate(lines, 1):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if not isinstance(e, dict) or e.get("type") != "assistant":
        continue
    content = (e.get("message") or {}).get("content")
    for c in content if isinstance(content, list) else []:
        if not isinstance(c, dict) or c.get("type") != "tool_use":
            continue
        name, inp = c.get("name"), c.get("input") if isinstance(c.get("input"), dict) else {}
        why = None
        if name not in allowed:
            why = "tool outside " + "/".join(allowed)
        elif name in ("Read", "Write") and outside(inp.get("file_path")):
            why = "file_path outside the sandbox"
        elif name in ("Grep", "Glob") and outside(inp.get("path")):
            why = "path outside the sandbox"
        elif name == "Glob" and outside(inp.get("pattern"), glob=True):
            why = "pattern outside the sandbox"
        elif name == "Grep" and outside(inp.get("glob"), glob=True):
            why = "glob outside the sandbox"
        elif name in ("Read", "Write") and not isinstance(inp.get("file_path"), str):
            why = "no file_path"
        if why:
            hits.append({"event": n, "tool": name, "reason": why, "input": show(inp)})
res = {"tainted": bool(hits), "events": hits, "allowed_tools": allowed, "sandbox": shown_root}
with open(out, "w", encoding="utf-8") as f:
    f.write(json.dumps(res, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
PY
TAINTED="$(jq -r '.tainted' "$OUT/taint.json")"

result="$(grep -E '^\{.*"type" *: *"result"' "$EVENTS" 2>/dev/null | sed -n '$p' || true)"
if [[ -z "$result" ]] || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$result"; then
  result='{"type":"result","subtype":"missing","is_error":true}'
fi
read -r _turns est_micro _cross <<<"$est"
ledger_json="$(jq -R -n -c '[inputs | fromjson? | select(type == "object")
      | (.cost_micro_usd // ((.cost_usd // 0) * 1000000))] | {rows: length, micro: (add // 0 | round)}' \
      < "$HOME_DIR/.eval/cost-ledger.jsonl")"
jq -n --argjson r "$result" --argjson l "$ledger_json" --arg model "$MODEL" --argjson cap "$MAX_USD" \
      --argjson cap_hit "$cap_hit" --argjson cap_turn "$cap_turn" --argjson est_micro "${est_micro:-0}" \
      --argjson watchdog "$([[ "$prices" != null ]] && echo true || echo false)" \
      --argjson timed_out "$timed_out" --argjson rc "$rc" \
  '(if ($r.total_cost_usd | type) == "number" then $r.total_cost_usd else null end) as $rc_usd
   | {model: $model, result_cost_usd: $rc_usd, ledger_rows: $l.rows, ledger_cost_usd: ($l.micro / 1000000),
      total_cost_usd: ((($rc_usd // 0) * 1000000 + $l.micro) | round / 1000000),
      num_turns: ($r.num_turns // null), subtype: ($r.subtype // null), is_error: ($r.is_error // null),
      cap_usd: $cap, cap_hit: $cap_hit, cap_turn: (if $cap_turn > 0 then $cap_turn else null end),
      estimate_usd: ($est_micro / 1000000), watchdog: $watchdog, timed_out: $timed_out, cli_exit: $rc}' \
  > "$OUT/cost.json"

subtype="$(jq -r '.subtype // ""' <<<"$result")"
status=completed exit_code=0
if [[ "$TAINTED" == true ]]; then status=tainted exit_code=3
elif [[ "$INTERRUPTED" -eq 1 ]]; then status=interrupted exit_code=1
elif [[ "$cap_hit" == true ]]; then status=cap_failure exit_code=1
elif [[ "$timed_out" == true ]]; then status=timed_out exit_code=1
elif [[ "$LABEL_STATUS" != ok ]]; then status="labels_$LABEL_STATUS" exit_code=1
elif [[ $rc -ne 0 && "$subtype" != error_max_turns ]]; then status=agent_error exit_code=1
fi

# session record: argv with the prompt as <prompt.md>, env with secrets <set>, host paths as placeholders
BS_ARGV="$(printf '%s\0' "${full[@]}" | jq -Rs -c 'split("\u0000") | .[:-1]')" \
BS_ENV="$(printf '%s\0' "${envkv[@]}" | jq -Rs -c 'split("\u0000") | .[:-1]')" \
BS_PROMPT="$PROMPT_TEXT" BS_MODEL="$MODEL" BS_EXECUTOR="$EXECUTOR" BS_IMAGE="$IMAGE" BS_IMAGE_ID="$IMAGE_ID" \
BS_TOOLS="$TOOLS" BS_MAX_TURNS="$MAX_TURNS" BS_TSEC="$TSEC" BS_MAX_USD="$MAX_USD" BS_PACKETS="$PACKET_LIST" \
BS_STATUS="$status" BS_LABEL_STATUS="$LABEL_STATUS" BS_EXIT="$exit_code" \
  python3 -I - "$OUT/session.json" "$WS" "$HOME_DIR" "$SESS" "$SECRET_KEYS" "$CUR_NAME" <<'PY'
import json, os, sys
out, ws, home, sess, secret, cname = sys.argv[1:7]
def clean(s):
    s = s.replace(ws, "<sandbox>").replace(home, "<home>").replace(sess, "<session>")
    return s.replace(cname, "<container>") if cname else s
argv = json.loads(os.environ["BS_ARGV"])
prompt = os.environ["BS_PROMPT"]
env = {}
for kv in json.loads(os.environ["BS_ENV"]):
    k, _, v = kv.partition("=")
    env[k] = "<set>" if f" {k} " in secret else clean(v)
rec = {"model": os.environ["BS_MODEL"], "executor": os.environ["BS_EXECUTOR"],
       "image": os.environ["BS_IMAGE"] if os.environ["BS_EXECUTOR"] == "container" else None,
       "image_id": json.loads(os.environ["BS_IMAGE_ID"]) if os.environ["BS_IMAGE_ID"] == "null" else os.environ["BS_IMAGE_ID"],
       "tools": os.environ["BS_TOOLS"].split(","), "max_turns": int(os.environ["BS_MAX_TURNS"]),
       "timeout_s": int(os.environ["BS_TSEC"]), "cap_usd": float(os.environ["BS_MAX_USD"]),
       "packets": os.environ["BS_PACKETS"].split("\n"),
       "argv": ["<prompt.md>" if a == prompt else clean(a) for a in argv], "env": env,
       "status": os.environ["BS_STATUS"], "label_status": os.environ["BS_LABEL_STATUS"],
       "exit": int(os.environ["BS_EXIT"])}
with open(out, "w", encoding="utf-8") as f:
    f.write(json.dumps(rec, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
PY

echo "blind-session: $status (labels $LABEL_STATUS, tainted $TAINTED, cost USD $(jq -r '.total_cost_usd' "$OUT/cost.json")) → $OUT"
exit "$exit_code"
