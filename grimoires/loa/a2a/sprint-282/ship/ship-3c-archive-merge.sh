#!/usr/bin/env bash
# ship-3c-archive-merge.sh — admin-merge the archive PR once its check runs are all green, then verify the housekeeping classification prepared nothing.
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa; source ~/.cache/loa/cycle-137/ship/MERGE
h="$(gh pr view $ARCHIVE_PR --json headRefOid --jq .headRefOid)"
pending="$(gh api "repos/0xHoneyJar/loa/commits/$h/check-runs?per_page=100" --paginate --jq '.check_runs[] | select(.status!="completed") | .name' | wc -l)"
bad="$(gh api "repos/0xHoneyJar/loa/commits/$h/check-runs?per_page=100" --paginate --jq '.check_runs[] | select(.status=="completed" and .conclusion!="success" and .conclusion!="skipped" and .conclusion!="neutral") | .name')"
echo "archive PR #$ARCHIVE_PR head $h: pending=$pending bad=[$bad]"; [[ "$pending" -eq 0 && -z "$bad" ]] || { echo "not merging" >&2; exit 1; }
gh pr merge $ARCHIVE_PR --merge --admin --subject "Merge pull request #$ARCHIVE_PR from 0xHoneyJar/chore/cycle-137-archive — archive cycle-137 after merge"
sleep 5; am="$(gh pr view $ARCHIVE_PR --json mergeCommit --jq .mergeCommit.oid)"; echo "ARCHIVE_MERGE_SHA=$am" | tee -a ~/.cache/loa/cycle-137/ship/MERGE
echo "--- Post-Merge Pipeline run on $am (G-3 live: housekeeping must prepare nothing)"
sleep 60; gh run list --workflow post-merge.yml --limit 3 --json databaseId,headSha,status,conclusion,createdAt --jq '.[] | "\(.databaseId) \(.headSha[0:9]) \(.status) \(.conclusion // "-") \(.createdAt)"'
