#!/usr/bin/env bash
# =============================================================================
# tools/fresh-mount-proof.sh — cycle-130 FR-1 (#1267; SDD §5.4, AC-1.3)
#
# Proves that a FRESH downstream submodule mount of this repository passes
# `check-loa.sh` integrity: no Tampered, no Missing (paths the mount does not
# link by design are reported as not-mounted and do not fail).
#
# Steps, all inside a new temp directory (nothing outside it is written):
#   1. upstream/   — a `git clone` of this repository over file://, with a
#                    local branch `fresh-mount-proof` at REF. With --worktree
#                    the source work tree's uncommitted state (tracked edits,
#                    deletions and untracked non-ignored files) is copied in
#                    and committed on that branch, inside the temp clone only.
#   2. downstream/ — `git init`, one commit, then the downstream entry point
#                    `upstream/.claude/scripts/mount-submodule.sh --branch
#                    fresh-mount-proof --ref <sha> --force` with
#                    LOA_UPSTREAM=file://.../upstream (the mount clones the
#                    submodule from there; no network).
#   3. `aleph.enabled: false` is set in downstream/.loa.config.yaml.
#   4. `bash .claude/scripts/check-loa.sh` runs in downstream/; its full output
#      is printed, then a summary line
#        fresh-mount-proof: Tampered=T Missing=M not-mounted=N check-loa-rc=R
#
# Git runs hermetically: GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1,
# a fixed identity, protocol.file.allow=always (needed for a file:// submodule
# on git >= 2.38.1) and core.hooksPath pointed at an empty directory.
#
# Usage:
#   tools/fresh-mount-proof.sh [--ref REF] [--worktree] [--keep] [--tmp DIR]
#
# Options:
#   --ref REF    commit-ish of this repository to mount (default: HEAD of the
#                repository the script lives in)
#   --worktree   mount REF plus the source work tree's uncommitted state
#                (use before the change is committed)
#   --keep       keep the temp directory and print its path
#   --tmp DIR    parent directory for the temp directory (default: $TMPDIR or
#                /tmp)
#   -h, --help   this text
#
# Exit codes:
#   0    check-loa.sh exited 0 on the fresh mount
#   1    check-loa.sh exited non-zero (its output names the failures)
#   2    usage error
#   3    setup failed (clone, overlay, downstream init or the mount itself);
#        the failing step's output is printed
# =============================================================================
set -euo pipefail
export LC_ALL=C

usage() { sed -n '/^# Usage:/,/^# =====/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'; }
die2() { echo "fresh-mount-proof: $*" >&2; exit 2; }
die3() { echo "fresh-mount-proof: SETUP FAILED: $*" >&2; exit 3; }

