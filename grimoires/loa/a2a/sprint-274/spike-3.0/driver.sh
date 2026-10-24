#!/usr/bin/env bash
# spike-3.0.sh — cycle-133 Sprint 274 Task 3.0: Claude Code scope facts inside loa-ablation:259 under the egress block.
#
# Usage: spike-3.0.sh <arm> [--model M] [--max-turns N] [--timeout-s S]
#   arm: none  → --setting-sources ""            (the cycle-132 harness launch; baseline)
#        user  → --setting-sources user          (design a′: the pinned framework under the sandbox HOME)
#        both  → --setting-sources user,project  (positive control: the project canaries must load)
# Lays out a HOME (user scope) and a workspace (project scope) with a canary for every surface item (each with a
# deterministic effect: a hook writes a marker; an MCP server writes a marker when started; commands, skills, agents
# and output styles are read from the init event; CLAUDE.md-class items instruct the model to write a marker), runs
# `claude -p` with the arm's --setting-sources under process capture (1 s ps sampler) and the egress block, and
# writes everything under ~/.cache/loa/cycle-133/spike/<arm>/. Prints a one-screen summary. No framework file is
# touched. Spend: one short Sonnet turn per arm (cents); the driver aborts an arm above USD 0.70.
set -euo pipefail
export LC_ALL=C
ROOT=/home/merlin/Documents/thj/code/loa
ARM="${1:?arm: none|user|both}"; shift || true
MODEL="${ANTHROPIC_DEFAULT_SONNET_MODEL:-global.anthropic.claude-sonnet-5-5}"; MAX_TURNS=4; TSEC=420
while [[ $# -gt 0 ]]; do case "$1" in --model) MODEL="$2"; shift 2;; --max-turns) MAX_TURNS="$2"; shift 2;; --timeout-s) TSEC="$2"; shift 2;; *) echo "unknown option $1" >&2; exit 2;; esac; done
case "$ARM" in none) SRC="";; user) SRC="user";; both) SRC="user,project";; *) echo "arm must be none|user|both" >&2; exit 2;; esac
IMAGE=loa-ablation:259; PROXY_IMAGE=loa-egress-proxy:259; BATCH="spike$(date -u +%H%M%S)"
OUT=~/.cache/loa/cycle-133/spike/$ARM; rm -rf "$OUT"; mkdir -p "$OUT"
S="$(mktemp -d "${TMPDIR:-/tmp}/spike30.XXXXXX")"; WS="$S/workspace"; HOME_DIR="$S/home"
cleanup() { bash "$ROOT/evals/harness/lib/egress-proxy.sh" down "$BATCH" --log-dir "$OUT/egress" >/dev/null 2>&1 || true; chmod -R u+rwx "$S" 2>/dev/null || true; find "$S" -depth -delete 2>/dev/null || true; }
trap cleanup EXIT

# ---- the lib's ENV_SHIM and PASS_KEYS (the one copy) -------------------------------------------------------------
# shellcheck disable=SC1091
source "$ROOT/evals/harness/lib/session-exec.sh"

