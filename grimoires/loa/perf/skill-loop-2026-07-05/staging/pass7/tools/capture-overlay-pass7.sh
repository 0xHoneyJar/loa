#!/usr/bin/env bash
# =============================================================================
# golden/capture.sh — capture & verify golden hook outputs (behavior proof)
# =============================================================================
# For each hook x payload combo, runs the LIVE hook once inside a fresh
# bench-env mirror, captures stdout + stderr + exit code into one
# <combo>.golden file, NORMALIZES environment-dependent tokens (see
# golden/README.md), and checksums the set.
#
# Usage:
#   capture.sh            # (re)capture goldens + write golden_checksums.txt
#   capture.sh --verify   # recapture to a temp dir and diff/sha256sum -c
#                         # against the committed goldens — exits non-zero on
#                         # ANY behavior drift. Run after every optimization.
#
# Normalization (MUST stay in sync with golden/README.md):
#   mirror root path  -> __ROOT__
#   ISO-8601 UTC ts   -> __TS__
#   bare dates        -> __DATE__
# =============================================================================

set -euo pipefail
export LC_ALL=C

GOLDEN_DIR="/home/merlin/Documents/thj/code/loa/grimoires/loa/perf/skill-loop-2026-07-05/golden"
PERF_DIR="$(cd "$GOLDEN_DIR/.." && pwd)"
MODE="capture"
[[ "${1:-}" == "--verify" ]] && MODE="verify"

OUT_DIR="$GOLDEN_DIR"
if [[ "$MODE" == "verify" ]]; then
  OUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loa-golden-verify.XXXXXX")"
  trap 'rm -rf "$OUT_DIR"' EXIT
fi

M="$("$PERF_DIR/bench-env.sh")"
# pass-7 staged overlay (pre-install verification)
cp "/home/merlin/Documents/thj/code/loa/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass7/karpathy-surgical-diff-check.sh" "$M/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
chmod +x "$M/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
H="$M/.claude/hooks"

normalize() {
  sed -e "s|$M|__ROOT__|g" \
      -e 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z/__TS__/g' \
      -e 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/__DATE__/g'
}

cap() {  # cap <name> <payload|-> [ENV=VAL...] [PREP::cmd] -- cmd...
  local name="$1" pl="$2"; shift 2
  local envs=() prep=""
  while [[ "$1" != "--" ]]; do
    case "$1" in
      PREP::*) prep="${1#PREP::}" ;;
      *) envs+=( "$1" ) ;;
    esac
    shift
  done
  shift
  [[ -z "$prep" ]] || ( cd "$M" && eval "$prep" )
  local rc=0 so se
  so="$(mktemp)"; se="$(mktemp)"
  if [[ "$pl" == "-" ]]; then
    ( cd "$M" && env "${envs[@]}" "$@" > "$so" 2> "$se" < /dev/null ) || rc=$?
  else
    ( cd "$M" && env "${envs[@]}" "$@" > "$so" 2> "$se" < "$M/payloads/$pl" ) || rc=$?
  fi
  {
    echo "COMBO: $name"
    echo "EXIT: $rc"
    echo "--- STDOUT ---"
    normalize < "$so"
    echo "--- STDERR ---"
    normalize < "$se"
  } > "$OUT_DIR/$name.golden"
  rm -f "$so" "$se"
  echo "captured $name (exit=$rc)"
}

