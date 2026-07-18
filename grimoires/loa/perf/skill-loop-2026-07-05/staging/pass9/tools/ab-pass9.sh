#!/usr/bin/env bash
# ab-pass9.sh — old-vs-new A/B for the three pass-9 hooks. Per-run ALTERNATION
# (pass-3 lesson: powersave governor drift makes block-wise A/B lie).
set -u
export LC_ALL=C
REPO=${REPO:-/home/merlin/Documents/thj/code/loa}
OLDDIR=${OLDDIR:-/tmp/p9/old}
NEWDIR=${NEWDIR:-$REPO/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass9}
WORK=${WORK:-/tmp/p9ab}
RUNS=${RUNS:-20}

rm -rf "$WORK"; mkdir -p "$WORK/old/.run" "$WORK/new/.run"

bench_pair() {  # bench_pair <label> <hook-basename> <payload-file> [ENV=VAL...]
  local label=$1 hook=$2 pl=$3; shift 3
  local side i t0 t1 hookpath
  declare -A xs=( [old]="" [new]="" )
  for i in 1 2 3; do for side in old new; do
    [[ $side == old ]] && hookpath="$OLDDIR/$hook" || hookpath="$NEWDIR/$hook"
    ( cd "$WORK/$side" && env "$@" bash "$hookpath" <"$pl" >/dev/null 2>&1 )
  done; done
  for ((i=0;i<RUNS;i++)); do
    for side in old new; do
      [[ $side == old ]] && hookpath="$OLDDIR/$hook" || hookpath="$NEWDIR/$hook"
      t0=${EPOCHREALTIME/./}
      ( cd "$WORK/$side" && env "$@" bash "$hookpath" <"$pl" >/dev/null 2>&1 )
      t1=${EPOCHREALTIME/./}
      xs[$side]+="$(( (t1 - t0) / 1000 )) "
    done
  done
  for side in old new; do
    local -a v; read -ra v <<< "${xs[$side]}"
    mapfile -t v < <(printf '%s\n' "${v[@]}" | sort -n)
    local n=${#v[@]} sum=0 x
    for x in "${v[@]}"; do sum=$((sum+x)); done
    local p95i=$(( (n*95 + 99) / 100 - 1 )); (( p95i >= n )) && p95i=$((n-1))
    printf '%s\t%s\truns=%d\tmean=%d.%01d\tp95=%d\tmin=%d\tmax=%d\n' \
      "$label" "$side" "$n" $((sum/n)) $(( (sum % n) * 10 / n )) \
      "${v[$p95i]}" "${v[0]}" "${v[$((n-1))]}"
  done
}

PL="$WORK/pl.json"
printf '# ab-pass9: adv-gate / spiral-skill-sentinel / mutation-logger, per-run alternation, %s runs\n' "$RUNS"

# adversarial-review-gate: fast path (steady-state Write), slow no-op, block-parity
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"grimoires/loa/NOTES.md","content":"# notes\nbench line\n"}}' > "$PL"
bench_pair "advgate-write-benign(fast)" adversarial-review-gate.sh "$PL"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"notes.md","content":"sprint COMPLETED yesterday"}}' > "$PL"
bench_pair "advgate-completed-in-content(slow)" adversarial-review-gate.sh "$PL"
python3 - "$PL" <<'PYEOF'
import json, sys
payload = {"tool_name": "Write",
           "tool_input": {"file_path": "grimoires/big.md",
                          "content": "benchmark line without markers " * 32000}}
open(sys.argv[1], "w").write(json.dumps(payload))
PYEOF
bench_pair "advgate-1MB-benign(fast)" adversarial-review-gate.sh "$PL"

# spiral-skill-sentinel: fast path (every non-spiraling Skill call) + slow parity
printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"implement","args":"sprint-1"}}' > "$PL"
bench_pair "sentinel-skill-implement(fast)" spiral-skill-sentinel.sh "$PL"
printf '%s' '{"tool_name":"Skill","tool_input":{"skill":"spiraling"}}' > "$PL"
bench_pair "sentinel-skill-spiraling(slow)" spiral-skill-sentinel.sh "$PL"

# mutation-logger: benign (filter no-match), mutating (append), near-miss, 100KB
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls -la /tmp"},"tool_result":{"exit_code":0}}' > "$PL"
bench_pair "ml-benign(ls)" mutation-logger.sh "$PL"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"chore: bench\""},"tool_result":{"exit_code":0}}' > "$PL"
bench_pair "ml-mutating(git-commit)" mutation-logger.sh "$PL"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"echo git status of github digits"},"tool_result":{"exit_code":0}}' > "$PL"
bench_pair "ml-nearmiss" mutation-logger.sh "$PL"
python3 - "$PL" <<'PYEOF'
import json, sys
payload = {"tool_name": "Bash",
           "tool_input": {"command": "wordpad " * 12800},
           "tool_result": {"exit_code": 0}}
open(sys.argv[1], "w").write(json.dumps(payload))
PYEOF
bench_pair "ml-100KB-benign" mutation-logger.sh "$PL"
