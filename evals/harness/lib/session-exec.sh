#!/usr/bin/env bash
# =============================================================================
# lib/session-exec.sh — the session mechanics a blind `claude -p` session shares with
# pipeline-run.sh (cycle-132 Task 1.4, SDD §1.4 "Blind session runner", D-7.1)
#
# Sourced (by a literal relative path, eval.yml trust boundary) by evals/harness/blind-session.sh.
# Every definition below is a VERBATIM copy of pipeline-run.sh's: the python3 -I exec shim that
# closes every descriptor above 2 and keeps exactly the named environment keys (DEC-0412), the
# Bedrock pass-through keys and the secret keys that travel by name only, and the per-model
# pricing lookup and stream re-pricing the cap watchdog uses (D-4.10). pipeline-run.sh keeps its
# own copies (its bats harness copies only the files it sources today; cycle-132 implementer B
# DECISION), and evals/tests/blind-session.bats fails when the two drift apart.
#
# Needs: REPO_ROOT (pricing.py lives under it); PRICE_CACHE is initialised here.
# Env: LOA_EVAL_PRICING_JSON (a {"<model>": {input_per_mtok, output_per_mtok, …}} override).
# =============================================================================

# ENV_SHIM <keys-csv> <cmd…>: close every descriptor above 2 (DEC-0412), keep exactly the
# named environment variables, exec <cmd>. No eval (eval.yml trust boundary), and secret
# values never appear in any argv: they travel in the environment only.
ENV_SHIM='import os, sys
keys = [k for k in sys.argv[1].split(",") if k]
env = {k: os.environ[k] for k in keys if k in os.environ}
os.closerange(3, 65536)
os.execvpe(sys.argv[2], sys.argv[2:], env)'
# pass-through keys, taken from the driver's environment when set; SECRET_KEYS are never
# written to an argv or a capture (recorded as <set>)
PASS_KEYS="AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_BEARER_TOKEN_BEDROCK ANTHROPIC_BEDROCK_REGION_PREFIX ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL"
SECRET_KEYS=" AWS_BEARER_TOKEN_BEDROCK "

# --- pricing (one lookup per model; D-4.10) ---------------------------------------------
PRICE_CACHE=""
price_for() {  # price_for <model id> → {"in":…,"out":…,"cr":…,"cc":…} micro-USD per Mtok, or null
  local m="$1" hit alias j
  hit="$(printf '%s\n' "$PRICE_CACHE" | awk -F'\t' -v m="$m" '$1 == m {print $2; exit}')"
  [[ -n "$hit" ]] && { printf '%s' "$hit"; return 0; }
  if [[ -n "${LOA_EVAL_PRICING_JSON:-}" ]]; then
    j="$(jq -c --arg m "$m" '.[$m] // null' <<<"$LOA_EVAL_PRICING_JSON" 2>/dev/null || echo null)"
  else
    alias="$(printf '%s' "$m" | sed -E 's/^([a-z]+\.)?anthropic\.//; s/-v[0-9]+(:[0-9]+)?$//')"
    j="$(cd "$REPO_ROOT/.claude/adapters" && python3 -I "$REPO_ROOT/.claude/adapters/loa_cheval/metering/pricing.py" \
          --alias "$alias" --json 2>/dev/null | sed -n '1p' || true)"
    [[ -n "$j" ]] || j=null
  fi
  j="$(jq -c 'if (type == "object") and (.input_per_mtok != null) and (.output_per_mtok != null)
              then {in: .input_per_mtok, out: .output_per_mtok,
                    cr: (.cache_read_per_mtok // (.input_per_mtok * 0.1)),
                    cc: (.cache_write_per_mtok // .cache_creation_per_mtok // (.input_per_mtok * 1.25))}
              else null end' <<<"$j" 2>/dev/null || echo null)"
  PRICE_CACHE="$PRICE_CACHE$m"$'\t'"$j"$'\n'
  printf '%s' "$j"
}
# price_events <events> <prices> <budget_micro> → "<turns> <estimate_micro> <crossing_turn|0>"
price_events() {
  jq -R -n -r --argjson p "$2" --argjson budget "$3" '
    def cost(u): ((u.input_tokens // 0) * $p.in + (u.output_tokens // 0) * $p.out
                  + (u.cache_read_input_tokens // 0) * $p.cr + (u.cache_creation_input_tokens // 0) * $p.cc) / 1000000;
    reduce (inputs | fromjson? | select(type == "object" and .type == "assistant"
                                        and ((.message.usage // null) | type) == "object")) as $e
      ({order: [], u: {}, n: 0};
       .n += 1
       | ($e.message.id // ("event-" + (.n | tostring))) as $id
       | (if .u[$id] == null then .order += [$id] else . end)
       | .u[$id] = $e.message.usage)
    | [.order[] as $id | cost(.u[$id])] as $c
    | (reduce range(0; $c | length) as $i ({s: 0, x: 0};
         if .x == 0 then (.s += $c[$i]) | (if .s >= $budget then .x = ($i + 1) else . end) else . end)) as $r
    | "\($c | length) \(($c | add // 0) | round) \($r.x)"' 2>/dev/null < "$1" || echo "0 0 0"
}
