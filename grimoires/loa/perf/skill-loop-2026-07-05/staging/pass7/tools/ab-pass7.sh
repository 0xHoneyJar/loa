#!/usr/bin/env bash
# ab-pass7.sh — old-vs-new A/B for karpathy-surgical-diff-check.sh across
# state-file sizes. Per-run ALTERNATION (pass-3 lesson: powersave governor
# drift makes block-wise A/B lie). Each side runs in its own sandbox root
# (hooks derive REPO_ROOT from BASH_SOURCE, so cache/state side effects stay
# in the sandbox). The state file grows by one entry per invocation on each
# side — both sides age identically. New side steady state = warm FAST path.
set -u
REPO=/home/merlin/Documents/thj/code/loa
OLDH=${OLDH:-/tmp/p7ab/old-hook.sh}
NEWH=$REPO/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass7/karpathy-surgical-diff-check.sh
WORK=/tmp/p7ab
RUNS=${RUNS:-20}

mkgen() { local n=$1 out=$2 i; : > "$out"
  for ((i=1;i<=n;i++)); do
    printf '{"ts":"2026-07-05T07:00:00Z","tool":"Edit","file":"/home/merlin/Documents/thj/code/loa/src/file%d.md","lines_changed":7,"running_total":%d,"session_id":"merlin-20260705"}\n' \
      $((i % 400)) $((i*7))
  done >> "$out"
}

build() { # build <dir> <hook>
  local d=$1 h=$2
  rm -rf "$d"; mkdir -p "$d/root/.claude/hooks/quality" "$d/root/.run" \
    "$d/root/grimoires/loa/a2a/trajectory"
  cp "$h" "$d/root/.claude/hooks/quality/k.sh"
  printf 'karpathy_principles:\n  surgical_diff_warning: warn\n  diff_lines_per_task: 100\n' \
    > "$d/root/.loa.config.yaml"
}

PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.md","new_string":"a\nb\nc"}}'

bench_pair() { # bench_pair <label> <statefixture>
  local label=$1 sf=$2 side i t0 t1
  declare -A xs=( [old]="" [new]="" )
  for side in old new; do
    cp -f "$sf" "$WORK/$side/root/.run/karpathy-task-state.jsonl"
    rm -f "$WORK/$side/root/.run/perf-cache/karpathy-state.v1.agg"
  done
  # warmup 3 each (lets the new side build its cache)
  for i in 1 2 3; do for side in old new; do
    ( cd "$WORK/$side/root" && printf '%s' "$PAYLOAD" | \
        env ${KPGATE:+KARPATHY_STATE_CACHE_MIN=$KPGATE} bash .claude/hooks/quality/k.sh >/dev/null 2>&1 )
  done; done
  for ((i=0;i<RUNS;i++)); do
    for side in old new; do
      t0=${EPOCHREALTIME/./}
      ( cd "$WORK/$side/root" && printf '%s' "$PAYLOAD" | \
          env ${KPGATE:+KARPATHY_STATE_CACHE_MIN=$KPGATE} bash .claude/hooks/quality/k.sh >/dev/null 2>&1 )
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

mkdir -p "$WORK"
[[ -f "$OLDH" ]] || { echo "missing OLD hook at $OLDH" >&2; exit 1; }
build "$WORK/old" "$OLDH"
build "$WORK/new" "$NEWH"
for n in 500 5000 20000; do
  [[ -f "$WORK/state-$n.jsonl" ]] || mkgen "$n" "$WORK/state-$n.jsonl"
done
cp -f "$REPO/.run/karpathy-task-state.jsonl" "$WORK/state-real.jsonl"

printf '# ab-pass7: karpathy-surgical-diff-check old vs new, warn regime, per-run alternation\n'
printf '# default gate (production, KARPATHY_STATE_CACHE_MIN=262144): <256KB rows take the original path\n'
KPGATE="" bench_pair "n=500" "$WORK/state-500.jsonl"
KPGATE="" bench_pair "n=5000" "$WORK/state-5000.jsonl"
KPGATE="" bench_pair "n=20000" "$WORK/state-20000.jsonl"
KPGATE="" bench_pair "n=real($(grep -c '' "$WORK/state-real.jsonl"))" "$WORK/state-real.jsonl"
printf '# forced-warm rows (gate=0): the warm-path floor below the gate, for the record\n'
KPGATE=0 bench_pair "n=500-FORCEDWARM" "$WORK/state-500.jsonl"
KPGATE=0 bench_pair "n=real-FORCEDWARM($(grep -c '' "$WORK/state-real.jsonl"))" "$WORK/state-real.jsonl"

# delta-path scenario: an external entry lands between calls (cross-session)
bench_delta() {
  local label=$1 sf=$2 side i t0 t1
  declare -A xs=( [old]="" [new]="" )
  for side in old new; do
    cp -f "$sf" "$WORK/$side/root/.run/karpathy-task-state.jsonl"
    rm -f "$WORK/$side/root/.run/perf-cache/karpathy-state.v1.agg"
  done
  for i in 1 2 3; do for side in old new; do
    ( cd "$WORK/$side/root" && printf '%s' "$PAYLOAD" | env ${KPGATE:+KARPATHY_STATE_CACHE_MIN=$KPGATE} bash .claude/hooks/quality/k.sh >/dev/null 2>&1 )
  done; done
  for ((i=0;i<RUNS;i++)); do
    for side in old new; do
      printf '{"ts":"t","tool":"Edit","file":"/ext/x.md","lines_changed":2,"running_total":0,"session_id":"e"}\n' \
        >> "$WORK/$side/root/.run/karpathy-task-state.jsonl"
      t0=${EPOCHREALTIME/./}
      ( cd "$WORK/$side/root" && printf '%s' "$PAYLOAD" | env ${KPGATE:+KARPATHY_STATE_CACHE_MIN=$KPGATE} bash .claude/hooks/quality/k.sh >/dev/null 2>&1 )
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
bench_delta "n=5000+delta" "$WORK/state-5000.jsonl"

# cold-path (cache deleted before every run — the miss penalty)
bench_cold() {
  local label=$1 sf=$2 side i t0 t1
  declare -A xs=( [old]="" [new]="" )
  for side in old new; do
    cp -f "$sf" "$WORK/$side/root/.run/karpathy-task-state.jsonl"
  done
  for ((i=0;i<RUNS;i++)); do
    for side in old new; do
      rm -f "$WORK/$side/root/.run/perf-cache/karpathy-state.v1.agg"
      t0=${EPOCHREALTIME/./}
      ( cd "$WORK/$side/root" && printf '%s' "$PAYLOAD" | env ${KPGATE:+KARPATHY_STATE_CACHE_MIN=$KPGATE} bash .claude/hooks/quality/k.sh >/dev/null 2>&1 )
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
bench_cold "n=500-COLD" "$WORK/state-500.jsonl"
