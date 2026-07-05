#!/usr/bin/env bash
# =============================================================================
# pass-6 spawn census: old vs staged (cold cache / warm cache) for
# zone-write-guard + karpathy-surgical-diff-check. PATH-shim interceptor
# (same method/limitations as exec-census.sh — ptrace unavailable).
# =============================================================================
set -euo pipefail
export LC_ALL=C

PERF=/home/merlin/Documents/thj/code/loa/grimoires/loa/perf/skill-loop-2026-07-05
STAGE=$PERF/staging/pass6
CENSUS="${1:-$PERF/census-pass6.tsv}"

M="$("$PERF/bench-env.sh")"
H="$M/.claude/hooks"
# old copies at the SAME tree depth (both hooks derive their root from
# their own location: hooks-old/safety/../../.. == $M). OLD bytes come from
# git HEAD (the pass-5 state) — the working tree may already hold the
# installed pass-6 versions.
mkdir -p "$M/.claude/hooks-old/safety" "$M/.claude/hooks-old/quality"
git -C /home/merlin/Documents/thj/code/loa show HEAD:.claude/hooks/safety/zone-write-guard.sh \
  > "$M/.claude/hooks-old/safety/zone-write-guard.sh"
git -C /home/merlin/Documents/thj/code/loa show HEAD:.claude/hooks/quality/karpathy-surgical-diff-check.sh \
  > "$M/.claude/hooks-old/quality/karpathy-surgical-diff-check.sh"
# overlay staged versions
cp "$STAGE/zone-write-guard.sh"              "$H/safety/zone-write-guard.sh"
cp "$STAGE/karpathy-surgical-diff-check.sh"  "$H/quality/karpathy-surgical-diff-check.sh"
chmod +x "$H/safety/zone-write-guard.sh" "$H/quality/karpathy-surgical-diff-check.sh" \
         "$M/.claude/hooks-old/safety/zone-write-guard.sh" \
         "$M/.claude/hooks-old/quality/karpathy-surgical-diff-check.sh"

TRACE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loa-census6.XXXXXX")"
trap 'rm -rf "$TRACE_DIR"' EXIT
SHIM_DIR="$TRACE_DIR/shims"
SPAWN_LOG="$TRACE_DIR/spawns.log"
mkdir -p "$SHIM_DIR"

BINS=(grep jq yq date mkdir realpath git cat head tail tr wc awk sed stat
      sort uniq find cp mv rm dirname basename timeout touch ln install)
for b in "${BINS[@]}"; do
  real="$(command -v "$b" 2>/dev/null)" || continue
  case "$real" in "$SHIM_DIR"/*) continue ;; esac
  printf '#!/bin/bash\necho %s >> %q\nexec %q "$@"\n' "$b" "$SPAWN_LOG" "$real" > "$SHIM_DIR/$b"
  chmod +x "$SHIM_DIR/$b"
done

printf 'label\tchild_spawns\tbreakdown\n' > "$CENSUS"

census() {  # census <label> <payload> [PREP::cmd] -- cmd...
  local lbl="$1" pl="$2"; shift 2
  local prep=""
  while [[ "$1" != "--" ]]; do
    case "$1" in PREP::*) prep="${1#PREP::}" ;; esac
    shift
  done
  shift
  [[ -z "$prep" ]] || ( cd "$M" && eval "$prep" ) > /dev/null 2>&1
  : > "$SPAWN_LOG"
  ( cd "$M" && env "PATH=$SHIM_DIR:$PATH" "$@" < "$M/payloads/$pl" > /dev/null 2>&1 ) || true
  local n breakdown
  n=$(wc -l < "$SPAWN_LOG" | tr -d ' ')
  breakdown=$(sort "$SPAWN_LOG" | uniq -c | sort -rn | awk '{printf "%s%s x%s", (NR>1?", ":""), $2, $1}')
  printf '%s\t%s\t%s\n' "$lbl" "$n" "$breakdown" >> "$CENSUS"
  printf '%-52s spawns=%-4s %s\n' "$lbl" "$n" "$breakdown"
}

NOCACHE="rm -rf .run/perf-cache"
WARMZ="rm -rf .run/perf-cache && .claude/hooks/safety/zone-write-guard.sh < payloads/write-grimoires.json"
WARMK="rm -rf .run/perf-cache && cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl && .claude/hooks/quality/karpathy-surgical-diff-check.sh < payloads/write-grimoires.json"

census "zwg/write-grim OLD"        write-grimoires.json "PREP::$NOCACHE" -- "$M/.claude/hooks-old/safety/zone-write-guard.sh"
census "zwg/write-grim NEW-cold"   write-grimoires.json "PREP::$NOCACHE" -- "$H/safety/zone-write-guard.sh"
census "zwg/write-grim NEW-warm"   write-grimoires.json "PREP::$WARMZ"   -- "$H/safety/zone-write-guard.sh"
census "zwg/write-claude OLD"      write-claude.json    "PREP::$NOCACHE" -- "$M/.claude/hooks-old/safety/zone-write-guard.sh"
census "zwg/write-claude NEW-warm" write-claude.json    "PREP::$WARMZ"   -- "$H/safety/zone-write-guard.sh"
census "zwg/edit-tests OLD"        edit-tests.json      "PREP::$NOCACHE" -- "$M/.claude/hooks-old/safety/zone-write-guard.sh"
census "zwg/edit-tests NEW-warm"   edit-tests.json      "PREP::$WARMZ"   -- "$H/safety/zone-write-guard.sh"

census "kp/write-grim-warn OLD"      write-grimoires.json "PREP::$NOCACHE && cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl" -- "$M/.claude/hooks-old/quality/karpathy-surgical-diff-check.sh"
census "kp/write-grim-warn NEW-cold" write-grimoires.json "PREP::$NOCACHE && cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl" -- "$H/quality/karpathy-surgical-diff-check.sh"
census "kp/write-grim-warn NEW-warm" write-grimoires.json "PREP::$WARMK && cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl" -- "$H/quality/karpathy-surgical-diff-check.sh"
census "kp/edit-tests-warn OLD"      edit-tests.json      "PREP::$NOCACHE && cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl" -- "$M/.claude/hooks-old/quality/karpathy-surgical-diff-check.sh"
census "kp/edit-tests-warn NEW-warm" edit-tests.json      "PREP::$WARMK && cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl" -- "$H/quality/karpathy-surgical-diff-check.sh"

echo ""
echo "census written to $CENSUS"
