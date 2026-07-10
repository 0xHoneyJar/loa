#!/usr/bin/env bash
# =============================================================================
# repo-map-gen.sh -- generate loa's own framework repo-map (cycle-116 D4)
#
# Sibling of agents-md-gen.sh / grimoire-index.sh. Emits a deterministic,
# stdlib-only LEXICAL symbol map (Aider-repo-map-style PageRank v1) of loa's
# framework code under .claude/ -- closing the semantic-retrieval gap named in
# grimoires/loa/proposals/okf-icm-comparative-analysis-2026-06-27.md:91.
# The heavy lifting is in .claude/scripts/lib/repo_map.py (pure stdlib).
#
# DETERMINISM CONTRACT: output is a pure function of the *.sh / *.py byte
#   contents under .claude/. No wall-clock timestamp / head_sha is emitted --
#   provenance is the generator name + an input CONTENT hash -- so the map
#   drifts ONLY when the mapped code changes, never on unrelated commits.
#   PYTHONHASHSEED=0 is a belt on top of the engine's sorted-list-iteration +
#   6-decimal-rounding suspenders (see repo_map.py's determinism contract).
#
# Modes:
#   (default)   write grimoires/loa/REPO-MAP.md + .checksum sidecar
#               + .run/repo-map.json (full per-symbol data)
#   --json      print the full JSON to stdout only (no writes; for bats/tooling)
#   --validate  regenerate to a tmpfile and diff vs the committed REPO-MAP.md;
#               exit 1 with a ::error:: annotation on drift, else exit 0
# =============================================================================
export LC_ALL=C
export TZ=UTC
export PYTHONHASHSEED=0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPT_VERSION="1.0.0"
source "${SCRIPT_DIR}/compat-lib.sh"

ENGINE="${SCRIPT_DIR}/lib/repo_map.py"
SCAN_SUBDIR=".claude"
OUT_MD="${PROJECT_ROOT}/grimoires/loa/REPO-MAP.md"
OUT_CHK="${OUT_MD}.checksum"
OUT_JSON="${PROJECT_ROOT}/.run/repo-map.json"

MODE="write"

usage() { sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)     MODE="json" ;;
      --validate) MODE="validate" ;;
      -h|--help)  usage; exit 0 ;;
      *) echo "repo-map-gen: unknown arg: $1" >&2; exit 2 ;;
    esac
    shift
  done
}

require_python() {
  command -v python3 >/dev/null 2>&1 || { echo "repo-map-gen: python3 required" >&2; exit 3; }
}

gen_md()   { python3 "${ENGINE}" --root "${PROJECT_ROOT}" --scan "${SCAN_SUBDIR}" --emit md; }
gen_json() { python3 "${ENGINE}" --root "${PROJECT_ROOT}" --scan "${SCAN_SUBDIR}" --emit json; }

# --- main ---
parse_args "$@"
require_python

case "${MODE}" in
  json)
    gen_json ;;
  validate)
    if [[ ! -f "${OUT_MD}" ]]; then
      echo "::error::[REPO-MAP-DRIFT] ${OUT_MD} missing -- run: bash .claude/scripts/repo-map-gen.sh" >&2
      exit 1
    fi
    TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
    gen_md > "$TMP"
    if ! diff -u "${OUT_MD}" "$TMP" >/dev/null 2>&1; then
      echo "::error::[REPO-MAP-DRIFT] REPO-MAP.md is stale vs .claude/ code. Regenerate: bash .claude/scripts/repo-map-gen.sh" >&2
      diff -u "${OUT_MD}" "$TMP" >&2 || true
      exit 1
    fi
    echo "repo-map: REPO-MAP.md consistent with .claude/ code." ;;
  write)
    mkdir -p "${PROJECT_ROOT}/.run"
    TMPM="$(mktemp)"; TMPJ="$(mktemp)"; trap 'rm -f "$TMPM" "$TMPJ"' EXIT
    gen_md   > "$TMPM"
    gen_json > "$TMPJ"
    mv "$TMPM" "${OUT_MD}"
    mv "$TMPJ" "${OUT_JSON}"
    sha256_portable "${OUT_MD}" | awk '{print $1}' > "${OUT_CHK}"
    trap - EXIT
    echo "repo-map: wrote ${OUT_MD#${PROJECT_ROOT}/} (+ $(basename "${OUT_CHK}")) + ${OUT_JSON#${PROJECT_ROOT}/}" ;;
esac
