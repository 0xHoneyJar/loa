#!/usr/bin/env bash
# ship-3b-archive-pr.sh — commit the staged archive, push the chore branch, open the archive PR; prints the PR number.
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa; source ~/.cache/loa/cycle-137/ship/MERGE
[[ "$(git branch --show-current)" == chore/cycle-137-archive ]] || { echo "not on chore/cycle-137-archive" >&2; exit 2; }
git diff --cached --quiet && { echo "nothing staged" >&2; exit 2; }
git commit -q -F - <<'MSG'
chore(cycle-137): archive cycle-137-performance-followups after merge — Sprints 281 and 282 shipped (PR #PRNUM, merge MERGESHA); ledger cycle archived (retention 50)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
PR="$(cat ~/.cache/loa/cycle-137/ship/PR)"
git commit -q --amend -F - <<MSG
chore(cycle-137): archive cycle-137-performance-followups after merge — Sprints 281 and 282 shipped (PR #$PR, merge ${MERGE_SHA:0:9}); ledger cycle archived (retention 50)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
MSG
git push -u origin chore/cycle-137-archive 2>&1 | tail -1
url="$(gh pr create --base main --head chore/cycle-137-archive --title "chore(cycle-137): archive cycle-137-performance-followups after merge" --body "$(printf '%s\n\n%s\n\n%s\n\n%s' "Archives cycle-137 \"performance follow-ups\" (Sprints 281 and 282, PR #$PR merged ${MERGE_SHA:0:9}) under grimoires/loa/archive/cycle-137-performance-followups and marks the ledger cycle archived (retention 50). Housekeeping only (\`housekeeping\` classification: the Post-Merge Pipeline prepares no candidate)." "Record branch: record/cycle-137-performance-followups (${RECORD_SHA:-pending})." "Release: v2.0.0-rc.9 published from the cycle merge candidate (see the release notes)." "🤖 Generated with [Claude Code](https://claude.com/claude-code)")" 2>&1 | tail -1)"
echo "$url"; apr="$(echo "$url" | grep -oE '[0-9]+$')"; echo "ARCHIVE_PR=$apr" | tee -a ~/.cache/loa/cycle-137/ship/MERGE
