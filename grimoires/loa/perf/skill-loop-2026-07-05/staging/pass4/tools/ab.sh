#!/usr/bin/env bash
# pass-4 interleaved A/B: per-run alternation old vs new (pass-3 precedent —
# neutralizes powersave-governor drift). 20 measured runs per side.
set -euo pipefail
export LC_ALL=C

PERF=/home/merlin/Documents/thj/code/loa/grimoires/loa/perf/skill-loop-2026-07-05
OLD=/tmp/p4ab/old
TSV="${1:-$PERF/ab-pass4.tsv}"
RUNS=20 WARMUP=3

M="$("$PERF/bench-env.sh")"
# old copies at the SAME tree depth (karpathy derives REPO_ROOT from its
# own location: hooks-old/quality/../../.. == $M, same as hooks/quality)
mkdir -p "$M/.claude/hooks-old/hygiene" "$M/.claude/hooks-old/audit" \
         "$M/.claude/hooks-old/quality" "$M/.claude/scripts-old"
cp "$OLD/settings-cleanup.sh"             "$M/.claude/hooks-old/hygiene/"
cp "$OLD/post-compact-reminder.sh"        "$M/.claude/hooks-old/"
cp "$OLD/mutation-logger.sh"              "$M/.claude/hooks-old/audit/"
cp "$OLD/write-mutation-logger.sh"        "$M/.claude/hooks-old/audit/"
cp "$OLD/karpathy-surgical-diff-check.sh" "$M/.claude/hooks-old/quality/"
cp "$OLD/cleanup-context.sh"              "$M/.claude/scripts-old/"
# scripts-old depth: cleanup-context uses env-provided paths only — depth-safe.
chmod +x "$M"/.claude/hooks-old/*.sh "$M"/.claude/hooks-old/*/*.sh "$M"/.claude/scripts-old/*.sh

printf 'combo\tversion\truns\tmin_ms\tmean_ms\tp95_ms\tmax_ms\n' > "$TSV"

declare -a S_OLD S_NEW

one() {  # <version> <payload|-> <prep> <envs...> -- cmd...
  local ver="$1" pl="$2" prep="$3"; shift 3
  local envs=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  [[ -z "$prep" ]] || ( cd "$M" && eval "$prep" ) > /dev/null 2>&1
  local t0 t1
  if [[ "$pl" == "-" ]]; then
    t0=$EPOCHREALTIME
    ( cd "$M" && env "${envs[@]}" "$@" > /dev/null 2>&1 < /dev/null ) || true
    t1=$EPOCHREALTIME
  else
    t0=$EPOCHREALTIME
    ( cd "$M" && env "${envs[@]}" "$@" > /dev/null 2>&1 < "$M/payloads/$pl" ) || true
    t1=$EPOCHREALTIME
  fi
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

ab() {  # <combo> <payload|-> <prep> <envs...> -- <old-cmd-rel> <new-cmd-rel>
  local combo="$1" pl="$2" prep="$3"; shift 3
  local envs=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  local oldc="$1" newc="$2"
  S_OLD=(); S_NEW=()
  for ((i=0;i<WARMUP;i++)); do
    one old "$pl" "$prep" ${envs[@]+"${envs[@]}"} -- "$M/$oldc"
    one new "$pl" "$prep" ${envs[@]+"${envs[@]}"} -- "$M/$newc"
  done
  S_OLD=(); S_NEW=()
  for ((i=0;i<RUNS;i++)); do
    one old "$pl" "$prep" ${envs[@]+"${envs[@]}"} -- "$M/$oldc"
    one new "$pl" "$prep" ${envs[@]+"${envs[@]}"} -- "$M/$newc"
  done
  stats "$combo" old "${S_OLD[@]}" | tee -a "$TSV"
  stats "$combo" new "${S_NEW[@]}" | tee -a "$TSV"
}

ab "settings-cleanup/large" stop-idle.json "cp fixtures/settings.local.large.json .claude/settings.local.json" \
   -- .claude/hooks-old/hygiene/settings-cleanup.sh .claude/hooks/hygiene/settings-cleanup.sh

ab "settings-cleanup/small" stop-idle.json "cp fixtures/settings.local.small.json .claude/settings.local.json" \
   -- .claude/hooks-old/hygiene/settings-cleanup.sh .claude/hooks/hygiene/settings-cleanup.sh

ab "post-compact/marker" prompt-submit.json "cp fixtures/compact-pending .run/compact-pending" \
   "HOME=$M" "PROJECT_ROOT=$M" \
   -- .claude/hooks-old/post-compact-reminder.sh .claude/hooks/post-compact-reminder.sh

ab "post-compact/no-marker" prompt-submit.json "rm -f .run/compact-pending .local/state/loa-compact/compact-pending" \
   "HOME=$M" "PROJECT_ROOT=$M" \
   -- .claude/hooks-old/post-compact-reminder.sh .claude/hooks/post-compact-reminder.sh

ab "mutation-logger/mutating" bash-mutating.json "" \
   -- .claude/hooks-old/audit/mutation-logger.sh .claude/hooks/audit/mutation-logger.sh

ab "mutation-logger/benign" bash-benign.json "" \
   -- .claude/hooks-old/audit/mutation-logger.sh .claude/hooks/audit/mutation-logger.sh

ab "write-mutation-logger/write-grim" write-grimoires.json "" \
   -- .claude/hooks-old/audit/write-mutation-logger.sh .claude/hooks/audit/write-mutation-logger.sh

ab "karpathy/write-grim-warn" write-grimoires.json "cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl" \
   -- .claude/hooks-old/quality/karpathy-surgical-diff-check.sh .claude/hooks/quality/karpathy-surgical-diff-check.sh

CCPREP="rm -rf grimoires/loa/context grimoires/loa/archive && mkdir -p grimoires/loa/context grimoires/loa/archive && cp -r fixtures/context/. grimoires/loa/context/"
ab_cc() {  # cleanup-context needs setsid + args
  local combo="$1" prep="$2" ctx="$3" oldc="$4" newc="$5"
  S_OLD=(); S_NEW=()
  for ((i=0;i<WARMUP;i++)); do
    one old skill-implement.json "$prep" "LOA_CONTEXT_DIR=$ctx" "LOA_LEDGER=$M/grimoires/loa/ledger.json" "LOA_ARCHIVE_BASE=$M/grimoires/loa/archive" -- setsid "$M/$oldc" --prompt
    one new skill-implement.json "$prep" "LOA_CONTEXT_DIR=$ctx" "LOA_LEDGER=$M/grimoires/loa/ledger.json" "LOA_ARCHIVE_BASE=$M/grimoires/loa/archive" -- setsid "$M/$newc" --prompt
  done
  S_OLD=(); S_NEW=()
  for ((i=0;i<RUNS;i++)); do
    one old skill-implement.json "$prep" "LOA_CONTEXT_DIR=$ctx" "LOA_LEDGER=$M/grimoires/loa/ledger.json" "LOA_ARCHIVE_BASE=$M/grimoires/loa/archive" -- setsid "$M/$oldc" --prompt
    one new skill-implement.json "$prep" "LOA_CONTEXT_DIR=$ctx" "LOA_LEDGER=$M/grimoires/loa/ledger.json" "LOA_ARCHIVE_BASE=$M/grimoires/loa/archive" -- setsid "$M/$newc" --prompt
  done
  stats "$combo" old "${S_OLD[@]}" | tee -a "$TSV"
  stats "$combo" new "${S_NEW[@]}" | tee -a "$TSV"
}
ab_cc "cleanup-context/full-archive" "$CCPREP" "$M/grimoires/loa/context" .claude/scripts-old/cleanup-context.sh .claude/scripts/cleanup-context.sh
ab_cc "cleanup-context/no-context-dir" "" "$M/absent-context" .claude/scripts-old/cleanup-context.sh .claude/scripts/cleanup-context.sh

echo ""
echo "ab-pass4 written to $TSV"
