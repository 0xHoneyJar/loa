#!/usr/bin/env bash
# pass-6 interleaved A/B: per-run alternation old vs new (pass-3/4/5
# precedent — neutralizes powersave-governor drift). 20 measured runs/side.
# WARM rows: cache pre-seeded once, never reset (production steady state).
# COLD rows: perf-cache wiped in prep before EVERY run (miss penalty).
set -euo pipefail
export LC_ALL=C

PERF=/home/merlin/Documents/thj/code/loa/grimoires/loa/perf/skill-loop-2026-07-05
STAGE=$PERF/staging/pass6
TSV="${1:-$PERF/ab-pass6.tsv}"
RUNS=20 WARMUP=3

M="$("$PERF/bench-env.sh")"
H="$M/.claude/hooks"
# OLD bytes from git HEAD (pass-5 state) — the working tree may already
# hold the installed pass-6 versions.
mkdir -p "$M/.claude/hooks-old/safety" "$M/.claude/hooks-old/quality"
git -C /home/merlin/Documents/thj/code/loa show HEAD:.claude/hooks/safety/zone-write-guard.sh \
  > "$M/.claude/hooks-old/safety/zone-write-guard.sh"
git -C /home/merlin/Documents/thj/code/loa show HEAD:.claude/hooks/quality/karpathy-surgical-diff-check.sh \
  > "$M/.claude/hooks-old/quality/karpathy-surgical-diff-check.sh"
cp "$STAGE/zone-write-guard.sh"             "$H/safety/zone-write-guard.sh"
cp "$STAGE/karpathy-surgical-diff-check.sh" "$H/quality/karpathy-surgical-diff-check.sh"
chmod +x "$H/safety/zone-write-guard.sh" "$H/quality/karpathy-surgical-diff-check.sh" \
         "$M/.claude/hooks-old/safety/zone-write-guard.sh" \
         "$M/.claude/hooks-old/quality/karpathy-surgical-diff-check.sh"

printf 'combo\tversion\truns\tmin_ms\tmean_ms\tp95_ms\tmax_ms\n' > "$TSV"

declare -a S_OLD S_NEW

one() {  # <version> <payload> <prep> -- cmd...
  local ver="$1" pl="$2" prep="$3"; shift 3
  shift  # --
  [[ -z "$prep" ]] || ( cd "$M" && eval "$prep" ) > /dev/null 2>&1
  local t0 t1
  t0=$EPOCHREALTIME
  ( cd "$M" && "$@" > /dev/null 2>&1 < "$M/payloads/$pl" ) || true
  t1=$EPOCHREALTIME
  local ms
  ms=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f",(b-a)*1000}')
  if [[ "$ver" == old ]]; then S_OLD+=("$ms"); else S_NEW+=("$ms"); fi
}

stats() {  # <combo> <version> <samples...>
  local combo="$1" ver="$2"; shift 2
  printf '%s\n' "$@" | sort -g | awk -v c="$combo" -v v="$ver" -v n="$#" '
    { s[NR]=$1; sum+=$1 }
    END { p=int(0.95*n+0.999999); if(p<1)p=1; if(p>n)p=n
          printf "%s\t%s\t%d\t%.3f\t%.3f\t%.3f\t%.3f\n", c, v, n, s[1], sum/n, s[p], s[n] }'
}

ab() {  # <combo> <payload> <once-prep> <old-prep> <new-prep> <old-rel> <new-rel>
  local combo="$1" pl="$2" once="$3" oprep="$4" nprep="$5" oldc="$6" newc="$7"
  [[ -z "$once" ]] || ( cd "$M" && eval "$once" ) > /dev/null 2>&1
  S_OLD=(); S_NEW=()
  local i
  for ((i=0;i<WARMUP;i++)); do
    one old "$pl" "$oprep" -- "$M/$oldc"
    one new "$pl" "$nprep" -- "$M/$newc"
  done
  S_OLD=(); S_NEW=()
  for ((i=0;i<RUNS;i++)); do
    one old "$pl" "$oprep" -- "$M/$oldc"
    one new "$pl" "$nprep" -- "$M/$newc"
  done
  stats "$combo" old "${S_OLD[@]}" | tee -a "$TSV"
  stats "$combo" new "${S_NEW[@]}" | tee -a "$TSV"
}

ZOLD=.claude/hooks-old/safety/zone-write-guard.sh
ZNEW=.claude/hooks/safety/zone-write-guard.sh
KOLD=.claude/hooks-old/quality/karpathy-surgical-diff-check.sh
KNEW=.claude/hooks/quality/karpathy-surgical-diff-check.sh
KSEED="cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl"
ZWARM="rm -rf .run/perf-cache && $ZNEW < payloads/write-grimoires.json"
KWARM="rm -rf .run/perf-cache && $KSEED && $KNEW < payloads/write-grimoires.json"

# WARM steady state (cache seeded once; old side unaffected by it)
ab "zwg/write-grim-warm"   write-grimoires.json "$ZWARM" "" ""        "$ZOLD" "$ZNEW"
ab "zwg/write-claude-warm" write-claude.json    "$ZWARM" "" ""        "$ZOLD" "$ZNEW"
ab "zwg/edit-tests-warm"   edit-tests.json      "$ZWARM" "" ""        "$ZOLD" "$ZNEW"
ab "kp/write-grim-warn-warm" write-grimoires.json "$KWARM" "$KSEED" "$KSEED" "$KOLD" "$KNEW"
ab "kp/edit-tests-warn-warm" edit-tests.json      "$KWARM" "$KSEED" "$KSEED" "$KOLD" "$KNEW"

# COLD (cache wiped before every new-side run — miss penalty; old prep wipes
# too so both sides pay the same rm)
ab "zwg/write-grim-cold" write-grimoires.json "" \
   "rm -rf .run/perf-cache" "rm -rf .run/perf-cache" "$ZOLD" "$ZNEW"
ab "kp/write-grim-warn-cold" write-grimoires.json "" \
   "rm -rf .run/perf-cache && $KSEED" "rm -rf .run/perf-cache && $KSEED" "$KOLD" "$KNEW"

echo ""
echo "ab-pass6 written to $TSV"
