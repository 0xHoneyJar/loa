#!/usr/bin/env bash
# ship-2-record.sh — record branch for cycle-137 (prev = cycle-136 record), accepting only the known NOTES prose hit class.
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa; source ~/.cache/loa/cycle-137/ship/MERGE
git fetch -q origin main "+refs/heads/record/*:refs/remotes/origin/record/*"
args=(--cycle 137 --head "$MERGE_SHA" --prev origin/record/cycle-136-bridgebuilder-followups --stage "stage 1")
set +e; out="$(bash .claude/scripts/record-branch.sh "${args[@]}" 2>&1)"; rc=$?; set -e
printf '%s\n' "$out" | tail -10
if (( rc != 0 )); then
  grep -q 'credential-shaped hit' <<<"$out" && { echo "STOP: credential-shaped hit" >&2; exit 1; }
  tree="$(grep -oE 'scan_tree=[0-9a-f]{40}' <<<"$out" | head -1 | cut -d= -f2)"; [[ -n "$tree" ]] || { echo "STOP: non-scan refusal" >&2; exit 1; }
  hits="$(grep 'record-branch: scan hit:' <<<"$out" | sed 's/.*scan hit: //')"; echo "--- hits:"; printf '%s\n' "$hits"
  grep -vq ':audit-key-password-assignment$' <<<"$hits" && { echo "STOP: unexpected hit class" >&2; exit 1; }
  bash .claude/scripts/record-branch.sh "${args[@]}" --accept-scan "$tree" 2>&1 | tail -6
fi
rec="$(git rev-parse refs/heads/record/cycle-137-performance-followups)"; echo "RECORD_SHA=$rec" | tee -a ~/.cache/loa/cycle-137/ship/MERGE
bash .claude/scripts/run-mode-ice.sh push origin record/cycle-137-performance-followups 2>&1 | tail -2
git ls-remote --heads origin record/cycle-137-performance-followups
