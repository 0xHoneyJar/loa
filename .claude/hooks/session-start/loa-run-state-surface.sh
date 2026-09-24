#!/usr/bin/env bash
# =============================================================================
# loa-run-state-surface.sh — SessionStart hook + `/loa` line (cycle-125 FR-3,
# SDD D-3.3): tell the next session exactly how to resume.
#
#   loa-run-state-surface.sh [--root DIR] [--line]
#
# Prints to STDOUT (SessionStart injects stdout into the session as context):
#   Run: <file> <STATE> (<age>) → <command>
#       when a resumable run state exists — sprint-plan-state.json / state.json
#       HALTED or INTERRUPTED, or RUNNING with last activity older than 12 h;
#       simstim-state.json RUNNING older than 12 h.
#   Session limit reset at <reset_at> — resume available: <command>
#       when .run/session-limit-state.json has reset_at_epoch <= now.
# Prints NOTHING for a clean tree, a fresh RUNNING (a live run — the session
# title hook covers it), JACKED_OUT/COMPLETED, or anything unparseable.
# Exit 0 always; missing jq → silent exit 0. Observability, never a gate.
# `--line` is the same output for loa-status.sh (no SessionStart framing).
# =============================================================================
set -uo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HOOK_DIR}/../../.." && pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 && -d "${2:-}" ]] || exit 0; ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    --line) shift ;;
    *) shift ;;
  esac
done
command -v jq >/dev/null 2>&1 || exit 0
RUN_DIR="$ROOT/.run"
[[ -d "$RUN_DIR" ]] || exit 0
STALE_SECS=$(( 12 * 3600 ))
now=$(date +%s)

_san() { printf '%s' "${1-}" | tr -d '\000-\037\177' | cut -c1-80; }
_age() {  # ISO-8601 → "Nh"/"Nm"/"?"
  local t="$1" e
  [[ -n "$t" && "$t" != "null" ]] || { echo "?"; return; }
  e=$(date -u -d "$t" +%s 2>/dev/null) || { echo "?"; return; }
  local d=$(( now - e )); (( d < 0 )) && d=0
  if (( d >= 3600 )); then echo "$(( d / 3600 ))h"; else echo "$(( d / 60 ))m"; fi
}
_secs() { local e; e=$(date -u -d "$1" +%s 2>/dev/null) || { echo -1; return; }; echo $(( now - e )); }

surface() {  # file label state-jq ts-jq resume-command
  local f="$RUN_DIR/$1" label="$2" st ts
  [[ -f "$f" ]] || return 0
  jq -e . "$f" >/dev/null 2>&1 || return 0
  st=$(jq -r "$3 // empty" "$f" 2>/dev/null); ts=$(jq -r "$4 // empty" "$f" 2>/dev/null)
  st=$(_san "$st")
  case "$st" in
    HALTED|INTERRUPTED) echo "Run: $label $st ($(_age "$ts") ago) → $5" ;;
    RUNNING)
      local s; s=$(_secs "$ts")
      if [[ -n "$ts" && "$s" -ge $STALE_SECS ]]; then echo "Run: $label RUNNING but idle for $(_age "$ts") → $5 (state is stale; beads hold the task truth)"; fi ;;
  esac
}
surface sprint-plan-state.json sprint-plan '.state' '.timestamps.last_activity' '/run-resume'
surface state.json run '.state' '.timestamps.last_activity // .updated_at' '/run-resume'
surface simstim-state.json simstim '.status // .state' '.updated_at // .timestamps.last_activity' '/simstim --resume'

# Session-limit capture (session-limit-capture.sh): once the reset time has
# passed, say so — the UserPromptSubmit reminder is one-shot, this is the
# session-start companion.
sl="$RUN_DIR/session-limit-state.json"
if [[ -f "$sl" ]] && jq -e . "$sl" >/dev/null 2>&1; then
  reset_epoch=$(jq -r '.reset_at_epoch // empty' "$sl" 2>/dev/null)
  reset_iso=$(_san "$(jq -r '.reset_at // "unknown"' "$sl" 2>/dev/null)")
  if [[ "$reset_epoch" =~ ^[0-9]+$ ]] && (( reset_epoch <= now )); then
    echo "Session limit reset at $reset_iso — resume available: /run-resume (or /run-status to inspect)"
  fi
fi
exit 0
