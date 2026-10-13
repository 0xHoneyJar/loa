#!/usr/bin/env bash
# =============================================================================
# red-test-check.sh: verify a bug fix's red-before-green (grimoires/loa/sdd.md D-7.5..D-7.7, §5.2).
#
# A /bug micro-sprint commits its failing test alone ("Red commit: <sha>" in reviewer.md) before
# the fix. This check runs the test command at the red commit and at the green revision, each in
# its own detached worktree under `mktemp -d`, and reports whether the test failed before and
# passes after:
#
#   0 VERIFIED     red fails by assertion and green passes
#   1 GREEN_FAILS  green fails (red failed by assertion)
#   2              usage error, a commit that does not resolve, red not a strict ancestor of
#                  green, a worktree that cannot be created, or a failing --setup
#   3 DECOY        the test passes at the red commit
#   4 NOT_A_RED    --test-file absent at the red commit, or the red run failed for a
#                  non-assertion reason (collection, compile, import, command not found)
#   5 TIMEOUT      a run exceeded --timeout
# The red-side verdicts (5, 3, 4) are judged first, then the green side (5, 1).
#
# Honest scope (as validate-ac-verification.sh states for its own check): this proves the
# command failed before and passes after. It does not prove the assertion is right, that the
# test exercises the bug, or that the fix is the cause; the reviewer still reads the test. The
# not-a-red patterns are heuristics over the red run's output: a test whose own assertion
# output contains one of them reads as NOT_A_RED (a false negative the reviewer can overrule).
#
# What runs where: the test argv runs with cwd = each worktree, never through `bash -c`.
# Uncommitted state in the live tree never counts and nothing is stashed. Present dependency
# directories (node_modules .venv vendor target .tox) are symlinked from the live tree into a
# worktree that lacks them (--no-link-deps turns this off); a test that writes into a linked
# directory writes into the live tree's copy. --setup is split on whitespace into an argv (no
# shell syntax; point it at a script for anything more) and runs in each worktree first.
# The timeout uses `timeout`, else `gtimeout`, else a bash watcher (TERM, then KILL after 2 s,
# to the run's process group); with `timeout`/`gtimeout` a test that itself exits 124 reads as
# a timeout. One cleanup removes both worktrees (worktree remove --force, then prune) and the
# scratch directory on every exit path, interrupts included.
#
# Usage: red-test-check.sh --red <commit> [--green <rev>] [--test-file <path>] [--setup <cmd>]
#                          [--no-link-deps] [--timeout <s>] [--json] -- <test command...>
# Run it from inside the repository's work tree. --json prints one object on stdout:
#   {red, green, red_exit, green_exit, verdict, red_tail, green_tail, linked_deps}
# (the exits are null when a run did not happen). Exit 2 errors print to stderr only.
# =============================================================================
export LC_ALL=C
set -euo pipefail

PROG="red-test-check"
DEP_DIRS="node_modules .venv vendor target .tox"
TAIL_LINES=80

# Not-a-red output patterns (ERE, matched on the red run's output when it failed). One entry
# per runner; extend here, never inline.
NOT_A_RED_PATTERNS=(
  # bats: the file did not load (gather failure), a parse error, a missing file or command
  'not ok [0-9]+ bats-gather-tests'
  'syntax error near unexpected token'
  'syntax error: unexpected end of file'
  'Test file .* does not exist'
  'command not found'
  ': not found$'
  # pytest: collection and import errors
  'ERROR collecting'
  'ImportError while importing'
  # node (node:test, jest, mocha): an unresolved import or a parse error
  'Cannot find module'
  'SyntaxError'
  # cargo: the crate or its tests did not build
  'could not compile'
  # go (1.22 toolchain): build or setup failure of the test binary
  'build failed'
  '\[setup failed\]'
)

usage(){
  echo "${PROG}: $*" >&2
  echo "usage: red-test-check.sh --red <commit> [--green <rev>] [--test-file <path>] [--setup <cmd>] [--no-link-deps] [--timeout <s>] [--json] -- <test command...>" >&2
  exit 2
}
die2(){ echo "${PROG}: $*" >&2; exit 2; }
strip(){ tr -d '\000-\010\013-\037\177'; }

