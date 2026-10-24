#!/usr/bin/env bash
# =============================================================================
# lib/arms-common.sh — helpers shared by the two batch runners (cycle-130 Task 3.2)
#
# Sourced (never executed) by evals/harness/run-arms.sh (cycle-129 recall arms) and
# evals/harness/run-ablation.sh (cycle-130 ablation batches), each by the literal
# relative path ./lib/arms-common.sh after `pushd "$SCRIPT_DIR"` (eval.yml trust
# boundary: no variable on a source line, no .claude/ code). Extracted from
# run-arms.sh without behaviour change; evals/tests/run-arms.bats is the golden check.
#
# Functions:
#   usd_ok <v>                 0 when <v> is an amount in USD (1-6 digits, up to 4 decimals)
#   fadd <a> <b>               a + b, printed %.10g (awk)
#   json_array <v>…            the arguments as a compact JSON string array
#   is_transport_failure <ws>  run-arms layout: <ws>/.eval/{executor.json,agent-output.json,
#                              agent-stderr.log}; 0 when the executor failed for a transport
#                              reason (timeout exit 124/137/143, no result event, API error
#                              status, or a CLI transport message on stderr)
#   is_pipeline_transport_failure <run-dir>
#                              pipeline-run.sh layout: 0 when meta/pipeline.json says
#                              agent_error AND the failing phase (the last executed record
#                              with a non-zero exit, else the last executed record) shows a
#                              provider/transport signature: its transcripts/stderr-<label>.log
#                              matches ARMS_TRANSPORT_RE, or its events-<label>.jsonl holds a
#                              result event with a non-empty api_error_status, or an is_error
#                              result (the CLI's own error, never the agent's text) whose text
#                              starts "API Error" or matches ARMS_TRANSPORT_RE (a usage or
#                              session limit). Assistant messages are never read. A phase timeout is the
#                              model's own account (DEC-0417) and is never transport here.
#                              Prints the signature source (stderr | api_error_status |
#                              api_error_result) and the phase label on success.
#   est_record <key> <pool> <cost>   add one completed trial's cost to the key's and the
#                              pool's means (est_next's inputs)
#   est_next <key> [<pool>]    the next trial's expected cost: the key's mean, else the
#                              pool's mean (default pool "all"), else `est_hint <key>`
#                              (default: $COST_HINT; a runner may redefine est_hint)
#   spend_charge <status> <cost> <what> [<cap>]
#                              charge one finished trial to SPENT: a trial that ended
#                              without status completed and without a reported cost is
#                              charged <cap> (default RUN_CAP; run-ablation.sh passes the
#                              trial kind's cap, DEC-0567) (ASSUMED_CAP+1, logged); else its cost.
#                              Sets CHARGED_COST to the reported cost it accepted (0 for an
#                              assumed charge); call it directly, never in $( ), or SPENT
#                              is lost with the subshell
#   budget_gate <key> <trial-number> [<pool>] [<reserve-per-trial>]
#                              0 launch; 1 cut (CUT_JSON set). Waits (reap) while only the
#                              in-flight reservation (${#PIDS[@]} × <reserve-per-trial>,
#                              default RUN_CAP; run-ablation.sh passes the largest cap among
#                              its plan's kinds, DEC-0567) blocks the launch
#
# Globals read: RUN_CAP, MAX_USD, COST_HINT, LAUNCHED, PIDS (array); written: SPENT,
# ASSUMED_CAP, CHARGED_COST, CUT_JSON, EST_KEYS/EST_SUM/EST_N, POOL_KEYS/POOL_SUM/POOL_N (parallel
# arrays: bash 3.2 has no associative arrays). The caller defines log and reap.
# =============================================================================

usd_ok() { [[ "$1" =~ ^[0-9]{1,6}(\.[0-9]{1,4})?$ ]]; }
fadd() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.10g", a + b }'; }
json_array() { printf '%s\n' "$@" | jq -R . | jq -sc .; }

# The CLI's transport messages (audit r1 DISS-C-005: matched on the CLI's stderr only,
# never on the agent's own output, so the agent under test cannot earn itself a retry
# by mentioning a network error).
ARMS_TRANSPORT_RE='rate.?limit|overloaded|session limit|usage limit|out of extra usage|ECONNRESET|ETIMEDOUT|socket hang up|^(fetch|request) failed|HTTP 5[0-9][0-9]'

is_transport_failure() {  # is_transport_failure <sandbox-ws>
  local ws="$1" out="$1/.eval/agent-output.json" err="$1/.eval/agent-stderr.log" rc
  rc="$(jq -r '.exit_code // 0' "$ws/.eval/executor.json" 2>/dev/null || echo 0)"  # check-no-swallowed-jq: ok (classification only: an unreadable executor.json falls to the agent-output checks below; pending #1025 sweep)
  case "$rc" in 124|137|143) return 0 ;; esac
  [[ "$(jq -r '.subtype // ""' "$out" 2>/dev/null)" == "missing" ]] && return 0
  [[ -n "$(jq -r '.api_error_status // empty' "$out" 2>/dev/null)" ]] && return 0
  grep -qiE "$ARMS_TRANSPORT_RE" "$err" 2>/dev/null && return 0
  return 1
}

