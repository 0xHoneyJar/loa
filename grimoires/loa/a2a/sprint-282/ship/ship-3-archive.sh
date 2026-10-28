#!/usr/bin/env bash
# ship-3-archive.sh — archive cycle-137 on a chore branch from origin/main (the merge must be on main).
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa; source ~/.cache/loa/cycle-137/ship/MERGE
dirty="$(git status --porcelain --untracked-files=no | grep -v " grimoires/loa/known-failures.md$" || true)"; [[ -z "$dirty" ]] || { echo "tracked tree not clean: $dirty" >&2; exit 2; }  # known-failures.md (KF-034/KF-055 recurrence rows) rides in the archive commit
git fetch -q origin main; git merge-base --is-ancestor "$MERGE_SHA" origin/main || { echo "merge not on main" >&2; exit 2; }
git checkout -q -B chore/cycle-137-archive origin/main
bash .claude/scripts/archive-cycle.sh --cycle 137 --retention 50 2>&1 | tail -6
D=grimoires/loa/archive/cycle-137-performance-followups; ls "$D"
git add -f "$D"/.archive-meta.json "$D"/CHANGELOG.md "$D"/README.md "$D"/ledger.json "$D"/prd.md "$D"/sdd.md "$D"/sprint.md; git add grimoires/loa/ledger.json grimoires/loa/known-failures.md
git diff --cached --stat | tail -2