REF=""
KEEP=0
WORKTREE=0
TMP_PARENT="${TMPDIR:-/tmp}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      [[ $# -ge 2 && -n "$2" ]] || die2 "--ref requires a commit-ish"
      REF="$2"; shift 2 ;;
    --tmp)
      [[ $# -ge 2 && -n "$2" ]] || die2 "--tmp requires a directory"
      TMP_PARENT="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --worktree) WORKTREE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die2 "unknown argument: $1 (see --help)" ;;
  esac
done
[[ -d "$TMP_PARENT" ]] || die2 "--tmp is not a directory: $TMP_PARENT"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SRC="$(git -C "$SELF_DIR" rev-parse --show-toplevel 2>/dev/null)" || die2 "script is not inside a git work tree"
[[ -n "$REF" ]] || REF="HEAD"
REF_SHA="$(git -C "$SRC" rev-parse --verify --quiet "${REF}^{commit}")" || die2 "not a commit in $SRC: $REF"

WORK="$(mktemp -d "${TMP_PARENT%/}/fresh-mount-proof.XXXXXX")"
cleanup() {
  if [[ $KEEP -eq 1 ]]; then
    echo "fresh-mount-proof: kept $WORK" >&2
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

# --- hermetic git ---------------------------------------------------------------
mkdir -p "$WORK/no-hooks"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
export GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1="$WORK/no-hooks"
export GIT_CONFIG_KEY_2=init.defaultBranch GIT_CONFIG_VALUE_2=main
export GIT_AUTHOR_NAME="fresh-mount-proof" GIT_AUTHOR_EMAIL="fresh-mount-proof@localhost"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
unset LOA_ALEPH_ENABLED

LOG="$WORK/step.log"
run_step() {  # run_step <description> <cmd...>; output to $LOG, printed on failure
  local desc="$1"; shift
  if ! "$@" > "$LOG" 2>&1; then
    cat "$LOG" >&2
    die3 "$desc"
  fi
}

suffix=""
[[ $WORKTREE -eq 1 ]] && suffix=" + work-tree state"
echo "fresh-mount-proof: source $SRC at ${REF_SHA}${suffix}"
echo "fresh-mount-proof: temp dir $WORK"

# --- 1. upstream clone ----------------------------------------------------------
UP="$WORK/upstream"
run_step "clone $SRC" git clone --quiet --no-checkout "file://$SRC" "$UP"
run_step "fetch $REF_SHA" git -C "$UP" fetch --quiet origin "$REF_SHA"
run_step "branch at $REF_SHA" git -C "$UP" checkout --quiet -B fresh-mount-proof "$REF_SHA"

overlay() {
  local p
  while IFS= read -r -d '' p; do
    if [[ -e "$SRC/$p" || -L "$SRC/$p" ]]; then
      [[ -d "$SRC/$p" && ! -L "$SRC/$p" ]] && continue   # gitlink / nested repo
      mkdir -p "$UP/$(dirname "$p")"
      rm -f "$UP/$p"
      cp -P "$SRC/$p" "$UP/$p"
    else
      rm -f "$UP/$p"
    fi
  done < <(git -C "$SRC" ls-files -z --cached --others --exclude-standard)
  git -C "$UP" add -A
  git -C "$UP" commit --quiet --allow-empty -m "fresh-mount-proof: work-tree state of $SRC"
}
[[ $WORKTREE -eq 1 ]] && run_step "work-tree overlay" overlay
MOUNT_SHA="$(git -C "$UP" rev-parse HEAD)"
echo "fresh-mount-proof: mounting upstream commit $MOUNT_SHA"

# --- 2. downstream repository and the submodule mount --------------------------
DOWN="$WORK/downstream"
mkdir -p "$DOWN"
init_downstream() {
  git -C "$DOWN" init --quiet
  printf '# downstream fixture\n' > "$DOWN/README.md"
  git -C "$DOWN" add README.md
  git -C "$DOWN" commit --quiet -m "initial commit"
}
run_step "downstream init" init_downstream

do_mount() {
  (cd "$DOWN" && LOA_UPSTREAM="file://$UP" bash "$UP/.claude/scripts/mount-submodule.sh" \
    --branch fresh-mount-proof --ref "$MOUNT_SHA" --force < /dev/null)
}
run_step "mount-submodule.sh" do_mount
echo "fresh-mount-proof: mount-submodule.sh exited 0 ($(grep -c 'Linked' "$LOG" || true) link lines)"

# --- 3. Aleph off ---------------------------------------------------------------
CFG="$DOWN/.loa.config.yaml"
[[ -f "$CFG" ]] || : > "$CFG"
if command -v yq >/dev/null 2>&1; then
  run_step "aleph.enabled: false" yq -i '.aleph.enabled = false' "$CFG"
else
  printf '\naleph:\n  enabled: false\n' >> "$CFG"
fi

# --- 4. check-loa.sh ------------------------------------------------------------
OUT="$WORK/check-loa.out"
rc=0
(cd "$DOWN" && CI=true bash .claude/scripts/check-loa.sh < /dev/null) > "$OUT" 2>&1 || rc=$?
echo "----- check-loa.sh (downstream) -----"
cat "$OUT"
echo "----- end check-loa.sh (exit $rc) -----"

tampered=$(grep -c 'Tampered: ' "$OUT" || true)
missing=$(grep -c 'Missing: ' "$OUT" || true)
not_mounted=$(sed -n 's/.*not-mounted: \([0-9][0-9]*\) path(s).*/\1/p' "$OUT")
echo "fresh-mount-proof: Tampered=${tampered} Missing=${missing} not-mounted=${not_mounted:-0} check-loa-rc=${rc}"
[[ $rc -eq 0 ]] && exit 0
exit 1