is_pipeline_transport_failure() {  # is_pipeline_transport_failure <run-dir>
  local rd="$1" pipe="$1/meta/pipeline.json" label
  [[ "$(jq -r '.status // ""' "$pipe" 2>/dev/null)" == "agent_error" ]] || return 1
  label="$(jq -r '[.phases // [] | .[] | select(.skipped != true)] as $r
                  | ([$r[] | select((.exit // 0) != 0)] | last // ($r | last) // {}) | .label // ""' \
           "$pipe" 2>/dev/null || true)"
  [[ "$label" =~ ^[A-Z][A-Z0-9]{0,15}$ ]] || return 1
  if grep -qiE "$ARMS_TRANSPORT_RE" "$rd/transcripts/stderr-$label.log" 2>/dev/null; then
    printf 'stderr %s\n' "$label"; return 0
  fi
  local ev="$rd/transcripts/events-$label.jsonl" sig=""
  if [[ -f "$ev" ]]; then
    sig="$(jq -R -r --arg re "$ARMS_TRANSPORT_RE" 'fromjson? | select(type == "object" and .type == "result")
                    | if ((.api_error_status // "") | tostring) != "" then "api_error_status"
                      elif .is_error == true and ((.result // "") | type) == "string"
                           and ((.result // "") | test("^API Error|" + $re; "i")) then "api_error_result"
                      else empty end' "$ev" 2>/dev/null | head -1 || true)"
  fi
  if [[ -n "$sig" ]]; then printf '%s %s\n' "$sig" "$label"; return 0; fi
  return 1
}

# --- est_next inputs (completed trials only; assumed charges never enter) ---------
EST_KEYS=() EST_SUM=() EST_N=() POOL_KEYS=() POOL_SUM=() POOL_N=()
_est_find() {  # _est_find <EST|POOL> <key> → index or -1
  local i
  if [[ "$1" == EST ]]; then
    for i in ${EST_KEYS[@]+"${!EST_KEYS[@]}"}; do [[ "${EST_KEYS[$i]}" == "$2" ]] && { echo "$i"; return; }; done
  else
    for i in ${POOL_KEYS[@]+"${!POOL_KEYS[@]}"}; do [[ "${POOL_KEYS[$i]}" == "$2" ]] && { echo "$i"; return; }; done
  fi
  echo -1
}
est_record() {  # est_record <key> <pool> <cost>
  local i
  i="$(_est_find EST "$1")"
  if [[ "$i" -lt 0 ]]; then i=${#EST_KEYS[@]}; EST_KEYS[$i]="$1"; EST_SUM[$i]=0; EST_N[$i]=0; fi
  EST_SUM[$i]="$(fadd "${EST_SUM[$i]}" "$3")"; EST_N[$i]=$(( ${EST_N[$i]} + 1 ))
  i="$(_est_find POOL "$2")"
  if [[ "$i" -lt 0 ]]; then i=${#POOL_KEYS[@]}; POOL_KEYS[$i]="$2"; POOL_SUM[$i]=0; POOL_N[$i]=0; fi
  POOL_SUM[$i]="$(fadd "${POOL_SUM[$i]}" "$3")"; POOL_N[$i]=$(( ${POOL_N[$i]} + 1 ))
}
est_hint() { printf '%s' "$COST_HINT"; }
est_next() {  # est_next <key> [<pool>]
  local i p
  i="$(_est_find EST "$1")"; p="$(_est_find POOL "${2:-all}")"
  if [[ "$i" -ge 0 ]] && [[ "${EST_N[$i]}" -gt 0 ]]; then
    awk -v s="${EST_SUM[$i]}" -v n="${EST_N[$i]}" 'BEGIN { printf "%.10g", s / n }'
  elif [[ "$p" -ge 0 ]] && [[ "${POOL_N[$p]}" -gt 0 ]]; then
    awk -v s="${POOL_SUM[$p]}" -v n="${POOL_N[$p]}" 'BEGIN { printf "%.10g", s / n }'
  else est_hint "$1"; fi
}

spend_charge() {  # spend_charge <status> <cost> <what> [<cap>]
  local st="$1" cost="$2" what="$3" cap="${4:-$RUN_CAP}"
  [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || cost=0
  if [[ "$st" != "completed" ]] && awk -v c="$cost" 'BEGIN { exit !(c + 0 == 0) }'; then
    # audit MEDIUM-A2: a failed trial that reports no cost is charged the run cap
    SPENT="$(fadd "$SPENT" "$cap")"; ASSUMED_CAP=$((ASSUMED_CAP + 1))
    log "assumed cap: $what ended ${st:-without a status} with no reported cost; USD $cap charged to spent"
    CHARGED_COST=0
  else
    SPENT="$(fadd "$SPENT" "$cost")"
    CHARGED_COST="$cost"
  fi
}

budget_gate() {  # budget_gate <key> <trial-number> [<pool>] [<reserve-per-trial>]
  local key="$1" at="$2" pool="${3:-all}" per="${4:-$RUN_CAP}" est inflight reserved
  while true; do
    est="$(est_next "$key" "$pool")"; inflight=${#PIDS[@]}
    reserved="$(awk -v k="$inflight" -v c="$per" 'BEGIN { printf "%.10g", k * c }')"
    if awk -v s="$SPENT" -v e="$est" -v m="$MAX_USD" 'BEGIN { exit !(s + e > m) }'; then
      CUT_JSON="$(jq -cn --arg s "$SPENT" --arg r "$reserved" --arg m "$MAX_USD" --arg e "$est" \
        --argjson launched "$LAUNCHED" --argjson at "$at" \
        '{reason: "max_usd", spent: ($s | tonumber), in_flight_reserved: ($r | tonumber), max: ($m | tonumber),
          est_next: ($e | tonumber), trials_launched: $launched, at_trial: $at}')"
      log "cut: max_usd $MAX_USD reached after $LAUNCHED trials (spent $SPENT, in-flight reserved $reserved, next est $est; trial $at not launched; reason recorded in STATUS.json)"
      return 1
    fi
    if awk -v s="$SPENT" -v r="$reserved" -v e="$est" -v m="$MAX_USD" 'BEGIN { exit !(s + r + e > m) }'; then
      reap "$inflight"; continue
    fi
    return 0
  done
}
