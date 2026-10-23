#!/usr/bin/env bash
# =============================================================================
# tools/gen-checksums.sh — cycle-130 FR-1 (#1267; SDD §5.1, DEC-0368)
#
# Writes the System Zone integrity manifest `.claude/checksums.json` from the
# TRACKED `.claude/` tree only. The legacy generators (mount-loa.sh and
# update.sh `generate_checksums`) walk the working tree with `find`, so build,
# cache and runtime artefacts (`__pycache__`, `.pytest_cache`, `node_modules`,
# `.run/`) that exist only on the generating machine end up in the manifest and
# read as Missing on every fresh mount. This generator lists
#
#   git -C ROOT ls-files -z -- .claude
#
# minus every path under `.claude/overrides/` (user-owned) and minus the
# manifest itself (`.claude/checksums.json`), hashes each with
# `sha256_portable` (.claude/scripts/compat-lib.sh) and writes
#
#   {"generated": "<UTC ISO-8601>", "algorithm": "sha256",
#    "files": {"<path>": "<sha256 hex>", ...}}
#
# pretty-printed by jq (2-space), keys in `LC_ALL=C` byte order. Two runs on
# the same tree are byte-identical except `generated`. The working-tree content
# of each tracked path is hashed (an unstaged edit is reflected); a tracked
# path deleted from the working tree is skipped with a warning on stderr.
#
# Usage:
#   tools/gen-checksums.sh [--root DIR] [--out FILE]   # (re)generate
#   tools/gen-checksums.sh --check [--root DIR] [--out FILE]
#
# Options:
#   --root DIR   repository work tree to read (default: the git top level of
#                the current directory)
#   --out FILE   manifest path (default: ROOT/.claude/checksums.json). With
#                --check this is the committed manifest that is compared.
#   --check      regenerate to a temp file and compare its `files` map with
#                the manifest at --out; nothing is written
#   -h, --help   this text
#
# Exit codes:
#   0  generated, or --check: the `files` maps are identical
#   1  --check: drift (the first ten differing paths, each labelled added /
#      removed / changed, on stderr) or the manifest is absent / not JSON
#   2  usage error, ROOT is not a git work tree, or a tracked path name that
#      cannot be represented safely (newline, tab or backslash)
# =============================================================================
set -euo pipefail
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../.claude/scripts/compat-lib.sh
source "${SELF_DIR}/../.claude/scripts/compat-lib.sh"

usage() { sed -n '/^# Usage:/,/^# =====/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'; }
die2() { echo "gen-checksums: $*" >&2; exit 2; }

