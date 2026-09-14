#!/usr/bin/env bash
# Shared local-only stale-cycle assessment for status and golden-path callers.
# Empty output means no positive evidence; never fetch or infer shipment from
# a null/different upstream active_cycle alone.
get_stale_worktree_json() {
    [[ "${STALE_CHECK:-true}" == "true" ]] || return 0
    local git_dir common_dir cycle upstream ledger record
    git_dir=$(git -C "$PROJECT_ROOT" rev-parse --absolute-git-dir 2>/dev/null) || return 0
    common_dir=$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null) || return 0
    [[ "$common_dir" == /* ]] || common_dir="$PROJECT_ROOT/$common_dir"
    [[ "$git_dir" != "$common_dir" ]] || return 0

    cycle=$(jq -er '.active_cycle | select(type == "string" and length > 0)' \
        "$PROJECT_ROOT/grimoires/loa/ledger.json" 2>/dev/null) || return 0
    upstream=$(git -C "$PROJECT_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
        || upstream="origin/main"
    ledger=$(git -C "$PROJECT_ROOT" show "${upstream}:grimoires/loa/ledger.json" 2>/dev/null) || return 0
    record=$(jq -ce --arg cycle "$cycle" \
        '[.cycles[] | select(.id == $cycle and (.status == "archived" or .status == "closed"))] |
         if length == 1 then .[0] else empty end' <<< "$ledger" 2>/dev/null) || return 0
    jq -nc --arg cycle "$cycle" --arg upstream "$upstream" --argjson record "$record" \
        '{cycle_id: $cycle, upstream_ref: $upstream, upstream_status: $record.status,
          archive_path: ($record.archive_path // null),
          warning: ("This worktree is a stale snapshot: cycle " + $cycle + " is " +
            $record.status + " in cached " + $upstream +
            ". Inspect the worktree before retiring it; the local workflow state is historical.")}'
}
