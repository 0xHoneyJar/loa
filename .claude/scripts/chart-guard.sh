#!/usr/bin/env bash
# =============================================================================
# chart-guard.sh: the first step of every /chart invocation (charting-decisions skill).
#
# /chart is interactive only: a map whose destination and fog rounds the agent answered for
# itself is not a map (PRD Appendix E D12, SDD D-4.3 step 0). This guard asks the decision
# ledger writer for the context (`dec-write-lib.sh context`: a fresh unattended marker, a RUNNING
# run state, LOA_UNATTENDED=1, LOA_FLATLINE_MODE=autonomous or an autonomous PRD Status line) and
# refuses when it says `unattended`. It also refuses when `br` is missing, because a map lives on
# beads.
#
# Usage:
#   chart-guard.sh                    # chart or work a map
#   chart-guard.sh --close-consumed   # `/chart close <slug> --consumed-by <cycle>`: the one
#                                     # operation allowed unattended (SDD D-4.5)
#   chart-guard.sh --root DIR         # fixture tree: its prd.md feeds the PRD Status signal
# Exit: 0 go (prints `interactive`, or `unattended` with --close-consumed); 1 refused; 2 usage.
# =============================================================================
export LC_ALL=C
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
DW="${SCRIPT_DIR}/lib/dec-write-lib.sh"
CLOSE_CONSUMED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --close-consumed) CLOSE_CONSUMED=1; shift ;;
    --root) [[ -n "${2:-}" && -d "${2:-}" ]] || { echo "chart-guard: --root needs a directory" >&2; exit 2; }; ROOT="$(cd "$2" && pwd -P)"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "chart-guard: unknown argument '$1' (usage: chart-guard.sh [--close-consumed] [--root DIR])" >&2; exit 2 ;;
  esac
done

if [[ ! -x "$DW" ]]; then
  echo "chart-guard: refused: ${DW#"${ROOT}/"} is missing, so the context cannot be checked; /chart does not run without it." >&2
  exit 1
fi

# Fail closed: a context that cannot be read counts as unattended.
ctx="$("$DW" context --prd "${ROOT}/grimoires/loa/prd.md" 2>/dev/null | head -n 1)" || ctx="unknown"
case "$ctx" in
  interactive) ;;
  unattended)
    if [[ $CLOSE_CONSUMED -eq 0 ]]; then
      echo "/chart is interactive: a map whose rounds the agent answered is not a map. Run it with the operator present." >&2
      echo "chart-guard: refused (context: unattended; see why with: .claude/scripts/lib/dec-write-lib.sh context --why)" >&2
      exit 1
    fi ;;
  *)
    echo "chart-guard: refused: the context could not be read (dec-write-lib.sh context printed '${ctx}'); /chart treats that as unattended." >&2
    exit 1 ;;
esac

if ! command -v br >/dev/null 2>&1; then
  echo "chart-guard: refused: br (beads_rust) is not on PATH. A map is an epic of question beads; install br (.claude/scripts/beads/install-br.sh) or plan without a map with /plan." >&2
  exit 1
fi

echo "$ctx"