RED=""
GREEN="HEAD"
TEST_FILE=""
SETUP=""
LINK_DEPS=1
TIMEOUT=600
JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --red) [[ -n "${2:-}" ]] || usage "--red needs a commit"; RED="$2"; shift 2 ;;
    --green) [[ -n "${2:-}" ]] || usage "--green needs a revision"; GREEN="$2"; shift 2 ;;
    --test-file) [[ -n "${2:-}" ]] || usage "--test-file needs a path"; TEST_FILE="$2"; shift 2 ;;
    --setup) [[ -n "${2:-}" ]] || usage "--setup needs a command"; SETUP="$2"; shift 2 ;;
    --no-link-deps) LINK_DEPS=0; shift ;;
    --timeout) [[ "${2:-}" =~ ^[1-9][0-9]{0,4}$ ]] || usage "--timeout needs seconds (1-99999)"; TIMEOUT="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --) shift; break ;;
    -h|--help) sed -n '3,41p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) usage "unknown argument '$1' (the test command goes after --)" ;;
  esac
done
[[ -n "$RED" ]] || usage "--red is required"
[[ $# -gt 0 ]] || usage "a test command is required after --"
case "$RED" in -*) usage "--red must be a commit, not an option" ;; esac
case "$GREEN" in -*) usage "--green must be a revision, not an option" ;; esac
case "$TEST_FILE" in
  /*) usage "--test-file must be relative to the repository root" ;;
  -*) usage "--test-file must be a path, not an option" ;;
esac
if [[ "$JSON" -eq 1 ]] && ! command -v jq >/dev/null 2>&1; then die2 "--json needs jq"; fi
SETUP_ARGV=()
if [[ -n "$SETUP" ]]; then
  read -r -a SETUP_ARGV <<< "$SETUP"
  [[ ${#SETUP_ARGV[@]} -gt 0 ]] || usage "--setup is empty"
fi

MAIN="$(git rev-parse --show-toplevel 2>/dev/null)" || die2 "not inside a git work tree"
MAIN="$(cd "$MAIN" && pwd -P)"

RED_SHA="$(git -C "$MAIN" rev-parse --verify --quiet "${RED}^{commit}")" || die2 "--red '${RED}' does not resolve to a commit"
GREEN_SHA="$(git -C "$MAIN" rev-parse --verify --quiet "${GREEN}^{commit}")" || die2 "--green '${GREEN}' does not resolve to a commit"
if [[ "$RED_SHA" == "$GREEN_SHA" ]] || ! git -C "$MAIN" merge-base --is-ancestor "$RED_SHA" "$GREEN_SHA"; then
  die2 "red ${RED_SHA} is not a strict ancestor of green ${GREEN_SHA}: commit the failing test first, then the fix"
fi

RED_EXIT=""
GREEN_EXIT=""
RED_TAIL=""
GREEN_TAIL=""
LINKED=""

# Report a verdict (text or JSON) and exit with its code.
finish(){
  local verdict="$1" code="$2"
  if [[ "$JSON" -eq 1 ]]; then
    jq -n --arg red "$RED_SHA" --arg green "$GREEN_SHA" --arg re "$RED_EXIT" --arg ge "$GREEN_EXIT" \
      --arg verdict "$verdict" --arg rt "$RED_TAIL" --arg gt "$GREEN_TAIL" --arg linked "$LINKED" \
      '{red: $red, green: $green,
        red_exit: (if $re == "" then null else ($re | tonumber) end),
        green_exit: (if $ge == "" then null else ($ge | tonumber) end),
        verdict: $verdict, red_tail: $rt, green_tail: $gt,
        linked_deps: ($linked | split(" ") | map(select(. != "")))}'
    if [[ -n "$RED_TAIL" ]]; then
      printf -- '--- red run (last %s lines) ---\n%s\n--- end red run ---\n' "$TAIL_LINES" "$RED_TAIL" >&2
    fi
  else
    echo "${PROG}: red ${RED_SHA} exit ${RED_EXIT:-n/a}; green ${GREEN_SHA} exit ${GREEN_EXIT:-n/a}; linked deps: ${LINKED:-none}"
    if [[ -n "$RED_EXIT" ]]; then
      printf -- '--- red run (last %s lines) ---\n%s\n--- end red run ---\n' "$TAIL_LINES" "$RED_TAIL"
    fi
    if [[ -n "$GREEN_EXIT" && "$GREEN_EXIT" != "0" ]]; then
      printf -- '--- green run (last %s lines) ---\n%s\n--- end green run ---\n' "$TAIL_LINES" "$GREEN_TAIL"
    fi
    echo "verdict: ${verdict}"
  fi
  exit "$code"
}

# D-7.6: the named test file must exist at the red commit.
if [[ -n "$TEST_FILE" ]] && ! git -C "$MAIN" cat-file -e "${RED_SHA}:${TEST_FILE#./}" 2>/dev/null; then
  echo "${PROG}: --test-file '${TEST_FILE}' does not exist at the red commit ${RED_SHA}: the failing test was not committed there" >&2
  finish NOT_A_RED 4
fi

# WARN: a green that differs from red only in test files cannot be a fix.
is_test_path(){
  local p="$1" b
  b="${p##*/}"
  [[ -n "$TEST_FILE" && "$p" == "${TEST_FILE#./}" ]] && return 0
  case "/$p" in */test/*|*/tests/*|*/spec/*|*/__tests__/*|*/testdata/*|*/fixtures/*) return 0 ;; esac
  case "$b" in test_*|*_test.*|*.test.*|*.spec.*|*_spec.*|*.bats) return 0 ;; esac
  return 1
}
nontest=0
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  if ! is_test_path "$p"; then nontest=1; break; fi
done < <(git -C "$MAIN" diff --name-only "$RED_SHA" "$GREEN_SHA" -- 2>/dev/null || true)
if [[ "$nontest" -eq 0 ]]; then
  echo "${PROG}: WARN: no non-test file changed between red ${RED_SHA} and green ${GREEN_SHA}; a pass there comes from test changes alone" >&2
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/red-test-check.XXXXXX")"
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
WT_RED=""
WT_GREEN=""
RUN_PID=""
WATCH_PID=""
remove_wt(){
  local wt="$1" d
  [[ -n "$wt" ]] || return 0
  # Unlink our dependency symlinks first, so nothing below can follow them into the live tree.
  for d in $DEP_DIRS; do
    if [[ -L "${wt}/${d}" ]]; then rm -f -- "${wt}/${d}"; fi
  done
  git -C "$MAIN" worktree remove --force "$wt" >/dev/null 2>&1 || true
}
cleanup(){
  if [[ -n "$WATCH_PID" ]]; then kill "$WATCH_PID" 2>/dev/null || true; fi
  if [[ -n "$RUN_PID" ]]; then
    kill -TERM -- "-${RUN_PID}" 2>/dev/null || kill -TERM "$RUN_PID" 2>/dev/null || true
  fi
  remove_wt "$WT_RED"
  remove_wt "$WT_GREEN"
  git -C "$MAIN" worktree prune >/dev/null 2>&1 || true
  if [[ -n "$SCRATCH" && -d "$SCRATCH" ]]; then rm -rf -- "$SCRATCH"; fi
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

add_wt(){
  local path="$1" sha="$2"
  # No hook from the shared hooks directory runs for our checkout.
  if ! git -C "$MAIN" -c core.hooksPath=/dev/null worktree add --detach "$path" "$sha" >/dev/null 2>"${SCRATCH}/wt-add.err"; then
    strip < "${SCRATCH}/wt-add.err" >&2
    die2 "could not create a worktree for ${sha}; nothing ran"
  fi
}

link_deps(){
  local wt="$1" d
  [[ "$LINK_DEPS" -eq 1 ]] || return 0
  for d in $DEP_DIRS; do
    if [[ -e "${MAIN}/${d}" && ! -e "${wt}/${d}" && ! -L "${wt}/${d}" ]]; then
      ln -s "${MAIN}/${d}" "${wt}/${d}"
      case " $LINKED " in *" $d "*) ;; *) LINKED="${LINKED:+$LINKED }$d" ;; esac
    fi
  done
}

# Run argv with cwd $1, output to $2, bounded by TIMEOUT. Sets RUN_RC and RUN_TIMED_OUT.
RUN_RC=0
RUN_TIMED_OUT=0
run_bounded(){
  local cwd="$1" log="$2" flag="${SCRATCH}/timed-out" tbin="" start
  shift 2
  rm -f -- "$flag"
  if command -v timeout >/dev/null 2>&1; then tbin=timeout
  elif command -v gtimeout >/dev/null 2>&1; then tbin=gtimeout
  fi
  start=$SECONDS
  # Job control gives the run its own process group, so a timeout or an interrupt stops the
  # whole tree it spawned.
  set -m
  if [[ -n "$tbin" ]]; then
    ( cd "$cwd" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX && exec "$tbin" -k 2 "$TIMEOUT" "$@" ) > "$log" 2>&1 < /dev/null &
  else
    ( cd "$cwd" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX && exec "$@" ) > "$log" 2>&1 < /dev/null &
  fi
  RUN_PID=$!
  set +m
  if [[ -z "$tbin" ]]; then
    ( i=0
      while kill -0 "$RUN_PID" 2>/dev/null; do
        if [[ "$i" -ge "$TIMEOUT" ]]; then
          : > "$flag"
          kill -TERM -- "-${RUN_PID}" 2>/dev/null || kill -TERM "$RUN_PID" 2>/dev/null || true
          sleep 2
          kill -KILL -- "-${RUN_PID}" 2>/dev/null || kill -KILL "$RUN_PID" 2>/dev/null || true
          exit 0
        fi
        sleep 1
        i=$((i + 1))
      done ) < /dev/null > /dev/null 2>&1 &
    WATCH_PID=$!
  fi
  set +e
  wait "$RUN_PID"
  RUN_RC=$?
  set -e
  RUN_PID=""
  if [[ -n "$WATCH_PID" ]]; then
    kill "$WATCH_PID" 2>/dev/null || true
    wait "$WATCH_PID" 2>/dev/null || true
    WATCH_PID=""
  fi
  RUN_TIMED_OUT=0
  if [[ -n "$tbin" ]]; then
    if [[ "$RUN_RC" -eq 124 ]] || { [[ "$RUN_RC" -eq 137 ]] && [[ $((SECONDS - start)) -ge "$TIMEOUT" ]]; }; then RUN_TIMED_OUT=1; fi
  elif [[ -f "$flag" ]]; then
    RUN_TIMED_OUT=1
  fi
  return 0
}

prepare(){
  local wt="$1" name="$2"
  link_deps "$wt"
  if [[ ${#SETUP_ARGV[@]} -gt 0 ]]; then
    run_bounded "$wt" "${SCRATCH}/setup-${name}.log" "${SETUP_ARGV[@]}"
    if [[ "$RUN_RC" -ne 0 || "$RUN_TIMED_OUT" -eq 1 ]]; then
      tail -n "$TAIL_LINES" "${SCRATCH}/setup-${name}.log" | strip >&2
      if [[ "$RUN_TIMED_OUT" -eq 1 ]]; then die2 "--setup timed out after ${TIMEOUT}s in the ${name} worktree"; fi
      die2 "--setup exited ${RUN_RC} in the ${name} worktree"
    fi
  fi
}

WT_RED="${SCRATCH}/red"
add_wt "$WT_RED" "$RED_SHA"
WT_GREEN="${SCRATCH}/green"
add_wt "$WT_GREEN" "$GREEN_SHA"
prepare "$WT_RED" red
prepare "$WT_GREEN" green

run_bounded "$WT_RED" "${SCRATCH}/red.log" "$@"
RED_EXIT="$RUN_RC"
RED_TO="$RUN_TIMED_OUT"
RED_TAIL="$(tail -n "$TAIL_LINES" "${SCRATCH}/red.log" | strip)"

run_bounded "$WT_GREEN" "${SCRATCH}/green.log" "$@"
GREEN_EXIT="$RUN_RC"
GREEN_TO="$RUN_TIMED_OUT"
GREEN_TAIL="$(tail -n "$TAIL_LINES" "${SCRATCH}/green.log" | strip)"

if [[ "$RED_TO" -eq 1 ]]; then
  echo "${PROG}: the red run exceeded ${TIMEOUT}s" >&2
  finish TIMEOUT 5
fi
if [[ "$RED_EXIT" -eq 0 ]]; then
  echo "${PROG}: the test passes at the red commit: it does not reproduce the bug" >&2
  finish DECOY 3
fi
if [[ "$RED_EXIT" -eq 126 || "$RED_EXIT" -eq 127 ]]; then
  echo "${PROG}: the red run exited ${RED_EXIT} (command not found or not executable): not an assertion failure" >&2
  finish NOT_A_RED 4
fi
# Strip once into a file: `strip | grep -q` under pipefail can turn a match into a miss.
strip < "${SCRATCH}/red.log" > "${SCRATCH}/red.clean"
for pat in "${NOT_A_RED_PATTERNS[@]}"; do
  if grep -qE -- "$pat" "${SCRATCH}/red.clean"; then
    echo "${PROG}: the red run failed by a non-assertion error (matched '${pat}'): fix the test so it loads, then re-check" >&2
    finish NOT_A_RED 4
  fi
done
if [[ "$GREEN_TO" -eq 1 ]]; then
  echo "${PROG}: the green run exceeded ${TIMEOUT}s" >&2
  finish TIMEOUT 5
fi
if [[ "$GREEN_EXIT" -ne 0 ]]; then
  echo "${PROG}: the test still fails at green ${GREEN_SHA}" >&2
  finish GREEN_FAILS 1
fi
finish VERIFIED 0