# --- combos (keep in lockstep with run-matrix.sh production rows) ------------
cap "block-destructive__bash-benign"      bash-benign.json      -- "$H/safety/block-destructive-bash.sh"
cap "block-destructive__bash-mutating"    bash-mutating.json    -- "$H/safety/block-destructive-bash.sh"
cap "block-destructive__bash-destructive" bash-destructive.json -- "$H/safety/block-destructive-bash.sh"
cap "block-destructive__bash-blocked"     bash-blocked.json     -- "$H/safety/block-destructive-bash.sh"
cap "team-role-guard__bash-benign"        bash-benign.json      -- "$H/safety/team-role-guard.sh"
cap "team-role-guard__bash-mutating-TEAM" bash-mutating.json    LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-role-guard.sh"
cap "mutation-logger__bash-benign"        bash-benign.json      -- "$H/audit/mutation-logger.sh"
cap "mutation-logger__bash-mutating"      bash-mutating.json    -- "$H/audit/mutation-logger.sh"
cap "team-role-guard-write__write-grim"   write-grimoires.json  -- "$H/safety/team-role-guard-write.sh"
cap "team-role-guard-write__write-grim-TEAM" write-grimoires.json LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-role-guard-write.sh"
cap "team-role-guard-write__write-claude-TEAM" write-claude.json LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-role-guard-write.sh"
cap "spiral-dispatch-guard__write-grim"   write-grimoires.json  -- "$H/safety/spiral-dispatch-guard.sh"
cap "zone-write-guard__write-grim"        write-grimoires.json  -- "$H/safety/zone-write-guard.sh"
cap "zone-write-guard__write-claude"      write-claude.json     -- "$H/safety/zone-write-guard.sh"
cap "zone-write-guard__edit-tests"        edit-tests.json       -- "$H/safety/zone-write-guard.sh"
cap "adversarial-gate__write-grim"        write-grimoires.json  -- "$H/safety/adversarial-review-gate.sh"
cap "adversarial-gate__write-completed"   write-completed.json  -- "$H/safety/adversarial-review-gate.sh"
cap "write-mutation-logger__write-grim"   write-grimoires.json  -- "$H/audit/write-mutation-logger.sh"
cap "write-mutation-logger__edit-tests"   edit-tests.json       -- "$H/audit/write-mutation-logger.sh"
cap "karpathy-diff__write-grim-fresh"     write-grimoires.json  "PREP::: > .run/karpathy-task-state.jsonl" -- "$H/quality/karpathy-surgical-diff-check.sh"
cap "karpathy-diff__write-grim-warn"      write-grimoires.json  "PREP::cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl" -- "$H/quality/karpathy-surgical-diff-check.sh"
cap "karpathy-diff__edit-tests-warn"      edit-tests.json       "PREP::cp fixtures/karpathy-seed.jsonl .run/karpathy-task-state.jsonl" -- "$H/quality/karpathy-surgical-diff-check.sh"
cap "team-skill-guard__skill-implement"   skill-implement.json  -- "$H/safety/team-skill-guard.sh"
cap "team-skill-guard__skill-implement-TEAM" skill-implement.json LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-skill-guard.sh"
cap "spiral-skill-sentinel__skill-implement" skill-implement.json -- "$H/safety/spiral-skill-sentinel.sh"
cap "run-mode-stop-guard__stop-idle"      stop-idle.json        -- "$H/safety/run-mode-stop-guard.sh"
cap "settings-cleanup__small"             stop-idle.json        -- "$H/hygiene/settings-cleanup.sh"
cap "settings-cleanup__large"             stop-idle.json        "PREP::cp fixtures/settings.local.large.json .claude/settings.local.json" -- "$H/hygiene/settings-cleanup.sh"
cap "post-compact-reminder__no-marker"    prompt-submit.json    "HOME=$M" "PROJECT_ROOT=$M" -- "$H/post-compact-reminder.sh"
cap "post-compact-reminder__marker"       prompt-submit.json    "HOME=$M" "PROJECT_ROOT=$M" "PREP::cp fixtures/compact-pending .run/compact-pending" -- "$H/post-compact-reminder.sh"
cap "cleanup-context__no-context-dir"     skill-implement.json  "LOA_CONTEXT_DIR=$M/absent-context" -- "$M/.claude/scripts/cleanup-context.sh" --prompt
cap "cleanup-context__full-archive"       skill-implement.json  \
  "LOA_CONTEXT_DIR=$M/grimoires/loa/context" \
  "LOA_LEDGER=$M/grimoires/loa/ledger.json" \
  "LOA_ARCHIVE_BASE=$M/grimoires/loa/archive" \
  "PREP::rm -rf grimoires/loa/context grimoires/loa/archive && mkdir -p grimoires/loa/context grimoires/loa/archive && cp -r fixtures/context/. grimoires/loa/context/" \
  -- setsid "$M/.claude/scripts/cleanup-context.sh" --prompt

# --- checksums / verification -------------------------------------------------
cd "$OUT_DIR"
if [[ "$MODE" == "capture" ]]; then
  sha256sum ./*.golden > golden_checksums.txt
  echo ""
  echo "golden_checksums.txt written ($(wc -l < golden_checksums.txt) combos)"
else
  status=0
  for f in "$GOLDEN_DIR"/*.golden; do
    base="$(basename "$f")"
    if ! diff -u "$f" "$OUT_DIR/$base" > /dev/null 2>&1; then
      echo "DRIFT: $base" >&2
      diff -u "$f" "$OUT_DIR/$base" | head -40 >&2 || true
      status=1
    fi
  done
  if (( status == 0 )); then
    echo ""
    echo "VERIFY OK: all $(ls "$GOLDEN_DIR"/*.golden | wc -l) golden outputs match"
  else
    echo ""
    echo "VERIFY FAILED: behavior drift detected — see diffs above" >&2
  fi
  exit "$status"
fi
