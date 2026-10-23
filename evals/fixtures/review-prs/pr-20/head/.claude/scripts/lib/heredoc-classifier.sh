#!/usr/bin/env bash
# heredoc-classifier.sh — library entry points for the FR-6 heredoc consumer
# classifier (cycle-129 D-6.1). The single implementation lives in the fence,
# .claude/hooks/safety/block-destructive-bash.sh; this file sources it in
# library mode (BDB_LIB_ONLY=1, which the fence honours only when sourced) so
# other scripts — guard-yield.sh's likely-false-positive heuristic — can call:
#
#   heredoc_consumer_class <command text>   prints interpreter|nonexec|none
#   heredoc_nonexec <command text>          exit 0 iff the command's heredocs
#                                           all have non-executing consumers
#
# Source only; never execute. Bash 3.2 compatible. When the fence cannot be
# read the functions report "none" / exit 1, which callers treat as "no
# classifier" (guard-yield.sh falls back to `<<` presence).
_hc_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_hc_fence="${_hc_lib_dir}/../../hooks/safety/block-destructive-bash.sh"
if [[ -r "$_hc_fence" ]]; then
  # shellcheck source=/dev/null
  BDB_LIB_ONLY=1 source "$_hc_fence"
fi
unset _hc_lib_dir _hc_fence

heredoc_consumer_class() {
  if declare -F _bdb_heredoc_consumer_class >/dev/null 2>&1; then
    _bdb_heredoc_consumer_class "${1:-}"
  else
    printf 'none\n'
  fi
}

heredoc_nonexec() {
  [[ "$(heredoc_consumer_class "${1:-}")" == nonexec ]]
}
