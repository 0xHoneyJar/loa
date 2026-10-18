#!/usr/bin/env bash
# =============================================================================
# freeze.sh — cycle-130 ablation suite freeze (SDD §5.13, DEC-0404, DEC-0414)
#
# Writes or verifies <root>/MANIFEST.sha256, the suite's frozen identity: one
# "<sha256>  <relpath>" line per file under <root>/tasks/ (and <root>/smoke/
# with --smoke), relpath relative to the root, LC_ALL=C sorted, sha256 (Python
# hashlib: no harness script sources .claude/ code, eval.yml trust boundary).
# validate-suite.sh runs first; an invalid suite is never frozen or accepted.
#
# Usage:
#   freeze.sh [--root DIR] [--smoke] [--check] [--allow-partial] [--suite-file F]
#
#   --root DIR        suite root (default grimoires/loa/evals/ablation-2.0)
#   --smoke           cover smoke/ too (passed to the validator as well)
#   --check           recompute and compare with MANIFEST.sha256; write nothing
#   --allow-partial   passed to validate-suite.sh (fewer than four tasks per type)
#   --suite-file F    passed to validate-suite.sh
#
# Output: `freeze: wrote MANIFEST.sha256 (N files, sha256 <digest of the manifest>)`
# or `freeze: OK — N files match MANIFEST.sha256 (sha256 …)`; on drift every
# changed / added / removed path on its own line.
#
# A symlink, or a path holding a newline, under a covered directory is refused
# before hashing, for writes and --check alike (no manifest written):
#   freeze: refused — the suite holds a symlink: <relpath>
#   freeze: refused — the suite holds a path with a newline: <relpath, newline as \n>
#
# Exit: 0 written / matches; 1 drift, missing manifest under --check, the
#       validator found violations, or a symlink / newline path was refused; 2 usage.
# Tested by evals/tests/freeze.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ROOT="$REPO_ROOT/grimoires/loa/evals/ablation-2.0"
CHECK=false SMOKE=false
VARGS=()

usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,31p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "freeze: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --smoke) SMOKE=true; VARGS+=(--smoke); shift ;;
    --check) CHECK=true; shift ;;
    --allow-partial) VARGS+=(--allow-partial); shift ;;
    --suite-file) [[ -n "${2:-}" ]] || die "--suite-file needs a path"; VARGS+=(--suite-file "$2"); shift 2 ;;
    --help|-h) usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done
[[ -n "$ROOT" && -d "$ROOT" ]] || die "suite root not found: ${ROOT:-<empty>}"
ROOT="$(cd "$ROOT" && pwd)"
MANIFEST="$ROOT/MANIFEST.sha256"

vrc=0
"$SCRIPT_DIR/validate-suite.sh" --root "$ROOT" ${VARGS[@]+"${VARGS[@]}"} || vrc=$?
if [[ $vrc -eq 1 ]]; then echo "freeze: refused — the suite does not validate" >&2; exit 1; fi
[[ $vrc -eq 0 ]] || die "validate-suite.sh failed (exit $vrc)"

# compute_manifest <out> — the manifest body for the current tree.
compute_manifest() {
  local out="$1" list dirs=(tasks)
  [[ "$SMOKE" == "true" ]] && dirs+=(smoke)
  list="$(mktemp "${TMPDIR:-/tmp}/freeze-list.XXXXXX")"
  local d nl rel
  # A newline in a path would split one entry into two listing lines: refuse it
  # before listing (exit 1), naming the path with the newline shown as \n.
  for d in "${dirs[@]}"; do
    [[ -d "$ROOT/$d" ]] || continue
    nl="$(cd "$ROOT" && find "$d" -name "$(printf '*\n*')" -print -quit)"
    if [[ -n "$nl" ]]; then
      rm -f "$list"
      echo "freeze: refused — the suite holds a path with a newline: ${nl//$'\n'/\\n}" >&2
      exit 1
    fi
  done
  # Files and symlinks are listed; a symlink is refused (exit 1) before any hashing,
  # since a link target can change the suite while the manifest stays the same.
  for d in "${dirs[@]}"; do
    [[ -d "$ROOT/$d" ]] || continue
    ( cd "$ROOT" && find "$d" \( -type f -o -type l \) -print )
  done | LC_ALL=C sort > "$list"
  while IFS= read -r rel; do
    if [[ -L "$ROOT/$rel" ]]; then
      rm -f "$list"
      echo "freeze: refused — the suite holds a symlink: $rel" >&2
      exit 1
    fi
  done < "$list"
  if grep -q '\\' "$list"; then rm -f "$list"; die "a path under the suite holds a backslash"; fi
  python3 -I - "$ROOT" "$list" > "$out" <<'PY' || { rm -f "$list"; die "hashing failed"; }
import hashlib, os, sys
root, listing = sys.argv[1], sys.argv[2]
for rel in open(listing, encoding="utf-8").read().splitlines():
    if not rel:
        continue
    h = hashlib.sha256()
    with open(os.path.join(root, rel), "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    print(h.hexdigest() + "  " + rel)
PY
  rm -f "$list"
}
digest_of() { python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }

TMP="$(mktemp "${TMPDIR:-/tmp}/freeze.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
compute_manifest "$TMP"
n="$(grep -c . "$TMP" || true)"

if [[ "$CHECK" == "true" ]]; then
  [[ -f "$MANIFEST" ]] || { echo "freeze: no MANIFEST.sha256 in $ROOT (run freeze.sh first)" >&2; exit 1; }
  if cmp -s "$TMP" "$MANIFEST"; then
    echo "freeze: OK — $n files match MANIFEST.sha256 (sha256 $(digest_of "$MANIFEST"))"
    exit 0
  fi
  echo "freeze: DRIFT against $MANIFEST:"
  python3 -I - "$MANIFEST" "$TMP" <<'PY'
import sys
def load(p):
    m = {}
    for line in open(p, encoding="utf-8"):
        line = line.rstrip("\n")
        if line:
            h, _, rel = line.partition("  ")
            m[rel] = h
    return m
old, new = load(sys.argv[1]), load(sys.argv[2])
for rel in sorted(set(old) | set(new)):
    if rel not in new:
        print(f"  removed  {rel}")
    elif rel not in old:
        print(f"  added    {rel}")
    elif old[rel] != new[rel]:
        print(f"  changed  {rel}")
PY
  exit 1
fi

cp "$TMP" "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
echo "freeze: wrote MANIFEST.sha256 ($n files, sha256 $(digest_of "$MANIFEST"))"
exit 0
