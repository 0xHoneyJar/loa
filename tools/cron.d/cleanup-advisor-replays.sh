#!/usr/bin/env bash
# =============================================================================
# .run/cron.d/cleanup-advisor-replays.sh — cycle-108 sprint-2 T2.A
# =============================================================================
# Daily cleanup of stale advisor-strategy benchmark worktrees.
#
# Removes /tmp/loa-advisor-replay-* directories that are >24h old,
# identified by mtime of their .cleanup-marker timestamp file. Worktrees
# that the harness scheduled with --cleanup-strategy=defer get this marker.
#
# Cron entry (operator must install manually; see crontab -e):
#   0 4 * * * /path/to/repo/.run/cron.d/cleanup-advisor-replays.sh >> /var/log/loa-cleanup.log 2>&1
# =============================================================================
set -uo pipefail

THRESHOLD_HOURS="${LOA_REPLAY_CLEANUP_HOURS:-24}"
THRESHOLD_MINUTES=$((THRESHOLD_HOURS * 60))

cleaned=0
errors=0
total=0

while IFS= read -r -d '' wt; do
    total=$((total + 1))
    marker="$wt/.cleanup-marker"
    if [ -f "$marker" ]; then
        # Marker present → respect deferred cleanup window.
        age_seconds=$(( $(date +%s) - $(date -r "$marker" +%s 2>/dev/null || echo 0) ))
        age_minutes=$((age_seconds / 60))
        if [ "$age_minutes" -lt "$THRESHOLD_MINUTES" ]; then
            continue
        fi
    fi
    # Find associated git worktree from the parent repo (worktree list).
    parent_repo="$(cat "$wt/.git" 2>/dev/null | sed -n 's|^gitdir: ||p' | sed 's|/.git/worktrees/.*||')"
    if [ -n "$parent_repo" ] && [ -d "$parent_repo" ]; then
        git -C "$parent_repo" worktree remove --force "$wt" 2>/dev/null && cleaned=$((cleaned + 1)) || errors=$((errors + 1))
    else
        # No parent repo found → it's an orphaned dir; safe to remove directly.
        rm -rf "$wt" 2>/dev/null && cleaned=$((cleaned + 1)) || errors=$((errors + 1))
    fi
done < <(find /tmp -maxdepth 1 -type d -name 'loa-advisor-replay-*' -print0 2>/dev/null)

echo "[$(date -u +%FT%TZ)] advisor-replay cleanup: $cleaned removed / $total total / $errors errors" >&2
