#!/usr/bin/env bash
# =============================================================================
# fingerprint.sh — toolchain fingerprint for ablation runs (cycle-130 FR-4, SDD A11 / DEC-0389)
#
# Prints `fp:<sha256>` over the LC_ALL=C-sorted `tool=version` lines of the
# toolchain an ablation run depends on (claude, codex, python3, node, yq, jq,
# bats, git, docker) plus `source_tree=<HEAD of --source-tree>`. A tool that is
# not installed reads `tool=absent`, so a missing tool changes the fingerprint
# instead of failing the run. The value fills `image_digest` in host mode and
# `fingerprint` in every mode (MANIFEST.json, pipeline.json, runs.jsonl). It reads the
# HOST toolchain: in container mode the phases run on the image's toolchain, and the
# image digest (not this value) identifies the batch's versions (on 2026-10-15 the host
# CLI was 2.1.300 while Dockerfile.ablation pins 2.1.299).
#
# Usage:
#   fingerprint.sh [--source-tree DIR] [--claude-bin B] [--bats-bin B] [--json]
#
# Options:
#   --source-tree DIR  the pinned Loa tree; its `git rev-parse HEAD` is folded in
#                      (`none` when absent or not a git tree)
#   --claude-bin B     the CLI executable (default: $EVAL_CLAUDE_BIN, else claude)
#   --bats-bin B       bats executable (default: bats on PATH, else the operator's
#                      ~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats)
#   --json             print {fingerprint, tools{}, source_tree, lines[]} instead
#
# Exit codes:
#   0  printed
#   2  usage error
#
# Tested by evals/tests/pipeline-run.bats (fingerprint cases).
# =============================================================================
set -euo pipefail
export LC_ALL=C

# Hashing is Python hashlib: no harness script sources .claude/ code (eval.yml
# "Validate grader trust boundary").

SOURCE_TREE=""
CLAUDE_BIN="${EVAL_CLAUDE_BIN:-claude}"
BATS_BIN="${LOA_EVAL_BATS_BIN:-}"
JSON=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-tree) SOURCE_TREE="${2:?--source-tree needs a value}"; shift 2 ;;
    --claude-bin)  CLAUDE_BIN="${2:?--claude-bin needs a value}"; shift 2 ;;
    --bats-bin)    BATS_BIN="${2:?--bats-bin needs a value}"; shift 2 ;;
    --json)        JSON=true; shift ;;
    -h|--help)     sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "fingerprint.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$BATS_BIN" ]]; then
  if command -v bats >/dev/null 2>&1; then BATS_BIN=bats
  else BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"; fi
fi

# first line of `<bin> <args>`, whitespace collapsed; `absent` when not runnable
tool_version() {  # tool_version <bin> <args...>
  local bin="$1"; shift
  if ! command -v "$bin" >/dev/null 2>&1 && [[ ! -x "$bin" ]]; then printf 'absent'; return 0; fi
  local out
  out="$("$bin" "$@" 2>&1 < /dev/null || true)"
  out="$(printf '%s\n' "$out" | sed -n '1p' | tr -s ' \t' ' ' | sed 's/^ //; s/ $//')"
  [[ -n "$out" ]] || out="unknown"
  printf '%s' "$out"
}

lines="$(
  {
    printf 'claude=%s\n'  "$(tool_version "$CLAUDE_BIN" --version)"
    printf 'codex=%s\n'   "$(tool_version codex --version)"
    printf 'python3=%s\n' "$(tool_version python3 --version)"
    printf 'node=%s\n'    "$(tool_version node --version)"
    printf 'yq=%s\n'      "$(tool_version yq --version)"
    printf 'jq=%s\n'      "$(tool_version jq --version)"
    printf 'bats=%s\n'    "$(tool_version "$BATS_BIN" --version)"
    printf 'git=%s\n'     "$(tool_version git --version)"
    printf 'docker=%s\n'  "$(tool_version docker --version)"
  } | LC_ALL=C sort
)"
src="none"
if [[ -n "$SOURCE_TREE" ]]; then
  src="$(git -C "$SOURCE_TREE" rev-parse HEAD 2>/dev/null || echo none)"
fi
lines="$lines"$'\n'"source_tree=$src"
digest="$(printf '%s\n' "$lines" | python3 -I -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')"
fp="fp:$digest"

if [[ "$JSON" == true ]]; then
  printf '%s\n' "$lines" | jq -Rn --arg fp "$fp" --arg src "$src" '
    [inputs | select(length > 0)] as $l
    | {fingerprint: $fp, source_tree: $src, lines: $l,
       tools: ($l | map(select(startswith("source_tree=") | not) | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}) | add)}'
else
  printf '%s\n' "$fp"
fi
