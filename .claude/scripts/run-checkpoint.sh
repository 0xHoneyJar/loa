#!/usr/bin/env bash
# =============================================================================
# run-checkpoint.sh — task-granular checkpoint in .run/sprint-plan-state.json
# (cycle-125 FR-3, SDD D-3.2). Beads are the task ledger; the checkpoint is a
# HINT mirrored into state for visibility and fast resume.
#
#   run-checkpoint.sh write --sprint sprint-N --phase PHASE [--task BEAD-ID] [--file F]
#       Atomically sets .schema_version = 2, .checkpoint = {sprint, task, phase, ts}
#       and .timestamps.last_activity = ts: jq → F.tmp.$$ → mv -f, under flock
#       on F.lock. F must already exist (a run in progress). Exit 0 · 2 usage /
#       no run · 3 write failed (the previous file is untouched).
#   run-checkpoint.sh read [--file F] [--json]
#       Prints the checkpoint when it is trustworthy: parses, and when a task
#       is named, `br show <task> --json` reports it closed (a checkpoint that
#       names an open or unknown bead is DISCARDED with a logged line — beads
#       remain the recovery source). schema_version 1 / no checkpoint → prints
#       "sprint granularity". Exit 0 always when F exists; 2 when it does not.
#
# Default F: $LOA_RUN_DIR/sprint-plan-state.json, else <repo>/.run/sprint-plan-state.json.
# Readers accept schema_version 1 and 2. No config key.
# =============================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '3,/^# Default F/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

sub="${1:-}"; [[ -n "$sub" ]] || usage; shift
file="" sprint="" task="" phase="" json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)   [[ $# -ge 2 && -n "$2" ]] || usage; file="$2"; shift 2 ;;
    --sprint) [[ $# -ge 2 && "$2" =~ ^[A-Za-z0-9._-]+$ ]] || usage; sprint="$2"; shift 2 ;;
    --task)   [[ $# -ge 2 && "$2" =~ ^[A-Za-z0-9._-]+$ ]] || usage; task="$2"; shift 2 ;;
    --phase)  [[ $# -ge 2 && "$2" =~ ^[A-Z_]+$ ]] || usage; phase="$2"; shift 2 ;;
    --json)   json=1; shift ;;
    *) usage ;;
  esac
done
if [[ -z "$file" ]]; then
  root="$(cd "$SCRIPT_DIR/../.." && pwd)"
  file="${LOA_RUN_DIR:-$root/.run}/sprint-plan-state.json"
fi

cmd_write() {
  [[ -n "$sprint" && -n "$phase" ]] || usage
  if [[ ! -f "$file" ]]; then echo "run-checkpoint: no run state at $file (start a run first)" >&2; return 2; fi
  local ts tmp lock rc=0
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  tmp="$file.tmp.$$"; lock="$file.lock"
  (
    # flock is util-linux (Linux); without it (macOS) the write is still atomic
    # (tmp + mv) but concurrent writers may interleave — last writer wins.
    if command -v flock >/dev/null 2>&1; then flock -w 5 9 || { echo "run-checkpoint: lock timeout on $lock" >&2; exit 3; }; fi
    if ! jq --arg s "$sprint" --arg t "$task" --arg p "$phase" --arg ts "$ts" \
         '.schema_version = 2
          | .checkpoint = {sprint: $s, task: (if $t == "" then null else $t end), phase: $p, ts: $ts}
          | .timestamps = ((.timestamps // {}) + {last_activity: $ts})' "$file" > "$tmp" 2>/dev/null; then
      rm -f -- "$tmp"; echo "run-checkpoint: $file is not valid JSON — checkpoint not written" >&2; exit 3
    fi
    jq -e . "$tmp" >/dev/null 2>&1 || { rm -f -- "$tmp"; echo "run-checkpoint: refusing to replace $file with unparseable output" >&2; exit 3; }
    mv -f -- "$tmp" "$file"
  ) 9>"$lock" || rc=$?
  return $rc
}

bead_closed() {  # $1 bead id → 0 when br reports closed
  command -v br >/dev/null 2>&1 || return 2
  local js st
  js=$(br show "$1" --json 2>/dev/null) || return 1
  st=$(printf '%s' "$js" | jq -r 'if type=="array" then .[0] else . end | .status // .issue.status // empty' 2>/dev/null)
  [[ "$st" == "closed" ]]
}

cmd_read() {
  if [[ ! -f "$file" ]]; then echo "run-checkpoint: no run state at $file" >&2; return 2; fi
  if ! jq -e . "$file" >/dev/null 2>&1; then echo "run-checkpoint: $file unparseable — no checkpoint; beads are the recovery truth" >&2; (( json )) && echo '{"checkpoint":null,"reason":"unparseable"}'; return 0; fi
  local sv cp s t p ts reason=""
  sv=$(jq -r '.schema_version // 1' "$file"); cp=$(jq -c '.checkpoint // null' "$file")
  if [[ "$cp" == "null" || "$sv" -lt 2 ]]; then
    (( json )) && echo '{"checkpoint":null,"reason":"sprint granularity"}' || echo "checkpoint: none (schema_version $sv → sprint granularity; resume at the first open bead of sprints.current)"
    return 0
  fi
  s=$(jq -r '.checkpoint.sprint // empty' "$file"); t=$(jq -r '.checkpoint.task // empty' "$file"); p=$(jq -r '.checkpoint.phase // empty' "$file"); ts=$(jq -r '.checkpoint.ts // empty' "$file")
  if [[ -z "$s" || -z "$p" ]]; then reason="malformed checkpoint"
  elif [[ -n "$t" ]]; then
    bead_closed "$t"; case $? in 0) ;; 2) reason="" ;; *) reason="task $t is not closed in beads";; esac
  fi
  if [[ -n "$reason" ]]; then
    echo "run-checkpoint: discarding checkpoint ($reason) — resume from the first open bead of $s" >&2
    (( json )) && jq -cn --arg r "$reason" --arg s "$s" '{checkpoint:null, reason:$r, sprint:$s}' || echo "checkpoint: discarded ($reason); resume at the first open bead of $s"
    return 0
  fi
  if (( json )); then jq -c '{checkpoint: .checkpoint}' "$file"
  else echo "checkpoint: $s ${t:+task $t }phase $p at $ts → resume at the first open bead after $t in $s"; fi
}

case "$sub" in
  write) cmd_write ;;
  read)  cmd_read ;;
  *) usage ;;
esac
