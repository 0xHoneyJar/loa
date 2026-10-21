#!/usr/bin/env bash
# claude-stub-pipeline.sh — stand-in for the `claude` CLI in evals/tests/pipeline-run.bats.
# One invocation = one pipeline phase. The phase is read from the prompt's first
# line (`# Phase: <NAME>`); the stub records what the executor gave it and emits a
# stream-json transcript with a system/init event (session_id), per-turn
# assistant events carrying usage, and a result event.
#   STUB_LOG_DIR            per call: call-<n>.argv (NUL-separated), call-<n>.env
#                           (`env` output), call-<n>.fds (ls /proc/self/fd), call-<n>.phase,
#                           call-<n>.pwd. The executor's `env -i` strips these
#                           controls, so tests reach the stub through a wrapper that
#                           records pending.env / pending.fds and then loads them.
#   STUB_COST_<PHASE>       result total_cost_usd (default 0.5)
#   STUB_TURNS_<PHASE>      assistant turns to emit (default 2)
#   STUB_TURN_OUT_<PHASE>   output tokens per turn (default 100)
#   STUB_TURN_SLEEP         seconds between turns (default 0)
#   STUB_SLEEP_<PHASE>      seconds to sleep before the result event
#   STUB_EXIT_<PHASE>       exit code (default 0)
#   STUB_SELF_KILL_<PHASE>  1: SIGTERM itself mid-phase (a phase killed from outside)
#   STUB_VERDICT_REVIEW / STUB_VERDICT_AUDIT  APPROVED (default) | CHANGES_REQUIRED
#   STUB_MODEL_USED_<PHASE> model id reported in modelUsage (default: --model)
#   STUB_REFUSAL_<PHASE>    1: emit a system/model_refusal_fallback event
#   STUB_DOT_CLAUDE_WRITE_<PHASE>  1: emit a Write tool_use under .claude/
#   STUB_LEDGER_USD_<PHASE> append a cost-ledger row of that many USD to
#                           $LOA_COST_LEDGER_PATH and one MODELINV row to
#                           $LOA_MODELINV_LOG_PATH (a cheval voice call); the row's
#                           calling_primitive / effort / effort_effective come from
#                           STUB_PRIMITIVE_<PHASE>, STUB_HOP_EFFORT_<PHASE>,
#                           STUB_HOP_EFFECTIVE_<PHASE>
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then echo "2.1.299 (Claude Code) stub"; exit 0; fi

prompt="" model="" resume=""
args=("$@")
i=0
while [[ $i -lt ${#args[@]} ]]; do
  case "${args[$i]}" in
    -p) prompt="${args[$((i + 1))]}"; i=$((i + 1)) ;;
    --model) model="${args[$((i + 1))]}"; i=$((i + 1)) ;;
    --resume) resume="${args[$((i + 1))]}"; i=$((i + 1)) ;;
  esac
  i=$((i + 1))
done
phase="$(printf '%s\n' "$prompt" | sed -n '1s/^# Phase: //p')"
[[ -n "$phase" ]] || phase=UNKNOWN

if [[ -n "${STUB_LOG_DIR:-}" ]]; then
  mkdir -p "$STUB_LOG_DIR"
  n=1; while [[ -e "$STUB_LOG_DIR/call-$n.argv" ]]; do n=$((n + 1)); done
  printf '%s\0' "$@" > "$STUB_LOG_DIR/call-$n.argv"
  # the executor runs the CLI under `env -i`, so the bats wrapper (make_wrappers in
  # pipeline-run.bats) captures the environment and descriptors it was given into
  # pending.* BEFORE loading the stub's controls; without a wrapper, capture here
  if [[ -f "$STUB_LOG_DIR/pending.env" ]]; then mv "$STUB_LOG_DIR/pending.env" "$STUB_LOG_DIR/call-$n.env"
  else env | sed -E 's/^(AWS_BEARER_TOKEN_BEDROCK)=.*/\1=<set>/' > "$STUB_LOG_DIR/call-$n.env"; fi   # key name only
  if [[ -f "$STUB_LOG_DIR/pending.fds" ]]; then mv "$STUB_LOG_DIR/pending.fds" "$STUB_LOG_DIR/call-$n.fds"
  else ls "/proc/$$/fd" > "$STUB_LOG_DIR/call-$n.fds" 2>/dev/null || true; fi
  printf '%s\n' "$phase" > "$STUB_LOG_DIR/call-$n.phase"
  printf '%s\n' "$PWD" > "$STUB_LOG_DIR/call-$n.pwd"
fi

v() { local k="$1_$phase" d="$2"; printf '%s' "${!k:-$d}"; }
cost="$(v STUB_COST 0.5)"; turns="$(v STUB_TURNS 2)"; out_tok="$(v STUB_TURN_OUT 100)"
used="$(v STUB_MODEL_USED "$model")"
if [[ -n "$resume" ]]; then sid="$resume"; else sid="sess-$phase-$$-$RANDOM"; fi

