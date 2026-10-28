#!/usr/bin/env bash
# ship-1-merge.sh <head sha> — admin-merge the cycle-137 PR once every required check run is green on that exact head.
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa; PR="$(cat ~/.cache/loa/cycle-137/ship/PR)"; H="${1:?head sha}"
full="$(git rev-parse "$H")"; cur="$(gh pr view $PR --json headRefOid --jq .headRefOid)"
[[ "$cur" == "$full" ]] || { echo "PR head moved: $cur != $full" >&2; exit 1; }
[[ "$(gh pr view $PR --json isDraft --jq .isDraft)" == false ]] || { echo "PR is a draft" >&2; exit 1; }
bad=0
for r in "Template Protection" "Validate Framework Files" "Lint Markdown" "Lint YAML" "Shell Tests" "Cross-Platform Compatibility"; do
  line="$(gh api "repos/0xHoneyJar/loa/commits/$full/check-runs?per_page=100" --paginate --jq ".check_runs[] | select(.name==\"$r\") | \"\(.status) \(.conclusion)\"" | head -1)"
  [[ -n "$line" ]] || { echo "required check '$r' has no run on $full" >&2; bad=1; continue; }
  st="${line%% *}"; co="${line##* }"; echo "$r: $st/$co"
  [[ "$st" == completed && "$co" == success ]] || bad=1
done
pending="$(gh api "repos/0xHoneyJar/loa/commits/$full/check-runs?per_page=100" --paginate --jq '.check_runs[] | select(.status!="completed") | .name' | wc -l)"; echo "check runs not completed: $pending"; [[ "$pending" -eq 0 ]] || bad=1
notgreen="$(gh api "repos/0xHoneyJar/loa/commits/$full/check-runs?per_page=100" --paginate --jq '.check_runs[] | select(.status=="completed" and .conclusion!="success" and .conclusion!="skipped" and .conclusion!="neutral") | .name')"; [[ -z "$notgreen" ]] || { echo "not green: $notgreen"; bad=1; }
[[ $bad -eq 0 ]] || { echo "not merging: a check is not green on $full" >&2; exit 1; }
gh pr merge $PR --merge --admin --subject "Merge pull request #$PR from 0xHoneyJar/feature/cycle-137-performance — cycle-137 performance follow-ups (Sprints 281 and 282)"
sleep 5; m="$(gh pr view $PR --json mergeCommit --jq .mergeCommit.oid)"; echo "MERGE_SHA=$m" | tee ~/.cache/loa/cycle-137/ship/MERGE
git fetch -q origin main; git merge-base --is-ancestor "$m" origin/main && echo "merge $m is on origin/main"
