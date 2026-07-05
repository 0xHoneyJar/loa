#!/usr/bin/env bash
# ab-pass8.sh — old-vs-new A/B for block-destructive-bash.sh across the four
# payload classes (benign / mutating / destructive-allowed / blocked).
# Per-run ALTERNATION (pass-3 lesson: powersave governor drift makes
# block-wise A/B lie). Each side runs in its own sandbox root with the real
# log-redactor copied in (the blocked path execs it).
set -u
export LC_ALL=C
REPO=${REPO:-/home/merlin/Documents/thj/code/loa}
OLDH=${OLDH:-/tmp/p8/old-hook.sh}
NEWH=${NEWH:-$REPO/.claude/hooks/safety/block-destructive-bash.sh}
WORK=${WORK:-/tmp/p8ab}
RUNS=${RUNS:-20}

rm -rf "$WORK"; mkdir -p "$WORK"
for side in old new; do
  mkdir -p "$WORK/$side/.claude/scripts/lib" "$WORK/$side/.run"
  cp "$REPO/.claude/scripts/lib/log-redactor.sh" "$WORK/$side/.claude/scripts/lib/"
done
cp "$OLDH" "$WORK/old/hook.sh"
cp "$NEWH" "$WORK/new/hook.sh"

mkpl() { jq -cn --arg c "$1" '{tool_input:{command:$c}}'; }

bench_pair() {  # bench_pair <label> <command-string>
  local label=$1 cmd=$2 side i t0 t1
  local pl="$WORK/payload.json"
  mkpl "$cmd" > "$pl"
  declare -A xs=( [old]="" [new]="" )
  for i in 1 2 3; do for side in old new; do
    ( cd "$WORK/$side" && env LOA_REPO_ROOT="$WORK/$side" bash hook.sh <"$pl" >/dev/null 2>&1 )
  done; done
  for ((i=0;i<RUNS;i++)); do
    for side in old new; do
      t0=${EPOCHREALTIME/./}
      ( cd "$WORK/$side" && env LOA_REPO_ROOT="$WORK/$side" bash hook.sh <"$pl" >/dev/null 2>&1 )
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

printf '# ab-pass8: block-destructive-bash old vs new, per-run alternation, %s runs\n' "$RUNS"
bench_pair "bash-benign(ls -la)"            'ls -la /tmp/loa-hookbench-1000'
bench_pair "bash-mutating(git commit)"      'git commit -m "chore(bench): update notes"'
bench_pair "bash-destructive(rm /tmp ok)"   'rm -rf /tmp/x'
bench_pair "bash-blocked(git push --force)" 'git push --force origin main'
# extra classes: guard-literal present but non-matching (worst benign), 100KB
bench_pair "bash-nearmiss(git commit w/push word)" 'git commit -m "do not push --force here"'
BIGPAD="$(printf 'word%099996d' 7)"
bench_pair "bash-100KB-benign"              "$BIGPAD"
