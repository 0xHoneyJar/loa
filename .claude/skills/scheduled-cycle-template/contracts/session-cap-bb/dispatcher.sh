#!/usr/bin/env bash
# session-cap-bb dispatcher.sh — phase 2 (dispatcher) for the post-reset
# bridgebuilder fan-out (bd-fanout-real-dispatch-9jv6 Tranche 1).
#
# On action:dispatch, fires the bridgebuilder-review headless entrypoint
# (resources/entry.sh — the same binary spiral-harness.sh already runs
# unattended) with --repo <owner/repo> and NO --pr, so BB self-discovers open
# PRs and dedups on its own incremental per-PR diff hashing. On action:noop it
# short-circuits (exit 0, nothing was in flight). This is the only mutating
# phase; a re-run under the same cycle_id re-invokes BB, whose per-PR hashing
# makes the review itself idempotent.
#
# Args: $1 cycle_id  $2 schedule_id  $3 phase_index  $4 prior_phases_json
set -euo pipefail

cycle_id="${1:?cycle_id required}"
schedule_id="${2:?schedule_id required}"

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_here}/../../../../.." && pwd)"
# The scheduler canonicalizes phase paths through the consumer's skills mount.
# Rebind a physical .loa root only when that consumer mounts these same skills.
if [[ "${REPO_ROOT##*/}" == ".loa" &&
      "${REPO_ROOT}/../.claude/skills" -ef "${REPO_ROOT}/.claude/skills" ]]; then
    REPO_ROOT="$(cd "${REPO_ROOT}/.." && pwd)"
fi
_sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }
HANDOFF_DIR="${TMPDIR:-/tmp}/loa-session-cap-bb.$(_sanitize "$cycle_id")"
mkdir -p "$HANDOFF_DIR"
DECIDER_FILE="${HANDOFF_DIR}/decider.json"

write_out() { printf '%s' "$1" | tee "${HANDOFF_DIR}/dispatcher.json"; }

action="noop"
if [[ -f "$DECIDER_FILE" ]] && jq empty "$DECIDER_FILE" 2>/dev/null; then
    action="$(jq -r '.action // "noop"' "$DECIDER_FILE")"
fi

if [[ "$action" != "dispatch" ]]; then
    write_out "$(jq -nc --arg cid "$cycle_id" --arg sid "$schedule_id" \
        '{cycle_id:$cid, schedule_id:$sid, dispatched:false,
          reason:"nothing was in flight (decider noop)"}')"
    exit 0
fi

# Resolve owner/repo: explicit override wins, else derive from the git origin.
repo="${LOA_SESSION_CAP_BB_REPO:-}"
if [[ -z "$repo" ]]; then
    url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
    repo="$(printf '%s' "$url" | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')"
fi
if [[ -z "$repo" ]]; then
    echo "dispatcher: could not resolve owner/repo (set LOA_SESSION_CAP_BB_REPO or a git origin)" >&2
    exit 1
fi

BB_ENTRY="${LOA_SESSION_CAP_BB_ENTRY:-${_here}/../../../bridgebuilder-review/resources/entry.sh}"
if [[ ! -f "$BB_ENTRY" ]]; then
    echo "dispatcher: bridgebuilder entrypoint not found: $BB_ENTRY" >&2
    exit 1
fi

# Fire BB with NO --pr: it self-discovers open PRs and dedups internally.
# BB's stdout (its run JSON) is kept in the handoff dir and replayed, so a DEGRADED run can name its voices.
BB_OUT="${HANDOFF_DIR}/bb-stdout.json"
rc=0
if [[ -x "$BB_ENTRY" ]]; then
    "$BB_ENTRY" --repo "$repo" >"$BB_OUT" || rc=$?
else
    bash "$BB_ENTRY" --repo "$repo" >"$BB_OUT" || rc=$?
fi
cat "$BB_OUT"

# cycle-129 D-7.7 (DEC-0150): exit 3 = the review COMPLETED with a DEGRADED consensus (bridgebuilder.exit_on_degraded;
# 0 restores the old exit). Not a failure: one WARN naming the incomplete voices, `degraded: true` in the handoff, exit 0.
degraded=false
voices=""
if [[ "$rc" -eq 3 ]]; then
    degraded=true
    voices=$(jq -r '[.verdicts[]?.voices.incomplete[]?] | unique | join(", ")' "$BB_OUT" 2>/dev/null) || voices=""
    echo "dispatcher: WARN: bridgebuilder completed DEGRADED (exit 3): incomplete voices: ${voices:-none named (degraded verdict quality)}" >&2
fi

write_out "$(jq -nc --arg cid "$cycle_id" --arg sid "$schedule_id" \
    --arg repo "$repo" --argjson ec "$rc" --argjson degraded "$degraded" --arg voices "$voices" \
    '{cycle_id:$cid, schedule_id:$sid, dispatched:true, repo:$repo,
      bb_exit_code:$ec, degraded:$degraded}
     + (if $degraded then {incomplete_voices: $voices} else {} end)')"
if [[ "$rc" -eq 3 ]]; then
    exit 0
fi
exit "$rc"
