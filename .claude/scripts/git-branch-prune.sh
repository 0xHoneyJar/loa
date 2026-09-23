#!/usr/bin/env bash
# git-branch-prune.sh — delete local branches that hold no unmerged work.
#
# Usage:
#   git-branch-prune.sh [--dry-run] [--base <ref>] [--json]
#
# A branch qualifies when ONE of these positively holds:
#   merged         its head is an ancestor of the base ref (a true merge)
#   squash-merged  a merged pull request exists for it (`gh pr list
#                  --state merged --head <name>`, bounded by `timeout 5`;
#                  skipped when `gh` is absent or LOA_FENCE_NO_NETWORK=1)
#   gone           its upstream no longer exists (`[gone]` after a
#                  `git fetch --prune`)
# The current branch, the base branch, main and master are never deleted.
# Any probe failure counts as "not merged" — the branch is kept.
#
# Every deletion prints the branch's last SHA so it can be restored with
# `git branch <name> <sha>` (git keeps the objects until gc). This is the
# sanctioned path for `git branch -D` on squash-merged branches: the
# destructive-command fence (FR-1.1) allows true merges offline and names
# this helper for everything else. Cycle-125 FR-1, SDD D-1.4.
#
# Exit: 0 deleted (or would delete under --dry-run), 1 nothing to do, 2 usage.
set -euo pipefail
export LC_ALL=C

SCRIPT_NAME="${0##*/}"
DRY_RUN=0
BASE=""
JSON=0

usage() {
  cat >&2 <<EOF
Usage: $SCRIPT_NAME [--dry-run] [--base <ref>] [--json]

  --dry-run     List the branches that would be deleted; delete nothing.
  --base <ref>  Merge base (default: first of origin/main, main, origin/master, master).
  --json        Emit one {"branch","reason","sha","deleted"} object per line.

Env: LOA_FENCE_NO_NETWORK=1 skips the merged-PR probe (gh).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --base) [[ $# -ge 2 && -n "${2:-}" ]] || { usage; exit 2; }; BASE="$2"; shift 2 ;;
    --base=*) BASE="${1#--base=}"; [[ -n "$BASE" ]] || { usage; exit 2; }; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *) usage; exit 2 ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "$SCRIPT_NAME: not inside a git work tree" >&2; exit 2; }

if [[ -z "$BASE" ]]; then
  for cand in origin/main main origin/master master; do
    if git rev-parse -q --verify "$cand^{commit}" >/dev/null 2>&1; then BASE="$cand"; break; fi
  done
  [[ -n "$BASE" ]] || { echo "$SCRIPT_NAME: no base ref found (pass --base <ref>)" >&2; exit 2; }
else
  git rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 || { echo "$SCRIPT_NAME: base ref not found: $BASE" >&2; exit 2; }
fi
base_short="${BASE#origin/}"
current="$(git symbolic-ref -q --short HEAD 2>/dev/null || true)"

# Merged-PR probe: only when gh is present and the network is not opted out.
probe_enabled=0
if [[ "${LOA_FENCE_NO_NETWORK:-0}" != "1" ]] && command -v gh >/dev/null 2>&1; then
  probe_enabled=1
fi
timeout_cmd=()
if command -v timeout >/dev/null 2>&1; then timeout_cmd=(timeout 5); fi

squash_merged() {
  local name="$1" n
  (( probe_enabled )) || return 1
  n=$("${timeout_cmd[@]}" gh pr list --state merged --head "$name" --json number --jq 'length' 2>/dev/null) || return 1
  [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]]
}

emit() {  # branch reason sha deleted
  if (( JSON )); then
    jq -cn --arg b "$1" --arg r "$2" --arg s "$3" --argjson d "$4" '{branch:$b, reason:$r, sha:$s, deleted:$d}'
  elif (( DRY_RUN )); then
    printf 'would delete  %-14s %s (%s)\n' "$2" "$1" "$3"
  else
    printf 'deleted       %-14s %s (was %s; restore: git branch %s %s)\n' "$2" "$1" "$3" "$1" "$3"
  fi
}

count=0
while IFS=$'\t' read -r name sha track; do
  [[ -n "$name" ]] || continue
  [[ "$name" == "$current" ]] && continue
  case "$name" in "$base_short"|main|master) continue ;; esac
  reason=""
  if git merge-base --is-ancestor "$name" "$BASE" 2>/dev/null; then
    reason="merged"
  elif [[ "$track" == "[gone]" ]]; then
    reason="gone"
  elif squash_merged "$name"; then
    reason="squash-merged"
  fi
  [[ -n "$reason" ]] || continue
  deleted=false
  if (( ! DRY_RUN )); then
    git branch -D -- "$name" >/dev/null 2>&1 || { echo "$SCRIPT_NAME: failed to delete $name" >&2; continue; }
    deleted=true
  fi
  emit "$name" "$reason" "$sha" "$deleted"
  count=$((count + 1))
done < <(git for-each-ref --format='%(refname:short)%09%(objectname:short)%09%(upstream:track)' refs/heads/)

if (( count == 0 )); then
  (( JSON )) || echo "nothing to prune (base $BASE)" >&2
  exit 1
fi
exit 0