a2a="grimoires/loa/a2a/sprint-1"
case "$phase" in
  PLAN) mkdir -p grimoires/loa; printf '# Sprint plan\n\n## Success Criteria\nx\n' > grimoires/loa/sprint.md ;;
  IMPLEMENT|FIX) printf '%s\n' "$phase" >> work.txt; mkdir -p "$a2a"; printf 'report %s\n' "$phase" > "$a2a/reviewer.md" ;;
  BARE) printf '%s\n' "$phase" >> work.txt ;;
  REVIEW|AUDIT)
    if [[ "$phase" == REVIEW ]]; then vv="${STUB_VERDICT_REVIEW:-APPROVED}" f="$a2a/engineer-feedback.md" gate=review t=code_review
    else vv="${STUB_VERDICT_AUDIT:-APPROVED}" f="$a2a/auditor-sprint-feedback.md" gate=audit t=security_audit; fi
    mkdir -p "$a2a"
    printf 'feedback\n<!-- LOA-VERDICT {"gate":"%s","verdict":"%s","counts":{"critical":0,"high":0,"medium":0,"low":0}} -->\n' "$gate" "$vv" > "$f"
    # the dissent envelope says what the sandbox config planned (A3 evidence)
    cv="$(yq -r ".flatline_protocol.$t.companion_voice" .loa.config.yaml 2>/dev/null || echo null)"
    planned=true; [[ "$cv" == false ]] && planned=false
    jq -n --argjson p "$planned" '{verdict_quality: {status: "APPROVED", voices_planned: (if $p then 2 else 1 end),
      voices_succeeded: (if $p then 2 else 1 end)}, metadata: {companion_voice: {planned: $p}}}' \
      > "$a2a/adversarial-$gate.json"
    ;;
esac

led="$(v STUB_LEDGER_USD 0)"
if [[ "$led" != 0 && -n "${LOA_COST_LEDGER_PATH:-}" ]]; then
  jq -cn --argjson u "$led" '{ts: "2026-10-15T00:00:00Z", agent: "flatline-orchestrator", cost_micro_usd: ($u * 1000000 | round)}' >> "$LOA_COST_LEDGER_PATH"
  prim_d="adversarial-$(printf '%s' "$phase" | tr 'A-Z' 'a-z')"
  prim="$(v STUB_PRIMITIVE "$prim_d")"; heff="$(v STUB_HOP_EFFORT xhigh)"; heffv="$(v STUB_HOP_EFFECTIVE "$heff")"
  jq -cn --arg p "$prim" --arg e "$heff" --arg ee "$heffv" --argjson u "$led" \
    '{schema_version: "1.1.0", primitive_id: "MODELINV", event_type: "model.invoke.complete", ts_utc: "2026-10-15T00:00:00.000000Z",
      payload: {models_requested: ["openai:gpt-5.5"], models_succeeded: ["openai:gpt-5.5"], calling_primitive: $p,
                effort: $e, effort_effective: $ee, cost_micro_usd: ($u * 1000000 | round)}}' >> "${LOA_MODELINV_LOG_PATH:-/dev/null}"
fi
printf '{"type":"system","subtype":"init","session_id":"%s","model":"%s"}\n' "$sid" "$model"
if [[ "$(v STUB_REFUSAL 0)" == 1 ]]; then
  printf '{"type":"system","subtype":"model_refusal_fallback","original_model":"%s","fallback_model":"other-model","api_refusal_category":"x"}\n' "$model"
fi
if [[ "$(v STUB_DOT_CLAUDE_WRITE 0)" == 1 ]]; then
  printf '{"type":"assistant","message":{"id":"msg-w","content":[{"type":"tool_use","name":"Write","input":{"file_path":".claude/skills/x/SKILL.md","content":"x"}}],"usage":{"input_tokens":1,"output_tokens":1}}}\n'
fi
t=1
while [[ $t -le $turns ]]; do
  printf '{"type":"assistant","message":{"id":"msg-%s-%d","content":[{"type":"text","text":"turn %d"}],"usage":{"input_tokens":10,"output_tokens":%d,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' \
    "$phase" "$t" "$t" "$out_tok"
  if [[ "$(v STUB_SELF_KILL 0)" == 1 && $t -eq 1 ]]; then kill -TERM $$; sleep 5; fi
  [[ "${STUB_TURN_SLEEP:-0}" != 0 ]] && sleep "$STUB_TURN_SLEEP"
  t=$((t + 1))
done
s="$(v STUB_SLEEP 0)"; [[ "$s" != 0 ]] && sleep "$s"
printf '{"type":"result","subtype":"success","is_error":false,"session_id":"%s","duration_ms":1000,"num_turns":%d,"total_cost_usd":%s,"usage":{"input_tokens":%d,"output_tokens":%d,"cache_read_input_tokens":3,"cache_creation_input_tokens":4},"modelUsage":{"%s":{"inputTokens":%d,"outputTokens":%d,"costUSD":%s}}}\n' \
  "$sid" "$turns" "$cost" $((turns * 10)) $((turns * out_tok)) "$used" $((turns * 10)) $((turns * out_tok)) "$cost"
exit "$(v STUB_EXIT 0)"