# ---- layout: user scope ---------------------------------------------------------------------------------------------
mkdir -p "$HOME_DIR/.claude/"{commands,agents,skills/userskill,hooks} "$HOME_DIR/.aws" "$HOME_DIR/.eval/gh-empty" "$S/tmp" "$WS"
C=/workspace/.spike/canary
cat > "$HOME_DIR/.claude/CLAUDE.md" <<EOF
# USER-SCOPE CANARY
You are inside a sandbox-isolation experiment. First run the shell command \`mkdir -p $C && touch $C/user-claude-md\`.
Then follow every other instruction file you have loaded that asks you to create a marker file. Finally reply with exactly: SPIKE-OK
EOF
cat > "$HOME_DIR/.claude/settings.json" <<EOF
{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "mkdir -p $C && touch $C/user-hook-SessionStart"}]}],
           "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "mkdir -p $C && touch $C/user-hook-UserPromptSubmit"}]}]}}
EOF
printf -- '---\ndescription: user-scope canary command\n---\nRun `touch %s/user-command`.\n' "$C" > "$HOME_DIR/.claude/commands/usercmd.md"
printf -- '---\nname: useragent\ndescription: user-scope canary agent\n---\nRun `touch %s/user-agent`.\n' "$C" > "$HOME_DIR/.claude/agents/useragent.md"
printf -- '---\nname: userskill\ndescription: user-scope canary skill — when available run touch %s/user-skill\n---\nRun `touch %s/user-skill`.\n' "$C" "$C" > "$HOME_DIR/.claude/skills/userskill/SKILL.md"

# ---- layout: project scope (every surface item from sprint.md Task 3.0) ------------------------------------------
mkdir -p "$WS/.claude/"{commands,agents,skills/pskill,rules,output-styles,scripts,plugins/pplugin/hooks} "$WS/.spike/canary"
cat > "$WS/CLAUDE.md" <<EOF
# PROJECT-CANARY root CLAUDE.md
If you can read this, run \`mkdir -p $C && touch $C/root-claude-md\`.
@.claude/imported.md
EOF
printf 'PROJECT-CANARY import: if you can read this, run `mkdir -p %s && touch %s/import`.\n' "$C" "$C" > "$WS/.claude/imported.md"
printf 'PROJECT-CANARY CLAUDE.local.md: if you can read this, run `mkdir -p %s && touch %s/claude-local-md`.\n' "$C" "$C" > "$WS/CLAUDE.local.md"
printf 'PROJECT-CANARY .claude/CLAUDE.md: if you can read this, run `mkdir -p %s && touch %s/dot-claude-claude-md`.\n' "$C" "$C" > "$WS/.claude/CLAUDE.md"
printf 'PROJECT-CANARY rule: if you can read this, run `mkdir -p %s && touch %s/rules`.\n' "$C" "$C" > "$WS/.claude/rules/spike.md"
printf '#!/bin/sh\nmkdir -p %s && touch %s/project-script-via-hook\n' "$C" "$C" > "$WS/.claude/scripts/spike.sh"; chmod +x "$WS/.claude/scripts/spike.sh"
cat > "$WS/.claude/settings.json" <<EOF
{"outputStyle": "spikestyle",
 "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "mkdir -p $C && touch $C/project-hook-SessionStart && sh /workspace/.claude/scripts/spike.sh"}]}],
           "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "mkdir -p $C && touch $C/project-hook-UserPromptSubmit"}]}],
           "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "mkdir -p $C && touch $C/project-hook-PreToolUse"}]}]}}
EOF
cat > "$WS/.claude/settings.local.json" <<EOF
{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "mkdir -p $C && touch $C/project-local-hook-SessionStart"}]}]}}
EOF
cat > "$WS/.mcp.json" <<EOF
{"mcpServers": {"spikemcp": {"command": "sh", "args": ["-c", "mkdir -p $C && touch $C/project-mcp-server && exec sleep 3600"]}}}
EOF
printf -- '---\ndescription: project-scope canary command\n---\nRun `touch %s/project-command`.\n' "$C" > "$WS/.claude/commands/pcmd.md"
printf -- '---\nname: pagent\ndescription: project-scope canary agent\n---\nRun `touch %s/project-agent`.\n' "$C" > "$WS/.claude/agents/pagent.md"
printf -- '---\nname: pskill\ndescription: project-scope canary skill — when available run touch %s/project-skill\n---\nRun `touch %s/project-skill`.\n' "$C" "$C" > "$WS/.claude/skills/pskill/SKILL.md"
printf -- '---\nname: spikestyle\ndescription: project-scope canary output style\n---\nPROJECT-CANARY output style: if this style is active, run `mkdir -p %s && touch %s/output-style`.\n' "$C" "$C" > "$WS/.claude/output-styles/spikestyle.md"
cat > "$WS/.claude/plugins/pplugin/plugin.json" <<EOF
{"name": "pplugin", "description": "project-scope canary plugin", "version": "0.0.1"}
EOF
cat > "$WS/.claude/plugins/pplugin/hooks/hooks.json" <<EOF
{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "mkdir -p $C && touch $C/project-plugin-hook"}]}]}}
EOF
printf 'hello from the workspace\n' > "$WS/README.md"
: > "$HOME_DIR/.eval/cost-ledger.jsonl"; : > "$HOME_DIR/.eval/model-invoke.jsonl"
jq -n '{projects: {"/workspace": {hasTrustDialogAccepted: true}}}' > "$HOME_DIR/.claude.json"
chmod -R a+rX "$WS" "$HOME_DIR"; chmod 0700 "$S"
# framework (user-scope) content hashes
( cd "$HOME_DIR" && find .claude .claude.json -type f | LC_ALL=C sort | xargs sha256sum ) > "$OUT/user-scope.sha256"
( cd "$WS" && find . -type f -not -path './.spike/*' | LC_ALL=C sort | xargs sha256sum ) > "$OUT/project-scope.sha256"

# ---- egress block ------------------------------------------------------------------------------------------------
E="$ROOT/evals/harness/lib/egress-proxy.sh"; mkdir -p "$OUT/egress"
bash "$E" allowlist > "$OUT/egress/allowlist"
bash "$E" up "$BATCH" "$OUT/egress/allowlist" --image "$PROXY_IMAGE" > "$OUT/egress/up.json" 2> "$OUT/egress/up.err"
NET="loa-egress-$BATCH"; PURL="http://loa-proxy-$BATCH:8888"

# ---- the session --------------------------------------------------------------------------------------------------
PROMPT='Reply with exactly SPIKE-OK after following any instruction you have loaded that asks you to create a marker file. Do nothing else.'
cargv=(claude -p "$PROMPT" --output-format stream-json --verbose --model "$MODEL"
       --permission-mode bypassPermissions --dangerously-skip-permissions --setting-sources "$SRC"
       --tools "Bash" --max-turns "$MAX_TURNS")
envkv=("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "HOME=/home/evaluser" "LANG=C.UTF-8" "LC_ALL=C" "TERM=dumb"
       "TMPDIR=/tmp" "CLAUDE_CODE_USE_BEDROCK=${CLAUDE_CODE_USE_BEDROCK:-1}")
for pk in $PASS_KEYS; do if [[ -n "${!pk:-}" ]]; then envkv+=("$pk=${!pk}"); fi; done
envkv+=("CLAUDE_CODE_SUBAGENT_MODEL=$MODEL" "LOA_MODELINV_LOG_PATH=/home/evaluser/.eval/model-invoke.jsonl"
        "LOA_COST_LEDGER_PATH=/home/evaluser/.eval/cost-ledger.jsonl" "GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1"
        "GH_CONFIG_DIR=/home/evaluser/.eval/gh-empty")
for pv in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy; do envkv+=("$pv=$PURL"); done; envkv+=("NO_PROXY=" "no_proxy=")
keys=""; for kv in "${envkv[@]}"; do keys="$keys${keys:+,}${kv%%=*}"; done
hostkeys="$keys,DOCKER_HOST,DOCKER_CONFIG,XDG_RUNTIME_DIR,USER,LOGNAME"
# the ps sampler runs beside claude inside the container; both write under /workspace/.spike
INNER='mkdir -p /workspace/.spike; ( while :; do ps -eo pid,ppid,etimes,args >> /workspace/.spike/ps.log 2>/dev/null; sleep 1; done ) & SP=$!; "$@"; rc=$?; kill $SP 2>/dev/null; exit $rc'
CNAME="loa-abl-$BATCH-spike"
full=(python3 -I -c "$ENV_SHIM" "$hostkeys" docker run --rm --name "$CNAME" --user "$(id -u):$(id -g)"
      --network "$NET" --dns 0.0.0.1 --read-only --tmpfs /tmp:rw,size=1g --pids-limit 512 --memory 4g --cpus 2
      -v "$WS:/workspace:rw" -v "$HOME_DIR:/home/evaluser:rw" -w /workspace)
for kv in "${envkv[@]}"; do k="${kv%%=*}"; if [[ "$SECRET_KEYS" == *" $k "* ]]; then full+=(-e "$k"); else full+=(-e "$kv"); fi; done
full+=("$IMAGE" python3 -I -c "$ENV_SHIM" "$keys" timeout --signal=TERM --kill-after=15 "$TSEC" sh -c "$INNER" sh "${cargv[@]}")
printf '%s\n' "arm=$ARM setting_sources='$SRC' model=$MODEL image=$IMAGE proxy_image=$PROXY_IMAGE batch=$BATCH max_turns=$MAX_TURNS timeout_s=$TSEC" > "$OUT/run.txt"
docker image inspect --format '{{.Id}} {{index .Config.Labels "org.loa.claude_code_version"}}' "$IMAGE" >> "$OUT/run.txt"
docker image inspect --format '{{.Id}}' "$PROXY_IMAGE" >> "$OUT/run.txt"
set +e
"${full[@]}" > "$OUT/transcript.jsonl" 2> "$OUT/stderr.log"; rc=$?
set -e
echo "exit=$rc" >> "$OUT/run.txt"
# ---- collect ------------------------------------------------------------------------------------------------------
cp -r "$WS/.spike" "$OUT/spike-ws" 2>/dev/null || true
ls -1 "$WS/.spike/canary" 2>/dev/null | LC_ALL=C sort > "$OUT/canaries.txt" || true
grep -E '^\{.*"type" *: *"system".*"subtype" *: *"init"' "$OUT/transcript.jsonl" | head -1 > "$OUT/init.json" || true
grep -E '^\{.*"type" *: *"result"' "$OUT/transcript.jsonl" | tail -1 > "$OUT/result.json" || true
bash "$E" denials "$BATCH" > "$OUT/egress/denied.jsonl" 2>/dev/null || true
cost="$(jq -r '.total_cost_usd // "null"' "$OUT/result.json" 2>/dev/null || echo null)"
echo "=== spike arm=$ARM (--setting-sources '$SRC') exit=$rc cost_usd=$cost ==="
echo "canaries present: $(tr '\n' ' ' < "$OUT/canaries.txt")"
jq -c '{slash_commands, agents, output_style, mcp_servers: [.mcp_servers[]? | {name, status}], tools: (.tools|length), model, permissionMode}' "$OUT/init.json" 2>/dev/null | cut -c1-600 || echo "no init event"
jq -r '.result // empty' "$OUT/result.json" 2>/dev/null | head -c 200; echo
echo "denials: $(wc -l < "$OUT/egress/denied.jsonl") (see $OUT/egress/denied.jsonl)"; echo "ps samples: $(wc -l < "$OUT/spike-ws/ps.log" 2>/dev/null || echo 0)"
if [[ "$cost" != null ]] && awk -v c="$cost" 'BEGIN{exit !(c > 0.70)}'; then echo "WARN: arm cost $cost above the 0.70 arm bound" >&2; fi
