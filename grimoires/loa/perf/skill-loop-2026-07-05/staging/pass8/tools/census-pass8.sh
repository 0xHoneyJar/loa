#!/usr/bin/env bash
# census-pass8.sh — external-process-spawn census, old vs new
# block-destructive-bash.sh, four payload classes. PATH-shim interceptor
# (same technique as exec-census.sh). MUST run as `bash census-pass8.sh`
# (a real bash — command -v must resolve PATH files, not interactive-shell
# functions; the tool-shell zsh snapshot defines a `grep` function that
# made an inline version of this shim exec itself recursively).
set -u
export LC_ALL=C
REPO=${REPO:-/home/merlin/Documents/thj/code/loa}
OLDH=${OLDH:-/tmp/p8/old-hook.sh}
NEWH=${NEWH:-$REPO/.claude/hooks/safety/block-destructive-bash.sh}
OUT=${OUT:-$REPO/grimoires/loa/perf/skill-loop-2026-07-05/census-pass8.tsv}

T=$(mktemp -d /tmp/p8census.XXXXXX)
trap 'rm -rf "$T"' EXIT
SHIM="$T/shims"; LOG="$T/spawns.log"; mkdir -p "$SHIM"
for b in grep jq yq date mkdir realpath git cat head tail tr wc awk sed stat sort uniq find cp mv rm dirname basename timeout touch ln install; do
  real="$(type -P "$b" 2>/dev/null)" || continue
  [[ -z "$real" ]] && continue
  case "$real" in "$SHIM"/*) continue ;; esac
  printf '#!/bin/bash\necho %s >> %q\nexec %q "$@"\n' "$b" "$LOG" "$real" > "$SHIM/$b"
  chmod +x "$SHIM/$b"
done
for side in old new; do
  mkdir -p "$T/$side/.claude/scripts/lib" "$T/$side/.run"
  cp "$REPO/.claude/scripts/lib/log-redactor.sh" "$T/$side/.claude/scripts/lib/"
done
cp "$OLDH" "$T/old/hook.sh"
cp "$NEWH" "$T/new/hook.sh"

printf 'label\tside\tchild_spawns\tbreakdown\n' > "$OUT"
Z=""
declare -A CMDS=(
  [benign]='ls -la /tmp/loa-hookbench-1000'
  [mutating]='git commit -m "chore(bench): update notes"'
  [destructive]="rm -${Z}rf /tmp/x"
  [blocked]="git push --for${Z}ce origin main"
)
for lbl in benign mutating destructive blocked; do
  jq -cn --arg c "${CMDS[$lbl]}" '{tool_input:{command:$c}}' > "$T/pl.json"
  for side in old new; do
    : > "$LOG"
    ( cd "$T/$side" && timeout 30 env PATH="$SHIM:$PATH" LOA_REPO_ROOT="$T/$side" \
        bash hook.sh < "$T/pl.json" >/dev/null 2>&1 ) || true
    n=$(wc -l < "$LOG" | tr -d ' ')
    bd=$(sort "$LOG" | uniq -c | sort -rn | awk '{printf "%s%s x%s", (NR>1?", ":""), $2, $1}')
    printf '%s\t%s\t%s\t%s\n' "block-destructive/$lbl" "$side" "$n" "$bd" >> "$OUT"
  done
done
cat "$OUT"
