#!/usr/bin/env bash
# =============================================================================
# chart-unblock-probe.sh: the only way a `decision:unblock` ticket runs anything (SDD D-4.12).
#
# An unblock ticket answers a question that blocks a decision ("does the lib build on bash 3.2?",
# "what does the API return?"). The probe argv is arbitrary, so this helper does not promise a
# read-only run; it bounds the run and fails the ticket when the run changed what it can see:
#
#   - The argv runs inside a detached worktree under `mktemp -d`, removed by an EXIT/INT/TERM
#     trap on every path, under a scrubbed environment: `env -i` with PATH, a scratch HOME and
#     TMPDIR, LC_ALL=C, TERM=dumb, no global or system git config, no terminal prompt, a failing
#     askpass, an empty credential helper and a failing ssh transport. No token, SSH agent socket
#     or credential helper of the session reaches it.
#   - Before and after the run it snapshots the repository: every ref and tag
#     (`git for-each-ref`), HEAD, a sha256 of the git config files, a listing plus hashes of the
#     hooks directory, and the main tree's `git status --porcelain --untracked-files=all
#     --ignored=matching`. Any difference fails the probe.
#   - A marker is created just before the run; any file under the main tree (and the shared git
#     directory when it lives elsewhere) newer than it fails the probe. Excluded: the scratch
#     directory, the object database and the per-worktree git directories.
#
# Outside the check: network egress other than git's credentialed transports (a probe can still
# open sockets or fetch over anonymous http), writes to absolute paths outside this work tree
# (the real home directory, /tmp, other checkouts, another worktree's git directory), and writes
# within the same second as the marker on a filesystem with one-second timestamps.
# The probe's own exit code is printed (`probe-exit: N`, 124 on a timeout) and is information
# for the ticket, not this helper's verdict. The charting session shows the operator the exact
# argv and runs it only after the operator confirms.
#
# Usage: chart-unblock-probe.sh --ticket <bead-id> [--timeout <s>] -- <cmd> [args...]
# Exit: 0 nothing it watches changed; 1 something changed (the ticket fails) or the worktree
#       could not be created; 2 usage.
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
    -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) usage "unknown argument '$1' (the probe command goes after --)" ;;
  esac
done
[[ -n "$TICKET" ]] || usage "--ticket is required"
[[ "$TICKET" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || usage "--ticket must match ^[A-Za-z0-9][A-Za-z0-9._-]*$"
[[ $# -gt 0 ]] || usage "a probe command is required after --"

MAIN="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "chart-unblock-probe: not inside a git work tree" >&2; exit 1; }
MAIN="$(cd "$MAIN" && pwd -P)"
abs_git(){ local p; p="$(git -C "$MAIN" rev-parse "$1" 2>/dev/null)" || return 1; case "$p" in /*) ;; *) p="${MAIN}/${p}" ;; esac; (cd "$p" && pwd -P); }
GITC="$(abs_git --git-common-dir)" || { echo "chart-unblock-probe: cannot resolve the git directory" >&2; exit 1; }
GITD="$(abs_git --git-dir)" || GITD="$GITC"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/chart-probe.XXXXXX")"
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
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

strip(){ tr -d '\000-\010\013-\037\177'; }

# Everything the probe could change that a later git command or session would trust.
snapshot(){
  local f
  echo "## refs"
  git -C "$MAIN" for-each-ref --format='%(refname) %(objectname)' 2>/dev/null || echo "for-each-ref failed"
  echo "## head"
  git -C "$MAIN" rev-parse HEAD 2>/dev/null || echo "no HEAD"
  git -C "$MAIN" symbolic-ref -q HEAD 2>/dev/null || echo "detached"
  echo "## config"
  for f in "${GITC}/config" "${GITC}/config.worktree" "${GITD}/config.worktree"; do
    if [[ -f "$f" ]]; then sha256_portable "$f"; fi
  done
  echo "## hooks"
  if [[ -d "${GITC}/hooks" ]]; then
    find "${GITC}/hooks" \( -type f -o -type l \) 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      if [[ -L "$f" ]]; then echo "link ${f} -> $(readlink "$f")"; else sha256_portable "$f"; fi
    done
  fi
  echo "## status"
  git -C "$MAIN" status --porcelain --untracked-files=all --ignored=matching 2>/dev/null || echo "status failed"
}

# Files newer than the marker: the main tree, plus the shared git directory when it lives
# outside the main tree (a linked worktree). Objects, per-worktree git dirs and scratch skipped.
newer_files(){
  local roots=("$MAIN") r
  case "$GITC" in "$MAIN"/*) ;; *) roots+=("$GITC") ;; esac
  for r in "${roots[@]}"; do
    find "$r" \( -path "$SCRATCH" -o -path "${GITC}/objects" -o -path "${GITC}/worktrees" \) -prune \
      -o \( -type f -o -type l \) -newer "$MARK" -print 2>/dev/null || true
  done | sed "s#^${MAIN}/##" | LC_ALL=C sort | head -n 50
}

before="$(snapshot)"
# Our own worktree add runs no hook from the shared hooks directory.
if ! git -C "$MAIN" -c core.hooksPath=/dev/null worktree add --detach "${SCRATCH}/wt" HEAD >/dev/null 2>&1; then
  echo "chart-unblock-probe: could not create a throwaway worktree; nothing ran" >&2
  exit 1
fi
WT="${SCRATCH}/wt"
mkdir -p "${SCRATCH}/home" "${SCRATCH}/tmp"
MARK="${SCRATCH}/before.marker"
: > "$MARK"

echo "chart-unblock-probe: ticket ${TICKET}: running in a throwaway worktree under a scrubbed environment (timeout ${TIMEOUT}s)" >&2
set +e
(cd "$WT" && run_with_timeout "$TIMEOUT" env -i \
    PATH="$PATH" HOME="${SCRATCH}/home" TMPDIR="${SCRATCH}/tmp" LC_ALL=C TERM=dumb \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false \
    SSH_ASKPASS=/bin/false GIT_SSH_COMMAND=/bin/false \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
    "$@")
rc=$?
set -e
echo "probe-exit: ${rc}"

newer="$(newer_files)"
after="$(snapshot)"
if [[ "$before" != "$after" || -n "$newer" ]]; then
  echo "chart-unblock-probe: FAIL: the probe changed the repository or the main tree; an unblock ticket never writes there. Changed entries:" >&2
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -E '^[<>]' | strip >&2 || true
  if [[ -n "$newer" ]]; then printf '%s\n' "$newer" | strip | sed 's/^/modified: /' >&2; fi
  exit 1
fi
exit 0
