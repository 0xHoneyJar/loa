#!/usr/bin/env bash
# =============================================================================
# chart-unblock-probe.sh: the only way a `decision:unblock` ticket runs anything (SDD D-4.12).
#
# An unblock ticket answers a question that blocks a decision ("does the lib build on bash 3.2?",
# "what does the API return?"). It may run read-only probes and throwaway worktrees; it never
# writes App-Zone code in the main tree. This helper records the main tree's
# `git status --porcelain --untracked-files=all --ignored=matching` (every untracked file and
# every ignored path that matches a pattern), runs the probe argv inside a detached worktree
# under `mktemp -d` (cwd = that worktree), removes the worktree by an EXIT/INT/TERM trap on every
# path, and exits 1 when the main tree's status changed. The probe's own exit code is printed
# (`probe-exit: N`, 124 on a timeout) and is information for the ticket, not this helper's verdict.
#
# Usage: chart-unblock-probe.sh --ticket <bead-id> [--timeout <s>] -- <cmd> [args...]
# Exit: 0 main tree unchanged; 1 main tree changed (the ticket fails) or the worktree could not
#       be created; 2 usage.
# =============================================================================
export LC_ALL=C
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/compat-lib.sh"

TICKET=""
TIMEOUT=600
usage(){ echo "chart-unblock-probe: $*" >&2; echo "usage: chart-unblock-probe.sh --ticket <bead-id> [--timeout <s>] -- <cmd> [args...]" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket) [[ -n "${2:-}" ]] || usage "--ticket needs a bead id"; TICKET="$2"; shift 2 ;;
    --timeout) [[ "${2:-}" =~ ^[1-9][0-9]{0,4}$ ]] || usage "--timeout needs seconds (1-99999)"; TIMEOUT="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) usage "unknown argument '$1' (the probe command goes after --)" ;;
  esac
done
[[ -n "$TICKET" ]] || usage "--ticket is required"
[[ "$TICKET" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || usage "--ticket must match ^[A-Za-z0-9][A-Za-z0-9._-]*$"
[[ $# -gt 0 ]] || usage "a probe command is required after --"

MAIN="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "chart-unblock-probe: not inside a git work tree" >&2; exit 1; }
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/chart-probe.XXXXXX")"
WT=""
cleanup(){
  if [[ -n "$WT" ]]; then
    git -C "$MAIN" worktree remove --force "$WT" >/dev/null 2>&1 || true
    git -C "$MAIN" worktree prune >/dev/null 2>&1 || true
  fi
  if [[ -n "$SCRATCH" && -d "$SCRATCH" ]]; then rm -rf -- "$SCRATCH"; fi
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

before="$(git -C "$MAIN" status --porcelain --untracked-files=all --ignored=matching 2>/dev/null)"
if ! git -C "$MAIN" worktree add --detach "${SCRATCH}/wt" HEAD >/dev/null 2>&1; then
  echo "chart-unblock-probe: could not create a throwaway worktree; nothing ran" >&2
  exit 1
fi
WT="${SCRATCH}/wt"

echo "chart-unblock-probe: ticket ${TICKET}: running in a throwaway worktree (timeout ${TIMEOUT}s)" >&2
set +e
(cd "$WT" && run_with_timeout "$TIMEOUT" "$@")
rc=$?
set -e
echo "probe-exit: ${rc}"

after="$(git -C "$MAIN" status --porcelain --untracked-files=all --ignored=matching 2>/dev/null)"
if [[ "$before" != "$after" ]]; then
  echo "chart-unblock-probe: FAIL: the probe changed the main tree; an unblock ticket never writes there. Changed entries:" >&2
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -E '^[<>]' | tr -d '\000-\010\013-\037\177' >&2 || true
  exit 1
fi
exit 0
