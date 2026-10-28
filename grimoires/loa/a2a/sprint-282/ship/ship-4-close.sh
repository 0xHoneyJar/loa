#!/usr/bin/env bash
# ship-4-close.sh — JACKED_OUT: completion block into both run-state files, park copies as *.cycle-137.jacked-out.json, checkout main.
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa; source ~/.cache/loa/cycle-137/ship/MERGE
PR="$(cat ~/.cache/loa/cycle-137/ship/PR)"; now="$(date -u +%FT%TZ)"
: "${MERGE_SHA:?}" "${RECORD_SHA:?}" "${ARCHIVE_PR:?}" "${ARCHIVE_MERGE_SHA:?}"
comp="$(jq -n --arg pr "$PR" --arg url "https://github.com/0xHoneyJar/loa/pull/$PR" --arg m "$MERGE_SHA" --arg r "$RECORD_SHA" --argjson apr "$ARCHIVE_PR" --arg am "$ARCHIVE_MERGE_SHA" \
  '{pushed:true, pr_created:true, pr_url:$url, merged_sha:$m, release_tag:"v2.0.0-rc.9", release_note:"v2.0.0-rc.9 published from the cycle merge candidate (publish-summary.md; R-6 … R-8)", record_branch:$r, archive_pr:$apr, archive_merged_sha:$am, skipped_reason:null}')"
jq --arg t "$now" --argjson c "$comp" '.state="JACKED_OUT" | .status="JACKED_OUT" | .timestamps.last_activity=$t | .timestamps.completed=$t | .checkpoint.phase="COMPLETE" | .checkpoint.ts=$t | .completion=$c' .run/sprint-plan-state.json > /tmp/sps.json && mv /tmp/sps.json .run/sprint-plan-state.json
jq --arg t "$now" --argjson c "$comp" '.state="JACKED_OUT" | .timestamps.last_activity=$t | .timestamps.completed=$t | .completion=$c' .run/state.json > /tmp/st.json && mv /tmp/st.json .run/state.json
cp .run/sprint-plan-state.json .run/sprint-plan-state.cycle-137.jacked-out.json; cp .run/state.json .run/state.cycle-137.jacked-out.json
jq -c '{state, status, completion}' .run/sprint-plan-state.json | cut -c1-400
git fetch -q origin main; git checkout -q main; git reset -q --hard origin/main; git log --oneline -1 | cut -c1-100
