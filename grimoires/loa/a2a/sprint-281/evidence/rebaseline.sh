#!/usr/bin/env bash
# Re-run the loop's original baseline commands and print before/after means (ms).
# Usage: bash rebaseline.sh > final-table.tsv   (run with the machine otherwise idle)
set -u; cd /home/merlin/Documents/thj/code/loa; export LC_ALL=C TZ=UTC PYTHONHASHSEED=0
B=~/.cache/loa/eso-loop/baseline; A=~/.cache/loa/eso-loop/final; mkdir -p "$A"; P=~/.cache/loa/eso-loop/payloads
mean() { jq -r '[.results[0].measurements[].time_wall_clock.value] | (add/length*1000*10|floor)/10' "$1" 2>/dev/null; }
run() { # name runs [--input payload] cmd...
  local n=$1 runs=$2; shift 2; local inp=(); if [[ "$1" == --input ]]; then inp=(--input "$2"); shift 2; fi
  hyperfine -N -i --warmup 2 --runs "$runs" "${inp[@]}" --export-json "$A/$n.json" "$*" >/dev/null 2>&1
  printf '%s\t%s\t%s\n' "$n" "$(mean "$B/$n.json")" "$(mean "$A/$n.json")"
}
HG=.claude/hooks/hook-guard.sh
printf 'command\tbaseline_ms\tfinal_ms\n'
run repo-map-gen 5 'bash .claude/scripts/repo-map-gen.sh'
run grimoire-index 5 'bash .claude/scripts/grimoire-index.sh'
run loa-status 5 'bash .claude/scripts/loa-status.sh'
run beads-health 5 'bash .claude/scripts/beads/beads-health.sh --json'
run upgrade-health 5 'bash .claude/scripts/upgrade-health-check.sh'
run cheval-help 10 'python3 .claude/adapters/cheval.py --help'
run ss-kf-surface 10 --input $P/session.json "bash .claude/hooks/loa-kf-surface.sh"
run ss-runstate 10 --input $P/session.json "bash $HG .claude/hooks/session-start/loa-run-state-surface.sh"
run ss-ctxclass 10 --input $P/session.json "bash $HG .claude/hooks/session-start/loa-context-class.sh"
run ss-decisions 10 --input $P/session.json "bash $HG .claude/hooks/session-start/loa-decisions-surface.sh"
run pre-write-implgate 10 --input $P/write.json "bash $HG .claude/hooks/compliance/implement-gate.sh"
run pre-write-notes 10 --input $P/write.json "bash $HG .claude/hooks/safety/notes-size-guard.sh"
run pre-write-zone 10 --input $P/write.json "bash $HG .claude/hooks/safety/zone-write-guard.sh"
run pre-bash-destructive 10 --input $P/bash.json "bash $HG .claude/hooks/safety/block-destructive-bash.sh"
run post-karpathy 10 --input $P/write.json "bash .claude/hooks/quality/karpathy-surgical-diff-check.sh"
run stop-runmode 10 --input $P/session.json "bash .claude/hooks/safety/run-mode-stop-guard.sh"