MANIFEST_REL=".claude/checksums.json"
ROOT=""
OUT=""
CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --root)
      [[ $# -ge 2 && -n "$2" ]] || die2 "--root requires a directory"
      ROOT="$2"; shift 2 ;;
    --out)
      [[ $# -ge 2 && -n "$2" ]] || die2 "--out requires a file path"
      OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die2 "unknown argument: $1 (see --help)" ;;
  esac
done

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die2 "not inside a git work tree (use --root DIR)"
fi
[[ -d "$ROOT" ]] || die2 "--root is not a directory: $ROOT"
ROOT="$(cd "$ROOT" && pwd -P)"
[[ "$(git -C "$ROOT" rev-parse --is-inside-work-tree 2>/dev/null || true)" == "true" ]] \
  || die2 "not a git work tree: $ROOT"
[[ -n "$OUT" ]] || OUT="${ROOT}/${MANIFEST_REL}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gen-checksums.XXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- 1. the tracked set (NUL-safe, C-sorted, overrides and manifest removed) --
files=()
while IFS= read -r -d '' path; do
  case "$path" in
    .claude/overrides/*|"$MANIFEST_REL") continue ;;
  esac
  case "$path" in
    *$'\n'*|*$'\t'*|*\\*) die2 "refusing a tracked path with a newline, tab or backslash: $(printf '%q' "$path")" ;;
  esac
  if [[ ! -f "${ROOT}/${path}" ]]; then
    # A gitlink, a dangling symlink or a path deleted in the working tree.
    echo "gen-checksums: warning: tracked path not a file in the working tree, skipped: $path" >&2
    continue
  fi
  files+=("$path")
done < <(git -C "$ROOT" ls-files -z -- .claude | sort -z)

# --- 2. hash in chunks (one sha256 process per 400 paths, order preserved) ----
TSV="${TMP_DIR}/files.tsv"
: > "$TSV"
n=${#files[@]}
i=0
while [[ $i -lt $n ]]; do
  chunk=("${files[@]:i:400}")
  hashes=()
  while IFS= read -r line; do
    hashes+=("${line%% *}")
  done < <(cd "$ROOT" && sha256_portable "${chunk[@]}")
  [[ ${#hashes[@]} -eq ${#chunk[@]} ]] || die2 "sha256 returned ${#hashes[@]} digests for ${#chunk[@]} paths"
  j=0
  while [[ $j -lt ${#chunk[@]} ]]; do
    [[ "${hashes[j]}" =~ ^[0-9a-f]{64}$ ]] || die2 "unexpected sha256 output for ${chunk[j]}"
    printf '%s\t%s\n' "${chunk[j]}" "${hashes[j]}" >> "$TSV"
    j=$((j + 1))
  done
  i=$((i + 400))
done
[[ $n -gt 0 ]] || echo "gen-checksums: warning: no tracked files under .claude in $ROOT" >&2

GEN="${TMP_DIR}/checksums.json"
jq -Rn --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  {generated: $generated, algorithm: "sha256",
   files: ([inputs | select(length > 0) | split("\t") | {key: .[0], value: .[1]}] | from_entries)}
' < "$TSV" > "$GEN"

# --- 3a. write ----------------------------------------------------------------
if [[ $CHECK -eq 0 ]]; then
  mkdir -p "$(dirname "$OUT")"
  chmod 0644 "$GEN"
  # mv replaces a symlinked manifest instead of writing through it.
  mv -f "$GEN" "$OUT"
  echo "gen-checksums: wrote $n entries to $OUT" >&2
  exit 0
fi

# --- 3b. --check --------------------------------------------------------------
if [[ ! -f "$OUT" ]]; then
  echo "gen-checksums: --check: manifest not found: $OUT (run tools/gen-checksums.sh)" >&2
  exit 1
fi
if ! jq -e '.files | type == "object"' "$OUT" >/dev/null 2>&1; then
  echo "gen-checksums: --check: manifest is not JSON with a files object: $OUT" >&2
  exit 1
fi
DIFF="${TMP_DIR}/diff.txt"
jq -rn --slurpfile old "$OUT" --slurpfile new "$GEN" '
  ($old[0].files) as $o | ($new[0].files) as $n |
  ( [ $n | keys[] | . as $p | select($o | has($p) | not) | {p: $p, k: "added"} ]
  + [ $o | keys[] | . as $p | select($n | has($p) | not) | {p: $p, k: "removed"} ]
  + [ $n | keys[] | . as $p | select(($o | has($p)) and $o[$p] != $n[$p]) | {p: $p, k: "changed"} ] )
  | sort_by(.p) | .[] | "\(.k): \(.p)"
' > "$DIFF"
count=$(wc -l < "$DIFF" | tr -d ' ')
if [[ "$count" -eq 0 ]]; then
  echo "gen-checksums: --check: OK ($n entries match $OUT)" >&2
  exit 0
fi
echo "gen-checksums: --check: DRIFT — $count path(s) differ between $OUT and the tracked tree:" >&2
sed -n '1,10s/^/  /p' "$DIFF" >&2
[[ "$count" -le 10 ]] || echo "  ... and $((count - 10)) more" >&2
echo "gen-checksums: regenerate with: bash tools/gen-checksums.sh" >&2
exit 1
